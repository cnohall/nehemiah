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
const COLORS      := [Color(0.80, 0.52, 0.22), Color(0.42, 0.50, 0.30)]   # amber, olive

var open := false
var _keys: Array = []
var _counts := [0, 0]
var _settled := 0.0
var _left := 0.0
var _poll := 0.0
var _rings: Array[Node3D] = []
var _labels: Array[Label3D] = []    # per ring: what it gives and costs (and who stands in it)
var _titles: Array[Label3D] = []
var _standards: Array[Node3D] = []

func _ready() -> void:
	add_to_group("yard_choice")
	GameState.section_changed.connect(func(_i):
		open = false
		_clear())

## Where ring `i` stands this stretch
static func ring_at(i: int) -> Vector3:
	var yard := GameState.yard_center()
	return Vector3(yard.x + (-RING_X if i == 0 else RING_X), 0.0, RING_Z)

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
		var title := _label(56, 0.014)
		title.text = tr(GameState.BOONS[keys[i]]["title"])
		title.modulate = COLORS[i].lightened(0.45)
		title.position = at + Vector3(0, 1.5, 0)
		add_child(title)
		_titles.append(title)
		var label := _label(34, 0.012)
		label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		label.position = at + Vector3(0, 1.1, 0)
		add_child(label)
		_labels.append(label)
	_show_counts(_counts, 0)

@rpc("authority", "call_local", "reliable")
func _show_counts(counts: Array, people: int) -> void:
	_counts = counts
	for i in _labels.size():
		var lines := GameState.boon_lines(_keys[i])
		var text: PackedStringArray = []
		for g: String in lines["gain"]:
			text.append("+ " + g)
		for c: String in lines["cost"]:
			text.append("- " + c)
		if people > 1 and counts[i] > 0:
			text.append("● ".repeat(counts[i]).strip_edges())
		_labels[i].text = "\n".join(text)

@rpc("authority", "call_local", "reliable")
func _chosen(pick: int) -> void:
	Sfx.play("horn")
	for i in _rings.size():
		var ring := _rings[i]
		var gone := ring.create_tween()
		gone.tween_property(ring, "scale", Vector3.ONE * (1.4 if i == pick else 0.2), 0.5).set_trans(Tween.TRANS_SINE)
		gone.tween_callback(ring.queue_free)
		_labels[i].queue_free()
		_titles[i].queue_free()
		if i != pick:
			var down := _standards[i].create_tween()
			down.tween_property(_standards[i], "scale", Vector3(1, 0.01, 1), 0.4)
			down.tween_callback(_standards[i].queue_free)
	_rings.clear()
	_labels.clear()
	_titles.clear()
	var keep: Node3D = _standards[pick] if pick < _standards.size() else null
	_standards.clear()
	if keep != null:
		_standards.append(keep)
	get_tree().call_group("watchmen", "call_choice", tr(GameState.BOONS[_keys[pick]]["title"]))

func _clear() -> void:
	for n in get_children():
		n.queue_free()
	_rings.clear()
	_labels.clear()
	_titles.clear()
	_standards.clear()

func _label(size: int, pixel := 0.012) -> Label3D:
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.pixel_size = pixel
	l.font_size = size
	l.outline_size = 12
	l.modulate = Color(0.98, 0.94, 0.82)
	l.outline_modulate = Color(0.16, 0.11, 0.08)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # put together translated
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
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
