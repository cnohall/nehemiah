extends ScatterLayer

# Landmarks around the work site, one set per section (GDD §6.1 "layout per section"):
# the sheepfold at the Sheep Gate, fish stalls, burned ruins, the Pool of Shelah, the
# priests' houses at the Horse Gate… Solid pieces block workers and enemies alike and
# shape how each stretch plays (the valley terraces funnel the enemy, the refuse heaps
# at the Dung Gate break the long haul into lanes, the houses at the Horse Gate cramp
# it). Also sets the ground's look for the section. Rebuilt on every peer from the
# section index alone (fixed seed per section); the DayDirector rebakes navigation at
# dawn, after this has run.
# Reuses ScatterLayer's primitives and batching; only the builders differ.

const WOOD       := Color(0.46, 0.34, 0.22)
const SOOT       := Color(0.24, 0.21, 0.19)
const FISH       := Color(0.62, 0.66, 0.68)
const WATER      := Color(0.20, 0.42, 0.46)
const FLAME      := Color(1.0, 0.62, 0.22)
const FLOWERS    := [Color(0.86, 0.30, 0.24), Color(0.95, 0.78, 0.30), Color(0.62, 0.36, 0.62)]
# Ground looks: scrub_bias (+ greener), tint + tint_amount, outside_shade (valley fall)
const GROUND_DEFAULT := { "scrub_bias": 0.0, "tint": Color(0.5, 0.5, 0.5), "tint_amount": 0.0, "outside_shade": 0.0, "feature": 0 }
## The ground shader's painted feature (ground.gdshader `feature`) for each landmark set
const GROUND_FEATURE := { "sheepfold": 7, "fish_market": 5, "ruins": 3, "workshops": 6, "ovens": 3, "valley": 1,
	"refuse": 3, "garden": 2, "ophel": 4, "priests": 4, "kidron": 1 }

# Solid pieces must leave these clear: the wall line and its working strip, and the
# enemy spawn line outside (WaveManager.SPAWN_Z)
const WALL_STRIP := Rect2(-23.0, -2.8, 46.0, 5.6)
const SPAWN_STRIP := Rect2(-20.0, -16.0, 40.0, 4.0)
const CLEARANCE := 1.2   # around piles, the trough, rubble heaps and the respawn point
const YARD_BACK := 13.5  # the lower city's first houses stand from z 14 (ScatterLayer.CITY)

signal rebuilt

var _body: StaticBody3D
var _built := -1
var _keep_clear: Array[Vector2] = []
var _camp: Array[Rect2] = []
## Debug builds: every landmark this section set down on the wall line, the spawn line,
## a worker spot or the work camp (tools/layout_test.gd reads it)
var crowded: Array[String] = []
## Where this section's landmarks set out breakable jars and baskets: [kind, position].
## Read by Breakables after `rebuilt`.
var props: Array = []

func _ready() -> void:
	GameState.section_changed.connect(_rebuild.unbind(1))
	_rebuild()

func _rebuild() -> void:
	var index := GameState.current_section_index
	if index == _built:
		return
	_built = index
	props.clear()
	crowded.clear()
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_batches.clear()
	_flock = null
	_rng.seed = 1000 + index
	_deco.seed = 2000 + index
	_body = StaticBody3D.new()
	_body.collision_mask = 0
	add_child(_body)
	_collect_keep_clear()
	_camp = work_camp_footprints(index)
	var ground := GROUND_DEFAULT.duplicate()
	ground["feature"] = GROUND_FEATURE.get(GameState.SECTIONS[index].get("terrain", ""), 0)
	match GameState.SECTIONS[index].get("terrain", ""):
		"sheepfold":
			_sheepfold(Vector3(-15.0, 0.0, -7.2))
			_first_map_olive()
		"fish_market": _fish_market()
		"ruins":       _ruins(ground)
		"workshops":   _workshops(ground)
		"ovens":       _ovens(ground)
		"valley":      _valley(ground)
		"refuse":      _refuse(ground)
		"garden":      _garden(ground)
		"ophel":       _ophel(ground)
		"priests":     _priests()
		"kidron":      _kidron(ground)
		"market":      _market()
	_flush()
	_apply_ground(ground)
	rebuilt.emit()

## Worker spots the section must leave clear (respawn point, piles, build sites, heaps)
func keep_clear() -> Array[Vector2]:
	return _keep_clear

## True if (x,z) `p` lies within `pad` of a solid landmark or the work camp
func blocks(p: Vector2, pad: float) -> bool:
	for r: Rect2 in _camp:
		if r.grow(pad).has_point(p):
			return true
	if _body == null:
		return false
	for shape: CollisionShape3D in _body.get_children():
		var half := (shape.shape as BoxShape3D).size * 0.5
		var local := shape.transform.affine_inverse() * Vector3(p.x, shape.transform.origin.y, p.y)
		if absf(local.x) < half.x + pad and absf(local.z) < half.z + pad:
			return true
	return false

func _prop(kind: String, at: Vector3) -> void:
	props.append([kind, Vector3(at.x, 0.0, at.z)])

# Everything a worker has to reach, as the SectionStage laid it out for this section
func _collect_keep_clear() -> void:
	_keep_clear.clear()
	_keep_clear.append(Vector2(0.0, 8.0))   # Player.RESPAWN_POS
	_keep_clear.append(GameState.yard_center() + Scribe.OFFSET)   # the scribe's desk
	for group: String in ["supply_piles", "build_sites"]:
		for n: Node3D in get_tree().get_nodes_in_group(group):
			if n.is_visible_in_tree() and absf(n.global_position.z) > 2.0:
				_keep_clear.append(Vector2(n.global_position.x, n.global_position.z))
	for parent: String in ["../Supplies", "../Rubble"]:
		for n in get_node(parent).get_children():
			if n.visible:
				_keep_clear.append(Vector2(n.position.x, n.position.z))

func _apply_ground(g: Dictionary) -> void:
	var mesh: MeshInstance3D = get_node_or_null("../Floor/Mesh")
	if mesh == null:
		return
	var mat := mesh.get_surface_override_material(0) as ShaderMaterial
	mat.set_shader_parameter("yard_center", GameState.yard_center())
	for key: String in ["scrub_bias", "tint_amount", "outside_shade"]:
		mat.set_shader_parameter(key, g[key])
	mat.set_shader_parameter("section_tint", g["tint"])
	mat.set_shader_parameter("feature", g["feature"])

# ── Pieces ────────────────────────────────────────────────────

# Solid box standing on the ground (visual + collision), `c` = footprint centre
func _solid(c: Vector3, size: Vector3, color: Color, yaw := 0.0) -> void:
	_add("block", Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(size), c + Vector3(0, size.y * 0.5, 0)), color)
	_collider(c, size, yaw)

func _collider(c: Vector3, size: Vector3, yaw := 0.0, check := true) -> void:
	if check:
		_check(Vector2(c.x, c.z), _footprint_half(size, yaw))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.transform = Transform3D(Basis(Vector3.UP, yaw), c + Vector3(0, size.y * 0.5, 0))
	_body.add_child(shape)

# Half extents of a yawed box's axis-aligned footprint
static func _footprint_half(size: Vector3, yaw: float) -> Vector2:
	var c := absf(cos(yaw))
	var s := absf(sin(yaw))
	return Vector2(size.x * c + size.z * s, size.x * s + size.z * c) * 0.5

# Debug aid: a piece that crowds the wall, the spawn line, something workers use or
# the work camp
func _check(p: Vector2, half: Vector2) -> void:
	if not OS.is_debug_build():
		return
	var box := Rect2(p - half, half * 2.0)
	if box.intersects(WALL_STRIP) or box.intersects(SPAWN_STRIP):
		_crowd(p, "the wall / spawn line")
	if box.end.y > YARD_BACK:
		_crowd(p, "the city's first houses")
	for k: Vector2 in _keep_clear:
		if box.grow(CLEARANCE).has_point(k):
			_crowd(p, str(k))
	for r: Rect2 in _camp:
		if box.intersects(r):
			_crowd(p, "the work camp at %s" % r.get_center())

func _crowd(p: Vector2, what: String) -> void:
	var line := "SectionTerrain (%s): piece at %s crowds %s" % [GameState.SECTIONS[_built]["name"], p, what]
	crowded.append(line)
	push_warning(line)

# Low dry-stone wall from a to b (sheepfolds, terraces), solid
func _drystone(a: Vector2, b: Vector2, height := 0.8, color := STONE_COLOR) -> void:
	var along := b - a
	var n := maxi(1, ceili(along.length() / 0.9))
	var yaw := -along.angle()
	for i in n:
		var t := (i + 0.5) / n
		var p := a + along * t
		var s := Vector3(along.length() / n * 1.05, height * _rng.randf_range(0.85, 1.1), 0.6)
		_add("block", Transform3D(Basis(Vector3.UP, yaw + _rng.randf_range(-0.05, 0.05)) * Basis.from_scale(s),
			Vector3(p.x, s.y * 0.5, p.y)), _vary(color, 0.07))
	var mid := (a + b) * 0.5
	_check(mid, _footprint_half(Vector3(along.length(), height, 0.6), yaw))
	_collider(Vector3(mid.x, 0, mid.y), Vector3(along.length(), height, 0.6), yaw, false)

# Market stall: four poles, a cloth roof, a table of goods. Solid table.
func _stall(c: Vector3, w: float, d: float, goods: String) -> void:
	var cloth: Color = AWNINGS[_rng.randi() % AWNINGS.size()]
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_add("trunk", Transform3D(Basis.from_scale(Vector3(0.5, 2.2, 0.5)), c + Vector3(sx * w * 0.45, 1.1, sz * d * 0.45)), _vary(WOOD, 0.04))
	_add("block", Transform3D(Basis(Vector3.RIGHT, 0.12) * Basis.from_scale(Vector3(w + 0.3, 0.06, d + 0.3)), c + Vector3(0, 2.25, 0)), cloth)
	_check(Vector2(c.x, c.z), Vector2(w + 0.3, d + 0.3) * 0.5)
	var table := Vector3(w * 0.85, 0.8, d * 0.6)
	_add("block", Transform3D(Basis.from_scale(table), c + Vector3(0, table.y * 0.5, 0)), _vary(WOOD, 0.03).lightened(0.05))
	_collider(c, table, 0.0, false)
	var top := c + Vector3(0, 0.83, 0)
	for i in 6:
		var at := top + Vector3(_rng.randf_range(-w * 0.35, w * 0.35), 0.05, _rng.randf_range(-d * 0.22, d * 0.22))
		match goods:
			"fish":
				_add("pebble", Transform3D(_yaw().scaled(Vector3(2.6, 0.8, 1.0)), at), _vary(FISH, 0.05))
			"jars":
				_add("jar", Transform3D(Basis.from_scale(Vector3.ONE * _rng.randf_range(0.6, 0.9)), at + Vector3(0, 0.15, 0)), _vary(CLAY_COLOR, 0.06))
			"metal":
				_add("pebble", Transform3D(_yaw().scaled(Vector3(1.2, 0.5, 1.2)), at), Color(0.86, 0.68, 0.30))
			_:
				_add("jar", Transform3D(Basis.from_scale(Vector3(1.1, 0.6, 1.1)), at + Vector3(0, 0.1, 0)), CLOTH_COLORS[_rng.randi() % CLOTH_COLORS.size()])
	# Stock that didn't fit on the table, set down beside the stall
	match goods:
		"jars":
			_prop("store", c + Vector3(w * 0.5 + 0.55, 0, 0.3))
			_prop("jar", c + Vector3(w * 0.5 + 0.5, 0, -0.45))
			_prop("jar", c + Vector3(-w * 0.5 - 0.5, 0, 0.1))
		"fish":
			_prop("basket", c + Vector3(-w * 0.5 - 0.55, 0, 0.2))

# Tree with a small solid trunk (the canopy is walked under)
func _tree(at: Vector3, myrtle := false) -> void:
	if myrtle:
		_myrtle(at, true)
	else:
		_olive(at)
	_collider(at, Vector3(0.5, 1.5, 0.5))
# A lone old olive beyond the Sheep Gate, west of the sheepfold and away from the
# hauling lanes. Its roots sit among the same limestone and dry grass as the slope.
func _first_map_olive() -> void:
	var at := Vector3(-22.0, 0.0, -8.5)
	var olive := OldOlive.new()
	olive.name = "OldOlive"
	olive.position = at
	olive.rotation.y = PI / 5.0
	add_child(olive)
	_collider(at, Vector3(1.0, 2.0, 1.0))
	for offset: Vector3 in [Vector3(-1.25, 0.18, 0.55), Vector3(1.05, 0.14, -0.6), Vector3(0.4, 0.12, 1.2)]:
		_add("boulder", Transform3D(_yaw().scaled(Vector3(0.7, 0.42, 0.55)), at + offset), _vary(ROCK_COLOR, 0.04))
	for offset: Vector3 in [Vector3(-1.5, 0, -0.5), Vector3(1.35, 0, 0.8), Vector3(0.65, 0, -1.45)]:
		_tuft(at + offset + Vector3(0, 0.1, 0))


## Torch on a pole — lit by DayLight when night falls (group "torches")
func _torch(at: Vector3) -> void:
	_add("trunk", Transform3D(Basis.from_scale(Vector3(0.6, 1.8, 0.6)), at + Vector3(0, 0.9, 0)), _vary(WOOD, 0.03).darkened(0.15))
	_add("drum", Transform3D(Basis.from_scale(Vector3(0.45, 0.2, 0.45)), at + Vector3(0, 1.85, 0)), Color(0.36, 0.28, 0.22))
	var torch := Node3D.new()
	torch.position = at + Vector3(0, 2.05, 0)
	torch.add_to_group("torches")
	add_child(torch)
	var flame := MeshInstance3D.new()
	flame.name = "Flame"
	flame.mesh = _sphere(0.16, 0.42, 8, 4)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = FLAME
	flame.material_override = mat
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.visible = false
	torch.add_child(flame)
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = Color(1.0, 0.72, 0.45)
	light.omni_range = 8.0
	light.omni_attenuation = 1.2
	light.light_energy = 0.0
	light.position.y = 0.3
	torch.add_child(light)
	_collider(at, Vector3(0.3, 2.0, 0.3))

# ── Sections ──────────────────────────────────────────────────

# Sheep Gate (3:1): a round dry-stone fold outside the wall, open to the south, sheep inside
func _sheepfold(c: Vector3) -> void:
	var r := 3.4
	var steps := 14
	for i in steps:
		var a0 := TAU * i / steps + PI * 0.5 + 0.35
		var a1 := TAU * (i + 1) / steps + PI * 0.5 + 0.35
		if i >= steps - 2:
			continue   # the opening, toward the wall
		_drystone(Vector2(c.x + cos(a0) * r, c.z + sin(a0) * r), Vector2(c.x + cos(a1) * r, c.z + sin(a1) * r), 0.7)
	# Leave daylight between their silhouettes at the game's camera angle.
	var flock := [
		[Vector3(-1.48, 0, -1.45), 0.15, "ewe"],
		[Vector3(1.42, 0, -1.35), -1.35, "ewe"],
		[Vector3(-1.47, 0, 1.1), -0.2, "ewe"],
		[Vector3(0.75, 0, 1.4), 2.85, "lamb"],
		[Vector3(1.9, 0, 1.15), -1.1, "lamb"],
	]
	# The flock keeps its rump and nose this far from the centre: inside the stone
	var pen_r := r - 0.3 - Flock.RADIUS - 0.05
	for i in flock.size():
		_sheep(c + flock[i][0], flock[i][1], flock[i][2], i + 1, true, c, pen_r)
	# A few strays grazing on the slope
	var strays := [Vector3(-8.5, 0, -9.5), Vector3(-5.5, 0, -10.4), Vector3(6.5, 0, -9.0)]
	for i in strays.size():
		_sheep(strays[i], _rng.randf() * TAU, "graze", i + 8)

# The blockout is deliberately complete without any small wool forms. +X faces forward.
# `detail = false` is used by the visual review tool to check the naked silhouette.
# Each sheep moves on its own (Flock): its body parts are merged into one mesh and its
# head parts into another (pivoting at the neck); legs and ears are posed by the Flock.
# `pen_r` > 0 keeps it inside the fold (centre `pen_c`); otherwise it strays near `c`.
func _sheep(c: Vector3, yaw: float, pose: String, style := 0, detail := true, pen_c := Vector3.ZERO, pen_r := 0.0) -> void:
	var size := (0.72 if pose == "lamb" else 1.0) * (1.0 + 0.025 * sin(style * 2.7))
	var coat := Color(0.88, 0.82, 0.71).lerp(Color(0.83, 0.75, 0.64), 0.1 + 0.08 * sin(style * 3.1))
	var face := Color(0.44, 0.29, 0.21).lerp(Color(0.51, 0.35, 0.25), 0.5 + 0.2 * sin(style * 1.7))
	var sheep_scale := Vector3(size, size * 1.32, size)
	var body: Array = []
	var head: Array = []
	var put := func(kind: String, at: Vector3, sc: Vector3, tint: Color, turn := Basis.IDENTITY) -> void:
		body.append([kind, Transform3D(turn * Basis.from_scale(sc * sheep_scale), at * sheep_scale), tint])
	put.call("sheep_torso", Vector3.ZERO, Vector3.ONE, coat)
	# Broad short tail belongs to the rump, rather than hanging below it.
	put.call("blob", Vector3(-0.79, 0.92, 0), Vector3(0.32, 0.28, 0.37), coat.darkened(0.015))
	var head_root := Flock.HEAD_ROOT
	var head_put := func(kind: String, at: Vector3, sc: Vector3, tint: Color, turn := Basis.IDENTITY) -> void:
		head.append([kind, Transform3D(turn * Basis.from_scale(sc * sheep_scale), (at - head_root) * sheep_scale), tint])
	head_put.call("sheep_neck", Vector3.ZERO, Vector3.ONE, coat)
	head_put.call("sheep_head", Vector3.ZERO, Vector3.ONE, face)
	for side: float in [-1.0, 1.0]:
		head_put.call("blob", Vector3(1.05, 1.17, side * 0.185), Vector3(0.055, 0.055, 0.03), Color(0.105, 0.07, 0.055))
		head_put.call("blob", Vector3(1.06, 1.185, side * 0.21), Vector3(0.016, 0.016, 0.012), Color(0.89, 0.76, 0.57))
	for side: float in [-1.0, 1.0]:
		head_put.call("blob", Vector3(1.45, 1.01, side * 0.087), Vector3(0.05, 0.032, 0.043), face.darkened(0.42))
	if detail:
		_sheep_fleece(put, head_put, coat, style)
	c.y = 0.0
	_sheep_flock().add_sheep(c, yaw, sheep_scale, _merge(body), _merge(head), face.darkened(0.09), face.darkened(0.045),
		0.08 * sin(style * 2.0), pose == "graze", pen_c, pen_r)

static var _part_meshes := {}
static var _flock_meshes: Array[Mesh] = []   # front leg, hind leg, ear
var _flock: Flock

# The section's Flock, made with its first sheep; added to the tree on _flush
func _sheep_flock() -> Flock:
	if _flock:
		return _flock
	if _flock_meshes.is_empty():
		# Leg and hooves in one: the leg takes the instance colour, the hooves keep near-black
		for kind: String in ["sheep_leg_front", "sheep_leg_hind"]:
			var parts := [[kind, Transform3D.IDENTITY, Color.WHITE]]
			for split: float in [-1.0, 1.0]:
				parts.append(["blob", Transform3D(Basis.from_scale(Vector3(0.24, 0.105, 0.11)), Vector3(0.07, 0.055, split * 0.063)), HOOF_ON_LEG])
			_flock_meshes.append(_merge(parts))
		_flock_meshes.append(_merge([["sheep_ear", Transform3D.IDENTITY, Color.WHITE]]))
	_flock = Flock.new()
	_flock.name = "Flock"
	_flock.setup(self, WALL_STRIP, _material_for("sheep_torso"), _flock_meshes[0], _flock_meshes[1], _flock_meshes[2], 3000 + maxi(_built, 0))
	return _flock

# Hoof colour as a share of the leg's (instance colours multiply the vertex colour)
const HOOF_ON_LEG := Color(0.45, 0.49, 0.58)

func _flush() -> void:
	super._flush()
	if _flock and _flock.get_parent() == null:
		add_child(_flock)

# Parts ([kind, transform, colour]) baked into one mesh with vertex colours: one draw
# call for a piece that moves on its own
func _merge(parts: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for part: Array in parts:
		if not _part_meshes.has(part[0]):
			_part_meshes[part[0]] = _mesh_for(part[0])
		var arrays: Array = (_part_meshes[part[0]] as Mesh).surface_get_arrays(0)
		var xf: Transform3D = part[1]
		var nb := xf.basis.inverse().transposed()
		var base := verts.size()
		var pv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in pv.size():
			verts.append(xf * pv[i])
			normals.append((nb * pn[i]).normalized())
			colors.append(part[2])
		if arrays[Mesh.ARRAY_INDEX] == null:
			for i in pv.size():
				indices.append(base + i)
		else:
			for i: int in arrays[Mesh.ARRAY_INDEX]:
				indices.append(base + i)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_COLOR] = colors
	out[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return mesh

# A single coat carries the silhouette. Broad rises are sculpted into its surface,
# so the wool stays connected without rows or seams between separate tufts.
func _sheep_fleece(put: Callable, head_put: Callable, coat: Color, style: int) -> void:
	put.call("sheep_coat_%d" % (style % 3), Vector3.ZERO, Vector3.ONE, coat)
	# A soft collar and short crown frame the face without covering it.
	head_put.call("sheep_wool", Vector3(0.65, 1.04, 0), Vector3(0.44, 0.34, 0.41), coat)
	head_put.call("sheep_wool", Vector3(0.82, 1.24, 0), Vector3(0.44, 0.15, 0.35), coat.lightened(0.01))

const SHEEP_TORSO := [
	[Vector3(-0.88, 0.76, 0), 0.01, 0.01, 0.01],
	[Vector3(-0.78, 0.76, 0), 0.25, 0.25, 0.25],
	[Vector3(-0.63, 0.75, 0), 0.36, 0.34, 0.37],
	[Vector3(-0.36, 0.74, 0), 0.42, 0.38, 0.44],
	[Vector3(-0.04, 0.74, 0), 0.43, 0.39, 0.47],
	[Vector3(0.25, 0.75, 0), 0.43, 0.4, 0.46],
	[Vector3(0.51, 0.78, 0), 0.37, 0.37, 0.39],
	[Vector3(0.67, 0.82, 0), 0.25, 0.28, 0.27],
	[Vector3(0.73, 0.84, 0), 0.01, 0.01, 0.01],
]
const SHEEP_COAT := [
	[Vector3(-0.91, 0.79, 0), 0.01, 0.01, 0.01],
	[Vector3(-0.79, 0.78, 0), 0.27, 0.27, 0.27],
	[Vector3(-0.6, 0.76, 0), 0.39, 0.37, 0.4],
	[Vector3(-0.3, 0.75, 0), 0.46, 0.4, 0.48],
	[Vector3(0.05, 0.75, 0), 0.47, 0.42, 0.51],
	[Vector3(0.35, 0.77, 0), 0.46, 0.42, 0.49],
	[Vector3(0.58, 0.81, 0), 0.35, 0.35, 0.39],
	[Vector3(0.73, 0.85, 0), 0.01, 0.01, 0.01],
]
const SHEEP_NECK := [
	[Vector3(0.43, 0.74, 0), 0.17, 0.22, 0.24],
	[Vector3(0.59, 0.85, 0), 0.19, 0.2, 0.22],
	[Vector3(0.7, 1.02, 0), 0.17, 0.18, 0.18],
	[Vector3(0.79, 1.15, 0), 0.13, 0.13, 0.16],
	[Vector3(0.82, 1.24, 0), 0.01, 0.01, 0.01],
]
const SHEEP_HEAD := [
	[Vector3(0.76, 1.11, 0), 0.01, 0.01, 0.01],
	[Vector3(0.82, 1.13, 0), 0.15, 0.16, 0.16],
	[Vector3(0.96, 1.11, 0), 0.21, 0.2, 0.21],
	[Vector3(1.11, 1.08, 0), 0.19, 0.19, 0.19],
	[Vector3(1.25, 1.05, 0), 0.17, 0.18, 0.17],
	[Vector3(1.38, 1.02, 0), 0.14, 0.14, 0.145],
	[Vector3(1.46, 1.01, 0), 0.115, 0.11, 0.13],
	[Vector3(1.5, 1.01, 0), 0.01, 0.01, 0.01],
]

static var _sheep_material: ShaderMaterial

func _material_for(kind: String) -> Material:
	if kind.begins_with("sheep_"):
		if _sheep_material == null:
			_sheep_material = Chunky.material(0.0, false, 0.0).duplicate() as ShaderMaterial
			_sheep_material.set_shader_parameter("grain", 0.0)
			_sheep_material.set_shader_parameter("top_light", 0.02)
			_sheep_material.set_shader_parameter("ground_ao", 0.08)
		return _sheep_material
	return super._material_for(kind)

func _mesh_for(kind: String) -> Mesh:
	match kind:
		"sheep_torso": return _loft(_resample(SHEEP_TORSO, 3))
		"sheep_wool": return _sphere(0.5, 1.0, 12, 5)
		"sheep_neck": return _loft(_resample(SHEEP_NECK, 3))
		"sheep_head": return _loft(_resample(SHEEP_HEAD, 3))
		"sheep_ear": return _sheep_ear_mesh()
		"sheep_leg_front": return _sheep_leg_mesh(false)
		"sheep_leg_hind": return _sheep_leg_mesh(true)
	if kind.begins_with("sheep_coat_"):
		return _sheep_coat_mesh(int(kind.get_slice("_", 2)))
	return super._mesh_for(kind)

static func _sheep_leg_mesh(hind: bool) -> ArrayMesh:
	var bend := -0.055 if hind else 0.01
	return _loft(_resample([
		[Vector3(0.025, 0.045, 0), 0.07, 0.08, 0.085],
		[Vector3(0.0, 0.16, 0), 0.072, 0.075, 0.08],
		[Vector3(bend, 0.33, 0), 0.09, 0.095, 0.09],
		[Vector3(bend - 0.035, 0.5, 0), 0.14, 0.14, 0.12],
		[Vector3(bend - 0.035, 0.65, 0), 0.14, 0.14, 0.13],
	], 2), [[0.0, TAU]], 0.0, 0.0, 10)

static func _sheep_coat_mesh(variant: int) -> ArrayMesh:
	# A handful of broad overlapping rises are sculpted directly into one surface.
	# Variants shift them slightly without adding bead-like pieces or extra draw calls.
	var rings := _resample(SHEEP_COAT, 3)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEG := 20
	for i in rings.size():
		var r: Array = rings[i]
		var x: float = r[0].x
		var tangent: Vector3 = (rings[mini(i + 1, rings.size() - 1)][0] - rings[maxi(i - 1, 0)][0]).normalized()
		var up := Vector3(-tangent.y, tangent.x, 0)
		var envelope := minf(1.0, (x + 0.91) * 6.0) * minf(1.0, (0.73 - x) * 6.0)
		for j in SEG:
			var a := TAU * j / SEG
			var wave := (0.014 * sin(x * 9.0 + a * 3.0) + 0.009 * cos(x * 5.0 - a * 4.0)) * maxf(envelope, 0.0)
			for lobe: Vector4 in [
				Vector4(-0.52 + 0.03 * variant, 1.18, 0.09, 0.3),
				Vector4(0.12 - 0.02 * variant, 1.75, 0.078, 0.34),
				Vector4(0.42, 0.3 + 0.08 * variant, 0.056, 0.28),
				Vector4(-0.3, PI + 0.1 * variant, 0.063, 0.32),
			]:
				var da := atan2(sin(a - lobe.y), cos(a - lobe.y))
				wave += lobe.z * exp(-0.5 * (pow((x - lobe.x) / lobe.w, 2.0) + pow(da / 0.62, 2.0))) * maxf(envelope, 0.0)
			var h: float = r[1] if sin(a) > 0.0 else r[2]
			st.add_vertex(r[0] + up * sin(a) * (h + wave) + Vector3.BACK * cos(a) * (r[3] + wave))
	for i in rings.size() - 1:
		for j in SEG:
			var a := i * SEG + j
			var b := i * SEG + (j + 1) % SEG
			for idx: int in [a, b + SEG, a + SEG, a, b, b + SEG]:
				st.add_index(idx)
	st.generate_normals()
	return st.commit()

static func _sheep_ear_mesh() -> ArrayMesh:
	var rings := [
		[Vector3(0.0, 0.0, 0.0), 0.055, 0.03],
		[Vector3(-0.035, -0.015, 0.11), 0.12, 0.045],
		[Vector3(-0.09, -0.045, 0.28), 0.145, 0.042],
		[Vector3(-0.15, -0.085, 0.43), 0.08, 0.03],
		[Vector3(-0.17, -0.1, 0.48), 0.005, 0.005],
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring: Array in rings:
		for j in 10:
			var a := TAU * j / 10.0
			st.add_vertex(ring[0] + Vector3(cos(a) * ring[1], sin(a) * ring[2], 0))
	for i in rings.size() - 1:
		for j in 10:
			var a := i * 10 + j
			var b := i * 10 + (j + 1) % 10
			for idx: int in [a, a + 10, b, b, a + 10, b + 10]:
				st.add_index(idx)
	st.generate_normals()
	return st.commit()


# Fish Gate (3:3): Tyrian fish sellers' stalls inside the gate (Neh. 13:16)
func _fish_market() -> void:
	_stall(Vector3(10.5, 0, 5.8), 3.0, 2.2, "fish")
	_stall(Vector3(15.5, 0, 6.2), 3.0, 2.2, "fish")
	_stall(Vector3(13.0, 0, 10.2), 3.2, 2.2, "jars")
	for p: Vector3 in [Vector3(8.4, 0, 8.2), Vector3(17.0, 0, 11.6)]:
		_prop("basket", p)
		_prop("basket", p + Vector3(0.7, 0, 0.35))

const REED_COLOR := Color(0.58, 0.47, 0.28)

# Jeshanah Gate (3:6): burned house shells with charred beams (Neh. 1:3, 2:13)
func _ruins(g: Dictionary) -> void:
	g["tint"] = Color(0.42, 0.37, 0.33)
	g["tint_amount"] = 0.16
	for c: Vector3 in [Vector3(-9.5, 0, 9.0), Vector3(15.5, 0, 10.0), Vector3(4.0, 0, 6.2), Vector3(-18.0, 0, -7.5)]:
		var w := _rng.randf_range(3.2, 4.2)
		var d := _rng.randf_range(2.6, 3.2)
		var tint := _vary(HOUSE_COLORS[0], 0.03).lerp(SOOT, 0.35)
		# Three broken walls, the fourth fallen
		_solid(c + Vector3(0, 0, -d * 0.5), Vector3(w, _rng.randf_range(0.9, 1.6), 0.35), tint)
		_solid(c + Vector3(-w * 0.5, 0, 0), Vector3(0.35, _rng.randf_range(0.7, 1.3), d), tint.darkened(0.05))
		_solid(c + Vector3(w * 0.5, 0, 0), Vector3(0.35, _rng.randf_range(0.5, 1.1), d * 0.6), tint.darkened(0.1))
		for i in 3:
			var tilt := Basis.from_euler(Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf() * TAU, _rng.randf_range(0.2, 0.5)))
			_add("block", Transform3D(tilt * Basis.from_scale(Vector3(2.4, 0.18, 0.18)), c + Vector3(_rng.randf_range(-1, 1), 0.35, _rng.randf_range(-0.8, 0.8))), SOOT)
		_add("patch", Transform3D(Basis.from_scale(Vector3(w * 0.9, 1, d * 0.9)), c + Vector3(0, 0.11, 0)), SOOT.lightened(0.1))

# Broad Wall (3:8): goldsmiths' forge and the ointment makers' stall, the ground left open
func _workshops(g: Dictionary) -> void:
	g["scrub_bias"] = -0.06
	var forge := Vector3(-15.5, 0, 6.5)
	_add("drum", Transform3D(Basis.from_scale(Vector3(1.6, 1.1, 1.6)), forge + Vector3(0, 0.55, 0)), _vary(CLAY_COLOR, 0.04))
	_add("drum", Transform3D(Basis.from_scale(Vector3(0.7, 0.05, 0.7)), forge + Vector3(0, 1.11, 0)), Color(0.95, 0.45, 0.15))
	_collider(forge, Vector3(1.6, 1.1, 1.6))
	_solid(forge + Vector3(1.8, 0, 0.4), Vector3(0.6, 0.6, 0.4), Color(0.30, 0.28, 0.27))   # anvil stone
	_smoke(forge + Vector3(0, 1.2, 0), true)
	_stall(Vector3(17.5, 0, 6.5), 3.0, 2.2, "jars")
	_stall(Vector3(-14.5, 0, 11.0), 2.8, 2.0, "metal")

# Tower of Ovens (3:11): domed clay bread ovens and firewood, smoke going up
func _ovens(g: Dictionary) -> void:
	g["tint"] = Color(0.66, 0.42, 0.30)
	g["tint_amount"] = 0.08
	for c: Vector3 in [Vector3(-9.5, 0, 6.0), Vector3(-14.5, 0, 8.8), Vector3(-17.0, 0, 4.6)]:
		_add("leaf", Transform3D(Basis.from_scale(Vector3(1.8, 1.7, 1.8)), c + Vector3(0, 0.4, 0)), _vary(CLAY_COLOR, 0.04).lightened(0.1))
		_add("opening", Transform3D(Basis.from_scale(Vector3(0.5, 0.45, 0.06)), c + Vector3(0, 0.35, 0.86)), Color(0.9, 0.42, 0.14))
		_collider(c, Vector3(1.8, 1.4, 1.8))
		_smoke(c + Vector3(0, 1.3, 0))
		_prop("basket", c + Vector3(-1.5, 0, 0.9))   # figs set out beside the baking
		var wood := c + Vector3(1.8, 0, 0.6)
		_check(Vector2(wood.x, wood.z), Vector2(0.4, 0.6))
		for i in 5:
			_add("trunk", Transform3D(Basis(Vector3.RIGHT, PI / 2) * Basis.from_scale(Vector3(0.7, 1.1, 0.7)), wood + Vector3(0, 0.1 + (i % 2) * 0.16, (i - 2) * 0.17)), _vary(WOOD, 0.05))

# Valley Gate (3:13): the ground falls into the valley; stone terraces with two gaps
# funnel the enemy into surges (and give the sling a line to hold)
func _valley(g: Dictionary) -> void:
	g["outside_shade"] = 0.65
	g["scrub_bias"] = 0.04
	_drystone(Vector2(-26.0, -8.0), Vector2(-8.0, -8.0), 0.9)
	_drystone(Vector2(-1.0, -8.5), Vector2(10.0, -8.5), 0.9)
	_drystone(Vector2(14.0, -8.0), Vector2(26.0, -8.0), 0.9)
	for x: float in [-22.0, -17.0, -12.0, 3.0, 7.0, 18.0, 23.0]:
		_olive(Vector3(x + _rng.randf_range(-0.8, 0.8), 0, -10.5 + _rng.randf_range(-0.4, 0.4)))

# Dung Gate (3:14): the site is far from the yard; refuse heaps along the way split the
# haul into lanes. The Hinnom valley smoulders outside.
func _refuse(g: Dictionary) -> void:
	g["tint"] = Color(0.45, 0.40, 0.35)
	g["tint_amount"] = 0.12
	g["outside_shade"] = 0.4
	for c: Vector3 in [Vector3(10.0, 0, 6.5), Vector3(14.5, 0, 10.5), Vector3(18.5, 0, 5.0), Vector3(25.0, 0, 12.0)]:
		var s := Vector3(_rng.randf_range(2.6, 3.2), _rng.randf_range(0.9, 1.2), _rng.randf_range(2.2, 2.8))
		_add("boulder", Transform3D(_yaw().scaled(s * Vector3(0.95, 1.0, 0.95)), c + Vector3(0, 0.1, 0)), _vary(Color(0.42, 0.36, 0.30), 0.04))
		for i in 6:   # potsherds
			_add("pebble", Transform3D(_yaw().scaled(Vector3(1.6, 0.4, 1.2)), c + Vector3(_rng.randf_range(-1.6, 1.6), 0.08, _rng.randf_range(-1.4, 1.4))), _vary(CLAY_COLOR, 0.06))
		_collider(c, Vector3(s.x * 0.95, 1.0, s.z * 0.95))
	_smoke(Vector3(4.0, 0.5, -10.0), true)
	_smoke(Vector3(-12.0, 0.5, -11.0), true)

# Fountain Gate (3:15): the Pool of Shelah and the King's Garden — a quiet, green stretch
func _garden(g: Dictionary) -> void:
	g["scrub_bias"] = 0.12
	g["tint"] = Color(0.46, 0.58, 0.30)
	g["tint_amount"] = 0.1
	var pool := Vector3(-18.0, 0, 6.5)   # on the work camp cart's ground (CAMP_GIVES_WAY)
	var pw := 7.0
	var pd := 4.0   # between the watchmen's lookout and the cistern
	# Stone rim around dark water
	_solid(pool + Vector3(0, 0, -pd * 0.5), Vector3(pw, 0.45, 0.5), STONE_COLOR)
	_solid(pool + Vector3(0, 0, pd * 0.5), Vector3(pw, 0.45, 0.5), STONE_COLOR)
	_solid(pool + Vector3(-pw * 0.5, 0, 0), Vector3(0.5, 0.45, pd), STONE_COLOR)
	_solid(pool + Vector3(pw * 0.5, 0, 0), Vector3(0.5, 0.45, pd), STONE_COLOR)
	_collider(pool, Vector3(pw - 0.5, 0.3, pd - 0.5))
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(pw - 0.5, pd - 0.5)
	water.mesh = plane
	water.material_override = water_material()
	water.position = pool + Vector3(0, 0.3, 0)
	add_child(water)
	# Water jars left by the pool steps, and by the far rim
	for off: Vector3 in [Vector3(pw * 0.5 + 0.8, 0, 1.9), Vector3(pw * 0.5 + 1.5, 0, 2.2), Vector3(pw * 0.5 + 2.6, 0, 1.8),
			Vector3(-pw * 0.5 - 0.7, 0, -1.2), Vector3(-pw * 0.5 - 0.7, 0, -0.5)]:
		_prop("jar", pool + off)
	# Stairs going down from the City of David (3:15), beside the pool
	for i in 5:
		_add("slab", Transform3D(Basis.from_scale(Vector3(2.4, 0.12, 0.5)), pool + Vector3(pw * 0.5 + 1.6, 0.06 + (4 - i) * 0.02, -1.0 + i * 0.5)), _vary(PAVING_COLOR, 0.03))
	# The King's Garden: olives and flowering myrtle, with palms near the water.
	for xi in 4:
		for zi in 2:
			var x := 7.5 + xi * 3.3   # the last column clear of the carpenters' bench
			var z := 6.0 + zi * 4.0
			_tree(Vector3(x + _rng.randf_range(-0.4, 0.4), 0, z + _rng.randf_range(-0.3, 0.3)), (xi + zi) % 2 == 0)
	for p: Vector3 in [Vector3(-23.0, 0, 8.0), Vector3(5.0, 0, 10.5)]:
		_date_palm(p)
		_collider(p, Vector3(0.55, 3.8, 0.55))
	for p: Vector3 in [Vector3(6.5, 0, 5.0), Vector3(12.0, 0, 13.0), Vector3(19.5, 0, 13.0)]:
		_myrtle(p)
	for i in 14:
		var at := Vector3(_rng.randf_range(8.0, 22.0), 0.15, _rng.randf_range(7.4, 8.6))
		_add("pebble", Transform3D(_yaw().scaled(Vector3(1.4, 1.4, 1.4)), at), FLOWERS[_rng.randi() % FLOWERS.size()])
	for p: Vector3 in [Vector3(-12.0, 0, -7.0), Vector3(-6.0, 0, -9.0), Vector3(8.0, 0, -8.0), Vector3(14.0, 0, -10.0)]:
		_tree(p, true)

# Water Gate (3:26): the Ophel slope — torches for the night watch (Neh. 4:22), boulders outside
func _ophel(g: Dictionary) -> void:
	g["outside_shade"] = 0.45
	for x: float in [-17.0, -10.5, -0.5, 10.0, 16.5]:
		_torch(Vector3(x, 0, 3.6))
	for p: Vector3 in [Vector3(-11.0, 0, 9.5), Vector3(16.5, 0, 9.5), Vector3(-10.0, 0, -4.2), Vector3(4.0, 0, -4.2), Vector3(14.0, 0, -4.2)]:
		_torch(p)
	for c: Vector3 in [Vector3(-16.0, 0, -8.0), Vector3(9.0, 0, -9.0), Vector3(21.0, 0, -7.0)]:
		for i in 3:
			var s := Vector3(_rng.randf_range(1.2, 1.9), _rng.randf_range(0.7, 1.2), _rng.randf_range(1.1, 1.7))
			_add("boulder", Transform3D(_yaw().scaled(s), c + Vector3(_rng.randf_range(-1.0, 1.0), s.y * 0.3, _rng.randf_range(-0.8, 0.8))), _vary(ROCK_COLOR, 0.05).lightened(0.05))
		_collider(c, Vector3(2.6, 1.2, 2.2))

# Horse Gate (3:28): "each one in front of his own house" — a row of priests' houses
# between the wall and the yard, narrow lanes between them
func _priests() -> void:
	# x spans; the lane at the gate (x ≈ -4) and the one at the respawn point stay open,
	# and the ends are left to the work camp's cart and the watchmen's lookouts
	var spans := [Vector2(-16.4, -12.0), Vector2(-10.2, -6.4),
		Vector2(1.6, 5.6), Vector2(7.4, 11.6), Vector2(13.4, 17.6)]
	for span: Vector2 in spans:
		var w := span.y - span.x
		var d := _rng.randf_range(3.2, 3.6)
		var c := Vector3((span.x + span.y) * 0.5, 0, 4.4 + d * 0.5)
		_low_house(c, w, d)

# Single-storey house kept low so it doesn't hide the wall from the camera
func _low_house(c: Vector3, w: float, d: float) -> void:
	var h := _rng.randf_range(1.6, 2.0)
	var tint := _vary(HOUSE_COLORS[_rng.randi() % HOUSE_COLORS.size()], 0.02)
	_solid(c, Vector3(w, h, d), tint)
	_roof(c, w, d, h, tint)
	_dress_walls(c, w, h, d)
	_plaster(c, w, h, d, tint)
	# Door toward the wall — "in front of his own house"
	var door := c + Vector3(_rng.randf_range(-w * 0.2, w * 0.2), 0, -d * 0.5)
	_door(door, -1.0)
	_prop("jar", door + Vector3(0.75, 0, -0.45))   # a water jar by the step
	if _rng.randf() < 0.6:
		var rug := c + Vector3(_rng.randf_range(-w * 0.2, w * 0.2), h + 0.1, 0)
		_rug(rug, minf(w * 0.5, 1.8), 1.2, _yaw_small(), CLOTH_COLORS[_rng.randi() % CLOTH_COLORS.size()])

# East Gate (3:29): across the Kidron, the olive trees of the Mount of Olives
func _kidron(g: Dictionary) -> void:
	g["outside_shade"] = 0.7
	g["scrub_bias"] = 0.05
	for row in 2:
		for i in 5:
			var x := 7.0 + i * 3.6 + row * 1.8 + _rng.randf_range(-0.5, 0.5)
			var at := Vector3(x, 0, -6.5 - row * 3.6 + _rng.randf_range(-0.4, 0.4))
			_tree(at)
			if row == 0 and i % 2 == 0:
				_prop("basket", at + Vector3(0.9, 0, 0.7))   # olives picked into it
	for x: float in [-20.0, -16.5]:
		_tree(Vector3(x, 0, -7.5))
	for x: float in [-13.0, -4.0, 1.5]:
		_dry_scrub(Vector3(x, 0, -9.5))

# Inspection Gate (3:31-32): the goldsmiths and traders by the Sheep Gate; the circuit
# closes where it began, so the sheepfold is back outside
func _market() -> void:
	_stall(Vector3(-14.5, 0, 9.0), 3.0, 2.2, "metal")
	_stall(Vector3(-8.2, 0, 5.4), 2.6, 2.0, "cloth")
	_stall(Vector3(15.0, 0, 8.5), 3.0, 2.2, "jars")
	_sheepfold(Vector3(-17.0, 0.0, -7.4))
