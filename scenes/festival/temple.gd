class_name Temple
extends StaticBody3D

# The house of God in the east of the city, for the festival (Neh. 8:16 "in the courts of
# God's house"): the rebuilt temple of Zerubbabel's day — plain dressed stone, not
# Solomon's gold. A walled court on a paved platform, its gate toward the city streets;
# the house at the back of the court on a raised inner pavement, side chambers against
# it, the tall porch before it, and the altar of burnt offering in front with its fire.
# Explore Jerusalem turns the view here so the camera looks from the court's south-west
# (-x, +z): the porch faces +z, the gate side, and nothing tall stands between it and
# the camera. Chunky blocks like the rest of the world; walls, altar and house are
# solid, the court itself open.

const COURT      := Rect2(27.0, 2.6, 16.0, 9.8)    # x, z, width, depth; close by the wall, clear of the houses south
const WALL_H     := 1.4
const WALL_T     := 0.6
const GATE_HALF  := 1.5     # the opening in the south wall, facing the city
const GATE_X     := 31.0
const AXIS_X     := 36.5    # the house, its door and the altar on one line
const HOUSE_Z    := Vector2(3.2, 6.6)   # back and front of the house
const STONE      := Color(0.86, 0.82, 0.74)
const PAVING     := Color(0.80, 0.76, 0.68)
const INNER      := Color(0.88, 0.85, 0.79)
const HOUSE      := Color(0.93, 0.90, 0.83)
const COURSE     := Color(0.84, 0.79, 0.70)
const MORTAR     := Color(0.80, 0.76, 0.68)   # the bed the dressed blocks lie in
const DOORWAY    := Color(0.20, 0.14, 0.09)
const CEDAR      := Color(0.47, 0.30, 0.17)
const BRONZE     := Color(0.60, 0.43, 0.25)
const VEIL       := Palette.MUREX
const ALTAR      := Color(0.70, 0.66, 0.60)
const FIRE       := Color(1.0, 0.6, 0.22)
const FROND      := Color(0.36, 0.52, 0.22)

## Where the altar stands (a priest keeps it)
const ALTAR_AT := Vector3(AXIS_X, 0.0, 10.3)

var _parts := WatchPost._Parts.new()
var _rng := RandomNumberGenerator.new()   # the cutting of the stones: fixed, so the house is the same every visit

func _ready() -> void:
	_rng.seed = 6161
	_court()
	_gate()
	_house()
	_altar(ALTAR_AT)
	add_child(_parts.build(Chunky.material(0.05)))
	_fire(ALTAR_AT + Vector3(0, 1.45, 0))

# The platform, its walls, and the raised inner pavement before the house
func _court() -> void:
	var c := Vector3(COURT.get_center().x, 0.0, COURT.get_center().y)
	var x0 := COURT.position.x
	var x1 := COURT.end.x
	var z0 := COURT.position.y
	var z1 := COURT.end.y
	_parts.add(Vector3(COURT.size.x, 0.16, COURT.size.y), c + Vector3(0, 0.08, 0), PAVING)
	_parts.add(Vector3(COURT.size.x + 0.5, 0.08, COURT.size.y + 0.5), c + Vector3(0, 0.04, 0), PAVING.darkened(0.08))
	_parts.add(Vector3(11.4, 0.08, 8.6), Vector3(AXIS_X, 0.2, COURT.get_center().y - 0.2), INNER)
	_flagstones(COURT, 0.16, PAVING)
	_flagstones(Rect2(AXIS_X - 5.7, COURT.get_center().y - 0.2 - 4.3, 11.4, 8.6), 0.24, INNER)
	# North, west and east walls whole; the south one opened by the gate
	_wall(Vector3(COURT.size.x, WALL_H, WALL_T), Vector3(c.x, 0, z0))
	_wall(Vector3(WALL_T, WALL_H, COURT.size.y), Vector3(x0, 0, c.z))
	_wall(Vector3(WALL_T, WALL_H, COURT.size.y), Vector3(x1, 0, c.z))
	var left := GATE_X - GATE_HALF - x0
	var right := x1 - GATE_X - GATE_HALF
	_wall(Vector3(left, WALL_H, WALL_T), Vector3(x0 + left * 0.5, 0, z1))
	_wall(Vector3(right, WALL_H, WALL_T), Vector3(x1 - right * 0.5, 0, z1))
	# Dressed stone on the faces the camera sees: the south wall's street side, the west wall's
	# outside, the north wall's and the east wall's court sides
	_ashlar(Vector3(x0 + left * 0.5, 0.16, z1 + WALL_T * 0.5), Vector3.BACK, left, 0.0, WALL_H, STONE)
	_ashlar(Vector3(x1 - right * 0.5, 0.16, z1 + WALL_T * 0.5), Vector3.BACK, right, 0.0, WALL_H, STONE)
	_ashlar(Vector3(x0 - WALL_T * 0.5, 0.16, c.z), Vector3.LEFT, COURT.size.y, 0.0, WALL_H, STONE)
	_ashlar(Vector3(c.x, 0.16, z0 + WALL_T * 0.5), Vector3.BACK, COURT.size.x, 0.0, WALL_H, STONE)
	_ashlar(Vector3(x1 - WALL_T * 0.5, 0.16, c.z), Vector3.LEFT, COURT.size.y, 0.0, WALL_H, STONE)
	# Buttresses on the outer faces the city sees
	for x: float in [35.5, 39.5]:
		_parts.add(Vector3(0.5, WALL_H + 0.1, 0.25), Vector3(x, (WALL_H + 0.1) * 0.5, z1 + WALL_T * 0.5 + 0.12), STONE.darkened(0.06))
	for z: float in [z0 + 3.0, z0 + 6.6]:
		_parts.add(Vector3(0.25, WALL_H + 0.1, 0.5), Vector3(x0 - WALL_T * 0.5 - 0.12, (WALL_H + 0.1) * 0.5, z), STONE.darkened(0.06))

# A court wall: dressed stone, a coping along its top and a course near its foot
func _wall(size: Vector3, foot: Vector3) -> void:
	_block(size, foot, STONE.darkened(0.1))   # the bed of mortar the dressed blocks (_ashlar) lie in
	_parts.add(Vector3(size.x + 0.12, 0.14, size.z + 0.12), foot + Vector3(0, size.y + 0.07, 0), STONE.lightened(0.06))

# The gate from the streets: two towers, a cedar lintel over, palm fronds for the feast
func _gate() -> void:
	var z := COURT.end.y
	for sx: float in [-1.0, 1.0]:
		var foot := Vector3(GATE_X + sx * (GATE_HALF + 0.45), 0, z)
		_block(Vector3(0.9, 2.7, 1.1), foot, STONE.darkened(0.12))
		_ashlar(foot + Vector3(0, 0.16, 0.55), Vector3.BACK, 0.9, 0.0, 2.55, STONE)
		_ashlar(foot + Vector3(-0.45, 0.16, 0), Vector3.LEFT, 1.1, 0.0, 2.55, STONE)
		_parts.add(Vector3(1.05, 0.16, 1.25), foot + Vector3(0, 2.78, 0), STONE.lightened(0.06))
		# The cedar leaf folded back into the court, half open, banded with bronze
		var open := 1.2
		var dir := Vector3(-sx * cos(open), 0, -sin(open))
		var yaw := Vector3(0, atan2(-dir.z, dir.x), 0)
		var hinge := Vector3(GATE_X + sx * GATE_HALF, 0.18, z)
		_parts.add(Vector3(1.5, 2.3, 0.1), hinge + dir * 0.75 + Vector3(0, 1.15, 0), CEDAR, yaw)
		for y: float in [0.45, 1.85]:
			_parts.add(Vector3(1.5, 0.12, 0.14), hinge + dir * 0.75 + Vector3(0, y, 0), BRONZE.darkened(0.25), yaw)
		_parts.add(Vector3(0.14, 2.3, 0.16), hinge + Vector3(0, 1.15, 0), BRONZE.darkened(0.3))
		_parts.add(Vector3(0.12, 1.3, 0.12), foot + Vector3(0, 3.3, 0.35), CEDAR)   # a pole for the fronds
		for k in 3:
			var a := -0.7 + k * 0.7
			_parts.add(Vector3(0.12, 0.9, 0.3), foot + Vector3(-sin(a) * 0.35, 4.1, 0.35), FROND, Vector3(0, 0, a))
	_parts.add(Vector3(GATE_HALF * 2.0 + 1.9, 0.36, 0.9), Vector3(GATE_X, 2.55, z), CEDAR)
	_parts.add(Vector3(GATE_HALF * 2.0 + 2.1, 0.14, 1.1), Vector3(GATE_X, 2.8, z), STONE.lightened(0.06))
	# Beam ends under the lintel, and worn threshold stones across the way in
	for k in 7:
		_parts.add(Vector3(0.2, 0.2, 0.5), Vector3(GATE_X - 2.4 + k * 0.8, 2.55, z + 0.5), CEDAR.darkened(0.08))
	for k in 4:
		_parts.add(Vector3(GATE_HALF * 0.5 - 0.04, 0.05, 1.2), Vector3(GATE_X - GATE_HALF + GATE_HALF * 0.25 + k * GATE_HALF * 0.5, 0.18, z), PAVING.darkened(0.04 + 0.025 * (k % 2)))

# The house at the back of the court: the holy place and the most holy behind it,
# chambers a storey lower along its sides, the high porch in front with its doorway
func _house() -> void:
	var depth := HOUSE_Z.y - HOUSE_Z.x
	var foot := Vector3(AXIS_X, 0.24, (HOUSE_Z.x + HOUSE_Z.y) * 0.5)
	var h := 5.6
	var w := 7.0
	_parts.add(Vector3(w + 4.4, 0.3, depth + 0.5), foot, COURSE)   # a plinth under it all
	_block(Vector3(w, h, depth), foot, MORTAR)
	_courses(Vector3(w, h, depth), foot, [1.6, 3.2, 4.8])
	_parts.add(Vector3(w + 0.3, 0.26, depth + 0.3), foot + Vector3(0, h + 0.13, 0), HOUSE.darkened(0.05))
	_merlons(foot + Vector3(0, h + 0.26, 0), w, depth)
	# Its sides, above the chambers; the face on the court is behind the porch
	for sx: float in [-1.0, 1.0]:
		_ashlar(Vector3(foot.x + sx * w * 0.5, foot.y, foot.z), Vector3(sx, 0, 0), depth, 3.4, h, HOUSE)
		_dentils(Vector3(foot.x + sx * (w * 0.5 + 0.15), foot.y, foot.z), Vector3(sx, 0, 0), depth, h - 0.12)
	# Windows high on its sides, above the chambers (1 Kings 6:4)
	for sx: float in [-1.0, 1.0]:
		for dz: float in [-0.9, 0.9]:
			_parts.add(Vector3(0.06, 0.7, 0.34), foot + Vector3(sx * (w * 0.5 + 0.02), 4.3, dz), DOORWAY)
	# Side chambers
	for sx: float in [-1.0, 1.0]:
		var cf := foot + Vector3(sx * (w * 0.5 + 1.0), 0, 0)
		_block(Vector3(2.0, 3.2, depth), cf, MORTAR.darkened(0.03))
		_courses(Vector3(2.0, 3.2, depth), cf, [1.6])
		_parts.add(Vector3(2.2, 0.2, depth + 0.2), cf + Vector3(0, 3.3, 0), HOUSE.darkened(0.07))
		_ashlar(cf + Vector3(sx * 1.0, 0, 0), Vector3(sx, 0, 0), depth, 0.16, 3.2, HOUSE.darkened(0.03))
		_ashlar(cf + Vector3(0, 0, depth * 0.5), Vector3.BACK, 2.0, 0.16, 3.2, HOUSE.darkened(0.03))
		_dentils(cf + Vector3(0, 0, depth * 0.5 + 0.1), Vector3.BACK, 2.0, 3.1)
		for k in 3:
			_parts.add(Vector3(0.06, 0.5, 0.36), cf + Vector3(sx * 1.02, 2.3, -1.0 + k * 1.0), DOORWAY)
	# The porch: wider and taller than the house, its face to the court
	var pd := 1.2
	var pw := w + 1.0
	var ph := 7.0
	var pf := Vector3(AXIS_X, 0.24, HOUSE_Z.y + pd * 0.5)
	var face := HOUSE_Z.y + pd
	_block(Vector3(pw, ph, pd), pf, MORTAR.lightened(0.02))
	_courses(Vector3(pw, ph, pd), pf, [1.6, 5.4])
	_parts.add(Vector3(pw + 0.35, 0.3, pd + 0.35), pf + Vector3(0, ph + 0.15, 0), HOUSE.darkened(0.05))
	_merlons(pf + Vector3(0, ph + 0.3, 0), pw, pd)
	# Dressed ashlar over its face, leaving the doorway bare, and over its two ends; a row of
	# dentils under the cornice all round
	_ashlar(Vector3(pf.x, pf.y, face), Vector3.BACK, pw, 0.16, ph, HOUSE.lightened(0.02), Rect2(-1.6, 0.0, 3.2, 5.2))
	for sx: float in [-1.0, 1.0]:
		_ashlar(Vector3(pf.x + sx * pw * 0.5, pf.y, pf.z), Vector3(sx, 0, 0), pd, 0.16, ph, HOUSE.lightened(0.02))
		_dentils(Vector3(pf.x + sx * (pw * 0.5 + 0.15), pf.y, pf.z), Vector3(sx, 0, 0), pd, ph - 0.12)
	_dentils(Vector3(pf.x, pf.y, face + 0.15), Vector3.BACK, pw, ph - 0.12)
	# Pilasters down its face
	for x: float in [-pw * 0.5 + 0.25, -1.9, 1.9, pw * 0.5 - 0.25]:
		_parts.add(Vector3(0.5, ph - 0.4, 0.14), Vector3(pf.x + x, 0.24 + (ph - 0.4) * 0.5, face + 0.07), HOUSE.lightened(0.04))
	# The doorway: a tall dark opening in a stepped frame, the veil, cedar doors folded back
	var door := Vector3(AXIS_X, 0.24, face)
	_parts.add(Vector3(2.7, 4.6, 0.08), door + Vector3(0, 2.3, 0.04), COURSE)
	_parts.add(Vector3(2.1, 4.0, 0.1), door + Vector3(0, 2.0, 0.06), DOORWAY)
	_parts.add(Vector3(1.7, 3.5, 0.05), door + Vector3(0, 1.75, 0.1), VEIL)
	for sx: float in [-1.0, 1.0]:
		_parts.add(Vector3(0.1, 3.6, 0.9), door + Vector3(sx * 1.25, 1.8, 0.45), CEDAR, Vector3(0, sx * 0.35, 0))
	_parts.add(Vector3(3.1, 0.4, 0.2), door + Vector3(0, 4.75, 0.12), CEDAR)
	# Steps up to the door
	for k in 3:
		var sh := 0.3 - k * 0.1
		_parts.add(Vector3(3.6 + k * 0.6, sh, 0.45), door + Vector3(0, sh * 0.5 - 0.1, 0.25 + k * 0.45), STONE.lightened(0.03))

# Thin darker courses round a block, at the given heights above its foot
func _courses(size: Vector3, foot: Vector3, at: Array) -> void:
	for y: float in at:
		_parts.add(Vector3(size.x + 0.16, 0.12, size.z + 0.16), foot + Vector3(0, y, 0), COURSE)

# Dressed ashlar over a plain face: blocks laid in staggered courses, each a shade off its
# neighbours and standing a little proud of the mortar bed, so the joints read. `at` is the
# middle of the face at its foot, `n` the way the face looks (+z, -x or +x), `y0`..`y1` the
# height it covers, `hole` a bare patch (x along the face from its middle, y) left for a door.
func _ashlar(at: Vector3, n: Vector3, width: float, y0: float, y1: float, tint: Color, hole := Rect2()) -> void:
	var u := Vector3.RIGHT if absf(n.z) > 0.5 else Vector3.BACK
	var rows := maxi(1, roundi((y1 - y0) / 0.42))
	var rh := (y1 - y0) / rows
	for r in rows:
		var x := -width * 0.5
		var first := true
		while x < width * 0.5 - 0.05:
			var bl := _rng.randf_range(0.7, 1.15)
			if first and r % 2 == 1:
				bl *= 0.5
			first = false
			bl = minf(bl, width * 0.5 - x)
			var mid := x + bl * 0.5
			var yc := y0 + rh * (r + 0.5)
			x += bl
			if hole.has_point(Vector2(mid, yc)):
				continue
			var size := Vector3(absf(u.x) * (bl - 0.03) + absf(n.x) * 0.05, rh - 0.03, absf(u.z) * (bl - 0.03) + absf(n.z) * 0.05)
			var v := _rng.randf_range(-0.05, 0.03)
			_parts.add(size, at + u * mid + n * 0.02 + Vector3(0, yc, 0), Color(tint.r + v, tint.g + v, tint.b + v * 1.1))

# A row of small square-cut beam ends under a cornice, standing out from a face
func _dentils(at: Vector3, n: Vector3, width: float, y: float) -> void:
	var u := Vector3.RIGHT if absf(n.z) > 0.5 else Vector3.BACK
	var count := maxi(2, floori(width / 0.42))
	for k in count:
		var mid := -width * 0.5 + width * (k + 0.5) / count
		var size := Vector3(absf(u.x) * 0.2 + absf(n.x) * 0.16, 0.16, absf(u.z) * 0.2 + absf(n.z) * 0.16)
		_parts.add(size, at + u * mid + Vector3(0, y, 0), HOUSE.darkened(0.08))

# Flagstones laid over a paved floor, a shade off one another, with the joints between
func _flagstones(rect: Rect2, y: float, base: Color) -> void:
	var nx := maxi(1, roundi(rect.size.x / 1.5))
	var nz := maxi(1, roundi(rect.size.y / 1.5))
	var w := rect.size.x / nx
	var d := rect.size.y / nz
	for i in nx:
		for j in nz:
			var v := _rng.randf_range(-0.06, 0.035)
			_parts.add(Vector3(w - 0.07, 0.03, d - 0.07), Vector3(rect.position.x + w * (i + 0.5), y + 0.012, rect.position.y + d * (j + 0.5)),
				Color(base.r + v, base.g + v, base.b + v * 1.1))

# Merlons along a roof's edges
func _merlons(top: Vector3, w: float, d: float) -> void:
	var n := int(w / 0.9)
	for i in n + 1:
		var x := -w * 0.5 + 0.2 + i * (w - 0.4) / n
		for sz: float in [-1.0, 1.0]:
			_parts.add(Vector3(0.4, 0.4, 0.3), top + Vector3(x, 0.2, sz * (d * 0.5 - 0.15)), HOUSE.darkened(0.04))
	var m := maxi(1, int(d / 0.9))
	for i in range(1, m):
		var z := -d * 0.5 + i * d / m
		for sx: float in [-1.0, 1.0]:
			_parts.add(Vector3(0.3, 0.4, 0.4), top + Vector3(sx * (w * 0.5 - 0.15), 0.2, z), HOUSE.darkened(0.04))

# The altar of burnt offering: unhewn stone (Ex. 20:25), horns at its corners, a ramp up
# its east side rather than steps (Ex. 20:26); wood stacked by it, the basin for washing
# (Ex. 30:18) by the porch
func _altar(at: Vector3) -> void:
	_solid(Vector3(2.6, 1.2, 2.6), at)
	# Whole stones, no tool laid to them: three rough courses round a core of rubble, no two the
	# same size, each lying a little off true
	_parts.add(Vector3(2.0, 1.1, 2.0), at + Vector3(0, 0.55, 0), ALTAR.darkened(0.25))
	for course in 3:
		for k in 9:
			var gx := k % 3 - 1
			var gz := k / 3 - 1
			if gx == 0 and gz == 0:
				continue
			var ch := 0.4 * _rng.randf_range(0.9, 1.15)
			var size := Vector3(_rng.randf_range(0.82, 1.02), ch, _rng.randf_range(0.82, 1.02))
			var jitter := Vector3(_rng.randf_range(-0.06, 0.06), 0, _rng.randf_range(-0.06, 0.06))
			var tilt := Vector3(_rng.randf_range(-0.07, 0.07), _rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.07, 0.07))
			var v := _rng.randf_range(-0.08, 0.05)
			_parts.add(size, at + Vector3(gx * 0.88, course * 0.38 + ch * 0.5, gz * 0.88) + jitter,
				Color(ALTAR.r + v, ALTAR.g + v, ALTAR.b + v * 1.1), tilt)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_parts.add(Vector3(0.3, 0.3, 0.3), at + Vector3(sx * 1.1, 1.35, sz * 1.1), ALTAR.lightened(0.06))
	_parts.add(Vector3(1.5, 0.2, 1.5), at + Vector3(0, 1.3, 0), Color(0.25, 0.2, 0.17))   # the hearth
	var slope := atan2(1.2, 1.9)
	_parts.add(Vector3(2.25, 0.3, 1.1), at + Vector3(2.25, 0.55, 0), ALTAR.darkened(0.04), Vector3(0, 0, -slope))
	for k in 3:
		_parts.add(Vector3(1.2, 0.14, 0.14), at + Vector3(-2.0, 0.1 + k * 0.14, 0.6 + (k % 2) * 0.1), CEDAR, Vector3(0, 0.15 * k, 0))
	var basin := Vector3(AXIS_X - 3.4, 0.24, HOUSE_Z.y + 2.2)
	_block(Vector3(0.5, 0.7, 0.5), basin, BRONZE.darkened(0.1))
	_parts.add(Vector3(1.1, 0.35, 1.1), basin + Vector3(0, 0.88, 0), BRONZE)
	_parts.add(Vector3(0.9, 0.06, 0.9), basin + Vector3(0, 1.05, 0), Color(0.45, 0.62, 0.70))

# A solid block standing on the ground at `foot`
func _block(size: Vector3, foot: Vector3, color: Color) -> void:
	_parts.add(size, foot + Vector3(0, size.y * 0.5, 0), color)
	_solid(size, foot)

# The collision of a block standing on `foot`, with nothing drawn for it
func _solid(size: Vector3, foot: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = foot + Vector3(0, size.y * 0.5, 0)
	add_child(shape)

# The fire on the altar (Lev. 6:13 "it shall not go out"): a glow, flames, smoke going up
func _fire(at: Vector3) -> void:
	var light := OmniLight3D.new()
	light.light_color = FIRE
	light.light_energy = 1.6
	light.omni_range = 5.0
	light.position = at + Vector3(0, 0.5, 0)
	add_child(light)
	var flames := CPUParticles3D.new()
	flames.amount = 14
	flames.lifetime = 0.8
	flames.preprocess = 0.8
	flames.direction = Vector3.UP
	flames.spread = 18.0
	flames.gravity = Vector3(0, 1.2, 0)
	flames.initial_velocity_min = 0.4
	flames.initial_velocity_max = 0.9
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	flames.emission_box_extents = Vector3(0.4, 0.05, 0.4)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.4, 0.9))
	ramp.set_color(1, Color(0.9, 0.3, 0.1, 0.0))
	flames.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	quad.material = DustFx.material()   # soft round puffs: a plain quad drew as hard-edged squares
	flames.mesh = quad
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flames.position = at
	add_child(flames)
	var smoke := CPUParticles3D.new()
	smoke.amount = 12
	smoke.lifetime = 5.0
	smoke.preprocess = 5.0   # already a full column when the court is entered, not a dark first cycle
	smoke.direction = Vector3.UP
	smoke.spread = 10.0
	smoke.gravity = Vector3(0.3, 0.4, 0.1)
	smoke.initial_velocity_min = 0.4
	smoke.initial_velocity_max = 0.7
	smoke.scale_amount_min = 0.9
	smoke.scale_amount_max = 1.6
	smoke.scale_amount_curve = DustFx.grow_curve()
	var sr := Gradient.new()
	sr.set_color(0, Color(0.88, 0.85, 0.8, 0.0))
	sr.set_color(1, Color(0.88, 0.85, 0.8, 0.0))   # before add_point: index 1 is the last point only until then
	sr.add_point(0.2, Color(0.88, 0.85, 0.8, 0.4))
	smoke.color_ramp = sr
	var sq := QuadMesh.new()
	sq.size = Vector2(1.0, 1.0)
	sq.material = DustFx.material()
	smoke.mesh = sq
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.position = at + Vector3(0, 0.6, 0)
	add_child(smoke)

## A point inside the court (for the journal's "go up to the house of God")
static func in_court(p: Vector3) -> bool:
	return COURT.grow(-0.4).has_point(Vector2(p.x, p.z))
