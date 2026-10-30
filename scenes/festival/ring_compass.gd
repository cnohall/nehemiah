class_name RingCompass
extends Control

# Where you are on the wall, for Explore Jerusalem: a small north-up plan of the circuit
# (CircuitDiorama.ring_unit — true to the city's shape) with the stretch you're on in
# gold and a dot where you stand along it, and beside it a compass needle pointing to
# true north as it lies in the view. Explore Jerusalem turns the view north-up on every
# stretch, so the needle stands up and the wall on screen lies as the gold does here.
# The campaign shows it too (GameHud), following the section being built; its view
# turns north-up only with Settings.turn_to_map.

const MAP := 132.0        # px, the plan's square
const PAD := 14.0         # px, clear round the ring inside it
const DIAL := 36.0        # px, the compass's radius
const GAP := 18.0
const SITE_HALF_X := 44.0 # the stretch's walkable ends (Player.PLAY_AREA)

const SCREEN_UP := Vector3(-0.70710678, 0.0, -0.70710678)   # the game's view: away from the camera

## Section index of the stretch you're on
var district := 0
## Outside Explore Jerusalem: keep to the section being built
var follow_section := false

var _fit := Transform2D()   # unit space → the plan's px, the ring fitted inside PAD

func _init() -> void:
	custom_minimum_size = Vector2(MAP + GAP + DIAL * 2.0 + 14.0, MAP)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	if follow_section:
		district = GameState.current_section_index
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

## True north on the site: world x runs along the stretch toward the next gate times
## Festival.FLOW, world -z is outside the wall
static func north_on_site(i: int) -> Vector3:
	var f := frame(i)
	var n := Vector2(0, -1)
	return Vector3(n.dot(f[0]) * Festival.FLOW, 0.0, -n.dot(f[1]))

## The view yaw (Main.set_view_yaw) that puts true north straight up-screen, as on a map
static func north_up_yaw(i: int) -> float:
	return SCREEN_UP.signed_angle_to(north_on_site(i), Vector3.UP)

## The ground direction on the site of a compass bearing (degrees, clockwise from north)
static func bearing_on_site(i: int, degrees: float) -> Vector3:
	return north_on_site(i).rotated(Vector3.UP, -deg_to_rad(degrees))

## "from the north-east" etc. (translated): the quarter a ground direction on the site
## points to, for the watchmen's calls
static func quarter(i: int, dir: Vector3) -> String:
	var n := north_on_site(i)
	var e := bearing_on_site(i, 90.0)
	var deg := rad_to_deg(atan2(dir.dot(e), dir.dot(n)))
	var words := [TranslationServer.translate("from the north"), TranslationServer.translate("from the north-east"),
		TranslationServer.translate("from the east"), TranslationServer.translate("from the south-east"),
		TranslationServer.translate("from the south"), TranslationServer.translate("from the south-west"),
		TranslationServer.translate("from the west"), TranslationServer.translate("from the north-west")]
	return words[posmod(roundi(deg / 45.0), 8)]

func _draw() -> void:
	_draw_plan()
	_draw_dial(Vector2(MAP + GAP + DIAL, MAP * 0.5))

# The plan, north up: the ring, its gates, your stretch in gold, you on it
func _draw_plan() -> void:
	var font := UiStyle.CINZEL_BOLD
	var rect := Rect2(Vector2.ZERO, Vector2(MAP, MAP))
	# A sheet of the plan: soft shadow under it, fibre in the paper, a rule pressed in
	draw_rect(Rect2(rect.position + Vector2(0, 2), rect.size), Color(UiStyle.DUSK, 0.12))
	draw_rect(rect, Color(UiStyle.PARCHMENT, 0.88))
	UiStyle._fibre(self, rect.size)
	var inner := rect.grow(-4.0)
	draw_rect(inner.grow(-0.5), Color(UiStyle.RULE, 0.55), false, 1.0)
	draw_rect(Rect2(inner.position + Vector2(1, 1), inner.size).grow(-0.5), Color(1, 1, 1, 0.45), false, 1.0)
	draw_rect(rect, UiStyle.RULE, false, 1.0)
	var n := CircuitDiorama.GATES.size()
	if _fit == Transform2D():
		_fit = _fit_ring(n)
	var ring := PackedVector2Array()
	for k in n * 8 + 1:
		ring.append(_fit * CircuitDiorama.ring_unit(k / 8.0))
	# The wall as a plan draws it: a band of stone between two ink lines
	var here := PackedVector2Array()
	for k in 9:
		here.append(_fit * CircuitDiorama.ring_unit(district + k / 8.0))
	draw_polyline(here, Color(UiStyle.GOLD, 0.85), 8.0, true)
	draw_polyline(ring, UiStyle.INK_SOFT, 4.2, true)
	draw_polyline(ring, UiStyle.PARCHMENT_DEEP.lerp(UiStyle.CREAM, 0.3), 2.0, true)
	for g in n:
		# Each gate a small tower on the line
		var at: Vector2 = _fit * CircuitDiorama.ring_unit(g)
		draw_rect(Rect2(at - Vector2(3, 3), Vector2(6, 6)), UiStyle.INK)
		draw_rect(Rect2(at - Vector2(1.5, 1.5), Vector2(3, 3)), UiStyle.PARCHMENT_DEEP)
	var me := Player.local
	if me != null and is_instance_valid(me):
		var t := clampf(inverse_lerp(-SITE_HALF_X, SITE_HALF_X, me.global_position.x * Festival.FLOW), 0.0, 1.0)
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
	draw_circle(c + Vector2(0, 2), DIAL, Color(UiStyle.DUSK, 0.12))
	draw_circle(c, DIAL, Color(UiStyle.PARCHMENT, 0.88))
	draw_circle(c, DIAL - 6.0, Color(UiStyle.PARCHMENT_DEEP, 0.35))
	draw_arc(c, DIAL, 0.0, TAU, 64, UiStyle.RULE, 1.0, true)
	draw_arc(c, DIAL - 3.5, 0.0, TAU, 64, Color(UiStyle.RULE, 0.55), 1.0, true)
	draw_arc(c, DIAL - 6.0, 0.0, TAU, 64, Color(UiStyle.RULE, 0.35), 1.0, true)
	var dir := _north_on_screen()
	if dir == Vector2.ZERO:
		return
	# Graduated between the two outer rings: sixteen points, the quarters cut deeper
	for q in 16:
		if q % 4 == 0:
			continue
		var d := dir.rotated(q * PI / 8.0)
		draw_line(c + d * (DIAL - 3.5), c + d * (DIAL - (1.5 if q % 2 == 1 else 0.5)), Color(UiStyle.INK_SOFT, 0.6), 1.0, true)
	for q in 4:
		var d := dir.rotated(q * PI * 0.5)
		var inner := DIAL - (9.0 if q == 0 else 7.0)
		draw_line(c + d * inner, c + d * (DIAL - 1.0), UiStyle.INK_SOFT if q > 0 else UiStyle.TERRACOTTA, 2.0 if q == 0 else 1.0, true)
	# The needle, struck in two halves: a lit and a shaded face along its spine
	var r := DIAL - 13.0
	var side := dir.orthogonal() * 4.5
	draw_colored_polygon(PackedVector2Array([c + dir * r, c + side, c]), UiStyle.TERRACOTTA.lightened(0.12))
	draw_colored_polygon(PackedVector2Array([c + dir * r, c, c - side]), UiStyle.TERRACOTTA.darkened(0.15))
	draw_colored_polygon(PackedVector2Array([c - dir * r, c + side, c]), UiStyle.INK_SOFT.lightened(0.15))
	draw_colored_polygon(PackedVector2Array([c - dir * r, c, c - side]), UiStyle.INK_SOFT)
	draw_circle(c, 2.6, UiStyle.GOLD.darkened(0.1))
	draw_circle(c, 1.4, UiStyle.CREAM)
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
