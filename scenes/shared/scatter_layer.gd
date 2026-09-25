extends Node3D

# Procedural set dressing: rocks, bushes, olive trees, rubble from the broken wall,
# and flat-roofed houses of the inner city (south of the wall, +z).
# Everything avoids the central action zone (wall line + supply piles).

const HALF_X := 47.0
const HALF_Z := 37.0

# Rects in (x,z) that stay clear of scatter
const AVOID := [
	Rect2(-23.0, -7.0, 46.0, 20.0),  # wall row + supply zone
	Rect2(-50.0, -2.0, 100.0, 4.0),  # outer wall stretches
]
const CITY := Rect2(-44.0, 16.0, 88.0, 20.0)   # houses go here
const CITY_ROAD_HALF := 3.5                     # keep a street open south of the gate

const ROCK_COLOR   := Color(0.62, 0.58, 0.50)
const BUSH_COLOR   := Color(0.36, 0.42, 0.22)
const OLIVE_LEAF   := Color(0.38, 0.44, 0.28)
const OLIVE_TRUNK  := Color(0.36, 0.30, 0.24)
const STONE_COLOR  := Color(0.70, 0.61, 0.46)
const HOUSE_COLOR  := Color(0.76, 0.67, 0.52)
const OPENING      := Color(0.18, 0.13, 0.09)

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 42
	_build_rocks()
	_build_bushes()
	_build_olive_trees()
	_build_rubble()
	_build_city()

# ── Ground cover ──────────────────────────────────────────────

func _build_rocks() -> void:
	var xf: Array[Transform3D] = []
	var col: Array[Color] = []
	for p in _free_points(420, false):
		var s := Vector3(_rng.randf_range(0.6, 1.8), _rng.randf_range(0.4, 1.0), _rng.randf_range(0.6, 1.8))
		xf.append(Transform3D(_yaw().scaled(s), Vector3(p.x, 0.04, p.y)))
		col.append(_vary(ROCK_COLOR, 0.06))
	# Pebbles: shadows cost more than they add at this size
	_multimesh(_sphere(0.13, 0.10, 5, 2), xf, col).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_bushes() -> void:
	# Each bush = 3 overlapping blobs so the silhouette isn't a single ball
	var xf: Array[Transform3D] = []
	var col: Array[Color] = []
	for p in _free_points(70, true):
		var base := _vary(BUSH_COLOR, 0.05)
		for i in 3:
			var off := Vector3(_rng.randf_range(-0.35, 0.35), 0.0, _rng.randf_range(-0.35, 0.35))
			var s := Vector3.ONE * _rng.randf_range(0.6, 1.1)
			xf.append(Transform3D(_yaw().scaled(s), Vector3(p.x, 0.2, p.y) + off))
			col.append(base.lightened(0.06 * i))
	_multimesh(_sphere(0.42, 0.62, 7, 4), xf, col)

func _build_olive_trees() -> void:
	var trunks: Array[Transform3D] = []
	var trunk_col: Array[Color] = []
	var leaves: Array[Transform3D] = []
	var leaf_col: Array[Color] = []
	for p in _free_points(26, true):
		var h := _rng.randf_range(1.2, 1.8)
		var lean := Basis.from_euler(Vector3(_rng.randf_range(-0.2, 0.2), 0, _rng.randf_range(-0.2, 0.2)))
		trunks.append(Transform3D(lean.scaled(Vector3(1, h, 1)), Vector3(p.x, h * 0.5, p.y)))
		trunk_col.append(_vary(OLIVE_TRUNK, 0.04))
		var top := Vector3(p.x, h, p.y) + lean * Vector3(0, h * 0.5, 0) - Vector3(0, h * 0.5, 0)
		for i in 5:
			var off := Vector3(_rng.randf_range(-0.9, 0.9), _rng.randf_range(0.0, 0.7), _rng.randf_range(-0.9, 0.9))
			var s := Vector3(_rng.randf_range(0.9, 1.4), _rng.randf_range(0.6, 0.9), _rng.randf_range(0.9, 1.4))
			leaves.append(Transform3D(_yaw().scaled(s), top + off + Vector3(0, 0.5, 0)))
			leaf_col.append(_vary(OLIVE_LEAF, 0.05))
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.12
	trunk.bottom_radius = 0.2
	trunk.height = 1.0
	trunk.radial_segments = 7
	_multimesh(trunk, trunks, trunk_col)
	_multimesh(_sphere(0.6, 1.0, 8, 5), leaves, leaf_col)

# Tumbled blocks either side of the wall line — the old wall "broken down" (Neh. 2:13)
func _build_rubble() -> void:
	var xf: Array[Transform3D] = []
	var col: Array[Color] = []
	for i in 70:
		var x := _rng.randf_range(-22.0, 22.0)
		var side := -1.0 if _rng.randf() < 0.7 else 1.0
		var z := side * _rng.randf_range(0.9, 3.2)
		var s := Vector3(_rng.randf_range(0.35, 0.7), _rng.randf_range(0.3, 0.5), _rng.randf_range(0.3, 0.5))
		var tilt := Basis.from_euler(Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf() * TAU, _rng.randf_range(-0.3, 0.3)))
		xf.append(Transform3D(tilt.scaled(s), Vector3(x, s.y * 0.4, z)))
		col.append(_vary(STONE_COLOR, 0.07))
	_multimesh(BoxMesh.new(), xf, col)

# ── City ──────────────────────────────────────────────────────

func _build_city() -> void:
	var bodies: Array[Transform3D] = []
	var body_col: Array[Color] = []
	var parapets: Array[Transform3D] = []
	var parapet_col: Array[Color] = []
	var openings: Array[Transform3D] = []
	var open_col: Array[Color] = []
	var body := StaticBody3D.new()
	add_child(body)

	var x := CITY.position.x
	while x < CITY.end.x:
		var w := _rng.randf_range(3.0, 5.0)
		var z := CITY.position.y + _rng.randf_range(0.0, 2.0)
		if absf(x + w * 0.5) < CITY_ROAD_HALF + w * 0.5:
			x += w + 0.8
			continue
		while z < CITY.end.y:
			var d := _rng.randf_range(3.0, 4.5)
			var h := _rng.randf_range(2.2, 3.6)
			var c := Vector3(x + w * 0.5, 0.0, z + d * 0.5)
			var tint := _vary(HOUSE_COLOR, 0.05)
			bodies.append(Transform3D(Basis.from_scale(Vector3(w, h, d)), c + Vector3(0, h * 0.5, 0)))
			body_col.append(tint)
			# Parapet lip on the flat roof (Deut. 22:8)
			parapets.append(Transform3D(Basis.from_scale(Vector3(w + 0.15, 0.25, d + 0.15)), c + Vector3(0, h + 0.1, 0)))
			parapet_col.append(tint.darkened(0.06))
			# Door on the north face (toward the wall / camera side)
			openings.append(Transform3D(Basis.from_scale(Vector3(0.8, 1.4, 0.06)),
				c + Vector3(_rng.randf_range(-w * 0.25, w * 0.25), 0.7, -d * 0.5 - 0.02)))
			open_col.append(OPENING)
			# Small window on the east face
			openings.append(Transform3D(Basis.from_scale(Vector3(0.06, 0.45, 0.45)),
				c + Vector3(w * 0.5 + 0.02, h * 0.62, _rng.randf_range(-d * 0.2, d * 0.2))))
			open_col.append(OPENING)
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(w, h, d)
			shape.shape = box
			shape.position = c + Vector3(0, h * 0.5, 0)
			body.add_child(shape)
			z += d + _rng.randf_range(1.2, 2.5)
		x += w + _rng.randf_range(1.5, 2.5)

	_multimesh(BoxMesh.new(), bodies, body_col)
	_multimesh(BoxMesh.new(), parapets, parapet_col)
	_multimesh(BoxMesh.new(), openings, open_col)

# ── Helpers ───────────────────────────────────────────────────

# Random (x,z) points outside AVOID (and outside the city when requested)
func _free_points(count: int, avoid_city: bool) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	var tries := 0
	while pts.size() < count and tries < count * 10:
		tries += 1
		var p := Vector2(_rng.randf_range(-HALF_X, HALF_X), _rng.randf_range(-HALF_Z, HALF_Z))
		if _blocked(p) or (avoid_city and CITY.grow(1.5).has_point(p)):
			continue
		pts.append(p)
	return pts

func _blocked(p: Vector2) -> bool:
	for r: Rect2 in AVOID:
		if r.has_point(p):
			return true
	return false

func _yaw() -> Basis:
	return Basis.from_euler(Vector3(0.0, _rng.randf() * TAU, 0.0))

func _vary(c: Color, amount: float) -> Color:
	var v := _rng.randf_range(-amount, amount)
	return Color(c.r + v, c.g + v, c.b + v * 0.8)

func _sphere(radius: float, height: float, segments: int, rings: int) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = segments
	m.rings = rings
	return m

func _multimesh(mesh: Mesh, xf: Array[Transform3D], colors: Array[Color]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, colors[i])
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.metallic_specular = 0.1
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)
	return mmi
