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

@onready var _sprite: AnimatedSprite3D        = $AnimatedSprite3D
@onready var _sync:   MultiplayerSynchronizer = $MultiplayerSynchronizer


# ══════════════════════════════════════════════════════════════════════════════
# BUILDING SYSTEM — private state
# ══════════════════════════════════════════════════════════════════════════════

## How wide/long/tall a placed stone brick is, in world-units.
## Proportions deliberately wider and longer than tall (realistic masonry).
const BLOCK_SIZE := Vector3(2.0, 0.8, 1.0)

## Grid cell size governs snapping.  X and Z snap to BLOCK_SIZE.x / BLOCK_SIZE.z.
const GRID_SNAP_X := 2.0   # matches BLOCK_SIZE.x
const GRID_SNAP_Z := 1.0   # matches BLOCK_SIZE.z

## Y-offset so the block sits on top of the ground plane (y = 0).
## Half the block height, because the mesh origin is centred.
const BLOCK_Y := BLOCK_SIZE.y * 0.5   # = 0.4

## Stone-grey material colour.
const STONE_COLOR := Color(0.55, 0.52, 0.48)

## The ghost (preview) node, created once and reused every frame.
var _ghost: MeshInstance3D = null

## True while the RMB is held (stone-throw charge); we skip placement then.
## (Populated by the combat system when it exists — defaulting false for now.)
var _charging_throw: bool = false


# ══════════════════════════════════════════════════════════════════════════════
# READY
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_setup_multiplayer_sync()
	_resolve_camera()
	_init_building_system()


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


# ══════════════════════════════════════════════════════════════════════════════
# BUILDING SYSTEM
# ══════════════════════════════════════════════════════════════════════════════
#
# Flow:
#   _init_building_system()    — called once from _ready()
#   _update_ghost_block()      — called every _process() frame (authority only)
#   _unhandled_input()         — fires _place_block() on LMB just-pressed
#   _place_block(grid_pos)     — instances the real block into the scene
#
# The ghost and placed blocks are added to get_tree().current_scene (the
# running main scene Node3D), NOT to get_tree().root (the Window).
# Adding 3D nodes to the Window root works but puts them outside the scene's
# world node, which breaks environment, lighting, and scene-save logic.
# ─────────────────────────────────────────────────────────────────────────────

func _init_building_system() -> void:
	## Create the ghost (preview) MeshInstance3D once and park it off-screen.
	## Only the authority player gets a ghost — remote players never see it.
	if not is_multiplayer_authority():
		return

	_ghost = MeshInstance3D.new()
	_ghost.name = "GhostBlock"

	# Brick-proportioned box mesh — same dimensions as the real placed block.
	var mesh := BoxMesh.new()
	mesh.size = BLOCK_SIZE
	_ghost.mesh = mesh

	# Semi-transparent blue-white preview material.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.8, 1.0, 0.45)
	mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost.material_override = mat

	# Disable the ghost's own shadow so it doesn't cast a confusing preview shadow.
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Start invisible until a valid ground position is under the cursor.
	_ghost.visible = false

	# Add to the running scene, not to the Window root.
	get_tree().current_scene.add_child(_ghost)


func _process(_delta: float) -> void:
	if not is_multiplayer_authority():
		return
	_update_ghost_block()


func _update_ghost_block() -> void:
	## Casts a ray from the camera through the mouse cursor and snaps the
	## ghost block to the nearest grid cell on the y = 0 ground plane.
	## Hides the ghost when the cursor is not over the ground.

	if _ghost == null or _camera == null:
		return

	var viewport := get_viewport()
	var mouse_pos := viewport.get_mouse_position()

	# Build a ray from the camera through the cursor into the 3D world.
	var ray_origin := _camera.project_ray_origin(mouse_pos)
	var ray_dir    := _camera.project_ray_normal(mouse_pos)

	# Intersect with the y = 0 plane analytically (no physics query needed).
	# Ray: P = ray_origin + t * ray_dir   →  solve for ray_origin.y + t*ray_dir.y = 0
	if abs(ray_dir.y) < 0.001:
		# Ray is nearly parallel to the ground plane — hide ghost.
		_ghost.visible = false
		return

	var t := -ray_origin.y / ray_dir.y
	if t < 0.0:
		# Intersection is behind the camera.
		_ghost.visible = false
		return

	var hit := ray_origin + ray_dir * t   # world-space XZ hit point, y ≈ 0

	# Snap X and Z to the brick grid independently (bricks are not square).
	var snapped_x := snappedf(hit.x, GRID_SNAP_X)
	var snapped_z := snappedf(hit.z, GRID_SNAP_Z)

	_ghost.global_position = Vector3(snapped_x, BLOCK_Y, snapped_z)
	_ghost.visible = true


func _unhandled_input(event: InputEvent) -> void:
	## LMB just-pressed → place block.
	## Using _unhandled_input (not _input) so UI controls that consume click
	## events (buttons, menus) block placement correctly.
	##
	## "mouse_left" is NOT defined in project.godot's input map, so we check
	## the raw mouse button rather than a named action.

	if not is_multiplayer_authority():
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			# Don't place a block while the RMB throw-charge is active.
			if _charging_throw:
				return
			if _ghost != null and _ghost.visible:
				_place_block(_ghost.global_position)


func _place_block(snapped_world_pos: Vector3) -> void:
	## Instances a solid stone-brick block at `snapped_world_pos` and adds it
	## to the running scene so all players can walk on it.
	##
	## The block is a plain Node3D containing:
	##   MeshInstance3D      — visual
	##   StaticBody3D        → CollisionShape3D  — physics (players can walk on top)

	var grid_x := int(round(snapped_world_pos.x / GRID_SNAP_X))
	var grid_z := int(round(snapped_world_pos.z / GRID_SNAP_Z))

	# ── Root container ────────────────────────────────────────────────────────
	var block := Node3D.new()
	block.name = "Block_%d_%d" % [grid_x, grid_z]
	block.global_position = snapped_world_pos

	# ── Visual mesh ───────────────────────────────────────────────────────────
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Mesh"

	var box := BoxMesh.new()
	box.size = BLOCK_SIZE
	mesh_inst.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color   = STONE_COLOR
	# Roughness gives the surface a matte, carved-stone feel.
	mat.roughness      = 0.85
	mat.metallic       = 0.0
	mesh_inst.material_override = mat

	block.add_child(mesh_inst)

	# ── Collision (StaticBody3D + CollisionShape3D) ───────────────────────────
	var body := StaticBody3D.new()
	body.name = "Body"

	var col := CollisionShape3D.new()
	col.name = "Shape"
	var shape := BoxShape3D.new()
	shape.size = BLOCK_SIZE        # collision volume matches visual exactly
	col.shape = shape

	body.add_child(col)
	block.add_child(body)

	# ── Add to scene ──────────────────────────────────────────────────────────
	# current_scene is the running main scene Node3D — the correct owner for
	# persistent world geometry.  Never use get_tree().root (the Window node).
	get_tree().current_scene.add_child(block)
