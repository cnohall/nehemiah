class_name DustFx
# Shared soft, round dust-puff material. Plain quads read as floating glass
# panes from the iso camera; a radial falloff makes them read as dust.

static var _mat: StandardMaterial3D

static func material() -> StandardMaterial3D:
	if _mat:
		return _mat
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.add_point(0.45, Color(1, 1, 1, 0.55))
	grad.set_color(grad.get_point_count() - 1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	_mat = StandardMaterial3D.new()
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_mat.vertex_color_use_as_albedo = true
	_mat.albedo_texture = tex
	return _mat

# Puffs swell as they fade, like dust settling outward
static func grow_curve() -> Curve:
	var c := Curve.new()
	c.max_value = 1.5
	c.add_point(Vector2(0, 0.6))
	c.add_point(Vector2(1, 1.4))
	return c
