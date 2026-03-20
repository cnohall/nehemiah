extends Node3D
## Main scene controller — Simplified for the core loop.

const PLAYER_SCENE: PackedScene = preload("res://player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy/enemy.tscn")
const STONE_SCENE: PackedScene = preload("res://scenes/player/stone.tscn")
const FLOATING_TEXT_SCENE: PackedScene = preload("res://scenes/ui/floating_text.tscn")
const GAME_HUD_SCENE: PackedScene = preload("res://scenes/ui/game_hud.tscn")
const SUPPLY_PILE_SCRIPT = preload("res://scenes/player/supply_pile.gd")
const MINIMAP_SCRIPT = preload("res://scenes/ui/minimap.gd")

const MIN_ZOOM: float = 5.0
const MAX_ZOOM: float = 35.0
const ZOOM_SPEED: float = 2.0

var is_game_over: bool = false

# Camera settings
var _local_player: CharacterBody3D = null
var _city_manager: CityManager = null
var _ready_peers: Array = []
var _target_zoom: float = 14.0
var _shake_intensity: float = 0.0
var _shake_timer: float = 0.0

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
var _last_synced_city_hp: float = 100.0

# ══════════════════════════════════════════════════════════════════════════════
# PROCESS
# ══════════════════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	_update_camera(delta)

func _update_camera(delta: float) -> void:
	if is_instance_valid(_local_player):
		var cam_y := maxf(10.0, (_camera.size * 0.5) * 0.7071 + 1.5)
		_camera.global_position = _local_player.global_position + Vector3(6, cam_y, 6)

	if _camera:
		_camera.size = lerp(_camera.size, _target_zoom, 10.0 * delta)

	# Screen shake
	if _shake_timer > 0.0:
		_shake_timer -= delta
		var frac := _shake_timer / 0.15
		_camera.global_position += Vector3(
			randf_range(-1.0, 1.0),
			0.0,
			randf_range(-1.0, 1.0)
		) * _shake_intensity * frac

func shake_camera(intensity: float, duration: float) -> void:
	_shake_intensity = intensity
	_shake_timer = duration

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
	_setup_ground_texture()

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
	spawn_floating_text.rpc(Vector3(0, 3, 0), "Section Complete!", Color.LIME)
	_sync_time_of_day.rpc(true)
	get_tree().create_timer(4.0).timeout.connect(_begin_dawn)

@rpc("authority", "call_local", "reliable")
func _sync_time_of_day(is_night: bool) -> void:
	if not _sun:
		return
	var tween := create_tween()
	tween.tween_property(_sun, "light_energy", 0.05 if is_night else 1.5, 2.0)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _begin_dawn() -> void:
	if not multiplayer.is_server():
		return
	var next_day: int = _wave_manager.current_wave + 1
	if next_day <= _wave_manager.MAX_DAYS and not is_game_over:
		_sync_time_of_day.rpc(false)
		if is_instance_valid(_city_manager):
			_city_manager.reset()
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
	_setup_ground_details()
	_rebake_navigation()

	if _wave_manager:
		_wave_manager.spawn_center = _building_mgr.get_section_center_for_day(1)

func _setup_city() -> void:
	_city_manager = CityManager.new()
	add_child(_city_manager)
	_city_manager.city_breached.connect(_on_city_breached)
	_city_manager.city_depleted.connect(func(): _end_game(false))
	_city_manager.city_hp_changed.connect(_on_city_hp_changed)

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
		pile = Node3D.new()
		pile.name = p_name
		pile.set_script(SUPPLY_PILE_SCRIPT)
		pile.material_type = type
		pile.add_to_group("supply_piles")
		add_child(pile)
	pile.global_position = pos
	return pile

# ══════════════════════════════════════════════════════════════════════════════
# GROUND DETAILS  (purely visual — no gameplay impact)
# ══════════════════════════════════════════════════════════════════════════════

# ── Asset paths ───────────────────────────────────────────────────────────────
# Drop downloaded files here; code falls back to procedural if missing.
#   Ground : res://assets/textures/ground_sand.png   (ambientCG – any Sand pack, _Color.png)
#   Palm   : res://assets/models/nature/palm.glb     (Quaternius nature pack)
#   Rocks  : res://assets/models/nature/rock_a.glb   (Quaternius – rename to rock_a/b/c)
#            res://assets/models/nature/rock_b.glb
#            res://assets/models/nature/rock_c.glb
const _SAND_TEX_PATH   := "res://assets/textures/ground_sand.jpg"
const _PALM_SCENE_PATH := "res://assets/models/nature/palm.glb"
const _ROCK_PATHS: Array[String] = [
	"res://assets/models/nature/rock_a.glb",
	"res://assets/models/nature/rock_b.glb",
	"res://assets/models/nature/rock_c.glb",
]
# Adjust these after importing if the assets come in at the wrong scale
const _PALM_SCALE := 1.0
const _ROCK_SCALE := 1.0

# ── Ground texture ────────────────────────────────────────────────────────────

func _setup_ground_texture() -> void:
	var mat := _make_ground_material()
	var floor_node := _nav_region.get_node_or_null("Floor") as CSGBox3D
	if floor_node:
		floor_node.material = mat
	var desert := get_node_or_null("DesertFloor") as CSGBox3D
	if desert:
		desert.material = mat

func _make_ground_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	if FileAccess.file_exists(_SAND_TEX_PATH):
		mat.albedo_texture = load(_SAND_TEX_PATH)
		mat.uv1_scale      = Vector3(8.0, 8.0, 1.0)
	else:
		# Procedural fallback — simplex noise blending two sand tones
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency  = 0.018
		noise.seed       = 7
		const SIZE := 256
		var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
		var sand_light := Color(0.78, 0.68, 0.47)
		var sand_dark  := Color(0.65, 0.55, 0.36)
		for py in range(SIZE):
			for px in range(SIZE):
				var t := (noise.get_noise_2d(px, py) + 1.0) * 0.5
				img.set_pixel(px, py, sand_light.lerp(sand_dark, t))
		mat.albedo_texture = ImageTexture.create_from_image(img)
		mat.uv1_scale      = Vector3(6.0, 6.0, 1.0)
	return mat

# ── Detail spawning ───────────────────────────────────────────────────────────

func _setup_ground_details() -> void:
	_spawn_road()
	_spawn_rocks()
	var palm_positions: Array[Vector3] = [
		Vector3(-15, 0, -13), Vector3(-20, 0, -22), Vector3(-13, 0, -30),
		Vector3( 15, 0, -14), Vector3( 19, 0, -23), Vector3( 12, 0, -31),
		Vector3( -8, 0, -35), Vector3(  8, 0, -36),
	]
	for pos: Vector3 in palm_positions:
		_spawn_palm(pos)

func _spawn_road() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.50, 0.44, 0.34)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(3.5, 0.06, 32.0)
	mesh_inst.mesh = box
	mesh_inst.material_override = mat
	mesh_inst.position = Vector3(0, 0.52, -12.0)
	add_child(mesh_inst)

func _spawn_rocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var rock_positions: Array[Vector3] = [
		Vector3(-28, 0,  -8), Vector3( 24, 0, -11), Vector3(-19, 0, -28),
		Vector3( 32, 0, -19), Vector3(-10, 0, -38), Vector3( 16, 0, -33),
		Vector3(-35, 0,  12), Vector3( 30, 0,  16), Vector3(-22, 0,  22),
		Vector3( 26, 0,   8), Vector3(-14, 0, -42), Vector3( 10, 0, -42),
	]
	# Load whichever rock scenes are available
	var rock_scenes: Array[PackedScene] = []
	for path in _ROCK_PATHS:
		if FileAccess.file_exists(path):
			rock_scenes.append(load(path) as PackedScene)

	for pos: Vector3 in rock_positions:
		if rock_scenes.is_empty():
			_spawn_rock_procedural(pos, rng)
		else:
			var scene := rock_scenes[rng.randi() % rock_scenes.size()]
			var inst  := scene.instantiate()
			inst.position = Vector3(pos.x, 0.5, pos.z)
			inst.rotation.y = rng.randf_range(0.0, PI)
			inst.scale = Vector3.ONE * _ROCK_SCALE * rng.randf_range(0.7, 1.3)
			add_child(inst)

func _spawn_rock_procedural(pos: Vector3, rng: RandomNumberGenerator) -> void:
	# Flattened sphere — more natural than a box
	var mesh_inst := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = rng.randf_range(0.25, 0.65)
	sph.height = sph.radius * rng.randf_range(0.35, 0.65)  # squash vertically
	mesh_inst.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var grey := rng.randf_range(0.44, 0.58)
	mat.albedo_color = Color(grey, grey * 0.93, grey * 0.85)
	mesh_inst.material_override = mat
	mesh_inst.position = Vector3(pos.x, 0.5 + sph.height * 0.3, pos.z)
	mesh_inst.rotation.y = rng.randf_range(0.0, PI)
	add_child(mesh_inst)

func _spawn_palm(pos: Vector3) -> void:
	if FileAccess.file_exists(_PALM_SCENE_PATH):
		var inst := (load(_PALM_SCENE_PATH) as PackedScene).instantiate()
		inst.position = Vector3(pos.x, 0.5, pos.z)
		inst.rotation.y = randf_range(0.0, TAU)
		inst.scale = Vector3.ONE * _PALM_SCALE * randf_range(0.85, 1.15)
		add_child(inst)
	else:
		_spawn_palm_procedural(pos)

func _spawn_palm_procedural(base_pos: Vector3) -> void:
	var root := Node3D.new()
	root.position = Vector3(base_pos.x, 0.5, base_pos.z)
	add_child(root)
	var height := randf_range(5.5, 8.0)
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.42, 0.30, 0.14)
	trunk_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var trunk := MeshInstance3D.new()
	var trunk_cyl := CylinderMesh.new()
	trunk_cyl.top_radius    = 0.16
	trunk_cyl.bottom_radius = 0.24
	trunk_cyl.height        = height
	trunk.mesh = trunk_cyl
	trunk.material_override = trunk_mat
	trunk.position.y = height * 0.5
	trunk.rotation.z = randf_range(-0.08, 0.08)
	root.add_child(trunk)
	var canopy_mat := StandardMaterial3D.new()
	canopy_mat.albedo_color = Color(0.20, 0.35, 0.10)
	canopy_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var canopy := MeshInstance3D.new()
	var canopy_sph := SphereMesh.new()
	canopy_sph.radius = randf_range(1.6, 2.2)
	canopy_sph.height = canopy_sph.radius * 0.75
	canopy.mesh = canopy_sph
	canopy.material_override = canopy_mat
	canopy.position.y = height + canopy_sph.radius * 0.25
	root.add_child(canopy)

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
	_spawn_stone.rpc(origin, direction, power, thrower_path)

@rpc("authority", "call_local", "reliable")
func _spawn_stone(origin: Vector3, direction: Vector3, power: float, thrower_path: NodePath) -> void:
	var s := STONE_SCENE.instantiate() as RigidBody3D
	s.position = origin
	# On clients: disable collision so only visuals play, no double-damage
	if not multiplayer.is_server():
		s.collision_layer = 0
		s.collision_mask = 0
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
func spawn_floating_text(pos: Vector3, text: String, color: Color, dur: float = 1.5) -> void:
	var ft = FLOATING_TEXT_SCENE.instantiate()
	ft.text = text
	ft.modulate = color
	ft.duration = dur
	add_child(ft)
	ft.global_position = pos

func _end_game(win: bool) -> void:
	if not multiplayer.is_server():
		return
	var msg = "VICTORY!" if win else "DEFEAT"
	var color = Color.LIME if win else Color.RED
	spawn_floating_text.rpc(Vector3(0, 5, 0), msg, color, 9999.0)
	_sync_game_over.rpc()

@rpc("authority", "call_local", "reliable")
func _sync_game_over() -> void:
	is_game_over = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_wall_complete() -> void:
	if not multiplayer.is_server() or is_game_over or _wave_manager.current_wave <= 0:
		return
	if _wave_manager.current_wave >= _wave_manager.MAX_DAYS:
		_end_game(true)
	else:
		_begin_night_transition()

func _on_city_breached() -> void:
	spawn_floating_text.rpc(Vector3(0, 4, CityManager.ZONE_Z_START), "Enemy in Jerusalem!", Color(1.0, 0.35, 0.1), 3.0)

func _on_city_hp_changed(current: float, max_hp: float) -> void:
	# Throttle: only broadcast when HP drops by at least 1 point (or hits zero)
	if absf(current - _last_synced_city_hp) >= 1.0 or current <= 0.0:
		_last_synced_city_hp = current
		_sync_city_hp.rpc(current, max_hp)

@rpc("authority", "call_local", "unreliable_ordered")
func _sync_city_hp(current: float, max_hp: float) -> void:
	if is_instance_valid(_hud):
		_hud.update_city_hp(current, max_hp)

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
	var minimap := Control.new()
	minimap.set_script(MINIMAP_SCRIPT)
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
	if id == multiplayer.get_unique_id():
		_local_player = p
	if id == multiplayer.get_unique_id() and is_instance_valid(_hud):
		p.health_changed.connect(_hud.update_health)
		p.stamina_changed.connect(_hud.update_stamina)
		p.sling_updated.connect(_hud.update_sling)
		p.wall_proximity_changed.connect(_hud.update_wall_needs)
		p.damaged.connect(func(amount: float) -> void:
			shake_camera(clampf(amount * 0.002, 0.04, 0.18), 0.15)
			if is_instance_valid(_hud):
				_hud.flash_damage(amount)
		)
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
	spawn_floating_text.rpc(Vector3(0, 3, 0), "Day %d Begins!" % wave_num, Color.ORANGE)
	_sync_day_ui.rpc(wave_num)

@rpc("authority", "call_local", "reliable")
func _sync_day_ui(day: int) -> void:
	if is_instance_valid(_hud) and _hud.has_method("update_day"):
		var max_days: int = _wave_manager.get("MAX_DAYS") if _wave_manager else 52
		_hud.update_day(day, max_days)

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
