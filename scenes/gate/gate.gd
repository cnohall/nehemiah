extends Node3D

# Opening between two buildable pillars, finished one of two ways once both pillars
# stand complete — either way it closes the gap to enemies:
#   gate sections with the "doors" twist — timber → doors hung (Neh. 3:3 "set up its
#     doors, its bolts and its bars"); lintel spans the top
#   stretches with no gate in the text (GameState.has_gate() false) — stone → infill
# Implements the build-site interface players use (see wall_section.gd).
# Server owns pending / finished; clients mirror them via the Sync child.

signal stage_changed(new_stage: int)

const LINTEL_SIZE  := Vector3(3.4, 0.55, 1.0)
const LINTEL_Y     := 2.2
const OPENING      := Vector3(3.0, 2.2, 0.35)   # door leaves fill this
const COST_BY_CREW := [2, 3, 3]                 # loads for crews of 1, 2, 3+
const STONE_COLOR  := Color(0.80, 0.74, 0.64)   # reads like the wall's textured limestone
const LABEL_RANGE  := 6.0
const LABEL_POLL   := 0.2
const DOOR_COLOR   := Color(0.42, 0.29, 0.17)
const BAR_COLOR    := Color(0.36, 0.30, 0.24)
const TARGET_COLOR := Color(0.86, 0.58, 0.22)
const WORK_TIME    := 2.5   # seconds for one worker to hang the doors / wall up the gap
const SOLO_WORK_MULT := 0.75

@onready var _pillars: Array = [$PillarLeft, $PillarRight]

var is_target := false:
	set(value):
		is_target = value
		if is_node_ready():
			_refresh()
var pending := 0:
	set(value):
		pending = value
		if is_node_ready():
			_update_label()
var finished := false:
	set(value):
		if value == finished:
			return
		finished = value
		if is_node_ready():
			if value:
				Sfx.play("build", global_position)
			_refresh()
			stage_changed.emit(1 if value else 0)

var _lintel: MeshInstance3D
var _doors: Node3D
var _infill: Node3D
var _door_body: StaticBody3D
var _footing: MeshInstance3D
var _label: Label3D
var _label_poll := 0.0
var _work: BuildWork

func _ready() -> void:
	_lintel = _box_mesh(LINTEL_SIZE, Vector3(0, LINTEL_Y + LINTEL_SIZE.y * 0.5, 0), Color(0.74, 0.65, 0.50))
	add_child(_lintel)
	_build_doors()
	_build_label()
	_work = BuildWork.new()
	_work.name = "Work"
	_work.position = Vector3(0, 3.0, 0)
	add_child(_work)
	_work.progress_changed.connect(_on_work_progress.unbind(1))
	_prime_work()
	GameState.crew_changed.connect(_prime_work.unbind(1))
	InputMode.changed.connect(_update_label.unbind(1))
	add_to_group("build_sites")
	_build_sync()
	for p in _pillars:
		p.stage_changed.connect(_refresh.unbind(1))
	GameState.section_changed.connect(_refresh.unbind(1))
	GameState.crew_changed.connect(_update_label.unbind(1))
	_refresh()

func _process(delta: float) -> void:
	_label_poll -= delta
	if _label_poll > 0.0:
		return
	_label_poll = LABEL_POLL
	_label.visible = _open_for_work() and _work.progress <= 0.0 and (is_target or _local_player_near())

# ── Build-site interface (server mutates) ──────────────────

func needs(kind: String) -> bool:
	return _open_for_work() and kind == _material() and pending < _cost()

func next_need() -> String:
	return _material() if needs(_material()) else ""

func deposit(kind: String, amount: int) -> bool:
	if not multiplayer.is_server() or not needs(kind):
		return false
	pending += amount
	return true

func can_build() -> bool:
	return _open_for_work() and pending >= _cost()

func try_build() -> bool:
	if not multiplayer.is_server() or not can_build():
		return false
	finished = true
	return true

## Done when doors hang / the gap is sealed — or at once when this section has no such step
func is_complete() -> bool:
	return finished or _material().is_empty()

func reset_slot() -> void:
	pending = 0
	finished = false
	_work.reset()

func repair(_fraction: float) -> void:
	pass

func distance_to_point(p: Vector3) -> float:
	var local := to_local(p)
	var half := OPENING * 0.5
	var clamped := local.clamp(-half, half)
	return Vector2(local.x - clamped.x, local.z - clamped.z).length()

func approach_point(from: Vector3, standoff: float) -> Vector3:
	var local := to_local(from)
	var half := OPENING * 0.5
	var clamped := local.clamp(-half, half)
	var side := signf(local.z) if local.z != 0.0 else 1.0
	var p := to_global(Vector3(clamped.x, 0.0, half.z * side + standoff * side))
	p.y = from.y
	return p

## What finishes this opening here: "wood" (doors), "stone" (infill) or "" (left open)
func _material() -> String:
	if not GameState.has_gate():
		return "stone"
	return "wood" if GameState.has_twist("doors") else ""

# The last step can start once both pillars stand finished
func _open_for_work() -> bool:
	return not _material().is_empty() and not finished \
		and _pillars.all(func(p): return p.is_complete())

func _cost() -> int:
	var cost: int = COST_BY_CREW[clampi(GameState.crew_size, 1, COST_BY_CREW.size()) - 1]
	return maxi(1, cost - 1) if GameState.active_build else cost

func work() -> BuildWork:
	return _work

func work_material() -> String:
	return _material() if not finished else ""

func _on_work_progress() -> void:
	_refresh()

func _prime_work() -> void:
	_work.work_time = WORK_TIME * (SOLO_WORK_MULT if GameState.crew_size == 1 else 1.0)

# ── Visuals ────────────────────────────────────────────────

## Every peer, at dusk: the new doors / infill take a bow with the wall
func celebrate() -> void:
	if not finished:
		return
	var leaf: Node3D = _doors if GameState.has_gate() else _infill
	leaf.scale = Vector3(1.04, 0.9, 1.04)
	create_tween().tween_property(leaf, "scale", Vector3.ONE, 0.45) 		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	DustFx.puff(self, global_position + Vector3.UP * 0.3, 16, 0.9)
	Sfx.play("deposit_beam", global_position)

func _refresh() -> void:
	var gate := GameState.has_gate()
	_lintel.visible = gate and _pillars.all(func(p): return p.stage == p.Stage.MORTARED)
	# While workers are at it the doors / infill go up plank by plank, stone by stone
	var working := not finished and _work.progress > 0.0
	_doors.visible = (finished or working) and gate
	_infill.visible = (finished or working) and not gate
	var fill := 1.0 if finished else _work.progress
	BuildWork.reveal(_doors, fill)
	BuildWork.reveal(_infill, fill)
	_door_body.get_child(0).set_deferred("disabled", not finished)
	_footing.visible = _open_for_work() and is_target
	_update_label()

# Two plank leaves with cross battens and a heavy bar across both
func _build_doors() -> void:
	_doors = Node3D.new()
	add_child(_doors)
	var leaf_w := OPENING.x * 0.5 - 0.03
	for side: float in [-1.0, 1.0]:
		var cx := side * (leaf_w * 0.5 + 0.015)
		for i in 4:
			var plank_w := leaf_w / 4.0
			var x := cx - leaf_w * 0.5 + plank_w * (i + 0.5)
			var v := (hash(Vector2(side, i)) % 7) * 0.008
			_doors.add_child(_box_mesh(Vector3(plank_w - 0.02, OPENING.y, 0.12), Vector3(x, OPENING.y * 0.5, 0),
				Color(DOOR_COLOR.r + v, DOOR_COLOR.g + v, DOOR_COLOR.b + v)))
		for y: float in [0.45, OPENING.y - 0.45]:
			_doors.add_child(_box_mesh(Vector3(leaf_w - 0.1, 0.14, 0.05), Vector3(cx, y, -0.09), DOOR_COLOR.darkened(0.2)))
	_doors.add_child(_box_mesh(Vector3(OPENING.x + 0.3, 0.16, 0.12), Vector3(0, OPENING.y * 0.55, -0.16), BAR_COLOR))
	# No gate here: the gap is walled up in courses matching the pillars
	_infill = Node3D.new()
	add_child(_infill)
	var rows := 4
	for r in rows:
		var h := OPENING.y / rows
		var stagger := 0.25 if r % 2 == 1 else 0.0
		var x := -OPENING.x * 0.5
		var i := 0
		while x < OPENING.x * 0.5 - 0.05:
			var w := minf(0.9 - (stagger if i == 0 else 0.0), OPENING.x * 0.5 - x)
			var v := (hash(Vector2(r, i)) % 9) * 0.01 - 0.04
			_infill.add_child(_box_mesh(Vector3(w - 0.05, h - 0.05, 0.9), Vector3(x + w * 0.5, h * (r + 0.5) + 0.1, 0),
				Color(STONE_COLOR.r + v, STONE_COLOR.g + v, STONE_COLOR.b + v)))
			x += w
			i += 1
	# Closed doors block movement like the wall
	_door_body = StaticBody3D.new()
	_door_body.collision_layer = 8
	_door_body.collision_mask = 4
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = OPENING
	shape.shape = box
	shape.position.y = OPENING.y * 0.5
	shape.disabled = true
	_door_body.add_child(shape)
	add_child(_door_body)
	# Amber footing in the opening when the doors are today's work
	_footing = _box_mesh(Vector3(OPENING.x, 0.04, 1.0), Vector3(0, 0.12, 0), TARGET_COLOR)
	add_child(_footing)

func _box_mesh(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	mi.material_override = mat
	return mi

# ── Label ──────────────────────────────────────────────────

func _build_label() -> void:
	_label = Label3D.new()
	UiStyle.world_label(_label, 40)
	_label.position = Vector3(0, 3.4, 0)
	_label.visible = false
	add_child(_label)

func _update_label() -> void:
	if _label == null:
		return
	var lines: PackedStringArray = []
	var what := "Hang the doors" if GameState.has_gate() else "Seal the gap"
	if GameState.active_build and can_build():
		lines.append("%s  [%s]" % [what, InputMode.key("interact")])
	else:
		lines.append("%s  ·  %s %d/%d" % [what, _material().capitalize(), mini(pending, _cost()), _cost()])
	_label.text = "\n".join(lines)

func _local_player_near() -> bool:
	return Player.local != null and distance_to_point(Player.local.global_position) < LABEL_RANGE

# ── Networking ─────────────────────────────────────────────

func _build_sync() -> void:
	NetworkManager.add_sync(self, [^".:pending", ^".:finished", ^".:is_target", ^"Work:progress"])
