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
const WOOL       := Color(0.93, 0.90, 0.82)
const FISH       := Color(0.62, 0.66, 0.68)
const WATER      := Color(0.20, 0.42, 0.46)
const FLAME      := Color(1.0, 0.62, 0.22)
const FIG_LEAF   := Color(0.30, 0.46, 0.20)
const FLOWERS    := [Color(0.86, 0.30, 0.24), Color(0.95, 0.78, 0.30), Color(0.62, 0.36, 0.62)]
# Ground looks: scrub_bias (+ greener), tint + tint_amount, outside_shade (valley fall)
const GROUND_DEFAULT := { "scrub_bias": 0.0, "tint": Color(0.5, 0.5, 0.5), "tint_amount": 0.0, "outside_shade": 0.0 }

# Solid pieces must leave these clear: the wall line and its working strip, and the
# enemy spawn line outside (WaveManager.SPAWN_Z)
const WALL_STRIP := Rect2(-23.0, -2.8, 46.0, 5.6)
const SPAWN_STRIP := Rect2(-20.0, -16.0, 40.0, 4.0)
const CLEARANCE := 1.2   # around piles, the trough, rubble heaps and the respawn point

var _body: StaticBody3D
var _built := -1
var _keep_clear: Array[Vector2] = []

func _ready() -> void:
	GameState.section_changed.connect(_rebuild.unbind(1))
	_rebuild()

func _rebuild() -> void:
	var index := GameState.current_section_index
	if index == _built:
		return
	_built = index
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_batches.clear()
	_rng.seed = 1000 + index
	_body = StaticBody3D.new()
	_body.collision_mask = 0
	add_child(_body)
	_collect_keep_clear()
	var ground := GROUND_DEFAULT.duplicate()
	match GameState.SECTIONS[index].get("terrain", ""):
		"sheepfold":   _sheepfold(Vector3(-15.0, 0.0, -7.2))
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

# Everything a worker has to reach, as the SectionStage laid it out for this section
func _collect_keep_clear() -> void:
	_keep_clear.clear()
	_keep_clear.append(Vector2(0.0, 8.0))   # Player.RESPAWN_POS
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

# Debug aid: a solid piece that crowds the wall, the spawn line or something workers use
func _check(p: Vector2, half: Vector2) -> void:
	if not OS.is_debug_build():
		return
	var sec_name: String = GameState.get_current_section()["name"]
	var box := Rect2(p - half, half * 2.0)
	if box.intersects(WALL_STRIP) or box.intersects(SPAWN_STRIP):
		push_warning("SectionTerrain (%s): piece at %s crowds the wall / spawn line" % [sec_name, p])
	for k: Vector2 in _keep_clear:
		if box.grow(CLEARANCE).has_point(k):
			push_warning("SectionTerrain (%s): piece at %s crowds %s" % [sec_name, p, k])

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
	_solid(c, Vector3(w * 0.85, 0.8, d * 0.6), _vary(WOOD, 0.03).lightened(0.05))
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

# Tree with a small solid trunk (the canopy is walked under)
func _tree(at: Vector3, fig := false) -> void:
	if fig:
		_add("trunk", Transform3D(Basis.from_scale(Vector3(1.2, 1.1, 1.2)), at + Vector3(0, 0.55, 0)), _vary(OLIVE_TRUNK, 0.04))
		for i in 4:
			var off := Vector3(_rng.randf_range(-0.8, 0.8), _rng.randf_range(1.2, 1.7), _rng.randf_range(-0.8, 0.8))
			_add("leaf", Transform3D(_yaw().scaled(Vector3.ONE * _rng.randf_range(1.0, 1.4)), at + off), _vary(FIG_LEAF, 0.05))
	else:
		_olive(at)
	_collider(at, Vector3(0.5, 1.5, 0.5))

func _smoke(at: Vector3, dark := false) -> void:
	var p := CPUParticles3D.new()
	p.amount = 10
	p.lifetime = 4.0
	p.direction = Vector3.UP
	p.spread = 12.0
	p.gravity = Vector3(0.25, 0.35, 0.1)
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.6
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.4
	p.scale_amount_curve = DustFx.grow_curve()
	var c := Color(0.35, 0.33, 0.32) if dark else Color(0.85, 0.82, 0.78)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(c, 0.0))
	ramp.add_point(0.2, Color(c, 0.35))
	ramp.set_color(1, Color(c, 0.0))
	p.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	quad.material = DustFx.material()
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = at
	add_child(p)

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
	for i in 7:
		var at := c + Vector3(_rng.randf_range(-2.0, 2.0), 0.35, _rng.randf_range(-2.0, 1.4))
		_add("bush", Transform3D(_yaw().scaled(Vector3(1.1, 0.7, 0.8)), at), _vary(WOOL, 0.04))
		_add("pebble", Transform3D(Basis.from_scale(Vector3(1.6, 2.0, 1.6)), at + Vector3(0.35, 0.1, 0.2)), Color(0.22, 0.18, 0.15))
	# A few strays grazing on the slope
	for p: Vector3 in [Vector3(-8.5, 0, -9.5), Vector3(-7.2, 0, -10.4), Vector3(6.5, 0, -9.0)]:
		_add("bush", Transform3D(_yaw().scaled(Vector3(1.1, 0.7, 0.8)), p + Vector3(0, 0.35, 0)), _vary(WOOL, 0.04))

# Fish Gate (3:3): Tyrian fish sellers' stalls inside the gate (Neh. 13:16)
func _fish_market() -> void:
	_stall(Vector3(10.5, 0, 5.8), 3.0, 2.2, "fish")
	_stall(Vector3(15.5, 0, 6.2), 3.0, 2.2, "fish")
	_stall(Vector3(13.0, 0, 10.2), 3.2, 2.2, "jars")
	for p: Vector3 in [Vector3(8.4, 0, 8.2), Vector3(17.8, 0, 8.8)]:
		_add("jar", Transform3D(Basis.from_scale(Vector3(1.6, 0.9, 1.6)), p + Vector3(0, 0.2, 0)), _vary(REED_COLOR, 0.04))

const REED_COLOR := Color(0.58, 0.47, 0.28)

# Jeshanah Gate (3:6): burned house shells with charred beams (Neh. 1:3, 2:13)
func _ruins(g: Dictionary) -> void:
	g["tint"] = Color(0.42, 0.37, 0.33)
	g["tint_amount"] = 0.16
	for c: Vector3 in [Vector3(-20.0, 0, 8.5), Vector3(19.5, 0, 9.5), Vector3(5.5, 0, 5.6), Vector3(-18.0, 0, -7.5)]:
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
	_stall(Vector3(-19.5, 0, 10.5), 2.8, 2.0, "metal")

# Tower of Ovens (3:11): domed clay bread ovens and firewood, smoke going up
func _ovens(g: Dictionary) -> void:
	g["tint"] = Color(0.66, 0.42, 0.30)
	g["tint_amount"] = 0.08
	for c: Vector3 in [Vector3(-9.5, 0, 6.0), Vector3(-14.5, 0, 8.8), Vector3(-19.5, 0, 5.5)]:
		_add("leaf", Transform3D(Basis.from_scale(Vector3(1.8, 1.7, 1.8)), c + Vector3(0, 0.4, 0)), _vary(CLAY_COLOR, 0.04).lightened(0.1))
		_add("opening", Transform3D(Basis.from_scale(Vector3(0.5, 0.45, 0.06)), c + Vector3(0, 0.35, 0.86)), Color(0.9, 0.42, 0.14))
		_collider(c, Vector3(1.8, 1.4, 1.8))
		_smoke(c + Vector3(0, 1.3, 0))
		var wood := c + Vector3(1.8, 0, 0.6)
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
	for c: Vector3 in [Vector3(10.0, 0, 6.5), Vector3(14.5, 0, 10.5), Vector3(18.5, 0, 5.0), Vector3(22.5, 0, 10.0)]:
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
	var pool := Vector3(-18.0, 0, 6.5)
	var pw := 7.0
	var pd := 4.6
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
	var mat := StandardMaterial3D.new()
	mat.albedo_color = WATER
	mat.roughness = 0.15
	mat.metallic_specular = 0.8
	water.material_override = mat
	water.position = pool + Vector3(0, 0.3, 0)
	add_child(water)
	# Stairs going down from the City of David (3:15), beside the pool
	for i in 5:
		_add("slab", Transform3D(Basis.from_scale(Vector3(2.4, 0.12, 0.5)), pool + Vector3(pw * 0.5 + 1.6, 0.06 + (4 - i) * 0.02, -1.0 + i * 0.5)), _vary(PAVING_COLOR, 0.03))
	# The King's Garden: figs and olives in rows, flower beds between
	for x: float in [9.0, 13.0, 17.0, 21.0]:
		for z: float in [6.0, 10.0]:
			_tree(Vector3(x + _rng.randf_range(-0.4, 0.4), 0, z + _rng.randf_range(-0.3, 0.3)), (x + z) as int % 2 == 0)
	for i in 14:
		var at := Vector3(_rng.randf_range(8.0, 22.0), 0.15, _rng.randf_range(7.4, 8.6))
		_add("pebble", Transform3D(_yaw().scaled(Vector3(1.4, 1.4, 1.4)), at), FLOWERS[_rng.randi() % FLOWERS.size()])
	for p: Vector3 in [Vector3(-12.0, 0, -7.0), Vector3(-6.0, 0, -9.0), Vector3(8.0, 0, -8.0), Vector3(14.0, 0, -10.0)]:
		_tree(p, true)

# Water Gate (3:26): the Ophel slope — torches for the night watch (Neh. 4:22), boulders outside
func _ophel(g: Dictionary) -> void:
	g["outside_shade"] = 0.45
	for x: float in [-17.0, -9.0, -0.5, 8.0, 16.5]:
		_torch(Vector3(x, 0, 3.6))
	for p: Vector3 in [Vector3(-11.0, 0, 9.5), Vector3(18.5, 0, 9.0), Vector3(-10.0, 0, -4.2), Vector3(4.0, 0, -4.2), Vector3(14.0, 0, -4.2)]:
		_torch(p)
	for c: Vector3 in [Vector3(-16.0, 0, -8.0), Vector3(9.0, 0, -9.0), Vector3(21.0, 0, -7.0)]:
		for i in 3:
			var s := Vector3(_rng.randf_range(1.2, 1.9), _rng.randf_range(0.7, 1.2), _rng.randf_range(1.1, 1.7))
			_add("boulder", Transform3D(_yaw().scaled(s), c + Vector3(_rng.randf_range(-1.0, 1.0), s.y * 0.3, _rng.randf_range(-0.8, 0.8))), _vary(ROCK_COLOR, 0.05).lightened(0.05))
		_collider(c, Vector3(2.6, 1.2, 2.2))

# Horse Gate (3:28): "each one in front of his own house" — a row of priests' houses
# between the wall and the yard, narrow lanes between them
func _priests() -> void:
	# x spans; the lane at the gate (x ≈ -4) and the one at the respawn point stay open
	var spans := [Vector2(-22.5, -18.3), Vector2(-16.4, -12.0), Vector2(-10.2, -6.4),
		Vector2(1.6, 5.6), Vector2(7.4, 11.6), Vector2(13.4, 17.6), Vector2(19.4, 23.0)]
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
	_add("block", Transform3D(Basis.from_scale(Vector3(w + 0.15, 0.22, d + 0.15)), c + Vector3(0, h + 0.1, 0)), tint.darkened(0.06))
	# Door toward the wall — "in front of his own house"
	_add("opening", Transform3D(Basis.from_scale(Vector3(0.8, 1.3, 0.06)), c + Vector3(_rng.randf_range(-w * 0.2, w * 0.2), 0.65, -d * 0.5 - 0.02)),
		DOOR_COLORS[_rng.randi() % DOOR_COLORS.size()])
	if _rng.randf() < 0.6:
		var rug := c + Vector3(_rng.randf_range(-w * 0.2, w * 0.2), h + 0.22, 0)
		_add("block", Transform3D(_yaw_small() * Basis.from_scale(Vector3(minf(w * 0.5, 1.8), 0.04, 1.2)), rug), CLOTH_COLORS[_rng.randi() % CLOTH_COLORS.size()])

# East Gate (3:29): across the Kidron, the olive trees of the Mount of Olives
func _kidron(g: Dictionary) -> void:
	g["outside_shade"] = 0.7
	g["scrub_bias"] = 0.05
	for row in 2:
		for i in 5:
			var x := 7.0 + i * 3.6 + row * 1.8 + _rng.randf_range(-0.5, 0.5)
			_tree(Vector3(x, 0, -6.5 - row * 3.6 + _rng.randf_range(-0.4, 0.4)))
	for x: float in [-20.0, -16.5]:
		_tree(Vector3(x, 0, -7.5))

# Inspection Gate (3:31-32): the goldsmiths and traders by the Sheep Gate; the circuit
# closes where it began, so the sheepfold is back outside
func _market() -> void:
	_stall(Vector3(-20.0, 0, 7.5), 3.0, 2.2, "metal")
	_stall(Vector3(-8.2, 0, 5.4), 2.6, 2.0, "cloth")
	_stall(Vector3(18.5, 0, 8.5), 3.0, 2.2, "jars")
	_sheepfold(Vector3(-17.0, 0.0, -7.4))
