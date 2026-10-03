class_name RelayMat
extends Node3D

# The long haul ("haul" twist, Gate of the Ash Heaps): a reed mat halfway between the far yard and the
# wall. A load dropped on it is stacked in a free place instead of landing loose, so one
# worker can run the yard end and another the wall end. A porter works the second half: he
# carries what lies on the mat to the wall that wants it — when the mat is full, or a
# little after the first load lands. Loads on the mat stay ordinary dropped items until he
# lifts them: anyone may still take one with [E]. Every peer builds it.

const AT      := Vector3(15.0, 0.0, 7.5)   # between the Gate of the Ash Heaps yard (30, 9) and the gate
const SLOTS   := 6
const REACH   := 2.6       # a drop this close lands on the mat
const SLOT_GAP := 0.7
const NEAR := 8.0          # the mat explains itself to anyone this close

## Set once the first load has been left here, so the explaining toast shows once a session
static var told := false

const DROPPED_ITEM := preload("res://scenes/dropped_item/dropped_item.tscn")
const PORTER_EVERY := 15.0   # a trip leaves this long after the first load lands…
const PORTER_SPEED := 3.2    # …or at once when the mat is full; slower than a running worker
const PORTER_LOADS := 4      # what he can take in one trip (the mat holds SLOTS)
const PORTER_STOP  := 2.5    # he halts this far short of the wall's centre
const PORTER_LOOK := {
	"skin": Color(0.64, 0.46, 0.32), "robe": Color(0.56, 0.44, 0.28), "trim": Color(0.34, 0.25, 0.14),
	"sash": Color(0.70, 0.40, 0.22), "hat": "wrap", "hat_color": Color(0.84, 0.76, 0.54), "tool": false,
	"band": Color(0.70, 0.40, 0.22), "beard": "short", "hair": Color(0.14, 0.10, 0.07),
	"outline": Color(0.22, 0.15, 0.08),
}

# The porter: the server decides when a trip leaves and what it carries (the loads leave the
# mat), then every peer walks the same trip locally; the server hands the loads to the wall
# when he arrives. Nothing here is replicated except the one trip call.
enum Leg { HOME, OUT, BACK }

var _label: WorldTag
var _hint: WorldTag
var _porter: Node3D
var _rig: CharacterRig
var _cargo: Node3D
var _leg := Leg.HOME
var _dest := Vector3.ZERO
var _kinds: Array = []
var _site: Node3D
var _timer := 0.0
var _facing := "down"

func _ready() -> void:
	position = AT
	_build()
	_build_porter()
	GameState.section_changed.connect(_refresh.unbind(1))
	GameState.phase_changed.connect(_on_phase_changed)
	_refresh()

func _refresh() -> void:
	var on := GameState.has_twist("haul")
	visible = on
	if on:
		add_to_group("relay_mats")
	elif is_in_group("relay_mats"):
		remove_from_group("relay_mats")
	if not on:
		_reset_porter()

## Stack places, world space, in fill order
func slots() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in SLOTS:
		out.append(global_position + Vector3((i % 3 - 1) * SLOT_GAP, 0.1, (i / 3 - 0.5) * SLOT_GAP))
	return out

## The first place no load lies on, or Vector3.INF when the mat is full
func free_slot() -> Vector3:
	var items := get_tree().get_nodes_in_group("dropped_items")
	for s in slots():
		if not items.any(func(it: Node3D): return Vector2(it.global_position.x - s.x, it.global_position.z - s.z).length() < SLOT_GAP * 0.45):
			return s
	return Vector3.INF

func loads() -> int:
	var n := 0
	for it: Node3D in get_tree().get_nodes_in_group("dropped_items"):
		if Vector2(it.global_position.x - global_position.x, it.global_position.z - global_position.z).length() < SLOT_GAP * 1.6:
			n += 1
	return n

func _process(delta: float) -> void:
	if not visible or _label == null:
		return
	_label.text = tr("Relay mat  %d/%d") % [loads(), SLOTS]
	_hint.visible = Player.local != null and Player.local.global_position.distance_to(global_position) < NEAR
	if _hint.visible:
		_hint.text = _hint_text(loads())
	if _leg != Leg.HOME:
		_walk(delta)
	elif multiplayer.is_server() and GameState.phase == GameState.Phase.WORK:
		_dispatch(delta)

## What the mat tells whoever stands near it: what it is for, then what the porter is doing
func _hint_text(n: int) -> String:
	if _leg == Leg.OUT:
		return tr("The porter is carrying them to the wall")
	if _leg == Leg.BACK:
		return tr("The porter walks back for more")
	if n > 0:
		return tr("The porter will carry these to the wall")
	return tr("Drop loads here — a porter carries them to the wall")

## Server: a trip leaves when the mat is full, or PORTER_EVERY after the first load landed
func _dispatch(delta: float) -> void:
	var n := loads()
	if n == 0:
		_timer = 0.0
		return
	_timer += delta
	if (n >= SLOTS and _timer >= 0.0) or _timer >= PORTER_EVERY:
		# Nothing a wall wants yet: look again in a few seconds, not every frame
		_timer = 0.0 if _send_porter() else -5.0

## The nearest wall (or gate door) that still wants `kind`
func _site_for(kind: String) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for s: Node3D in get_tree().get_nodes_in_group("build_sites"):
		if s.needs(kind) and s.global_position.distance_to(global_position) < best_d:
			best_d = s.global_position.distance_to(global_position)
			best = s
	return best

# Server: lift the loads some wall wants off the mat and send them off. One wall per trip —
# the one that wants the first load; a surplus is set down beside it on arrival.
func _send_porter() -> bool:
	var kinds: Array = []
	var site: Node3D = null
	for it: Node3D in get_tree().get_nodes_in_group("dropped_items"):
		if kinds.size() >= PORTER_LOADS:
			break
		if it.kind == "beam" or Vector2(it.global_position.x - global_position.x,
				it.global_position.z - global_position.z).length() >= SLOT_GAP * 1.6:
			continue
		if site == null:
			site = _site_for(it.kind)
		if site == null or not site.needs(it.kind):
			continue
		if it.take():
			kinds.append(it.kind)
	if kinds.is_empty():
		return false
	var to := site.global_position - global_position
	to.y = 0.0
	_site = site
	_porter_go.rpc(site.global_position - to.normalized() * PORTER_STOP, kinds)
	return true

@rpc("authority", "call_local", "reliable")
func _porter_go(dest: Vector3, kinds: Array) -> void:
	_dest = dest
	_kinds = kinds
	_leg = Leg.OUT
	_porter.global_position = _home_stand()
	_porter.visible = true
	for c in _cargo.get_children():
		c.queue_free()
	for i in kinds.size():
		var prop := DroppedItem.build_prop(kinds[i])
		prop.scale = Vector3.ONE * 0.6
		prop.position.y = i * 0.2
		_cargo.add_child(prop)

func _home_stand() -> Vector3:
	return global_position + Vector3(0, 0, SLOT_GAP * 1.6)

func _walk(delta: float) -> void:
	var goal := _dest if _leg == Leg.OUT else _home_stand()
	var step := goal - _porter.global_position
	step.y = 0.0
	if step.length() < 0.1:
		_arrive()
		return
	_facing = CharAnim.dir_from_velocity(step, _facing)
	_rig.play("walk_" + _facing)
	_porter.global_position += step.normalized() * minf(step.length(), PORTER_SPEED * delta)

func _arrive() -> void:
	if _leg == Leg.OUT:
		for c in _cargo.get_children():
			c.queue_free()
		if multiplayer.is_server():
			_deliver()
		_leg = Leg.BACK
	else:
		_reset_porter()

# Server: hand the loads to the wall; what it no longer wants is set down beside it
func _deliver() -> void:
	var given := 0
	for k: String in _kinds:
		if is_instance_valid(_site) and _site.deposit(k, 1):
			given += 1
		else:
			_spawn_item(k, _dest + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6)))
	_kinds = []
	if given > 0 and is_instance_valid(_site) and _site.can_build() and not GameState.active_build:
		_site.try_build()

func _spawn_item(kind: String, at: Vector3) -> void:
	var items := get_parent().get_node_or_null("Items")
	if items == null:
		return
	var item: DroppedItem = DROPPED_ITEM.instantiate()
	item.kind = kind
	item.position = Vector3(at.x, 0.1, at.z)
	NetworkManager.gate_sync(item.get_node("MultiplayerSynchronizer"))
	items.add_child(item, true)

func _reset_porter() -> void:
	if multiplayer.is_server():
		for k: String in _kinds:   # the day ended mid-trip: the loads stay where he stood
			_spawn_item(k, _porter.global_position)
	_kinds = []
	_leg = Leg.HOME
	_timer = 0.0
	if _porter != null:
		_porter.visible = false
		_rig.play("idle_down")
		for c in _cargo.get_children():
			c.queue_free()

func _on_phase_changed(phase: GameState.Phase) -> void:
	if phase != GameState.Phase.WORK and _leg != Leg.HOME:
		_reset_porter()

func _build_porter() -> void:
	_porter = Node3D.new()
	_porter.visible = false
	add_child(_porter)
	_rig = CharacterRig.new()
	_porter.add_child(_rig)
	_rig.setup(PORTER_LOOK)
	_cargo = Node3D.new()
	_cargo.position.y = 1.5
	_porter.add_child(_cargo)

func _build() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.70, 0.58, 0.36)
	mat.roughness = 0.95
	var mesh := BoxMesh.new()
	mesh.size = Vector3(SLOT_GAP * 3.4, 0.06, SLOT_GAP * 2.4)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position.y = 0.1
	add_child(mi)
	# Woven edge: a darker rim
	var rim := StandardMaterial3D.new()
	rim.albedo_color = Color(0.46, 0.36, 0.20)
	for side: float in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(SLOT_GAP * 3.4, 0.08, 0.1)
		e.mesh = b
		e.material_override = rim
		e.position = Vector3(0, 0.11, side * SLOT_GAP * 1.2)
		add_child(e)
	_label = WorldTag.make(WorldTag.Kind.STATION, "")
	_label.position.y = 1.6
	add_child(_label)
	_hint = WorldTag.make(WorldTag.Kind.NOTE, "")
	_hint.position.y = 2.4
	_hint.visible = false
	add_child(_hint)
