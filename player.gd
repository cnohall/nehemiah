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
## ─────────────────────────────────────────────────────────────────────────────


# ══════════════════════════════════════════════════════════════════════════════
# EXPORTS — tweak in the Inspector without editing code
# ══════════════════════════════════════════════════════════════════════════════

## NodePath to the scene's Camera3D.  Assign in the Inspector.
## If left blank the script falls back to get_viewport().get_camera_3d().
@export var camera_path: NodePath = NodePath("../IsometricCamera")

## Walk speed in metres per second.
@export var move_speed: float = 5.0


# ══════════════════════════════════════════════════════════════════════════════
# CONSTANTS
# ══════════════════════════════════════════════════════════════════════════════

## Fallback animation used when a requested animation is missing in SpriteFrames.
const FALLBACK_ANIM: String = "idle_down"

const BLOCK_SCENE: PackedScene = preload("res://scenes/building_block/building_block.tscn")

## Building block dimensions — wide/long/short for realistic masonry.
const BLOCK_SIZE  := Vector3(2.0, 0.8, 1.0)
const GRID_SNAP_X := 2.0   # matches BLOCK_SIZE.x
const GRID_SNAP_Z := 1.0   # matches BLOCK_SIZE.z
const GRID_SNAP_Y := 0.8   # matches BLOCK_SIZE.y
const BLOCK_Y_OFFSET := 0.9 # floor top (0.5) + half block height (0.4)
const STONE_COLOR := Color(0.55, 0.52, 0.48)


# ══════════════════════════════════════════════════════════════════════════════
# PRIVATE VARIABLES
# ══════════════════════════════════════════════════════════════════════════════

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _camera: Camera3D = null

## Remembers the last direction faced so idle animations preserve facing.
var _last_facing: String = "down"

## Building System
var _ghost_block: MeshInstance3D = null
var _blocks_container: Node3D = null
var _building_rotation: float = 0.0

## Combat System
var _is_charging: bool = false
var _throw_power: float = 0.0
var _reload_timer: float = 0.0
const MAX_THROW_POWER: float = 50.0  # Much faster projectiles
const CHARGE_SPEED: float = 40.0     # Reaches max faster
const RELOAD_TIME: float = 0.5       # Snappier reload

## HUD & Targeting
var _power_bar: ProgressBar = null
var _target_mesh: MeshInstance3D = null


# ══════════════════════════════════════════════════════════════════════════════
# REPLICATED STATE
## These two vars are watched by the MultiplayerSynchronizer child node.
## Any change the authority makes is broadcast to every peer automatically.
# ══════════════════════════════════════════════════════════════════════════════

## The currently-playing animation name — synced across the network.
var current_animation: String = FALLBACK_ANIM


# ══════════════════════════════════════════════════════════════════════════════
# NODE REFERENCES — resolved at runtime via @onready
# ══════════════════════════════════════════════════════════════════════════════

@onready var _sprite: AnimatedSprite3D = $AnimatedSprite3D


# ══════════════════════════════════════════════════════════════════════════════
# READY
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	add_to_group("players")
	_setup_multiplayer_sync()
	_resolve_camera()
	_init_building_system()
	_init_hud()
	_init_targeter()


func _setup_multiplayer_sync() -> void:
	## Config is now baked into player.tscn (root_path + SceneReplicationConfig
	## sub-resource), so nothing needs to be done at runtime.
	pass


func _resolve_camera() -> void:
	_camera = get_node_or_null(camera_path)
	if _camera == null:
		_camera = get_viewport().get_camera_3d()
	if _camera == null:
		push_error(
			"PlayerController: No Camera3D found. " +
			"Set the 'camera_path' export in the Inspector."
		)


func _init_hud() -> void:
	## Only create HUD elements for the local player.
	if not is_multiplayer_authority():
		return
	
	var canvas := CanvasLayer.new()
	add_child(canvas)
	
	# Simple progress bar that will show charge power.
	_power_bar = ProgressBar.new()
	_power_bar.custom_minimum_size = Vector2(200, 20)
	_power_bar.show_percentage = false
	_power_bar.max_value = MAX_THROW_POWER
	_power_bar.visible = false
	
	# Position it at the bottom center of the screen.
	_power_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_power_bar.position.y -= 100 # Move it up slightly from the very bottom
	_power_bar.position.x -= 100 # Center it (half of width)
	
	# Style the bar to match the stone theme.
	var style_bg := StyleBoxFlat.new()
	style_bg.bg_color = Color(0.1, 0.1, 0.1, 0.5)
	_power_bar.add_theme_stylebox_override("background", style_bg)
	
	var style_fill := StyleBoxFlat.new()
	style_fill.bg_color = Color(0.9, 0.7, 0.2) # Gold/Stone-ish
	_power_bar.add_theme_stylebox_override("fill", style_fill)
	
	canvas.add_child(_power_bar)


func _init_targeter() -> void:
	if not is_multiplayer_authority():
		return
		
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


# ══════════════════════════════════════════════════════════════════════════════
# PROCESS
# ══════════════════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	if is_multiplayer_authority():
		_update_ghost_block()
		_update_combat(delta)


func _exit_tree() -> void:
	if is_instance_valid(_ghost_block):
		_ghost_block.queue_free()
	if is_instance_valid(_target_mesh):
		_target_mesh.queue_free()


# ══════════════════════════════════════════════════════════════════════════════
# PHYSICS PROCESS
# ══════════════════════════════════════════════════════════════════════════════

func _physics_process(delta: float) -> void:
	# Non-authority peers (remote players) do nothing except mirror the
	# animation string that was synced to them over the network.
	if not is_multiplayer_authority():
		_apply_remote_animation()
		return

	# ── Gravity ──────────────────────────────────────────────────────────────
	if not is_on_floor():
		velocity.y -= _gravity * delta

	# ── Isometric Movement ───────────────────────────────────────────────────
	var move_dir := _get_isometric_input()

	if move_dir != Vector3.ZERO:
		velocity.x = move_dir.x * move_speed
		velocity.z = move_dir.z * move_speed
		_update_walk_animation(move_dir)
	else:
		# Decelerate smoothly rather than stopping instantly.
		velocity.x = move_toward(velocity.x, 0.0, move_speed)
		velocity.z = move_toward(velocity.z, 0.0, move_speed)
		_update_idle_animation()

	move_and_slide()


# ══════════════════════════════════════════════════════════════════════════════
# ISOMETRIC INPUT → WORLD-SPACE DIRECTION
# ══════════════════════════════════════════════════════════════════════════════

func _get_isometric_input() -> Vector3:
	## Reads WASD input and returns a normalised world-space Vector3, rotated
	## so that W always moves "into the screen" from the player's view and D
	## always moves to the right — regardless of camera Y-rotation.
	##
	## The trick: project the camera's local forward/right axes onto the flat
	## XZ world plane, then combine them with the raw input magnitude.

	var raw := Vector2(
		Input.get_axis("move_left",  "move_right"),   # A = -1.0 │ D = +1.0
		Input.get_axis("move_up",    "move_down")     # W = -1.0 │ S = +1.0
	)

	if raw == Vector2.ZERO:
		return Vector3.ZERO

	if _camera == null:
		# Fallback with no camera: treat XZ as screen XY.
		return Vector3(raw.x, 0.0, raw.y).normalized()

	var cam_basis := _camera.global_transform.basis

	# Camera's local -Z axis is its "look-forward" direction in world space.
	var cam_forward := -cam_basis.z  # into the screen
	var cam_right   :=  cam_basis.x  # to the right on screen

	# Flatten onto the XZ plane so camera tilt doesn't push the character
	# into or out of the ground.
	cam_forward.y = 0.0
	cam_right.y   = 0.0
	cam_forward   = cam_forward.normalized()
	cam_right     = cam_right.normalized()

	# W/S → travel along the camera's flat-forward axis.
	# A/D → travel along the camera's flat-right axis.
	var world_dir := (cam_forward * -raw.y) + (cam_right * raw.x)
	return world_dir.normalized()


# ══════════════════════════════════════════════════════════════════════════════
# ANIMATION STATE MACHINE
# ─────────────────────────────────────────────────────────────────────────────

func _update_walk_animation(world_dir: Vector3) -> void:
	var facing := _resolve_screen_direction(world_dir)
	_last_facing = facing              # remember for idle
	_play_animation("walk_" + facing)


func _update_idle_animation() -> void:
	_play_animation("idle_" + _last_facing)


func _resolve_screen_direction(world_dir: Vector3) -> String:
	## Converts a world-space XZ direction into one of 8 screen-space names.

	var screen := _world_dir_to_screen(world_dir)

	# atan2(x, y) gives 0 at screen-up and increases clockwise.
	var angle_deg := rad_to_deg(atan2(screen.x, screen.y))

	# Snap to nearest 45° octant, then normalise into [0, 360) to avoid
	# negative-number ambiguity in the match statement.
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
		_:   return "down"   # should never be reached


func _world_dir_to_screen(world_dir: Vector3) -> Vector2:
	## Projects a normalised world-space XZ direction into the camera's 2D
	## screen plane.  Returns a normalised Vector2 where:
	##   +X = screen-right   +Y = screen-up

	if _camera == null:
		# No camera: assume default top-down mapping.
		return Vector2(world_dir.x, -world_dir.z)

	var cam_basis := _camera.global_transform.basis

	# Screen-X: how much the direction aligns with camera-right.
	var screen_x := world_dir.dot(cam_basis.x)

	# Screen-Y: how much the direction aligns with "flat camera-up".
	# We remove the vertical component of the camera's up vector so that
	# the tilted isometric camera still gives us a clean horizontal reference.
	var cam_up_flat := Vector3(cam_basis.y.x, 0.0, cam_basis.y.z).normalized()
	var screen_y    := world_dir.dot(cam_up_flat)

	return Vector2(screen_x, screen_y).normalized()


func _play_animation(anim_name: String) -> void:
	## Plays an animation on the local sprite AND writes `current_animation`
	## so that MultiplayerSynchronizer can broadcast it to all peers.

	if current_animation == anim_name:
		return  # Already playing — do not restart the animation.

	current_animation = anim_name  # <── MultiplayerSynchronizer watches this.

	if _sprite == null:
		return

	if _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(anim_name):
		_sprite.play(anim_name)
	else:
		push_warning(
			"PlayerController: SpriteFrames missing '%s'. Falling back to '%s'."
			% [anim_name, FALLBACK_ANIM]
		)
		if _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(FALLBACK_ANIM):
			_sprite.play(FALLBACK_ANIM)


func _apply_remote_animation() -> void:
	## Called every frame on non-authority peers.
	## `current_animation` is already kept current by MultiplayerSynchronizer,
	## so we only need to mirror it onto the local sprite node.

	if _sprite == null or _sprite.animation == current_animation:
		return
	if _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(current_animation):
		_sprite.play(current_animation)


# ══════════════════════════════════════════════════════════════════════════════
# BUILDING SYSTEM
# ══════════════════════════════════════════════════════════════════════════════

func _init_building_system() -> void:
	if not is_multiplayer_authority():
		return

	_blocks_container = get_tree().current_scene.get_node_or_null("Blocks")

	_ghost_block = MeshInstance3D.new()
	_ghost_block.name = "GhostBlock"

	var mesh := BoxMesh.new()
	mesh.size = BLOCK_SIZE
	_ghost_block.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color  = Color(0.6, 0.8, 1.0, 0.45)
	mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_block.material_override = mat
	_ghost_block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost_block.visible = false

	get_tree().current_scene.add_child.call_deferred(_ghost_block)


func _update_ghost_block() -> void:
	if _ghost_block == null or _camera == null or _is_charging:
		if _ghost_block: _ghost_block.visible = false
		return

	var result := _get_ground_hit()
	if result.is_empty():
		_ghost_block.visible = false
		return

	var hit_point: Vector3 = result.position
	var hit_normal: Vector3 = result.normal

	# Offset slightly into the intended cell to ensure we snap to the correct grid position.
	var target_pos := hit_point + hit_normal * 0.1

	var snapped_x: float = snappedf(target_pos.x, GRID_SNAP_X)
	var snapped_z: float = snappedf(target_pos.z, GRID_SNAP_Z)
	var snapped_y: float = snappedf(target_pos.y - BLOCK_Y_OFFSET, GRID_SNAP_Y) + BLOCK_Y_OFFSET

	_ghost_block.global_position = Vector3(snapped_x, snapped_y, snapped_z)
	_ghost_block.rotation.y = _building_rotation
	_ghost_block.visible = true


func _get_ground_hit() -> Dictionary:
	## Shared helper for building and combat to find where the mouse is pointing on the floor.
	if _camera == null: return {}
	
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := _camera.project_ray_origin(mouse_pos)
	var ray_dir    := _camera.project_ray_normal(mouse_pos)

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 1000.0)
	
	# Detect Floor, Blocks, AND Enemies (assuming layer 1, 2, 4)
	query.collision_mask = 1 | 2 | 4 
	
	# CRITICAL: Exclude the local player so we can shoot "through" our own head
	# when aiming toward the top of the screen.
	query.exclude = [get_rid()]
	
	return space_state.intersect_ray(query)


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
		
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		_building_rotation = fmod(_building_rotation + PI/2.0, PI)

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		
		# LMB -> Place Block
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if not _is_charging and _ghost_block != null and _ghost_block.visible:
				get_tree().current_scene.request_place_block.rpc_id(1, _ghost_block.global_position, _building_rotation)
		
		# RMB -> Charge Throw
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_start_charging()
			else:
				_release_throw()


# ══════════════════════════════════════════════════════════════════════════════
# COMBAT SYSTEM
# ══════════════════════════════════════════════════════════════════════════════

func _start_charging() -> void:
	if _reload_timer > 0.0:
		return # Still reloading
		
	_is_charging = true
	_throw_power = 10.0 # Start with some base oomph
	
	if _power_bar:
		_power_bar.visible = true
		_power_bar.value = _throw_power
	
	if _target_mesh:
		_target_mesh.visible = true

func _release_throw() -> void:
	if not _is_charging:
		return
	
	_is_charging = false
	if _power_bar:
		_power_bar.visible = false
	if _target_mesh:
		_target_mesh.visible = false
	
	if _camera == null:
		return

	# Intersect the camera ray with the y=0 ground plane geometrically.
	# Using physics (_get_ground_hit) can hit stale stones on the ground
	# and corrupt the aim direction.
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := _camera.project_ray_origin(mouse_pos)
	var ray_dir    := _camera.project_ray_normal(mouse_pos)

	var world_dir_flat: Vector3
	if ray_dir.y < -0.001:
		var t := -ray_origin.y / ray_dir.y
		var ground_point := ray_origin + ray_dir * t
		world_dir_flat = Vector3(ground_point.x - global_position.x, 0.0, ground_point.z - global_position.z).normalized()
	else:
		# Aimed at or above the horizon — use horizontal component of the ray.
		world_dir_flat = Vector3(ray_dir.x, 0.0, ray_dir.z).normalized()

	var spawn_pos := global_position + Vector3(0, 1.8, 0)
	var final_dir := (world_dir_flat + Vector3(0, 0.2, 0)).normalized()
	
	get_tree().current_scene.request_throw_stone.rpc_id(1, spawn_pos, final_dir, _throw_power, get_path())
	
	_throw_power = 0.0
	_reload_timer = RELOAD_TIME

func _update_combat(delta: float) -> void:
	# Handle reload cooldown
	if _reload_timer > 0.0:
		_reload_timer = max(0.0, _reload_timer - delta)
		if _reload_timer > 0.0:
			_sprite.modulate = Color(0.7, 0.7, 0.7)
		else:
			_sprite.modulate = Color.WHITE

	# Handle charging
	if _is_charging:
		_throw_power = min(_throw_power + CHARGE_SPEED * delta, MAX_THROW_POWER)
		if _power_bar:
			_power_bar.value = _throw_power
			if _throw_power >= MAX_THROW_POWER:
				_power_bar.modulate = Color.RED if Engine.get_frames_drawn() % 10 < 5 else Color.WHITE
			else:
				_power_bar.modulate = Color.WHITE
		
		# Update targeter position
		var result := _get_ground_hit()
		if not result.is_empty() and _target_mesh:
			_target_mesh.global_position = result.position + Vector3(0, 0.1, 0)
			_target_mesh.visible = true
		elif _target_mesh:
			_target_mesh.visible = false
