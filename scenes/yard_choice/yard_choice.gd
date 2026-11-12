class_name YardChoice
extends Node3D

# The choice before a stretch, made in the yard (GDD §6.5, §5.28): at the stretch's first
# dawn two rings stand on the ground between the start and the wall, each with its
# standard and what it gives and costs. The crew walks into one. No card to read past, no
# vote to skip: the people standing there are the vote. It closes once every person has
# stood in a ring for a moment, or when the time runs out: most bodies win, the host's
# ring breaks a tie, nobody = the first. Bots don't vote. The chosen standard stays in the
# yard for the stretch, so the pick is seen, not only told.
# Server decides (DayDirector holds the dawn while it's open); every peer draws it.
# `-- --card-choice`: the old way, the last story card (GameState.yard_choice).

signal resolved(key: String)

const RING_RADIUS := 1.7
const RING_X      := 4.4     # each ring this far either side of the start spot (the crew starts within 1.3 m of it)
const RING_Z      := 6.6     # just wall-side of the start (z 8), clear of the Broad Wall's inner face
const SETTLE      := 1.5     # s every person must stand in a ring before it closes
const TIMEOUT     := 25.0
const POLL        := 0.15
const RING_ZS     := [6.6, 10.2, 11.4, 9.0, 12.2]    # tried in turn when the base spot is taken (YARD_BACK 13.5)
const RING_DX     := [0.0, 1.5, 3.0, -1.5, 4.5, 6.0, -3.0]  # outward from the start spot first
const COLORS      := [Color(0.80, 0.52, 0.22), Color(0.42, 0.50, 0.30)]   # amber, olive
const GAIN        := Color(0.98, 0.95, 0.89)   # cream on the dark plaque
const COST        := Color(0.94, 0.62, 0.48)   # warm terracotta, still bright on dark

var open := false
var _keys: Array = []
var _counts := [0, 0]
var _settled := 0.0
var _left := 0.0
var _poll := 0.0
var _spots: Array[Vector3] = []
var _rings: Array[Node3D] = []
var _tags: Array[WorldTag] = []     # per ring: a dark plaque, title + what it gives and costs
var _lines: Array[VBoxContainer] = []   # per ring: the gain/cost lines (and who stands in it)
var _standards: Array[Node3D] = []

func _ready() -> void:
	add_to_group("yard_choice")
	GameState.section_changed.connect(func(_i):
		open = false
		_clear())

## Where ring `i` stands this stretch (worked out when the choice opens)
func ring_at(i: int) -> Vector3:
	return _spots[i] if i < _spots.size() else _base_spot(i)

func _base_spot(i: int) -> Vector3:
	var yard := GameState.yard_center()
	return Vector3(yard.x + (-RING_X if i == 0 else RING_X), 0.0, RING_Z)

# The base spot, or the nearest clear one: some stretches put houses (Horse Gate's
# priests), piles or heaps there. Same terrain on every peer, so the same spots.
func _place_rings() -> void:
	_spots.clear()
	var terrain := get_node_or_null("../SectionTerrain")
	for i in 2:
		var base := _base_spot(i)
		var out := -1.0 if i == 0 else 1.0
		# First spot with room all round; failing that, the one with the most room
		var pick := base
		var best := -INF
		for z: float in RING_ZS:
			for dx: float in RING_DX:
				var p := Vector3(base.x + dx * out, 0.0, z)
				var room := _room(terrain, p, i)
				if room > best:
					best = room
					pick = p
				if room >= 0.0:
					break
			if best >= 0.0:
				break
		_spots.append(pick)

# Clearance (m) to the nearest thing a ring mustn't sit on: below 0 = crowded
func _room(terrain: Node, p: Vector3, i: int) -> float:
	var flat := Vector2(p.x, p.z)
	var room := INF
	if terrain != null:
		if terrain.blocks(flat, RING_RADIUS + 0.3):
			return -10.0   # inside a house or a wall: never, unless nothing else
		for k: Vector2 in terrain.keep_clear():   # piles carry jars and baskets round them
			room = minf(room, flat.distance_to(k) - (RING_RADIUS + 3.0))
		for prop: Array in terrain.props:   # jars, baskets: not solid, but clutter in a ring
			var at: Vector3 = prop[1]
			room = minf(room, flat.distance_to(Vector2(at.x, at.z)) - (RING_RADIUS + 0.3))
	if i == 1:   # never on top of the other ring
		room = minf(room, flat.distance_to(Vector2(_spots[0].x, _spots[0].z)) - RING_RADIUS * 2.6)
	return room

## Server: open the choice for the stretch starting now
func begin(keys: Array) -> void:
	_keys = keys.duplicate()
	_settled = 0.0
	_left = TIMEOUT
	_poll = 0.0
	open = true
	_show.rpc(_keys)

func _process(delta: float) -> void:
	if not open or not multiplayer.is_server():
		return
	_left -= delta
	_poll -= delta
	if _poll > 0.0 and _left > 0.0:
		return
	_poll = POLL
	var counts := [0, 0]
	var people := 0
	var host_in := -1
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_bot():
			continue
		people += 1
		for i in 2:
			var at := ring_at(i)
			if Vector2(p.global_position.x - at.x, p.global_position.z - at.z).length() <= RING_RADIUS:
				counts[i] += 1
				if int(p.name) == 1:
					host_in = i
	if counts != _counts:
		_counts = counts
		_show_counts.rpc(counts, people)
	var all_in: bool = people > 0 and counts[0] + counts[1] >= people
	_settled = _settled + POLL if all_in else 0.0
	if _settled >= SETTLE or _left <= 0.0:
		var pick := 0
		if counts[1] > counts[0] or (counts[1] == counts[0] and counts[0] > 0 and host_in == 1):
			pick = 1
		open = false
		GameState.set_boon(_keys[pick])
		_chosen.rpc(pick)
		resolved.emit(_keys[pick])

# ── Every peer: drawn ──────────────────────────────────────

@rpc("authority", "call_local", "reliable")
func _show(keys: Array) -> void:
	_clear()
	_keys = keys
	_place_rings()
	for i in 2:
		var at := ring_at(i)
		at.y = Terrain.height(at.x, at.z)
		var ring := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.orientation = PlaneMesh.FACE_Y
		quad.size = Vector2.ONE * RING_RADIUS * 2.3
		ring.mesh = quad
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://assets/shaders/ground_marker.gdshader")
		mat.set_shader_parameter("shadow_color", Color(COLORS[i], 0.16))
		mat.set_shader_parameter("ring_color", Color(COLORS[i], 0.95))
		mat.set_shader_parameter("ring_radius", 0.43)
		mat.set_shader_parameter("ring_width", 0.035)
		ring.material_override = mat
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.position = at + Vector3(0, 0.14, 0)   # the floor top is y 0.1
		add_child(ring)
		_rings.append(ring)
		var breathe := ring.create_tween().set_loops()
		breathe.tween_property(ring, "scale", Vector3.ONE * 1.05, 0.7).set_trans(Tween.TRANS_SINE)
		breathe.tween_property(ring, "scale", Vector3.ONE * 0.97, 0.7).set_trans(Tween.TRANS_SINE)
		var standard := _standard(COLORS[i], keys[i])
		standard.position = at + Vector3(0, 0, -RING_RADIUS + 0.2)
		add_child(standard)
		_standards.append(standard)
		# A dark plaque in screen space (like the pile/site tags): reads on any ground
		var body := VBoxContainer.new()
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_theme_constant_override("separation", 2)
		var title := _text(tr(GameState.BOONS[keys[i]]["title"]).to_upper(),
			UiStyle.tracked(UiStyle.CINZEL_BOLD, 2), 20, COLORS[i].lightened(0.4))
		body.add_child(title)
		var rule := ColorRect.new()
		rule.color = Color(UiStyle.GOLD, 0.35)
		rule.custom_minimum_size = Vector2(0, 1)
		body.add_child(rule)
		var lines := VBoxContainer.new()
		lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lines.add_theme_constant_override("separation", 0)
		body.add_child(lines)
		var tag := WorldTag.make(WorldTag.Kind.STATION)
		tag.custom = body
		tag.see_through_alpha = 0.8   # the choice has to stay readable; a worker still shows through
		# Over the standard (the ring's wall side): the crew comes from the start spot,
		# below it on screen, so a worker in the ring doesn't sit under it and fade it
		tag.position = standard.position + Vector3(0, 2.9, 0)
		add_child(tag)
		_tags.append(tag)
		_lines.append(lines)
	_show_counts(_counts, 0)

@rpc("authority", "call_local", "reliable")
func _show_counts(counts: Array, people: int) -> void:
	_counts = counts
	for i in _lines.size():
		var box := _lines[i]
		for c in box.get_children():
			c.free()
		var lines := GameState.boon_lines(_keys[i])
		for g: String in lines["gain"]:
			box.add_child(_text("+ " + g, UiStyle.SPECTRAL_MEDIUM, 17, GAIN))
		for c: String in lines["cost"]:
			box.add_child(_text("- " + c, UiStyle.SPECTRAL_MEDIUM, 17, COST))
		if people > 1 and counts[i] > 0:
			box.add_child(_text("● ".repeat(counts[i]).strip_edges(), UiStyle.WORLD_FONT, 16, WorldTag.TEXT))

@rpc("authority", "call_local", "reliable")
func _chosen(pick: int) -> void:
	Sfx.play("horn")
	for i in _rings.size():
		var ring := _rings[i]
		var gone := ring.create_tween()
		gone.tween_property(ring, "scale", Vector3.ONE * (1.4 if i == pick else 0.2), 0.5).set_trans(Tween.TRANS_SINE)
		gone.tween_callback(ring.queue_free)
		if i < _tags.size():
			_tags[i].queue_free()
		if i != pick:
			var down := _standards[i].create_tween()
			down.tween_property(_standards[i], "scale", Vector3(1, 0.01, 1), 0.4)
			down.tween_callback(_standards[i].queue_free)
	_rings.clear()
	_tags.clear()
	_lines.clear()
	var keep: Node3D = _standards[pick] if pick < _standards.size() else null
	_standards.clear()
	if keep != null:
		_standards.append(keep)
	get_tree().call_group("watchmen", "call_choice", tr(GameState.BOONS[_keys[pick]]["title"]))

func _clear() -> void:
	for n in get_children():
		n.queue_free()
	_rings.clear()
	_tags.clear()
	_lines.clear()
	_standards.clear()

func _text(t: String, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # put together translated
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("line_spacing", -4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# A pole with a cloth in the ring's colour; a work standard carries a mallet head on top,
# a watch standard a spear point
func _standard(cloth: Color, key: String) -> Node3D:
	var root := Node3D.new()
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.32, 0.2)
	var cloth_mat := StandardMaterial3D.new()
	cloth_mat.albedo_color = cloth
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.05
	pm.bottom_radius = 0.06
	pm.height = 2.6
	pole.mesh = pm
	pole.material_override = wood
	pole.position.y = 1.3
	root.add_child(pole)
	var flag := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.75, 0.95, 0.04)
	flag.mesh = fm
	flag.material_override = cloth_mat
	flag.position = Vector3(0.4, 2.0, 0)
	root.add_child(flag)
	var sway := flag.create_tween().set_loops()
	sway.tween_property(flag, "rotation:y", 0.18, 1.1).set_trans(Tween.TRANS_SINE)
	sway.tween_property(flag, "rotation:y", -0.12, 1.1).set_trans(Tween.TRANS_SINE)
	var top := MeshInstance3D.new()
	var watch: bool = GameState.BOONS[key].get("mods", {}).get("harm", 1.0) < 1.0
	if watch:
		var tip := PrismMesh.new()
		tip.size = Vector3(0.16, 0.36, 0.05)
		top.mesh = tip
		var bronze := StandardMaterial3D.new()
		bronze.albedo_color = Color(0.72, 0.52, 0.26)
		top.material_override = bronze
		top.position.y = 2.78
	else:
		var head := BoxMesh.new()
		head.size = Vector3(0.42, 0.2, 0.2)
		top.mesh = head
		top.material_override = wood
		top.position.y = 2.68
	root.add_child(top)
	return root
