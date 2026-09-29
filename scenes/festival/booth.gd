class_name Booth
extends Node3D

# A booth for the Festival of Booths (Neh. 8:16): a marked square where branches are
# brought, then worked into a shelter — four poles, a lattice, a roof of leafy boughs.
# The build-site interface players use (see wall_section.gd), like WatchPost; never one
# of the day's units (is_target false). Solo festival: the server is the only peer.

signal raised

const COST      := 2      # boughs
const WORK_TIME := 2.5
const FOOT      := Vector3(2.4, 0.0, 2.4)
const POLE      := Color(0.52, 0.36, 0.20)
const MARK      := Color(0.62, 0.52, 0.36)
const LABEL_RANGE := 7.0

var is_target := false
var pending := 0
var built := false
## Where it stands, for the journal's line ("in the broad place", "in God's house")
var place := ""

var _work: BuildWork
var _mark: Node3D
var _shelter: Node3D
var _label: WorldTag

func _ready() -> void:
	add_to_group("build_sites")
	_mark = _build_mark()
	_shelter = _build_shelter()
	_shelter.visible = false
	_work = BuildWork.new()
	_work.name = "Work"
	_work.position = Vector3(0, 2.8, 0)
	_work.work_time = WORK_TIME
	add_child(_work)
	# The shelter goes up piece by piece while it's worked
	_work.progress_changed.connect(func(v: float):
		_shelter.visible = built or v > 0.0
		if v > 0.0:
			BuildWork.reveal(_shelter, v))
	_label = WorldTag.make(WorldTag.Kind.SITE)
	_label.position = Vector3(0, 2.6, 0)
	_label.clamp_to_screen = false   # five of them: no crowd of tags at the screen edge
	add_child(_label)
	_update_label()

func _process(_delta: float) -> void:
	var near := Player.local != null and distance_to_point(Player.local.global_position) < LABEL_RANGE
	_label.visible = not built and _work.progress <= 0.0
	_label.modulate.a = 1.0 if near else WorldTag.DIM

# ── Build-site interface ───────────────────────────────────

func needs(kind: String) -> bool:
	return not built and kind == "branch" and pending < COST

func next_need() -> String:
	return "branch" if needs("branch") else ""

func deposit(kind: String, _amount: int) -> bool:
	if not needs(kind):
		return false
	pending += 1
	_update_label()
	return true

func can_build() -> bool:
	return not built and pending >= COST

func try_build() -> bool:
	if not can_build():
		return false
	built = true
	_shelter.visible = true
	BuildWork.reveal(_shelter, 1.0)
	_mark.visible = false
	Sfx.play("build", global_position)
	DustFx.puff(self, global_position + Vector3(0, 1.0, 0), 10, 0.6)
	_update_label()
	raised.emit()
	return true

func is_complete() -> bool:
	return built

func blocks_workers() -> bool:
	return false

func refusal(kind: String) -> String:
	if built:
		return "This booth stands"
	return "The booth wants branches — from the olive trees outside the wall" if kind != "branch" \
		else "Branches enough — {interact} to build it"

func work() -> BuildWork:
	return _work

func work_material() -> String:
	return "branch" if can_build() else ""

func reset_slot() -> void:
	pass

func repair(_fraction: float) -> void:
	pass

func distance_to_point(p: Vector3) -> float:
	var local := to_local(p)
	var half := FOOT * 0.5
	var clamped := Vector3(clampf(local.x, -half.x, half.x), 0.0, clampf(local.z, -half.z, half.z))
	return Vector2(local.x - clamped.x, local.z - clamped.z).length()

func approach_point(from: Vector3, standoff: float) -> Vector3:
	var local := to_local(from)
	var half := FOOT * 0.5
	var clamped := Vector3(clampf(local.x, -half.x, half.x), 0.0, clampf(local.z, -half.z, half.z))
	var out := Vector3(local.x - clamped.x, 0.0, local.z - clamped.z)
	if out.length_squared() < 0.0001:
		out = Vector3(0, 0, 1)
	var at := to_global(clamped + out.normalized() * standoff)
	at.y = from.y
	return at

func _update_label() -> void:
	if _label == null:
		return
	_label.text = "Build  [%s]" % InputMode.key("interact") if can_build() \
		else "%s\nBranch %d/%d" % [tr("A booth"), pending, COST]

# ── Visuals ────────────────────────────────────────────────

# Before: four stakes and a scratched square on the ground
func _build_mark() -> Node3D:
	var parts := WatchPost._Parts.new()
	parts.add(Vector3(FOOT.x, 0.03, FOOT.z), Vector3(0, 0.12, 0), MARK)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			parts.add(Vector3(0.1, 0.4, 0.1), Vector3(sx * 1.05, 0.3, sz * 1.05), POLE)
	var mm := parts.build(Chunky.wood_material(0.02))
	add_child(mm)
	return mm

# After: poles, rails, a lattice roof thatched with boughs — pieces in the order they go
# up, so BuildWork.reveal shows it rising as it's worked
func _build_shelter() -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var h := 2.1
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var pole := WatchPost._Parts.new()
			pole.add(Vector3(0.12, h, 0.12), Vector3(sx * 1.05, 0.1 + h * 0.5, sz * 1.05), POLE)
			root.add_child(pole.build(Chunky.wood_material(0.02)))
	var rails := WatchPost._Parts.new()
	for sz: float in [-1.05, 0.0, 1.05]:
		rails.add(Vector3(2.3, 0.08, 0.08), Vector3(0, h + 0.1, sz), POLE.lightened(0.08))
	root.add_child(rails.build(Chunky.wood_material(0.02)))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name) + int(global_position.x * 10.0)
	for i in 9:
		var bough := DroppedItem.build_prop("branch")
		bough.position = Vector3(-0.9 + (i % 3) * 0.9, h + 0.22, -0.9 + (i / 3) * 0.9)
		bough.rotation.y = rng.randf() * TAU
		bough.scale = Vector3.ONE * 1.6
		root.add_child(bough)
	return root
