extends Node
## Owns the wall blueprint registry — populated on ALL peers so ghost-block
## snapping works everywhere. Blueprint visuals are server-only.

var _blueprint_positions: Dictionary = {}
var _blueprint_meshes: Dictionary = {}   # server-only: key → MeshInstance3D

# ── Registry ──────────────────────────────────────────────────────────────────

func init_registry() -> void:
	_blueprint_positions.clear()
	# 12 historical gate/corner positions, clockwise from NW. Neh 3 circuit.
	# Scale: ~1 unit ≈ 15 m. City is pear-shaped (wide north, tapering south).
	var corners: Array[Vector3] = [
		Vector3(-16,  0, -30),  # NW  — Old Gate
		Vector3( -6,  0, -36),  # N   — Fish Gate
		Vector3(  6,  0, -36),  # NE  — Sheep Gate  (circuit start, Neh 3:1)
		Vector3( 20,  0, -28),  # NE  — Tower of Hananel / Miphkad Gate
		Vector3( 30,  0, -14),  # E   — East Gate (Neh 3:29)
		Vector3( 30,  0,   2),  # E   — Horse Gate / Water Gate (Neh 3:26-28)
		Vector3( 20,  0,  20),  # ESE — Fountain Gate (Neh 3:15)
		Vector3(  6,  0,  32),  # S   — toward Dung Gate
		Vector3( -4,  0,  36),  # S   — Dung Gate, southernmost tip (Neh 3:14)
		Vector3(-16,  0,  26),  # SW  — Valley Gate (Neh 2:13)
		Vector3(-28,  0,   8),  # W   — Tower of the Ovens / Broad Wall (Neh 3:11)
		Vector3(-28,  0, -14),  # WN  — back toward Old Gate
	]
	for i in range(corners.size()):
		_register_wall_edge(corners[i], corners[(i + 1) % corners.size()])

func _register_wall_edge(a: Vector3, b: Vector3) -> void:
	var edge := b - a
	var dir := edge.normalized()
	# +PI/2 puts the 2.0 long face along the wall (bricks laid sideways)
	var angle := atan2(dir.x, dir.z) + PI / 2.0
	# Step = 2.0 matches block long-face width so bricks tile without gaps
	const STEP: float = 2.0
	var count := int(ceil(edge.length() / STEP)) + 1
	for i in range(count):
		var pos := a + dir * (float(i) * STEP)
		var key := Vector3(snappedf(pos.x, 0.1), 0.0, snappedf(pos.z, 0.1))
		if not _blueprint_positions.has(key):
			_blueprint_positions[key] = angle

# ── Visuals (server-only) ─────────────────────────────────────────────────────

func spawn_visuals(parent: Node3D) -> void:
	var mat := _make_blueprint_material()
	for key in _blueprint_positions:
		_spawn_single_visual(key, _blueprint_positions[key], mat, parent)

func _spawn_single_visual(key: Vector3, angle: float, mat: StandardMaterial3D, parent: Node3D) -> void:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 0.05, 1.0)
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
		if is_instance_valid(mesh_node): mesh_node.queue_free()
		_blueprint_meshes.erase(key)

func restore_at(key: Vector3, angle: float, parent: Node3D) -> void:
	_blueprint_positions[key] = angle
	if multiplayer.is_server():
		_spawn_single_visual(key, angle, _make_blueprint_material(), parent)
