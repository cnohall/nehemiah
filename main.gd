extends Node3D
## Main scene controller — Refactored for maintainability.

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
@onready var _building_mgr            = $BuildingManager
@onready var _upgrade_mgr             = $UpgradeManager
@onready var _env_mgr                 = $EnvironmentManager

var _local_player: CharacterBody3D = null
var _temple: Node3D = null
var _breach_area: Area3D = null
var _summary_screen: Control = null

# Stats Tracking
var _daily_kills: Dictionary = {} 
var _daily_blocks: Dictionary = {}
var _ready_peers: Array = []

# Shekel system constants
const SHEKEL_MAGNET_RANGE: float = 8.0
const SHEKEL_PICKUP_RANGE: float = 1.2
const SHEKEL_SPEED: float = 7.0
var _shekel_uid: int = 0

# Camera settings
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
var stone_damage_mult: float = 1.0
var team_gold: int:
	get: return _upgrade_mgr.team_gold if _upgrade_mgr else 0
var upgrades_purchased: Dictionary:
	get: return _upgrade_mgr.purchased if _upgrade_mgr else {}

# Material Piles
var _stone_pile: Node3D = null
var _wood_pile: Node3D = null
var _mortar_pile: Node3D = null

# ══════════════════════════════════════════════════════════════════════════════
# PROCESS
# ══════════════════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	_update_local_player_ref()
	_update_camera(delta)
	
	if _shake_intensity > 0:
		_shake_intensity = max(0, _shake_intensity - _shake_decay * delta)

	if multiplayer.is_server() and _shekels:
		_process_shekels(delta)

func _update_local_player_ref() -> void:
	if not is_instance_valid(_local_player):
		for child in _players.get_children():
			if child is CharacterBody3D and child.is_multiplayer_authority():
				_local_player = child
				_sync_hud_local()
				break

func _update_camera(delta: float) -> void:
	if is_instance_valid(_local_player):
		var cam_y := maxf(10.0, (_camera.size * 0.5) * 0.7071 + 1.5)
		var base_cam_pos = _local_player.global_position + Vector3(6, cam_y, 6)
		_camera.global_position = base_cam_pos + _get_noise_shake(delta)

	if _camera:
		_camera.size = lerp(_camera.size, _target_zoom, 10.0 * delta)

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

# ══════════════════════════════════════════════════════════════════════════════
# READY & SETUP
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_shake_noise.seed = randi()
	_shake_noise.frequency = 0.5
	
	_init_ui()
	_connect_signals()

	if multiplayer.is_server():
		_setup_world()

func _init_ui() -> void:
	var summary_scene = load("res://scenes/ui/day_summary_screen.tscn")
	_summary_screen = summary_scene.instantiate()
	add_child(_summary_screen)
	_summary_screen.ready_pressed.connect(_on_summary_ready)

func _connect_signals() -> void:
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

# ══════════════════════════════════════════════════════════════════════════════
# DAY / NIGHT CYCLES
# ══════════════════════════════════════════════════════════════════════════════

func _on_wave_cleared(wave_num: int) -> void:
	_spawn_floating_text.rpc(Vector3(0, 3, 0), "Day %d Complete!" % wave_num, Color.LIME)
	if multiplayer.is_server() and not is_game_over:
		_env_mgr.sync_transition.rpc(true) # To Night
		_show_summary_to_all()

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
	sync_summary.rpc(_wave_manager.current_wave, stats_data, _building_mgr.blocks_placed, _building_mgr.blocks_for_win)

@rpc("authority", "call_local", "reliable")
func sync_summary(day: int, stats: Dictionary, blocks: int, target: int) -> void:
	if _summary_screen:
		_summary_screen.display_summary(day, stats, blocks, target)

func _on_summary_ready() -> void:
	request_ready_next_day.rpc_id(1)

@rpc("any_peer", "call_local", "reliable")
func request_ready_next_day() -> void:
	if not multiplayer.is_server(): return
	var pid = multiplayer.get_remote_sender_id()
	if pid == 0: pid = 1
	
	if not _ready_peers.has(pid): _ready_peers.append(pid)
	
	var active_pids = []
	for child in _players.get_children(): active_pids.append(int(child.name))
	
	var everyone_ready = true
	for id in active_pids:
		if not _ready_peers.has(id):
			everyone_ready = false; break
			
	if everyone_ready and active_pids.size() > 0:
		_begin_dawn()

func _begin_dawn() -> void:
	if not multiplayer.is_server(): return
	_ready_peers.clear()
	_daily_kills.clear()
	_daily_blocks.clear()

	var next_day: int = _wave_manager.current_wave + 1
	if next_day <= _wave_manager.MAX_DAYS and not is_game_over:
		sync_start_dawn.rpc()
		_building_mgr.load_section_for_day(next_day)
		_update_breach_area(next_day)
		_setup_piles()
		_building_mgr.place_starting_ruins()
		_wave_manager.start_next_wave()

@rpc("authority", "call_local", "reliable")
func sync_start_dawn() -> void:
	if _env_mgr: _env_mgr.sync_transition(false) # To Day
	_summary_screen.visible = false
	# Clear ground clutter
	for c in get_tree().get_nodes_in_group("carriables"):
		if c.carrier == null: c.queue_free()

# ══════════════════════════════════════════════════════════════════════════════
# WORLD GEN
# ══════════════════════════════════════════════════════════════════════════════

func _setup_world() -> void:
	_temple = TEMPLE_SCENE.instantiate()
	add_child(_temple)
	_temple.destroyed.connect(func(): _end_game(false))
	
	_setup_boundaries()
	_setup_breach_detection()
	_setup_piles()
	_rebake_navigation()
	
	if _wave_manager:
		_wave_manager.spawn_center = _building_mgr.get_section_center_for_day(1)

func _setup_piles() -> void:
	var dir := _building_mgr.get_interior_direction()
	var right_dir = dir.cross(Vector3.UP)
	
	_stone_pile = _ensure_pile(_stone_pile, "StonePile", "stone", dir * 15.0 + Vector3(0, 0.5, 0))
	_wood_pile = _ensure_pile(_wood_pile, "WoodPile", "wood", dir * 12.0 + right_dir * 12.0 + Vector3(0, 0.5, 0))
	_mortar_pile = _ensure_pile(_mortar_pile, "MortarPile", "mortar", dir * 12.0 - right_dir * 12.0 + Vector3(0, 0.5, 0))
	
	if _temple: _temple.position = dir * 25.0 + Vector3(0, 0.5, 0)

func _ensure_pile(pile: Node3D, p_name: String, type: String, pos: Vector3) -> Node3D:
	if not pile:
		var script = load("res://scenes/player/supply_pile.gd")
		pile = Node3D.new(); pile.name = p_name; pile.set_script(script)
		pile.material_type = type; pile.add_to_group("supply_piles"); add_child(pile)
	pile.global_position = pos
	return pile

# ══════════════════════════════════════════════════════════════════════════════
# COMBAT & ECONOMY
# ══════════════════════════════════════════════════════════════════════════════

@rpc("any_peer", "call_local", "reliable")
func request_throw_stone(origin: Vector3, direction: Vector3, power: float, thrower_path: NodePath) -> void:
	if not multiplayer.is_server(): return
	var s := STONE_SCENE.instantiate() as RigidBody3D; s.position = origin; _stones.add_child(s, true)
	if s.has_method("set_thrower"): s.set_thrower(thrower_path)
	s.apply_central_impulse(direction.normalized() * power)

func drop_shekel(pos: Vector3, val: int) -> void:
	if not multiplayer.is_server(): return
	_shekel_uid += 1; _sync_spawn_shekel.rpc("sk_%d" % _shekel_uid, pos, val)

@rpc("authority", "call_local", "reliable")
func _sync_spawn_shekel(uid: String, pos: Vector3, val: int) -> void:
	var s := SHEKEL_SCENE.instantiate(); s.name = uid; s.set_meta("gold_value", val)
	_shekels.add_child(s); s.global_position = pos

func _process_shekels(delta: float) -> void:
	for s in _shekels.get_children():
		var best_p: Node3D = null; var best_d := SHEKEL_MAGNET_RANGE
		for p in _players.get_children():
			if p.get("_is_dead"): continue
			var d = p.global_position.distance_to(s.global_position)
			if d < best_d: best_d = d; best_p = p
		
		if best_p:
			if best_d < 1.2:
				award_gold(s.get_meta("gold_value", 1), best_p); _sync_despawn_shekel.rpc(s.name)
			else:
				var dir = (best_p.global_position - s.global_position).normalized()
				s.global_position += dir * SHEKEL_SPEED * delta
				_sync_shekel_pos.rpc(s.name, s.global_position)

@rpc("authority", "call_local", "reliable")
func _sync_despawn_shekel(uid: String) -> void:
	var s = _shekels.get_node_or_null(uid); if s: s.queue_free()

@rpc("authority", "unreliable")
func _sync_shekel_pos(uid: String, pos: Vector3) -> void:
	var s = _shekels.get_node_or_null(uid); if s: s.global_position = pos

func award_gold(amount: int, player: Node3D) -> void:
	if _upgrade_mgr: _upgrade_mgr.add_gold(amount)
	_spawn_floating_text.rpc(player.global_position + Vector3(0, 2, 0), "+%d Shekels" % amount, Color.GOLD)

# ══════════════════════════════════════════════════════════════════════════════
# HELPERS & SYSTEM
# ══════════════════════════════════════════════════════════════════════════════

func _rebake_navigation() -> void:
	if _nav_region: _nav_region.bake_navigation_mesh()

func _on_blocks_changed(_total: int) -> void:
	_sync_hud_local()

func _sync_hud_local() -> void:
	if _local_player and _local_player.get("_hud"):
		var hud = _local_player._hud
		hud.update_wave(_wave_manager.current_wave)
		hud.update_progress(_building_mgr.blocks_placed, _building_mgr.blocks_for_win)

@rpc("authority", "call_local", "reliable")
func _spawn_floating_text(pos: Vector3, text: String, color: Color, dur: float = 1.5) -> void:
	var ft = FLOATING_TEXT_SCENE.instantiate(); ft.text = text; ft.modulate = color; ft.duration = dur
	add_child(ft); ft.global_position = pos

func _end_game(win: bool) -> void:
	is_game_over = true
	_show_game_over_rpc.rpc(win, _wave_manager.current_wave)

@rpc("authority", "call_local", "reliable")
func _show_game_over_rpc(win: bool, day: int) -> void:
	if _local_player and _local_player.get("_hud"):
		_local_player._hud.show_game_over(win, day)

# ══════════════════════════════════════════════════════════════════════════════
# BOILERPLATE REMOVED
# ══════════════════════════════════════════════════════════════════════════════

func _setup_boundaries() -> void:
	var bounds := StaticBody3D.new(); bounds.name = "MapBoundaries"; add_child(bounds)
	var wall_size = Vector3(80, 20, 1)
	for i in range(4):
		var col := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = wall_size
		col.shape = box; bounds.add_child(col)
		match i:
			0: col.position = Vector3(0, 5, 40)
			1: col.position = Vector3(0, 5, -40)
			2: col.position = Vector3(40, 5, 0); col.rotation.y = PI/2
			3: col.position = Vector3(-40, 5, 0); col.rotation.y = PI/2

func _setup_breach_detection() -> void:
	_breach_area = Area3D.new(); _breach_area.name = "CityBreachArea"; _breach_area.collision_mask = 4
	var col := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(40, 10, 20); col.shape = box
	_breach_area.add_child(col); add_child(_breach_area); _breach_area.body_entered.connect(_on_city_breached)

func _update_breach_area(_day: int) -> void:
	var dir := _building_mgr.get_interior_direction()
	_breach_area.global_position = dir * 25.0 + Vector3(0, 0.5, 0)
	_breach_area.look_at(_breach_area.global_position + dir, Vector3.UP)

func _on_city_breached(body: Node) -> void:
	if multiplayer.is_server() and body.is_in_group("enemies"): _end_game(false)

func _on_wall_complete() -> void:
	if not multiplayer.is_server(): return
	if _wave_manager.current_wave >= _wave_manager.MAX_DAYS: _end_game(true)
	else:
		_spawn_floating_text.rpc(Vector3(0, 3, 0), "Section Complete!", Color.LIME)
		_env_mgr.sync_transition.rpc(true) # To Night
		_show_summary_to_all()

func _on_lobby_created_success(_id: int) -> void:
	_building_mgr.load_section_rpc.rpc(1); _spawn_player(1)
	get_tree().create_timer(2.0).timeout.connect(func(): _wave_manager.start_next_wave())

func _on_lobby_joined_success(_id: int) -> void: pass

func _on_player_connected(id: int) -> void: _spawn_player(id)

func _on_player_disconnected(id: int) -> void:
	var n = _players.get_node_or_null(str(id)); if n: n.queue_free()

func _spawn_player(id: int) -> void:
	if _players.has_node(str(id)): return
	var p = PLAYER_SCENE.instantiate(); p.name = str(id); p.set_multiplayer_authority(id)
	_players.add_child(p, true); p.damaged.connect(func(_a): add_shake(0.2))
	if multiplayer.is_server():
		p.died.connect(func(): get_tree().create_timer(3.0).timeout.connect(func(): if is_instance_valid(p): p.respawn(Vector3.ZERO)))

func _on_enemy_spawned(enemy: Node3D) -> void:
	_enemies.add_child(enemy, true)
	if multiplayer.is_server(): enemy.tree_exiting.connect(func(): _on_enemy_removed(enemy))

func _on_enemy_removed(enemy: Node3D) -> void:
	var id = enemy.get_meta("killer_id", 0)
	if id != 0: _daily_kills[id] = _daily_kills.get(id, 0) + 1
