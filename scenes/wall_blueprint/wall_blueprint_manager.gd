extends Node
## Owns the wall blueprint registry — populated on ALL peers so ghost-block
## snapping works everywhere. Blueprint visuals are server-only.

# ── Wall geometry ──────────────────────────────────────────────────────────────

## 12 gate/corner positions clockwise, scale ~1 unit = 15 m. Pear-shaped city.
const CORNERS: Array[Vector3] = [
	Vector3(-16,  0, -30),  # 0  NW  — Old/Jeshanah Gate
	Vector3( -6,  0, -36),  # 1  N   — Fish Gate
	Vector3(  6,  0, -36),  # 2  NE  — Sheep Gate  (Neh 3:1 start)
	Vector3( 20,  0, -28),  # 3  NE  — Tower of Hananel / Miphkad Gate
	Vector3( 30,  0, -14),  # 4  E   — East Gate
	Vector3( 30,  0,   2),  # 5  E   — Horse Gate / Water Gate
	Vector3( 20,  0,  20),  # 6  SE  — Fountain Gate
	Vector3(  6,  0,  32),  # 7  S   — toward Dung Gate
	Vector3( -4,  0,  36),  # 8  S   — Dung Gate (southernmost)
	Vector3(-16,  0,  26),  # 9  SW  — Valley Gate
	Vector3(-28,  0,   8),  # 10 W   — Tower of Ovens / Broad Wall
	Vector3(-28,  0, -14),  # 11 WN  — Broad Wall north end
]

## 12 playable sections in Nehemiah 3 narrative order.
## "a"/"b" are CORNERS indices for the two endpoints.
## "day_start"/"day_end" are inclusive. Total = 52 days.
const SECTIONS: Array[Dictionary] = [
	{
		"name": "Sheep Gate", "neh": "3:1-2", "a": 2, "b": 3, "day_start": 1, "day_end": 4,
		"quote": "Eliashib the high priest arose with his brothers the priests and built the Sheep Gate."
	},
	{
		"name": "Fish Gate", "neh": "3:3-5", "a": 1, "b": 2, "day_start": 5, "day_end": 8,
		"quote": "The sons of Hassenaah built the Fish Gate with its beams and doors."
	},
	{
		"name": "Jeshanah Gate", "neh": "3:6-12", "a": 0, "b": 1, "day_start": 9, "day_end": 12,
		"quote": "Joiada and Meshullam repaired the Jeshanah Gate; goldsmiths worked alongside."
	},
	{
		"name": "Broad Wall", "neh": "3:8", "a": 11, "b": 0, "day_start": 13, "day_end": 17,
		"quote": "They restored Jerusalem as far as the Broad Wall."
	},
	{
		"name": "Tower of Ovens", "neh": "3:11-12", "a": 10, "b": 11, "day_start": 18, "day_end": 23,
		"quote": "Malkijah and Hasshub repaired another section and the Tower of Ovens."
	},
	{
		"name": "Valley Gate", "neh": "3:13", "a": 9, "b": 10, "day_start": 24, "day_end": 29,
		"quote": "Hanun and the inhabitants of Zanoah repaired the Valley Gate."
	},
	{
		"name": "Dung Gate", "neh": "3:13-14", "a": 8, "b": 9, "day_start": 30, "day_end": 33,
		"quote": "Malchijah son of Rechab repaired the Dung Gate; he rebuilt it and set its doors."
	},
	{
		"name": "Fountain Gate", "neh": "3:15", "a": 7, "b": 8, "day_start": 34, "day_end": 36,
		"quote": "Shallun repaired the Fountain Gate; he built it and covered it, and set its doors."
	},
	{
		"name": "Water Gate & Ophel", "neh": "3:26-27", "a": 6, "b": 7, "day_start": 37, "day_end": 41,
		"quote": "The temple servants living on Ophel made repairs as far as the Water Gate."
	},
	{
		"name": "Horse Gate", "neh": "3:28", "a": 5, "b": 6, "day_start": 42, "day_end": 47,
		"quote": "Above the Horse Gate the priests made repairs, each one opposite his own house."
	},
	{
		"name": "East Gate", "neh": "3:29", "a": 4, "b": 5, "day_start": 48, "day_end": 50,
		"quote": "Zadok son of Immer made repairs opposite his own house."
	},
	{
		"name": "Miphkad Gate", "neh": "3:31-32", "a": 3, "b": 4, "day_start": 51, "day_end": 52,
		"quote": "Goldsmiths and merchants completed the circuit, from the Miphkad Gate."
	},
]

var _blueprint_positions: Dictionary = {}
var _blueprint_meshes: Dictionary = {}   # server-only: key → MeshInstance3D
var _interior_direction: Vector3 = Vector3.BACK
var _endpoints: Array[Vector3] = []      # the two scaled corner positions for the current day

# ── Registry ──────────────────────────────────────────────────────────────────

## Returns the section dict for a given day number (1-52).
func get_section_for_day(day: int) -> Dictionary:
	for sec in SECTIONS:
		if day >= sec.day_start and day <= sec.day_end:
			return sec
	return SECTIONS[-1]

func get_interior_direction() -> Vector3:
	return _interior_direction

## Returns the world midpoint of the current section — (0,0,0) in local map space.
func get_section_center_for_day(_day: int) -> Vector3:
	return Vector3.ZERO

## Initialises blueprints for the given day's section only. Called on ALL peers.
func init_registry_for_day(day: int) -> void:
	_blueprint_positions.clear()
	var sec: Dictionary = get_section_for_day(day)

	var a: Vector3 = CORNERS[sec.a]
	var b: Vector3 = CORNERS[sec.b]
	var midpoint: Vector3 = (a + b) * 0.5

	# Interior is towards the original city center (0,0,0)
	_interior_direction = -midpoint.normalized()
	if _interior_direction == Vector3.ZERO:
		_interior_direction = Vector3.BACK

	# Scale section to span ~70 units of the 80-unit map
	var length: float = a.distance_to(b)
	var scale_factor: float = 70.0 / max(1.0, length)

	var local_a: Vector3 = (a - midpoint) * scale_factor
	var local_b: Vector3 = (b - midpoint) * scale_factor

	_endpoints = [local_a, local_b]

	var section_name: String = sec.get("name", "")
	var is_gate: bool = section_name.to_lower().contains("gate")

	_register_wall_edge(local_a, local_b, is_gate)

## Initialises blueprints for the entire wall circuit (editor / debug use).
func init_registry() -> void:
	_blueprint_positions.clear()
	for i in range(CORNERS.size()):
		_register_wall_edge(CORNERS[i], CORNERS[(i + 1) % CORNERS.size()])

## Removes all visuals from the scene tree (server only) and clears registries.
func clear_all() -> void:
	for key in _blueprint_meshes:
		var m: Node = _blueprint_meshes[key]
		if is_instance_valid(m):
			m.queue_free()
	_blueprint_meshes.clear()
	_blueprint_positions.clear()
	_endpoints.clear()

func get_endpoints() -> Array[Vector3]:
	return _endpoints

func _register_wall_edge(a: Vector3, b: Vector3, is_gate: bool = false) -> void:
	var edge := b - a
	var dir := edge.normalized()
	var angle := atan2(dir.x, dir.z) + PI / 2.0
	const STEP: float = 10.0
	var count := int(ceil(edge.length() / STEP)) + 1
	var middle_index = int(count / 2)

	for i in range(count):
		if is_gate and i == middle_index:
			# Skip the middle index for now to leave a physical gap (the gate)
			continue

		var pos := a + dir * (float(i) * STEP)
		var snapped_x = snappedf(pos.x, 0.1)
		var snapped_z = snappedf(pos.z, 0.1)
		var key := Vector3(snapped_x, 0.0, snapped_z)
		if not _blueprint_positions.has(key):
			_blueprint_positions[key] = angle

# ── Visuals (server-only) ─────────────────────────────────────────────────────

func spawn_visuals(parent: Node3D) -> void:
	var mat := _make_blueprint_material()
	for key in _blueprint_positions:
		_spawn_single_visual(key, _blueprint_positions[key], mat, parent)

func _spawn_single_visual(
	key: Vector3,
	angle: float,
	mat: StandardMaterial3D,
	parent: Node3D
) -> void:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(10.0, 0.05, 1.0)
	mesh_inst.mesh = box
	mesh_inst.material_override = mat
	mesh_inst.position = Vector3(key.x, 0.51, key.z)
	mesh_inst.rotation.y = angle
	parent.add_child(mesh_inst)
	_blueprint_meshes[key] = mesh_inst

func _make_blueprint_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.6, 1.0, 0.18)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

# ── Queries (all peers) ───────────────────────────────────────────────────────

func get_nearest(world_pos: Vector3, max_dist: float) -> Vector3:
	var best_key := Vector3.INF
	var best_d2 := max_dist * max_dist
	var flat := Vector3(world_pos.x, 0.0, world_pos.z)
	for key in _blueprint_positions:
		var d2: float = flat.distance_squared_to(key)
		if d2 < best_d2:
			best_d2 = d2
			best_key = key
	return best_key

func get_angle(key: Vector3) -> float:
	return _blueprint_positions.get(key, 0.0)

# ── Mutations ─────────────────────────────────────────────────────────────────

func erase_at(key: Vector3) -> void:
	_blueprint_positions.erase(key)
	if _blueprint_meshes.has(key):
		var mesh_node: Node = _blueprint_meshes[key]
		if is_instance_valid(mesh_node):
			mesh_node.queue_free()
		_blueprint_meshes.erase(key)

func restore_at(key: Vector3, angle: float, parent: Node3D) -> void:
	_blueprint_positions[key] = angle
	if multiplayer.is_server():
		var mat = _make_blueprint_material()
		_spawn_single_visual(key, angle, mat, parent)
