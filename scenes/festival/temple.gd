class_name Temple
extends StaticBody3D

# The house of God in the east of the city, for the festival (Neh. 8:16 "in the courts of
# God's house"): the rebuilt temple of Zerubbabel's day — plain, not Solomon's gold. A
# walled court on a paved platform, its gate on the south toward the city streets; the
# sanctuary on the west of the court with its porch facing east, the altar of burnt
# offering before it with its fire. Chunky blocks like the rest of the world; walls,
# altar and house are solid, the court itself open.

const COURT      := Rect2(27.0, 4.6, 16.0, 9.8)    # x, z, width, depth; a lane left along the wall
const WALL_H     := 1.4
const WALL_T     := 0.6
const GATE_HALF  := 1.5     # the opening in the south wall, facing the city
const GATE_X     := 36.0
const STONE      := Color(0.86, 0.82, 0.74)
const PAVING     := Color(0.80, 0.76, 0.68)
const HOUSE      := Color(0.90, 0.87, 0.80)
const DOORWAY    := Color(0.20, 0.14, 0.09)
const VEIL       := Palette.MUREX
const ALTAR      := Color(0.70, 0.66, 0.60)
const FIRE       := Color(1.0, 0.6, 0.22)

var _parts := WatchPost._Parts.new()

func _ready() -> void:
	var c := Vector3(COURT.get_center().x, 0.0, COURT.get_center().y)
	var x0 := COURT.position.x
	var x1 := COURT.end.x
	var z0 := COURT.position.y
	var z1 := COURT.end.y
	# Platform paving, a step proud of the ground
	_parts.add(Vector3(COURT.size.x, 0.16, COURT.size.y), c + Vector3(0, 0.08, 0), PAVING)
	# Court walls: north, west and east whole; the south one open to the city streets
	_block(Vector3(COURT.size.x, WALL_H, WALL_T), Vector3(c.x, 0, z0), STONE)
	_block(Vector3(WALL_T, WALL_H, COURT.size.y), Vector3(x0, 0, c.z), STONE)
	_block(Vector3(WALL_T, WALL_H, COURT.size.y), Vector3(x1, 0, c.z), STONE)
	var gate_x := GATE_X
	var left := gate_x - GATE_HALF - x0
	var right := x1 - gate_x - GATE_HALF
	_block(Vector3(left, WALL_H, WALL_T), Vector3(x0 + left * 0.5, 0, z1), STONE)
	_block(Vector3(right, WALL_H, WALL_T), Vector3(x1 - right * 0.5, 0, z1), STONE)
	for sx: float in [-1.0, 1.0]:
		_block(Vector3(0.9, WALL_H + 0.7, 0.9), Vector3(gate_x + sx * (GATE_HALF + 0.2), 0, z1), STONE.darkened(0.05))
	_parts.add(Vector3(COURT.size.x + 0.2, 0.12, WALL_T + 0.15), Vector3(c.x, WALL_H + 0.06, z0), STONE.lightened(0.05))
	# The sanctuary on the west of the court, its porch and doorway facing east
	var house := Vector3(x0 + 3.4, 0, c.z)
	_block(Vector3(4.6, 5.4, 5.2), house, HOUSE)
	_parts.add(Vector3(4.9, 0.3, 5.5), house + Vector3(0, 5.55, 0), HOUSE.darkened(0.06))
	var porch := house + Vector3(3.0, 0, 0)
	_block(Vector3(1.6, 6.2, 5.8), porch, HOUSE.lightened(0.03))
	_parts.add(Vector3(1.8, 0.3, 6.1), porch + Vector3(0, 6.35, 0), HOUSE.darkened(0.04))
	_parts.add(Vector3(0.06, 2.8, 1.4), porch + Vector3(0.83, 1.5, 0), DOORWAY)
	_parts.add(Vector3(0.05, 2.5, 1.1), porch + Vector3(0.86, 1.35, 0), VEIL)
	# Steps up to the porch
	for k in 3:
		_parts.add(Vector3(0.5, 0.12 * (3 - k), 2.4), porch + Vector3(1.05 + k * 0.5, 0.06 * (3 - k) + 0.1, 0), STONE)
	# The altar of burnt offering before the house: unhewn stone (Ex. 20:25), horns at
	# its corners, a ramp on its south side
	var altar := Vector3(x1 - 5.5, 0, c.z - 0.6)
	_block(Vector3(2.4, 1.2, 2.4), altar, ALTAR)
	_parts.add(Vector3(0.9, 0.5, 1.6), altar + Vector3(0, 0.25, 1.9), ALTAR.darkened(0.05))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_parts.add(Vector3(0.3, 0.25, 0.3), altar + Vector3(sx * 1.05, 1.32, sz * 1.05), ALTAR.lightened(0.05))
	_parts.add(Vector3(1.3, 0.2, 1.3), altar + Vector3(0, 1.3, 0), Color(0.25, 0.2, 0.17))   # the hearth
	add_child(_parts.build(Chunky.material(0.05)))
	_fire(altar + Vector3(0, 1.45, 0))

# A solid block standing on the ground at `foot`
func _block(size: Vector3, foot: Vector3, color: Color) -> void:
	_parts.add(size, foot + Vector3(0, size.y * 0.5, 0), color)
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
	quad.size = Vector2(0.35, 0.35)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = mat
	flames.mesh = quad
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flames.position = at
	add_child(flames)
	var smoke := CPUParticles3D.new()
	smoke.amount = 12
	smoke.lifetime = 5.0
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
	sr.add_point(0.2, Color(0.88, 0.85, 0.8, 0.4))
	sr.set_color(1, Color(0.88, 0.85, 0.8, 0.0))
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
