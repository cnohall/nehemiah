extends Node
## Manages wall sections, completion tracking, and construction.
## Server-authoritative.

signal blocks_changed(total: int)
signal wall_complete
signal navigation_changed

const WALL_SECTION_SCENE: PackedScene = preload("res://scenes/building_block/wall_section.tscn")

var blocks_placed: int = 0
var blocks_for_win: int = 0
var _is_setting_up: bool = false
var _blocks: Node3D = null
var _players: Node3D = null
var _blueprint_mgr: Node = null

# Exposed for minimap (accessed via main._blueprint_positions getter)
var _blueprint_positions: Dictionary:
	get:
		var empty: Dictionary = {}
		return _blueprint_mgr._blueprint_positions if _blueprint_mgr else empty

func _ready() -> void:
	_ensure_references()

	_blueprint_mgr = load("res://scenes/wall_blueprint/wall_blueprint_manager.gd").new()
	_blueprint_mgr.name = "WallBlueprintManager"
	add_child(_blueprint_mgr)
	_blueprint_mgr.init_registry_for_day(1)
	blocks_for_win = _blueprint_mgr._blueprint_positions.size()

	# Sections are spawned by main.gd after the multiplayer peer is established.

func _ensure_references() -> void:
	if _blocks == null:
		_blocks = get_parent().get_node_or_null("NavigationRegion3D/Blocks")
	if _players == null:
		_players = get_parent().get_node_or_null("Players")

func _spawn_sections_for_blueprints(place_ruins: bool = false) -> void:
	_ensure_references()
	if _blocks == null:
		return

	# Clear old blocks
	for b in _blocks.get_children():
		if is_instance_valid(b):
			b.queue_free()

	# Spawn directly — no RPC. Sections live server-side only.
	# Client visual state is replicated by each section's own _sync_* RPCs.
	for pos: Vector3 in _blueprint_positions:
		var rot = _blueprint_positions[pos]
		_spawn_section_local(pos, rot)

	if place_ruins:
		_is_setting_up = true
		_do_place_starting_ruins()
		_is_setting_up = false

func _spawn_section_local(pos: Vector3, rot: float) -> void:
	_ensure_references()
	if _blocks == null:
		return
	var section = WALL_SECTION_SCENE.instantiate()
	if section:
		_blocks.add_child(section)
		section.global_position = Vector3(pos.x, 0.5, pos.z)
		section.rotation.y = rot
		section.completed.connect(_on_section_completed)
		section.uncompleted.connect(_on_section_sabotaged)

func _on_section_completed() -> void:
	if not multiplayer.is_server():
		return
	blocks_placed += 1
	blocks_changed.emit(blocks_placed)
	if blocks_for_win > 0 and blocks_placed >= blocks_for_win:
		wall_complete.emit()
	navigation_changed.emit()

func _on_section_sabotaged() -> void:
	if not multiplayer.is_server():
		return
	blocks_placed = max(0, blocks_placed - 1)
	blocks_changed.emit(blocks_placed)
	navigation_changed.emit()

# ── Section loading ───────────────────────────────────────────────────────────

func load_section_for_day(day: int) -> void:
	if not multiplayer.is_server():
		return
	load_section_rpc.rpc(day)

@rpc("authority", "call_local", "reliable")
func load_section_rpc(day: int) -> void:
	_ensure_references()
	if _blocks:
		for b in _blocks.get_children():
			if is_instance_valid(b):
				b.queue_free()

	blocks_placed = 0
	_blueprint_mgr.clear_all()
	_blueprint_mgr.init_registry_for_day(day)
	blocks_for_win = _blueprint_mgr._blueprint_positions.size()

	if multiplayer.is_server():
		_spawn_sections_for_blueprints(true)

	_spawn_towers()
	blocks_changed.emit(blocks_placed)

func _spawn_towers() -> void:
	_ensure_references()
	if _blocks == null:
		return

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.40, 0.35)  # warm sandstone

	# We place towers at the exact edges to seal the map
	for pos: Vector3 in _blueprint_mgr.get_endpoints():
		var tower_body := StaticBody3D.new()
		tower_body.position = Vector3(pos.x, 2.5, pos.z)
		tower_body.add_to_group("towers")
		_blocks.add_child(tower_body)

		# Visual
		var mesh_inst := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = Vector3(3.5, 5.0, 3.5)
		mesh_inst.mesh = box_mesh
		mesh_inst.material_override = mat
		tower_body.add_child(mesh_inst)

		# Collision
		var col_shape := CollisionShape3D.new()
		var box_col := BoxShape3D.new()
		box_col.size = Vector3(3.5, 5.0, 3.5)
		col_shape.shape = box_col
		tower_body.add_child(col_shape)

		# Optional: Spawn decorative "rubble" wall extending outside map
		_spawn_decorative_edge_ruin(pos, mat)

func _spawn_decorative_edge_ruin(edge_pos: Vector3, mat: Material) -> void:
	# Spawns a few unbuilt-looking wall blocks just outside the map bounds
	var dir = 1.0 if edge_pos.x > 0 else -1.0
	for i: int in range(1, 4):
		var ruin := MeshInstance3D.new()
		var box := BoxMesh.new()
		# Randomly sized/rotated blocks for a "ruined" look
		box.size = Vector3(5.0, randf_range(0.2, 0.8), 1.2)
		ruin.mesh = box
		ruin.material_override = mat
		ruin.position = edge_pos + Vector3(dir * i * 6.0, -2.0, randf_range(-0.5, 0.5))
		ruin.rotation.y = randf_range(-0.1, 0.1)
		ruin.rotation.z = randf_range(-0.2, 0.2)
		_blocks.add_child(ruin)

func get_section_center_for_day(day: int) -> Vector3:
	return _blueprint_mgr.get_section_center_for_day(day)

func get_section_for_day(day: int) -> Dictionary:
	return _blueprint_mgr.get_section_for_day(day)

func get_interior_direction() -> Vector3:
	return _blueprint_mgr.get_interior_direction()

# ── Queries ────────────────────────────────────────────────────────────

## Returns the nearest wall section within max_dist, or null.
func get_nearest_section(world_pos: Vector3, max_dist: float) -> WallSection:
	_ensure_references()
	if _blocks == null:
		return null

	var best: WallSection = null
	var best_dist := max_dist
	for section in _blocks.get_children():
		if is_instance_valid(section) and section is WallSection and not section.is_queued_for_deletion():
			var d := world_pos.distance_to(section.global_position)
			if d < best_dist:
				best_dist = d
				best = section
	return best

func get_nearest_placeable(world_pos: Vector3, max_dist: float) -> Vector3:
	_ensure_references()
	if _blocks == null:
		return Vector3.INF

	var best := Vector3.INF
	var best_dist := max_dist
	for section in _blocks.get_children():
		if is_instance_valid(section) and section is Node3D and not section.is_queued_for_deletion():
			var d := world_pos.distance_to(section.global_position)
			if d < best_dist:
				best_dist = d
				best = section.global_position
	return best

func get_placeable_angle(pos: Vector3) -> float:
	_ensure_references()
	if _blocks == null:
		return 0.0

	for section in _blocks.get_children():
		if is_instance_valid(section) and section is Node3D and not section.is_queued_for_deletion():
			if section.global_position.distance_to(pos) < 0.1:
				return section.rotation.y
	return 0.0

func get_stack_at(_pos: Vector3) -> int:
	return 0

# ── Starting ruins ────────────────────────────────────────────────────────────

func place_starting_ruins() -> void:
	_is_setting_up = true
	_do_place_starting_ruins()
	_is_setting_up = false

func _do_place_starting_ruins() -> void:
	_ensure_references()
	if _blocks == null or _blocks.get_child_count() == 0:
		return

	var children = _blocks.get_children()
	children.shuffle()

	var ruin_pct = 0.2
	var main = get_tree().current_scene
	if main and main.get("_wave_manager"):
		var wave = main._wave_manager.current_wave
		if wave <= 1:
			ruin_pct = 0.6
		elif wave <= 3:
			ruin_pct = 0.4

	var count = int(children.size() * ruin_pct)
	for i: int in range(count):
		var section = children[i]
		if is_instance_valid(section) and section.has_method("_sync_materials"):
			section.stone_count  = randi_range(1, WallSection.STONE_NEEDED)
			section.wood_count   = randi_range(0, WallSection.WOOD_NEEDED)
			section.mortar_count = randi_range(0, WallSection.MORTAR_NEEDED)
			section.completion_percent = randf_range(5.0, 30.0)
			section.sync_materials.rpc(section.stone_count, section.wood_count, section.mortar_count)
			section.sync_progress.rpc(section.completion_percent)

func spawn_blueprint_visuals() -> void:
	_blueprint_mgr.spawn_visuals(get_parent())

func on_block_destroyed(_pos: Vector3, _rot: float) -> void:
	pass
