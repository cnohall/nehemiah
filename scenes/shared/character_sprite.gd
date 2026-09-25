class_name CharacterSprite
extends AnimatedSprite3D

# LPC character sprite with outline / hit-flash shader and a ground marker
# (contact shadow + optional player-colour ring).

const SPRITE_SHADER := preload("res://assets/shaders/character_sprite.gdshader")
const MARKER_SHADER := preload("res://assets/shaders/ground_marker.gdshader")
const FLASH_TIME    := 0.16
# LPC figures are ~48 px tall in a 64 px frame, feet 2 px above the frame bottom.
# 0.035 m/px → ~1.7 m adult, matching the 1.8 m collision capsule and 2 m walls.
const PIXEL_SIZE    := 0.035
const FRAME_PX      := 64
const FOOT_PAD_PX   := 2
const SQUASH_TIME   := 0.28
const STEP_FRAMES   := [1, 5]   # footfalls in the 8-frame walk / run cycles

signal footstep

var _mat: ShaderMaterial
var _marker_mat: ShaderMaterial
var _flash_tween: Tween
var _squash_tween: Tween
var _base_scale := 1.0
var _base_y := 0.0

func setup(sheet: Texture2D, anims: Array, tint: Color = Color.WHITE, size_scale := 1.0) -> void:
	pixel_size = PIXEL_SIZE
	scale = Vector3.ONE * size_scale
	# Put the feet on the parent's origin (sprite is centred on its frame)
	position.y = (FRAME_PX * 0.5 - FOOT_PAD_PX) * PIXEL_SIZE * size_scale
	_base_scale = size_scale
	_base_y = position.y
	sprite_frames = LPCFrames.build(sheet, anims)
	_mat = ShaderMaterial.new()
	_mat.shader = SPRITE_SHADER
	_mat.set_shader_parameter("sheet", sheet)
	_mat.set_shader_parameter("tint", tint)
	material_override = _mat
	_build_marker()
	frame_changed.connect(func():
		if frame in STEP_FRAMES and (animation.begins_with("run") or animation.begins_with("walk")):
			footstep.emit())

## Swap to another sheet with the same layout (e.g. a player's tunic colour)
func set_sheet(sheet: Texture2D, anims: Array) -> void:
	var current := animation
	var current_frame := frame
	sprite_frames = LPCFrames.build(sheet, anims)
	_mat.set_shader_parameter("sheet", sheet)
	if sprite_frames.has_animation(current):
		play(current)
		frame = current_frame

func set_outline_color(c: Color) -> void:
	_mat.set_shader_parameter("outline_color", c)

func set_ring_color(c: Color) -> void:
	_marker_mat.set_shader_parameter("ring_color", c)

func hit_flash() -> void:
	if _flash_tween:
		_flash_tween.kill()
	_mat.set_shader_parameter("flash", 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_method(func(v: float): _mat.set_shader_parameter("flash", v), 1.0, 0.0, FLASH_TIME)

## Freeze the current frame for a beat so a hit lands with weight (visual only —
## movement carries on, so nothing desyncs)
func hitstop(duration: float) -> void:
	if not is_playing():
		return
	pause()
	await get_tree().create_timer(duration).timeout
	if is_instance_valid(self) and not is_playing():
		play()

## Cartoon squash & stretch (x, y factors), springing back to normal. Feet stay planted.
func squash(amount: Vector2) -> void:
	if _squash_tween:
		_squash_tween.kill()
	_apply_squash(amount)
	_squash_tween = create_tween()
	_squash_tween.tween_method(func(t: float): _apply_squash(Vector2.ONE.lerp(amount, t)), 1.0, 0.0, SQUASH_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _apply_squash(f: Vector2) -> void:
	scale = Vector3(f.x, f.y, 1.0) * _base_scale
	position.y = _base_y * f.y

func _build_marker() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.3, 1.3)
	quad.orientation = PlaneMesh.FACE_Y
	_marker_mat = ShaderMaterial.new()
	_marker_mat.shader = MARKER_SHADER
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = _marker_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Sibling of the sprite so it stays flat on the ground, not billboarded
	mi.position = Vector3(0, 0.03, 0)
	get_parent().add_child.call_deferred(mi)
