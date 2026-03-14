extends Node2D
## Main scene controller — 2D top-down version.

const PLAYER_SCENE: PackedScene = preload("res://player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy/enemy.tscn")
const STONE_SCENE: PackedScene = preload("res://scenes/player/stone.tscn")
const FLOATING_TEXT_SCENE: PackedScene = preload("res://scenes/ui/floating_text.tscn")

const MIN_ZOOM: float = 10.0
const MAX_ZOOM: float = 50.0
const ZOOM_SPEED: float = 2.0

var is_game_over: bool = false

var _local_player: CharacterBody2D = null
var _city_manager: CityManager = null
var _ready_peers: Array = []
var _target_zoom: float = 25.0

# Material Piles
var _stone_pile: Node2D = null
var _wood_pile: Node2D = null
var _mortar_pile: Node2D = null

@onready var _nav_region: NavigationRegion2D = $NavigationRegion2D
@onready var _blocks: Node2D = $NavigationRegion2D/Blocks
@onready var _players: Node2D = $Players
@onready var _enemies: Node2D = $Enemies
@onready var _stones: Node2D = $Stones
@onready var _camera: Camera2D = $Camera2D
@onready var _canvas_modulate: CanvasModulate = $CanvasModulate
@onready var _wave_manager: Node = $WaveManager
@onready var _building_mgr: Node = $BuildingManager

# ══════════════════════════════════════════════════════════════════════════════
# PROCESS
# ══════════════════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	_update_local_player_ref()
	_update_camera(delta)

func _update_local_player_ref() -> void:
	if not is_instance_valid(_local_player):
		for child in _players.get_children():
			if child is CharacterBody2D and child.is_multiplayer_authority():
				_local_player = child
				_sync_hud_local()
				break

func _update_camera(delta: float) -> void:
	if is_instance_valid(_local_player):
		_camera.global_position = _local_player.global_position

	if _camera:
		var z := _camera.zoom.x
		z = lerp(z, _target_zoom, 10.0 * delta)
		_camera.zoom = Vector2(z, z)

func _unhandled_input(event: InputEvent) -> void:
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

		_wave_manager.current_wave = next_day - 1
		_begin_dawn()

# ══════════════════════════════════════════════════════════════════════════════
# READY & SETUP
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_connect_signals()
	_setup_nav_polygon()

	if multiplayer.is_server():
		_setup_world()

func _setup_nav_polygon() -> void:
	if not _nav_region:
		return
	# Define walkable area covering the full play field (±65 units)
	var nav_poly := NavigationPolygon.new()
	nav_poly.add_outline(PackedVector2Array([
		Vector2(-65, -65), Vector2(-65, 65),
		Vector2(65, 65),   Vector2(65, -65)
	]))
	nav_poly.make_polygons_from_outlines()
	_nav_region.navigation_polygon = nav_poly

func _connect_signals() -> void:
	_building_mgr.blocks_changed.connect(_on_blocks_changed)
	_building_mgr.wall_complete.connect(_on_wall_complete)
	_building_mgr.navigation_changed.connect(_rebake_navigation)

	NetworkManager.lobby_created_success.connect(_on_lobby_created_success)
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
	_spawn_floating_text.rpc(Vector2(0, -20), "Day %d Complete!" % wave_num, Color.LIME)
	if multiplayer.is_server() and not is_game_over:
		_wave_manager.stop_spawning()
		for enemy in _enemies.get_children():
			enemy.queue_free()

		_sync_time_of_day.rpc(true)  # To Night
		get_tree().create_timer(4.0).timeout.connect(_begin_dawn)

@rpc("authority", "call_local", "reliable")
func _sync_time_of_day(is_night: bool) -> void:
	if _canvas_modulate:
		_canvas_modulate.color = Color(0.15, 0.12, 0.20) if is_night else Color.WHITE

func _begin_dawn() -> void:
	if not multiplayer.is_server():
		return
	var next_day: int = _wave_manager.current_wave + 1
	if next_day <= _wave_manager.MAX_DAYS and not is_game_over:
		_sync_time_of_day.rpc(false)  # To Day
		_building_mgr.load_section_for_day(next_day)
		_setup_piles()
		_building_mgr.place_starting_ruins()

		for player in _players.get_children():
			if player.has_method("respawn"):
				player.respawn(Vector2.ZERO)

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
	var dir: Vector2 = _building_mgr.get_interior_direction()  # Vector2.DOWN
	var right_dir := Vector2(dir.y, -dir.x)  # perpendicular to interior dir

	# Place piles in the safe zone (y=10, between wall at y=0 and city at y=20)
	var s_pos = dir * 10.0
	_stone_pile = _ensure_pile(_stone_pile, "StonePile", "stone", s_pos)

	var w_pos = dir * 8.0 + right_dir * 12.0
	_wood_pile = _ensure_pile(_wood_pile, "WoodPile", "wood", w_pos)

	var m_pos = dir * 8.0 - right_dir * 12.0
	_mortar_pile = _ensure_pile(_mortar_pile, "MortarPile", "mortar", m_pos)

func _ensure_pile(pile: Node2D, p_name: String, type: String, pos: Vector2) -> Node2D:
	if not pile:
		var script = load("res://scenes/player/supply_pile.gd")
		pile = Node2D.new()
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
	origin: Vector2,
	direction: Vector2,
	power: float,
	thrower_path: NodePath
) -> void:
	if not multiplayer.is_server():
		return
	var s := STONE_SCENE.instantiate() as RigidBody2D
	s.position = origin
	_stones.add_child(s, true)
	if s.has_method("set_thrower"):
		s.set_thrower(thrower_path)
	s.apply_central_impulse(direction.normalized() * power)

func _rebake_navigation() -> void:
	if _nav_region:
		_nav_region.bake_navigation_polygon()

func _bake_nav_and_wait() -> void:
	if not _nav_region:
		return
	_nav_region.bake_navigation_polygon()
	await _nav_region.bake_finished

# ══════════════════════════════════════════════════════════════════════════════
# HUD & EVENTS
# ══════════════════════════════════════════════════════════════════════════════

func _on_blocks_changed(_total: int) -> void:
	_sync_hud_local()

func _sync_hud_local() -> void:
	if _local_player and _local_player.get("_hud"):
		var hud = _local_player._hud
		hud.update_wave(_wave_manager.current_wave)
		hud.update_progress(_building_mgr.blocks_placed, _building_mgr.blocks_for_win)
		hud.update_section_info(_wave_manager.current_wave)

@rpc("authority", "call_local", "reliable")
func _spawn_floating_text(pos: Vector2, text: String, color: Color, dur: float = 1.5) -> void:
	var ft = FLOATING_TEXT_SCENE.instantiate()
	ft.text = text
	ft.modulate = color
	ft.duration = dur
	add_child(ft)
	ft.global_position = pos

func _end_game(win: bool) -> void:
	is_game_over = true
	_show_game_over_rpc.rpc(win, _wave_manager.current_wave)

@rpc("authority", "call_local", "reliable")
func _show_game_over_rpc(win: bool, day: int) -> void:
	if _local_player and _local_player.get("_hud"):
		_local_player._hud.show_game_over(win, day)

func _on_wall_complete() -> void:
	if not multiplayer.is_server():
		return
	if _wave_manager.current_wave >= _wave_manager.MAX_DAYS:
		_end_game(true)
	else:
		_spawn_floating_text.rpc(Vector2(0, -20), "Section Complete!", Color.LIME)
		_on_wave_cleared(_wave_manager.current_wave)

# ══════════════════════════════════════════════════════════════════════════════
# MULTIPLAYER
# ══════════════════════════════════════════════════════════════════════════════

func _on_lobby_created_success(_id: int) -> void:
	_building_mgr.load_section_rpc.rpc(1)
	_spawn_player(1)
	await _bake_nav_and_wait()
	_wave_manager.start_next_wave()

func _on_player_connected(id: int) -> void:
	_spawn_player(id)

func _on_player_disconnected(id: int) -> void:
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
	p.global_position = Vector2.ZERO
	p.damaged.connect(func(_a): pass)
	if multiplayer.is_server():
		p.died.connect(func():
			get_tree().create_timer(3.0).timeout.connect(func():
				if is_instance_valid(p):
					p.respawn(Vector2.ZERO)
			)
		)

func _on_enemy_spawned(enemy: Node) -> void:
	_enemies.add_child(enemy, true)

func _on_wave_started(wave_num: int) -> void:
	_spawn_floating_text.rpc(Vector2(0, -20), "Day %d Begins!" % wave_num, Color.ORANGE)
	_sync_hud_local()

# ══════════════════════════════════════════════════════════════════════════════
# BOILERPLATE
# ══════════════════════════════════════════════════════════════════════════════

func _setup_boundaries() -> void:
	var bounds := StaticBody2D.new()
	bounds.name = "MapBoundaries"
	add_child(bounds)

	# Four walls at map edges (±65 units)
	var edges := [
		[Vector2(0, -65), Vector2(130, 2)],   # Top
		[Vector2(0, 65),  Vector2(130, 2)],   # Bottom
		[Vector2(-65, 0), Vector2(2, 130)],   # Left
		[Vector2(65, 0),  Vector2(2, 130)],   # Right
	]
	for edge in edges:
		var col := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = edge[1]
		col.shape = rect
		col.position = edge[0]
		bounds.add_child(col)
