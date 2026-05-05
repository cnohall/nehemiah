class_name WallSection
extends Node3D

static var _shared_stone_tex: ImageTexture = null

signal progress_changed(percent: float)
signal completed
signal uncompleted

# ── Constants ─────────────────────────────────────────────────────────────────

const STONE_NEEDED: int  = 3
const WOOD_NEEDED: int   = 3
const MORTAR_NEEDED: int = 3
const UNIT: float = 100.0 / 9.0  # ~11.11% — one material unit of build progress
const MAX_HEIGHT: float = 2.4
const BLOCK_SIZE := Vector3(10.0, 0.8, 1.0)

# Build phase thresholds
const PHASE_WOOD:  float = 100.0 / 3.0   # ~33.3% — wood scaffolding complete
const PHASE_STONE: float = 200.0 / 3.0   # ~66.7% — stone layer complete

# Wall mesh state colours (per build phase)
const COLOR_EMPTY    := Color(0.28, 0.25, 0.22)  # charcoal rubble
const COLOR_WOOD     := Color(0.55, 0.40, 0.18)  # warm wood scaffolding
const COLOR_STONE    := Color(0.62, 0.58, 0.52)  # grey stone blocks
const COLOR_MORTAR   := Color(0.82, 0.76, 0.60)  # cream mortared finish
const COLOR_COMPLETE := Color(0.95, 0.92, 0.85)  # limestone white


# ── Variables ─────────────────────────────────────────────────────────────────

var stone_count: int = 0
var wood_count: int = 0
var mortar_count: int = 0
var completion_percent: float = 0.0:
	set(v):
		var max_allowed = get_max_allowed_completion()
		completion_percent = clamp(v, 0.0, max_allowed)
		_update_visuals()
		progress_changed.emit(completion_percent)
		if completion_percent >= 100.0 and not _is_completed:
			_on_completed()
		elif completion_percent < 100.0 and _is_completed:
			_on_sabotaged()

var _is_completed: bool = false

## Solid ground-level footprint — always visible even at 0% completion
var _footprint: MeshInstance3D = null

# Physics blocker — enabled whenever completion > 0
var _static_body: StaticBody3D = null
var _collision_shape: CollisionShape3D = null

# Audio
var _audio_player: AudioStreamPlayer3D = null
var _snd_stone:  AudioStream = null
var _snd_wood:   AudioStream = null
var _snd_mortar: AudioStream = null

var _indicators: WallSectionIndicators = null

var _wall_mat: StandardMaterial3D = null

@onready var _mesh: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	add_to_group("wall_sections")
	_build_footprint()
	_build_wall_material()
	_build_audio()
	_build_static_body()
	_indicators = WallSectionIndicators.new()
	_indicators.name = "Indicators"
	add_child(_indicators)
	_indicators.build()
	_update_visuals()
	call_deferred("_init_indicator_worldspace")

func _build_audio() -> void:
	_audio_player = AudioStreamPlayer3D.new()
	_audio_player.max_distance = 15.0
	_audio_player.unit_size = 2.0
	_audio_player.bus = &"Master"
	add_child(_audio_player)
	_snd_stone  = _try_load_stream("res://assets/sounds/place_stone.wav")
	_snd_wood   = _try_load_stream("res://assets/sounds/place_wood.wav")
	_snd_mortar = _try_load_stream("res://assets/sounds/place_mortar.wav")

func _try_load_stream(path: String) -> AudioStream:
	return load(path) if FileAccess.file_exists(path) else null

func _play_sound(sound_name: String) -> void:
	if not _audio_player:
		return
	var stream: AudioStream
	var pitch_range := Vector2(0.9, 1.1)
	match sound_name:
		"place_stone":  stream = _snd_stone
		"place_wood":   stream = _snd_wood
		"place_mortar": stream = _snd_mortar
		"build_loop":   stream = _snd_wood  # fallback
		"sabotage":
			stream = _snd_stone
			pitch_range = Vector2(0.45, 0.65)  # low crumble thud
	if not stream:
		return
	if _audio_player.playing and _audio_player.stream == stream and sound_name == "build_loop":
		return
	_audio_player.stream = stream
	_audio_player.pitch_scale = randf_range(pitch_range.x, pitch_range.y)
	_audio_player.play()

func _build_static_body() -> void:
	_static_body = StaticBody3D.new()
	_static_body.collision_layer = 2  # Wall layer
	_static_body.collision_mask = 0

	_collision_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(BLOCK_SIZE.x, MAX_HEIGHT, BLOCK_SIZE.z)
	_collision_shape.shape = box
	_collision_shape.position = Vector3(0, MAX_HEIGHT * 0.5, 0)
	_collision_shape.disabled = true  # Off until something is built
	_static_body.add_child(_collision_shape)
	add_child(_static_body)

func _build_footprint() -> void:
	_footprint = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(BLOCK_SIZE.x, 0.1, BLOCK_SIZE.z)
	_footprint.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.20, 0.18)
	mat.roughness = 0.95
	_footprint.material_override = mat
	_footprint.position.y = 0.05
	add_child(_footprint)

func _build_wall_material() -> void:
	_wall_mat = StandardMaterial3D.new()
	_wall_mat.roughness = 0.85
	_wall_mat.albedo_color = COLOR_EMPTY
	if _shared_stone_tex == null:
		_shared_stone_tex = _generate_stone_texture()
	_wall_mat.albedo_texture = _shared_stone_tex
	_wall_mat.uv1_scale = Vector3(1.5, 1.0, 1.0)
	_mesh.material_override = _wall_mat

func _generate_stone_texture() -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.06
	noise.seed = 7
	const SIZE := 128
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for y in range(SIZE):
		for x in range(SIZE):
			var n := (noise.get_noise_2d(x, y) + 1.0) * 0.5
			var v := lerpf(0.82, 1.0, n)
			img.set_pixel(x, y, Color(v, v * 0.98, v * 0.95))
	return ImageTexture.create_from_image(img)

func _init_indicator_worldspace() -> void:
	if is_instance_valid(_indicators):
		_indicators.init_worldspace(global_position, MAX_HEIGHT)

# ── Staged Construction Logic ─────────────────────────────────────────────────

func get_max_allowed_completion() -> float:
	# Building is phase-ordered: wood → stone → mortar.
	# Each unit of material adds ~11.11% to the buildable ceiling.
	# Stone/mortar phases are locked until the previous phase is fully stocked.
	if wood_count < WOOD_NEEDED:
		return float(wood_count) * UNIT
	if stone_count < STONE_NEEDED:
		return PHASE_WOOD + float(stone_count) * UNIT
	return PHASE_STONE + float(mortar_count) * UNIT

func is_ready_to_build() -> bool:
	return completion_percent < get_max_allowed_completion()

# ── Visuals ───────────────────────────────────────────────────────────────────

func _update_visuals() -> void:
	if not is_node_ready():
		return

	# Wall grows as materials are added + built
	var current_h: float = lerp(0.2, MAX_HEIGHT, completion_percent / 100.0)
	if is_instance_valid(_mesh):
		_mesh.scale.y = current_h / BLOCK_SIZE.y
		_mesh.position.y = current_h * 0.5

	# Enable physics blocker whenever anything is built
	if is_instance_valid(_collision_shape):
		_collision_shape.disabled = (completion_percent <= 0.0)

	_update_wall_color()
	if is_instance_valid(_indicators):
		_indicators.refresh(stone_count, wood_count, mortar_count, get_blocking_material(), _is_completed)

func _pop_visual() -> void:
	var tween := create_tween()
	tween.tween_property(_mesh, "scale:x", 1.18, 0.08)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_mesh, "scale:z", 1.18, 0.08)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_mesh, "scale:x", 1.0, 0.08)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(_mesh, "scale:z", 1.0, 0.08)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _update_wall_color() -> void:
	if not _wall_mat:
		return
	if _is_completed:
		_wall_mat.albedo_color = COLOR_COMPLETE
		_wall_mat.emission_enabled = true
		_wall_mat.emission = Color(0.5, 0.45, 0.30) * 0.4
	elif completion_percent >= PHASE_STONE:
		_wall_mat.albedo_color = COLOR_MORTAR
		_wall_mat.emission_enabled = true
		_wall_mat.emission = COLOR_MORTAR * 0.08
	elif completion_percent >= PHASE_WOOD:
		_wall_mat.albedo_color = COLOR_STONE
		_wall_mat.emission_enabled = true
		_wall_mat.emission = COLOR_STONE * 0.06
	elif completion_percent > 0.0:
		_wall_mat.albedo_color = COLOR_WOOD
		_wall_mat.emission_enabled = true
		_wall_mat.emission = COLOR_WOOD * 0.06
	else:
		_wall_mat.albedo_color = COLOR_EMPTY
		_wall_mat.emission_enabled = false

func get_blocking_material() -> String:
	# Returns the material type currently preventing further building
	if wood_count < WOOD_NEEDED:
		return "wood"
	if completion_percent >= PHASE_WOOD and stone_count < STONE_NEEDED:
		return "stone"
	if completion_percent >= PHASE_STONE and mortar_count < MORTAR_NEEDED:
		return "mortar"
	return ""


# ── Damage (enemy sabotage) ───────────────────────────────────────────────────

const DAMAGE_SCALE: float = 0.12

func take_damage(amount: float) -> void:
	if not multiplayer.is_server():
		return
	if _is_completed:  # 100% walls are immune
		return

	var old_pct := completion_percent
	var new_pct := maxf(old_pct - amount * DAMAGE_SCALE, 0.0)

	# Each 11.11% threshold crossed removes one material (highest phase first).
	var units_crossed := floori(old_pct / UNIT) - floori(new_pct / UNIT)
	if units_crossed > 0:
		for _i in range(units_crossed):
			_remove_one_material()
		sync_materials.rpc(stone_count, wood_count, mortar_count)

	# Set completion AFTER material loss so the setter re-clamps to the new ceiling.
	completion_percent = new_pct
	sync_progress.rpc(completion_percent)
	_play_sound_rpc.rpc("sabotage")

func _remove_one_material() -> void:
	# Strips one unit from the highest stocked phase (mortar → stone → wood)
	if mortar_count > 0:
		mortar_count -= 1
	elif stone_count > 0:
		stone_count -= 1
	elif wood_count > 0:
		wood_count -= 1

# ── Material delivery RPCs ────────────────────────────────────────────────────

@rpc("any_peer", "call_local", "reliable")
func request_add_material(sender_id: int) -> void:
	if not multiplayer.is_server():
		return
	var scene = get_tree().current_scene if get_tree() else null
	var players_node = scene.get_node_or_null("Players") if scene else null
	var player = players_node.get_node_or_null(str(sender_id)) if players_node else null
	
	if player == null or player.get("carried_item") == null:
		return
	var item = player.carried_item
	if item == null:
		return
	
	var m_type = item.material_type
	if try_add_material(item):
		var sound_name := "place_stone"
		match m_type:
			MaterialItem.Type.WOOD: sound_name = "place_wood"
			MaterialItem.Type.MORTAR: sound_name = "place_mortar"
		
		_play_sound_rpc.rpc(sound_name)
		sync_materials.rpc(stone_count, wood_count, mortar_count)
		sync_progress.rpc(completion_percent)
		_consume_item_rpc.rpc(player.get_path(), item.get_path())

func try_add_material(carriable: Node) -> bool:
	if not carriable is MaterialItem:
		return false

	var success = false
	match carriable.material_type:
		MaterialItem.Type.STONE:
			if stone_count < STONE_NEEDED:
				stone_count += 1
				success = true
		MaterialItem.Type.WOOD:
			if wood_count < WOOD_NEEDED:
				wood_count += 1
				success = true
		MaterialItem.Type.MORTAR:
			if mortar_count < MORTAR_NEEDED:
				mortar_count += 1
				success = true

	if success:
		_pop_visual()
		_update_visuals()
		return true

	return false

@rpc("authority", "call_local", "reliable")
func _consume_item_rpc(player_path: NodePath, item_path: NodePath) -> void:
	var player = get_node_or_null(player_path)
	if player:
		player.carried_item = null
	var item = get_node_or_null(item_path)
	if item:
		item.queue_free()

@rpc("authority", "call_local", "reliable")
func sync_materials(s: int, w: int, m: int) -> void:
	stone_count = s
	wood_count = w
	mortar_count = m
	_update_visuals()

# ── Building RPCs ─────────────────────────────────────────────────────────────

@rpc("any_peer", "call_local", "unreliable")
func request_build(amount: float) -> void:
	if not multiplayer.is_server():
		return
	if is_ready_to_build():
		# Play build sound occasionally during progress
		if int(completion_percent * 2.0) != int((completion_percent + amount) * 2.0):
			_play_sound_rpc.rpc("build_loop")
		
		completion_percent += amount
		sync_progress.rpc(completion_percent)

@rpc("authority", "call_local", "unreliable")
func sync_progress(pct: float) -> void:
	completion_percent = pct
	_update_visuals()

@rpc("authority", "call_local", "reliable")
func _play_sound_rpc(sound_name: String) -> void:
	_play_sound(sound_name)

# ── Completion callbacks ──────────────────────────────────────────────────────

func _on_completed() -> void:
	_is_completed = true
	completed.emit()
	var main = get_tree().current_scene
	if main.has_method("shake_camera"):
		main.shake_camera(0.15, 0.12)
	_play_completion_flash()

func _play_completion_flash() -> void:
	if not is_instance_valid(_mesh) or not _wall_mat:
		return
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void:
		_wall_mat.emission_enabled = true
		_wall_mat.emission = Color(1.0, 0.95, 0.85) * v
	, 2.0, 0.4, 0.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_mesh, "scale", Vector3(1.08, 1.0, 1.08), 0.12)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_mesh, "scale", Vector3.ONE, 0.2)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _on_sabotaged() -> void:
	_is_completed = false
	uncompleted.emit()
	var main = get_tree().current_scene
	if main.has_method("shake_camera"):
		main.shake_camera(0.08, 0.10)
