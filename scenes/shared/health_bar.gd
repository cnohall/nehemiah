class_name HealthBar
extends MeshInstance3D

# Overhead bar for characters. Hidden while full unless `always_show`.

const SHADER := preload("res://assets/shaders/health_bar.gdshader")
const HEALTHY := Color(0.52, 0.66, 0.28)
const HURT    := Color(0.86, 0.62, 0.22)
const LOW     := Color(0.78, 0.30, 0.20)

var _mat: ShaderMaterial

func _init(width := 0.8, height := 0.09) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)
	mesh = quad
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false

## Health fraction 0..1; colour shifts green → amber → red. Hidden when full.
func show_health(frac: float) -> void:
	frac = clampf(frac, 0.0, 1.0)
	_apply(frac, HEALTHY if frac > 0.6 else (HURT if frac > 0.3 else LOW))
	visible = frac < 0.999

## Explicit colour + always visible (e.g. a downed countdown)
func show_value(frac: float, color: Color) -> void:
	_apply(clampf(frac, 0.0, 1.0), color)
	visible = true

func _apply(frac: float, color: Color) -> void:
	_mat.set_shader_parameter("fill", frac)
	_mat.set_shader_parameter("fill_color", color)
