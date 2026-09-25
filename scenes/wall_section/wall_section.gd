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
# With hands-on building the labour moves from hauling to working the wall: one load
# less per stage (never below one), paid back in work time
const ACTIVE_BUILD_DISCOUNT := 1
# Seconds of work for one worker to raise each stage (BuildWork); a solo builder is quicker
const WORK_TIME := { Stage.FRAMED: 2.0, Stage.STACKED: 3.0, Stage.MORTARED: 2.0 }
const SOLO_WORK_MULT := 0.75
# "beams" twist (Neh. 3:3 "they laid its beams"): framing takes long beams, carried in
# pairs, instead of loose timber
const BEAM_COST_BY_CREW    := [1, 2, 2]
const MAX_HEALTH           := 150.0
const DEGRADE_HEALTH_RATIO := 0.5
const LABEL_RANGE          := 6.0
const LABEL_POLL           := 0.2

const COURSE_H     := 0.5    # stone course height
const MERLON_W     := 0.7
const MERLON_H     := 0.45
const GAP_ROUGH    := 0.07   # joint width before mortar
const GAP_MORTARED := 0.03

const STONE_COLOR  := Color(0.80, 0.74, 0.63)   # Jerusalem limestone — paler than the ground so the wall leads
const MORTAR_COLOR := Color(0.62, 0.56, 0.46)
const EARTH_COLOR  := Color(0.55, 0.45, 0.30)
const TARGET_COLOR := Color(0.86, 0.58, 0.22)   # today's work — amber footing
const WOOD_COLOR   := Color(0.48, 0.32, 0.17)

const _FONT := preload("res://assets/fonts/Spectral/Spectral-SemiBold.ttf")

@export var stage: Stage = Stage.EMPTY:
	set(value):
		if value == stage:
			return
		if is_node_ready() and not decorative:
			Sfx.play("build" if value > stage else "wall_crumble", global_position)
			# Felt by whoever is close: a thud when a course goes up, a jolt when one falls
			if GameState.phase == GameState.Phase.WORK and _local_player_near():
				get_tree().call_group("camera_rig", "shake", 0.15 if value > stage else 0.45)
		stage = value
		if is_node_ready():
			_update_visuals()
			_dust_puff()
			_bounce()
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

# Replicated; a drop shakes the stones on every peer so an attack reads at a glance
var health: float = MAX_HEALTH:
	set(value):
		if value < health and is_node_ready():
			_shake()
			Sfx.play("wall_hit", global_position)
			last_hit_msec = Time.get_ticks_msec()
		health = value
# Local clock of the last hit seen on this peer — drives the HUD's off-screen alert
var last_hit_msec := -100000
# Materials deposited here, waiting to be built
var pending: Dictionary = _empty_pending():
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
var _juice_tween: Tween
var _work: BuildWork
# The next stage going up while workers are at it, revealed block by block
var _preview: Node3D
var _preview_skip := 0

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
		add_to_group("wall_sections")   # what enemies batter
		add_to_group("build_sites")     # what workers deliver to (walls + gate doors)
		GameState.section_changed.connect(_update_label.unbind(1))
		_work = BuildWork.new()
		_work.name = "Work"
		_work.position = Vector3(_center.x, _size.y + 0.9, _center.z)
		add_child(_work)
		_work.progress_changed.connect(_on_work_progress)
		InputMode.changed.connect(_update_label.unbind(1))
		_build_sync()
		GameState.crew_changed.connect(_update_label.unbind(1))
		GameState.crew_changed.connect(_prime_work.unbind(1))
		_prime_work()
	_update_visuals()

func _process(delta: float) -> void:
	_label_poll -= delta
	if _label_poll > 0.0:
		return
	_label_poll = LABEL_POLL
	var damaged := is_built() and health < MAX_HEALTH
	var working := _work != null and _work.progress > 0.0   # the bar and rising stones say it all
	_label.visible = not working and ((is_target and not is_complete()) 		or ((stage != Stage.MORTARED or damaged) and _local_player_near()))
	if damaged:
		_update_label()

static func _empty_pending() -> Dictionary:
	return { "stone": 0, "wood": 0, "mortar": 0, "beam": 0 }

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
	if target_stage == Stage.FRAMED and GameState.has_twist("beams"):
		return { "beam": BEAM_COST_BY_CREW[tier] }
	var cost: Dictionary = MATERIAL_COST_BY_CREW[tier][target_stage].duplicate()
	if GameState.active_build:
		for kind: String in cost:
			cost[kind] = maxi(1, cost[kind] - ACTIVE_BUILD_DISCOUNT)
	return cost

## BuildWork: the site that holds this progress
func work() -> BuildWork:
	return _work

## Material being worked into the next stage ("" when finished) — picks the strike sound
func work_material() -> String:
	var next := stage + 1
	return "" if next > Stage.MORTARED else cost_for(next).keys()[0]

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
	_prime_work()
	return true

func _prime_work() -> void:
	if _work == null:
		return
	var next := stage + 1
	if next <= Stage.MORTARED:
		_work.work_time = WORK_TIME[next] * (SOLO_WORK_MULT if GameState.crew_size == 1 else 1.0)

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
	pending = _empty_pending()
	health = MAX_HEALTH
	stage = Stage.EMPTY
	_work.reset()
	_prime_work()

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

# Spot just outside the footprint on the side facing `from` — where an attacker stands
func approach_point(from: Vector3, standoff: float) -> Vector3:
	var local := to_local(from) - _center
	var half := _size * 0.5
	var clamped := local.clamp(-half, half)
	var out := Vector3(local.x - clamped.x, 0.0, local.z - clamped.z)
	if out.length_squared() < 0.0001:
		out = Vector3(0.0, 0.0, signf(local.z) if local.z != 0.0 else -1.0)
	var p := to_global(_center + clamped + out.normalized() * standoff)
	p.y = from.y
	return p

# ── Damage (server) ────────────────────────────────────────

func take_damage(amount: float) -> void:
	if stage == Stage.EMPTY:
		return
	health = clampf(health - amount, 0.0, MAX_HEALTH)
	if health == 0.0:
		_degrade()

func _degrade() -> void:
	pending = _empty_pending()
	health = MAX_HEALTH * DEGRADE_HEALTH_RATIO
	stage = (stage - 1) as Stage
	_work.reset()
	_prime_work()
	# Knocked back to bare foundation — slot stays so it can be rebuilt
	if stage == Stage.EMPTY:
		destroyed.emit()

# ── Networking ─────────────────────────────────────────────

func _build_sync() -> void:
	var cfg := SceneReplicationConfig.new()
	for prop: NodePath in [^".:stage", ^".:pending", ^".:health", ^".:is_target", ^"Work:progress"]:
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
	_clear_preview()
	_col.set_deferred("disabled", stage == Stage.EMPTY and not decorative)
	_add_foundation()
	_build_stage(stage, _visual_rng())
	_update_label()

# Same seed every time, so a stage's preview lays exactly the blocks it will end up with
func _visual_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(global_position.snapped(Vector3.ONE * 0.1))
	return rng

# Every peer: workers' progress → the next stage rises in the order it's built
func _on_work_progress(value: float) -> void:
	var next := stage + 1
	if value <= 0.0 or next > Stage.MORTARED:
		_clear_preview()
		return
	if _preview == null:
		_preview = Node3D.new()
		add_child(_preview)
		var real := _visual
		_visual = _preview
		_build_stage(next as Stage, _visual_rng())
		_visual = real
		# Pieces already standing in this stage are shown from the start
		match next:
			Stage.STACKED:
				_preview_skip = _first_multimesh_count(_visual)
			Stage.MORTARED:
				_preview_skip = 1 + _first_multimesh_count(_preview)   # mortar core + courses
			_:
				_preview_skip = 0
	BuildWork.reveal(_preview, value, _preview_skip)

func _clear_preview() -> void:
	if _preview != null:
		_preview.queue_free()
		_preview = null

static func _first_multimesh_count(root: Node) -> int:
	for c in root.get_children():
		if c is MultiMeshInstance3D:
			return c.multimesh.instance_count
	return 0

func _build_stage(s: Stage, rng: RandomNumberGenerator) -> void:
	match s:
		Stage.EMPTY:
			_add_courses(rng, 0.25, GAP_ROUGH * 2.0)  # ruined footing, walkable
		Stage.FRAMED:
			_add_courses(rng, minf(COURSE_H, _size.y), GAP_ROUGH)
			_add_scaffold(rng)
		Stage.STACKED:
			_add_courses(rng, _size.y, GAP_ROUGH)
		Stage.MORTARED:
			_add_box(Vector3(_size.x - 0.12, _size.y - 0.05, _size.z - 0.12),
				_center, MORTAR_COLOR)
			_add_courses(rng, _size.y, GAP_MORTARED)
			_add_merlons()

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
			# Value jitter + a warm/cool drift per block; the odd weathered stone reused from rubble
			var v := rng.randf_range(-0.07, 0.06)
			if rng.randf() < 0.08:
				v -= 0.12
			var w := rng.randf_range(-0.025, 0.025)
			colors.append(Color(STONE_COLOR.r + v + w, STONE_COLOR.g + v, STONE_COLOR.b + v * 1.2 - w))
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

# Timber scaffold marking the wall's full height: rough poles, X-braces, putlogs
# with short plank runs, and a ladder on the city side (Neh. 4:17 builders at work)
func _add_scaffold(rng: RandomNumberGenerator) -> void:
	var h := _size.y + 0.35
	var bays := maxi(1, roundi(_size.x / 1.5))
	var x0 := _center.x - _size.x * 0.5
	var bay := _size.x / bays
	var off := _size.z * 0.5 + 0.28
	var tops: Array[Vector3] = []
	for side: float in [-1.0, 1.0]:
		var z := _center.z + side * off
		var feet: Array[Vector3] = []
		var heads: Array[Vector3] = []
		for i in bays + 1:
			var x := x0 + bay * i
			var foot := Vector3(x + rng.randf_range(-0.05, 0.05), 0.0, z)
			var head := Vector3(x + rng.randf_range(-0.08, 0.08), h + rng.randf_range(-0.1, 0.15), z + side * 0.04)
			_add_pole(foot, head, 0.055, WOOD_COLOR.darkened(rng.randf_range(0.0, 0.15)))
			feet.append(foot)
			heads.append(head)
		# Ledger lashed along the top, X-brace in alternate bays
		var ly := h - 0.12
		_add_pole(Vector3(x0 - 0.15, ly, z), Vector3(x0 + _size.x + 0.15, ly, z), 0.035, WOOD_COLOR.darkened(0.1))
		for i in bays:
			if (i + int(side > 0.0)) % 2 == 0:
				var a := feet[i] + Vector3(0, 0.15, 0)
				var b := Vector3(heads[i + 1].x, ly, z)
				_add_pole(a, b, 0.03, WOOD_COLOR.darkened(0.18))
		if side > 0.0:
			tops = heads
	# Putlogs across the wall with short, slightly skewed plank runs on top
	for i in bays + 1:
		var x := tops[i].x
		_add_pole(Vector3(x, h - 0.08, _center.z - off - 0.1), Vector3(x, h - 0.08, _center.z + off + 0.1),
			0.03, WOOD_COLOR.darkened(0.1))
	for i in bays:
		if rng.randf() < 0.75:
			_add_box(Vector3(bay * rng.randf_range(0.7, 0.95), 0.04, 0.28),
				Vector3(x0 + bay * (i + 0.5), h - 0.03, _center.z + rng.randf_range(-0.2, 0.2)),
				WOOD_COLOR.lightened(rng.randf_range(0.06, 0.16)))
			_visual.get_child(-1).rotation.y = rng.randf_range(-0.06, 0.06)
	# Ladder leaning on the city side
	var lx := x0 + bay * (rng.randi_range(0, bays - 1) + 0.5)
	var base_z := _center.z + off + 0.75
	var top_z := _center.z + off + 0.05
	for dx: float in [-0.2, 0.2]:
		_add_pole(Vector3(lx + dx, 0.0, base_z), Vector3(lx + dx, h + 0.1, top_z), 0.03, WOOD_COLOR.lightened(0.05))
	var rungs := int(h / 0.32)
	for r in range(1, rungs + 1):
		var t := float(r) / (rungs + 1)
		var y := (h + 0.1) * t
		var z := lerpf(base_z, top_z, t)
		_add_pole(Vector3(lx - 0.2, y, z), Vector3(lx + 0.2, y, z), 0.02, WOOD_COLOR.lightened(0.05))

# Round-ish timber between two points (6-sided, so it catches light like a pole)
func _add_pole(a: Vector3, b: Vector3, radius: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.85
	mesh.bottom_radius = radius
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 6
	mesh.rings = 1
	mi.mesh = mesh
	var dir := (b - a).normalized()
	mi.basis = Basis(Quaternion(Vector3.UP, dir)) if absf(dir.dot(Vector3.UP)) < 0.999 else Basis()
	mi.position = (a + b) * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	mi.material_override = mat
	_visual.add_child(mi)

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

# Stage raised: pop up from slightly squashed, cartoon-style
func _bounce() -> void:
	if _juice_tween:
		_juice_tween.kill()
	_visual.position = Vector3.ZERO
	_visual.scale = Vector3(1.02, 0.9, 1.02)
	_juice_tween = create_tween()
	_juice_tween.tween_property(_visual, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _shake() -> void:
	if _juice_tween and _juice_tween.is_running():
		return
	_juice_tween = create_tween()
	for x: float in [0.07, -0.06, 0.04, -0.02, 0.0]:
		_juice_tween.tween_property(_visual, "position:x", x, 0.04)

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
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	p.scale_amount_curve = DustFx.grow_curve()
	p.angle_min = 0.0
	p.angle_max = 360.0
	# Earthier than the limestone so the puff reads against a fresh wall
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.78, 0.68, 0.52, 0.5))
	ramp.set_color(1, Color(0.78, 0.68, 0.52, 0.0))
	p.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.material = DustFx.material()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	var next := stage + 1
	if GameState.active_build and can_build():
		# Everything's here — it needs hands, not loads
		lines.append("Build  [%s]" % InputMode.key("interact"))
	elif next <= Stage.MORTARED:
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
