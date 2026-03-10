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
@onready var _world_env: WorldEnvironment = $WorldEnvironment
@onready var _sun: DirectionalLight3D = $DirectionalLight3D

var _local_player: CharacterBody3D = null
var _temple: Node3D = null

# Camera Shake & Zoom
var _target_zoom: float = 14.0
const MIN_ZOOM: float = 5.0
const MAX_ZOOM: float = 35.0
const ZOOM_SPEED: float = 2.0

var _shake_intensity: float = 0.0
var _shake_decay: float = 5.0
var _shake_noise := FastNoiseLite.new()
var _noise_y: float = 0.0

# Game State
var is_game_over: bool = false
var blocks_placed: int = 0
const BLOCKS_FOR_WIN: int = 250

# Day/Night Transition
var _is_transitioning: bool = false
var _transition_elapsed: float = 0.0
const TRANSITION_DURATION: float = 2.5
enum TransitionPhase { NONE, NIGHT_FALL, NIGHT_HOLD, DAY_RISE }
var _transition_phase: TransitionPhase = TransitionPhase.NONE
const SUN_DAY: float = 1.5
const SUN_NIGHT: float = 0.05
const BRIGHT_DAY: float = 1.0
const BRIGHT_NIGHT: float = 0.12

# Wall blueprint manager — handles registry, visuals, and snapping queries
var _blueprint_mgr: Node = null
# Expose positions dict for minimap backward compat
var _blueprint_positions: Dictionary:
	get: return _blueprint_mgr._blueprint_positions if _blueprint_mgr else {}

# Stone quarry
var _quarry_pos: Vector3 = Vector3(-8.0, 0.5, -8.0)
const QUARRY_INTERACT_RANGE: float = 5.0

# Suppresses per-block nav rebakes during bulk world setup
var _is_setting_up: bool = false

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

	if _is_transitioning:
		_tick_day_night(delta)

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

	_blueprint_mgr = load("res://scenes/wall_blueprint/wall_blueprint_manager.gd").new()
	_blueprint_mgr.name = "WallBlueprintManager"
	add_child(_blueprint_mgr)
	_blueprint_mgr.init_registry()

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

# ══════════════════════════════════════════════════════════════════════════════
# DAY / NIGHT TRANSITION
# ══════════════════════════════════════════════════════════════════════════════

func _tick_day_night(delta: float) -> void:
	_transition_elapsed += delta
	var t: float = clampf(_transition_elapsed / TRANSITION_DURATION, 0.0, 1.0)
	match _transition_phase:
		TransitionPhase.NIGHT_FALL:
			_sun.light_energy = lerp(SUN_DAY, SUN_NIGHT, t)
			_world_env.environment.adjustment_brightness = lerp(BRIGHT_DAY, BRIGHT_NIGHT, t)
			if t >= 1.0:
				_transition_elapsed = 0.0
				_transition_phase = TransitionPhase.NIGHT_HOLD
				_spawn_floating_text.rpc(Vector3(0, 4, 0), "Night falls...", Color.CORNFLOWER_BLUE, 2.5)
				if multiplayer.is_server():
					get_tree().create_timer(2.5).timeout.connect(_begin_dawn)
		TransitionPhase.DAY_RISE:
			_sun.light_energy = lerp(SUN_NIGHT, SUN_DAY, t)
			_world_env.environment.adjustment_brightness = lerp(BRIGHT_NIGHT, BRIGHT_DAY, t)
			if t >= 1.0:
				_is_transitioning = false
				_transition_phase = TransitionPhase.NONE

func _begin_dawn() -> void:
	_transition_elapsed = 0.0
	_transition_phase = TransitionPhase.DAY_RISE
	if not is_game_over:
		_wave_manager.start_next_wave()

# ══════════════════════════════════════════════════════════════════════════════
# WORLD SETUP  (server only)
# ══════════════════════════════════════════════════════════════════════════════

func _setup_world() -> void:
	_floor.size = Vector3(160, 1, 160)

	_temple = TEMPLE_SCENE.instantiate()
	_temple.position = Vector3(0, 0.75, 0)
	add_child(_temple)
	var breach_area = _temple.get_node("BreachArea") as Area3D
	breach_area.body_entered.connect(_on_temple_breached)

	_blueprint_mgr.spawn_visuals(self)
	_setup_quarry()

	_is_setting_up = true
	_place_starting_ruins()
	_is_setting_up = false

	_rebake_navigation()

# ── Blueprint helpers  (all peers) — thin wrappers over WallBlueprintManager ──

func get_nearest_blueprint(world_pos: Vector3, max_dist: float) -> Vector3:
	return _blueprint_mgr.get_nearest(world_pos, max_dist)

func get_blueprint_angle(key: Vector3) -> float:
	return _blueprint_mgr.get_angle(key)

# ── Quarry  (server only, interaction checked server-side) ───────────────────

func _setup_quarry() -> void:
	var quarry := Node3D.new()
	quarry.name = "StoneQuarry"
	quarry.position = _quarry_pos

	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(3.0, 1.0, 3.0)
	mesh_inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.50, 0.46, 0.40)
	mat.roughness = 0.95
	mesh_inst.material_override = mat
	quarry.add_child(mesh_inst)

	# Second pile for visual interest
	var mesh2 := MeshInstance3D.new()
	var box2 := BoxMesh.new()
	box2.size = Vector3(1.5, 0.7, 1.5)
	mesh2.mesh = box2
	mesh2.material_override = mat
	mesh2.position = Vector3(1.8, -0.15, 1.2)
	quarry.add_child(mesh2)

	add_child(quarry)

# ── Starting ruins ────────────────────────────────────────────────────────────

func _place_starting_ruins() -> void:
	# Pre-placed rubble representing the broken-down wall Nehemiah found.
	# Scattered in small clusters around the perimeter, leaving most as blueprint.
	var ruin_spots: Array[Vector3] = [
		# North wall (Sheep Gate cluster)
		Vector3( 4.0, 0.9, -36.0), Vector3( 2.0, 0.9, -36.0), Vector3( 0.0, 0.9, -36.0),
		# NE — Tower of Hananel area
		Vector3(16.0, 0.9, -30.0), Vector3(18.0, 0.9, -28.0),
		# East wall — Temple Mount face
		Vector3(30.0, 0.9, -12.0), Vector3(30.0, 0.9,  -8.0),
		# East — Water Gate
		Vector3(30.0, 0.9,   0.0),
		# SE — Fountain Gate
		Vector3(20.0, 0.9,  18.0), Vector3(16.0, 0.9,  24.0),
		# South near Dung Gate
		Vector3( 4.0, 0.9,  34.0),
		# SW — Valley Gate
		Vector3(-14.0, 0.9, 24.0),
		# West wall
		Vector3(-28.0, 0.9,  6.0), Vector3(-28.0, 0.9, -2.0),
		# NW — Old Gate
		Vector3(-22.0, 0.9, -20.0), Vector3(-14.0, 0.9, -28.0),
	]
	for pos in ruin_spots:
		var key := get_nearest_blueprint(pos, 3.0)
		var rot := get_blueprint_angle(key) if key != Vector3.INF else 0.0
		do_place_block.rpc(pos, rot)

# ══════════════════════════════════════════════════════════════════════════════
# TEMPLE & GAME END
# ══════════════════════════════════════════════════════════════════════════════

func _on_temple_breached(body: Node) -> void:
	if not multiplayer.is_server() or is_game_over: return
	if body.is_in_group("enemies") or body.get_parent().is_in_group("enemies"):
		_end_game(false)

func _end_game(win: bool) -> void:
	is_game_over = true
	if _wave_manager: _wave_manager.is_active = false
	add_shake(0.5)
	_update_global_hud()
	var day: int = _wave_manager.current_wave if is_instance_valid(_wave_manager) else 0
	_show_game_over_screen.rpc(win, day)

@rpc("authority", "call_local", "reliable")
func _show_game_over_screen(win: bool, day: int) -> void:
	for player in _players.get_children():
		if player.is_multiplayer_authority():
			var hud = player.get("_hud")
			if hud and hud.has_method("show_game_over"):
				hud.show_game_over(win, day)
			return

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
# WAVE / DAY HANDLERS
# ══════════════════════════════════════════════════════════════════════════════

func _on_wave_started(wave_num: int) -> void:
	_spawn_floating_text.rpc(Vector3(0, 3, 0), "Day %d Begins!" % wave_num, Color.ORANGE)
	add_shake(0.25)
	_update_global_hud()

func _on_wave_cleared(wave_num: int) -> void:
	_spawn_floating_text.rpc(Vector3(0, 3, 0), "Day %d Complete!" % wave_num, Color.LIME)
	if multiplayer.is_server() and not is_game_over:
		_begin_night_transition.rpc()

@rpc("authority", "call_local", "reliable")
func _begin_night_transition() -> void:
	_is_transitioning = true
	_transition_elapsed = 0.0
	_transition_phase = TransitionPhase.NIGHT_FALL

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
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = 1
	var player = _players.get_node_or_null(str(sender_id))
	if player == null: return
	if player.get("stones_carried") == null or player.stones_carried <= 0:
		return
	player.stones_carried -= 1
	if player.has_method("sync_stones_to_hud"):
		player.sync_stones_to_hud()
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
	block.global_position = snapped_world_pos
	block.rotation.y = rotation_y
	_blocks.add_child(block)

	# Remove the corresponding blueprint segment on all peers
	var bp_key := Vector3(snappedf(snapped_world_pos.x, 0.1), 0.0, snappedf(snapped_world_pos.z, 0.1))
	_blueprint_mgr.erase_at(bp_key)

	if multiplayer.is_server():
		blocks_placed += 1
		_update_global_hud()
		if blocks_placed >= BLOCKS_FOR_WIN: _end_game(true)
		if not _is_setting_up:
			_rebake_navigation()

func on_block_destroyed(world_pos: Vector3, rotation_y: float) -> void:
	if not multiplayer.is_server(): return
	var bp_key := Vector3(snappedf(world_pos.x, 0.1), 0.0, snappedf(world_pos.z, 0.1))
	_restore_blueprint.rpc(bp_key, rotation_y)
	blocks_placed = max(0, blocks_placed - 1)
	_update_global_hud()
	_rebake_navigation()

@rpc("authority", "call_local", "reliable")
func _restore_blueprint(bp_key: Vector3, rotation_y: float) -> void:
	_blueprint_mgr.restore_at(bp_key, rotation_y, self)

func _rebake_navigation() -> void:
	if _nav_region: _nav_region.bake_navigation_mesh()

# ══════════════════════════════════════════════════════════════════════════════
# STONE ECONOMY
# ══════════════════════════════════════════════════════════════════════════════

@rpc("any_peer", "reliable")
func request_collect_stones() -> void:
	if not multiplayer.is_server(): return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = 1
	var player = _players.get_node_or_null(str(sender_id))
	if player == null or player.get("stones_carried") == null: return
	if player.global_position.distance_to(_quarry_pos) > QUARRY_INTERACT_RANGE:
		_spawn_floating_text.rpc_id(
			sender_id, player.global_position + Vector3(0, 2, 0),
			"Move closer to the quarry!", Color.YELLOW, 1.5
		)
		return
	if player.stones_carried >= player.MAX_STONES: return
	player.stones_carried = player.MAX_STONES
	if player.has_method("sync_stones_to_hud"):
		player.sync_stones_to_hud()
	_spawn_floating_text.rpc_id(
		sender_id, player.global_position + Vector3(0, 2, 0),
		"Stones gathered!", Color.WHEAT, 1.5
	)

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
		player.died.connect(func(): get_tree().create_timer(3.0).timeout.connect(
			func(): if player.has_method("respawn"): player.respawn(Vector3(0, 1.5, 0))
		))
