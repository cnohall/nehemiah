class_name RingCompass
extends Control

# Where you are on the wall, for Walk the City: a small north-up plan of the circuit
# (CircuitDiorama.ring_unit — true to the city's shape) with the stretch you're on in
# gold and a dot where you stand along it, and beside it a compass needle pointing to
# true north as it lies in the view. The site is always laid out the same way (outside
# the wall up-screen), so north turns as you go round: at the Sheep Gate it's up, at the
# Fountain Gate it's behind you.

const MAP := 132.0        # px, the plan's square
const PAD := 14.0         # px, clear round the ring inside it
const DIAL := 36.0        # px, the compass's radius
const GAP := 18.0
const SITE_HALF_X := 44.0 # the stretch's walkable ends (Player.PLAY_AREA)

## Section index of the stretch you're on
var district := 0

var _fit := Transform2D()   # unit space → the plan's px, the ring fitted inside PAD

func _init() -> void:
	custom_minimum_size = Vector2(MAP + GAP + DIAL * 2.0 + 14.0, MAP)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

## Unit-space (x east, y south) direction along the stretch toward the next gate, and
## out of the city across it
static func frame(i: int) -> Array[Vector2]:
	var a := CircuitDiorama.ring_unit(i)
	var b := CircuitDiorama.ring_unit(i + 1)
	var along := (b - a).normalized()
	var mid := CircuitDiorama.ring_unit(i + 0.5)
	var out := mid - CircuitDiorama.CENTER
	out = (out - along * out.dot(along)).normalized()
	return [along, out]

## True north on the site: world x runs along the stretch toward the next gate, world -z
## is outside the wall
static func north_on_site(i: int) -> Vector3:
	var f := frame(i)
	var n := Vector2(0, -1)
	return Vector3(n.dot(f[0]), 0.0, -n.dot(f[1]))

func _draw() -> void:
	_draw_plan()
	_draw_dial(Vector2(MAP + GAP + DIAL, MAP * 0.5))

# The plan, north up: the ring, its gates, your stretch in gold, you on it
func _draw_plan() -> void:
	var font := UiStyle.CINZEL_BOLD
	var rect := Rect2(Vector2.ZERO, Vector2(MAP, MAP))
	draw_rect(rect, Color(UiStyle.PARCHMENT_DEEP, 0.7))
	draw_rect(rect, UiStyle.RULE, false, 1.0)
	var n := CircuitDiorama.GATES.size()
	if _fit == Transform2D():
		_fit = _fit_ring(n)
	var ring := PackedVector2Array()
	for k in n * 8 + 1:
		ring.append(_fit * CircuitDiorama.ring_unit(k / 8.0))
	draw_polyline(ring, UiStyle.INK_SOFT, 2.0, true)
	var here := PackedVector2Array()
	for k in 9:
		here.append(_fit * CircuitDiorama.ring_unit(district + k / 8.0))
	draw_polyline(here, UiStyle.GOLD, 5.0, true)
	for g in n:
		draw_circle(_fit * CircuitDiorama.ring_unit(g), 2.5, UiStyle.INK)
	var me := Player.local
	if me != null and is_instance_valid(me):
		var t := clampf(inverse_lerp(-SITE_HALF_X, SITE_HALF_X, me.global_position.x), 0.0, 1.0)
		var at: Vector2 = _fit * CircuitDiorama.ring_unit(district + t)
		draw_circle(at, 5.5, UiStyle.TERRACOTTA)
		draw_arc(at, 5.5, 0.0, TAU, 16, UiStyle.CREAM, 1.5, true)
	# North is up on the plan: a small arrow in its corner
	var tip := Vector2(12, 7)
	draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-4, 7), tip + Vector2(4, 7)]), UiStyle.TERRACOTTA)
	draw_string(font, Vector2(tip.x - 4.5, 26), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiStyle.TERRACOTTA)

# The ring's bounds scaled to fill the square less PAD, centred
func _fit_ring(n: int) -> Transform2D:
	var lo := Vector2(INF, INF)
	var hi := -lo
	for k in n * 8:
		var u := CircuitDiorama.ring_unit(k / 8.0)
		lo = lo.min(u)
		hi = hi.max(u)
	var size := hi - lo
	var s := (MAP - PAD * 2.0) / maxf(size.x, size.y)
	var offset := Vector2(MAP, MAP) * 0.5 - (lo + size * 0.5) * s
	return Transform2D(0.0, Vector2(s, s), 0.0, offset)

# The compass: a dial with the four quarters marked, turned so its needle points to
# north as it lies in the view
func _draw_dial(c: Vector2) -> void:
	var font := UiStyle.CINZEL_BOLD
	draw_circle(c, DIAL, Color(UiStyle.PARCHMENT_DEEP, 0.7))
	draw_arc(c, DIAL, 0.0, TAU, 48, UiStyle.RULE, 1.0, true)
	draw_arc(c, DIAL - 4.0, 0.0, TAU, 48, Color(UiStyle.RULE, 0.5), 1.0, true)
	var dir := _north_on_screen()
	if dir == Vector2.ZERO:
		return
	for q in 4:
		var d := dir.rotated(q * PI * 0.5)
		var inner := DIAL - (9.0 if q == 0 else 7.0)
		draw_line(c + d * inner, c + d * (DIAL - 1.0), UiStyle.INK_SOFT if q > 0 else UiStyle.TERRACOTTA, 2.0 if q == 0 else 1.0, true)
	var r := DIAL - 13.0
	var side := dir.orthogonal() * 4.5
	draw_colored_polygon(PackedVector2Array([c + dir * r, c + side, c - side]), UiStyle.TERRACOTTA)
	draw_colored_polygon(PackedVector2Array([c - dir * r, c + side, c - side]), UiStyle.INK_SOFT)
	draw_circle(c, 2.0, UiStyle.CREAM)
	# The N just outside the rim, off the north tick
	var size := font.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
	var at := c + dir * (DIAL + 9.0)
	draw_string(font, at + Vector2(-size.x * 0.5, size.y * 0.3), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiStyle.TERRACOTTA)

# North on the site, through the camera: which way it points on screen
func _north_on_screen() -> Vector2:
	var cam := get_viewport().get_camera_3d()
	var me := Player.local
	if cam == null or me == null or not is_instance_valid(me):
		return Vector2.ZERO
	var p := me.global_position
	var d := cam.unproject_position(p + north_on_site(district) * 4.0) - cam.unproject_position(p)
	return d.normalized()
