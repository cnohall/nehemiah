extends Node
## Manages wall block placement, destruction, stacking, and blueprint tracking.
## Server-authoritative. Emits signals so main.gd can react without coupling.

signal blocks_changed(total: int)
signal wall_complete
signal navigation_changed

const BLOCK_SCENE: PackedScene = preload("res://scenes/building_block/building_block.tscn")
const MAX_WALL_LAYERS: int = 3

var blocks_placed: int = 0
var blocks_for_win: int = 0   ## Set dynamically = blueprint count for the current section
var block_hp_bonus: float = 0.0
var _is_setting_up: bool = false

var _blocks: Node3D = null
var _players: Node3D = null
var _blueprint_mgr: Node = null

# Exposed for minimap (accessed via main._blueprint_positions getter)
var _blueprint_positions: Dictionary:
	get: return _blueprint_mgr._blueprint_positions if _blueprint_mgr else {}

func _ready() -> void:
	_blocks  = get_parent().get_node("Blocks")
	_players = get_parent().get_node("Players")

	_blueprint_mgr = load("res://scenes/wall_blueprint/wall_blueprint_manager.gd").new()
	_blueprint_mgr.name = "WallBlueprintManager"
	add_child(_blueprint_mgr)
	_blueprint_mgr.init_registry_for_day(1)
	blocks_for_win = _blueprint_mgr._blueprint_positions.size()

# Called by main._setup_world() on the server after _ready.
func spawn_blueprint_visuals() -> void:
	_blueprint_mgr.spawn_visuals(get_parent())

# Places the 17 pre-placed starting ruins (server only, suppresses nav rebakes).
func place_starting_ruins() -> void:
	_is_setting_up = true
	_do_place_starting_ruins()
	_is_setting_up = false

# ── Section loading ───────────────────────────────────────────────────────────

## Called by main.gd on the server to transition to a new day's wall section.
func load_section_for_day(day: int) -> void:
	if not multiplayer.is_server(): return
	load_section_rpc.rpc(day)

@rpc("authority", "call_local", "reliable")
func load_section_rpc(day: int) -> void:
	# Clear all placed blocks
	for b in _blocks.get_children():
		if b is Node3D:
			b.queue_free()
	blocks_placed = 0
	# Clear blueprint registry and visuals
	_blueprint_mgr.clear_all()
	# Rebuild for the new section (all peers rebuild their local registry)
	_blueprint_mgr.init_registry_for_day(day)
	blocks_for_win = _blueprint_mgr._blueprint_positions.size()
	# Spawn fresh visuals on server
	if multiplayer.is_server():
		_blueprint_mgr.spawn_visuals(get_parent())
	blocks_changed.emit(blocks_placed)

## Returns the world-space midpoint of the current day's wall section.
func get_section_center_for_day(day: int) -> Vector3:
	return _blueprint_mgr.get_section_center_for_day(day)

## Returns the section metadata dict for a given day.
func get_section_for_day(day: int) -> Dictionary:
	return _blueprint_mgr.get_section_for_day(day)

func get_interior_direction() -> Vector3:
	return _blueprint_mgr.get_interior_direction()

# ── Blueprint queries (all peers) ────────────────────────────────────────────

func get_nearest_blueprint(world_pos: Vector3, max_dist: float) -> Vector3:
	return _blueprint_mgr.get_nearest(world_pos, max_dist)

func get_blueprint_angle(key: Vector3) -> float:
	return _blueprint_mgr.get_angle(key)

func get_stack_at(bp_key: Vector3) -> int:
	var count := 0
	for block in _blocks.get_children():
		if block is Node3D:
			if absf(snappedf(block.global_position.x, 0.1) - bp_key.x) < 0.15 \
			and absf(snappedf(block.global_position.z, 0.1) - bp_key.z) < 0.15:
				count += 1
	return count

# Nearest placeable spot: blueprint (layer 0) OR existing column with room left.
func get_nearest_placeable(world_pos: Vector3, max_dist: float) -> Vector3:
	var best := Vector3.INF
	var best_dist := max_dist
	for key in _blueprint_positions:
		var d := Vector2(world_pos.x - key.x, world_pos.z - key.z).length()
		if d < best_dist:
			best_dist = d
			best = key
	var seen: Dictionary = {}
	for block in _blocks.get_children():
		if not block is Node3D: continue
		var bkey := Vector3(snappedf(block.global_position.x, 0.1), 0.0, snappedf(block.global_position.z, 0.1))
		if seen.has(bkey): continue
		seen[bkey] = true
		if get_stack_at(bkey) < MAX_WALL_LAYERS:
			var d := Vector2(world_pos.x - bkey.x, world_pos.z - bkey.z).length()
			if d < best_dist:
				best_dist = d
				best = bkey
	return best

func get_placeable_angle(bp_key: Vector3) -> float:
	if _blueprint_positions.has(bp_key):
		return _blueprint_positions[bp_key]
	for block in _blocks.get_children():
		if block is Node3D:
			if absf(snappedf(block.global_position.x, 0.1) - bp_key.x) < 0.15 \
			and absf(snappedf(block.global_position.z, 0.1) - bp_key.z) < 0.15:
				return block.rotation.y
	return 0.0

# ── Building RPCs ─────────────────────────────────────────────────────────────

# Called by player.gd via rpc_id(1, ...). Server validates then broadcasts do_place_block.
@rpc("any_peer", "call_local", "reliable")
func server_place_block(snapped_world_pos: Vector3, rotation_y: float) -> void:
	if not multiplayer.is_server(): return
	if get_parent().get("is_game_over"): return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = 1
	var player := _players.get_node_or_null(str(sender_id))
	if player == null: return
	
	# Validate distance
	if player.global_position.distance_to(snapped_world_pos) > 8.0:
		return
	
	# Validate stone cost (one stone per column)
	var is_new_column = get_stack_at(Vector3(snapped_world_pos.x, 0, snapped_world_pos.z)) == 0
	if is_new_column:
		if player.get("stones_carried") == null or player.stones_carried <= 0: 
			return
		player.stones_carried -= 1
	
	do_place_block.rpc(snapped_world_pos, rotation_y)

@rpc("authority", "call_local", "reliable")
func do_place_block(snapped_world_pos: Vector3, rotation_y: float) -> void:
	var block_name := "Block_%d_%d_%d" % [
		int(round(snapped_world_pos.x * 100)),
		int(round(snapped_world_pos.y * 100)),
		int(round(snapped_world_pos.z * 100))
	]
	if _blocks.has_node(block_name): return

	var block := BLOCK_SCENE.instantiate()
	block.name = block_name
	block.rotation.y = rotation_y
	_blocks.add_child(block)
	block.global_position = snapped_world_pos
	if block_hp_bonus > 0.0 and block.get("health") != null:
		block.health += block_hp_bonus

	var bp_key := Vector3(snappedf(snapped_world_pos.x, 0.1), 0.0, snappedf(snapped_world_pos.z, 0.1))
	_blueprint_mgr.erase_at(bp_key)

	if multiplayer.is_server():
		blocks_placed += 1
		blocks_changed.emit(blocks_placed)
		if blocks_for_win > 0 and blocks_placed >= blocks_for_win:
			wall_complete.emit()
		if not _is_setting_up:
			navigation_changed.emit()

func on_block_destroyed(world_pos: Vector3, rotation_y: float) -> void:
	if not multiplayer.is_server(): return
	var bp_key := Vector3(snappedf(world_pos.x, 0.1), 0.0, snappedf(world_pos.z, 0.1))
	# Cascade: remove any blocks above the destroyed one.
	for block in _blocks.get_children():
		if block is Node3D and block.global_position.y > world_pos.y + 0.3:
			if absf(snappedf(block.global_position.x, 0.1) - bp_key.x) < 0.15 \
			and absf(snappedf(block.global_position.z, 0.1) - bp_key.z) < 0.15:
				_remove_block_rpc.rpc(block.name)
				blocks_placed = max(0, blocks_placed - 1)
	blocks_placed = max(0, blocks_placed - 1)
	blocks_changed.emit(blocks_placed)
	navigation_changed.emit()
	# Restore blueprint only when this was the last block at this XZ.
	if get_stack_at(bp_key) <= 1:
		_restore_blueprint.rpc(bp_key, rotation_y)

@rpc("authority", "call_local", "reliable")
func _remove_block_rpc(block_name: String) -> void:
	var b := _blocks.get_node_or_null(block_name)
	if b: b.queue_free()

@rpc("authority", "call_local", "reliable")
func _restore_blueprint(bp_key: Vector3, rotation_y: float) -> void:
	_blueprint_mgr.restore_at(bp_key, rotation_y, get_parent())

# ── Starting ruins ────────────────────────────────────────────────────────────
# Places random ruins within the CURRENT section's blueprints.
func _do_place_starting_ruins() -> void:
	if _blueprint_positions.is_empty(): return
	
	var keys = _blueprint_positions.keys()
	
	# Early waves have more ruins for faster testing/progression
	var ruin_pct = 0.2
	var main = get_tree().current_scene
	if main and main.get("_wave_manager"):
		var wave = main._wave_manager.current_wave
		if wave <= 1: ruin_pct = 0.6
		elif wave <= 3: ruin_pct = 0.4
	
	var count = int(keys.size() * ruin_pct)
	keys.shuffle()
	
	for i in range(count):
		var key = keys[i]
		var angle = _blueprint_positions[key]
		do_place_block.rpc(Vector3(key.x, 0.9, key.z), angle)
