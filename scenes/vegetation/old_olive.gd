class_name OldOlive
extends Node3D

# A single, hand-shaped olive for art review. It is intentionally separate from
# ScatterLayer until its silhouette has been checked at gameplay scale.

const BARK := Color(0.49, 0.34, 0.23)
const BARK_LIGHT := Color(0.66, 0.48, 0.33)
const CROWN := [
	# centre, width (x), depth (z), seed
	[Vector3(-2.95, 3.31, -0.20), 1.29, 0.85, 1],
	[Vector3(-1.47, 4.03, -0.58), 1.05, 0.88, 2],
	[Vector3(0.16, 4.78, -0.27), 1.36, 0.96, 3],
	[Vector3(1.53, 4.05, 0.03), 1.03, 0.83, 4],
	[Vector3(3.08, 3.22, 0.12), 1.26, 0.84, 5],
	[Vector3(1.86, 2.77, 0.98), 0.88, 0.73, 6],
]

func _ready() -> void:
	scale = Vector3.ONE * 1.25
	var bark := _vertex_material()
	# Flared roots anchor the trunk; their paths also begin its spiral.
	_tube([Vector3(-1.02, 0.05, 0.12), Vector3(-0.50, 0.20, 0.02), Vector3(-0.08, 0.59, -0.04)], [0.30, 0.34, 0.42], bark)
	_tube([Vector3(0.90, 0.05, 0.38), Vector3(0.44, 0.21, 0.20), Vector3(0.04, 0.66, 0.02)], [0.29, 0.33, 0.42], bark)
	_tube([Vector3(0.25, 0.06, -0.89), Vector3(0.11, 0.21, -0.39), Vector3(0.00, 0.62, -0.03)], [0.27, 0.33, 0.40], bark)
	_tube([Vector3(0.0, 0.10, 0.0), Vector3(-0.08, 0.78, -0.02), Vector3(0.26, 1.42, 0.13), Vector3(0.20, 1.98, 0.06)], [0.64, 0.58, 0.47, 0.33], bark)
	_tube([Vector3(-0.26, 0.14, 0.27), Vector3(-0.32, 0.64, 0.20), Vector3(0.10, 1.29, 0.31), Vector3(0.36, 1.86, 0.12)], [0.24, 0.23, 0.19, 0.10], bark)
	_tube([Vector3(0.31, 0.13, -0.22), Vector3(0.37, 0.69, -0.29), Vector3(0.04, 1.35, -0.14), Vector3(-0.01, 1.94, -0.04)], [0.22, 0.22, 0.17, 0.09], bark)
	# Three long limbs curve in different directions rather than radiating as straight rods.
	_tube([Vector3(0.20, 1.75, 0.06), Vector3(-0.50, 2.14, -0.10), Vector3(-1.46, 2.74, -0.27), Vector3(-2.91, 3.26, -0.20)], [0.35, 0.29, 0.19, 0.10], bark)
	_tube([Vector3(0.20, 1.86, 0.06), Vector3(0.38, 2.60, -0.04), Vector3(0.13, 3.54, -0.19), Vector3(0.22, 4.68, -0.20)], [0.31, 0.25, 0.16, 0.08], bark)
	_tube([Vector3(0.24, 1.80, 0.07), Vector3(0.94, 2.05, 0.25), Vector3(1.94, 2.64, 0.31), Vector3(3.02, 3.16, 0.15)], [0.34, 0.27, 0.18, 0.09], bark)
	# Open secondary forks remain visible between the six separate foliage pads.
	_tube([Vector3(-1.46, 2.74, -0.27), Vector3(-1.23, 3.42, -0.49), Vector3(-1.43, 3.93, -0.58)], [0.17, 0.12, 0.06], bark)
	_tube([Vector3(1.94, 2.64, 0.31), Vector3(1.81, 2.59, 0.70), Vector3(1.86, 2.74, 0.98)], [0.16, 0.11, 0.06], bark)
	for entry in CROWN:
		var pos: Vector3 = entry[0]
		var foliage := MeshInstance3D.new()
		foliage.mesh = _foliage_mesh(entry[1], entry[2], entry[3])
		foliage.material_override = _vertex_material()
		foliage.position = pos
		add_child(foliage)

static func _vertex_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

func _tube(points: Array[Vector3], radii: Array[float], mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var samples := (points.size() - 1) * 4
	for i in samples:
		var s0 := i / float(samples)
		var s1 := (i + 1) / float(samples)
		var a := _tube_ring(points, radii, s0)
		var b := _tube_ring(points, radii, s1)
		for k in 9:
			var angle0 := TAU * k / 9.0
			var angle1 := TAU * (k + 1) / 9.0
			var p0: Vector3 = a[0] + a[1] * cos(angle0) * a[3] + a[2] * sin(angle0) * a[3]
			var p1: Vector3 = a[0] + a[1] * cos(angle1) * a[3] + a[2] * sin(angle1) * a[3]
			var q0: Vector3 = b[0] + b[1] * cos(angle0) * b[3] + b[2] * sin(angle0) * b[3]
			var q1: Vector3 = b[0] + b[1] * cos(angle1) * b[3] + b[2] * sin(angle1) * b[3]
			var tint := BARK.lerp(BARK_LIGHT, 0.34 + 0.30 * sin(k * 2.4 + s0 * 8.0))
			for p in [p0, q0, p1, p1, q0, q1]:
				st.set_color(tint)
				st.add_vertex(p)
	st.generate_normals()
	var node := MeshInstance3D.new()
	node.mesh = st.commit()
	node.material_override = mat
	add_child(node)

static func _tube_ring(points: Array[Vector3], radii: Array[float], t: float) -> Array:
	var part := minf(t * (points.size() - 1), points.size() - 1.001)
	var i := floori(part)
	var u := part - i
	var center: Vector3 = points[i].cubic_interpolate(points[i + 1], points[maxi(i - 1, 0)], points[mini(i + 2, points.size() - 1)], u)
	var ahead_t := minf(t + 0.012, 1.0)
	var behind_t := maxf(t - 0.012, 0.0)
	var ahead := _curve_point(points, ahead_t)
	var behind := _curve_point(points, behind_t)
	var tangent := (ahead - behind).normalized()
	var across := tangent.cross(Vector3.FORWARD).normalized()
	if across.length_squared() < 0.01:
		across = tangent.cross(Vector3.RIGHT).normalized()
	var depth := tangent.cross(across).normalized()
	var twist := Basis(tangent, t * 1.7)
	var radius := lerpf(radii[i], radii[i + 1], u)
	return [center, twist * across, twist * depth, radius]

static func _curve_point(points: Array[Vector3], t: float) -> Vector3:
	var part := minf(t * (points.size() - 1), points.size() - 1.001)
	var i := floori(part)
	return points[i].cubic_interpolate(points[i + 1], points[maxi(i - 1, 0)], points[mini(i + 2, points.size() - 1)], part - i)

static func _foliage_mesh(width: float, depth: float, seed: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for lobe in 5:
		var a := TAU * (lobe + 0.16 * sin(lobe * 3.7 + seed)) / 5.0 + seed * 0.7
		var distance := 0.22 + 0.18 * absf(sin(lobe * 2.13 + seed * 1.7))
		var offset := Vector3(cos(a) * width * distance, 0.14 * sin(lobe * 2.7 + seed), sin(a) * depth * distance)
		_append_crown_lobe(st, offset, width * (0.51 + 0.20 * absf(sin(lobe * 1.9 + seed))), depth * (0.54 + 0.17 * absf(cos(lobe * 2.2 + seed))), seed * 7 + lobe)
	st.generate_normals()
	return st.commit()

static func _append_crown_lobe(st: SurfaceTool, offset: Vector3, width: float, depth: float, seed: int) -> void:
	const SIDES := 18
	var levels := [-0.29, -0.19, -0.04, 0.12, 0.27, 0.34]
	var sizes := [0.15, 0.68, 1.0, 0.96, 0.69, 0.12]
	var colors := [Color(0.23, 0.30, 0.27), Color(0.32, 0.40, 0.35), Color(0.40, 0.49, 0.43), Color(0.49, 0.57, 0.50), Color(0.55, 0.61, 0.54), Color(0.54, 0.60, 0.53)]
	for j in levels.size() - 1:
		for i in SIDES:
			var p00 := offset + _crown_point(i, j, seed, width, depth, levels, sizes)
			var p01 := offset + _crown_point(i + 1, j, seed, width, depth, levels, sizes)
			var p10 := offset + _crown_point(i, j + 1, seed, width, depth, levels, sizes)
			var p11 := offset + _crown_point(i + 1, j + 1, seed, width, depth, levels, sizes)
			for p in [p00, p10, p01, p01, p10, p11]:
				var col: Color = colors[j + 1] if p.y - offset.y > (levels[j] + levels[j + 1]) * 0.5 else colors[j]
				col = col.lightened(0.035 * sin(i * 2.7 + seed))
				st.set_color(col)
				st.add_vertex(p)
	# Close the small top and bottom rings; an open ring reads as a dark pinhole at
	# the normal game zoom, especially on the highest crown.
	for i in SIDES:
		st.set_color(colors[5])
		for p in [offset + _crown_point(i, 5, seed, width, depth, levels, sizes), offset + Vector3(0, levels[5] + 0.015, 0), offset + _crown_point(i + 1, 5, seed, width, depth, levels, sizes)]:
			st.add_vertex(p)
		st.set_color(colors[0])
		for p in [offset + _crown_point(i + 1, 0, seed, width, depth, levels, sizes), offset + Vector3(0, levels[0] - 0.015, 0), offset + _crown_point(i, 0, seed, width, depth, levels, sizes)]:
			st.add_vertex(p)
	# Broad, pointed shoots break the cushion edge into foliage silhouettes.
	for i in 9:
		var angle := TAU * (i + 0.15 * sin(i * 2.4 + seed)) / 9.0
		var direction := Vector3(cos(angle), 0, sin(angle))
		var sideways := Vector3(-direction.z, 0, direction.x)
		var r := width * (0.72 + 0.13 * sin(angle * 5.0 + seed))
		var root := offset + Vector3(direction.x * r, 0.11, direction.z * depth * 0.73)
		var tip := root + direction * (0.22 + 0.08 * sin(i * 2.7 + seed)) + Vector3(0, 0.04 * sin(i + seed), 0)
		var shoulder := root + direction * 0.10 + Vector3(0, 0.055, 0)
		st.set_color(colors[4].lightened(0.02 * sin(i + seed)))
		for p in [root, shoulder + sideways * 0.095, tip, root, tip, shoulder - sideways * 0.095]:
			st.add_vertex(p)

static func _crown_point(i: int, level: int, seed: int, width: float, depth: float, heights: Array, sizes: Array) -> Vector3:
	var a := TAU * (i % 18) / 18.0
	var scallop := 1.0 + 0.13 * sin(a * 5.0 + seed * 1.7) + 0.09 * sin(a * 9.0 - seed * 2.1)
	var drift := Vector2(0.10 * sin(seed * 2.0 + level), 0.08 * cos(seed + level))
	return Vector3(cos(a) * width * sizes[level] * scallop + drift.x, heights[level] + 0.045 * sin(a * 7.0 + seed), sin(a) * depth * sizes[level] * scallop + drift.y)
