class_name ScatterLayer
extends Node3D

# Procedural set dressing. Deterministic (fixed seed) so every peer builds the same.
#   Inside (+z):  the city — houses along a paved street from the gate and one cross
#                 street, a well where they meet. Only houses have collision.
#   Outside (-z): a dirt track from the gate, olive groves on stone terraces, rock
#                 outcrops, and the enemy camp to the north (Neh. 4:8, 4:11).
#                 Visual only — nothing outside changes enemy navigation.
# Everything avoids the central action zone (wall line + supply yard).

const HALF_X := 47.0
const HALF_Z := 37.0

# Rects in (x,z) that stay clear of scatter
const AVOID := [
	Rect2(-23.0, -7.0, 46.0, 20.0),  # wall row + supply yard
	Rect2(-50.0, -2.0, 100.0, 4.0),  # outer wall stretches
]
# Where enemies walk in from the spawn line (z = -14) to the wall — keep sightlines open
const APPROACH := Rect2(-26.0, -24.0, 52.0, 22.0)
const CITY := Rect2(-44.0, 14.0, 88.0, 22.0)

# Streets — the main street runs south from the gate opening (x = -4)
const GATE_X      := -4.0
const MAIN_HALF_W := 2.5
const CROSS_Z     := Vector2(22.0, 25.5)            # cross street z-range
const WELL_POS    := Vector3(1.6, 0.0, 23.75)

const ROCK_COLOR   := Color(0.62, 0.58, 0.50)
const BUSH_COLOR   := Color(0.36, 0.42, 0.22)
const OLIVE_LEAF   := Color(0.38, 0.44, 0.28)
const OLIVE_TRUNK  := Color(0.36, 0.30, 0.24)
const STONE_COLOR  := Palette.LIMESTONE
# Palette.gd holds the shared world colours — plaster, dyes, doors
const HOUSE_COLORS := Palette.PLASTER
const DOOR_COLORS  := Palette.DOORS
# Rugs and cloth drying on the flat roofs — the colour you see from above
const CLOTH_COLORS := Palette.DYES
const PAVING_COLOR := Palette.PAVING
const TENT_COLOR   := Color(0.20, 0.15, 0.12)   # black goat-hair
const CLAY_COLOR   := Color(0.60, 0.38, 0.24)
const OPENING      := Color(0.18, 0.13, 0.09)
const AWNINGS      := [Palette.MADDER, Palette.SAFFRON, Palette.INDIGO, Palette.WELD, Palette.UNDYED]

var _rng := RandomNumberGenerator.new()
# Instances collected by kind, flushed into one MultiMesh each at the end
var _batches := {}

func _ready() -> void:
	_rng.seed = 42
	_build_pebbles()
	_build_rubble()
	_build_bushes()
	_build_groves()
	_build_outcrops()
	_build_camp()
	_build_streets()
	_build_city()
	_flush()

# ── Ground cover ──────────────────────────────────────────────

func _build_pebbles() -> void:
	for p in _free_points(380, false, false):
		var s := Vector3(_rng.randf_range(0.6, 1.8), _rng.randf_range(0.4, 1.0), _rng.randf_range(0.6, 1.8))
		_add("pebble", Transform3D(_yaw().scaled(s), Vector3(p.x, 0.04, p.y)), _vary(ROCK_COLOR, 0.06))

# Tumbled blocks either side of the wall line — the old wall "broken down" (Neh. 2:13)
func _build_rubble() -> void:
	for i in 70:
		var x := _rng.randf_range(-22.0, 22.0)
		var side := -1.0 if _rng.randf() < 0.7 else 1.0
		var z := side * _rng.randf_range(0.9, 3.2)
		var s := Vector3(_rng.randf_range(0.35, 0.7), _rng.randf_range(0.3, 0.5), _rng.randf_range(0.3, 0.5))
		var tilt := Basis.from_euler(Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf() * TAU, _rng.randf_range(-0.3, 0.3)))
		_add("block", Transform3D(tilt.scaled(s), Vector3(x, s.y * 0.4, z)), _vary(STONE_COLOR, 0.07))

func _build_bushes() -> void:
	# Each bush = 3 overlapping blobs so the silhouette isn't a single ball
	for p in _free_points(46, true, false):
		_bush(Vector3(p.x, 0.0, p.y))

func _bush(at: Vector3) -> void:
	var base := _vary(BUSH_COLOR, 0.05)
	for i in 3:
		var off := Vector3(_rng.randf_range(-0.35, 0.35), 0.2, _rng.randf_range(-0.35, 0.35))
		var s := Vector3.ONE * _rng.randf_range(0.6, 1.1)
		_add("bush", Transform3D(_yaw().scaled(s), at + off), base.lightened(0.06 * i))

# ── Outside ───────────────────────────────────────────────────

# Olive groves in rows on low dry-stone terraces
func _build_groves() -> void:
	for g: Vector3 in [Vector3(-34, 0, -20), Vector3(30, 0, -28), Vector3(38, 0, -10), Vector3(-36, 0, -33)]:
		var rows := _rng.randi_range(2, 3)
		var cols := _rng.randi_range(3, 4)
		for r in rows:
			var rz := g.z + r * 4.5
			# Terrace wall along the downhill (city-facing) side of each row
			var tx := g.x - 2.5
			while tx < g.x + cols * 4.0 - 1.5:
				var s := Vector3(_rng.randf_range(0.7, 1.1), _rng.randf_range(0.35, 0.5), 0.5)
				_add("block", Transform3D(_yaw_small() * Basis.from_scale(s), Vector3(tx, s.y * 0.5, rz + 2.0)), _vary(STONE_COLOR, 0.08).darkened(0.08))
				tx += s.x * 0.95
			for c in cols:
				if _rng.randf() < 0.15:
					continue
				_olive(Vector3(g.x + c * 4.0 + _rng.randf_range(-0.6, 0.6), 0.0, rz + _rng.randf_range(-0.5, 0.5)))

func _olive(at: Vector3) -> void:
	var h := _rng.randf_range(1.2, 1.8)
	var lean := Basis.from_euler(Vector3(_rng.randf_range(-0.2, 0.2), 0, _rng.randf_range(-0.2, 0.2)))
	_add("trunk", Transform3D(lean.scaled(Vector3(1, h, 1)), at + Vector3(0, h * 0.5, 0)), _vary(OLIVE_TRUNK, 0.04))
	var top := at + lean * Vector3(0, h * 0.5, 0) + Vector3(0, h * 0.5, 0)
	for i in 5:
		var off := Vector3(_rng.randf_range(-0.9, 0.9), _rng.randf_range(0.0, 0.7), _rng.randf_range(-0.9, 0.9))
		var s := Vector3(_rng.randf_range(0.9, 1.4), _rng.randf_range(0.6, 0.9), _rng.randf_range(0.9, 1.4))
		_add("leaf", Transform3D(_yaw().scaled(s), top + off + Vector3(0, 0.5, 0)), _vary(OLIVE_LEAF, 0.05))

# Limestone breaking through the soil, well clear of the enemy approach
func _build_outcrops() -> void:
	for c: Vector3 in [Vector3(-44, 0, -6), Vector3(28, 0, -40), Vector3(44, 0, -24), Vector3(-18, 0, -38), Vector3(12, 0, -34)]:
		for i in _rng.randi_range(3, 6):
			var s := Vector3(_rng.randf_range(0.9, 2.2), _rng.randf_range(0.5, 1.4), _rng.randf_range(0.9, 2.0))
			var at := c + Vector3(_rng.randf_range(-2.5, 2.5), s.y * 0.3, _rng.randf_range(-2.0, 2.0))
			_add("boulder", Transform3D(_yaw().scaled(s), at), _vary(ROCK_COLOR, 0.05).lightened(0.05))
		_bush(c + Vector3(_rng.randf_range(-3, 3), 0, 2.5))

# Sanballat's men camped beyond the ridge (Neh. 4:8, 4:11) — dark tents and a fire ring
func _build_camp() -> void:
	var centre := Vector3(-12.0, 0.0, -41.0)
	for i in 6:
		var a := i * TAU / 6.0 + _rng.randf_range(-0.2, 0.2)
		var at := centre + Vector3(cos(a) * 6.5, 0.0, sin(a) * 3.5)
		var s := Vector3(_rng.randf_range(2.6, 3.6), _rng.randf_range(1.3, 1.7), _rng.randf_range(2.2, 3.0))
		_add("tent", Transform3D(Basis(Vector3.UP, a + PI / 2.0) * Basis.from_scale(s), at + Vector3(0, s.y * 0.5, 0)), _vary(TENT_COLOR, 0.03))
	for i in 9:
		var a := i * TAU / 9.0
		_add("block", Transform3D(_yaw().scaled(Vector3(0.35, 0.25, 0.3)), centre + Vector3(cos(a) * 0.9, 0.1, sin(a) * 0.9)), _vary(ROCK_COLOR, 0.05).darkened(0.2))
	_add("patch", Transform3D(Basis.from_scale(Vector3(0.7, 1.0, 0.7)), centre + Vector3(0, 0.11, 0)), Color(0.12, 0.09, 0.07))

# ── City ──────────────────────────────────────────────────────

func _on_street(p: Vector2, margin := 0.0) -> bool:
	return absf(p.x - GATE_X) < MAIN_HALF_W + margin \
		or (p.y > CROSS_Z.x - margin and p.y < CROSS_Z.y + margin)

# Irregular limestone slabs along both streets
func _build_streets() -> void:
	var z := CITY.position.y - 1.0
	while z < CITY.end.y + 2.0:
		var x := -HALF_X
		while x < HALF_X:
			var p := Vector2(x, z)
			if _on_street(p) and z >= CITY.position.y - 1.0:
				var s := Vector3(_rng.randf_range(0.7, 1.05), 0.05, _rng.randf_range(0.6, 0.95))
				var at := Vector3(x + _rng.randf_range(-0.08, 0.08), 0.105, z + _rng.randf_range(-0.08, 0.08))
				_add("slab", Transform3D(_yaw_small() * Basis.from_scale(s), at), _vary(PAVING_COLOR, 0.04))
			x += 1.1
		z += 1.0
	# Well at the crossing: stone drum, dark water, and a trough
	var well := Transform3D(Basis.from_scale(Vector3(1.6, 0.8, 1.6)), WELL_POS + Vector3(0, 0.4, 0))
	_add("drum", well, _vary(STONE_COLOR, 0.03))
	_add("drum", Transform3D(Basis.from_scale(Vector3(1.2, 0.05, 1.2)), WELL_POS + Vector3(0, 0.81, 0)), Color(0.10, 0.12, 0.13))
	_add("block", Transform3D(Basis.from_scale(Vector3(1.6, 0.35, 0.5)), WELL_POS + Vector3(1.6, 0.18, 0.4)), _vary(STONE_COLOR, 0.03))

func _build_city() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	# Street-front rows: (x range, row z, door faces north?) — south-side rows face the street
	var rows := [
		[Vector2(-44.0, GATE_X - MAIN_HALF_W - 0.6), CROSS_Z.x - 0.8, false],   # west, north of cross street
		[Vector2(GATE_X + MAIN_HALF_W + 0.6, 44.0), CROSS_Z.x - 0.8, false],    # east, north of cross street
		[Vector2(-44.0, GATE_X - MAIN_HALF_W - 0.6), CROSS_Z.y + 0.8, true],    # west, south of cross street
		[Vector2(GATE_X + MAIN_HALF_W + 0.6, 44.0), CROSS_Z.y + 0.8, true],     # east, south of cross street
		[Vector2(-40.0, 40.0), 32.5, true],                                     # back lane, sparse
	]
	for row in rows:
		var span: Vector2 = row[0]
		var edge_z: float = row[1]
		var faces_north: bool = row[2]
		var sparse := edge_z > 30.0
		var x := span.x + _rng.randf_range(0.0, 1.5)
		while x < span.y - 3.0:
			var w := _rng.randf_range(3.2, 5.5)
			if x + w > span.y:
				break
			if absf(x + w * 0.5 - GATE_X) < MAIN_HALF_W + w * 0.5 + 0.4:   # keep the main street open
				x = GATE_X + MAIN_HALF_W + 0.6
				continue
			# Gaps between houses: lanes, yards, the odd courtyard tree
			if _rng.randf() < (0.45 if sparse else 0.25):
				if _rng.randf() < 0.5:
					var yard_z := edge_z + (2.5 if faces_north else -2.5)
					if _rng.randf() < 0.5:
						_olive(Vector3(x + w * 0.5, 0.0, yard_z))
					else:
						_bush(Vector3(x + w * 0.5, 0.0, yard_z))
				x += w + _rng.randf_range(0.8, 1.6)
				continue
			var d := _rng.randf_range(3.0, 4.2)
			var cz := edge_z + (d * 0.5 if faces_north else -d * 0.5)
			_house(body, Vector3(x + w * 0.5, 0.0, cz), w, d, faces_north)
			x += w + _rng.randf_range(0.3, 1.4)

func _house(body: StaticBody3D, c: Vector3, w: float, d: float, faces_north: bool) -> void:
	var h := _rng.randf_range(2.2, 3.2)
	var tint := _vary(HOUSE_COLORS[_rng.randi() % HOUSE_COLORS.size()], 0.02)
	_add("block", Transform3D(Basis.from_scale(Vector3(w, h, d)), c + Vector3(0, h * 0.5, 0)), tint)
	# Parapet lip on the flat roof (Deut. 22:8)
	_add("block", Transform3D(Basis.from_scale(Vector3(w + 0.15, 0.25, d + 0.15)), c + Vector3(0, h + 0.1, 0)), tint.darkened(0.06))
	var top := h
	# Upper room on part of the roof
	if _rng.randf() < 0.3:
		var uw := w * _rng.randf_range(0.4, 0.55)
		var ud := d * 0.6
		var uh := _rng.randf_range(1.6, 2.0)
		var ux := (w - uw) * 0.5 * (1.0 if _rng.randf() < 0.5 else -1.0)
		_add("block", Transform3D(Basis.from_scale(Vector3(uw, uh, ud)), c + Vector3(ux, h + uh * 0.5, 0)), tint.lightened(0.03))
		_add("opening", Transform3D(Basis.from_scale(Vector3(0.06, 0.4, 0.4)), c + Vector3(ux + uw * 0.5 + 0.02, h + uh * 0.6, 0)), OPENING)
		top = h + uh
	# Door on the street face; north faces are the ones the camera sees
	var face := -1.0 if faces_north else 1.0
	var door_x := _rng.randf_range(-w * 0.25, w * 0.25)
	_add("opening", Transform3D(Basis.from_scale(Vector3(0.8, 1.4, 0.06)), c + Vector3(door_x, 0.7, face * (d * 0.5 + 0.02))),
		DOOR_COLORS[_rng.randi() % DOOR_COLORS.size()])
	_add("opening", Transform3D(Basis.from_scale(Vector3(0.06, 0.45, 0.45)), c + Vector3(w * 0.5 + 0.02, h * 0.62, _rng.randf_range(-d * 0.2, d * 0.2))), OPENING)
	# Rug or cloth laid out on the roof to dry
	if _rng.randf() < 0.45:
		var rw := minf(w * 0.5, _rng.randf_range(1.2, 2.0))
		var rd := minf(d * 0.5, _rng.randf_range(0.9, 1.5))
		var rug := c + Vector3(_rng.randf_range(-w * 0.2, w * 0.2), h + 0.24, _rng.randf_range(-d * 0.15, d * 0.15))
		_add("block", Transform3D(_yaw_small() * Basis.from_scale(Vector3(rw, 0.04, rd)), rug),
			CLOTH_COLORS[_rng.randi() % CLOTH_COLORS.size()])
	# Cloth awning over the door
	if _rng.randf() < 0.55:
		var awn := Transform3D(Basis(Vector3.RIGHT, face * 0.25) * Basis.from_scale(Vector3(1.6, 0.05, 1.1)),
			c + Vector3(door_x, 1.75, face * (d * 0.5 + 0.5)))
		_add("block", awn, AWNINGS[_rng.randi() % AWNINGS.size()])
	# Water jars by the door
	if _rng.randf() < 0.4:
		for i in _rng.randi_range(1, 3):
			var jar := c + Vector3(door_x + 0.7 + i * 0.4, 0.3, face * (d * 0.5 + 0.35))
			_add("jar", Transform3D(Basis.from_scale(Vector3.ONE * _rng.randf_range(0.8, 1.1)), jar), _vary(CLAY_COLOR, 0.05))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, top, d)
	shape.shape = box
	shape.position = c + Vector3(0, top * 0.5, 0)
	body.add_child(shape)

# ── Batching ──────────────────────────────────────────────────

func _add(kind: String, xf: Transform3D, color: Color) -> void:
	if not _batches.has(kind):
		_batches[kind] = [[] as Array[Transform3D], [] as Array[Color]]
	_batches[kind][0].append(xf)
	_batches[kind][1].append(color)

func _flush() -> void:
	for kind: String in _batches:
		var mmi := _multimesh(_mesh_for(kind), _batches[kind][0], _batches[kind][1])
		# Ground-hugging bits: shadows cost more than they add
		if kind in ["pebble", "patch", "slab"]:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_batches.clear()

func _mesh_for(kind: String) -> Mesh:
	match kind:
		"pebble":  return _sphere(0.13, 0.10, 5, 2)
		"bush":    return _sphere(0.42, 0.62, 7, 4)
		"leaf":    return _sphere(0.6, 1.0, 8, 5)
		"boulder": return _sphere(0.6, 0.9, 6, 3)
		"jar":     return _sphere(0.22, 0.5, 8, 4)
		"trunk":   return _cylinder(0.12, 0.2, 1.0, 7)
		"drum":    return _cylinder(0.5, 0.5, 1.0, 12)
		"patch":   return _cylinder(0.5, 0.5, 0.02, 10)
		"tent":
			var m := PrismMesh.new()
			m.size = Vector3.ONE
			return m
	return BoxMesh.new()   # block, slab, opening

# ── Helpers ───────────────────────────────────────────────────

# Random (x,z) points outside AVOID (optionally also outside the city / enemy approach)
func _free_points(count: int, avoid_city: bool, avoid_approach: bool) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	var tries := 0
	while pts.size() < count and tries < count * 10:
		tries += 1
		var p := Vector2(_rng.randf_range(-HALF_X, HALF_X), _rng.randf_range(-HALF_Z, HALF_Z))
		if _blocked(p) or (avoid_city and CITY.grow(1.5).has_point(p)) \
				or (avoid_approach and APPROACH.has_point(p)):
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

func _yaw_small() -> Basis:
	return Basis.from_euler(Vector3(0.0, _rng.randf_range(-0.12, 0.12), 0.0))

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

func _cylinder(top: float, bottom: float, height: float, segments: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = segments
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
	mat.vertex_color_is_srgb = true   # palette constants are authored in sRGB
	mat.roughness = 1.0
	mat.metallic_specular = 0.1
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)
	return mmi
