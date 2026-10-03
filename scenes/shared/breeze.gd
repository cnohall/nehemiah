class_name Breeze
extends Node3D

# Ambient air: a drift of dust and pollen motes carried on the wind, catching the sun. Follows
# the camera's ground focus (the motes stay in the world), thins out toward dusk and is gone
# after dark. Cloud shadows (ground.gdshader) and foliage sway (chunky.gdshader) share its
# wind direction. Purely visual; each peer runs its own.

const WIND := Vector3(0.85, 0.0, 0.52)
const AREA := Vector3(36.0, 3.0, 28.0)   # half extents of where motes are born, round the focus
const AMOUNT := 150
const LIFETIME := 11.0

var _motes: GPUParticles3D
var _day: Node

func _ready() -> void:
	_motes = GPUParticles3D.new()
	_motes.amount = AMOUNT
	_motes.lifetime = LIFETIME
	_motes.preprocess = LIFETIME
	_motes.local_coords = false
	_motes.visibility_aabb = AABB(-AREA * 2.0 - Vector3(20, 10, 20), AREA * 4.0 + Vector3(40, 20, 40))
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = AREA
	m.direction = WIND
	m.spread = 14.0
	m.initial_velocity_min = 0.7
	m.initial_velocity_max = 1.6
	m.gravity = Vector3(0, 0.01, 0)
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 0.35
	m.turbulence_noise_scale = 3.5
	m.turbulence_influence_min = 0.02
	m.turbulence_influence_max = 0.07
	m.scale_min = 0.5
	m.scale_max = 1.4
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.18, 0.8, 1.0])
	ramp.colors = PackedColorArray([Color(1, 0.94, 0.78, 0.0), Color(1, 0.94, 0.78, 0.5), Color(1, 0.94, 0.78, 0.45), Color(1, 0.94, 0.78, 0.0)])
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	m.color_ramp = tex
	_motes.process_material = m
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_dot()
	mat.no_depth_test = false
	quad.material = mat
	_motes.draw_pass_1 = quad
	add_child(_motes)
	_day = get_parent().get_node_or_null("DayLight")

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var fwd := -cam.global_basis.z
	var hit: Variant = Plane(Vector3.UP, 1.0).intersects_ray(cam.global_position, fwd)
	if hit != null:
		var at: Vector3 = hit
		global_position = Vector3(at.x, 1.0, at.z)
	# Dusk thins the motes; night (and the day's last light) takes them away
	var k := 1.0
	if _day != null:
		k = 1.0 - clampf(_day.darkness * 1.4 + _day.evening * 0.5, 0.0, 1.0)
	_motes.amount_ratio = clampf(k, 0.0, 1.0)
	_motes.emitting = k > 0.02

static var _dot: GradientTexture2D

static func _soft_dot() -> GradientTexture2D:
	if not _dot:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_dot = GradientTexture2D.new()
		_dot.gradient = g
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(0.5, 0.0)
		_dot.width = 32
		_dot.height = 32
	return _dot
