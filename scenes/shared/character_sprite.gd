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

var _mat: ShaderMaterial
var _marker_mat: ShaderMaterial
var _flash_tween: Tween

func setup(sheet: Texture2D, anims: Array, tint: Color = Color.WHITE, size_scale := 1.0) -> void:
	pixel_size = PIXEL_SIZE
	scale = Vector3.ONE * size_scale
	# Put the feet on the parent's origin (sprite is centred on its frame)
	position.y = (FRAME_PX * 0.5 - FOOT_PAD_PX) * PIXEL_SIZE * size_scale
	sprite_frames = LPCFrames.build(sheet, anims)
	_mat = ShaderMaterial.new()
	_mat.shader = SPRITE_SHADER
	_mat.set_shader_parameter("sheet", sheet)
	_mat.set_shader_parameter("tint", tint)
	material_override = _mat
	_build_marker()

## Swap to another sheet with the same layout (e.g. a player's tunic colour)
func set_sheet(sheet: Texture2D, anims: Array) -> void:
	var current := animation
	var current_frame := frame
	sprite_frames = LPCFrames.build(sheet, anims)
	_mat.set_shader_parameter("sheet", sheet)
	if sprite_frames.has_animation(current):
		play(current)
		frame = current_frame

func set_ring_color(c: Color) -> void:
	_marker_mat.set_shader_parameter("ring_color", c)

func hit_flash() -> void:
	if _flash_tween:
		_flash_tween.kill()
	_mat.set_shader_parameter("flash", 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_method(func(v: float): _mat.set_shader_parameter("flash", v), 1.0, 0.0, FLASH_TIME)

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
