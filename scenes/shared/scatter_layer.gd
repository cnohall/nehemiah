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

const ROCK_COLOR   := Color(0.66, 0.63, 0.57)
const BUSH_COLOR   := Color(0.40, 0.50, 0.22)
const TUFT_COLOR   := Color(0.46, 0.62, 0.22)
const OLIVE_LEAF   := Palette.LEAF
const OLIVE_TRUNK  := Color(0.42, 0.30, 0.20)
const STONE_COLOR  := Palette.LIMESTONE
# Palette.gd holds the shared world colours — plaster, dyes, doors
const HOUSE_COLORS := Palette.PLASTER
const DOOR_COLORS  := Palette.DOORS
# Rugs and cloth drying on the flat roofs — the colour you see from above
const CLOTH_COLORS := Palette.DYES
const PAVING_COLOR := Palette.PAVING
const WATER_COLOR  := Color(0.24, 0.52, 0.72)
const GROUT        := Color(0.64, 0.54, 0.41)
const TENT_COLOR   := Color(0.20, 0.15, 0.12)   # black goat-hair
const CLAY_COLOR   := Color(0.60, 0.38, 0.24)
const OPENING      := Color(0.18, 0.13, 0.09)
const FOOTING      := Color(0.70, 0.66, 0.58)   # rough limestone course at the foot of a house
const BEAM_COLOR   := Color(0.42, 0.28, 0.16)
const AWNINGS      := [Palette.INDIGO, Palette.MADDER, Palette.INDIGO, Palette.SAFFRON, Palette.UNDYED]

var _rng := RandomNumberGenerator.new()
# Instances collected by kind, flushed into one MultiMesh each at the end
var _batches := {}

func _ready() -> void:
	_rng.seed = 42
	_build_pebbles()
	_build_rubble()
	_build_bushes()
	_build_tufts()
	_build_grit()
	_build_groves()
	_build_outcrops()
	_build_camp()
	_build_streets()
	_build_city()
	_build_work_camp()
	# Added later: kept after everything seeded above so the city layout doesn't shift
	_build_stone_clusters()
	_build_tuft_pairs()
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

# Tufts of dry grass: a few blades fanned out, tips lighter
func _build_tufts() -> void:
	for p in _free_points(260, true, false):
		_tuft(Vector3(p.x, 0.1, p.y))
	# A scatter along the wall foot and round the yard, where feet don't reach
	for i in 70:
		var at := Vector3(_rng.randf_range(-22.0, 22.0), 0.1, _rng.randf_range(-6.0, -1.6) if _rng.randf() < 0.6 else _rng.randf_range(1.6, 3.0))
		_tuft(at)

# Grass grows in little colonies: pairs and threes rather than lone tufts
func _build_tuft_pairs() -> void:
	for p in _free_points(200, true, false):
		for j in _rng.randi_range(2, 3):
			_tuft(Vector3(p.x + _rng.randf_range(-0.55, 0.55), 0.1, p.y + _rng.randf_range(-0.55, 0.55)))

func _tuft(at: Vector3) -> void:
	var base := _vary(TUFT_COLOR, 0.05)
	var n := _rng.randi_range(7, 11)
	for i in n:
		var a := TAU * i / n + _rng.randf_range(-0.3, 0.3)
		var lean := _rng.randf_range(0.15, 0.6)
		var h := _rng.randf_range(0.28, 0.6)
		var b := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, lean) * Basis.from_scale(Vector3(1, h, 1))
		_add("blade", Transform3D(b, at + Basis(Vector3.UP, a) * Vector3(0, 0, 0.04) + Vector3(0, h * 0.4, 0)), base.lightened(_rng.randf_range(0.0, 0.12)))

# Grit on the work yard: small stones kicked about
func _build_grit() -> void:
	for i in 90:
		var p := Vector2(_rng.randf_range(-20.0, 20.0), _rng.randf_range(-6.0, 13.0))
		if absf(p.y) < 1.4:
			continue
		var s := Vector3(_rng.randf_range(0.7, 1.6), _rng.randf_range(0.5, 1.1), _rng.randf_range(0.7, 1.6))
		_add("pebble", Transform3D(_yaw().scaled(s), Vector3(p.x, 0.1, p.y)), _vary(ROCK_COLOR, 0.07))

# Little heaps of broken limestone, a few chunky stones each — the mockup's rubble
# texture, mostly toward the wall and around the yard
func _build_stone_clusters() -> void:
	var spots: Array[Vector2] = _free_points(140, true, false)
	for i in 110:
		spots.append(Vector2(_rng.randf_range(-24.0, 24.0), _rng.randf_range(-9.0, 12.0)))
	for p in spots:
		if absf(p.y) < 1.3 or _blocked(p):
			continue
		var base := _vary(Palette.WALL_STONE, 0.06).darkened(_rng.randf_range(0.0, 0.12))
		for j in _rng.randi_range(2, 5):
			var sz := _rng.randf_range(0.14, 0.32)
			var s := Vector3(sz * _rng.randf_range(0.9, 1.5), sz * _rng.randf_range(0.6, 1.0), sz * _rng.randf_range(0.9, 1.4))
			var off := Vector3(_rng.randf_range(-0.35, 0.35), s.y * 0.45, _rng.randf_range(-0.35, 0.35))
			var tilt := Basis.from_euler(Vector3(_rng.randf_range(-0.25, 0.25), _rng.randf() * TAU, _rng.randf_range(-0.25, 0.25)))
			_add("chip", Transform3D(tilt.scaled(s), Vector3(p.x, 0.0, p.y) + off), base.lightened(_rng.randf_range(0.0, 0.08)))

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
	_add("trunk", Transform3D(lean.scaled(Vector3(1.3, h, 1.3)), at + Vector3(0, h * 0.5, 0)), _vary(OLIVE_TRUNK, 0.04))
	var top := at + lean * Vector3(0, h * 0.5, 0) + Vector3(0, h * 0.5, 0)
	# Chunky canopy: a ring of big faceted clumps and one on top, lighter where the sun hits
	var leaf := _vary(OLIVE_LEAF, 0.04)
	for i in 4:
		var a := i * TAU / 4.0 + _rng.randf_range(-0.4, 0.4)
		var off := Vector3(cos(a) * 0.75, _rng.randf_range(0.0, 0.3), sin(a) * 0.75)
		var s := Vector3(_rng.randf_range(1.2, 1.5), _rng.randf_range(0.85, 1.05), _rng.randf_range(1.2, 1.5))
		_add("leaf", Transform3D(_yaw().scaled(s), top + off + Vector3(0, 0.45, 0)), leaf.darkened(0.06))
		# A smaller lump bulging out of each clump, so the crown reads lumpy
		_add("leaf", Transform3D(Basis.from_scale(s * 0.55), top + off * 1.45 + Vector3(0, 0.75, 0)), leaf.lightened(0.02))
	_add("leaf", Transform3D(_yaw().scaled(Vector3(1.5, 1.1, 1.5)), top + Vector3(0, 1.05, 0)), leaf.lightened(0.05))

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

# Cobbled streets: tight rows of rounded limestone setts, each a little different in
# size, height and tone; the odd one missing so the earth shows through
func _build_streets() -> void:
	const STEP := 0.52
	# Packed-earth bed the setts sit in: the joints read as grout, not bare sand
	var z0 := CITY.position.y - 1.0
	var z1 := CITY.end.y + 2.0
	_add("bed", Transform3D(Basis.from_scale(Vector3(MAIN_HALF_W * 2.0 - 1.4, 0.02, z1 - z0)), Vector3(GATE_X, 0.1, (z0 + z1) * 0.5)), GROUT)
	_add("bed", Transform3D(Basis.from_scale(Vector3(HALF_X * 2.0, 0.02, CROSS_Z.y - CROSS_Z.x - 1.3)), Vector3(0, 0.1, (CROSS_Z.x + CROSS_Z.y) * 0.5)), GROUT)
	var z := CITY.position.y - 1.0
	var row := 0
	while z < CITY.end.y + 2.0:
		var x := -HALF_X + (STEP * 0.5 if row % 2 == 1 else 0.0)
		while x < HALF_X:
			var p := Vector2(x, z)
			if _on_street(p) and _rng.randf() > 0.04:
				# Ragged street edges: fewer setts toward the kerb
				var edge := _street_edge(p)
				if edge > 0.0 or _rng.randf() < 0.5 + edge:
					var s := Vector3(_rng.randf_range(0.42, 0.62), _rng.randf_range(0.07, 0.13), _rng.randf_range(0.42, 0.56))
					var at := Vector3(x + _rng.randf_range(-0.04, 0.04), 0.1 + s.y * 0.35, z + _rng.randf_range(-0.04, 0.04))
					# Mixed limestone: mostly pale, some honey-warm, the odd grey or worn dark one
					var c := _vary(PAVING_COLOR, 0.04)
					var r := _rng.randf()
					if r < 0.25:
						c = c.lerp(Color(0.82, 0.70, 0.52), 0.5)
					elif r < 0.4:
						c = c.lerp(Color(0.66, 0.66, 0.64), 0.5)
					elif r < 0.48:
						c = c.darkened(0.14)
					_add("slab", Transform3D(Basis(Vector3.UP, _rng.randf_range(-0.25, 0.25)) * Basis.from_scale(s), at), c)
			x += STEP
		z += STEP * 0.95
		row += 1
	# Well at the crossing: stone drum, dark water, and a trough
	var well := Transform3D(Basis.from_scale(Vector3(1.6, 0.8, 1.6)), WELL_POS + Vector3(0, 0.4, 0))
	_add("drum", well, _vary(STONE_COLOR, 0.03))
	_add("drum", Transform3D(Basis.from_scale(Vector3(1.25, 0.05, 1.25)), WELL_POS + Vector3(0, 0.77, 0)), WATER_COLOR)
	_add("block", Transform3D(Basis.from_scale(Vector3(1.6, 0.35, 0.5)), WELL_POS + Vector3(1.6, 0.18, 0.4)), _vary(STONE_COLOR, 0.03))

# Distance inside the street's edge (negative within the last metre)
func _street_edge(p: Vector2) -> float:
	var main := MAIN_HALF_W - absf(p.x - GATE_X)
	var cross := minf(p.y - CROSS_Z.x, CROSS_Z.y - p.y)
	return maxf(main, cross) - 1.0

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
	_dress_walls(c, w, h, d)
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
	_door(c + Vector3(door_x, 0, face * d * 0.5), face)
	_window(c + Vector3(w * 0.5, h * 0.62, _rng.randf_range(-d * 0.2, d * 0.2)))
	# Rug or cloth laid out on the roof to dry
	if _rng.randf() < 0.45:
		var rw := minf(w * 0.5, _rng.randf_range(1.2, 2.0))
		var rd := minf(d * 0.5, _rng.randf_range(0.9, 1.5))
		var rug := c + Vector3(_rng.randf_range(-w * 0.2, w * 0.2), h + 0.24, _rng.randf_range(-d * 0.15, d * 0.15))
		_add("block", Transform3D(_yaw_small() * Basis.from_scale(Vector3(rw, 0.04, rd)), rug),
			CLOTH_COLORS[_rng.randi() % CLOTH_COLORS.size()])
	# Cloth awning over the door, on two poles
	if _rng.randf() < 0.55:
		_canopy(c + Vector3(door_x, 0, face * (d * 0.5 + 0.65)), 1.8, 1.2, face, AWNINGS[_rng.randi() % AWNINGS.size()])
	# Jars and a basket up on the roof
	if _rng.randf() < 0.45:
		for i in _rng.randi_range(1, 3):
			var jar := c + Vector3(_rng.randf_range(-w * 0.35, w * 0.35), h + 0.4, _rng.randf_range(-d * 0.3, d * 0.3))
			_add("jar", Transform3D(Basis.from_scale(Vector3.ONE * _rng.randf_range(0.8, 1.1)), jar), _vary(CLAY_COLOR, 0.05))
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

# Stone footing, and roof-beam ends showing under the parapet on the faces the camera sees
func _dress_walls(c: Vector3, w: float, h: float, d: float) -> void:
	_add("block", Transform3D(Basis.from_scale(Vector3(w + 0.1, 0.42, d + 0.1)), c + Vector3(0, 0.21, 0)), _vary(FOOTING, 0.03))
	var y := h - 0.3
	var n := maxi(2, floori(w / 0.8))
	for i in n:
		var x := -w * 0.5 + w / n * (i + 0.5)
		_add("timber", Transform3D(Basis.from_scale(Vector3(0.14, 0.14, 0.3)), c + Vector3(x, y, d * 0.5 + 0.08)), _vary(BEAM_COLOR, 0.04))
	n = maxi(2, floori(d / 0.8))
	for i in n:
		var z := -d * 0.5 + d / n * (i + 0.5)
		_add("timber", Transform3D(Basis.from_scale(Vector3(0.3, 0.14, 0.14)), c + Vector3(w * 0.5 + 0.08, y, z)), _vary(BEAM_COLOR, 0.04))

# Door in a wall face (z = face side): dark recess, painted leaf, timber lintel, stone step
func _door(at: Vector3, face: float) -> void:
	_add("opening", Transform3D(Basis.from_scale(Vector3(1.0, 1.6, 0.08)), at + Vector3(0, 0.8 + 0.2, face * 0.02)), OPENING)
	_add("opening", Transform3D(Basis.from_scale(Vector3(0.78, 1.42, 0.08)), at + Vector3(0, 0.71 + 0.2, face * 0.05)),
		DOOR_COLORS[_rng.randi() % DOOR_COLORS.size()])
	_add("timber", Transform3D(Basis.from_scale(Vector3(1.35, 0.18, 0.24)), at + Vector3(0, 1.72 + 0.2, face * 0.08)), _vary(BEAM_COLOR, 0.03))
	_add("block", Transform3D(Basis.from_scale(Vector3(1.2, 0.14, 0.45)), at + Vector3(0, 0.07, face * 0.22)), _vary(FOOTING, 0.03))

# Small window on the +x face: opening, lintel, sill
func _window(at: Vector3) -> void:
	_add("opening", Transform3D(Basis.from_scale(Vector3(0.08, 0.5, 0.5)), at + Vector3(0.02, 0, 0)), OPENING)
	_add("timber", Transform3D(Basis.from_scale(Vector3(0.16, 0.12, 0.78)), at + Vector3(0.06, 0.33, 0)), _vary(BEAM_COLOR, 0.03))
	_add("block", Transform3D(Basis.from_scale(Vector3(0.16, 0.07, 0.66)), at + Vector3(0.06, -0.3, 0)), _vary(FOOTING, 0.03))

# Cloth canopy on two front poles, sloping back toward the wall it leans on
func _canopy(at: Vector3, w: float, d: float, face: float, cloth: Color) -> void:
	for sx: float in [-1.0, 1.0]:
		_add("timber", Transform3D(Basis.from_scale(Vector3(0.1, 2.0, 0.1)), at + Vector3(sx * w * 0.45, 1.0, face * d * 0.35)), _vary(BEAM_COLOR, 0.04))
	_add("block", Transform3D(Basis(Vector3.RIGHT, face * 0.22) * Basis.from_scale(Vector3(w + 0.1, 0.06, d)), at + Vector3(0, 2.0, 0)), cloth)
	# Scalloped front edge, a shade darker
	var n := int(w / 0.3)
	for i in n:
		var x := -w * 0.5 + (i + 0.5) * w / n
		_add("block", Transform3D(Basis.from_scale(Vector3(w / n - 0.04, 0.24 if i % 2 == 0 else 0.17, 0.05)), at + Vector3(x, 1.84, face * d * 0.5)), cloth.darkened(0.12))

# ── Work camp ─────────────────────────────────────────────────
# The builders' camp at the edges of the yard (Neh. 4:22 "let each man lodge inside
# Jerusalem"): a shaded cistern, a stone cart, the carpenters' bench, the standards.
# Visual only, kept to the yard's margins.
func _build_work_camp() -> void:
	_cistern(Vector3(-20.5, 0, 10.5))
	_cart(Vector3(-21.0, 0, 5.5), 0.5)
	_bench(Vector3(19.5, 0, 9.0))
	for x: float in [-22.2, 21.6]:
		_banner(Vector3(x, 0, 2.6))

# Stone-lined basin of water under an indigo canopy, jars waiting beside it
func _cistern(c: Vector3) -> void:
	# Rim of separate cut blocks, two courses, joints staggered
	for course in 2:
		var y := 0.14 + course * 0.26
		for side: float in [-1.0, 1.0]:
			var x := -1.25 + (0.3 if course == 1 else 0.0)
			while x < 1.2:
				var l := minf(_rng.randf_range(0.5, 0.75), 1.25 - x)
				_add("block", Transform3D(Basis.from_scale(Vector3(l - 0.04, 0.24, 0.36)), c + Vector3(x + l * 0.5, y, side * 1.0)), _vary(Palette.WALL_STONE, 0.07))
				x += l
			var z := -0.82 + (0.25 if course == 0 else 0.0)
			while z < 0.8:
				var l2 := minf(_rng.randf_range(0.5, 0.7), 0.82 - z)
				_add("block", Transform3D(Basis.from_scale(Vector3(0.36, 0.24, l2 - 0.04)), c + Vector3(side * 1.07, y, z + l2 * 0.5)), _vary(Palette.WALL_STONE, 0.07))
				z += l2
	_add("block", Transform3D(Basis.from_scale(Vector3(1.8, 0.06, 1.7)), c + Vector3(0, 0.44, 0)), WATER_COLOR)
	# Light on the water: a few pale streaks
	for i in 4:
		_add("slab", Transform3D(Basis(Vector3.UP, 0.5).scaled(Vector3(_rng.randf_range(0.3, 0.6), 0.01, 0.05)), c + Vector3(_rng.randf_range(-0.6, 0.6), 0.475, _rng.randf_range(-0.6, 0.6))), WATER_COLOR.lightened(0.45))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_add("timber", Transform3D(Basis.from_scale(Vector3(0.16, 2.4, 0.16)), c + Vector3(sx * 1.5, 1.2, sz * 1.35)), _vary(BEAM_COLOR, 0.04))
	# Cloth in two panels meeting in a low ridge, scalloped valance all round
	for sz: float in [-1.0, 1.0]:
		_add("block", Transform3D(Basis(Vector3.RIGHT, sz * 0.16) * Basis.from_scale(Vector3(3.4, 0.07, 1.62)), c + Vector3(0, 2.52, sz * 0.78)), Palette.INDIGO)
	_valance(c + Vector3(0, 2.36, 0), 3.4, 3.1, Palette.INDIGO.darkened(0.12))
	for i in 3:
		_jar(c + Vector3(1.9 + (i % 2) * 0.45, 0.0, -0.6 + i * 0.55), _rng.randf_range(1.0, 1.3))

# Scalloped cloth edge: tabs hanging off each side of a w×d canopy
func _valance(c: Vector3, w: float, d: float, cloth: Color) -> void:
	for side: float in [-1.0, 1.0]:
		var n := int(w / 0.34)
		for i in n:
			var x := -w * 0.5 + (i + 0.5) * w / n
			_add("block", Transform3D(Basis.from_scale(Vector3(w / n - 0.05, 0.26 if i % 2 == 0 else 0.2, 0.04)), c + Vector3(x, 0, side * d * 0.5)), cloth)
		var m := int(d / 0.34)
		for i in m:
			var z := -d * 0.5 + (i + 0.5) * d / m
			_add("block", Transform3D(Basis.from_scale(Vector3(0.04, 0.26 if i % 2 == 0 else 0.2, d / m - 0.05)), c + Vector3(side * w * 0.5, 0, z)), cloth)

# Clay water jar: round belly, narrow neck, a lip
func _jar(at: Vector3, sc: float) -> void:
	var col := _vary(CLAY_COLOR, 0.05)
	_add("jar", Transform3D(Basis.from_scale(Vector3(1.25, 1.1, 1.25) * sc), at + Vector3(0, 0.28 * sc, 0)), col)
	_add("drum", Transform3D(Basis.from_scale(Vector3(0.2, 0.2, 0.2) * sc), at + Vector3(0, 0.6 * sc, 0)), col.darkened(0.05))
	_add("drum", Transform3D(Basis.from_scale(Vector3(0.3, 0.06, 0.3) * sc), at + Vector3(0, 0.71 * sc, 0)), col.lightened(0.08))

# Two-wheeled cart loaded with cut stone
func _cart(c: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	_add("timber", Transform3D(b * Basis.from_scale(Vector3(1.9, 0.14, 1.2)), c + b * Vector3(0, 0.62, 0)), _vary(BEAM_COLOR, 0.04).lightened(0.08))
	for sz: float in [-1.0, 1.0]:
		_add("timber", Transform3D(b * Basis.from_scale(Vector3(1.9, 0.3, 0.08)), c + b * Vector3(0, 0.82, sz * 0.58)), _vary(BEAM_COLOR, 0.04))
		# Wheel: a thick disc on its side, hub in the middle
		_add("drum", Transform3D(b * Basis(Vector3.RIGHT, PI / 2) * Basis.from_scale(Vector3(0.95, 0.12, 0.95)), c + b * Vector3(0, 0.48, sz * 0.72)), BEAM_COLOR.darkened(0.15))
		_add("drum", Transform3D(b * Basis(Vector3.RIGHT, PI / 2) * Basis.from_scale(Vector3(0.25, 0.2, 0.25)), c + b * Vector3(0, 0.48, sz * 0.8)), BEAM_COLOR.darkened(0.35))
	# Shafts resting on the ground
	for sz: float in [-0.35, 0.35]:
		_add("timber", Transform3D(b * Basis(Vector3.FORWARD, -0.32) * Basis.from_scale(Vector3(1.5, 0.08, 0.08)), c + b * Vector3(1.55, 0.35, sz)), _vary(BEAM_COLOR, 0.04))
	for i in 5:
		var s := Vector3(_rng.randf_range(0.45, 0.6), 0.32, _rng.randf_range(0.35, 0.45))
		_add("block", Transform3D(b * Basis(Vector3.UP, _rng.randf_range(-0.3, 0.3)) * Basis.from_scale(s),
			c + b * Vector3(-0.55 + (i % 3) * 0.55, 0.86 + (i / 3) * 0.3, -0.22 + (i % 2) * 0.44)), _vary(Palette.WALL_STONE, 0.05))

# Carpenter's bench: trestle top, a plank being worked, shavings, a stack of boards
func _bench(c: Vector3) -> void:
	_add("timber", Transform3D(Basis.from_scale(Vector3(2.0, 0.14, 0.8)), c + Vector3(0, 0.82, 0)), _vary(BEAM_COLOR, 0.03).lightened(0.12))
	for sx: float in [-0.8, 0.8]:
		for sz: float in [-0.3, 0.3]:
			_add("timber", Transform3D(Basis.from_scale(Vector3(0.12, 0.8, 0.12)), c + Vector3(sx, 0.4, sz)), _vary(BEAM_COLOR, 0.04))
	_add("block", Transform3D(Basis(Vector3.UP, 0.15) * Basis.from_scale(Vector3(1.6, 0.07, 0.3)), c + Vector3(0.1, 0.93, 0.05)), Color(0.74, 0.54, 0.32))
	for i in 14:
		_add("pebble", Transform3D(_yaw().scaled(Vector3(0.9, 0.3, 0.5)), c + Vector3(_rng.randf_range(-1.2, 1.2), 0.1, _rng.randf_range(-0.9, 0.9))), Color(0.86, 0.68, 0.42))
	for i in 4:
		_add("block", Transform3D(Basis.from_scale(Vector3(0.3, 0.07, 2.2)), c + Vector3(1.7 + (i % 2) * 0.05, 0.14 + i * 0.075, 0.2)), _vary(Color(0.66, 0.46, 0.27), 0.04))

# Standard on a pole: indigo cloth with a pale tower worked on it
func _banner(at: Vector3) -> void:
	_add("timber", Transform3D(Basis.from_scale(Vector3(0.14, 4.4, 0.14)), at + Vector3(0, 2.2, 0)), _vary(BEAM_COLOR, 0.03))
	_add("timber", Transform3D(Basis.from_scale(Vector3(0.1, 0.1, 1.2)), at + Vector3(0.06, 4.25, 0.55)), _vary(BEAM_COLOR, 0.03))
	_add("block", Transform3D(Basis.from_scale(Vector3(0.05, 1.8, 1.05)), at + Vector3(0.08, 3.25, 0.58)), Palette.INDIGO)
	# Swallow-tail: two short points at the foot
	for dz: float in [-0.27, 0.27]:
		_add("block", Transform3D(Basis(Vector3.RIGHT, dz * 1.4) * Basis.from_scale(Vector3(0.05, 0.4, 0.4)), at + Vector3(0.08, 2.25, 0.58 + dz)), Palette.INDIGO)
	# Tower emblem, a stepped silhouette in undyed wool
	var e := at + Vector3(0.11, 3.2, 0.58)
	_add("block", Transform3D(Basis.from_scale(Vector3(0.03, 0.55, 0.36)), e), Palette.UNDYED)
	for dz: float in [-0.13, 0.0, 0.13]:
		_add("block", Transform3D(Basis.from_scale(Vector3(0.03, 0.12, 0.08)), e + Vector3(0, 0.33, dz)), Palette.UNDYED)
	_add("block", Transform3D(Basis.from_scale(Vector3(0.035, 0.2, 0.1)), e + Vector3(0.002, -0.17, 0)), Palette.INDIGO)

# ── Batching ──────────────────────────────────────────────────

func _add(kind: String, xf: Transform3D, color: Color) -> void:
	if not _batches.has(kind):
		_batches[kind] = [[] as Array[Transform3D], [] as Array[Color]]
	_batches[kind][0].append(xf)
	_batches[kind][1].append(color)

func _flush() -> void:
	for kind: String in _batches:
		var mmi := _multimesh(_mesh_for(kind), _batches[kind][0], _batches[kind][1], _material_for(kind))
		# Ground-hugging bits: shadows cost more than they add
		if kind in ["pebble", "patch", "slab", "blade", "bed", "chip"]:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_batches.clear()

# Chunky look: bevelled blocks, faceted foliage and rock
func _material_for(kind: String) -> Material:
	match kind:
		"block", "opening": return Chunky.material(0.06)
		"chip":             return Chunky.material(0.03, false, 0.3)
		"timber":           return Chunky.wood_material(0.025)
		"slab":             return Chunky.material(0.1, false, 0.28)
		"bush", "leaf":     return Chunky.foliage_material()
		"blade":            return Chunky.material(0.0, true, 0.0)
		"boulder", "pebble": return Chunky.material(0.0, true, 0.0)
	return Chunky.material(0.0, false, 0.0)

func _mesh_for(kind: String) -> Mesh:
	match kind:
		"block", "slab", "opening", "chip", "timber": return Chunky.unit_block()
		"pebble":  return _sphere(0.13, 0.10, 5, 2)
		"blade":   return _cylinder(0.0, 0.075, 1.0, 3)
		"bush":    return _sphere(0.42, 0.62, 12, 6)
		"leaf":    return _sphere(0.6, 1.0, 14, 7)
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

func _multimesh(mesh: Mesh, xf: Array[Transform3D], colors: Array[Color], mat: Material = null) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, colors[i])
	if mat == null:
		mat = Chunky.material(0.0, false, 0.0)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)
	return mmi
