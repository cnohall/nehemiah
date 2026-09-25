extends StaticBody3D

# Buildable wall slot, also used by gate pillars and watchtowers.
# Server owns stage / health / pending; clients mirror stage + pending via the Sync child.
# Footprint comes from the CollisionShape3D box; visuals are generated per stage.

signal stage_changed(new_stage: int)
signal destroyed

enum Stage { EMPTY, FRAMED, STACKED, MORTARED }

# Cost of reaching each stage, by crew size (1, 2, 3+). A solo builder needs fewer
# trips; a full crew does the full job.
const MATERIAL_COST_BY_CREW := [
	{ Stage.FRAMED: { "wood": 2 }, Stage.STACKED: { "stone": 4 }, Stage.MORTARED: { "mortar": 1 } },
	{ Stage.FRAMED: { "wood": 3 }, Stage.STACKED: { "stone": 5 }, Stage.MORTARED: { "mortar": 2 } },
	{ Stage.FRAMED: { "wood": 3 }, Stage.STACKED: { "stone": 6 }, Stage.MORTARED: { "mortar": 2 } },
]
const MAX_HEALTH           := 150.0
const DEGRADE_HEALTH_RATIO := 0.5
const LABEL_RANGE          := 6.0
const LABEL_POLL           := 0.2

const COURSE_H     := 0.5    # stone course height
const MERLON_W     := 0.7
const MERLON_H     := 0.45
const GAP_ROUGH    := 0.07   # joint width before mortar
const GAP_MORTARED := 0.03

const STONE_COLOR  := Color(0.74, 0.64, 0.48)   # Jerusalem limestone
const MORTAR_COLOR := Color(0.62, 0.56, 0.46)
const EARTH_COLOR  := Color(0.55, 0.45, 0.30)
const TARGET_COLOR := Color(0.86, 0.58, 0.22)   # today's work — amber footing
const WOOD_COLOR   := Color(0.48, 0.32, 0.17)

const _FONT := preload("res://assets/fonts/Spectral/Spectral-SemiBold.ttf")

@export var stage: Stage = Stage.EMPTY:
	set(value):
		if value == stage:
			return
		stage = value
		if is_node_ready():
			_update_visuals()
			_dust_puff()
			stage_changed.emit(stage)

# Outer stretches repaired by other families (Neh. 3) — not networked, not buildable.
# They rise with the campaign (rubble on day 1, finished by day 52 — "the whole wall
# was joined together to half its height", Neh. 4:6) and always block movement.
@export var decorative := false

# Server marks the units that must be finished today (DayDirector)
var is_target := false:
	set(value):
		is_target = value
		if is_node_ready():
			_foundation_mat.albedo_color = TARGET_COLOR if value else EARTH_COLOR
			_update_label()

var health: float = MAX_HEALTH
# Materials deposited here, waiting to be built
var pending: Dictionary = { "stone": 0, "wood": 0, "mortar": 0 }:
	set(value):
		pending = value
		if is_node_ready():
			_update_label()

var _size: Vector3
var _center: Vector3
var _visual: Node3D
var _label: Label3D
var _foundation_mat: StandardMaterial3D
var _label_poll := 0.0

@onready var _col: CollisionShape3D = $CollisionShape3D

func _enter_tree() -> void:
	# Before ready, so the starting stage doesn't play a dust puff
	if decorative and not is_node_ready():
		_follow_campaign(GameState.current_day)

func _ready() -> void:
	_size = (_col.shape as BoxShape3D).size
	_center = _col.position
	_visual = Node3D.new()
	add_child(_visual)
	_build_label()
	if decorative:
		set_process(false)
		GameState.day_changed.connect(_follow_campaign)
	else:
		add_to_group("wall_sections")
		_build_sync()
		GameState.crew_changed.connect(_update_label.unbind(1))
	_update_visuals()

func _process(delta: float) -> void:
	_label_poll -= delta
	if _label_poll > 0.0:
		return
	_label_poll = LABEL_POLL
	var damaged := is_built() and health < MAX_HEALTH
	_label.visible = (is_target and not is_complete()) 		or ((stage != Stage.MORTARED or damaged) and _local_player_near())
	if damaged:
		_update_label()

# ── Deposit / Build (server) ───────────────────────────────

func deposit(kind: String, amount: int) -> bool:
	if not multiplayer.is_server() or not needs(kind):
		return false
	pending[kind] = pending.get(kind, 0) + amount
	_update_label()
	return true

func needs(kind: String) -> bool:
	var next := stage + 1
	if next > Stage.MORTARED:
		return false
	var cost: Dictionary = cost_for(next)
	return cost.has(kind) and pending.get(kind, 0) < cost[kind]

func cost_for(target_stage: int) -> Dictionary:
	var tier := clampi(GameState.crew_size, 1, MATERIAL_COST_BY_CREW.size()) - 1
	return MATERIAL_COST_BY_CREW[tier][target_stage]

## Material still missing for the next stage ("" when finished)
func next_need() -> String:
	var next := stage + 1
	if next > Stage.MORTARED:
		return ""
	var cost: Dictionary = cost_for(next)
	for kind: String in cost:
		if pending.get(kind, 0) < cost[kind]:
			return kind
	return ""

func can_build() -> bool:
	var next := stage + 1
	if next > Stage.MORTARED:
		return false
	var cost: Dictionary = cost_for(next)
	for kind in cost:
		if pending.get(kind, 0) < cost[kind]:
			return false
	return true

func try_build() -> bool:
	if not multiplayer.is_server() or not can_build():
		return false
	var next := stage + 1
	var cost: Dictionary = cost_for(next)
	for kind in cost:
		pending[kind] -= cost[kind]
	stage = next as Stage
	return true

# Returns how much of the next stage's required material is pending (0.0–1.0)
func get_build_progress() -> float:
	var next := stage + 1
	if next > Stage.MORTARED:
		return 1.0
	var cost: Dictionary = cost_for(next)
	var kind: String = cost.keys()[0]
	return minf(float(pending.get(kind, 0)) / float(cost[kind]), 1.0)

## Decorative only: stage from how far the campaign has got. Each stretch is offset a
## few days so they don't all rise together. Pure function of the day, so every peer agrees.
func _follow_campaign(day: int) -> void:
	var t := (day - 1 + (hash(global_position.x) % 7) - 3) / float(GameState.TOTAL_DAYS - 1)
	var s := Stage.EMPTY
	if day >= GameState.TOTAL_DAYS or t >= 0.9:
		s = Stage.MORTARED
	elif t >= 0.5:
		s = Stage.STACKED
	elif t >= 0.2:
		s = Stage.FRAMED
	stage = s

func is_built() -> bool:
	return stage != Stage.EMPTY

func is_complete() -> bool:
	return stage == Stage.MORTARED

# ── Day transitions (server) ───────────────────────────────

## New circuit section: back to bare foundations
func reset_slot() -> void:
	pending = { "stone": 0, "wood": 0, "mortar": 0 }
	health = MAX_HEALTH
	stage = Stage.EMPTY

## Overnight repair of part of the damage
func repair(fraction: float) -> void:
	health = minf(MAX_HEALTH, health + (MAX_HEALTH - health) * fraction)

# Distance from a world point to this section's footprint (not its centre —
# an enemy at the end of an 8 m wall is still touching it)
func distance_to_point(p: Vector3) -> float:
	var local := to_local(p) - _center
	var half := _size * 0.5
	var clamped := local.clamp(-half, half)
	return Vector2(local.x - clamped.x, local.z - clamped.z).length()

# ── Damage (server) ────────────────────────────────────────

func take_damage(amount: float) -> void:
	if stage == Stage.EMPTY:
		return
	health = clampf(health - amount, 0.0, MAX_HEALTH)
	if health == 0.0:
		_degrade()

func _degrade() -> void:
	pending = { "stone": 0, "wood": 0, "mortar": 0 }
	health = MAX_HEALTH * DEGRADE_HEALTH_RATIO
	stage = (stage - 1) as Stage
	# Knocked back to bare foundation — slot stays so it can be rebuilt
	if stage == Stage.EMPTY:
		destroyed.emit()

# ── Networking ─────────────────────────────────────────────

func _build_sync() -> void:
	var cfg := SceneReplicationConfig.new()
	for prop: NodePath in [^".:stage", ^".:pending", ^".:health", ^".:is_target"]:
		cfg.add_property(prop)
		cfg.property_set_replication_mode(prop, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.replication_interval = 0.1
	sync.replication_config = cfg
	NetworkManager.gate_sync(sync)
	add_child(sync)

# ── Visuals ────────────────────────────────────────────────

func _update_visuals() -> void:
	for c in _visual.get_children():
		c.queue_free()
	_col.set_deferred("disabled", stage == Stage.EMPTY and not decorative)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(global_position.snapped(Vector3.ONE * 0.1))
	_add_foundation()
	match stage:
		Stage.EMPTY:
			_add_courses(rng, 0.25, GAP_ROUGH * 2.0)  # ruined footing, walkable
		Stage.FRAMED:
			_add_courses(rng, minf(COURSE_H, _size.y), GAP_ROUGH)
			_add_scaffold()
		Stage.STACKED:
			_add_courses(rng, _size.y, GAP_ROUGH)
		Stage.MORTARED:
			_add_box(Vector3(_size.x - 0.12, _size.y - 0.05, _size.z - 0.12),
				_center, MORTAR_COLOR)
			_add_courses(rng, _size.y, GAP_MORTARED)
			_add_merlons()
	_update_label()

func _add_foundation() -> void:
	var s := Vector3(_size.x + 0.35, 0.12, _size.z + 0.35)
	_foundation_mat = _add_box(s, Vector3(_center.x, 0.06, _center.z),
		TARGET_COLOR if is_target else EARTH_COLOR)

# Staggered courses of rough-cut blocks, one MultiMesh for the whole section
func _add_courses(rng: RandomNumberGenerator, height: float, gap: float) -> void:
	var rows := maxi(1, roundi(height / COURSE_H))
	var row_h := height / rows
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var x0 := _center.x - _size.x * 0.5
	var y0 := 0.12
	for r in rows:
		var x := x0
		var first := true
		while x < x0 + _size.x - 0.05:
			var blen := rng.randf_range(0.7, 1.25)
			if first and r % 2 == 1:
				blen *= 0.5  # stagger joints
			first = false
			blen = minf(blen, x0 + _size.x - x)
			var depth := _size.z + rng.randf_range(-0.05, 0.05)
			var s := Vector3(blen - gap, row_h - gap, depth)
			var pos := Vector3(x + blen * 0.5, y0 + row_h * (r + 0.5), _center.z)
			transforms.append(Transform3D(Basis.from_scale(s), pos))
			var v := rng.randf_range(-0.07, 0.06)
			colors.append(Color(STONE_COLOR.r + v, STONE_COLOR.g + v, STONE_COLOR.b + v * 1.2))
			x += blen
	_add_multimesh(transforms, colors)

func _add_merlons() -> void:
	var top := 0.12 + _size.y
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var deep := _size.z > 1.5  # towers: ring of merlons; walls: single row
	var md := 0.4 if deep else _size.z
	var nx := maxi(1, floori(_size.x / (MERLON_W * 2.0)))
	var zs: Array = [_center.z - _size.z * 0.5 + md * 0.5, _center.z + _size.z * 0.5 - md * 0.5] if deep else [_center.z]
	for z: float in zs:
		for i in nx:
			var x := _center.x - _size.x * 0.5 + _size.x / nx * (i + 0.5)
			transforms.append(Transform3D(Basis.from_scale(Vector3(MERLON_W, MERLON_H, md)),
				Vector3(x, top + MERLON_H * 0.5, z)))
			colors.append(STONE_COLOR)
	if deep:
		var nz := maxi(1, floori(_size.z / (MERLON_W * 2.0)))
		for x: float in [_center.x - _size.x * 0.5 + md * 0.5, _center.x + _size.x * 0.5 - md * 0.5]:
			for i in range(1, nz - 1):  # skip ends, covered by the x rows
				var z := _center.z - _size.z * 0.5 + _size.z / nz * (i + 0.5)
				transforms.append(Transform3D(Basis.from_scale(Vector3(md, MERLON_H, MERLON_W)),
					Vector3(x, top + MERLON_H * 0.5, z)))
				colors.append(STONE_COLOR)
	_add_multimesh(transforms, colors)

func _add_scaffold() -> void:
	var h := _size.y + 0.3
	var posts := maxi(2, ceili(_size.x / 1.6) + 1)
	for side: float in [-1.0, 1.0]:
		var z := _center.z + side * (_size.z * 0.5 + 0.18)
		for i in posts:
			var x := _center.x - _size.x * 0.5 + _size.x * i / (posts - 1)
			_add_box(Vector3(0.12, h, 0.12), Vector3(x, h * 0.5, z), WOOD_COLOR)
		for y: float in [h * 0.5, h - 0.06]:
			_add_box(Vector3(_size.x + 0.2, 0.09, 0.09), Vector3(_center.x, y, z), WOOD_COLOR.darkened(0.1))
	# Walk boards across the top
	_add_box(Vector3(_size.x, 0.05, _size.z + 0.5), Vector3(_center.x, h * 0.5 + 0.07, _center.z),
		WOOD_COLOR.lightened(0.08))

func _add_box(size: Vector3, pos: Vector3, color: Color) -> StandardMaterial3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	mi.material_override = mat
	_visual.add_child(mi)
	return mat

func _add_multimesh(transforms: Array[Transform3D], colors: Array[Color]) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _stone_material()
	_visual.add_child(mmi)

static var _stone_mat: StandardMaterial3D

static func _stone_material() -> StandardMaterial3D:
	if _stone_mat == null:
		var noise := FastNoiseLite.new()
		noise.frequency = 0.08
		noise.fractal_octaves = 4
		var tex := NoiseTexture2D.new()
		tex.noise = noise
		tex.seamless = true
		tex.width = 256
		tex.height = 256
		var grad := Gradient.new()
		grad.set_color(0, Color(0.80, 0.80, 0.80))
		grad.set_color(1, Color(1.0, 1.0, 1.0))
		tex.color_ramp = grad
		_stone_mat = StandardMaterial3D.new()
		_stone_mat.vertex_color_use_as_albedo = true
		_stone_mat.albedo_texture = tex
		_stone_mat.uv1_triplanar = true
		_stone_mat.uv1_world_triplanar = true
		_stone_mat.uv1_scale = Vector3.ONE * 0.6
		_stone_mat.roughness = 0.92
	return _stone_mat

func _dust_puff() -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.85
	p.amount = 28
	p.lifetime = 1.4
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(_size.x * 0.5, 0.2, _size.z * 0.5 + 0.3)
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.8
	p.gravity = Vector3(0, -0.6, 0)
	p.damping_min = 0.8
	p.damping_max = 1.4
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.87, 0.78, 0.60, 0.55))
	ramp.set_color(1, Color(0.87, 0.78, 0.60, 0.0))
	p.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 0.7)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	quad.material = mat
	p.mesh = quad
	p.position = Vector3(_center.x, 0.3, _center.z)
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)

# ── Label ──────────────────────────────────────────────────

func _build_label() -> void:
	_label = Label3D.new()
	_label.font = _FONT
	_label.font_size = 40
	_label.pixel_size = 0.01
	_label.outline_size = 10
	_label.modulate = Color(0.98, 0.95, 0.88)
	_label.outline_modulate = Color(0.20, 0.14, 0.08)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.position = Vector3(_center.x, _size.y + 1.0, _center.z)
	_label.visible = false
	add_child(_label)

func _update_label() -> void:
	var lines: PackedStringArray = []
	if is_target and not is_complete():
		lines.append("— Today's work —")
	var next := stage + 1
	if next <= Stage.MORTARED:
		var cost: Dictionary = cost_for(next)
		var parts: PackedStringArray = []
		for kind: String in cost:
			var have: int = mini(pending.get(kind, 0), cost[kind])
			parts.append("%s %d/%d" % [kind.capitalize(), have, cost[kind]])
		lines.append("  ".join(parts))
	if is_built() and health < MAX_HEALTH:
		lines.append("Wall %d%%" % roundi(health / MAX_HEALTH * 100.0))
	_label.text = "\n".join(lines)

func _local_player_near() -> bool:
	for p: Node3D in get_tree().get_nodes_in_group("players"):
		if p.is_multiplayer_authority():
			return distance_to_point(p.global_position) < LABEL_RANGE
	return false
