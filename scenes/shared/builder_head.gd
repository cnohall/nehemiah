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
var _clustered_builder := false

func build(rig: Node3D, head: Node3D, look: Dictionary) -> void:
	_rig = rig
	_head = head
	_skin = look["skin"]
	_hair = look["hair"]
	_brow = look.get("brow", _hair.darkened(0.12))
	_beard_kind = look.get("beard", "")
	_hat = look.get("hat", "band")
	_style = look.get("hair_style", "short")
	_clustered_builder = _style == "short" and look.get("basket_stones", false)
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
	# A single rounded-square skull. The broad lower rings keep the jaw from
	# becoming a point, while the flat crown disappears under the hair cap.
	_add(_profile("face", [
		Vector4(-0.025, 0.09, 0.13, -0.09), Vector4(0.015, 0.20, 0.22, -0.18),
		Vector4(0.105, 0.285, 0.27, -0.24), Vector4(0.23, 0.315, 0.285, -0.27),
		Vector4(0.35, 0.305, 0.28, -0.275), Vector4(0.47, 0.285, 0.26, -0.26),
		Vector4(0.56, 0.255, 0.205, -0.23), Vector4(0.625, 0.17, 0.105, -0.16),
		Vector4(0.645, 0.015, 0.0, -0.03)], 0.74), _skin)
	for side: float in [-1.0, 1.0]:
		# One flattened ear and one shallow inset, with no small helix details.
		_oval(Vector3(0.13, 0.19, 0.115), _skin, Vector3(side * 0.326, 0.315, 0.005))
		_oval(Vector3(0.032, 0.105, 0.065), _skin.darkened(0.17), Vector3(side * 0.387, 0.32, 0.028))
		# Smaller eyes sit deeper in the face, with the brow shading their tops.
		var eye := Vector3(side * 0.135, 0.340, 0.224)
		_oval(Vector3(0.132, 0.103, 0.075), Color(0.97, 0.92, 0.83), eye)
		_oval(Vector3(0.067, 0.073, 0.024), Color(0.19, 0.11, 0.07), eye + Vector3(-side * 0.009, -0.004, 0.032))
		_oval(Vector3(0.035, 0.051, 0.012), Color(0.045, 0.029, 0.024), eye + Vector3(-side * 0.009, -0.004, 0.044))
		# The inner brow sits lowest, giving the builder a focused expression.
		_lock("brow%s" % side, [Vector3(side * 0.040, 0.382, 0.315), Vector3(side * 0.096, 0.395, 0.344), Vector3(side * 0.174, 0.428, 0.322), Vector3(side * 0.245, 0.415, 0.263)], 0.046, 0.034, _brow)
	# One broad bridge and rounded tip, projecting beyond the eyes in profile.
	_add(_profile("nose", [Vector4(0.220, 0.033, 0.308, 0.25),
		Vector4(0.248, 0.072, 0.375, 0.25), Vector4(0.280, 0.093, 0.408, 0.25),
		Vector4(0.320, 0.072, 0.385, 0.25), Vector4(0.390, 0.030, 0.280, 0.25)], 0.95), _skin)
	_oval(Vector3(0.125, 0.025, 0.018), _skin.darkened(0.37), Vector3(0, 0.152, 0.297))

func _beard() -> void:
	if _beard_kind.is_empty():
		return
	var short := _beard_kind == "short"
	# The wrap is one closed cheek-to-cheek volume. Its front top dips under
	# the mouth; the sides rise into the sideburns.
	_add(_beard_mass(short), _hair)
	for side: float in [-1.0, 1.0]:
		# Two large cheek locks per side, overlapping the broad mass.
		_lock("cheek_upper%s" % side, [Vector3(side * 0.275, 0.260, 0.160), Vector3(side * 0.355, 0.228, 0.242), Vector3(side * 0.350, 0.142, 0.294), Vector3(side * 0.263, 0.103, 0.283)], 0.088, 0.038, _hair.lightened(0.020), Vector3(side, 0, 0))
		_lock("cheek_lower%s" % side, [Vector3(side * 0.258, 0.172, 0.248), Vector3(side * 0.330, 0.132, 0.312), Vector3(side * 0.270, 0.008, 0.327), Vector3(side * 0.175, -0.045, 0.260)], 0.078, 0.041, _hair.lightened(0.010), Vector3.FORWARD)
		# Moustache remains two separate curved wedges above the beard.
		_lock("moustache%s" % side, [Vector3(side * 0.018, 0.200, 0.338), Vector3(side * 0.070, 0.222, 0.386), Vector3(side * 0.132, 0.194, 0.370), Vector3(side * 0.190, 0.177, 0.313)], 0.050, 0.035, _hair.lightened(0.025))
	# Four chunky chin locks, with their tips defining a soft scalloped edge.
	for i in 4:
		var x := (i - 1.5) * 0.108
		var central := i == 1 or i == 2
		var tip_y := (-0.070 if central else -0.050) if short else (-0.138 if central else -0.092)
		_lock("chin_%s_%s" % ["short" if short else "full", i], [Vector3(x, 0.103, 0.313), Vector3(x + 0.022, 0.068, 0.388), Vector3(x + 0.014, -0.050, 0.375), Vector3(x * 0.82, tip_y, 0.215)], 0.082 if central else 0.064, 0.056, _hair.lightened(0.009 * (i % 3)))
	if _beard_kind == "long":
		for i in 3:
			var x := (i - 1) * 0.115
			_lock("long%s" % i, [Vector3(x, -0.06, 0.25), Vector3(x * 1.15, -0.15, 0.36), Vector3(x * 0.8, -0.30, 0.32), Vector3(x * 0.45, -0.39 + absf(x) * 0.5, 0.20)], 0.077, 0.055, _hair.lightened(0.012 * i))

func _haircut() -> void:
	if _hat == "wrap" or _hat == "hood" or _hat == "helmet":
		# Covered heads retain only a simple nape and sideburns.
		_oval(Vector3(0.60, 0.30, 0.26), _hair, Vector3(0, 0.35, -0.20))
		for side: float in [-1.0, 1.0]:
			_lock("sideburn%s" % side, [Vector3(side * 0.285, 0.41, 0.12), Vector3(side * 0.33, 0.36, 0.15), Vector3(side * 0.30, 0.27, 0.19), Vector3(side * 0.27, 0.22, 0.20)], 0.045, 0.034, _hair, Vector3(side, 0, 0))
		return
	# One cap provides the common crown and back volume.
	_add(_profile("hair_cap", [Vector4(0.19, 0.16, 0.02, -0.25),
		Vector4(0.28, 0.27, 0.07, -0.32), Vector4(0.395, 0.33, 0.21, -0.35),
		Vector4(0.48, 0.34, 0.29, -0.35), Vector4(0.585, 0.355, 0.30, -0.35),
		Vector4(0.69, 0.29, 0.25, -0.29), Vector4(0.755, 0.11, 0.10, -0.11),
		Vector4(0.765, 0.012, 0.0, -0.01)], 0.85), _hair)
	if _clustered_builder:
		_builder_clustered_hair()
		return
	var lift := 0.018 if _style == "curly" else 0.0
	var locks := [
		[Vector3(-0.30, 0.58, -0.13), Vector3(-0.36, 0.73, 0.00), Vector3(-0.30, 0.69, 0.20), Vector3(-0.22, 0.59, 0.27)],
		[Vector3(-0.22, 0.67, -0.19), Vector3(-0.15, 0.79, -0.05), Vector3(-0.15, 0.70, 0.22), Vector3(-0.07, 0.59, 0.28)],
		[Vector3(-0.07, 0.70, -0.22), Vector3(0.02, 0.82, -0.06), Vector3(0.04, 0.73, 0.22), Vector3(0.10, 0.59, 0.29)],
		[Vector3(0.10, 0.68, -0.20), Vector3(0.23, 0.79, -0.04), Vector3(0.27, 0.68, 0.20), Vector3(0.24, 0.59, 0.27)],
		[Vector3(0.26, 0.61, -0.12), Vector3(0.39, 0.71, 0.01), Vector3(0.36, 0.62, 0.20), Vector3(0.29, 0.57, 0.23)],
		[Vector3(-0.25, 0.66, -0.28), Vector3(-0.16, 0.77, -0.33), Vector3(-0.05, 0.70, -0.33), Vector3(0.03, 0.47, -0.33)],
		[Vector3(0.07, 0.69, -0.29), Vector3(0.18, 0.76, -0.33), Vector3(0.29, 0.63, -0.29), Vector3(0.26, 0.43, -0.28)]
	]
	for i in locks.size():
		var points: Array = locks[i].duplicate()
		for j in points.size():
			points[j] = points[j] + Vector3(0, lift, 0)
		var width: float = [0.094, 0.116, 0.120, 0.108, 0.068, 0.060, 0.060][i]
		_lock("hair_%s_%s" % [_style, i], points, width, 0.066 if i < 4 else 0.047, _hair.lightened(0.012 * (i % 3)), Vector3.UP)
	if _style == "bushy":
		for side: float in [-1.0, 1.0]:
			_lock("bushy_side%s" % side, [Vector3(side * 0.32, 0.51, -0.17), Vector3(side * 0.39, 0.40, -0.17), Vector3(side * 0.36, 0.22, -0.19), Vector3(side * 0.31, 0.10, -0.21)], 0.075, 0.060, _hair, Vector3(side, 0, 0))

func _builder_clustered_hair() -> void:
	# Four broad clumps frame the forehead. Their roots blend into the cap and
	# their tips tuck toward the headband, keeping the front rounded and full.
	_lock("builder_front_left", [Vector3(-0.09, 0.65, -0.10), Vector3(-0.26, 0.77, 0.08), Vector3(-0.36, 0.66, 0.34), Vector3(-0.23, 0.565, 0.30)], 0.115, 0.070, _hair.lightened(0.018), Vector3.UP)
	_lock("builder_front_mid_left", [Vector3(0.04, 0.68, -0.13), Vector3(-0.08, 0.78, 0.06), Vector3(-0.18, 0.67, 0.36), Vector3(-0.08, 0.57, 0.30)], 0.124, 0.078, _hair.lightened(0.010), Vector3.UP)
	_lock("builder_front_mid_right", [Vector3(0.18, 0.66, -0.05), Vector3(0.25, 0.75, 0.07), Vector3(0.18, 0.68, 0.28), Vector3(0.13, 0.585, 0.29)], 0.111, 0.073, _hair.lightened(0.025), Vector3.UP)
	_lock("builder_front_right", [Vector3(0.28, 0.63, -0.06), Vector3(0.35, 0.70, 0.04), Vector3(0.31, 0.64, 0.20), Vector3(0.28, 0.59, 0.22)], 0.086, 0.061, _hair, Vector3.UP)
	# Two restrained crown forms and two short nape forms complete the shape.
	_lock("builder_crown_left", [Vector3(-0.24, 0.63, -0.23), Vector3(-0.28, 0.77, -0.13), Vector3(-0.12, 0.80, 0.13), Vector3(-0.03, 0.67, 0.23)], 0.080, 0.047, _hair.lightened(0.013), Vector3.UP)
	_lock("builder_crown_right", [Vector3(0.12, 0.67, -0.26), Vector3(0.30, 0.79, -0.15), Vector3(0.33, 0.70, 0.09), Vector3(0.24, 0.61, 0.18)], 0.082, 0.045, _hair.lightened(0.008), Vector3.UP)
	for side: float in [-1.0, 1.0]:
		_lock("builder_nape%s" % side, [Vector3(side * 0.15, 0.40, -0.23), Vector3(side * 0.23, 0.38, -0.28), Vector3(side * 0.21, 0.28, -0.28), Vector3(side * 0.16, 0.22, -0.24)], 0.054, 0.040, _hair, Vector3.BACK)

func _headband(color: Color, fold: Color) -> void:
	# Broad ribbon, one fold, and a compact side/rear knot.
	_add(_band(), color)
	_lock("band_fold", [Vector3(-0.28, 0.50, 0.17), Vector3(-0.10, 0.49, 0.355), Vector3(0.12, 0.54, 0.358), Vector3(0.28, 0.53, 0.17)], 0.012, 0.007, fold)
	_oval(Vector3(0.12, 0.11, 0.095), color.darkened(0.07), Vector3(-0.16, 0.51, -0.33))
	for i in 2:
		_lock("band_tail%s" % i, [Vector3(-0.16, 0.50, -0.34), Vector3(-0.23 + i * 0.09, 0.43, -0.41), Vector3(-0.29 + i * 0.20, 0.29, -0.42), Vector3(-0.31 + i * 0.22, 0.21 + i * 0.04, -0.39)], 0.069, 0.018, color.lightened(i * 0.05), Vector3.BACK)

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

# Cubic sweep with a rounded root and a tapered tip.
func _lock(key: String, points: Array, width: float, depth: float, color: Color, outward := Vector3.FORWARD, grooves := false) -> void:
	if not _cache.has(key):
		var vertices := PackedVector3Array()
		var indices := PackedInt32Array()
		var uv := PackedVector2Array()
		var steps := 12
		var sides := 12
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
				vertices.append(center + side * cos(a) * width * taper + normal * sin(a) * depth * taper)
				uv.append(Vector2(float(j) / sides, t))
				if i < steps:
					var k := i * sides + j
					var next := i * sides + (j + 1) % sides
					indices.append_array(PackedInt32Array([k, next, k + sides, next, next + sides, k + sides]))
		_cache[key] = _mesh(vertices, indices, uv)
	_add(_cache[key], color)

static func _profile(key: String, rings: Array, roundness: float) -> Mesh:
	if _cache.has(key):
		return _cache[key]
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	const SIDES := 24
	var smooth_rings: Array[Vector4] = []
	for i in rings.size() - 1:
		var a: Vector4 = rings[maxi(0, i - 1)]
		var b: Vector4 = rings[i]
		var c: Vector4 = rings[i + 1]
		var d: Vector4 = rings[mini(rings.size() - 1, i + 2)]
		for step in 2:
			var t := step / 2.0
			smooth_rings.append((2.0 * b + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t * t + (-a + 3.0 * b - 3.0 * c + d) * t * t * t) * 0.5)
	smooth_rings.append(rings.back())
	for i in smooth_rings.size():
		var ring := smooth_rings[i]
		for j in SIDES:
			var a := TAU * j / SIDES
			var x := signf(cos(a)) * pow(absf(cos(a)), roundness) * ring.y * (0.86 if key == "face" else 1.0)
			var front_power := 0.28 if key == "nose" else 0.68
			var z := pow(sin(a), front_power) * ring.z if sin(a) >= 0 else sin(a) * -ring.w
			if key == "face":
				z *= 0.92
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

static func _beard_mass(short: bool) -> Mesh:
	var key := "beard_mass_short" if short else "beard_mass_full"
	if _cache.has(key):
		return _cache[key]
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	const SIDES := 24
	const RINGS := 10
	for i in RINGS:
		var t := float(i) / (RINGS - 1)
		for j in SIDES:
			var a := TAU * j / SIDES
			var front := maxf(0.0, sin(a))
			var y := lerpf(0.27, -0.055 if short else -0.125, t) - 0.15 * pow(front, 4.0) * pow(1.0 - t, 3.0)
			var width := 0.27 + 0.08 * sin(PI * t) - 0.255 * pow(t, 4.0)
			var z := 0.07 + 0.06 * t + sin(a) * (0.24 + 0.05 * sin(PI * t) if sin(a) > 0.0 else 0.22)
			vertices.append(Vector3(cos(a) * width, y, z))
			if i < RINGS - 1:
				var k := i * SIDES + j
				var next := i * SIDES + (j + 1) % SIDES
				indices.append_array(PackedInt32Array([k, k + SIDES, next, next, k + SIDES, next + SIDES]))
	_cache[key] = _mesh(vertices, indices)
	return _cache[key]

static func _band() -> Mesh:
	if _cache.has("headband"):
		return _cache["headband"]
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	const SIDES := 32
	const RINGS := 4
	for i in RINGS:
		var t := float(i) / (RINGS - 1)
		for j in SIDES:
			var a := TAU * j / SIDES
			var puff := sin(t * PI) * 0.012
			var tuck := smoothstep(0.7, 1.0, t)
			vertices.append(Vector3(cos(a) * (0.355 + puff - tuck * 0.012), 0.435 + t * 0.14 + cos(a + 0.3) * 0.016, sin(a) * (0.333 + puff - tuck * 0.015) - 0.014))
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
