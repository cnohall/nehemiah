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
@onready var _wave_manager: Node     = $WaveManager
@onready var _world_env: WorldEnvironment    = $WorldEnvironment
@onready var _sun: DirectionalLight3D        = $DirectionalLight3D
@onready var _building_mgr: Node     = $BuildingManager

var _local_player: CharacterBody3D = null
var _temple: Node3D = null

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

# Game State
var is_game_over: bool = false
var team_gold: int = 0
var upgrades_purchased: Dictionary = {}
var stone_damage_mult: float = 1.0

const UPGRADES: Dictionary = {
	"sling":      {"name": "Tempered Slings",    "desc": "Stone damage x1.5",         "cost": 10},
	"stone_cart": {"name": "Stone Cart",          "desc": "+3 max stones for all",     "cost": 15},
	"blessing":   {"name": "Nehemiah Blessing",  "desc": "Restore all player health", "cost": 20},
	"mortar":     {"name": "Thick Mortar",        "desc": "New wall blocks +25 HP",    "cost": 25},
}

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
var _quarry_pos: Vector3 = Vector3(-8.0, 0.5, -8.0)
const QUARRY_INTERACT_RANGE: float = 5.0

# Expose blueprint positions for minimap backward compat
var _blueprint_positions: Dictionary:
	get: return _building_mgr._blueprint_positions if _building_mgr else {}

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
		# Raise camera Y with zoom so the bottom of the view never dips below ground.
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

# ══════════════════════════════════════════════════════════════════════════════
# READY
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_shake_noise.seed = randi()
	_shake_noise.frequency = 0.5

	_building_mgr.blocks_changed.connect(_on_blocks_changed)
	_building_mgr.wall_complete.connect(func(): _end_game(true))
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
	_temple = TEMPLE_SCENE.instantiate()
	_temple.position = Vector3(0, 0.75, 0)
	add_child(_temple)
	var breach_area = _temple.get_node("BreachArea") as Area3D
	breach_area.body_entered.connect(_on_temple_breached)

	_building_mgr.spawn_blueprint_visuals()
	_setup_quarry()

	_building_mgr.place_starting_ruins()
	_rebake_navigation()

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

	var mesh2 := MeshInstance3D.new()
	var box2 := BoxMesh.new()
	box2.size = Vector3(1.5, 0.7, 1.5)
	mesh2.mesh = box2
	mesh2.material_override = mat
	mesh2.position = Vector3(1.8, -0.15, 1.2)
	quarry.add_child(mesh2)

	add_child(quarry)

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
	var wave: int = _wave_manager.current_wave if _wave_manager else 0
	_sync_hud.rpc(wave, _building_mgr.blocks_placed)

func _on_blocks_changed(total: int) -> void:
	_update_global_hud()

@rpc("authority", "call_local", "reliable")
func _sync_hud(wave: int, progress: int) -> void:
	if _local_player and _local_player.get("_hud"):
		var hud = _local_player._hud
		if hud.has_method("update_wave"): hud.update_wave(wave)
		if hud.has_method("update_progress"): hud.update_progress(progress, _building_mgr.BLOCKS_FOR_WIN)

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
# STONE ECONOMY
# ══════════════════════════════════════════════════════════════════════════════

@rpc("any_peer", "reliable")
func request_collect_stones() -> void:
	if not multiplayer.is_server(): return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = 1
	var player = _players.get_node_or_null(str(sender_id))
	if player == null or player.get("stones_carried") == null: return

	# Pick up any dropped stones nearby first.
	var picked_up := _pickup_ground_stones(player, sender_id)

	# Then check quarry proximity.
	var near_quarry: bool = (player as Node3D).global_position.distance_to(_quarry_pos) <= QUARRY_INTERACT_RANGE
	if near_quarry and player.stones_carried < player.max_stones:
		player.stones_carried = player.max_stones
		_spawn_floating_text.rpc_id(sender_id, player.global_position + Vector3(0, 2, 0), "Stones gathered!", Color.WHEAT, 1.5)
	elif not near_quarry and picked_up == 0:
		_spawn_floating_text.rpc_id(sender_id, player.global_position + Vector3(0, 2, 0), "Move closer to the quarry!", Color.YELLOW, 1.5)

	if picked_up > 0 or near_quarry:
		if player.has_method("sync_stones_to_hud"):
			player.sync_stones_to_hud()

func _pickup_ground_stones(player: Node, sender_id: int) -> int:
	const PICKUP_RANGE := 2.5
	var picked_up := 0
	for stone in _stones.get_children():
		if stone is RigidBody3D and stone.get_meta("is_loot", false):
			if player.global_position.distance_to(stone.global_position) < PICKUP_RANGE:
				if player.stones_carried < player.max_stones:
					player.stones_carried += 1
					picked_up += 1
					stone.queue_free()
	if picked_up > 0:
		_spawn_floating_text.rpc_id(sender_id, player.global_position + Vector3(0, 2, 0),
			"Picked up %d stone%s!" % [picked_up, "s" if picked_up > 1 else ""], Color.WHEAT, 1.5)
	return picked_up

func _drop_player_stones(player: Node) -> void:
	var count: int = player.get("stones_carried") if player.get("stones_carried") != null else 0
	if count <= 0: return
	for i in count:
		var stone := STONE_SCENE.instantiate() as RigidBody3D
		stone.set_meta("is_loot", true)
		var offset := Vector3(randf_range(-0.6, 0.6), 0.4, randf_range(-0.6, 0.6))
		_stones.add_child(stone, true)
		stone.global_position = player.global_position + Vector3(0, 0.5, 0)
		stone.apply_central_impulse(offset.normalized() * 2.0)
	player.stones_carried = 0
	if player.has_method("sync_stones_to_hud"):
		player.sync_stones_to_hud()

# ── Upgrade System ───────────────────────────────────────────────────────────

@rpc("any_peer", "reliable")
func request_purchase_upgrade(upgrade_id: String) -> void:
	if not multiplayer.is_server(): return
	if upgrades_purchased.get(upgrade_id, false): return
	var upgrade: Dictionary = UPGRADES.get(upgrade_id, {})
	if upgrade.is_empty(): return
	var cost: int = upgrade["cost"]
	if team_gold < cost: return
	team_gold -= cost
	_sync_gold.rpc(team_gold)
	_apply_upgrade.rpc(upgrade_id)

@rpc("authority", "call_local", "reliable")
func _apply_upgrade(upgrade_id: String) -> void:
	upgrades_purchased[upgrade_id] = true
	match upgrade_id:
		"sling":
			stone_damage_mult = 1.5
		"stone_cart":
			for player in _players.get_children():
				if player.get("max_stones") != null:
					player.max_stones += 3
					if player.is_multiplayer_authority() and player.get("_hud"):
						player._hud.update_stones(player.stones_carried, player.max_stones)
		"mortar":
			if _building_mgr.get("block_hp_bonus") != null:
				_building_mgr.block_hp_bonus = 25.0
		"blessing":
			for player in _players.get_children():
				if player.get("health") == null: continue
				player.health = 100.0
				if player.get("_is_dead"): player._is_dead = false
				if player.get("visible") != null: player.visible = true
				if player.is_multiplayer_authority() and player.get("_hud"):
					player._hud.update_health(100.0)
	# Refresh upgrade UI on all peers
	_sync_upgrades.rpc(upgrades_purchased, team_gold)

@rpc("authority", "call_local", "reliable")
func _sync_upgrades(state: Dictionary, gold: int) -> void:
	upgrades_purchased = state
	team_gold = gold
	if _local_player and _local_player.get("_hud"):
		var hud = _local_player._hud
		if hud.has_method("update_upgrades"):
			hud.update_upgrades(state, gold)

# ── Shekel Drops ─────────────────────────────────────────────────────────────

func drop_shekel(pos: Vector3, gold_value: int) -> void:
	if not multiplayer.is_server(): return
	_shekel_uid += 1
	_spawn_shekel_node.rpc("sk_%d" % _shekel_uid, pos, gold_value)

@rpc("authority", "call_local", "reliable")
func _spawn_shekel_node(uid: String, pos: Vector3, gold_value: int) -> void:
	var shekel := SHEKEL_SCENE.instantiate()
	shekel.name = uid
	shekel.set_meta("gold_value", gold_value)
	_shekels.add_child(shekel)
	shekel.global_position = pos

func _process_shekels(delta: float) -> void:
	for shekel: Node3D in _shekels.get_children():
		var best_player: Node3D = null
		var best_dist: float = SHEKEL_MAGNET_RANGE
		for player in _players.get_children():
			if player.get("_is_dead"): continue
			var d: float = (player as Node3D).global_position.distance_to(shekel.global_position)
			if d < best_dist:
				best_dist = d
				best_player = player as Node3D
		if best_player == null: continue
		if best_dist < SHEKEL_PICKUP_RANGE:
			var gold_val: int = shekel.get_meta("gold_value", 1)
			var uid: String = shekel.name
			award_gold(gold_val)
			_despawn_shekel.rpc(uid)
		else:
			var dir := (best_player.global_position - shekel.global_position).normalized()
			var t: float = 1.0 - (best_dist / SHEKEL_MAGNET_RANGE)
			shekel.global_position += dir * lerpf(SHEKEL_SPEED * 0.4, SHEKEL_SPEED * 2.5, t * t) * delta
			_sync_shekel_pos.rpc(shekel.name, shekel.global_position)

@rpc("authority", "call_local", "reliable")
func _despawn_shekel(uid: String) -> void:
	var shekel := _shekels.get_node_or_null(uid)
	if is_instance_valid(shekel): shekel.queue_free()

@rpc("authority", "unreliable")
func _sync_shekel_pos(uid: String, pos: Vector3) -> void:
	var shekel := _shekels.get_node_or_null(uid)
	if is_instance_valid(shekel): shekel.global_position = pos

# ── Gold Economy ──────────────────────────────────────────────────────────────

func award_gold(amount: int) -> void:
	if not multiplayer.is_server(): return
	team_gold += amount
	_sync_gold.rpc(team_gold)

@rpc("authority", "call_local", "reliable")
func _sync_gold(total: int) -> void:
	if _local_player and _local_player.get("_hud"):
		var hud = _local_player._hud
		if hud.has_method("update_gold"): hud.update_gold(total)

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
	for data in block_data: _building_mgr.do_place_block(data.pos, data.rot)

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
	stone.apply_central_impulse(direction.normalized() * power)

# ══════════════════════════════════════════════════════════════════════════════
# NAVIGATION
# ══════════════════════════════════════════════════════════════════════════════

func _rebake_navigation() -> void:
	if _nav_region: _nav_region.bake_navigation_mesh()

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
		player.died.connect(func():
			_drop_player_stones(player)
			get_tree().create_timer(3.0).timeout.connect(
				func(): if player.has_method("respawn"): player.respawn(Vector3(0, 1.5, 0))
			))
