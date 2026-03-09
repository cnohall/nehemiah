extends Node3D
## Main scene controller

const PLAYER_SCENE: PackedScene = preload("res://player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy/enemy.tscn")
const BLOCK_SCENE: PackedScene = preload("res://scenes/building_block/building_block.tscn")
const STONE_SCENE: PackedScene = preload("res://scenes/player/stone.tscn")
const TEMPLE_SCENE: PackedScene = preload("res://scenes/temple/temple.tscn")
const FLOATING_TEXT_SCENE: PackedScene = preload("res://scenes/ui/floating_text.tscn")

@onready var _players: Node3D  = $Players
@onready var _enemies: Node3D  = $Enemies
@onready var _blocks:  Node3D  = $Blocks
@onready var _stones:  Node3D  = $Stones
@onready var _camera:  Camera3D = $Camera3D
@onready var _nav_region: NavigationRegion3D = $NavigationRegion3D
@onready var _floor: CSGBox3D = $NavigationRegion3D/Floor
@onready var _wave_manager: Node = $WaveManager

var _local_player: CharacterBody3D = null
var _temple: Node3D = null

# Camera Shake & Zoom
var _target_zoom: float = 10.0
const MIN_ZOOM: float = 5.0
const MAX_ZOOM: float = 20.0
const ZOOM_SPEED: float = 2.0

var _shake_intensity: float = 0.0
var _shake_decay: float = 5.0
var _shake_noise := FastNoiseLite.new()
var _noise_y: float = 0.0

# Game State
var is_game_over: bool = false
var blocks_placed: int = 0
const BLOCKS_FOR_WIN: int = 50

# ══════════════════════════════════════════════════════════════════════════════
# PROCESS
# ══════════════════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	if not is_instance_valid(_local_player):
		for child in _players.get_children():
			if child is CharacterBody3D and child.is_multiplayer_authority():
				_local_player = child
				_update_global_hud()
				break

	if is_instance_valid(_local_player):
		var base_cam_pos = _local_player.global_position + Vector3(6, 10, 6)
		_camera.global_position = base_cam_pos + _get_noise_shake(delta)
		
	if _camera:
		_camera.size = lerp(_camera.size, _target_zoom, 10.0 * delta)
	
	if _shake_intensity > 0:
		_shake_intensity = max(0, _shake_intensity - _shake_decay * delta)

func _get_noise_shake(delta: float) -> Vector3:
	_noise_y += delta * 150.0 
	var shake_val = _shake_intensity * _shake_intensity 
	return Vector3(
		_shake_noise.get_noise_2d(_noise_y, 0) * shake_val,
		_shake_noise.get_noise_2d(0, _noise_y) * shake_val,
		0
	)

func add_shake(amount: float) -> void:
	_shake_intensity = clamp(_shake_intensity + amount, 0, 1.0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_zoom = clamp(_target_zoom - ZOOM_SPEED, MIN_ZOOM, MAX_ZOOM)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_zoom = clamp(_target_zoom + ZOOM_SPEED, MIN_ZOOM, MAX_ZOOM)

# ══════════════════════════════════════════════════════════════════════════════
# READY
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_shake_noise.seed = randi()
	_shake_noise.frequency = 0.5
	
	NetworkManager.lobby_created_success.connect(_on_lobby_created_success)
	NetworkManager.lobby_joined_success.connect(_on_lobby_joined_success)
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	
	if _wave_manager:
		_wave_manager.wave_started.connect(_on_wave_started)
		_wave_manager.wave_cleared.connect(_on_wave_cleared)
		_wave_manager.enemy_spawned.connect(_on_enemy_spawned)
	
	if multiplayer.is_server():
		_setup_world()

func _setup_world() -> void:
	_floor.size = Vector3(60, 1, 60)
	
	_temple = TEMPLE_SCENE.instantiate()
	_temple.position = Vector3(0, 0.75, 0)
	add_child(_temple)
	
	var breach_area = _temple.get_node("BreachArea") as Area3D
	breach_area.body_entered.connect(_on_temple_breached)
	
	_create_wall_blueprints()
	_rebake_navigation()

func _create_wall_blueprints() -> void:
	var wall_radius := 10.0
	var blueprint_mat := StandardMaterial3D.new()
	blueprint_mat.albedo_color = Color(0.2, 0.6, 1.0, 0.15)
	blueprint_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	blueprint_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	for i in range(-5, 6):
		_spawn_blueprint_segment(Vector3(i * 2.0, 0.51, wall_radius), blueprint_mat)
		_spawn_blueprint_segment(Vector3(i * 2.0, 0.51, -wall_radius), blueprint_mat)
		_spawn_blueprint_segment(Vector3(wall_radius, 0.51, i * 2.0), blueprint_mat, PI/2.0)
		_spawn_blueprint_segment(Vector3(-wall_radius, 0.51, i * 2.0), blueprint_mat, PI/2.0)

func _spawn_blueprint_segment(pos: Vector3, mat: Material, rot: float = 0.0) -> void:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 0.05, 1.0)
	mesh_inst.mesh = box
	mesh_inst.material_override = mat
	mesh_inst.position = pos
	mesh_inst.rotation.y = rot
	add_child(mesh_inst)

func _on_temple_breached(body: Node) -> void:
	if not multiplayer.is_server() or is_game_over:
		return
	if body.is_in_group("enemies") or body.get_parent().is_in_group("enemies"):
		_end_game(false)

func _end_game(win: bool) -> void:
	is_game_over = true
	if _wave_manager: _wave_manager.is_active = false
	var msg = "VICTORY!" if win else "DEFEAT!"
	_spawn_floating_text.rpc(Vector3(0, 5, 0), msg, Color.GOLD if win else Color.RED, 5.0)
	add_shake(0.5)
	_update_global_hud()

@rpc("authority", "call_local", "reliable")
func _spawn_floating_text(pos: Vector3, text: String, color: Color, dur: float = 1.5) -> void:
	var ft = FLOATING_TEXT_SCENE.instantiate()
	ft.text = text
	ft.modulate = color
	ft.duration = dur
	add_child(ft)
	ft.global_position = pos

func _update_global_hud() -> void:
	var wave = _wave_manager.current_wave if _wave_manager else 0
	_sync_hud.rpc(wave, blocks_placed)

@rpc("authority", "call_local", "reliable")
func _sync_hud(wave: int, progress: int) -> void:
	if _local_player and _local_player.get("_hud"):
		var hud = _local_player._hud
		if hud.has_method("update_wave"): hud.update_wave(wave)
		if hud.has_method("update_progress"): hud.update_progress(progress, BLOCKS_FOR_WIN)

# ══════════════════════════════════════════════════════════════════════════════
# WAVE SYSTEM HANDLERS
# ══════════════════════════════════════════════════════════════════════════════

func _on_wave_started(wave_num: int) -> void:
	_spawn_floating_text.rpc(Vector3(0, 3, 0), "WAVE %d BEGINS!" % wave_num, Color.ORANGE)
	add_shake(0.25)
	_update_global_hud()

func _on_wave_cleared(wave_num: int) -> void:
	_spawn_floating_text.rpc(Vector3(0, 3, 0), "WAVE CLEAR!", Color.LIME)
	get_tree().create_timer(5.0).timeout.connect(func(): if not is_game_over: _wave_manager.start_next_wave())

func _on_enemy_spawned(enemy: Node3D) -> void:
	_enemies.add_child(enemy, true)

# ══════════════════════════════════════════════════════════════════════════════
# NETWORK SIGNAL HANDLERS
# ══════════════════════════════════════════════════════════════════════════════

func _on_lobby_created_success(_lobby_id: int) -> void:
	_spawn_player(1) 
	get_tree().create_timer(2.0).timeout.connect(func(): _wave_manager.start_next_wave())

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
	if not multiplayer.is_server() or is_game_over: return
	do_place_block.rpc(snapped_world_pos, rotation_y)

@rpc("authority", "call_local", "reliable")
func do_place_block(snapped_world_pos: Vector3, rotation_y: float) -> void:
	var block_name := "Block_%d_%d_%d" % [int(round(snapped_world_pos.x * 100)), int(round(snapped_world_pos.y * 100)), int(round(snapped_world_pos.z * 100))]
	if _blocks.has_node(block_name): return

	var block := BLOCK_SCENE.instantiate()
	block.name = block_name
	block.global_position = snapped_world_pos
	block.rotation.y = rotation_y
	_blocks.add_child(block)
	
	if multiplayer.is_server():
		blocks_placed += 1
		_update_global_hud()
		if blocks_placed >= BLOCKS_FOR_WIN: _end_game(true)
		_rebake_navigation()

func _rebake_navigation() -> void:
	if _nav_region: _nav_region.bake_navigation_mesh()

# ══════════════════════════════════════════════════════════════════════════════
# ROSTER & STATE SYNC
# ══════════════════════════════════════════════════════════════════════════════

@rpc("any_peer", "reliable")
func _request_roster() -> void:
	if not multiplayer.is_server(): return
	var requester := multiplayer.get_remote_sender_id()
	var player_ids: Array = []
	for child in _players.get_children(): player_ids.append(int(child.name))
	var block_data: Array = []
	for child in _blocks.get_children():
		if child is Node3D: block_data.append({"pos": child.global_position, "rot": child.rotation.y})
	_receive_roster.rpc_id(requester, player_ids, block_data)

@rpc("authority", "reliable")
func _receive_roster(player_ids: Array, block_data: Array) -> void:
	for id in player_ids: _spawn_player(int(id))
	for data in block_data: do_place_block(data.pos, data.rot)

# ══════════════════════════════════════════════════════════════════════════════
# COMBAT SYSTEM RPCs
# ══════════════════════════════════════════════════════════════════════════════

@rpc("any_peer", "call_local", "reliable")
func request_throw_stone(origin: Vector3, direction: Vector3, power: float, thrower_path: NodePath = NodePath("")) -> void:
	if not multiplayer.is_server(): return
	var stone := STONE_SCENE.instantiate() as RigidBody3D
	stone.position = origin
	_stones.add_child(stone, true)
	if stone.has_method("set_thrower"): stone.set_thrower(thrower_path)
	var impulse = direction.normalized() * power
	stone.apply_central_impulse(impulse)

# ══════════════════════════════════════════════════════════════════════════════
# SPAWN HELPER
# ══════════════════════════════════════════════════════════════════════════════

func _spawn_player(peer_id: int) -> void:
	var node_name := str(peer_id)
	if _players.has_node(node_name): return
	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	player.name = node_name
	player.camera_path = NodePath("")
	player.position = Vector3(0, 1.5, 0)
	player.set_multiplayer_authority(peer_id)
	_players.add_child(player, true)
	
	player.damaged.connect(func(_amt): add_shake(0.2))
	
	if multiplayer.is_server(): 
		player.died.connect(func(): get_tree().create_timer(3.0).timeout.connect(func(): if player.has_method("respawn"): player.respawn(Vector3(0, 1.5, 0))))
