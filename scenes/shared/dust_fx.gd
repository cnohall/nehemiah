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

## One-shot burst of dust at a world point (added under `parent`, freed when done)
static func puff(parent: Node, at: Vector3, amount := 8, size := 0.5,
		color := Color(0.87, 0.78, 0.60, 0.6)) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = 0.5
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.4
	p.gravity = Vector3(0, -2.5, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	p.scale_amount_curve = grow_curve()
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color, 0.0))
	p.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = material()
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.top_level = true
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)

# Puffs swell as they fade, like dust settling outward
static func grow_curve() -> Curve:
	var c := Curve.new()
	c.max_value = 1.5
	c.add_point(Vector2(0, 0.6))
	c.add_point(Vector2(1, 1.4))
	return c
