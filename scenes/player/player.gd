extends CharacterBody3D
## PlayerController — Simplified Core Worker
## ─────────────────────────────────────────────────────────────────────────────

signal health_changed(new_val: float)
signal died
signal damaged(amount: float)

const FALLBACK_ANIM: String = "idle_down"

# Building Constants
const BUILD_RANGE: float = 4.0
const BUILD_RATE: float = 25.0 # 25% per second

# Stamina Constants
const MAX_STAMINA: float = 100.0
const STAMINA_REGEN: float = 12.0        # Slow recovery — you're a laborer, not an athlete
const STAMINA_DRAIN: float = 50.0        # ~2s of full sprint before exhausted
const SPRINT_MULTIPLIER: float = 1.5     # Labored push, not a dash
const STAMINA_RECOVER_THRESHOLD: float = 25.0  # Must recover to 25% before sprinting again

@export var camera_path: NodePath = NodePath("../IsometricCamera")
@export var move_speed: float = 6.0
@export var jump_velocity: float = 4.5

@export var health: float = 100.0:
	set(v):
		health = clampf(v, 0.0, 100.0)
		if is_multiplayer_authority() and _hud:
			_hud.update_health(health)
		if health <= 0 and not _is_dead:
			_die()

var stamina: float = 100.0:
	set(v):
		stamina = clampf(v, 0.0, MAX_STAMINA)
		if is_multiplayer_authority() and _hud:
			_hud.update_stamina(stamina, MAX_STAMINA)

# Private State
var carried_item: MaterialItem = null
var current_animation: String = FALLBACK_ANIM
var is_sprinting: bool = false

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _camera: Camera3D = null
var _last_facing: String = "down"
var _hud: CanvasLayer = null
var _is_dead: bool = false
var _exhausted: bool = false
var _slinger: Slinger = null

@onready var _sprite: AnimatedSprite3D        = $AnimatedSprite3D
@onready var _sync:   MultiplayerSynchronizer = $MultiplayerSynchronizer

# ══════════════════════════════════════════════════════════════════════════════
# READY & SETUP
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	add_to_group("players")
	_setup_multiplayer_sync()
	_resolve_camera()

	if is_multiplayer_authority():
		var hud_scene = load("res://scenes/ui/game_hud.tscn")
		_hud = hud_scene.instantiate()
		add_child(_hud)
		_hud.update_health(health)
		_notify_carried_changed()

		_slinger = Slinger.new()
		_slinger.name = "Slinger"
		add_child(_slinger)
		_slinger.init(self, _camera, _hud)

func _setup_multiplayer_sync() -> void:
	_sync.root_path = NodePath("..")
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:global_position"))
	config.add_property(NodePath(".:current_animation"))
	_sync.replication_config = config

func _resolve_camera() -> void:
	_camera = get_node_or_null(camera_path)
	if _camera == null:
		_camera = get_viewport().get_camera_3d()

# ══════════════════════════════════════════════════════════════════════════════
# PROCESS
# ══════════════════════════════════════════════════════════════════════════════

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority() or _is_dead:
		_apply_remote_animation()
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta

	var move_dir := _get_isometric_input()
	var current_speed := move_speed
	
	# Sprint Logic — can't sprint carrying stone, can't sprint while exhausted
	var carrying_stone := carried_item != null and carried_item.material_type == MaterialItem.Type.STONE
	var wants_to_sprint := Input.is_key_pressed(KEY_SHIFT) and move_dir != Vector3.ZERO and not carrying_stone
	if wants_to_sprint and not _exhausted:
		is_sprinting = true
		current_speed *= SPRINT_MULTIPLIER
		stamina -= STAMINA_DRAIN * delta
		if stamina <= 0.0:
			_exhausted = true
	else:
		is_sprinting = false
		stamina += STAMINA_REGEN * delta
		if _exhausted and stamina >= STAMINA_RECOVER_THRESHOLD:
			_exhausted = false

	if carried_item:
		current_speed *= (1.0 - carried_item.speed_penalty)

	velocity.x = move_dir.x * current_speed
	velocity.z = move_dir.z * current_speed

	if move_dir != Vector3.ZERO:
		_update_walk_animation(move_dir)
	else:
		_update_idle_animation()

	move_and_slide()

	if _slinger:
		_slinger.process(delta, Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))
	_process_building(delta)

func _get_isometric_input() -> Vector3:
	var raw := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	if raw == Vector2.ZERO or _camera == null:
		return Vector3.ZERO
	var basis := _camera.global_transform.basis
	var world_dir := (basis.x * raw.x) + (Vector3(basis.z.x, 0, basis.z.z).normalized() * raw.y)
	return world_dir.normalized()

# ══════════════════════════════════════════════════════════════════════════════
# ACTIONS
# ══════════════════════════════════════════════════════════════════════════════

func _process_building(delta: float) -> void:
	var building_mgr = get_tree().current_scene.get_node_or_null("BuildingManager")
	if not building_mgr:
		return

	var nearest_section = building_mgr.get_nearest_section(global_position, BUILD_RANGE)
	if nearest_section:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if carried_item:
				nearest_section.request_add_material.rpc_id(1, multiplayer.get_unique_id())
			elif nearest_section.is_ready_to_build():
				nearest_section.request_build.rpc_id(1, BUILD_RATE * delta)
				if _hud:
					_hud.update_place(nearest_section.completion_percent, 100.0)
			else:
				# Blocked - show what's needed
				if _hud:
					var m_type = nearest_section.get_blocking_material()
					var needed = m_type.to_upper()
					var color = Color.WHITE
					match m_type:
						"wood": color = Color(0.58, 0.36, 0.16)
						"stone": color = Color(0.72, 0.68, 0.60)
						"mortar": color = Color(0.50, 0.50, 0.58)
					_hud.update_place(nearest_section.completion_percent, 100.0, "NEED: " + needed, color)
		elif _hud:
			# Not holding LMB, but near - show current progress bar quietly?
			# Actually, let's keep it clean and only show when active
			_hud.update_place(0, 1)
	elif _hud:
		_hud.update_place(0, 1)

func _handle_interaction() -> void:
	var building_mgr = get_tree().current_scene.get_node_or_null("BuildingManager")

	# 1. Try interacting with Wall Section (if carrying or building)
	var nearest_section = null
	if building_mgr:
		nearest_section = building_mgr.get_nearest_section(global_position, BUILD_RANGE)

	if nearest_section:
		if carried_item:
			nearest_section.request_add_material.rpc_id(1, multiplayer.get_unique_id())
			return

	# 2. Try picking up a dropped item (if hands are empty)
	if carried_item == null:
		var items = get_tree().get_nodes_in_group("carriables")
		var best_item: MaterialItem = null
		var min_item_dist = 2.5
		for item in items:
			if item is MaterialItem and item.carrier == null:
				var d = global_position.distance_to(item.global_position)
				if d < min_item_dist:
					min_item_dist = d; best_item = item
		if best_item:
			request_pickup.rpc_id(1, best_item.get_path())
			return

	# 3. Try getting from a supply pile (if hands are empty)
	if carried_item == null:
		var piles = get_tree().get_nodes_in_group("supply_piles")
		var best_pile: Node3D = null
		var min_pile_dist = 3.0
		for pile in piles:
			var d = global_position.distance_to(pile.global_position)
			if d < min_pile_dist:
				min_pile_dist = d; best_pile = pile
		if best_pile:
			best_pile.request_spawn_material.rpc_id(1, multiplayer.get_unique_id())
			return

# ══════════════════════════════════════════════════════════════════════════════
## NETWORK
# ══════════════════════════════════════════════════════════════════════════════

@rpc("any_peer", "call_local", "reliable")
func request_pickup(path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var item = get_node_or_null(path)
	if item and item is MaterialItem and item.carrier == null:
		sync_pickup.rpc(path)

@rpc("authority", "call_local", "reliable")
func sync_pickup(path: NodePath) -> void:
	var item = get_node_or_null(path)
	if item and item is MaterialItem:
		item.pick_up(self)
		carried_item = item
		_notify_carried_changed()

@rpc("any_peer", "call_local", "reliable")
func request_drop(pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	if carried_item:
		sync_drop.rpc(pos)

@rpc("authority", "call_local", "reliable")
func sync_drop(pos: Vector3) -> void:
	if carried_item:
		carried_item.drop(pos)
		carried_item = null
		_notify_carried_changed()

func _notify_carried_changed() -> void:
	if is_multiplayer_authority() and _hud:
		var m_name = carried_item.material_name if carried_item else ""
		_hud.update_carried(m_name)

func take_damage(amount: float) -> void:
	if not multiplayer.is_server() or _is_dead:
		return
	_take_damage_rpc.rpc(amount)

@rpc("authority", "call_local", "reliable")
func _take_damage_rpc(amount: float) -> void:
	health -= amount
	damaged.emit(amount)
	if health <= 0 and not _is_dead:
		_die()

func _die() -> void:
	_is_dead = true; visible = false; died.emit()

func respawn(pos: Vector3) -> void:
	health = 100.0; _is_dead = false; visible = true; global_position = pos

# ══════════════════════════════════════════════════════════════════════════════
## ANIMATION
# ══════════════════════════════════════════════════════════════════════════════

func _update_walk_animation(world_dir: Vector3) -> void:
	_last_facing = _resolve_screen_direction(world_dir)
	_play_animation("walk_" + _last_facing)

func _update_idle_animation() -> void:
	_play_animation("idle_" + _last_facing)

func _resolve_screen_direction(world_dir: Vector3) -> String:
	var angle := rad_to_deg(atan2(world_dir.x, world_dir.z))
	var snap := int(fmod(snapped(angle, 45.0) + 360.0, 360.0))
	var lookup = {
		0:   "up_right",  # S+D → southeast
		45:  "up",       # D   → east
		90:  "up_left",    # W+D → northeast
		135: "left",          # W   → north
		180: "down_left",     # W+A → northwest
		225: "down",        # A   → west
		270: "down_right",   # S+A → southwest
		315: "right"         # S   → south
	}
	return lookup.get(snap, "down")

func _play_animation(anim_name: String) -> void:
	if current_animation == anim_name:
		return
	current_animation = anim_name
	if _sprite and _sprite.sprite_frames and _sprite.sprite_frames.has_animation(anim_name):
		_sprite.play(anim_name)

func _apply_remote_animation() -> void:
	if _sprite and _sprite.sprite_frames and _sprite.animation != current_animation:
		if _sprite.sprite_frames.has_animation(current_animation):
			_sprite.play(current_animation)

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or _is_dead:
		return
	if event.is_action_pressed("interact"):
		_handle_interaction()
	if event.is_action_pressed("drop"):
		var drop_pos = global_position + Vector3(0, 0, -1).rotated(Vector3.UP, rotation.y)
		request_drop.rpc_id(1, drop_pos)
