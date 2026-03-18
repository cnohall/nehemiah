extends Node3D
## Main scene controller — Simplified for the core loop.

const PLAYER_SCENE: PackedScene = preload("res://player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy/enemy.tscn")
const STONE_SCENE: PackedScene = preload("res://scenes/player/stone.tscn")
const FLOATING_TEXT_SCENE: PackedScene = preload("res://scenes/ui/floating_text.tscn")
const GAME_HUD_SCENE: PackedScene = preload("res://scenes/ui/game_hud.tscn")

const MIN_ZOOM: float = 5.0
const MAX_ZOOM: float = 35.0
const ZOOM_SPEED: float = 2.0

var is_game_over: bool = false

# Camera settings
var _local_player: CharacterBody3D = null
var _city_manager: CityManager = null
var _ready_peers: Array = []
var _target_zoom: float = 14.0

# Material Piles
var _stone_pile: Node3D = null
var _wood_pile: Node3D = null
var _mortar_pile: Node3D = null

@onready var _nav_region: NavigationRegion3D = $NavigationRegion3D
@onready var _blocks: Node3D = $NavigationRegion3D/Blocks
@onready var _players: Node3D = $Players
@onready var _enemies: Node3D = $Enemies
@onready var _stones: Node3D = $Stones
@onready var _camera: Camera3D = $Camera3D
@onready var _sun: DirectionalLight3D = $DirectionalLight3D
@onready var _wave_manager: Node = $WaveManager
@onready var _building_mgr: Node = $BuildingManager

var _ambience_player: AudioStreamPlayer = null
var _music_player: AudioStreamPlayer = null
var _hud_layer: CanvasLayer = null
var _hud: Node = null

# ══════════════════════════════════════════════════════════════════════════════
# PROCESS
# ══════════════════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	_update_local_player_ref()
	_update_camera(delta)

func _update_local_player_ref() -> void:
	if not is_instance_valid(_local_player):
		for child in _players.get_children():
			if child is CharacterBody3D and child.is_multiplayer_authority():
				_local_player = child
				break

func _update_camera(delta: float) -> void:
	if is_instance_valid(_local_player):
		var cam_y := maxf(10.0, (_camera.size * 0.5) * 0.7071 + 1.5)
		var base_cam_pos = _local_player.global_position + Vector3(6, cam_y, 6)
		_camera.global_position = base_cam_pos

	if _camera:
		_camera.size = lerp(_camera.size, _target_zoom, 10.0 * delta)

func _unhandled_input(event: InputEvent) -> void:
	# Zoom Input Handling
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_zoom = maxf(MIN_ZOOM, _target_zoom - ZOOM_SPEED)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_zoom = minf(MAX_ZOOM, _target_zoom + ZOOM_SPEED)
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_EQUAL: # Often '+' key
			_target_zoom = maxf(MIN_ZOOM, _target_zoom - ZOOM_SPEED)
		elif event.keycode == KEY_MINUS:
			_target_zoom = minf(MAX_ZOOM, _target_zoom + ZOOM_SPEED)

	if not multiplayer.is_server():
		return

	# Debug Level Selection: Use Left/Right arrows to browse days
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_RIGHT:
			_debug_change_day(1)
		elif event.keycode == KEY_LEFT:
			_debug_change_day(-1)

func _debug_change_day(offset: int) -> void:
	var next_day = clampi(_wave_manager.current_wave + offset, 1, _wave_manager.MAX_DAYS)
	if next_day != _wave_manager.current_wave:
		_wave_manager.stop_spawning()
		for enemy in _enemies.get_children():
			enemy.queue_free()
		_wave_manager.current_wave = next_day - 1 # _begin_dawn increments it
		_begin_dawn()

# ══════════════════════════════════════════════════════════════════════════════
# READY & SETUP
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_connect_signals()
	_setup_audio()

	if multiplayer.is_server():
		_setup_world()

func _setup_audio() -> void:
	_ambience_player = AudioStreamPlayer.new()
	add_child(_ambience_player)

	var wind_path = "res://assets/sounds/desert_wind.wav"
	if FileAccess.file_exists(wind_path):
		var stream = load(wind_path) as AudioStreamWAV
		if stream:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			_ambience_player.stream = stream
			_ambience_player.volume_db = -18.0
			_ambience_player.play()

	_music_player = AudioStreamPlayer.new()
	add_child(_music_player)

	var music_path = "res://assets/music/bgm_main.ogg"
	if FileAccess.file_exists(music_path):
		var stream = load(music_path)
		if stream:
			_music_player.stream = stream
			_music_player.volume_db = -20.0
			_music_player.play()

func _connect_signals() -> void:
	_building_mgr.blocks_changed.connect(func(_total): pass)
	_building_mgr.wall_complete.connect(_on_wall_complete)
	_building_mgr.navigation_changed.connect(_rebake_navigation)

	NetworkManager.lobby_created_success.connect(_on_lobby_created_success)
	NetworkManager.lobby_joined_success.connect(func(_id: int): _setup_hud())
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)

	if _wave_manager:
		_wave_manager.wave_started.connect(_on_wave_started)
		_wave_manager.enemy_spawned.connect(_on_enemy_spawned)

# ══════════════════════════════════════════════════════════════════════════════
# DAY / NIGHT CYCLES
# ══════════════════════════════════════════════════════════════════════════════

func _begin_night_transition() -> void:
	_wave_manager.stop_spawning()
	for enemy in _enemies.get_children():
		enemy.queue_free()
	_spawn_floating_text.rpc(Vector3(0, 3, 0), "Section Complete!", Color.LIME)
	_sync_time_of_day.rpc(true)
	get_tree().create_timer(4.0).timeout.connect(_begin_dawn)

@rpc("authority", "call_local", "reliable")
func _sync_time_of_day(is_night: bool) -> void:
	if _sun:
		_sun.light_energy = 0.05 if is_night else 1.5

func _begin_dawn() -> void:
	if not multiplayer.is_server():
		return
	var next_day: int = _wave_manager.current_wave + 1
	if next_day <= _wave_manager.MAX_DAYS and not is_game_over:
		_sync_time_of_day.rpc(false)
		_building_mgr.load_section_for_day(next_day)
		_setup_piles()
		_building_mgr.place_starting_ruins()

		for player in _players.get_children():
			if player.has_method("respawn"):
				player.respawn(Vector3(0, 1.0, 0))

		await _bake_nav_and_wait()
		_wave_manager.start_next_wave()

# ══════════════════════════════════════════════════════════════════════════════
# WORLD GEN
# ══════════════════════════════════════════════════════════════════════════════

func _setup_world() -> void:
	_setup_boundaries()
	_setup_city()
	_setup_piles()
	_rebake_navigation()

	if _wave_manager:
		_wave_manager.spawn_center = _building_mgr.get_section_center_for_day(1)

func _setup_city() -> void:
	_city_manager = CityManager.new()
	add_child(_city_manager)
	_city_manager.city_breached.connect(func(_e): _end_game(false))

func _setup_piles() -> void:
	var dir: Vector3 = _building_mgr.get_interior_direction()
	var right_dir = dir.cross(Vector3.UP)

	var s_pos = dir * 10.0 + Vector3(0, 0.5, 0)
	_stone_pile = _ensure_pile(_stone_pile, "StonePile", "stone", s_pos)

	var w_pos = dir * 8.0 + right_dir * 12.0 + Vector3(0, 0.5, 0)
	_wood_pile = _ensure_pile(_wood_pile, "WoodPile", "wood", w_pos)

	var m_pos = dir * 8.0 - right_dir * 12.0 + Vector3(0, 0.5, 0)
	_mortar_pile = _ensure_pile(_mortar_pile, "MortarPile", "mortar", m_pos)

func _ensure_pile(pile: Node3D, p_name: String, type: String, pos: Vector3) -> Node3D:
	if not pile:
		var script = load("res://scenes/player/supply_pile.gd")
		pile = Node3D.new()
		pile.name = p_name
		pile.set_script(script)
		pile.material_type = type
		pile.add_to_group("supply_piles")
		add_child(pile)
	pile.global_position = pos
	return pile

# ══════════════════════════════════════════════════════════════════════════════
# COMBAT & NAVIGATION
# ══════════════════════════════════════════════════════════════════════════════

@rpc("any_peer", "call_local", "reliable")
func request_throw_stone(
	origin: Vector3,
	direction: Vector3,
	power: float,
	thrower_path: NodePath
) -> void:
	if not multiplayer.is_server():
		return
	var s := STONE_SCENE.instantiate() as RigidBody3D
	s.position = origin
	_stones.add_child(s, true)
	if s.has_method("set_thrower"):
		s.set_thrower(thrower_path)
	s.apply_central_impulse(direction.normalized() * power)

func _rebake_navigation() -> void:
	if not _nav_region:
		return
	var mesh := _nav_region.navigation_mesh
	if mesh:
		mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_BOTH
		mesh.geometry_collision_mask = 0b11  # layers 1 (floor) + 2 (walls)
	_nav_region.bake_navigation_mesh()

func _bake_nav_and_wait() -> void:
	if not _nav_region:
		return
	_nav_region.bake_navigation_mesh()
	await _nav_region.bake_finished

# ══════════════════════════════════════════════════════════════════════════════
# GAME EVENTS
# ══════════════════════════════════════════════════════════════════════════════

@rpc("authority", "call_local", "reliable")
func _spawn_floating_text(pos: Vector3, text: String, color: Color, dur: float = 1.5) -> void:
	var ft = FLOATING_TEXT_SCENE.instantiate()
	ft.text = text
	ft.modulate = color
	ft.duration = dur
	add_child(ft)
	ft.global_position = pos

func _end_game(win: bool) -> void:
	is_game_over = true
	var msg = "VICTORY!" if win else "DEFEAT"
	var color = Color.LIME if win else Color.RED
	_spawn_floating_text.rpc(Vector3(0, 5, 0), msg, color, 9999.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_wall_complete() -> void:
	if not multiplayer.is_server() or is_game_over or _wave_manager.current_wave <= 0:
		return
	if _wave_manager.current_wave >= _wave_manager.MAX_DAYS:
		_end_game(true)
	else:
		_begin_night_transition()

# ══════════════════════════════════════════════════════════════════════════════
# MULTIPLAYER
# ══════════════════════════════════════════════════════════════════════════════

func _setup_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 5
	add_child(_hud_layer)

	# Root control gives children a proper full-screen rect to anchor against.
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(root)

	# Health / stamina bars + pause overlay — top-left
	_hud = GAME_HUD_SCENE.instantiate()
	root.add_child(_hud)
	_hud.pause_changed.connect(func(is_paused: bool) -> void:
		if is_instance_valid(_local_player):
			_local_player.ui_blocked = is_paused
	)

	# Minimap — bottom-right
	var minimap_script = load("res://scenes/ui/minimap.gd")
	var minimap := Control.new()
	minimap.set_script(minimap_script)
	minimap.anchor_left   = 1.0
	minimap.anchor_top    = 1.0
	minimap.anchor_right  = 1.0
	minimap.anchor_bottom = 1.0
	minimap.offset_left   = -176.0
	minimap.offset_top    = -176.0
	minimap.offset_right  = -16.0
	minimap.offset_bottom = -16.0
	minimap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	minimap.grow_vertical   = Control.GROW_DIRECTION_BEGIN
	root.add_child(minimap)

func _on_lobby_created_success(_id: int) -> void:
	_setup_hud()
	_sync_time_of_day.rpc(false)
	_building_mgr.load_section_rpc.rpc(1)
	_spawn_player(1)
	await _bake_nav_and_wait()
	_wave_manager.start_next_wave()

func _on_player_connected(id: int) -> void:
	_spawn_player(id)

func _on_player_disconnected(id: int) -> void:
	if not is_instance_valid(_players):
		return
	var n = _players.get_node_or_null(str(id))
	if n:
		n.queue_free()

func _spawn_player(id: int) -> void:
	if _players.has_node(str(id)):
		return
	var p = PLAYER_SCENE.instantiate()
	p.name = str(id)
	p.set_multiplayer_authority(id)
	_players.add_child(p, true)
	p.global_position = Vector3(0, 1.0, 0)
	p.damaged.connect(func(_a): pass)
	if id == multiplayer.get_unique_id() and is_instance_valid(_hud):
		p.health_changed.connect(_hud.update_health)
		p.stamina_changed.connect(_hud.update_stamina)
		p.sling_updated.connect(_hud.update_sling)
		p.wall_proximity_changed.connect(_hud.update_wall_needs)
	if multiplayer.is_server():
		p.died.connect(func():
			get_tree().create_timer(3.0).timeout.connect(func():
				if is_instance_valid(p):
					p.respawn(Vector3(0, 1.0, 0))
			)
		)

func _on_enemy_spawned(enemy: Node3D) -> void:
	_enemies.add_child(enemy, true)

func _on_wave_started(wave_num: int) -> void:
	_spawn_floating_text.rpc(Vector3(0, 3, 0), "Day %d Begins!" % wave_num, Color.ORANGE)
	# Breach detection activates 45 s into the wave — gives players time to build
	if is_instance_valid(_city_manager):
		get_tree().create_timer(45.0).timeout.connect(_city_manager.activate_breach)

# ══════════════════════════════════════════════════════════════════════════════
# BOILERPLATE
# ══════════════════════════════════════════════════════════════════════════════

func _setup_boundaries() -> void:
	var bounds := StaticBody3D.new()
	bounds.name = "MapBoundaries"
	add_child(bounds)
	var wall_size = Vector3(80, 20, 1)
	for i in range(4):
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = wall_size
		col.shape = box
		bounds.add_child(col)
		match i:
			0: col.position = Vector3(0, 5, 40)
			1: col.position = Vector3(0, 5, -40)
			2:
				col.position = Vector3(40, 5, 0)
				col.rotation.y = PI/2
			3:
				col.position = Vector3(-40, 5, 0)
				col.rotation.y = PI/2
