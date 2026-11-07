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
const STONE_COLOR  := Palette.WALL_STONE         # the pillars' limestone
const IRON_COLOR   := Color(0.21, 0.20, 0.22)
const LABEL_RANGE  := 6.0
const LABEL_POLL   := 0.2
const DOOR_COLOR   := Color(0.42, 0.29, 0.17)
const BAR_COLOR    := Color(0.36, 0.30, 0.24)
const TARGET_COLOR := Color(0.86, 0.58, 0.22)
const WORK_TIME    := 2.5   # seconds for one worker to hang the doors / wall up the gap
const SOLO_WORK_MULT := 0.75
const DOOR_LAYER   := 16   # enemies-only wall
const WALL_LAYER   := 8

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

var _lintel: Node3D   # the stone over the opening, its threshold and the torch brackets: up once both pillars are
var _doors: Node3D
var _infill: Node3D
var _door_body: StaticBody3D
var _footing: MeshInstance3D
var _label: WorldTag
var _label_poll := 0.0
var _work: BuildWork

func _ready() -> void:
	_build_lintel()
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
	var near := _local_player_near()
	_label.visible = not GameState.festival and _open_for_work() and _work.progress <= 0.0 and (is_target or near)
	var focus := SiteFocus.site() == self
	_label.pulse = focus
	_label.modulate.a = 1.0 if focus or near else WorldTag.DIM

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

## Sealed infill is climbed like the wall; hung doors let workers straight through
func blocks_workers() -> bool:
	return finished and not GameState.has_gate()

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
	var cost: int = COST_BY_CREW[clampi(GameState.cost_crew(), 1, COST_BY_CREW.size()) - 1]
	return maxi(1, cost - 1) if GameState.active_build else cost

func work() -> BuildWork:
	return _work

func work_material() -> String:
	return _material() if not finished else ""

func _on_work_progress() -> void:
	_refresh()

func _prime_work() -> void:
	_work.work_time = WORK_TIME * GameState.solo_mult(SOLO_WORK_MULT)

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
	_door_body.collision_layer = DOOR_LAYER if gate else WALL_LAYER   # stone infill is wall
	_footing.visible = _open_for_work() and is_target and not GameState.attract
	_update_label()

# Two plank leaves, each braced and strapped, with a heavy bar across both on the city
# side (+z; the foe comes from -z) and a head beam under the lintel. Parts are batched into
# a wood and an iron multimesh so BuildWork.reveal still raises them plank by plank.
func _build_doors() -> void:
	_doors = Node3D.new()
	add_child(_doors)
	var wood: Array = []
	var iron: Array = []
	var leaf_w := OPENING.x * 0.5 - 0.03
	var h := OPENING.y
	const PLANKS := 5
	for side: float in [-1.0, 1.0]:
		var cx := side * (leaf_w * 0.5 + 0.015)
		var pw := leaf_w / PLANKS
		for i in PLANKS:
			var x := cx - leaf_w * 0.5 + pw * (i + 0.5)
			var v := (hash(Vector2(side, i)) % 7) * 0.008
			var trim := (hash(Vector2(i, side * 3.0)) % 5) * 0.02   # tops cut a hand off true, under the head beam
			_part(wood, Vector3(pw - 0.02, h - trim, 0.12), Vector3(x, (h - trim) * 0.5, 0), _tone(DOOR_COLOR, v))
	for side: float in [-1.0, 1.0]:
		var cx := side * (leaf_w * 0.5 + 0.015)
		for y: float in [0.45, h - 0.45]:
			for z: float in [-0.09, 0.09]:
				_part(wood, Vector3(leaf_w - 0.1, 0.14, 0.05), Vector3(cx, y, z), DOOR_COLOR.darkened(0.2))
		# Diagonal brace on the city side, from the hinge foot up to the meeting stile
		var foot := Vector2(cx + side * (leaf_w * 0.5 - 0.12), 0.45)
		var head := Vector2(cx - side * (leaf_w * 0.5 - 0.12), h - 0.45)
		var run := head - foot
		var brace := Basis(Vector3.BACK, atan2(run.y, run.x))
		_part(wood, Vector3(run.length(), 0.13, 0.04), Vector3((foot.x + head.x) * 0.5, (foot.y + head.y) * 0.5, 0.135), DOOR_COLOR.darkened(0.12), brace)
	_part(wood, Vector3(0.08, h - 0.1, 0.2), Vector3(0, (h - 0.1) * 0.5, 0), DOOR_COLOR.darkened(0.25))   # covers the seam between the leaves
	_part(wood, Vector3(OPENING.x + 0.3, 0.16, 0.12), Vector3(0, h * 0.55, 0.22), BAR_COLOR)
	_part(wood, Vector3(OPENING.x + 0.2, 0.2, 0.3), Vector3(0, h - 0.1, 0), DOOR_COLOR.darkened(0.1))
	# Iron: a strap across each batten with a row of studs, a ring pull at the stile, a
	# cap on the hinge end, brackets cradling the bar
	for side: float in [-1.0, 1.0]:
		var cx := side * (leaf_w * 0.5 + 0.015)
		for y: float in [0.45, h - 0.45]:
			for face: float in [-1.0, 1.0]:
				var z := face * (0.17 if face > 0.0 else 0.12)
				_part(iron, Vector3(leaf_w * 0.92, 0.07, 0.03), Vector3(cx, y, z), IRON_COLOR)
				_part(iron, Vector3(0.14, 0.12, 0.05), Vector3(side * (OPENING.x * 0.5 - 0.1), y, z), IRON_COLOR.lightened(0.04))
				for k in 5:
					_part(iron, Vector3(0.05, 0.05, 0.04), Vector3(cx - leaf_w * 0.36 + k * leaf_w * 0.18, y, z + face * 0.02), IRON_COLOR.lightened(0.1))
		_part(iron, Vector3(0.12, 0.12, 0.03), Vector3(side * 0.16, 1.05, 0.19), IRON_COLOR)
		for ring: Array in [[Vector3(0.16, 0.03, 0.03), Vector3(0, 0.07, 0)], [Vector3(0.16, 0.03, 0.03), Vector3(0, -0.07, 0)],
				[Vector3(0.03, 0.17, 0.03), Vector3(-0.065, 0, 0)], [Vector3(0.03, 0.17, 0.03), Vector3(0.065, 0, 0)]]:
			_part(iron, ring[0], Vector3(side * 0.16, 0.98, 0.215) + ring[1], IRON_COLOR.lightened(0.08))
		_part(iron, Vector3(0.2, 0.28, 0.2), Vector3(side * (OPENING.x * 0.5 + 0.02), h * 0.55, 0.22), IRON_COLOR)
	_blocks(_doors, wood, Chunky.wood_material(0.02))
	_blocks(_doors, iron, Chunky.material(0.015, false, 0.3))
	# No gate here: the gap is walled up in courses matching the pillars
	_infill = Node3D.new()
	add_child(_infill)
	var courses: Array = []
	var rows := 4
	for r in rows:
		var rh := OPENING.y / rows
		var stagger := 0.25 if r % 2 == 1 else 0.0
		var x := -OPENING.x * 0.5
		var i := 0
		while x < OPENING.x * 0.5 - 0.05:
			var w := minf(0.9 - (stagger if i == 0 else 0.0), OPENING.x * 0.5 - x)
			var v := (hash(Vector2(r, i)) % 9) * 0.01 - 0.04
			_part(courses, Vector3(w - 0.05, rh - 0.05, 0.9), Vector3(x + w * 0.5, rh * (r + 0.5) + 0.1, 0), _tone(STONE_COLOR, v))
			x += w
			i += 1
	_blocks(_infill, courses, Chunky.stone_material(0.07))
	# Closed doors block enemies like the wall, but open for workers (layer 16 is in the
	# enemies' and the nav bake's mask, not the players') — nobody gets shut outside
	_door_body = StaticBody3D.new()
	_door_body.collision_layer = DOOR_LAYER
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

## Over the opening, from the same stone as the pillars: three lintel stones, a cornice
## with dentils, an inscription plaque, the threshold flags and a torch bracket on each
## pillar. Both faces are dressed (the foe's, -z, and the city's, +z).
func _build_lintel() -> void:
	_lintel = Node3D.new()
	add_child(_lintel)
	var stone: Array = []
	var dark: Array = []
	var fit: Array = []
	var x := -LINTEL_SIZE.x * 0.5
	var k := 0
	for w: float in [1.1, 1.2, 1.1]:
		_part(stone, Vector3(w - 0.03, LINTEL_SIZE.y, LINTEL_SIZE.z), Vector3(x + w * 0.5, LINTEL_Y + LINTEL_SIZE.y * 0.5, 0), _tone(STONE_COLOR, _jit(k)))
		x += w
		k += 1
	# Coping over it in five stones, a shade darker than the lintel so it does not glare from above
	for i in 5:
		_part(stone, Vector3(0.74, 0.12, LINTEL_SIZE.z + 0.12), Vector3(-1.6 + i * 0.8, LINTEL_Y + LINTEL_SIZE.y + 0.06, 0), _tone(STONE_COLOR, -0.05 + _jit(i + 10) * 0.6))
	for face: float in [-1.0, 1.0]:
		for i in 10:
			_part(stone, Vector3(0.15, 0.1, 0.06), Vector3(-1.5 + i * (3.0 / 9.0), LINTEL_Y + LINTEL_SIZE.y - 0.06, face * (LINTEL_SIZE.z * 0.5 + 0.02)), _tone(STONE_COLOR, 0.05 + _jit(i + 20) * 0.5))
		_part(dark, Vector3(0.8, 0.26, 0.04), Vector3(0, LINTEL_Y + 0.27, face * (LINTEL_SIZE.z * 0.5 + 0.005)), Palette.STONE_JOINT)
		_part(stone, Vector3(0.17, 0.17, 0.03), Vector3(0, LINTEL_Y + 0.27, face * (LINTEL_SIZE.z * 0.5 + 0.03)), _tone(STONE_COLOR, 0.04), Basis(Vector3.BACK, PI * 0.25))
	# Threshold flags, worn a shade darker down the middle where the carts run
	for i in 5:
		var worn := 0.045 if absi(i - 2) <= 1 else 0.0
		_part(stone, Vector3(0.62, 0.18, LINTEL_SIZE.z), Vector3(-1.2 + i * 0.6, 0.08, 0), _tone(STONE_COLOR, _jit(i + 40) - worn - 0.03))
	# Torch brackets on the city face of each pillar: an iron arm, a cup, a wrapped brand
	for side: float in [-1.0, 1.0]:
		var tx := side * 1.95
		var tz := LINTEL_SIZE.z * 0.5
		_part(fit, Vector3(0.05, 0.05, 0.26), Vector3(tx, 1.95, tz + 0.12), IRON_COLOR)
		_part(fit, Vector3(0.16, 0.06, 0.16), Vector3(tx, 1.9, tz + 0.26), IRON_COLOR)
		_part(fit, Vector3(0.07, 0.4, 0.07), Vector3(tx, 2.1, tz + 0.26), BAR_COLOR.darkened(0.1))
		_part(fit, Vector3(0.11, 0.14, 0.11), Vector3(tx, 2.33, tz + 0.26), Color(0.16, 0.12, 0.09))
	_blocks(_lintel, stone, Chunky.stone_material(0.05))
	_blocks(_lintel, dark, Chunky.material(0.0, false, 0.0))
	_blocks(_lintel, fit, Chunky.material(0.015, false, 0.3))

## Append one block (size, centre, colour, optional rotation) to a parts list
func _part(parts: Array, size: Vector3, pos: Vector3, color: Color, rot := Basis.IDENTITY) -> void:
	parts.append([Transform3D(rot * Basis.from_scale(size), pos), color])

func _tone(c: Color, v: float) -> Color:
	return Color(c.r + v, c.g + v, c.b + v)

## A fixed shade off true for stone number `k`, so every gate is cut the same
func _jit(k: int) -> float:
	return (hash(Vector2(k, 5)) % 9) * 0.012 - 0.05

## A multimesh of unit blocks, one instance per part. Instances show in the order given.
func _blocks(parent: Node3D, parts: Array, mat: Material) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = Chunky.unit_block()
	mm.instance_count = parts.size()
	for i in parts.size():
		mm.set_instance_transform(i, parts[i][0])
		mm.set_instance_color(i, parts[i][1])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	parent.add_child(mmi)

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
	_label = WorldTag.make(WorldTag.Kind.SITE)
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
