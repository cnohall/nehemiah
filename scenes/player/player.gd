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


# ══════════════════════════════════════════════════════════════════════════════
# PRIVATE VARIABLES
# ══════════════════════════════════════════════════════════════════════════════

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _camera: Camera3D = null

## Remembers the last direction faced so idle animations preserve facing.
var _last_facing: String = "down"


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

@onready var _sprite: AnimatedSprite3D      = $AnimatedSprite3D
@onready var _sync:   MultiplayerSynchronizer = $MultiplayerSynchronizer


# ══════════════════════════════════════════════════════════════════════════════
# READY
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_setup_multiplayer_sync()
	_resolve_camera()


func _setup_multiplayer_sync() -> void:
	## Programmatically build the ReplicationConfig so no extra editor steps
	## are needed.  The MultiplayerSpawner (on the parent scene) will call
	## set_multiplayer_authority(peer_id) on each spawned instance, which
	## tells Godot which peer "owns" this node and should drive its physics.

	# root_path ".." means: sync properties on THIS node (the CharacterBody3D),
	# because the MultiplayerSynchronizer is a direct child of it.
	_sync.root_path = NodePath("..")

	var config := SceneReplicationConfig.new()

	# ── global_position ──────────────────────────────────────────────────────
	# spawn = true  → sent to any peer that joins after this node is created.
	# watch = true  → delta-synced whenever the value changes each frame.
	config.add_property(NodePath(".:global_position"))
	config.property_set_spawn(NodePath(".:global_position"), true)
	config.property_set_watch(NodePath(".:global_position"), true)

	# ── current_animation ────────────────────────────────────────────────────
	# Keeps remote players' sprite animations in sync.
	config.add_property(NodePath(".:current_animation"))
	config.property_set_spawn(NodePath(".:current_animation"), true)
	config.property_set_watch(NodePath(".:current_animation"), true)

	_sync.replication_config = config


func _resolve_camera() -> void:
	_camera = get_node_or_null(camera_path)
	if _camera == null:
		_camera = get_viewport().get_camera_3d()
	if _camera == null:
		push_error(
			"PlayerController: No Camera3D found. " +
			"Set the 'camera_path' export in the Inspector."
		)


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

	var basis := _camera.global_transform.basis

	# Camera's local -Z axis is its "look-forward" direction in world space.
	var cam_forward := -basis.z  # into the screen
	var cam_right   :=  basis.x  # to the right on screen

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
# ══════════════════════════════════════════════════════════════════════════════
#
# Because the AnimatedSprite3D is set to Y_BILLBOARD it always faces the camera,
# so we resolve animation direction in SCREEN SPACE, not world space.
#
# Screen-space convention (matches what the pixel artist draws):
#   "up"       = towards the top of the screen
#   "down"     = towards the bottom of the screen
#   "right"    = towards the right of the screen
#   "left"     = towards the left of the screen
#   "up_right" = diagonal, etc.
#
# Required SpriteFrames animation names (16 total):
#   idle_up   idle_up_right   idle_right   idle_down_right
#   idle_down idle_down_left  idle_left    idle_up_left
#   walk_up   walk_up_right   walk_right   walk_down_right
#   walk_down walk_down_left  walk_left    walk_up_left
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

	var basis := _camera.global_transform.basis

	# Screen-X: how much the direction aligns with camera-right.
	var screen_x := world_dir.dot(basis.x)

	# Screen-Y: how much the direction aligns with "flat camera-up".
	# We remove the vertical component of the camera's up vector so that
	# the tilted isometric camera still gives us a clean horizontal reference.
	var cam_up_flat := Vector3(basis.y.x, 0.0, basis.y.z).normalized()
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
