extends CharacterBody3D
## PlayerController
## ─────────────────────────────────────────────────────────────────────────────
## Node:    CharacterBody3D  (root of the Player scene)
## Script:  scenes/player/player.gd
##
## Responsibilities:
##   • WASD movement projected onto the isometric camera's XZ plane
##   • 8-directional AnimatedSprite3D (Y-Billboard) animation state machine
##   • MultiplayerSynchronizer configured at runtime for position + anim sync
##   • Health, Stone carrying, and Role-specific stats
## ─────────────────────────────────────────────────────────────────────────────

signal health_changed(new_val: float)
signal died
signal damaged(amount: float)

# ══════════════════════════════════════════════════════════════════════════════
# EXPORTS — tweak in the Inspector without editing code
# ══════════════════════════════════════════════════════════════════════════════

## NodePath to the scene's Camera3D.  Assign in the Inspector.
## If left blank the script falls back to get_viewport().get_camera_3d().
@export var camera_path: NodePath = NodePath("../IsometricCamera")

## Walk speed in metres per second.
@export var move_speed: float = 5.0
@export var jump_velocity: float = 4.5

# ══════════════════════════════════════════════════════════════════════════════
# CONSTANTS
# ══════════════════════════════════════════════════════════════════════════════

## Fallback animation used when a requested animation is missing in SpriteFrames.
const FALLBACK_ANIM: String = "idle_down"

const ROLES: Dictionary = {
	"builder": {
		"name": "Builder",
		"stone_cap": 5,
		"place_speed": 1.4, # 1.4x faster (1.4s vs 2.0s)
		"combat_bonus": 1.0,
		"reload_time": 0.5,
		"desc": "Builds the wall faster."
	},
	"slinger": {
		"name": "Slinger",
		"stone_cap": 5,
		"place_speed": 1.0,
		"combat_bonus": 1.2, # +20% damage
		"reload_time": 0.35,
		"desc": "Powerful stone throws."
	},
	"porter": {
		"name": "Porter",
		"stone_cap": 10,
		"place_speed": 1.0,
		"combat_bonus": 1.0,
		"reload_time": 0.5,
		"desc": "Carries more stones."
	}
}

# ══════════════════════════════════════════════════════════════════════════════
# PRIVATE VARIABLES
# ══════════════════════════════════════════════════════════════════════════════

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _camera: Camera3D = null

## Remembers the last direction faced so idle animations preserve facing.
var _last_facing: String = "down"

var _hud: CanvasLayer = null
var _is_dead: bool = false
var _place_timer: float = 0.0
var _target_blueprint_pos: Vector3 = Vector3.INF
var _placing_is_new_column: bool = false

# ══════════════════════════════════════════════════════════════════════════════
# REPLICATED STATE
## These vars are watched by the MultiplayerSynchronizer child node.
# ══════════════════════════════════════════════════════════════════════════════

## The currently-playing animation name — synced across the network.
var current_animation: String = FALLBACK_ANIM

@export var role: String = "slinger":
	set(v):
		role = v
		if is_node_ready(): _apply_role_stats()

@export var health: float = 100.0:
	set(v):
		health = clampf(v, 0.0, 100.0)
		if is_multiplayer_authority() and _hud:
			_hud.update_health(health)
		if health <= 0 and not _is_dead:
			_die()

@export var stones_carried: int = 0:
	set(v):
		stones_carried = clampi(v, 0, max_stones)
		if is_multiplayer_authority() and _hud:
			_hud.update_stones(stones_carried, max_stones)

@export var max_stones: int = 5:
	set(v):
		max_stones = v
		if is_multiplayer_authority() and _hud:
			_hud.update_stones(stones_carried, max_stones)

# ══════════════════════════════════════════════════════════════════════════════
# NODE REFERENCES — resolved at runtime via @onready
# ══════════════════════════════════════════════════════════════════════════════

@onready var _sprite: AnimatedSprite3D        = $AnimatedSprite3D
@onready var _sync:   MultiplayerSynchronizer = $MultiplayerSynchronizer

# ══════════════════════════════════════════════════════════════════════════════
# BUILDING SYSTEM — private state
# ══════════════════════════════════════════════════════════════════════════════

## How wide/long/tall a placed stone brick is, in world-units.
const BLOCK_SIZE := Vector3(2.0, 0.8, 1.0)
const BLOCK_Y := BLOCK_SIZE.y * 0.5 

## The ghost (preview) node, created once and reused every frame.
var _ghost: MeshInstance3D = null
var _aim_dot: MeshInstance3D = null

## True while the RMB is held (stone-throw charge); we skip placement then.
var _charging_throw: bool = false
var _throw_power: float = 0.0
var _reload_timer: float = 0.0
const MAX_THROW_POWER: float = 30.0
const CHARGE_RATE: float = 30.0

## Sprint / stamina
var stamina: float = 100.0
const MAX_STAMINA: float = 100.0
const SPRINT_SPEED_MULT: float = 1.6
const SPRINT_DRAIN: float = 30.0
const STAMINA_REGEN: float = 20.0
const BUILD_RANGE: float = 6.0

# ══════════════════════════════════════════════════════════════════════════════
# READY
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	add_to_group("players")
	_setup_multiplayer_sync()
	_resolve_camera()
	_init_building_system()
	_apply_role_stats()
	
	if is_multiplayer_authority():
		var hud_scene = load("res://scenes/ui/game_hud.tscn")
		_hud = hud_scene.instantiate()
		add_child(_hud)
		_hud.update_health(health)
		_hud.update_stones(stones_carried, max_stones)
		_hud.update_role(role)

func _apply_role_stats() -> void:
	var data = ROLES.get(role, ROLES["slinger"])
	max_stones = data["stone_cap"]
	if is_multiplayer_authority() and _hud:
		_hud.update_role(data["name"])
		_hud.update_stones(stones_carried, max_stones)

func _setup_multiplayer_sync() -> void:
	_sync.root_path = NodePath("..")
	var config := SceneReplicationConfig.new()

	config.add_property(NodePath(".:global_position"))
	config.property_set_spawn(NodePath(".:global_position"), true)
	config.property_set_watch(NodePath(".:global_position"), true)

	config.add_property(NodePath(".:current_animation"))
	config.property_set_spawn(NodePath(".:current_animation"), true)
	config.property_set_watch(NodePath(".:current_animation"), true)
	
	config.add_property(NodePath(".:role"))
	config.property_set_spawn(NodePath(".:role"), true)
	config.property_set_watch(NodePath(".:role"), true)

	_sync.replication_config = config


func _resolve_camera() -> void:
	_camera = get_node_or_null(camera_path)
	if _camera == null:
		_camera = get_viewport().get_camera_3d()


# ══════════════════════════════════════════════════════════════════════════════
# PHYSICS PROCESS
# ══════════════════════════════════════════════════════════════════════════════

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority() or _is_dead:
		_apply_remote_animation()
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta
	
	if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
		velocity.y = jump_velocity

	var move_dir := _get_isometric_input()
	var sprinting := Input.is_key_pressed(KEY_SHIFT) and move_dir != Vector3.ZERO and stamina > 0.0
	var speed := move_speed * (SPRINT_SPEED_MULT if sprinting else 1.0)

	if sprinting:
		stamina = maxf(0.0, stamina - SPRINT_DRAIN * delta)
	else:
		stamina = minf(MAX_STAMINA, stamina + STAMINA_REGEN * delta)

	if _hud and _hud.has_method("update_stamina"):
		_hud.update_stamina(stamina)

	if move_dir != Vector3.ZERO:
		velocity.x = move_dir.x * speed
		velocity.z = move_dir.z * speed
		_update_walk_animation(move_dir)
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)
		_update_idle_animation()

	move_and_slide()
	
	_process_combat(delta)
	_process_building(delta)


func _get_isometric_input() -> Vector3:
	var raw := Vector2(
		Input.get_axis("move_left",  "move_right"),
		Input.get_axis("move_up",    "move_down")
	)
	if raw == Vector2.ZERO: return Vector3.ZERO
	if _camera == null: return Vector3(raw.x, 0.0, raw.y).normalized()

	var basis := _camera.global_transform.basis
	var cam_forward := -basis.z
	var cam_right   :=  basis.x
	cam_forward.y = 0.0
	cam_right.y   = 0.0
	var world_dir := (cam_forward.normalized() * -raw.y) + (cam_right.normalized() * raw.x)
	return world_dir.normalized()

# ══════════════════════════════════════════════════════════════════════════════
# COMBAT & BUILDING
# ══════════════════════════════════════════════════════════════════════════════

func _process_combat(delta: float) -> void:
	if _reload_timer > 0:
		_reload_timer -= delta
		return

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_charging_throw = true
		_throw_power = min(_throw_power + CHARGE_RATE * delta, MAX_THROW_POWER)
		if _hud: _hud.update_power(_throw_power, MAX_THROW_POWER)
		if _aim_dot: _aim_dot.visible = true
	else:
		if _charging_throw:
			_throw_stone()
			_reload_timer = ROLES.get(role, ROLES["slinger"])["reload_time"]
		_charging_throw = false
		_throw_power = 0.0
		if _hud: _hud.update_power(0, MAX_THROW_POWER)
		if _aim_dot: _aim_dot.visible = false

func _throw_stone() -> void:
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = _camera.project_ray_origin(mouse_pos)
	var ray_dir = _camera.project_ray_normal(mouse_pos)
	# Floor is at y=0.5
	var t = (0.5 - ray_origin.y) / ray_dir.y
	var target = ray_origin + ray_dir * t
	
	# Target the center of the enemy (around y=1.0) instead of their feet
	var target_3d = Vector3(target.x, 1.0, target.z)
	var spawn_origin = global_position + Vector3(0, 1.2, 0)
	var dir = (target_3d - spawn_origin).normalized()
	
	# Add a slight upward lift based on distance to help the stone reach the target
	var dist = spawn_origin.distance_to(target_3d)
	dir.y += clamp(dist * 0.015, 0.0, 0.3)
	
	var main = get_tree().current_scene
	if main.has_method("request_throw_stone"):
		main.request_throw_stone.rpc_id(1, spawn_origin, dir, _throw_power, get_path())

func _process_building(delta: float) -> void:
	if _place_timer > 0:
		# If user releases button or moves too far, cancel placement
		var dist = global_position.distance_to(_target_blueprint_pos)
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or dist > BUILD_RANGE:
			_cancel_placement()
			return
			
		_place_timer -= delta
		if _hud: _hud.update_place(_place_timer, _get_base_place_duration())
		if _place_timer <= 0:
			_complete_placement()

func _cancel_placement() -> void:
	_place_timer = 0.0
	_target_blueprint_pos = Vector3.INF
	if _hud: _hud.update_place(0, 1.0)

func _get_base_place_duration() -> float:
	var mult = ROLES.get(role, ROLES["slinger"])["place_speed"]
	return 2.0 / mult

func _complete_placement() -> void:
	if _target_blueprint_pos == Vector3.INF: return
	
	var main = get_tree().current_scene
	var building_mgr = main.get_node_or_null("BuildingManager")
	if building_mgr:
		building_mgr.server_place_block.rpc_id(1, _target_blueprint_pos, _target_rotation)
	_target_blueprint_pos = Vector3.INF

# ══════════════════════════════════════════════════════════════════════════════
# ANIMATION & GHOST
# ══════════════════════════════════════════════════════════════════════════════

func _update_walk_animation(world_dir: Vector3) -> void:
	var facing := _resolve_screen_direction(world_dir)
	_last_facing = facing
	_play_animation("walk_" + facing)

func _update_idle_animation() -> void:
	_play_animation("idle_" + _last_facing)

func _resolve_screen_direction(world_dir: Vector3) -> String:
	var screen := _world_dir_to_screen(world_dir)
	var angle_deg := rad_to_deg(atan2(screen.x, screen.y))
	var snap := fmod(snapped(angle_deg, 45.0) + 360.0, 360.0)
	match int(snap):
		0: return "up"
		45: return "up_right"
		90: return "right"
		135: return "down_right"
		180: return "down"
		225: return "down_left"
		270: return "left"
		315: return "up_left"
		_: return "down"

func _world_dir_to_screen(world_dir: Vector3) -> Vector2:
	if _camera == null: return Vector2(world_dir.x, -world_dir.z)
	var basis := _camera.global_transform.basis
	var screen_x := world_dir.dot(basis.x)
	var cam_up_flat := Vector3(basis.y.x, 0.0, basis.y.z).normalized()
	var screen_y := world_dir.dot(cam_up_flat)
	return Vector2(screen_x, screen_y).normalized()

func _play_animation(anim_name: String) -> void:
	if current_animation == anim_name: return
	current_animation = anim_name
	if _sprite and _sprite.sprite_frames and _sprite.sprite_frames.has_animation(anim_name):
		_sprite.play(anim_name)

func _apply_remote_animation() -> void:
	if _sprite == null or _sprite.animation == current_animation: return
	if _sprite.sprite_frames and _sprite.sprite_frames.has_animation(current_animation):
		_sprite.play(current_animation)

func _init_building_system() -> void:
	if not is_multiplayer_authority(): return
	_ghost = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = BLOCK_SIZE
	_ghost.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.6, 1.0, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost.material_override = mat
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	get_tree().current_scene.add_child(_ghost)
	
	_aim_dot = MeshInstance3D.new()
	var dot_mesh := CylinderMesh.new()
	dot_mesh.top_radius = 0.25
	dot_mesh.bottom_radius = 0.25
	dot_mesh.height = 0.05
	_aim_dot.mesh = dot_mesh
	var dot_mat := StandardMaterial3D.new()
	dot_mat.albedo_color = Color(1.0, 0.0, 0.0, 0.5) # Semi-transparent red
	dot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_mat.no_depth_test = true
	dot_mat.render_priority = 100
	_aim_dot.material_override = dot_mat
	_aim_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim_dot.visible = false
	get_tree().current_scene.add_child(_aim_dot)

func _process(_delta: float) -> void:
	if not is_multiplayer_authority() or _is_dead: return
	_update_ghost_block()
	_update_aim_dot()

func _update_aim_dot() -> void:
	if _aim_dot == null or not _aim_dot.visible or _camera == null: return
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := _camera.project_ray_origin(mouse_pos)
	var ray_dir    := _camera.project_ray_normal(mouse_pos)
	if abs(ray_dir.y) < 0.001: return
	# Floor is at y=0.5
	var t := (0.5 - ray_origin.y) / ray_dir.y
	if t < 0.0: return
	var hit := ray_origin + ray_dir * t
	_aim_dot.global_position = hit + Vector3(0, 0.1, 0)

func _update_ghost_block() -> void:
	if _ghost == null or _camera == null: return
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := _camera.project_ray_origin(mouse_pos)
	var ray_dir    := _camera.project_ray_normal(mouse_pos)
	if abs(ray_dir.y) < 0.001:
		_ghost.visible = false
		return
	# Floor is at y=0.5
	var t := (0.5 - ray_origin.y) / ray_dir.y
	if t < 0.0:
		_ghost.visible = false
		return
	var hit := ray_origin + ray_dir * t
	
	var main = get_tree().current_scene
	var building_mgr = main.get_node_or_null("BuildingManager")
	if building_mgr and building_mgr.has_method("get_nearest_placeable"):
		var snap_pos = building_mgr.get_nearest_placeable(hit, 5.0)
		if snap_pos != Vector3.INF:
			# Check player distance to build spot
			if global_position.distance_to(snap_pos) > BUILD_RANGE:
				_ghost.visible = false
				return
				
			var stack_height = building_mgr.get_stack_at(snap_pos)
			var y_pos = 0.9 + (stack_height * 0.8)
			_ghost.global_position = Vector3(snap_pos.x, y_pos, snap_pos.z)
			_ghost.rotation.y = building_mgr.get_placeable_angle(snap_pos)
			_ghost.visible = true
			return
	_ghost.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or _is_dead: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			var scene = get_tree().current_scene
			if multiplayer.is_server():
				scene.request_collect_stones()
			else:
				scene.request_collect_stones.rpc_id(1)
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if _charging_throw or _place_timer > 0: return
			if _ghost and _ghost.visible:
				var is_new_section = true
				var main = get_tree().current_scene
				var building_mgr = main.get_node_or_null("BuildingManager")
				if building_mgr and building_mgr.has_method("get_stack_at"):
					if building_mgr.get_stack_at(Vector3(_ghost.global_position.x, 0, _ghost.global_position.z)) > 0:
						is_new_section = false
				
				if stones_carried > 0 or not is_new_section:
					_start_placement(_ghost.global_position, _ghost.rotation.y)
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			get_tree().current_scene._target_zoom = clamp(get_tree().current_scene._target_zoom - 2.0, 5, 35)
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			get_tree().current_scene._target_zoom = clamp(get_tree().current_scene._target_zoom + 2.0, 5, 35)

var _target_rotation: float = 0.0

@rpc("authority", "call_local", "reliable")
func set_stones(val: int) -> void:
	stones_carried = val

func _start_placement(pos: Vector3, rot: float) -> void:
	_target_blueprint_pos = pos
	_target_rotation = rot
	_place_timer = _get_base_place_duration()
	
	var main = get_tree().current_scene
	var building_mgr = main.get_node_or_null("BuildingManager")
	_placing_is_new_column = true
	if building_mgr and building_mgr.has_method("get_stack_at"):
		# Check if this is the first block in the column (y=0)
		if building_mgr.get_stack_at(Vector3(pos.x, 0, pos.z)) > 0:
			_placing_is_new_column = false

func take_damage(amount: float) -> void:
	if not multiplayer.is_server() or _is_dead: return
	_take_damage_rpc.rpc(amount)

@rpc("authority", "call_local", "reliable")
func _take_damage_rpc(amount: float) -> void:
	health -= amount
	damaged.emit(amount)
	if health <= 0 and not _is_dead:
		_die()

func _die() -> void:
	_is_dead = true
	visible = false
	died.emit()

func respawn(pos: Vector3) -> void:
	health = 100.0
	_is_dead = false
	visible = true
	global_position = pos

func sync_stones_to_hud() -> void:
	if is_multiplayer_authority() and _hud:
		_hud.update_stones(stones_carried, max_stones)
