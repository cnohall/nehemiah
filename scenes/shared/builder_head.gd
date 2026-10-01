extends RefCounted

# Builder-specific sculpt. All positions are relative to the animated neck pivot.
# Curved, tapered locks and shaped cross sections are authored in model space;
# meshes are cached across gameplay rigs and the live crew portraits.
static var _cache: Dictionary = {}
static var _material: ShaderMaterial
var _rig: Node3D
var _head: Node3D
var _skin: Color
var _hair: Color
var _brow: Color
var _beard_kind := ""
var _hat := "band"
var _style := "short"

func build(rig: Node3D, head: Node3D, look: Dictionary) -> void:
	_rig = rig
	_head = head
	_skin = look["skin"]
	_hair = look["hair"]
	_brow = look.get("brow", _hair.darkened(0.12))
	_beard_kind = look.get("beard", "")
	_hat = look.get("hat", "band")
	_style = look.get("hair_style", "short")
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = preload("res://assets/shaders/builder_sculpt.gdshader")
	_face()
	_beard()
	_haircut()
	var cloth: Color = look["hat_color"]
	match _hat:
		"wrap":
			_turban(cloth, look.get("band", cloth.darkened(0.3)))
		"hood":
			_hood(cloth)
		"helmet":
			_helmet(cloth)
		_:
			_headband(cloth, look.get("stripe", cloth.lightened(0.10)) if _hat == "scarf" else cloth.lightened(0.10))

func _add(mesh: Mesh, color: Color, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var part: MeshInstance3D = _rig._part(_head, mesh, color, pos, rot)
	part.material_override = _material
	return part

func _oval(size: Vector3, color: Color, pos: Vector3, rot := Vector3.ZERO) -> void:
	_add(_rig._ellipsoid(size, true), color, pos, rot)

func _face() -> void:
	# Skull, temples, cheekbones and jaw form one continuous surface.
	_add(_profile("face", [
		Vector4(-0.005, 0.12, 0.14, -0.10), Vector4(0.06, 0.22, 0.23, -0.19),
		Vector4(0.15, 0.275, 0.28, -0.245), Vector4(0.25, 0.31, 0.29, -0.27),
		Vector4(0.35, 0.305, 0.283, -0.28), Vector4(0.45, 0.30, 0.265, -0.275),
		Vector4(0.54, 0.275, 0.22, -0.25), Vector4(0.61, 0.19, 0.12, -0.19),
		Vector4(0.64, 0.015, -0.025, -0.055)], 0.82), _skin)
	for side: float in [-1.0, 1.0]:
		# Ears have a warm concha and a raised helix, visible in the profile view.
		_oval(Vector3(0.135, 0.195, 0.125), _skin, Vector3(side * 0.317, 0.295, 0.005), Vector3(0, side * 0.25, side * -0.10))
		_oval(Vector3(0.037, 0.125, 0.077), _skin.darkened(0.24), Vector3(side * 0.377, 0.30, 0.019))
		_lock("ear%s" % side, [Vector3(side * 0.387, 0.252, 0.023), Vector3(side * 0.400, 0.30, 0.049), Vector3(side * 0.395, 0.343, 0.010), Vector3(side * 0.385, 0.291, -0.008)], 0.013, 0.012, _skin.lightened(0.06), Vector3(side, 0, 0))
		var eye := Vector3(side * 0.132, 0.346, 0.267)
		_oval(Vector3(0.166, 0.113, 0.040), _skin.darkened(0.20), eye)
		_oval(Vector3(0.142, 0.088, 0.041), Color(0.95, 0.88, 0.72), eye + Vector3(0, -0.002, 0.012))
		_oval(Vector3(0.068, 0.077, 0.022), Color(0.27, 0.13, 0.052), eye + Vector3(-side * 0.008, -0.003, 0.033))
		_oval(Vector3(0.039, 0.058, 0.012), Color(0.055, 0.027, 0.019), eye + Vector3(-side * 0.008, 0, 0.045))
		_oval(Vector3(0.018, 0.020, 0.009), Color(1, 0.97, 0.87), eye + Vector3(-0.014, 0.016, 0.053))
		_lock("upper_lid%s" % side, [eye + Vector3(-0.077, 0.0, 0.017), eye + Vector3(-0.038, 0.065, 0.035), eye + Vector3(0.035, 0.061, 0.035), eye + Vector3(0.076, -0.004, 0.009)], 0.014, 0.013, _skin.darkened(0.28))
		_lock("lower_lid%s" % side, [eye + Vector3(-0.071, -0.01, 0.017), eye + Vector3(-0.034, -0.057, 0.03), eye + Vector3(0.04, -0.057, 0.03), eye + Vector3(0.075, -0.004, 0.01)], 0.010, 0.010, _skin.lightened(0.04))
		# Inner brow sits low; the outer end arches and tapers into the temple.
		_lock("brow%s" % side, [Vector3(side * 0.038, 0.386, 0.285), Vector3(side * 0.10, 0.412, 0.307), Vector3(side * 0.18, 0.430, 0.287), Vector3(side * 0.232, 0.405, 0.247)], 0.032, 0.024, _brow)
	# One continuous bridge and tip, with the root embedded in the forehead.
	_add(_profile("nose", [Vector4(0.225, 0.025, 0.310, 0.25),
		Vector4(0.24, 0.056, 0.350, 0.25), Vector4(0.263, 0.071, 0.397, 0.25),
		Vector4(0.293, 0.055, 0.368, 0.25), Vector4(0.34, 0.038, 0.316, 0.25),
		Vector4(0.393, 0.024, 0.275, 0.25)], 1.0), _skin)
	_oval(Vector3(0.11, 0.055, 0.060), _skin, Vector3(0, 0.257, 0.371))
	for side: float in [-1.0, 1.0]:
		_oval(Vector3(0.028, 0.017, 0.020), _skin.darkened(0.46), Vector3(side * 0.042, 0.232, 0.351))
	_oval(Vector3(0.155, 0.026, 0.025), Color(0.24, 0.085, 0.038), Vector3(0, 0.154, 0.297))
	_oval(Vector3(0.12, 0.025, 0.027), _skin.darkened(0.10), Vector3(0, 0.134, 0.303))

func _beard() -> void:
	if _beard_kind.is_empty():
		return
	var short := _beard_kind == "short"
	# Compact chin mass leaves the neck and tunic visible, matching the turnaround.
	if not short:
		_oval(Vector3(0.54, 0.22, 0.34), _hair, Vector3(0, 0.065, 0.125))
		_add(_beard_surface(), _hair.lightened(0.012))
	for side: float in [-1.0, 1.0]:
		_oval(Vector3(0.16, 0.27, 0.31), _hair, Vector3(side * 0.255, 0.17, 0.078), Vector3(0.18, 0, side * -0.18))
		for i in 3:
			var x := side * (0.252 - i * 0.035)
			var y := 0.225 - i * 0.026
			_lock("jaw%s_%s" % [side, i], [Vector3(x, y, 0.242), Vector3(x, y - 0.025, 0.271), Vector3(x - side * 0.013, y - 0.08, 0.282), Vector3(x - side * 0.025, y - 0.12, 0.263)], 0.034, 0.013, _hair.lightened(0.018 * (i % 2)))
		# Moustache grows outward from the philtrum and hooks down at the corner.
		_lock("moustache%s" % side, [Vector3(side * 0.006, 0.214, 0.333), Vector3(side * 0.068, 0.237, 0.36), Vector3(side * 0.125, 0.183, 0.348), Vector3(side * 0.175, 0.172, 0.300)], 0.033, 0.034, _hair.lightened(0.025))
	if short:
		# A close-cropped chin: a short, rounded tuft under the lip and a shadow along the jaw.
		_oval(Vector3(0.40, 0.17, 0.26), _hair, Vector3(0, 0.07, 0.19))
		for i in 5:
			var x := (i - 2) * 0.05
			_lock("tuft%s" % i, [Vector3(x, 0.10, 0.311), Vector3(x + 0.006, 0.07, 0.340), Vector3(x + 0.006, 0.035, 0.318), Vector3(x * 0.9, 0.012 + absf(x) * 0.12, 0.262)], 0.030, 0.014, _hair.lightened(0.013 * (i % 3)))
		return
	for i in 7:
		var x := (i - 3) * 0.043
		_lock("chin%s" % i, [Vector3(x, 0.10, 0.311), Vector3(x + 0.009, 0.07, 0.350), Vector3(x + 0.009, 0.018, 0.301), Vector3(x * 0.86, -0.029 + absf(x) * 0.20, 0.193)], 0.028, 0.014, _hair.lightened(0.013 * (i % 3)))
	if _beard_kind == "long":
		# A patriarch's beard: five heavy tails falling over the chest.
		for i in 5:
			var x := (i - 2) * 0.062
			var fall := 0.40 - absf(i - 2) * 0.07
			_lock("long%s" % i, [Vector3(x, -0.01, 0.255), Vector3(x * 1.1, -0.12, 0.335), Vector3(x * 0.8, -fall * 0.7, 0.33), Vector3(x * 0.5, -fall, 0.29)], 0.062, 0.030, _hair.lightened(0.014 * (i % 3)), Vector3.FORWARD, true)

func _haircut() -> void:
	if _hat == "wrap" or _hat == "hood" or _hat == "helmet":
		# Only the nape and the sideburns show under the cloth.
		_oval(Vector3(0.59, 0.40, 0.225), _hair, Vector3(0, 0.335, -0.205))
		for side: float in [-1.0, 1.0]:
			_lock("sideburn%s" % side, [Vector3(side * 0.287, 0.371, 0.125), Vector3(side * 0.31, 0.34, 0.16), Vector3(side * 0.28, 0.28, 0.17), Vector3(side * 0.27, 0.21, 0.21)], 0.037, 0.028, _hair, Vector3(side, 0, 0))
		return
	_oval(Vector3(0.65, 0.235, 0.61), _hair, Vector3(0, 0.552, -0.025))
	_oval(Vector3(0.59, 0.40, 0.225), _hair, Vector3(0, 0.335, -0.205))
	if _style == "curly":
		# Tight curls: a cap of overlapping tufts over the band and down the nape.
		for i in 16:
			var h := float(hash(i * 5 + 1) % 9) / 9.0
			var x := (i % 4 - 1.5) * 0.17
			var z := (i / 4 - 1.5) * 0.16
			_oval(Vector3(0.20, 0.17, 0.20), _hair.lightened(h * 0.10), Vector3(x, 0.62 + h * 0.03 - (absf(x) + absf(z)) * 0.20, z - 0.02), Vector3(h, h * 2.0, 0))
		for i in 8:
			var x := (i % 4 - 1.5) * 0.18
			_oval(Vector3(0.19, 0.18, 0.17), _hair.lightened((i % 3) * 0.04), Vector3(x, 0.30 - (i / 4) * 0.15, -0.30))
	elif _style == "bushy":
		# Thick mane: heavy locks falling past the ears to the shoulders.
		for side: float in [-1.0, 1.0]:
			for i in 3:
				_oval(Vector3(0.17, 0.30, 0.17), _hair.lightened(i * 0.025), Vector3(side * 0.31, 0.22 - i * 0.04, -0.02 - i * 0.12), Vector3(-0.25, 0, side * 0.15))
		_oval(Vector3(0.60, 0.42, 0.22), _hair.lightened(0.02), Vector3(0, 0.10, -0.30))
	# Staggered nape locks, swept off the ears. No grid of disconnected blobs.
	for i in 7:
		# Sweep around the back half of the skull (front is +Z).
		var p := Vector3(cos(i * PI / 6.0) * 0.29, 0.43, -sin(i * PI / 6.0) * 0.26 - 0.035)
		var outward := Vector3(p.x, 0, p.z).normalized()
		_lock("nape%s" % i, [p, p + outward * 0.05 + Vector3(0, -0.05, 0), p + outward * 0.055 + Vector3(0.025, -0.17, 0), p + Vector3(0.035, -0.235, 0)], 0.068, 0.052, _hair.lightened(0.018 * (i % 3)), outward)
	# Authored sweeps follow the scalp and overlap asymmetrically, like the reference.
	# Each row is a cubic path in X/Z; height follows the crown instead of floating.
	var sweeps := [
		[Vector2(-0.29, -0.15), Vector2(-0.31, -0.04), Vector2(-0.20, 0.08), Vector2(-0.23, 0.21)],
		[Vector2(-0.22, -0.23), Vector2(-0.17, -0.08), Vector2(-0.28, 0.12), Vector2(-0.15, 0.26)],
		[Vector2(-0.13, -0.27), Vector2(-0.08, -0.09), Vector2(-0.19, 0.14), Vector2(-0.05, 0.28)],
		[Vector2(-0.01, -0.28), Vector2(0.10, -0.10), Vector2(-0.09, 0.13), Vector2(0.07, 0.28)],
		[Vector2(0.11, -0.26), Vector2(0.23, -0.09), Vector2(0.05, 0.13), Vector2(0.16, 0.25)],
		[Vector2(0.23, -0.18), Vector2(0.31, -0.08), Vector2(0.20, 0.13), Vector2(0.26, 0.17)],
		[Vector2(-0.22, -0.25), Vector2(-0.12, -0.30), Vector2(0.01, -0.27), Vector2(0.06, -0.22)],
		[Vector2(0.02, -0.29), Vector2(0.13, -0.29), Vector2(0.24, -0.23), Vector2(0.27, -0.12)]
	]
	for i in sweeps.size():
		var points: Array = []
		for j in 4:
			var p: Vector2 = sweeps[i][j]
			var dome := sqrt(maxf(0.0, 1.0 - pow(p.x / 0.37, 2) - pow(p.y / 0.36, 2)))
			var y := 0.535 + dome * 0.14 + (0.045 if j == 1 or j == 2 else 0.0)
			points.append(Vector3(p.x, y, p.y))
		_lock("sweep%s" % i, points, 0.093 if i < 6 else 0.069, 0.052, _hair.lightened(0.018 * (i % 4)), Vector3.UP, true)
	_lock("fringe_left", [Vector3(-0.30, 0.545, 0.08), Vector3(-0.24, 0.645, 0.23), Vector3(-0.06, 0.632, 0.31), Vector3(-0.10, 0.55, 0.306)], 0.061, 0.040, _hair.lightened(0.03), Vector3(0, 0.7, 0.7), true)
	_lock("fringe_center", [Vector3(-0.16, 0.625, 0.07), Vector3(-0.03, 0.678, 0.22), Vector3(0.16, 0.618, 0.31), Vector3(0.10, 0.554, 0.31)], 0.064, 0.040, _hair.lightened(0.045), Vector3(0, 0.7, 0.7), true)
	for side: float in [-1.0, 1.0]:
		_lock("temple%s" % side, [Vector3(side * 0.27, 0.462, 0.14), Vector3(side * 0.33, 0.43, 0.12), Vector3(side * 0.29, 0.38, 0.11), Vector3(side * 0.285, 0.346, 0.16)], 0.043, 0.035, _hair, Vector3(side, 0, 0), true)
		_lock("sideburn%s" % side, [Vector3(side * 0.287, 0.371, 0.125), Vector3(side * 0.31, 0.34, 0.16), Vector3(side * 0.28, 0.28, 0.17), Vector3(side * 0.27, 0.21, 0.21)], 0.037, 0.028, _hair, Vector3(side, 0, 0))
	# One distinctive forelock curls over the band on the builder's left.
	_lock("forelock", [Vector3(0.12, 0.622, 0.13), Vector3(0.30, 0.66, 0.20), Vector3(0.29, 0.52, 0.351), Vector3(0.21, 0.503, 0.335)], 0.063, 0.037, _hair.lightened(0.03), Vector3(0, 0.6, 0.8), true)

func _headband(color: Color, fold: Color) -> void:
	# A soft, uneven wrapped ribbon with diagonal folds; back knot and tapered tails.
	_add(_band(), color)
	for i in 2:
		_lock("band_fold%s" % i, [Vector3(-0.28, 0.49 + i * 0.029, 0.16), Vector3(-0.13, 0.48 + i * 0.037, 0.358), Vector3(0.12, 0.53 + i * 0.028, 0.359), Vector3(0.28, 0.53 + i * 0.019, 0.17)], 0.010, 0.006, fold)
	_oval(Vector3(0.12, 0.105, 0.09), color.darkened(0.1), Vector3(-0.10, 0.49, -0.329))
	for i in 2:
		_lock("band_tail%s" % i, [Vector3(-0.10, 0.49, -0.33), Vector3(-0.17 - i * 0.03, 0.42, -0.40), Vector3(-0.22 + i * 0.17, 0.29, -0.42), Vector3(-0.26 + i * 0.19, 0.23 + i * 0.035, -0.39)], 0.067, 0.014, color.lightened(i * 0.06), Vector3.BACK)

func _turban(cloth: Color, band: Color) -> void:
	# Wound head-cloth over the crown, a coloured band, cloth falling behind to the shoulders.
	_oval(Vector3(0.80, 0.40, 0.76), cloth, Vector3(0, 0.56, -0.02))
	for k in 3:
		_oval(Vector3(0.78 - k * 0.07, 0.19, 0.74 - k * 0.07), cloth.darkened(0.07 + k * 0.02), Vector3(0, 0.55 + k * 0.07, -0.02 - k * 0.02), Vector3(0, 0, 0.12 - k * 0.10))
	_add(_band(), band)
	_oval(Vector3(0.74, 0.50, 0.15), cloth.darkened(0.04), Vector3(0, 0.24, -0.37), Vector3(0.12, 0, 0))
	for side: float in [-1.0, 1.0]:
		_oval(Vector3(0.14, 0.52, 0.42), cloth.darkened(0.02), Vector3(side * 0.37, 0.24, -0.12), Vector3(-0.12, 0, side * 0.10))

func _hood(cloth: Color) -> void:
	_oval(Vector3(0.78, 0.40, 0.72), cloth, Vector3(0, 0.55, -0.06))
	_oval(Vector3(0.76, 0.66, 0.30), cloth, Vector3(0, 0.28, -0.30))
	for side: float in [-1.0, 1.0]:
		_oval(Vector3(0.13, 0.56, 0.48), cloth, Vector3(side * 0.37, 0.30, -0.07), Vector3(0, 0, side * 0.05))
	_oval(Vector3(0.86, 0.26, 0.56), cloth.darkened(0.06), Vector3(0, -0.06, -0.14))

func _helmet(metal: Color) -> void:
	_oval(Vector3(0.74, 0.50, 0.70), metal, Vector3(0, 0.56, -0.03))
	_add(_rig._soft(Vector3(0.78, 0.07, 0.74), 0.02), metal.darkened(0.25), Vector3(0, 0.46, -0.02))
	_add(_rig._soft(Vector3(0.07, 0.30, 0.06), 0.015), metal.darkened(0.15), Vector3(0, 0.34, 0.345))

# Cubic sweep with a rounded root and a tapered tip. A shallow lobed
# cross section gives each hair lock longitudinal sculpted grooves.
func _lock(key: String, points: Array, width: float, depth: float, color: Color, outward := Vector3.FORWARD, grooves := false) -> void:
	if not _cache.has(key):
		var vertices := PackedVector3Array()
		var indices := PackedInt32Array()
		var uv := PackedVector2Array()
		var steps := 16 if grooves else 10
		var sides := 16 if grooves else 10
		for i in steps + 1:
			var t := float(i) / steps
			var center: Vector3 = points[0].bezier_interpolate(points[1], points[2], points[3], t)
			var tangent: Vector3 = points[0].bezier_derivative(points[1], points[2], points[3], t).normalized()
			var side := tangent.cross(outward).normalized()
			if side.length_squared() < 0.1:
				side = tangent.cross(Vector3.RIGHT).normalized()
			var normal := side.cross(tangent).normalized()
			var taper := pow(sin(PI * t), 0.48) * (1.12 - t * 0.52)
			taper = maxf(taper, 0.012)
			for j in sides:
				var a := TAU * j / sides
				var ridge := 1.0 + (0.11 * cos(a * 6.0 + t * 0.6) if grooves else 0.0)
				vertices.append(center + side * cos(a) * width * taper + normal * sin(a) * depth * taper * ridge)
				uv.append(Vector2(float(j) / sides, t))
				if i < steps:
					var k := i * sides + j
					var next := i * sides + (j + 1) % sides
					indices.append_array(PackedInt32Array([k, next, k + sides, next, next + sides, k + sides]))
		_cache[key] = _mesh(vertices, indices, uv)
	var part := _add(_cache[key], color)
	if grooves:
		part.set_instance_shader_parameter("hair_detail", 1.0)

static func _profile(key: String, rings: Array, roundness: float) -> Mesh:
	if _cache.has(key):
		return _cache[key]
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	const SIDES := 36
	var smooth_rings: Array[Vector4] = []
	for i in rings.size() - 1:
		var a: Vector4 = rings[maxi(0, i - 1)]
		var b: Vector4 = rings[i]
		var c: Vector4 = rings[i + 1]
		var d: Vector4 = rings[mini(rings.size() - 1, i + 2)]
		for step in 4:
			var t := step / 4.0
			smooth_rings.append((2.0 * b + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t * t + (-a + 3.0 * b - 3.0 * c + d) * t * t * t) * 0.5)
	smooth_rings.append(rings.back())
	for i in smooth_rings.size():
		var ring := smooth_rings[i]
		for j in SIDES:
			var a := TAU * j / SIDES
			var x := signf(cos(a)) * pow(absf(cos(a)), roundness) * ring.y
			var front_power := 0.28 if key == "nose" else 0.68
			var z := pow(sin(a), front_power) * ring.z if sin(a) >= 0 else sin(a) * -ring.w
			if key == "face" and sin(a) > 0:
				# Cheekbone volume belongs to the continuous face surface.
				z += 0.018 * exp(-pow((absf(x) - 0.18) / 0.075, 2.0) - pow((ring.x - 0.25) / 0.08, 2.0))
			vertices.append(Vector3(x, ring.x, z))
			if i < smooth_rings.size() - 1:
				var k := i * SIDES + j
				var next := i * SIDES + (j + 1) % SIDES
				indices.append_array(PackedInt32Array([k, next, k + SIDES, next, next + SIDES, k + SIDES]))
	_cache[key] = _mesh(vertices, indices)
	return _cache[key]

static func _beard_surface() -> Mesh:
	if _cache.has("beard_surface"):
		return _cache["beard_surface"]
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	const ROW := 13
	for i in 41:
		var u := (i - 20) / 20.0
		var upper := 0.12 + 0.15 * pow(absf(u), 1.6)
		var lower := -0.040 + 0.09 * u * u
		for j in ROW:
			var t := j / float(ROW - 1)
			var y := lerpf(upper, lower, t) + cos(u * PI * 8) * 0.005 * t * t
			var z := 0.30 + 0.045 * sin(PI * t) - 0.14 * t * t * t - 0.11 * u * u
			z += cos(u * PI * 8 + t * 0.5) * 0.004 * sin(t * PI)
			vertices.append(Vector3(u * 0.282, y, z))
			if i < 40 and j < ROW - 1:
				var k := i * ROW + j
				indices.append_array(PackedInt32Array([k, k + ROW, k + 1, k + 1, k + ROW, k + ROW + 1]))
	_cache["beard_surface"] = _mesh(vertices, indices)
	return _cache["beard_surface"]

static func _band() -> Mesh:
	if _cache.has("headband"):
		return _cache["headband"]
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	const SIDES := 48
	const RINGS := 6
	for i in RINGS:
		var t := float(i) / (RINGS - 1)
		for j in SIDES:
			var a := TAU * j / SIDES
			var puff := sin(t * PI) * 0.014 + sin(a * 3 + t * 7) * 0.003
			var tuck := smoothstep(0.7, 1.0, t)
			vertices.append(Vector3(cos(a) * (0.337 + puff - tuck * 0.012), 0.454 + t * 0.109 + cos(a + 0.3) * 0.016, sin(a) * (0.320 + puff - tuck * 0.015) - 0.014))
			if i < RINGS - 1:
				var k := i * SIDES + j
				var next := i * SIDES + (j + 1) % SIDES
				indices.append_array(PackedInt32Array([k, next, k + SIDES, next, next + SIDES, k + SIDES]))
	_cache["headband"] = _mesh(vertices, indices)
	return _cache["headband"]

static func _mesh(vertices: PackedVector3Array, indices: PackedInt32Array, uv := PackedVector2Array()) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	if not uv.is_empty():
		arrays[Mesh.ARRAY_TEX_UV] = uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var surface := SurfaceTool.new()
	surface.create_from(mesh, 0)
	surface.generate_normals()
	return surface.commit()
