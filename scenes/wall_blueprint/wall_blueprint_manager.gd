extends Node
## Owns the wall blueprint registry. Populated on ALL peers.
## Translates historical WallData into a local 80x80 tactical map.

# ── Tactical Map Settings ──────────────────────────────────────────────────

const WORLD_SCALE: float = 3.0    # Scale historical units to game meters
const STEP: float = 10.0          # Meters per wall block

var _blueprint_positions: Dictionary = {}
var _blueprint_meshes: Dictionary = {}   # server-only: key → MeshInstance3D
var _context_visuals: Array[Dictionary] = [] # Array of {pos, angle, is_finished}
var _interior_direction: Vector3 = Vector3.BACK
var _endpoints: Array[Vector3] = []      # the two local endpoints for the current section
var _current_day: int = 1

# ── Registry ──────────────────────────────────────────────────────────────────

func get_section_for_day(day: int) -> Dictionary:
	for sec: Dictionary in WallData.SECTIONS:
		if day >= sec.day_start and day <= sec.day_end:
			return sec
	return WallData.SECTIONS[-1]

func get_interior_direction() -> Vector3:
	return _interior_direction

func get_section_center_for_day(_day: int) -> Vector3:
	return Vector3.ZERO

## Initialises blueprints for the given day's section. Called on ALL peers.
func init_registry_for_day(day: int) -> void:
	_current_day = day
	_blueprint_positions.clear()
	_context_visuals.clear()

	var sec = get_section_for_day(day)
	var a_idx = sec.a
	var b_idx = sec.b

	# 1. Get historical positions
	var hist_a = WallData.CORNERS[a_idx]
	var hist_b = WallData.CORNERS[b_idx]

	# 2. Calculate transform to center and rotate the section to horizontal
	var hist_dir = (hist_b - hist_a).normalized()
	var section_angle = atan2(hist_dir.x, hist_dir.z)

	# Local points: A is left (-X), B is right (+X)
	var dist = hist_a.distance_to(hist_b) * WORLD_SCALE
	var local_a = Vector3(-dist * 0.5, 0, 0)
	var local_b = Vector3(dist * 0.5, 0, 0)
	_endpoints = [local_a, local_b]

	_interior_direction = Vector3.BACK

	var is_gate: bool = sec.get("name", "").to_lower().contains("gate")
	_register_wall_edge(local_a, local_b, is_gate)

	# 3. Add "Folds" — show the previous and next segments as non-interactable visuals
	_register_context_segments(a_idx, b_idx, local_a, local_b, section_angle)

func _register_context_segments(a_idx: int, b_idx: int, local_a: Vector3, 
		local_b: Vector3, section_angle: float) -> void:
	# Show a bit of the previous section at the left end
	var prev_idx = (a_idx - 1 + WallData.CORNERS.size()) % WallData.CORNERS.size()
	var hist_prev = WallData.CORNERS[prev_idx]
	var hist_a = WallData.CORNERS[a_idx]
	var dir_prev = (hist_a - hist_prev).normalized()
	var angle_prev = atan2(dir_prev.x, dir_prev.z) - section_angle
	_spawn_visual_segment(local_a, angle_prev, false)

	# Show a bit of the next section at the right end
	var next_idx = (b_idx + 1) % WallData.CORNERS.size()
	var hist_next = WallData.CORNERS[next_idx]
	var hist_b = WallData.CORNERS[b_idx]
	var dir_next = (hist_next - hist_b).normalized()
	var angle_next = atan2(dir_next.x, dir_next.z) - section_angle
	_spawn_visual_segment(local_b, angle_next, true)

func _spawn_visual_segment(origin: Vector3, local_angle: float, is_next: bool) -> void:
	for i: int in range(1, 4):
		var dir = Vector3(sin(local_angle), 0, cos(local_angle))
		var sign = 1.0 if is_next else -1.0
		var pos: Vector3 = origin + dir * STEP * float(i) * sign
		_context_visuals.append({
			"pos": pos,
			"angle": local_angle,
			"is_finished": not is_next
		})

func _register_wall_edge(a: Vector3, b: Vector3, is_gate: bool = false) -> void:
	var edge := b - a
	var dir := edge.normalized()
	var angle := 0.0

	var count := int(floor(edge.length() / STEP))
	var offset = (edge.length() - (count * STEP)) * 0.5
	var middle_index = int(count / 2)

	for i: int in range(count + 1):
		if is_gate and i == middle_index:
			continue

		var pos: Vector3 = a + dir * (float(i) * STEP + offset)
		var snapped_x = snappedf(pos.x, 0.1)
		var snapped_z = snappedf(pos.z, 0.1)
		var key := Vector3(snapped_x, 0.0, snapped_z)
		if not _blueprint_positions.has(key):
			_blueprint_positions[key] = angle

# ── Visuals (server-only) ─────────────────────────────────────────────────────

func spawn_visuals(parent: Node3D) -> void:
	clear_visual_nodes()

	var blueprint_mat := _make_blueprint_material()
	for key: Vector3 in _blueprint_positions:
		_spawn_single_visual(key, _blueprint_positions[key], blueprint_mat, parent)

	var finished_mat := StandardMaterial3D.new()
	finished_mat.albedo_color = Color(0.7, 0.65, 0.6)
	finished_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var ruin_mat := StandardMaterial3D.new()
	ruin_mat.albedo_color = Color(0.3, 0.25, 0.2)
	ruin_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ruin_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ruin_mat.albedo_color.a = 0.5

	for visual: Dictionary in _context_visuals:
		var mesh_inst := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(STEP, 2.4 if visual.is_finished else 0.4, 1.0)
		mesh_inst.mesh = box
		mesh_inst.material_override = finished_mat if visual.is_finished else ruin_mat
		mesh_inst.position = visual.pos + Vector3(0, box.size.y * 0.5, 0)
		mesh_inst.rotation.y = visual.angle
		parent.add_child(mesh_inst)
		_blueprint_meshes[visual.pos] = mesh_inst

		var static_body := StaticBody3D.new()
		var col_shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = box.size
		col_shape.shape = box_shape
		static_body.add_child(col_shape)
		mesh_inst.add_child(static_body)

func _spawn_single_visual(key: Vector3, angle: float, 
		mat: StandardMaterial3D, parent: Node3D) -> void:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(STEP, 0.05, 1.0)
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

# ── Queries ───────────────────────────────────────────────────────

func get_blueprint_count() -> int:
	return _blueprint_positions.size()

func get_blueprint_positions() -> Dictionary:
	return _blueprint_positions

func get_nearest(world_pos: Vector3, max_dist: float) -> Vector3:
	var best_key := Vector3.INF
	var best_d2 := max_dist * max_dist
	var flat := Vector3(world_pos.x, 0.0, world_pos.z)
	for key: Vector3 in _blueprint_positions:
		var d2: float = flat.distance_squared_to(key)
		if d2 < best_d2:
			best_d2 = d2
			best_key = key
	return best_key

func get_angle(key: Vector3) -> float:
	return _blueprint_positions.get(key, 0.0)

# ── Mutations ─────────────────────────────────────────────────────────────────

func clear_all() -> void:
	clear_visual_nodes()
	_blueprint_positions.clear()
	_context_visuals.clear()
	_endpoints.clear()

func clear_visual_nodes() -> void:
	for key: Vector3 in _blueprint_meshes:
		var m: Node = _blueprint_meshes[key]
		if is_instance_valid(m):
			m.queue_free()
	_blueprint_meshes.clear()

func get_endpoints() -> Array[Vector3]:
	return _endpoints

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
