extends Node3D
## Main scene controller

const PLAYER_SCENE: PackedScene = preload("res://player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy/enemy.tscn")
const BLOCK_SCENE: PackedScene = preload("res://scenes/building_block/building_block.tscn")

@onready var _players: Node3D  = $Players
@onready var _enemies: Node3D  = $Enemies
@onready var _blocks:  Node3D  = $Blocks
@onready var _camera:  Camera3D = $Camera3D
@onready var _nav_region: NavigationRegion3D = $NavigationRegion3D
@onready var _spawn_timer: Timer = $EnemySpawnTimer

var _local_player: CharacterBody3D = null

# ══════════════════════════════════════════════════════════════════════════════
# PROCESS
# ══════════════════════════════════════════════════════════════════════════════

func _process(_delta: float) -> void:
	if not is_instance_valid(_local_player):
		for child in _players.get_children():
			if child is CharacterBody3D and child.is_multiplayer_authority():
				_local_player = child
				break

	if is_instance_valid(_local_player):
		_camera.global_position = _local_player.global_position + Vector3(6, 10, 6)

# ══════════════════════════════════════════════════════════════════════════════
# READY
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	NetworkManager.lobby_created_success.connect(_on_lobby_created_success)
	NetworkManager.lobby_joined_success.connect(_on_lobby_joined_success)
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	
	_spawn_timer.timeout.connect(_on_spawn_timer_timeout)

# ══════════════════════════════════════════════════════════════════════════════
# NETWORK SIGNAL HANDLERS
# ══════════════════════════════════════════════════════════════════════════════

func _on_lobby_created_success(_lobby_id: int) -> void:
	_spawn_player(1)  # host peer ID is always 1
	_spawn_timer.start()

func _on_lobby_joined_success(_lobby_id: int) -> void:
	_request_roster.rpc_id(1)

func _on_player_connected(peer_id: int) -> void:
	_spawn_player(peer_id)

func _on_player_disconnected(peer_id: int) -> void:
	var node := _players.get_node_or_null(str(peer_id))
	if is_instance_valid(node):
		node.queue_free()

# ══════════════════════════════════════════════════════════════════════════════
# BUILDING SYSTEM RPCs
# ══════════════════════════════════════════════════════════════════════════════

@rpc("any_peer", "call_local", "reliable")
func request_place_block(snapped_world_pos: Vector3, rotation_y: float) -> void:
	if not multiplayer.is_server():
		return
	# Server validates and broadcasts
	do_place_block.rpc(snapped_world_pos, rotation_y)

@rpc("authority", "call_local", "reliable")
func do_place_block(snapped_world_pos: Vector3, rotation_y: float) -> void:
	# Duplicate check using coordinate-based naming
	var block_name := "Block_%d_%d_%d" % [
		int(round(snapped_world_pos.x * 100)),
		int(round(snapped_world_pos.y * 100)),
		int(round(snapped_world_pos.z * 100))
	]

	if _blocks.has_node(block_name):
		return

	var block := BLOCK_SCENE.instantiate()
	block.name = block_name
	block.global_position = snapped_world_pos
	block.rotation.y = rotation_y
	_blocks.add_child(block)
	
	_rebake_navigation()

func _rebake_navigation() -> void:
	if _nav_region:
		_nav_region.bake_navigation_mesh()

const MAX_ENEMIES: int = 20

# ══════════════════════════════════════════════════════════════════════════════
# ENEMY SPAWNING
# ══════════════════════════════════════════════════════════════════════════════

func _on_spawn_timer_timeout() -> void:
	if not multiplayer.is_server():
		return
	
	if _enemies.get_child_count() >= MAX_ENEMIES:
		return
		
	_spawn_enemy()

func _spawn_enemy() -> void:
	var enemy := ENEMY_SCENE.instantiate()
	
	# Spawn at a random position on the edge of the floor
	var angle := randf() * PI * 2.0
	var radius := 12.0
	enemy.position = Vector3(cos(angle) * radius, 0.5, sin(angle) * radius)
	
	_enemies.add_child(enemy, true) # true for human-readable name

# ══════════════════════════════════════════════════════════════════════════════
# ROSTER & STATE SYNC
# ══════════════════════════════════════════════════════════════════════════════

@rpc("any_peer", "reliable")
func _request_roster() -> void:
	if not multiplayer.is_server():
		return
	var requester := multiplayer.get_remote_sender_id()
	
	# Collect player IDs
	var player_ids: Array = []
	for child in _players.get_children():
		player_ids.append(int(child.name))
		
	# Collect block positions and rotations
	var block_data: Array = []
	for child in _blocks.get_children():
		if child is Node3D:
			block_data.append({"pos": child.global_position, "rot": child.rotation.y})
			
	_receive_roster.rpc_id(requester, player_ids, block_data)

@rpc("authority", "reliable")
func _receive_roster(player_ids: Array, block_data: Array) -> void:
	for id in player_ids:
		_spawn_player(int(id))
	for data in block_data:
		do_place_block(data.pos, data.rot)

# ══════════════════════════════════════════════════════════════════════════════
# SPAWN HELPER
# ══════════════════════════════════════════════════════════════════════════════

func _spawn_player(peer_id: int) -> void:
	var node_name := str(peer_id)
	if _players.has_node(node_name):
		return

	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	player.name = node_name
	player.camera_path = NodePath("")
	player.position = Vector3(0, 1.5, 0)
	player.set_multiplayer_authority(peer_id)
	_players.add_child(player, true)
