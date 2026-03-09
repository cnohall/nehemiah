extends CharacterBody3D
## PlayerController

@export var camera_path: NodePath = NodePath("../IsometricCamera")
@export var move_speed: float = 5.0
@export var jump_force: float = 6.0

const FALLBACK_ANIM: String = "idle_down"
const BLOCK_SCENE: PackedScene = preload("res://scenes/building_block/building_block.tscn")
const HUD_SCENE: PackedScene = preload("res://scenes/ui/game_hud.tscn")

const BLOCK_SIZE  := Vector3(2.0, 0.8, 1.0)
const GRID_SNAP_Y := 0.8
const BLOCK_Y_OFFSET := 0.9
const STONE_COLOR := Color(0.55, 0.52, 0.48)

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _camera: Camera3D = null
var _last_facing: String = "down"

## Building System
var _ghost_block: MeshInstance3D = null
var _blocks_container: Node3D = null
var _building_rotation: float = 0.0

## Combat System
var _is_charging: bool = false
var _throw_power: float = 0.0
var _reload_timer: float = 0.0
const MAX_THROW_POWER: float = 25.0
const CHARGE_SPEED: float = 20.0
const RELOAD_TIME: float = 0.5

## HUD & Targeting
var _hud: CanvasLayer = null
var _target_mesh: MeshInstance3D = null

## Replicated State
var current_animation: String = FALLBACK_ANIM
var health: float = 100.0

signal died
signal damaged(amount: float)

@onready var _sprite: AnimatedSprite3D = $AnimatedSprite3D
var _is_dead: bool = false

func _ready() -> void:
	add_to_group("players")
	_resolve_camera()
	_init_building_system()
	_init_hud()
	_init_targeter()

func _init_hud() -> void:
	if not is_multiplayer_authority():
		return
	
	if is_instance_valid(_hud):
		_hud.queue_free()
		
	_hud = HUD_SCENE.instantiate()
	add_child(_hud)
	
	var resume_btn = _hud.get_node("PauseMenu/Panel/VBox/ResumeBtn")
	resume_btn.pressed.connect(func(): _toggle_pause(false))
	
	var quit_btn = _hud.get_node("PauseMenu/Panel/VBox/QuitBtn")
	quit_btn.pressed.connect(func(): get_tree().quit())

func _resolve_camera() -> void:
	_camera = get_node_or_null(camera_path)
	if _camera == null:
		_camera = get_viewport().get_camera_3d()

func take_damage(amount: float) -> void:
	if not multiplayer.is_server() or _is_dead:
		return
		
	health -= amount
	damaged.emit(amount)
	
	if health <= 0:
		health = 0
		_is_dead = true
		died.emit()
		_play_death_effect.rpc()
	
	_update_hud_health.rpc(health)

@rpc("authority", "call_local", "reliable")
func _update_hud_health(val: float) -> void:
	if _hud: _hud.update_health(val)

@rpc("authority", "call_local", "reliable")
func _play_death_effect() -> void:
	_is_dead = true
	visible = false
	if is_instance_valid(_ghost_block):
		_ghost_block.visible = false
	if is_instance_valid(_target_mesh):
		_target_mesh.visible = false

func respawn(spawn_pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
		
	health = 100.0
	_is_dead = false
	global_position = spawn_pos
	_do_respawn.rpc(spawn_pos)

@rpc("authority", "call_local", "reliable")
func _do_respawn(spawn_pos: Vector3) -> void:
	_is_dead = false
	health = 100.0
	global_position = spawn_pos
	visible = true
	if _hud: 
		_hud.update_health(100.0)
		_hud.get_node("PauseMenu").visible = false

func _process(delta: float) -> void:
	if not is_multiplayer_authority(): return
	if _is_dead: return
	
	_update_ghost_block()
	_update_combat(delta)

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		_apply_remote_animation()
		return

	if _is_dead: 
		velocity = Vector3.ZERO
		move_and_slide()
		return

	if _hud and _hud.get_node("PauseMenu").visible:
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta

	if is_on_floor() and Input.is_action_just_pressed("ui_accept"):
		velocity.y = jump_force

	var move_dir := _get_isometric_input()
	if move_dir != Vector3.ZERO:
		velocity.x = move_dir.x * move_speed
		velocity.z = move_dir.z * move_speed
		_update_walk_animation(move_dir)
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed)
		velocity.z = move_toward(velocity.z, 0.0, move_speed)
		_update_idle_animation()

	move_and_slide()

func _get_isometric_input() -> Vector3:
	var raw := Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_up", "move_down"))
	if raw == Vector2.ZERO or _camera == null:
		return Vector3(raw.x, 0.0, raw.y).normalized() if raw != Vector2.ZERO else Vector3.ZERO

	var cam_basis := _camera.global_transform.basis
	var cam_forward := Vector3(cam_basis.z.x, 0.0, cam_basis.z.z).normalized()
	var cam_right := Vector3(cam_basis.x.x, 0.0, cam_basis.x.z).normalized()
	return (cam_right * raw.x + cam_forward * raw.y).normalized()

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
		0:   return "up"
		45:  return "up_right"
		90:  return "right"
		135: return "down_right"
		180: return "down"
		225: return "down_left"
		270: return "left"
		315: return "up_left"
		_:   return "down"

func _world_dir_to_screen(world_dir: Vector3) -> Vector2:
	if _camera == null: return Vector2(world_dir.x, -world_dir.z)
	var cam_basis := _camera.global_transform.basis
	var screen_x := world_dir.dot(cam_basis.x)
	var cam_up_flat := Vector3(cam_basis.y.x, 0.0, cam_basis.y.z).normalized()
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
	
	if is_instance_valid(_ghost_block):
		_ghost_block.queue_free()
		
	_blocks_container = get_tree().current_scene.get_node_or_null("Blocks")
	_ghost_block = MeshInstance3D.new()
	_ghost_block.name = "GhostBlock"
	var mesh := BoxMesh.new()
	mesh.size = BLOCK_SIZE
	_ghost_block.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.8, 1.0, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_block.material_override = mat
	_ghost_block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost_block.visible = false
	get_tree().current_scene.add_child.call_deferred(_ghost_block)

func _update_ghost_block() -> void:
	if _ghost_block == null or _camera == null or _is_charging or _is_dead:
		if _ghost_block: _ghost_block.visible = false
		return
	var result := _get_ground_hit()
	if result.is_empty():
		_ghost_block.visible = false
		return
	var target_pos: Vector3 = result.position + result.normal * 0.1
	
	# Smarter snapping based on rotation
	# Default size: 2.0x1.0. Snap values should respect this.
	var snap_x = 2.0
	var snap_z = 1.0
	
	# If rotated 90 or 270 degrees (check if rotation is closer to perpendicular)
	var angle_mod = fmod(abs(_building_rotation), PI)
	if abs(angle_mod - PI/2.0) < 0.1:
		snap_x = 1.0
		snap_z = 2.0
	
	var snapped_pos := Vector3(
		snappedf(target_pos.x, snap_x), 
		snappedf(target_pos.y - BLOCK_Y_OFFSET, GRID_SNAP_Y) + BLOCK_Y_OFFSET, 
		snappedf(target_pos.z, snap_z)
	)
	_ghost_block.global_position = snapped_pos
	_ghost_block.rotation.y = _building_rotation
	_ghost_block.visible = true

func _get_ground_hit() -> Dictionary:
	if _camera == null: return {}
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := _camera.project_ray_origin(mouse_pos)
	var ray_dir := _camera.project_ray_normal(mouse_pos)
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 1000.0)
	query.collision_mask = 1 | 2 | 4
	query.exclude = [get_rid()]
	return space_state.intersect_ray(query)

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or _is_dead: return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			_building_rotation = fmod(_building_rotation + PI/2.0, PI)
		if event.keycode == KEY_ESCAPE:
			if _hud: _toggle_pause(not _hud.get_node("PauseMenu").visible)

	if _hud and _hud.get_node("PauseMenu").visible: return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if not _is_charging and _ghost_block != null and _ghost_block.visible:
				get_tree().current_scene.request_place_block.rpc_id(1, _ghost_block.global_position, _building_rotation)
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed: _start_charging()
			else: _release_throw()

func _toggle_pause(should_pause: bool) -> void:
	if _hud: _hud.toggle_pause(should_pause)

func _init_targeter() -> void:
	if not is_multiplayer_authority(): return
	
	if is_instance_valid(_target_mesh):
		_target_mesh.queue_free()
		
	_target_mesh = MeshInstance3D.new()
	var ring := CylinderMesh.new()
	ring.top_radius = 0.4
	ring.bottom_radius = 0.4
	ring.height = 0.05
	_target_mesh.mesh = ring
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0, 0, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_target_mesh.material_override = mat
	_target_mesh.visible = false
	get_tree().current_scene.add_child.call_deferred(_target_mesh)

func _start_charging() -> void:
	if _reload_timer > 0.0 or _is_dead: return
	_is_charging = true
	_throw_power = 10.0
	if _hud: _hud.update_power(_throw_power, MAX_THROW_POWER)

func _release_throw() -> void:
	if not _is_charging: return
	_is_charging = false
	if _hud: _hud.update_power(0, MAX_THROW_POWER)
	if _target_mesh: _target_mesh.visible = false
	if _camera == null: return

	var mouse_pos := get_viewport().get_mouse_position()
	var player_screen_pos := _camera.unproject_position(global_position)
	var screen_dir := (mouse_pos - player_screen_pos).normalized()
	var cam_basis := _camera.global_transform.basis
	var cam_right := cam_basis.x
	var cam_up_flat := Vector3(cam_basis.y.x, 0.0, cam_basis.y.z).normalized()
	var world_dir_flat = (cam_right * screen_dir.x + cam_up_flat * -screen_dir.y).normalized()
	var spawn_pos = global_position + Vector3(0, 0.4, 0)
	var final_dir = (world_dir_flat + Vector3(0, 0.2, 0)).normalized()
	get_tree().current_scene.request_throw_stone.rpc_id(1, spawn_pos, final_dir, _throw_power, get_path())
	_throw_power = 0.0
	_reload_timer = RELOAD_TIME

func _update_combat(delta: float) -> void:
	if _reload_timer > 0.0:
		_reload_timer = max(0.0, _reload_timer - delta)
		_sprite.modulate = Color(0.7, 0.7, 0.7) if _reload_timer > 0.0 else Color.WHITE

	if _is_charging:
		_throw_power = min(_throw_power + CHARGE_SPEED * delta, MAX_THROW_POWER)
		if _hud: _hud.update_power(_throw_power, MAX_THROW_POWER)
		var result := _get_ground_hit()
		if not result.is_empty() and _target_mesh:
			_target_mesh.global_position = result.position + Vector3(0, 0.1, 0)
			_target_mesh.visible = true
		elif _target_mesh:
			_target_mesh.visible = false
