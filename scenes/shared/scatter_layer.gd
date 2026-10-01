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
const BUSH_COLOR   := Color(0.36, 0.45, 0.26)
const MYRTLE_LEAF  := Color(0.37, 0.49, 0.25)
const SCRUB_LEAF   := Color(0.49, 0.52, 0.35)
const PALM_LEAF    := Color(0.43, 0.47, 0.28)
const DATE_COLOR   := Color(0.72, 0.36, 0.12)
const TUFT_COLOR   := Color(0.58, 0.60, 0.32)   # dusty sage — late summer, half dry
const STRAW_COLOR  := Color(0.80, 0.70, 0.42)
const MEADOW_GREEN := Color(0.52, 0.58, 0.28)
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
const LAMPLIGHT    := Color(1.0, 0.58, 0.2)   # a clay oil lamp behind the window, at dusk

var _rng := RandomNumberGenerator.new()
# House details added after the layout was fixed draw from here, so nothing shifts
var _deco := RandomNumberGenerator.new()
# Instances collected by kind, flushed into one MultiMesh each at the end
var _batches := {}
# Window glows, lit by DayLight at dusk (set_lamps); built in _flush, in a fixed shuffled
# order so they come on one by one, the same on every peer
var _lamp_spots: Array[Transform3D] = []
var _lamps: MultiMesh
var _halos: MultiMesh   # the soft glow round each lit window, same order
static var _halo_mat: StandardMaterial3D

func _ready() -> void:
	_rng.seed = 42
	_deco.seed = 4242
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
	_build_meadows()
	_build_rock_clusters()
	_flush()

# ── Ground cover ──────────────────────────────────────────────

func _build_pebbles() -> void:
	var pts := _free_points(380, false, false)
	for i in pts.size():
		var s := Vector3(_rng.randf_range(0.6, 1.8), _rng.randf_range(0.4, 1.0), _rng.randf_range(0.6, 1.8))
		var xf := Transform3D(_yaw().scaled(s), Vector3(pts[i].x, 0.04, pts[i].y))
		var col := _vary(ROCK_COLOR, 0.06)
		if i % 3 != 2:   # thinned: the draws stay, a third aren't placed
			_add("pebble", xf, col)

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
	# Lone tufts read as stray spikes: still drawn from the RNG (the layout mustn't
	# shift) but not placed; grass now grows only in colonies and meadows
	for p in _free_points(260, true, false):
		_tuft(Vector3(p.x, 0.1, p.y), false)
	# A scatter along the wall foot and round the yard, where feet don't reach
	for i in 70:
		var at := Vector3(_rng.randf_range(-22.0, 22.0), 0.1, _rng.randf_range(-6.0, -1.6) if _rng.randf() < 0.6 else _rng.randf_range(1.6, 3.0))
		_tuft(at)

## Shared with ground.gdshader meadow_mask() — keep the two in step
static func meadow(x: float, z: float) -> float:
	return sin(x * 0.21 + z * 0.13) * sin(z * 0.17 - x * 0.07) \
		+ 0.45 * sin(x * 0.43 + 1.7) * sin(z * 0.39 + 0.4)

const WORK_RECT := Rect2(-14.0, -2.5, 28.0, 15.5)   # matches ground.gdshader work_rect

# Grass thick on the green ground the shader lays under it, bushes at the heart
func _build_meadows() -> void:
	var z := -HALF_Z
	while z < 14.0:
		var x := -HALF_X
		while x < HALF_X:
			# Jitter more than half the step, so the grid doesn't show
			var p := Vector2(x + _rng.randf_range(-0.4, 0.4) * 1.6, z + _rng.randf_range(-0.4, 0.4) * 1.6)
			x += 1.1
			var m := meadow(p.x, p.y)
			if m < 0.62 or WORK_RECT.grow(1.5).has_point(p) or _blocked(p) or _on_street(p, 1.0):
				continue
			_tuft(Vector3(p.x, 0.1, p.y), true, clampf(remap(m, 0.62, 1.1, 0.0, 1.0), 0.0, 1.0))
			if m > 0.85 and _rng.randf() < 0.12:
				_bush(Vector3(p.x, 0.0, p.y))
		z += 1.1

# Weathered limestone breaking the surface in twos and threes, pebbles round them
func _build_rock_clusters() -> void:
	for p in _free_points(60, true, false):
		if WORK_RECT.grow(1.0).has_point(p):
			continue
		var c := Vector3(p.x, 0.0, p.y)
		for j in _rng.randi_range(2, 3):
			var s := Vector3(_rng.randf_range(0.5, 1.0), _rng.randf_range(0.3, 0.6), _rng.randf_range(0.45, 0.9))
			var at := c + Vector3(_rng.randf_range(-0.6, 0.6), s.y * 0.25, _rng.randf_range(-0.6, 0.6))
			_add("boulder", Transform3D(_yaw().scaled(s), at), _vary(ROCK_COLOR, 0.05).lightened(0.06))
		for j in 5:
			var s2 := Vector3.ONE * _rng.randf_range(0.8, 1.5)
			_add("pebble", Transform3D(_yaw().scaled(s2), c + Vector3(_rng.randf_range(-1.1, 1.1), 0.04, _rng.randf_range(-1.1, 1.1))), _vary(ROCK_COLOR, 0.06))

# Grass grows in little colonies: pairs and threes rather than lone tufts
func _build_tuft_pairs() -> void:
	for p in _free_points(200, true, false):
		for j in _rng.randi_range(2, 3):
			_tuft(Vector3(p.x + _rng.randf_range(-0.55, 0.55), 0.1, p.y + _rng.randf_range(-0.55, 0.55)))

# One tuft = one instance of a baked clump of curved blades (_tuft_mesh), in one of two
# shapes. `lush` (0 … 1) makes it bigger and greener — the heart of a meadow.
# RNG draws are fixed per tuft whatever the look, so nothing seeded later shifts.
func _tuft(at: Vector3, place := true, lush := 0.0) -> void:
	var base := _vary(TUFT_COLOR, 0.05)
	var n := _rng.randi_range(7, 11)
	var yaw := 0.0
	var lean := 0.0
	var h := 0.0
	var tint := 0.0
	for i in n:
		var a := TAU * i / n + _rng.randf_range(-0.3, 0.3)
		if i == 0:
			yaw = a
		lean += _rng.randf_range(0.15, 0.6) / n
		h += _rng.randf_range(0.28, 0.6) / n
		tint = maxf(tint, _rng.randf_range(0.0, 0.12))
	if not place:
		return
	# lean ~0.37, h ~0.44, tint ~0.1 on average: spread each back out to a useful range
	var size := remap(h, 0.36, 0.52, 0.8, 1.2) * (1.0 + lush * 0.5)
	var c := base.lerp(STRAW_COLOR, clampf(remap(tint, 0.08, 0.12, 0.0, 0.45), 0.0, 0.45))
	c = c.lerp(MEADOW_GREEN, lush * 0.6)
	var b := Basis(Vector3.UP, yaw).scaled(Vector3(size * (0.8 + lean), size, size * (0.8 + lean)))
	_add("tuft" if n % 2 == 0 else "tuft_b", Transform3D(b, at - Vector3(0, 0.02, 0)), c)

# A clump of curved, tapering blades fanned from a small root, ~0.3 m tall, ~0.45 m
# across. UV.y = 0 at the root, 1 at the tip (grass.gdshader shades along it).
static func _tuft_mesh(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blades := 17
	for i in blades:
		var a := TAU * i / blades + rng.randf_range(-0.25, 0.25)
		var out := Vector3(cos(a), 0.0, sin(a))
		var side := out.cross(Vector3.UP)
		var root := out * rng.randf_range(0.0, 0.07)
		# Inner blades stand up tall, outer ones splay low
		var inner := i % 3 == 0
		var tall := rng.randf_range(0.26, 0.36) if inner else rng.randf_range(0.14, 0.26)
		var reach := rng.randf_range(0.03, 0.08) if inner else rng.randf_range(0.12, 0.22)
		var w := rng.randf_range(0.038, 0.055)
		var pts: Array[Vector3] = []
		for k in 4:
			var t := k / 3.0
			pts.append(root + out * reach * t * t + Vector3.UP * tall * (t * (1.6 - 0.6 * t)))
		for k in 3:
			var t0 := k / 3.0
			var t1 := (k + 1) / 3.0
			var w0 := w * (1.0 - t0)
			var w1 := w * (1.0 - t1)
			var q := [pts[k] - side * w0, pts[k] + side * w0, pts[k + 1] + side * w1, pts[k + 1] - side * w1]
			var v := [t0, t0, t1, t1]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_uv(Vector2(0.0, v[idx]))
				st.set_normal(Vector3.UP)
				st.add_vertex(q[idx])
	return st.commit()

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
	for i in spots.size():
		var p := spots[i]
		if absf(p.y) < 1.3 or _blocked(p):
			continue
		# Warm limestone like the ground it lies on (the cool wall grey spotted the whole
		# map), and only two heaps in three: the draws are all still taken
		var shown := i % 3 != 2
		var base := _vary(Palette.LIMESTONE, 0.06).darkened(_rng.randf_range(0.0, 0.12))
		for j in _rng.randi_range(2, 5):
			var sz := _rng.randf_range(0.14, 0.32)
			var s := Vector3(sz * _rng.randf_range(0.9, 1.5), sz * _rng.randf_range(0.6, 1.0), sz * _rng.randf_range(0.9, 1.4))
			var off := Vector3(_rng.randf_range(-0.35, 0.35), s.y * 0.45, _rng.randf_range(-0.35, 0.35))
			var tilt := Basis.from_euler(Vector3(_rng.randf_range(-0.25, 0.25), _rng.randf() * TAU, _rng.randf_range(-0.25, 0.25)))
			var col := base.lightened(_rng.randf_range(0.0, 0.08))
			if shown:
				_add("chip", Transform3D(tilt.scaled(s), Vector3(p.x, 0.0, p.y) + off), col)

func _build_bushes() -> void:
	# Low myrtle in sheltered spots, silver dry scrub on the exposed slopes.
	for p in _free_points(46, true, false):
		if p.y < -10.0 and _rng.randf() < 0.65:
			_dry_scrub(Vector3(p.x, 0.0, p.y))
		else:
			_bush(Vector3(p.x, 0.0, p.y))

func _bush(at: Vector3) -> void:
	_myrtle(at, false)

# Branching stems stay visible below the small, glossy leaf clusters. A few white
# blossoms identify myrtle without turning every patch of ground into a flower bed.
func _myrtle(at: Vector3, tree := false) -> void:
	var rng := _plant_rng(at, 91)
	var height := 1.75 if tree else 0.84
	var spread := 1.1 if tree else 0.78
	var wood := OLIVE_TRUNK.lightened(0.08)
	var stems := 7 if tree else 6
	for stem in stems:
		var a := TAU * stem / float(stems) + rng.randf_range(-0.25, 0.25)
		var foot := at + Vector3(cos(a) * 0.12, 0.05, sin(a) * 0.12)
		var tip := at + Vector3(cos(a) * spread * rng.randf_range(0.55, 1.0), height * rng.randf_range(0.75, 1.1), sin(a) * spread * rng.randf_range(0.55, 1.0))
		_wood_between(foot, tip, 0.15 if tree else 0.075, wood)
		# Rounded overlapping crowns establish the dense silhouette in the reference.
		var crown_size := Vector3(0.95, 0.65, 0.84) if tree else Vector3(0.82, 0.54, 0.73)
		_add("leaf", Transform3D(Basis(Vector3.UP, a).scaled(crown_size), tip + Vector3(0, 0.05, 0)), MYRTLE_LEAF.darkened(rng.randf_range(0.02, 0.14)))
		for j in 4:
			var pos := tip + Vector3(rng.randf_range(-0.26, 0.26), rng.randf_range(-0.15, 0.2), rng.randf_range(-0.26, 0.26))
			var scale := Vector3(0.62, 0.4, 0.54) * (1.15 if tree else 0.8)
			_add("myrtle_sprig", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(scale), pos + Vector3(0, 0.17, 0)), MYRTLE_LEAF.lightened(rng.randf_range(0.08, 0.28)))
		if stem % 2 == 0:
			for petal in 3:
				var flower := tip + Vector3(rng.randf_range(-0.3, 0.3), 0.22, rng.randf_range(-0.3, 0.3))
				_add("blossom", Transform3D(Basis.from_scale(Vector3.ONE * (1.0 if tree else 0.8)), flower), Color(0.96, 0.92, 0.79))

func _dry_scrub(at: Vector3) -> void:
	var rng := _plant_rng(at, 419)
	for stem in 7:
		var a := TAU * stem / 7.0 + rng.randf_range(-0.3, 0.3)
		var tip := at + Vector3(cos(a) * rng.randf_range(0.3, 0.7), rng.randf_range(0.55, 1.05), sin(a) * rng.randf_range(0.3, 0.7))
		_wood_between(at + Vector3(0, 0.06, 0), tip, 0.055, OLIVE_TRUNK.lightened(0.1))
		if stem % 3 != 0:
			_add("leaf", Transform3D(Basis(Vector3.UP, a).scaled(Vector3(0.32, 0.26, 0.3)), tip), SCRUB_LEAF.darkened(0.1))
			_add("myrtle_sprig", Transform3D(Basis(Vector3.UP, a).scaled(Vector3(0.32, 0.24, 0.3)), tip), SCRUB_LEAF.lightened(rng.randf_range(-0.08, 0.06)))

static func _plant_rng(at: Vector3, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(at.x * 7919.0 + at.z * 104729.0)) + salt
	return rng

func _wood_between(a: Vector3, b: Vector3, width: float, color: Color) -> void:
	var delta := b - a
	var basis := Basis(Quaternion(Vector3.UP, delta.normalized()))
	_add("timber", Transform3D(basis.scaled(Vector3(width, delta.length(), width)), (a + b) * 0.5), color)

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
	var rng := _plant_rng(at, 211)
	var old := rng.randf() < 0.4
	var h := rng.randf_range(1.4, 1.8) if old else rng.randf_range(1.55, 2.0)
	var crown := 1.3 if old else 1.0
	var base := at + Vector3(0, 0.06, 0)
	var fork := at + Vector3(rng.randf_range(-0.12, 0.12), h, rng.randf_range(-0.12, 0.12))
	var wood := OLIVE_TRUNK.lightened(0.08)
	# Split, twisting trunks make the old trees distinct from the younger single stems.
	if old:
		for i in 2:
			var side := -1.0 if i == 0 else 1.0
			var bend := at + Vector3(side * 0.23, h * 0.55, side * 0.11)
			_wood_between(base + Vector3(side * 0.12, 0, 0), bend, 0.4, wood.darkened(0.07 * i))
			_wood_between(bend, fork + Vector3(side * 0.16, 0, 0), 0.29, wood.lightened(0.07))
	else:
		_wood_between(base, fork, 0.34, wood)
	for i in 9:
		var a := TAU * i / 9.0 + rng.randf_range(-0.23, 0.23)
		var reach := rng.randf_range(0.9, 1.5) * crown
		var end := fork + Vector3(cos(a) * reach, rng.randf_range(0.36, 1.1), sin(a) * reach)
		_wood_between(fork + Vector3(0, 0.05, 0), end, 0.17 if old else 0.12, wood)
		var foliage := OLIVE_LEAF.lerp(Color(0.68, 0.69, 0.52), rng.randf_range(0.45, 0.75))
		_add("leaf", Transform3D(Basis(Vector3.UP, a).scaled(Vector3(1.12, 0.58, 0.88)), end + Vector3(0, 0.18, 0)), foliage.darkened(0.11))
		for j in 6:
			var pos := end + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.16, 0.24), rng.randf_range(-0.3, 0.3))
			var s := Vector3(rng.randf_range(0.55, 0.75), rng.randf_range(0.28, 0.4), rng.randf_range(0.5, 0.7))
			_add("olive_sprig", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(s), pos + Vector3(0, 0.34, 0)), foliage.lightened(rng.randf_range(0.05, 0.2)))

func _date_palm(at: Vector3) -> void:
	var rng := _plant_rng(at, 617)
	var h := rng.randf_range(3.8, 4.5)
	var trunk := Color(0.52, 0.31, 0.17)
	_wood_between(at + Vector3(0, 0.1, 0), at + Vector3(0, h, 0), 0.42, trunk)
	# Staggered diamond-like leaf bases give the date palm its armored trunk.
	for row in 15:
		var y := 0.3 + row * (h - 0.5) / 15.0
		for side in 4:
			var a := TAU * (side + 0.5 * (row % 2)) / 4.0
			var p := at + Vector3(cos(a) * 0.23, y, sin(a) * 0.23)
			_add("palm_scale", Transform3D(Basis(Vector3.UP, a).scaled(Vector3(0.34, 0.28, 0.13)), p), trunk.lightened(rng.randf_range(-0.08, 0.16)))
	var crown := at + Vector3(0, h + 0.1, 0)
	for i in 16:
		var a := TAU * i / 16.0 + rng.randf_range(-0.12, 0.12)
		var size := rng.randf_range(0.88, 1.18)
		_add("palm_frond", Transform3D(Basis(Vector3.UP, a).scaled(Vector3.ONE * size), crown), PALM_LEAF.lightened(rng.randf_range(-0.11, 0.09)))
	for bunch in 3:
		var a := TAU * bunch / 3.0 + 0.3
		for fruit in 5:
			var p := crown + Vector3(cos(a) * (0.4 + fruit * 0.05), -0.48 - fruit * 0.12, sin(a) * (0.4 + fruit * 0.05))
			_add("date", Transform3D(Basis.from_scale(Vector3(0.12, 0.17, 0.12)), p), DATE_COLOR.lightened(rng.randf_range(-0.07, 0.13)))

# Limestone breaking through the soil, well clear of the enemy approach
func _build_outcrops() -> void:
	for c: Vector3 in [Vector3(-44, 0, -6), Vector3(28, 0, -40), Vector3(44, 0, -24), Vector3(-18, 0, -38), Vector3(12, 0, -34)]:
		for i in _rng.randi_range(3, 6):
			var s := Vector3(_rng.randf_range(0.9, 2.2), _rng.randf_range(0.5, 1.4), _rng.randf_range(0.9, 2.0))
			var at := c + Vector3(_rng.randf_range(-2.5, 2.5), s.y * 0.3, _rng.randf_range(-2.0, 2.0))
			_add("boulder", Transform3D(_yaw().scaled(s), at), _vary(ROCK_COLOR, 0.05).lightened(0.05))
		_bush(c + Vector3(_rng.randf_range(-3, 3), 0, 2.5))

# The enemy's camps, just beyond where their men come on (Neh. 4:8, 4:11 "they will not
# know or see, until we come in among them"): Sanballat's soldiers of Samaria (4:2) in
# ridge tents under his standard, Geshem's Arabs in black goat-hair tents with their
# camels, and a picket fire out on the east flank. Visual only, behind the spawn line.
# Built with its own RNG: the draws the old camp made are still taken, so the city
# seeded after it keeps its layout.
func _build_camp() -> void:
	for i in 48:
		_rng.randf()
	if GameState.festival:
		return   # the wall is dedicated (Neh. 12): the enemy has gone home
	var layout_rng := _rng
	_rng = RandomNumberGenerator.new()
	_rng.seed = 455
	_soldier_camp(Vector3(-12.0, 0.0, -22.5))
	_arab_camp(Vector3(10.5, 0.0, -24.5))
	_picket(Vector3(23.0, 0.0, -15.5))
	_rng = layout_rng

const CAMP_CLEAR := [Rect2(-20.0, -28.0, 16.0, 11.0), Rect2(3.0, -30.0, 15.5, 11.0), Rect2(20.0, -18.5, 6.0, 5.5)]
const GOAT_HAIR  := Color(0.25, 0.20, 0.17)
const BRONZE     := Color(0.72, 0.52, 0.26)
const OXBLOOD    := Color(0.46, 0.12, 0.09)
const CAMEL      := Color(0.60, 0.44, 0.29)

# Samaria's soldiers: ridge tents in two rows round a fire, a spear rack, the standard
func _soldier_camp(c: Vector3) -> void:
	for i in 3:
		_ridge_tent(c + Vector3(-5.0 + i * 3.4, 0, -2.6 + _rng.randf_range(-0.3, 0.3)), _rng.randf_range(-0.12, 0.12),
			Palette.UNDYED.darkened(0.12) if i != 1 else Palette.MADDER.darkened(0.25))
	for i in 2:
		_ridge_tent(c + Vector3(3.6 + i * 3.0, 0, 1.2 + i * 0.6), PI * 0.5 + _rng.randf_range(-0.1, 0.1), Palette.UNDYED.darkened(0.18))
	_campfire(c + Vector3(-0.8, 0, 1.0))
	_spear_rack(c + Vector3(-5.2, 0, 1.8), 0.0)
	_standard(c + Vector3(1.4, 0, -1.2), OXBLOOD)
	_firewood(c + Vector3(-3.2, 0, 2.6))
	for p: Vector3 in [Vector3(1.8, 0, 2.4), Vector3(2.4, 0, 2.0)]:
		_sack(c + p)
	_jar(c + Vector3(2.2, 0, 2.9), 1.1)

# Geshem's Arabs: two long black tents of goat hair, camels couched beside them
func _arab_camp(c: Vector3) -> void:
	_hair_tent(c + Vector3(-2.6, 0, -1.8), 0.08)
	_hair_tent(c + Vector3(3.4, 0, -2.6), -0.1)
	_campfire(c + Vector3(0.6, 0, 1.4))
	_camel(c + Vector3(-3.6, 0, 2.8), 0.4)
	_camel(c + Vector3(-5.2, 0, 4.5), PI + 0.2)
	_camel(c + Vector3(7.4, 0, 2.6), 3.7)
	for i in 3:
		_sack(c + Vector3(2.4 + i * 0.55, 0, 0.6 + (i % 2) * 0.3))
	_jar(c + Vector3(-0.8, 0, 2.8), 1.0)
	_jar(c + Vector3(-0.4, 0, 3.1), 0.8)
	_spear_rack(c + Vector3(3.2, 0, 2.8), -0.2)

# A lone watch fire on the flank, spears stuck in the ground
func _picket(c: Vector3) -> void:
	_campfire(c)
	for i in 3:
		var at := c + Vector3(1.4 + i * 0.35, 0, -0.8 + i * 0.25)
		_spear(at, Basis.from_euler(Vector3(_rng.randf_range(-0.12, 0.12), 0, _rng.randf_range(-0.12, 0.12))))
	_sack(c + Vector3(-1.2, 0, -0.6))

# Soldier's tent: a ridge of cloth over a pole at each end, dark doorway, pegged ropes
func _ridge_tent(c: Vector3, yaw: float, cloth: Color) -> void:
	var b := Basis(Vector3.UP, yaw)
	var l := _rng.randf_range(2.3, 2.7)
	var h := 1.45
	var half := 1.05
	var slope := sqrt(h * h + half * half)
	var tilt := atan2(h, half)
	cloth = _vary(cloth, 0.03)
	for side: float in [-1.0, 1.0]:
		var panel := b * Basis(Vector3.RIGHT, side * tilt) * Basis.from_scale(Vector3(l, 0.06, slope))
		_add("block", Transform3D(panel, c + b * Vector3(0, h * 0.5, side * half * 0.5)), cloth.darkened(0.0 if side < 0 else 0.1))
		# Pegged guy ropes off the eaves
		for sx: float in [-1.0, 1.0]:
			_rope(c + b * Vector3(sx * l * 0.45, 0.2, side * half), c + b * Vector3(sx * (l * 0.5 + 0.3), 0.0, side * (half + 0.55)))
	# Gable ends: a pole standing out of the ridge, the front flap open on a dark doorway
	for sx: float in [-1.0, 1.0]:
		_add("timber", Transform3D(b * Basis.from_scale(Vector3(0.08, h + 0.35, 0.08)), c + b * Vector3(sx * (l * 0.5 + 0.02), (h + 0.35) * 0.5, 0)), _vary(BEAM_COLOR, 0.04))
	var door := b * Basis(Vector3.UP, PI * 0.5)
	_add("tent", Transform3D(door * Basis.from_scale(Vector3(1.4, 1.05, 0.05)), c + b * Vector3(l * 0.5 - 0.01, 0.53, 0)), OPENING)
	_add("tent", Transform3D(door * Basis.from_scale(Vector3(2.1, h, 0.04)), c + b * Vector3(-l * 0.5 + 0.02, h * 0.5, 0)), cloth.darkened(0.14))

# Bedouin "house of hair": low black cloth on rows of poles, open to the front, a
# pale woven band along the roof, the back and sides let down
func _hair_tent(c: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var l := 4.6
	var d := 3.0
	var ridge := 1.75
	var eave := 1.05
	var slope := sqrt(pow(ridge - eave, 2) + pow(d * 0.5, 2))
	var tilt := atan2(ridge - eave, d * 0.5)
	for side: float in [-1.0, 1.0]:
		var rot := b * Basis(Vector3.RIGHT, side * tilt)
		var panel := rot * Basis.from_scale(Vector3(l, 0.07, slope))
		var mid := c + b * Vector3(0, (ridge + eave) * 0.5, side * d * 0.25)
		_add("block", Transform3D(panel, mid), _vary(GOAT_HAIR, 0.02).lightened(0.06 if side > 0 else 0.0))
		# The woven band: two pale stripes running the length of each slope
		for k: float in [-0.22, 0.25]:
			var at := mid + rot * Vector3(0, 0.012, k * slope)
			_add("block", Transform3D(panel * Basis.from_scale(Vector3(1.0, 1.1, 0.07)), at), Palette.UNDYED.darkened(0.1))
	# Back and sides let down to the ground
	_add("block", Transform3D(b * Basis.from_scale(Vector3(l, eave, 0.05)), c + b * Vector3(0, eave * 0.5, -d * 0.5)), GOAT_HAIR.darkened(0.1))
	for sx: float in [-1.0, 1.0]:
		_add("block", Transform3D(b * Basis.from_scale(Vector3(0.05, eave, d)), c + b * Vector3(sx * l * 0.5, eave * 0.5, 0)), GOAT_HAIR.darkened(0.05))
	# Poles along the front, the dark inside, a rug and cushions just in the shade
	for i in 4:
		var x := -l * 0.5 + 0.3 + i * (l - 0.6) / 3.0
		_add("timber", Transform3D(b * Basis.from_scale(Vector3(0.09, eave, 0.09)), c + b * Vector3(x, eave * 0.5, d * 0.5)), _vary(BEAM_COLOR, 0.04))
	_add("block", Transform3D(b * Basis.from_scale(Vector3(l - 0.2, 0.04, d - 0.3)), c + b * Vector3(0, 0.1, 0)), Color(0.14, 0.11, 0.09))
	_add("block", Transform3D(b * Basis.from_scale(Vector3(2.2, 0.05, 1.3)), c + b * Vector3(-0.4, 0.13, 0.6)), Palette.MADDER)
	_add("block", Transform3D(b * Basis.from_scale(Vector3(2.2, 0.052, 0.12)), c + b * Vector3(-0.4, 0.14, 0.95)), Palette.SAFFRON)
	for i in 2:
		_add("blob", Transform3D(b * Basis.from_scale(Vector3(0.7, 0.3, 0.4)), c + b * Vector3(-1.1 + i * 0.9, 0.24, -0.1)), Palette.DYES[(i + 2) % Palette.DYES.size()])
	for sx: float in [-1.0, 1.0]:
		_rope(c + b * Vector3(sx * l * 0.5, eave, d * 0.5), c + b * Vector3(sx * (l * 0.5 + 0.9), 0.0, d * 0.5 + 0.9))
		_rope(c + b * Vector3(sx * l * 0.5, eave, -d * 0.5), c + b * Vector3(sx * (l * 0.5 + 0.9), 0.0, -d * 0.5 - 0.9))

# A camel couched on folded legs (+X is forward), drawn in the workers' chunky style: a
# short lofted body with the hump behind the middle and a blanket over the flanks, a
# thick neck tapering up out of the chest, and a big round head with heavy brows and a
# drooping lip, turned a little to look about. Pale belly, throat and muzzle
func _camel(c: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * 1.25)
	var col := _vary(CAMEL, 0.04)
	var pale := col.lightened(0.2)
	var dark := col.darkened(0.2)
	var cloth: Color = [Palette.MADDER, Palette.INDIGO, Palette.MUREX][_rng.randi() % 3]
	_add("camel_body", Transform3D(b, c), col)
	_add("camel_belly", Transform3D(b, c), pale)
	_add("camel_cloth", Transform3D(b, c), cloth)
	_add("camel_band", Transform3D(b, c), Palette.UNDYED)
	# Legs folded under: the fore knees just showing at the chest, the hind legs along
	# the flanks with the feet tucked forward
	for sz: float in [-1.0, 1.0]:
		_add("blob", Transform3D(b * Basis.from_scale(Vector3(0.36, 0.16, 0.18)), c + b * Vector3(0.6, 0.09, sz * 0.2)), pale.darkened(0.06))
		_add("blob", Transform3D(b * Basis.from_scale(Vector3(0.66, 0.32, 0.2)), c + b * Vector3(-0.4, 0.2, sz * 0.4)), col)
		_add("blob", Transform3D(b * Basis.from_scale(Vector3(0.3, 0.1, 0.14)), c + b * Vector3(-0.02, 0.05, sz * 0.46)), pale.darkened(0.06))
	# Tail kept flat down the rump, a dark tuft at the end
	_add("blob", Transform3D(b * Basis(Vector3.BACK, 0.15) * Basis.from_scale(Vector3(0.07, 0.3, 0.07)), c + b * Vector3(-0.84, 0.42, 0)), col.darkened(0.08))
	_add("blob", Transform3D(b * Basis.from_scale(Vector3(0.1, 0.12, 0.08)), c + b * Vector3(-0.87, 0.27, 0)), dark)
	# Neck and head, turned about the chest
	var neck := Basis(Vector3.UP, _rng.randf_range(-0.45, 0.45))
	var root := Vector3(0.6, 0.6, 0)
	var part := func(kind: String, size: Vector3, at: Vector3, tint: Color) -> void:
		_add(kind, Transform3D(b * neck * Basis.from_scale(size), c + b * (root + neck * (at - root))), tint)
	part.call("camel_neck", Vector3.ONE, Vector3.ZERO, col)
	part.call("camel_throat", Vector3.ONE, Vector3.ZERO, pale)
	part.call("camel_head", Vector3.ONE, Vector3.ZERO, col.lightened(0.03))
	part.call("camel_muzzle", Vector3.ONE, Vector3.ZERO, col.lightened(0.1))
	# The drooping lower lip, nostrils, halter
	part.call("blob", Vector3(0.2, 0.1, 0.17), Vector3(1.55, 1.23, 0), pale.darkened(0.05))
	part.call("block", Vector3(0.05, 0.31, 0.32), Vector3(1.4, 1.41, 0), cloth)
	for sz: float in [-1.0, 1.0]:
		part.call("blob", Vector3(0.04, 0.03, 0.05), Vector3(1.63, 1.42, sz * 0.055), dark.darkened(0.3))
		# Big dark eyes under heavy brows, small round ears laid back
		part.call("blob", Vector3(0.08, 0.09, 0.05), Vector3(1.24, 1.51, sz * 0.18), Color(0.08, 0.06, 0.05))
		part.call("blob", Vector3(0.03, 0.03, 0.02), Vector3(1.26, 1.54, sz * 0.2), Color(0.95, 0.92, 0.85))
		part.call("blob", Vector3(0.16, 0.05, 0.08), Vector3(1.23, 1.58, sz * 0.17), dark)
		_add("blob", Transform3D(b * neck * Basis(Vector3.BACK, 0.5) * Basis.from_scale(Vector3(0.07, 0.15, 0.06)), c + b * (root + neck * (Vector3(1.04, 1.62, sz * 0.13) - root))), dark)

# Camel lofts, rings along a spine in the XY plane: [centre, above, below, side]
# (half-extents toward the spine's upper normal, away from it, and across in Z)
const CAMEL_BODY := [
	[Vector3(-0.84, 0.44, 0), 0.01, 0.01, 0.01],
	[Vector3(-0.82, 0.44, 0), 0.13, 0.13, 0.15],
	[Vector3(-0.78, 0.44, 0), 0.23, 0.24, 0.28],
	[Vector3(-0.68, 0.43, 0), 0.34, 0.36, 0.42],
	[Vector3(-0.52, 0.42, 0), 0.46, 0.38, 0.48],
	[Vector3(-0.34, 0.42, 0), 0.7, 0.38, 0.49],
	[Vector3(-0.16, 0.42, 0), 0.84, 0.38, 0.47],
	[Vector3(0.02, 0.42, 0), 0.72, 0.38, 0.46],
	[Vector3(0.2, 0.43, 0), 0.5, 0.38, 0.44],
	[Vector3(0.38, 0.45, 0), 0.38, 0.37, 0.4],
	[Vector3(0.54, 0.47, 0), 0.32, 0.33, 0.34],
	[Vector3(0.66, 0.48, 0), 0.22, 0.24, 0.22],
	[Vector3(0.72, 0.48, 0), 0.01, 0.01, 0.01],
]
# Deep out of the chest, tapering as it rises
const CAMEL_NECK := [
	[Vector3(0.4, 0.62, 0), 0.26, 0.3, 0.26],
	[Vector3(0.66, 0.66, 0), 0.24, 0.28, 0.23],
	[Vector3(0.86, 0.76, 0), 0.2, 0.23, 0.19],
	[Vector3(1.0, 0.94, 0), 0.16, 0.18, 0.16],
	[Vector3(1.07, 1.14, 0), 0.145, 0.15, 0.145],
	[Vector3(1.1, 1.3, 0), 0.15, 0.15, 0.15],
	[Vector3(1.11, 1.4, 0), 0.01, 0.01, 0.01],
]
# Big round skull, then the long heavy muzzle
const CAMEL_HEAD := [
	[Vector3(0.98, 1.44, 0), 0.01, 0.01, 0.01],
	[Vector3(1.0, 1.44, 0), 0.12, 0.12, 0.13],
	[Vector3(1.08, 1.45, 0), 0.2, 0.17, 0.2],
	[Vector3(1.2, 1.45, 0), 0.21, 0.17, 0.2],
	[Vector3(1.32, 1.43, 0), 0.16, 0.15, 0.16],
	[Vector3(1.44, 1.4, 0), 0.14, 0.15, 0.15],
	[Vector3(1.54, 1.38, 0), 0.14, 0.16, 0.155],
	[Vector3(1.62, 1.37, 0), 0.11, 0.13, 0.12],
	[Vector3(1.66, 1.37, 0), 0.01, 0.01, 0.01],
]
# The blanket hangs down each flank from just below the hump's shoulders
const CAMEL_RIDGE := 0.4
const CLOTH_ARCS := [[-0.45, 0.8], [PI - 0.8, PI + 0.45]]

# `rings` with `sub` smooth (Catmull-Rom) steps between each pair, so a few hand-set
# rings loft without facets
static func _resample(rings: Array, sub: int) -> Array:
	var out := []
	var n := rings.size()
	for i in n - 1:
		var pre: Array = rings[maxi(i - 1, 0)]
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		var post: Array = rings[mini(i + 2, n - 1)]
		for j in sub:
			var t := j / float(sub)
			var r := [a[0].cubic_interpolate(b[0], pre[0], post[0], t)]
			for k in range(1, 4):
				r.append(cubic_interpolate(a[k], b[k], pre[k], post[k], t))
			out.append(r)
	out.append(rings[n - 1])
	return out

# A tube lofted through `rings` (see CAMEL_BODY), smooth-shaded. `arcs` limits it to
# angle ranges round the spine (0 is +Z, PI/2 the upper side), `grow` pads it outward,
# `ridge` narrows the upper side toward a spine (a camel's back is narrower than its belly)
static func _loft(rings: Array, arcs: Array = [[0.0, TAU]], grow := 0.0, ridge := 0.0, seg := 18) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := rings.size()
	var verts := 0
	for arc: Array in arcs:
		var closed: bool = arc[1] - arc[0] >= TAU - 0.001
		var cols: int = seg if closed else maxi(2, ceili(seg * (arc[1] - arc[0]) / TAU) + 1)
		var first := verts
		for i in n:
			var r: Array = rings[i]
			var t: Vector3 = (rings[mini(i + 1, n - 1)][0] - rings[maxi(i - 1, 0)][0]).normalized()
			var up := Vector3(-t.y, t.x, 0.0)
			for k in cols:
				var a: float = arc[0] + (arc[1] - arc[0]) * k / float(cols if closed else cols - 1)
				var s := sin(a)
				var h: float = (r[1] if s > 0.0 else r[2]) + grow
				var w: float = r[3] * (1.0 - ridge * maxf(s, 0.0)) + grow
				st.add_vertex(r[0] + up * s * h + Vector3.BACK * cos(a) * w)
			verts += cols
		for i in n - 1:
			for k in (cols if closed else cols - 1):
				var a0 := first + i * cols + k
				var a1 := first + i * cols + (k + 1) % cols
				for idx: int in [a0, a1 + cols, a0 + cols, a0, a1, a1 + cols]:
					st.add_index(idx)
	st.generate_normals()
	return st.commit()

# Fire ring: blackened stones, crossed logs, embers; the flame and its light come up
# at night with the torches (DayLight, group "torches"), smoke all day
func _campfire(c: Vector3) -> void:
	for i in 9:
		var a := i * TAU / 9.0 + _rng.randf_range(-0.1, 0.1)
		_add("block", Transform3D(Basis(Vector3.UP, -a) * Basis.from_scale(Vector3(0.34, 0.24, 0.3)), c + Vector3(cos(a) * 0.72, 0.12, sin(a) * 0.72)), _vary(ROCK_COLOR, 0.05).darkened(0.3))
	_add("patch", Transform3D(Basis.from_scale(Vector3(1.3, 1.0, 1.3)), c + Vector3(0, 0.11, 0)), Color(0.14, 0.11, 0.09))
	for i in 4:
		var a := i * PI / 4.0 + 0.3
		var log_b := Basis(Vector3.UP, a) * Basis(Vector3.BACK, 0.22)
		_add("timber", Transform3D(log_b * Basis.from_scale(Vector3(0.9, 0.12, 0.12)), c + Vector3(0, 0.2, 0)), Color(0.22, 0.15, 0.10))
	_add("ember", Transform3D(Basis.from_scale(Vector3(0.55, 0.12, 0.55)), c + Vector3(0, 0.16, 0)), Color(1.0, 0.45, 0.14))
	_smoke(c + Vector3(0, 0.4, 0))
	var torch := Node3D.new()
	torch.position = c + Vector3(0, 0.45, 0)
	torch.add_to_group("torches")
	add_child(torch)
	var flame := MeshInstance3D.new()
	flame.name = "Flame"
	flame.mesh = _sphere(0.3, 0.8, 8, 4)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.62, 0.22)
	flame.material_override = mat
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.visible = false
	torch.add_child(flame)
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = Color(1.0, 0.66, 0.38)
	light.omni_range = 9.0
	light.omni_attenuation = 1.3
	light.light_energy = 0.0
	light.position.y = 0.5
	torch.add_child(light)

# Crossbar on two forked posts, spears leaning on it, round shields propped below
func _spear_rack(c: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	for sx: float in [-0.9, 0.9]:
		_add("timber", Transform3D(b * Basis.from_scale(Vector3(0.1, 1.5, 0.1)), c + b * Vector3(sx, 0.75, 0)), _vary(BEAM_COLOR, 0.04))
	_add("timber", Transform3D(b * Basis.from_scale(Vector3(2.0, 0.09, 0.09)), c + b * Vector3(0, 1.45, 0)), _vary(BEAM_COLOR, 0.04).lightened(0.05))
	for i in 5:
		_spear(c + b * Vector3(-0.7 + i * 0.35, 0, -0.35), b * Basis(Vector3.RIGHT, 0.22))
	for sx: float in [-0.45, 0.4]:
		var shield := b * Basis(Vector3.RIGHT, PI * 0.5 - 0.3)
		_add("drum", Transform3D(shield * Basis.from_scale(Vector3(0.75, 0.08, 0.75)), c + b * Vector3(sx, 0.38, 0.32)), OXBLOOD.lightened(0.08))
		_add("drum", Transform3D(shield * Basis.from_scale(Vector3(0.2, 0.12, 0.2)), c + b * Vector3(sx, 0.39, 0.35)), BRONZE)

# A spear standing (on `basis`, its lean) with its foot at `at`: shaft and bronze head
func _spear(at: Vector3, basis: Basis) -> void:
	_add("timber", Transform3D(basis * Basis.from_scale(Vector3(0.05, 2.3, 0.05)), at + basis * Vector3(0, 1.15, 0)), Color(0.50, 0.36, 0.22))
	_add("block", Transform3D(basis * Basis.from_scale(Vector3(0.1, 0.26, 0.05)), at + basis * Vector3(0, 2.38, 0)), BRONZE)

# The enemy's standard: tall pole, crossbar, oxblood cloth with a bronze disc
func _standard(at: Vector3, cloth: Color) -> void:
	_add("timber", Transform3D(Basis.from_scale(Vector3(0.14, 4.2, 0.14)), at + Vector3(0, 2.1, 0)), _vary(BEAM_COLOR, 0.03).darkened(0.1))
	_add("timber", Transform3D(Basis.from_scale(Vector3(1.3, 0.1, 0.1)), at + Vector3(0.1, 4.0, 0.06)), _vary(BEAM_COLOR, 0.03))
	_add("block", Transform3D(Basis.from_scale(Vector3(1.15, 1.6, 0.05)), at + Vector3(0.1, 3.15, 0.1)), cloth)
	for dx: float in [-0.29, 0.0, 0.29]:
		_add("block", Transform3D(Basis.from_scale(Vector3(0.22, 0.3, 0.05)), at + Vector3(0.1 + dx, 2.25, 0.1)), cloth.darkened(0.1))
	_add("drum", Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(0.55, 0.04, 0.55)), at + Vector3(0.1, 3.25, 0.14)), BRONZE)
	_add("block", Transform3D(Basis.from_scale(Vector3(0.14, 0.3, 0.14)), at + Vector3(0, 4.35, 0)), BRONZE)

func _firewood(c: Vector3) -> void:
	for i in 7:
		var log_b := Basis(Vector3.BACK, PI * 0.5)
		_add("trunk", Transform3D(log_b * Basis.from_scale(Vector3(0.75, 1.3, 0.75)), c + Vector3(0, 0.1 + (i / 3) * 0.19, -0.3 + (i % 3) * 0.22 + (i / 3) * 0.1)), _vary(OLIVE_TRUNK, 0.05))

# Grain sack: a lumpy bag, the neck tied off
func _sack(at: Vector3) -> void:
	var col := _vary(Palette.UNDYED, 0.04).darkened(0.08)
	_add("blob", Transform3D(_yaw().scaled(Vector3(0.5, 0.55, 0.45)), at + Vector3(0, 0.3, 0)), col)
	_add("drum", Transform3D(Basis.from_scale(Vector3(0.16, 0.12, 0.16)), at + Vector3(0, 0.6, 0)), col.darkened(0.12))

# A taut rope from `a` down to a peg at `b`
func _rope(a: Vector3, b: Vector3) -> void:
	var dir := (b - a).normalized()
	var rot := Basis(Quaternion(Vector3.RIGHT, dir))
	_add("timber", Transform3D(rot.scaled_local(Vector3(a.distance_to(b), 0.025, 0.025)), (a + b) * 0.5), Color(0.72, 0.62, 0.46))
	_add("timber", Transform3D(Basis.from_scale(Vector3(0.06, 0.2, 0.06)), b + Vector3(0, 0.08, 0)), BEAM_COLOR)

## Slow smoke going up (a cook fire, an oven, a smouldering heap)
func _smoke(at: Vector3, dark := false) -> void:
	var p := CPUParticles3D.new()
	p.amount = 10
	p.lifetime = 4.0
	p.direction = Vector3.UP
	p.spread = 12.0
	p.gravity = Vector3(0.25, 0.35, 0.1)
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.6
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.4
	p.scale_amount_curve = DustFx.grow_curve()
	var c := Color(0.35, 0.33, 0.32) if dark else Color(0.85, 0.82, 0.78)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(c, 0.0))
	ramp.add_point(0.2, Color(c, 0.35))
	ramp.set_color(1, Color(c, 0.0))
	p.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	quad.material = DustFx.material()
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = at
	add_child(p)

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
	_well(WELL_POS)

# The city well: a ring of cut stones in two courses, dark water well down inside, a
# timber frame with a bucket on its rope, and a stone trough beside it. No RNG draws
# (the city layout after it is seeded).
func _well(c: Vector3) -> void:
	const N := 10
	const R := 0.72
	for course in 2:
		for i in N:
			var a := TAU * (i + course * 0.5) / N
			var tint := 0.03 * sin(i * 2.3 + course)
			_add("block", Transform3D(Basis(Vector3.UP, -a).scaled_local(Vector3(0.36, 0.3, 0.46)),
				c + Vector3(cos(a) * R, 0.15 + course * 0.31, sin(a) * R)), Palette.WALL_STONE.darkened(0.06 + tint))
	# Coping stones round the lip, a shade lighter
	for i in N:
		var a := TAU * (i + 0.25) / N
		_add("block", Transform3D(Basis(Vector3.UP, -a).scaled_local(Vector3(0.4, 0.1, 0.5)),
			c + Vector3(cos(a) * R, 0.69, sin(a) * R)), Palette.WALL_STONE.lightened(0.04))
	# Dark shaft, water a way down
	_add("drum", Transform3D(Basis.from_scale(Vector3(1.0, 0.5, 1.0)), c + Vector3(0, 0.36, 0)), Color(0.16, 0.13, 0.11))
	_add("drum", Transform3D(Basis.from_scale(Vector3(0.98, 0.02, 0.98)), c + Vector3(0, 0.5, 0)), WATER_COLOR.darkened(0.35))
	# Frame: two posts, a crossbeam, the bucket hanging on its rope
	for sx: float in [-1.0, 1.0]:
		_add("timber", Transform3D(Basis.from_scale(Vector3(0.14, 1.9, 0.14)), c + Vector3(sx * 0.95, 0.95, 0)), BEAM_COLOR)
	_add("timber", Transform3D(Basis.from_scale(Vector3(2.2, 0.13, 0.13)), c + Vector3(0, 1.86, 0)), BEAM_COLOR.lightened(0.05))
	_add("block", Transform3D(Basis.from_scale(Vector3(0.03, 0.62, 0.03)), c + Vector3(0.15, 1.5, 0)), Color(0.72, 0.62, 0.44))
	_add("drum", Transform3D(Basis.from_scale(Vector3(0.28, 0.24, 0.28)), c + Vector3(0.15, 1.1, 0)), BEAM_COLOR.darkened(0.1))
	# Trough for the animals: a hollowed stone — floor, two long sides, two ends — with
	# the water set down inside (not flush with the rim, where the two would flicker)
	var t := c + Vector3(1.75, 0.0, 0.45)
	var tc := Palette.WALL_STONE.darkened(0.08)
	_add("block", Transform3D(Basis.from_scale(Vector3(1.5, 0.2, 0.55)), t + Vector3(0, 0.1, 0)), tc)
	for sz: float in [-1.0, 1.0]:
		_add("block", Transform3D(Basis.from_scale(Vector3(1.5, 0.22, 0.1)), t + Vector3(0, 0.3, sz * 0.225)), tc)
	for sx: float in [-1.0, 1.0]:
		_add("block", Transform3D(Basis.from_scale(Vector3(0.1, 0.22, 0.35)), t + Vector3(sx * 0.7, 0.3, 0)), tc)
	_add("block", Transform3D(Basis.from_scale(Vector3(1.3, 0.04, 0.36)), t + Vector3(0, 0.3, 0)), WATER_COLOR)

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
	_roof(c, w, d, h, tint)
	_dress_walls(c, w, h, d)
	_plaster(c, w, h, d, tint)
	var top := h
	var upper := false
	var ux := 0.0
	var uw := 0.0
	# Upper room on part of the roof
	if _rng.randf() < 0.3:
		upper = true
		uw = w * _rng.randf_range(0.4, 0.55)
		var ud := d * 0.6
		var uh := _rng.randf_range(1.6, 2.0)
		ux = (w - uw) * 0.5 * (1.0 if _rng.randf() < 0.5 else -1.0)
		_add("block", Transform3D(Basis.from_scale(Vector3(uw, uh, ud)), c + Vector3(ux, h + uh * 0.5, 0)), tint.lightened(0.03))
		_roof(c + Vector3(ux, h, 0), uw, ud, uh, tint.lightened(0.03))
		_add("opening", Transform3D(Basis.from_scale(Vector3(0.06, 0.4, 0.4)), c + Vector3(ux + uw * 0.5 + 0.02, h + uh * 0.6, 0)), OPENING)
		_lamp_spots.append(Transform3D(Basis.from_scale(Vector3(0.02, 0.32, 0.32)), c + Vector3(ux + uw * 0.5 + 0.055, h + uh * 0.6, 0)))
		top = h + uh
	# Door on the street face; north faces are the ones the camera sees
	var face := -1.0 if faces_north else 1.0
	var door_x := _rng.randf_range(-w * 0.25, w * 0.25)
	_door(c + Vector3(door_x, 0, face * d * 0.5), face)
	_window(c + Vector3(w * 0.5, h * 0.62, _rng.randf_range(-d * 0.2, d * 0.2)))
	# Rug or cloth laid out on the roof to dry
	var rug_at := Vector3.INF
	var rug_half := Vector2.ZERO
	if _rng.randf() < 0.45:
		var rw := minf(w * 0.5, _rng.randf_range(1.2, 2.0))
		var rd := minf(d * 0.5, _rng.randf_range(0.9, 1.5))
		rug_at = c + Vector3(_rng.randf_range(-w * 0.2, w * 0.2), h + 0.1, _rng.randf_range(-d * 0.15, d * 0.15))
		rug_half = Vector2(rw, rd) * 0.5
		# Not tucked under the upper room: over to the open half of the roof
		if upper and absf(rug_at.x - (c.x + ux)) < uw * 0.5 + rug_half.x:
			rug_at.x = c.x - signf(ux) * uw * 0.5   # the middle of the open part
		_rug(rug_at, rw, rd, _yaw_small(), CLOTH_COLORS[_rng.randi() % CLOTH_COLORS.size()])
	# Cloth awning over the door, on two poles
	if _rng.randf() < 0.55:
		_canopy(c + Vector3(door_x, 0, face * (d * 0.5 + 0.65)), 1.8, 1.2, face, AWNINGS[_rng.randi() % AWNINGS.size()])
	# Jars up on the roof
	if _rng.randf() < 0.45:
		for i in _rng.randi_range(1, 3):
			var jar := c + Vector3(_rng.randf_range(-w * 0.35, w * 0.35), h + 0.08, _rng.randf_range(-d * 0.3, d * 0.3))
			_jar(jar, _rng.randf_range(0.8, 1.1) * 0.7)
	# Water jars by the door
	if _rng.randf() < 0.4:
		for i in _rng.randi_range(1, 3):
			var jar := c + Vector3(door_x + 0.7 + i * 0.4, 0.1, face * (d * 0.5 + 0.35))
			_jar(jar, _rng.randf_range(0.8, 1.1) * 0.75)
	# Details from their own RNG (the layout's draws stay as they were)
	if faces_north and not upper and w > 3.6 and _deco.randf() < 0.6:
		# Up the back wall, the +z face the camera sees (the door is round the front)
		_stair(body, c + Vector3(0, 0, d * 0.5), w, h, 1.0 if _deco.randf() < 0.5 else -1.0)
	_roof_life(c, w, d, h, rug_at, rug_half, upper, ux, uw)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, top, d)
	shape.shape = box
	shape.position = c + Vector3(0, top * 0.5, 0)
	body.add_child(shape)

# Flat roof: packed mud over the beams, a shade warmer than the lime-washed walls, inside
# a raised parapet (Deut. 22:8)
func _roof(c: Vector3, w: float, d: float, h: float, tint: Color) -> void:
	var mud := tint.lerp(Color(0.72, 0.60, 0.45), 0.45)
	_add("block", Transform3D(Basis.from_scale(Vector3(w - 0.1, 0.1, d - 0.1)), c + Vector3(0, h + 0.03, 0)), mud)
	var lip := tint.darkened(0.04)
	const T := 0.2
	for sz: float in [-1.0, 1.0]:
		_add("block", Transform3D(Basis.from_scale(Vector3(w + 0.14, 0.34, T)), c + Vector3(0, h + 0.1, sz * (d * 0.5 + 0.07 - T * 0.5))), lip)
	for sx: float in [-1.0, 1.0]:
		_add("block", Transform3D(Basis.from_scale(Vector3(T, 0.34, d - 0.26)), c + Vector3(sx * (w * 0.5 + 0.07 - T * 0.5), h + 0.1, 0)), lip)

# Rain splashes mud up the foot of the lime-washed walls the camera sees
func _plaster(c: Vector3, w: float, h: float, d: float, tint: Color) -> void:
	var splash := tint.lerp(Color(0.62, 0.50, 0.36), 0.35)
	_add("wash", Transform3D(Basis.from_scale(Vector3(w + 0.02, 0.26, 0.02)), c + Vector3(0, 0.55, d * 0.5 + 0.01)), splash)
	_add("wash", Transform3D(Basis.from_scale(Vector3(0.02, 0.26, d + 0.02)), c + Vector3(w * 0.5 + 0.01, 0.55, 0)), splash)

# Stone steps built against the +z face, from the ground at one end up to the roof at
# the `sx` corner
func _stair(body: StaticBody3D, face_mid: Vector3, w: float, h: float, sx: float) -> void:
	var run := minf(w * 0.55, h * 1.05)
	var n := ceili(h / 0.3)
	var step := run / n
	var top_x := sx * (w * 0.5 - 0.1)   # outer edge of the top step, at the corner
	var col := FOOTING.darkened(_deco.randf_range(0.0, 0.05))
	for i in n:
		var sh := h * float(i + 1) / n
		var x := top_x - sx * (run - (i + 0.5) * step)
		_add("block", Transform3D(Basis.from_scale(Vector3(step + 0.02, sh, 0.72)), face_mid + Vector3(x, sh * 0.5, 0.36)), col.darkened(0.04 * (i % 2)))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(run, h * 0.6, 0.72)
	shape.shape = box
	shape.position = face_mid + Vector3(top_x - sx * run * 0.5, h * 0.3, 0.36)
	body.add_child(shape)

# What people keep on a roof: a stone roller for the mud, a mat of figs drying, a
# shelter of palm fronds
func _roof_life(c: Vector3, w: float, d: float, h: float, rug_at: Vector3, rug_half: Vector2, upper: bool, ux: float, uw: float) -> void:
	var spots: Array[Vector3] = []
	for i in 6:
		var p := c + Vector3(_deco.randf_range(-w * 0.32, w * 0.32), h + 0.08, _deco.randf_range(-d * 0.26, d * 0.26))
		if rug_at != Vector3.INF and absf(p.x - rug_at.x) < rug_half.x + 0.8 and absf(p.z - rug_at.z) < rug_half.y + 0.7:
			continue
		if upper and absf(p.x - (c.x + ux)) < uw * 0.5 + 0.6:
			continue
		var clear := true
		for q: Vector3 in spots:
			if p.distance_to(q) < 1.3:
				clear = false
		if clear:
			spots.append(p)
	var k := 0
	if spots.size() > k and _deco.randf() < 0.45:
		# Stone roller, left where the roof was last rolled
		var p := spots[k]
		k += 1
		var roll := Basis(Vector3.UP, _deco.randf() * TAU) * Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(0.36, 0.55, 0.36))
		_add("drum", Transform3D(roll, p + Vector3(0, 0.18, 0)), ROCK_COLOR.darkened(0.18 + _deco.randf_range(0.0, 0.08)))
	if spots.size() > k and _deco.randf() < 0.5:
		# A reed mat with fruit laid out on it to dry
		var p := spots[k]
		k += 1
		var yaw := Basis(Vector3.UP, _deco.randf_range(-0.15, 0.15))
		_add("slab", Transform3D(yaw * Basis.from_scale(Vector3(1.1, 0.03, 0.8)), p), Color(0.70, 0.58, 0.36))
		var fruit: Color = [Color(0.40, 0.24, 0.26), Color(0.78, 0.60, 0.30), Color(0.52, 0.40, 0.20)][_deco.randi() % 3]
		for i in 10:
			var off := yaw * Vector3(_deco.randf_range(-0.42, 0.42), 0.05, _deco.randf_range(-0.28, 0.28))
			_add("pebble", Transform3D(Basis.from_scale(Vector3.ONE * 0.8), p + off), fruit.lightened(_deco.randf_range(0.0, 0.08)))
	if spots.size() > k and w > 4.0 and _deco.randf() < 0.3:
		# A shelter of poles roofed with dried palm fronds, for the heat of the day
		var p := spots[k]
		k += 1
		for dx: float in [-0.6, 0.6]:
			for dz: float in [-0.45, 0.45]:
				_add("timber", Transform3D(Basis.from_scale(Vector3(0.08, 1.7, 0.08)), p + Vector3(dx, 0.85, dz)), BEAM_COLOR)
		for dz: float in [-0.45, 0.45]:
			_add("timber", Transform3D(Basis.from_scale(Vector3(1.4, 0.08, 0.08)), p + Vector3(0, 1.68, dz)), BEAM_COLOR.darkened(0.08))
		for i in 7:
			var frond := Basis(Vector3.UP, _deco.randf_range(-0.12, 0.12)) * Basis.from_scale(Vector3(0.24, 0.05, 1.3))
			_add("timber", Transform3D(frond, p + Vector3(-0.63 + i * 0.21, 1.74, 0)), Color(0.64, 0.55, 0.33).darkened(_deco.randf_range(0.0, 0.12)))

# A woven rug laid out flat: dyed ground, a band of another dye near each end, a pale
# fringe, a lozenge in the middle
func _rug(at: Vector3, w: float, d: float, yaw: Basis, cloth: Color) -> void:
	cloth = cloth.lerp(Palette.UNDYED, 0.12)
	_add("block", Transform3D(yaw * Basis.from_scale(Vector3(w, 0.04, d)), at), cloth)
	var band: Color = CLOTH_COLORS[_deco.randi() % CLOTH_COLORS.size()]
	if band.is_equal_approx(cloth):
		band = Palette.UNDYED
	for sx: float in [-1.0, 1.0]:
		_add("block", Transform3D(yaw * Basis.from_scale(Vector3(0.12, 0.045, d)), at + yaw * Vector3(sx * w * 0.32, 0, 0)), band)
		_add("block", Transform3D(yaw * Basis.from_scale(Vector3(0.1, 0.03, d - 0.08)), at + yaw * Vector3(sx * (w * 0.5 + 0.05), -0.005, 0)), Palette.UNDYED)
	_add("block", Transform3D(yaw * Basis(Vector3.UP, PI * 0.25) * Basis.from_scale(Vector3(d * 0.32, 0.045, d * 0.32)), at), band.lerp(cloth, 0.3))

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
	_lamp_spots.append(Transform3D(Basis.from_scale(Vector3(0.02, 0.4, 0.4)), at + Vector3(0.065, 0, 0)))
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
	# Outboard of the watchmen's lookouts (Watchmen.STAND_X), clear of their legs and ladder
	for x: float in [-23.6, 23.4]:
		_banner(Vector3(x, 0, 1.6))

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
	_valance(c + Vector3(0, 2.39, 0), 3.4, 3.1, Palette.INDIGO.darkened(0.12), tan(0.16))
	for i in 3:
		_jar(c + Vector3(1.9 + (i % 2) * 0.45, 0.0, -0.6 + i * 0.55), _rng.randf_range(1.0, 1.3))

# Scalloped cloth edge hanging from a w×d ridged canopy: `c.y` is the eave height; on the
# gable ends the tabs climb with the roof (`slope` per metre in toward the ridge) so they
# hang from the cloth, not from the air under it
func _valance(c: Vector3, w: float, d: float, cloth: Color, slope := 0.0) -> void:
	for side: float in [-1.0, 1.0]:
		var n := int(w / 0.34)
		for i in n:
			var x := -w * 0.5 + (i + 0.5) * w / n
			var h := 0.26 if i % 2 == 0 else 0.2
			_add("block", Transform3D(Basis.from_scale(Vector3(w / n - 0.05, h, 0.04)), c + Vector3(x, 0.02 - h * 0.5, side * d * 0.5)), cloth)
		var m := int(d / 0.34)
		for i in m:
			var z := -d * 0.5 + (i + 0.5) * d / m
			var h := 0.26 if i % 2 == 0 else 0.2
			var top := (d * 0.5 - absf(z)) * slope
			_add("block", Transform3D(Basis.from_scale(Vector3(0.04, h, d / m - 0.05)), c + Vector3(side * w * 0.5, top + 0.02 - h * 0.5, z)), cloth)

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
	# Shafts: from under the front of the bed down to the ground, where the ox would stand
	for sz: float in [-0.42, 0.42]:
		var from := c + b * Vector3(0.7, 0.55, sz)
		var to := c + b * Vector3(2.35, 0.06, sz * 0.8)
		var dir := (to - from).normalized()
		var rot := Basis(Quaternion(Vector3.RIGHT, dir))
		_add("timber", Transform3D(rot.scaled_local(Vector3(from.distance_to(to), 0.09, 0.09)), (from + to) * 0.5), _vary(BEAM_COLOR, 0.04))
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
	# Swallow-tail: two tails flush with the cloth's edges, a notch between. Thinner than
	# the cloth and tucked up inside it so the join shows no seam (foot at y 2.35)
	for s: float in [-1.0, 1.0]:
		_add("block", Transform3D(Basis.from_scale(Vector3(0.04, 0.46, 0.44)), at + Vector3(0.08, 2.2, 0.58 + s * 0.305)), Palette.INDIGO)
	# Tower emblem, a stepped silhouette in undyed wool
	var e := at + Vector3(0.11, 3.2, 0.58)
	_add("block", Transform3D(Basis.from_scale(Vector3(0.03, 0.55, 0.36)), e), Palette.UNDYED)
	for dz: float in [-0.13, 0.0, 0.13]:
		_add("block", Transform3D(Basis.from_scale(Vector3(0.03, 0.12, 0.08)), e + Vector3(0, 0.33, dz)), Palette.UNDYED)
	_add("block", Transform3D(Basis.from_scale(Vector3(0.035, 0.2, 0.1)), e + Vector3(0.002, -0.17, 0)), Palette.INDIGO)

# ── Batching ──────────────────────────────────────────────────

const CAMP_CLEARED := ["pebble", "tuft", "tuft_b", "bush", "boulder", "chip"]

func _add(kind: String, xf: Transform3D, color: Color) -> void:
	# Ground cover stays out of the enemy camps (it's placed before them, from the layout RNG)
	if kind in CAMP_CLEARED:
		for r: Rect2 in CAMP_CLEAR:
			if r.has_point(Vector2(xf.origin.x, xf.origin.z)):
				return
	if not _batches.has(kind):
		_batches[kind] = [[] as Array[Transform3D], [] as Array[Color]]
	_batches[kind][0].append(xf)
	_batches[kind][1].append(color)

func _flush() -> void:
	for kind: String in _batches:
		var mmi := _multimesh(_mesh_for(kind), _batches[kind][0], _batches[kind][1], _material_for(kind))
		# Ground-hugging bits: shadows cost more than they add
		if kind in ["pebble", "patch", "slab", "tuft", "tuft_b", "bed", "chip", "ember", "wash"]:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_batches.clear()
	_build_lamps()

func _build_lamps() -> void:
	_lamps = null
	_halos = null
	if _lamp_spots.is_empty():
		return
	# Own RNG: the layout's _rng must not shift
	var rng := RandomNumberGenerator.new()
	rng.seed = 4021 + _lamp_spots.size()
	var order := _lamp_spots.duplicate()
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Transform3D = order[i]
		order[i] = order[j]
		order[j] = t
	var colors: Array[Color] = []
	var halo_xf: Array[Transform3D] = []
	var halo_colors: Array[Color] = []
	for xf: Transform3D in order:
		colors.append(LAMPLIGHT.darkened(rng.randf_range(0.0, 0.15)))
		# A quad in the wall's plane (+x face), a little proud of it
		halo_xf.append(Transform3D(Basis(Vector3.UP, PI * 0.5).scaled(Vector3.ONE * xf.basis.get_scale().y * 3.2), xf.origin + Vector3(0.04, 0, 0)))
		halo_colors.append(Color(LAMPLIGHT, rng.randf_range(0.35, 0.5)))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	var mmi := _multimesh(Chunky.unit_block(), order, colors, mat)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lamps = mmi.multimesh
	_lamps.visible_instance_count = 0
	var halo := _multimesh(QuadMesh.new(), halo_xf, halo_colors, _lamp_halo_material())
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halos = halo.multimesh
	_halos.visible_instance_count = 0
	_lamp_spots.clear()
	add_to_group("window_lamps")

static func _lamp_halo_material() -> StandardMaterial3D:
	if _halo_mat:
		return _halo_mat
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	_halo_mat = StandardMaterial3D.new()
	_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_halo_mat.vertex_color_use_as_albedo = true
	_halo_mat.albedo_texture = tex
	_halo_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _halo_mat

## DayLight: light `share` (0 … 1) of the windows
func set_lamps(share: float) -> void:
	if _lamps:
		_lamps.visible_instance_count = roundi(share * _lamps.instance_count)
		_halos.visible_instance_count = _lamps.visible_instance_count

static var _grass_mat: ShaderMaterial
static var _ember_mat: StandardMaterial3D

# Glowing coals: unlit, so they read as heat by day and night
static func _ember_material() -> StandardMaterial3D:
	if not _ember_mat:
		_ember_mat = StandardMaterial3D.new()
		_ember_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ember_mat.vertex_color_use_as_albedo = true
		_ember_mat.vertex_color_is_srgb = true
	return _ember_mat

static func _grass_material() -> ShaderMaterial:
	if not _grass_mat:
		_grass_mat = ShaderMaterial.new()
		_grass_mat.shader = preload("res://assets/shaders/grass.gdshader")
	return _grass_mat

# Chunky look: bevelled blocks, faceted foliage and rock
func _material_for(kind: String) -> Material:
	match kind:
		"block", "opening": return Chunky.material(0.06)
		"chip":             return Chunky.material(0.03, false, 0.3)
		"timber":           return Chunky.wood_material(0.025)
		"slab":             return Chunky.material(0.1, false, 0.28)
		"bush", "leaf", "olive_sprig", "myrtle_sprig", "palm_frond": return Chunky.foliage_material()
		"tuft", "tuft_b":   return _grass_material()
		"boulder", "pebble": return Chunky.material(0.0, true, 0.0)
	return Chunky.material(0.0, false, 0.0)

func _mesh_for(kind: String) -> Mesh:
	match kind:
		"block", "slab", "opening", "chip", "timber": return Chunky.unit_block()
		"pebble":  return _sphere(0.13, 0.10, 5, 2)
		"tuft":    return _tuft_mesh(7)
		"tuft_b":  return _tuft_mesh(31)
		"bush":    return _sphere(0.42, 0.62, 12, 6)
		"leaf":    return _sphere(0.6, 1.0, 14, 7)
		"olive_sprig": return _sprig_mesh(9)
		"myrtle_sprig": return _sprig_mesh(7)
		"blossom": return _sphere(0.085, 0.05, 6, 2)
		"palm_frond": return _palm_frond_mesh()
		"palm_scale": return Chunky.unit_block()
		"date": return _sphere(0.5, 1.0, 8, 4)
		"boulder": return _sphere(0.6, 0.9, 6, 3)
		"jar":     return _sphere(0.22, 0.5, 8, 4)
		"blob":    return _sphere(0.5, 1.0, 12, 6)
		"ember":   return _sphere(0.5, 1.0, 8, 3)
		"trunk":   return _cylinder(0.12, 0.2, 1.0, 7)
		"drum":    return _cylinder(0.5, 0.5, 1.0, 12)
		"camel_body":  return _loft(_resample(CAMEL_BODY, 3), [[0.0, TAU]], 0.0, CAMEL_RIDGE)
		# Pale undersides: the same lofts, just proud, over the lower arc only
		"camel_belly": return _loft(_resample(CAMEL_BODY, 3), [[PI + 0.3, TAU - 0.3]], 0.006, CAMEL_RIDGE)
		"camel_neck":  return _loft(_resample(CAMEL_NECK, 3))
		"camel_throat": return _loft(_resample(CAMEL_NECK, 3), [[PI + 0.55, TAU - 0.55]], 0.006)
		"camel_head":  return _loft(_resample(CAMEL_HEAD, 3))
		"camel_muzzle": return _loft(_resample(CAMEL_HEAD, 3).slice(15, 25), [[0.0, TAU]], 0.006)
		# Rings 4..9 and 6..7 of the body, after the resample
		"camel_cloth": return _loft(_resample(CAMEL_BODY, 3).slice(12, 28), CLOTH_ARCS, 0.025, CAMEL_RIDGE)
		"camel_band":  return _loft(_resample(CAMEL_BODY, 3).slice(18, 22), CLOTH_ARCS, 0.04, CAMEL_RIDGE)
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
# Small pointed leaves on fine twigs. One mesh instance is a complete sprig, so the
# crowns stay detailed without creating a node or draw call for every leaf.
static func _sprig_mesh(count: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in count:
		var a := TAU * i / count
		var d := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-sin(a), 0, cos(a))
		var root := d * 0.13 + Vector3(0, 0.03 * (i % 3), 0)
		var mid := d * 0.45 + Vector3(0, 0.07 + 0.04 * (i % 2), 0)
		var tip := d * 0.72 + Vector3(0, 0.03, 0)
		var left := mid - side * 0.12
		var right := mid + side * 0.12
		for p in [root, left, tip, root, tip, right, tip, left, root, right, tip, root]:
			st.add_vertex(p)
	st.generate_normals()
	return st.commit()

# A curved midrib with paired, narrow leaflets. The downward outer arc makes the
# crown legible from the game's elevated camera as well as at character height.
static func _palm_frond_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 14:
		var t := i / 14.0
		var next := (i + 1) / 14.0
		var a := Vector3(0.1 + 2.65 * t, 0.15 + 0.42 * sin(t * PI) - 0.95 * t * t, 0)
		var b := Vector3(0.1 + 2.65 * next, 0.15 + 0.42 * sin(next * PI) - 0.95 * next * next, 0)
		var width := 0.025 * (1.0 - t * 0.7)
		for p in [a + Vector3(0, 0, width), b + Vector3(0, 0, width), b - Vector3(0, 0, width), a + Vector3(0, 0, width), b - Vector3(0, 0, width), a - Vector3(0, 0, width), b - Vector3(0, 0, width), b + Vector3(0, 0, width), a + Vector3(0, 0, width), a - Vector3(0, 0, width), b - Vector3(0, 0, width), a - Vector3(0, 0, width)]:
			st.add_vertex(p)
	for i in 23:
		var t := 0.07 + i * 0.039
		var x := 0.1 + 2.65 * t
		var y := 0.15 + 0.42 * sin(t * PI) - 0.95 * t * t
		var length := 0.85 * sin(t * PI) + 0.1
		for side in [-1.0, 1.0]:
			var root := Vector3(x, y, 0)
			var shoulder := root + Vector3(0.11, 0.015, side * length * 0.48)
			var tip := root + Vector3(0.24, -0.13, side * length)
			var left := shoulder + Vector3(-0.045, 0, 0)
			var right := shoulder + Vector3(0.045, 0, 0)
			for p in [root, left, tip, root, tip, right, tip, left, root, right, tip, root]:
				st.add_vertex(p)
	st.generate_normals()
	return st.commit()


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
