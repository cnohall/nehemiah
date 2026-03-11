extends Node3D
## Main scene controller

const PLAYER_SCENE: PackedScene = preload("res://player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy/enemy.tscn")
const STONE_SCENE: PackedScene = preload("res://scenes/player/stone.tscn")
const TEMPLE_SCENE: PackedScene = preload("res://scenes/temple/temple.tscn")
const FLOATING_TEXT_SCENE: PackedScene = preload("res://scenes/ui/floating_text.tscn")
const SHEKEL_SCENE: PackedScene = preload("res://scenes/economy/shekel.tscn")

@onready var _players: Node3D        = $Players
@onready var _enemies: Node3D        = $Enemies
@onready var _blocks: Node3D         = $Blocks
@onready var _stones: Node3D         = $Stones
@onready var _shekels: Node3D        = $Shekels
@onready var _camera: Camera3D       = $Camera3D
@onready var _nav_region: NavigationRegion3D = $NavigationRegion3D
@onready var _wave_manager            = $WaveManager
@onready var _world_env: WorldEnvironment    = $WorldEnvironment
@onready var _sun: DirectionalLight3D        = $DirectionalLight3D
@onready var _building_mgr            = $BuildingManager
@onready var _upgrade_mgr             = $UpgradeManager

var _local_player: CharacterBody3D = null
var _temple: Node3D = null
var _breach_area: Area3D = null
var _summary_screen: Control = null

# Stats Tracking
var _daily_kills: Dictionary = {} # peer_id -> int
var _daily_blocks: Dictionary = {} # peer_id -> int
var _ready_peers: Array = []

# Shekel (gold drop) system
var _shekel_uid: int = 0
const SHEKEL_MAGNET_RANGE: float = 8.0
const SHEKEL_PICKUP_RANGE: float = 1.2
const SHEKEL_SPEED: float = 7.0

# Camera Shake & Zoom
var _target_zoom: float = 14.0
const MIN_ZOOM: float = 5.0
const MAX_ZOOM: float = 35.0
const ZOOM_SPEED: float = 2.0

var _shake_intensity: float = 0.0
var _shake_decay: float = 5.0
var _shake_noise := FastNoiseLite.new()
var _noise_y: float = 0.0

# Game State (Legacy backward-compat bridge for old scripts)
var is_game_over: bool = false
var stone_damage_mult: float = 1.0
var team_gold: int:
	get: return _upgrade_mgr.team_gold if _upgrade_mgr else 0
var upgrades_purchased: Dictionary:
	get: return _upgrade_mgr.purchased if _upgrade_mgr else {}

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

# Stone quarry
var _quarry_pos: Vector3 = Vector3(-4.0, 0.5, -4.0)
const QUARRY_INTERACT_RANGE: float = 5.0

# Expose blueprint positions for minimap backward compat
var _blueprint_positions: Dictionary:
	get: return _building_mgr._blueprint_positions if _building_mgr else {}

# ==============================================================================
# PROCESS
# ==============================================================================

func _process(delta: float) -> void:
	if not is_instance_valid(_local_player):
		for child in _players.get_children():
			if child is CharacterBody3D and child.is_multiplayer_authority():
				_local_player = child
				_update_global_hud()
				break

	if is_instance_valid(_local_player):
		var cam_y := maxf(10.0, (_camera.size * 0.5) * 0.7071 + 1.5)
		var base_cam_pos = _local_player.global_position + Vector3(6, cam_y, 6)
		_camera.global_position = base_cam_pos + _get_noise_shake(delta)

	if _camera:
		_camera.size = lerp(_camera.size, _target_zoom, 10.0 * delta)

	if _shake_intensity > 0:
		_shake_intensity = max(0, _shake_intensity - _shake_decay * delta)

	if _is_transitioning:
		_tick_day_night(delta)

	if multiplayer.is_server() and _shekels:
		_process_shekels(delta)

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

	if event.is_action_pressed("ui_focus_next"): # Tab
		if _local_player and _local_player.get("_hud"):
			_local_player._hud.toggle_upgrades(upgrades_purchased, team_gold)

# ==============================================================================
# READY
# ==============================================================================

func _ready() -> void:
	_shake_noise.seed = randi()
	_shake_noise.frequency = 0.5
	
	var summary_scene = load("res://scenes/ui/day_summary_screen.tscn")
	_summary_screen = summary_scene.instantiate()
	add_child(_summary_screen)
	_summary_screen.ready_pressed.connect(_on_summary_ready)

	_building_mgr.blocks_changed.connect(_on_blocks_changed)
	_building_mgr.wall_complete.connect(_on_wall_complete)
	_building_mgr.navigation_changed.connect(_rebake_navigation)

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

# ==============================================================================
# DAY / NIGHT TRANSITION
# ==============================================================================

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
				if multiplayer.is_server():
					_show_summary_to_all()
		TransitionPhase.DAY_RISE:
			_sun.light_energy = lerp(SUN_NIGHT, SUN_DAY, t)
			_world_env.environment.adjustment_brightness = lerp(BRIGHT_NIGHT, BRIGHT_DAY, t)
			if t >= 1.0:
				_is_transitioning = false
				_transition_phase = TransitionPhase.NONE

func _show_summary_to_all() -> void:
	if not multiplayer.is_server(): return
	var stats_data := {}
	for player in _players.get_children():
		var pid = int(player.name)
		stats_data[pid] = {
			"name": "Player %d" % pid,
			"kills": _daily_kills.get(pid, 0),
			"blocks": _daily_blocks.get(pid, 0)
		}
	_display_summary_rpc.rpc(_wave_manager.current_wave, stats_data, _building_mgr.blocks_placed, _building_mgr.blocks_for_win)

@rpc("authority", "call_local", "reliable")
func _display_summary_rpc(day: int, stats: Dictionary, blocks: int, target: int) -> void:
	if _summary_screen:
		_summary_screen.display_summary(day, stats, blocks, target)

func _on_summary_ready() -> void:
	_report_ready.rpc_id(1)

@rpc("any_peer", "call_local", "reliable")
func _report_ready() -> void:
	if not multiplayer.is_server(): return
	var pid = multiplayer.get_remote_sender_id()
	if pid == 0: pid = 1 # local host case
	
	if not _ready_peers.has(pid): 
		_ready_peers.append(pid)
	
	# Check if all CURRENT players are ready
	var active_pids = []
	for child in _players.get_children():
		active_pids.append(int(child.name))
	
	var everyone_ready = true
	for id in active_pids:
		if not _ready_peers.has(id):
			everyone_ready = false
			break
			
	if everyone_ready and active_pids.size() > 0:
		_begin_dawn()

func _begin_dawn() -> void:
	if not multiplayer.is_server(): return
	_ready_peers.clear()
	_daily_kills.clear()
	_daily_blocks.clear()

	var next_day: int = _wave_manager.current_wave + 1
	if next_day <= _wave_manager.MAX_DAYS and not is_game_over:
		# Load wall section for the new day on all peers (this centers/scales it)
		_building_mgr.load_section_for_day(next_day)
		# Update breach detection area and quarry/temple based on new interior dir
		_update_breach_area(next_day)
		_setup_quarry()
		
		# Place some initial ruins for each section
		_building_mgr.place_starting_ruins()
		
		# Respawn all players at the section center (0,0,0 local)
		_respawn_players_rpc.rpc(Vector3.ZERO)

	_start_dawn_rpc.rpc()
	if not is_game_over: _wave_manager.start_next_wave()

@rpc("authority", "call_local", "reliable")
func _respawn_players_rpc(section_center: Vector3) -> void:
	var spawn_pos := Vector3(section_center.x, 0.5, section_center.z)
	for player in _players.get_children():
		if player is CharacterBody3D and player.is_multiplayer_authority():
			player.global_position = spawn_pos
			# Restore health for the new day
			if "health" in player:
				player.health = 100.0
			if "_is_dead" in player:
				player._is_dead = false
			player.visible = true

@rpc("authority", "call_local", "reliable")
func _start_dawn_rpc() -> void:
	_transition_elapsed = 0.0
	_transition_phase = TransitionPhase.DAY_RISE
	_summary_screen.visible = false

# ==============================================================================
# WORLD SETUP
# ==============================================================================

func _setup_world() -> void:
	_temple = TEMPLE_SCENE.instantiate()
	add_child(_temple)
	if _temple.has_signal("destroyed"):
		_temple.destroyed.connect(func(): _end_game(false))
	_setup_breach_detection()
	_setup_boundaries()
	
	_building_mgr.spawn_blueprint_visuals()
	_setup_quarry()
	_building_mgr.place_starting_ruins()
	_rebake_navigation()
	
	_update_breach_area(1)
	
	if _wave_manager:
		_wave_manager.spawn_center = _building_mgr.get_section_center_for_day(1)

func _setup_boundaries() -> void:
	var bounds := StaticBody3D.new()
	bounds.name = "MapBoundaries"
	add_child(bounds)
	
	# Map is 80x80 centered at (0,0)
	var wall_size = Vector3(80, 20, 1)
	for i in range(4):
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = wall_size
		col.shape = box
		bounds.add_child(col)
		match i:
			0: col.position = Vector3(0, 5, 40) # South
			1: col.position = Vector3(0, 5, -40) # North
			2: col.position = Vector3(40, 5, 0); col.rotation.y = PI/2 # East
			3: col.position = Vector3(-40, 5, 0); col.rotation.y = PI/2 # West

func _setup_quarry() -> void:
	# Position quarry 10 units "inside" from the center
	var dir := Vector3.BACK
	if _building_mgr and _building_mgr.has_method("get_interior_direction"):
		dir = _building_mgr.get_interior_direction()
	
	# Fix height: position y=1.0 with a 1m tall mesh puts the bottom at y=0.5 (on floor)
	var quarry_local_pos = dir * 10.0 + Vector3(0, 1.0, 0)
	_quarry_pos = quarry_local_pos
	
	# If quarry exists, move it. Else create it.
	var quarry = get_node_or_null("StoneQuarry")
	if not quarry:
		quarry = Node3D.new()
		quarry.name = "StoneQuarry"
		add_child(quarry)
		var mesh_inst := MeshInstance3D.new()
		# Make it slightly taller (1.2m) and lift it so it definitely sits on floor
		var box := BoxMesh.new(); box.size = Vector3(3, 1.2, 3); mesh_inst.mesh = box
		var mat := StandardMaterial3D.new(); mat.albedo_color = Color(0.5, 0.46, 0.4); mat.roughness = 0.95
		mesh_inst.material_override = mat; quarry.add_child(mesh_inst)
		var mesh2 := MeshInstance3D.new(); var box2 := BoxMesh.new(); box2.size = Vector3(1.5, 0.8, 1.5); mesh2.mesh = box2
		mesh2.material_override = mat; mesh2.position = Vector3(1.8, -0.2, 1.2); quarry.add_child(mesh2)
	
	quarry.position = _quarry_pos
	# Update temple position too
	if _temple: _temple.position = dir * 25.0 + Vector3(0, 0.5, 0)

func _setup_breach_detection() -> void:
	_breach_area = Area3D.new()
	_breach_area.name = "CityBreachArea"
	_breach_area.collision_mask = 4 # Enemies
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 10, 20) # 40m wide, 20m deep
	col.shape = box
	_breach_area.add_child(col)
	
	# Add a visual representation similar to the quarry
	var mesh_inst := MeshInstance3D.new()
	var mesh := BoxMesh.new(); mesh.size = Vector3(40, 0.05, 20)
	mesh_inst.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.2, 0.2, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_inst.material_override = mat
	_breach_area.add_child(mesh_inst)
	
	add_child(_breach_area)
	_breach_area.body_entered.connect(_on_city_breached)

func _update_breach_area(_day: int) -> void:
	if not _building_mgr: return
	var dir: Vector3 = _building_mgr.get_interior_direction()
	# Position 25 units inside the city
	_breach_area.global_position = dir * 25.0 + Vector3(0, 0.51, 0)
	
	# Rotate so the width (40m) is parallel to the wall section
	_breach_area.look_at(_breach_area.global_position + dir, Vector3.UP)

func _on_wall_complete() -> void:
	if not multiplayer.is_server(): return
	
	if _wave_manager:
		_wave_manager.stop_spawning()
	
	# Clear all remaining enemies immediately so the day ends
	for enemy in _enemies.get_children():
		enemy.queue_free()
	
	# If this was the final wall section (Day 52), trigger win
	if _wave_manager and _wave_manager.current_wave >= _wave_manager.MAX_DAYS:
		_end_game(true)

func _on_city_breached(body: Node) -> void:
	if not multiplayer.is_server() or is_game_over: return
	var node = body
	while node:
		if node.is_in_group("enemies"):
			_end_game(false); return
		node = node.get_parent()

func _end_game(win: bool) -> void:
	is_game_over = true
	if _wave_manager: _wave_manager.is_active = false
	add_shake(0.5); _update_global_hud()
	_show_game_over_screen.rpc(win, _wave_manager.current_wave if _wave_manager else 0)

@rpc("authority", "call_local", "reliable")
func _show_game_over_screen(win: bool, day: int) -> void:
	for p in _players.get_children():
		if p.is_multiplayer_authority() and p.get("_hud"): p._hud.show_game_over(win, day)

@rpc("authority", "call_local", "reliable")
func _spawn_floating_text(pos: Vector3, text: String, color: Color, dur: float = 1.5) -> void:
	var ft = FLOATING_TEXT_SCENE.instantiate(); ft.text = text; ft.modulate = color; ft.duration = dur
	add_child(ft); ft.global_position = pos

func _update_global_hud() -> void:
	var wave: int = _wave_manager.current_wave if _wave_manager else 0
	_sync_hud.rpc(wave, _building_mgr.blocks_placed)

func _on_blocks_changed(total: int) -> void:
	_update_global_hud()
	if multiplayer.is_server():
		var id = multiplayer.get_remote_sender_id()
		if id == 0: id = 1
		_daily_blocks[id] = _daily_blocks.get(id, 0) + 1

@rpc("authority", "call_local", "reliable")
func _sync_hud(wave: int, progress: int) -> void:
	if _local_player and _local_player.get("_hud"):
		var hud = _local_player._hud
		if hud.has_method("update_wave"): hud.update_wave(wave)
		if hud.has_method("update_progress"): hud.update_progress(progress, _building_mgr.blocks_for_win)

func _on_wave_started(wave_num: int) -> void:
	_spawn_floating_text.rpc(Vector3(0, 3, 0), "Day %d Begins!" % wave_num, Color.ORANGE)
	add_shake(0.25); _update_global_hud()

func _on_wave_cleared(wave_num: int) -> void:
	_spawn_floating_text.rpc(Vector3(0, 3, 0), "Day %d Complete!" % wave_num, Color.LIME)
	if multiplayer.is_server() and not is_game_over: _begin_night_transition.rpc()

@rpc("authority", "call_local", "reliable")
func _begin_night_transition() -> void:
	_is_transitioning = true; _transition_elapsed = 0.0; _transition_phase = TransitionPhase.NIGHT_FALL

func _on_enemy_spawned(enemy: Node3D) -> void:
	_enemies.add_child(enemy, true)
	if multiplayer.is_server(): enemy.tree_exiting.connect(_on_enemy_removed.bind(enemy))

func _on_enemy_removed(enemy: Node3D) -> void:
	if not multiplayer.is_server(): return
	var id = 0
	if enemy.has_meta("killer_id"):
		id = enemy.get_meta("killer_id")
	if id != 0: _daily_kills[id] = _daily_kills.get(id, 0) + 1

# ==============================================================================
# NETWORK SIGNAL HANDLERS
# ==============================================================================

func _on_lobby_created_success(_lobby_id: int) -> void:
	_spawn_player(1)
	_rebake_navigation()
	# Wait a bit longer to ensure nav is ready
	get_tree().create_timer(3.0).timeout.connect(func(): _wave_manager.start_next_wave())

func _on_lobby_joined_success(_lobby_id: int) -> void:
	_request_roster.rpc_id(1)

func _on_player_connected(id: int) -> void:
	_spawn_player(id)

func _on_player_disconnected(id: int) -> void:
	var node := _players.get_node_or_null(str(id))
	if is_instance_valid(node): node.queue_free()

# ==============================================================================
# ECONOMY & UPGRADES (Proxy to UpgradeManager)
# ==============================================================================

@rpc("any_peer", "reliable")
func request_purchase_upgrade(upgrade_id: String) -> void:
	if _upgrade_mgr: _upgrade_mgr.request_purchase(upgrade_id)

func award_gold(amount: int, player: Node3D = null) -> void:
	if _upgrade_mgr: _upgrade_mgr.add_gold(amount)
	
	# Show floating text at the player who picked it up
	var target_pos = Vector3.ZERO
	if is_instance_valid(player):
		target_pos = player.global_position
	elif is_instance_valid(_local_player):
		target_pos = _local_player.global_position
		
	if target_pos != Vector3.ZERO:
		_spawn_floating_text.rpc(target_pos + Vector3(0, 2, 0), "+%d Shekels" % amount, Color.GOLD)

func get_local_hud() -> CanvasLayer:
	if is_instance_valid(_local_player) and "_hud" in _local_player:
		return _local_player._hud
	return null

# -- Stone gathering -----------------------------------------------------------

@rpc("any_peer", "reliable")
func request_collect_stones() -> void:
	if not multiplayer.is_server(): return
	var id := multiplayer.get_remote_sender_id()
	if id == 0: id = 1
	var player = _players.get_node_or_null(str(id))
	if player == null: return
	var picked_up := _pickup_ground_stones(player, id)
	var near_quarry: bool = player.global_position.distance_to(_quarry_pos) <= QUARRY_INTERACT_RANGE
	if near_quarry and player.stones_carried < player.max_stones:
		player.set_stones.rpc(player.max_stones)
		_spawn_floating_text.rpc_id(id, player.global_position + Vector3(0, 2, 0), "Stones gathered!", Color.WHEAT, 1.5)
	elif not near_quarry and picked_up == 0:
		_spawn_floating_text.rpc_id(id, player.global_position + Vector3(0, 2, 0), "Move closer to the quarry!", Color.YELLOW, 1.5)

func _pickup_ground_stones(player: Node, id: int) -> int:
	var count := 0
	var current_stones = player.stones_carried
	for s in _stones.get_children():
		if s.get_meta("is_loot", false) and player.global_position.distance_to(s.global_position) < 2.5:
			if current_stones + count < player.max_stones:
				count += 1; s.queue_free()
	if count > 0:
		player.set_stones.rpc(current_stones + count)
		_spawn_floating_text.rpc_id(id, player.global_position + Vector3(0, 2, 0), "Picked up %d stones!" % count, Color.WHEAT, 1.5)
	return count

func _drop_player_stones(player: Node) -> void:
	var count: int = 0
	if "stones_carried" in player:
		count = player.stones_carried
	for i in count:
		var s := STONE_SCENE.instantiate() as RigidBody3D; s.set_meta("is_loot", true)
		_stones.add_child(s, true); s.global_position = player.global_position + Vector3(0, 0.5, 0)
		s.apply_central_impulse(Vector3(randf_range(-0.6, 0.6), 0.4, randf_range(-0.6, 0.6)).normalized() * 2.0)
	if player.has_method("set_stones"):
		player.set_stones.rpc(0)

# -- Shekel Drops --------------------------------------------------------------

func drop_shekel(pos: Vector3, gold_value: int) -> void:
	if not multiplayer.is_server(): return
	_shekel_uid += 1; _spawn_shekel_node.rpc("sk_%d" % _shekel_uid, pos, gold_value)

@rpc("authority", "call_local", "reliable")
func _spawn_shekel_node(uid: String, pos: Vector3, gold_value: int) -> void:
	var s := SHEKEL_SCENE.instantiate(); s.name = uid; s.set_meta("gold_value", gold_value)
	_shekels.add_child(s); s.global_position = pos

func _process_shekels(delta: float) -> void:
	for s: Node3D in _shekels.get_children():
		var best_p: Node3D = null; var best_d := SHEKEL_MAGNET_RANGE
		for p in _players.get_children():
			var is_dead = false
			if "_is_dead" in p: is_dead = p._is_dead
			var d = p.global_position.distance_to(s.global_position)
			if d < best_d and not is_dead: best_d = d; best_p = p
		if best_p == null: continue

		if best_d < 1.2:
			award_gold(s.get_meta("gold_value", 1), best_p); _despawn_shekel.rpc(s.name)
		else:
			var dir = (best_p.global_position - s.global_position).normalized()
			s.global_position += dir * lerpf(SHEKEL_SPEED * 0.4, SHEKEL_SPEED * 2.5, pow(1.0 - (best_d / SHEKEL_MAGNET_RANGE), 2)) * delta
			_sync_shekel_pos.rpc(s.name, s.global_position)

@rpc("authority", "call_local", "reliable")
func _despawn_shekel(uid: String) -> void:
	var s = _shekels.get_node_or_null(uid); if is_instance_valid(s): s.queue_free()

@rpc("authority", "unreliable")
func _sync_shekel_pos(uid: String, pos: Vector3) -> void:
	var s = _shekels.get_node_or_null(uid); if is_instance_valid(s): s.global_position = pos

# ==============================================================================
# ROSTER & STATE SYNC
# ==============================================================================

@rpc("any_peer", "reliable")
func _request_roster() -> void:
	if not multiplayer.is_server(): return
	var req := multiplayer.get_remote_sender_id()
	var ids: Array = []; for c in _players.get_children(): ids.append(int(c.name))
	var blocks: Array = []; for c in _blocks.get_children(): blocks.append({"pos": c.global_position, "rot": c.rotation.y})
	_receive_roster.rpc_id(req, ids, blocks)

@rpc("authority", "reliable")
func _receive_roster(ids: Array, blocks: Array) -> void:
	for id in ids: _spawn_player(id)
	for b in blocks: _building_mgr.do_place_block(b.pos, b.rot)

@rpc("any_peer", "call_local", "reliable")
func request_throw_stone(origin: Vector3, direction: Vector3, power: float, thrower_path: NodePath = NodePath("")) -> void:
	if not multiplayer.is_server(): return
	var s := STONE_SCENE.instantiate() as RigidBody3D; s.position = origin; _stones.add_child(s, true)
	if s.has_method("set_thrower"): s.set_thrower(thrower_path)
	s.apply_central_impulse(direction.normalized() * power)

func _rebake_navigation() -> void:
	if _nav_region: _nav_region.bake_navigation_mesh()

func _spawn_player(id: int) -> void:
	if _players.has_node(str(id)): return
	var p: CharacterBody3D = PLAYER_SCENE.instantiate(); p.name = str(id); p.position = Vector3(0, 0.5, 0)
	p.set_multiplayer_authority(id); _players.add_child(p, true); p.damaged.connect(func(_a): add_shake(0.2))
	if multiplayer.is_server():
		p.died.connect(func():
			_drop_player_stones(p)
			get_tree().create_timer(3.0).timeout.connect(func(): if p.has_method("respawn"): p.respawn(Vector3(0, 0.5, 0))))
