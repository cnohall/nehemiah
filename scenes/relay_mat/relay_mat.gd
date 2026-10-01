class_name RelayMat
extends Node3D

# The long haul ("haul" twist, Dung Gate): a reed mat halfway between the far yard and the
# wall. A load dropped on it is stacked in a free place instead of landing loose, so one
# worker can run the yard end and another the wall end — the relay is a choice the crew
# makes (who hauls, who builds), not just a longer walk. Loads on it are ordinary dropped
# items: anyone takes them with [E]. Every peer builds it; nothing replicated.

const AT      := Vector3(15.0, 0.0, 7.5)   # between the Dung Gate yard (30, 9) and the gate
const SLOTS   := 6
const REACH   := 2.6       # a drop this close lands on the mat
const SLOT_GAP := 0.7

var _label: WorldTag

func _ready() -> void:
	position = AT
	_build()
	GameState.section_changed.connect(_refresh.unbind(1))
	_refresh()

func _refresh() -> void:
	var on := GameState.has_twist("haul")
	visible = on
	if on:
		add_to_group("relay_mats")
	elif is_in_group("relay_mats"):
		remove_from_group("relay_mats")

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

func _process(_delta: float) -> void:
	if visible and _label != null:
		_label.text = tr("Relay mat  %d/%d") % [loads(), SLOTS]

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
