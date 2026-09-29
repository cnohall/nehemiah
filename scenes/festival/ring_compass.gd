class_name RingCompass
extends Control

# Where you are on the wall, for Walk the City: a small north-up plan of the circuit
# (CircuitDiorama.ring_unit — true to the city's shape) with the stretch you're on in
# gold and a dot where you stand along it, and beside it a compass needle pointing to
# true north as it lies in the view. The site is always laid out the same way (outside
# the wall up-screen), so north turns as you go round: at the Sheep Gate it's up, at the
# Fountain Gate it's behind you.

const MAP := 132.0        # px, the plan's square
const ROSE := 58.0        # px, the compass
const GAP := 14.0
const SITE_HALF_X := 44.0 # the stretch's walkable ends (Player.PLAY_AREA)

## Section index of the stretch you're on
var district := 0

func _init() -> void:
	custom_minimum_size = Vector2(MAP + GAP + ROSE, MAP)
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
	var font := UiStyle.CINZEL_BOLD
	# ── The plan, north up ──
	var rect := Rect2(Vector2.ZERO, Vector2(MAP, MAP))
	draw_rect(rect, Color(UiStyle.PARCHMENT_DEEP, 0.7))
	draw_rect(rect, UiStyle.RULE, false, 1.0)
	var to_px := func(u: Vector2) -> Vector2:
		return (u - Vector2(0.5, 0.5)) * MAP * 1.25 + Vector2(MAP, MAP) * 0.5
	var n := CircuitDiorama.GATES.size()
	var ring := PackedVector2Array()
	for k in n * 8 + 1:
		ring.append(to_px.call(CircuitDiorama.ring_unit(k / 8.0)))
	draw_polyline(ring, UiStyle.INK_SOFT, 2.0, true)
	var here := PackedVector2Array()
	for k in 9:
		here.append(to_px.call(CircuitDiorama.ring_unit(district + k / 8.0)))
	draw_polyline(here, UiStyle.GOLD, 5.0, true)
	for g in n:
		draw_circle(to_px.call(CircuitDiorama.ring_unit(g)), 2.5, UiStyle.INK)
	# You, along the stretch
	var me := Player.local
	if me != null and is_instance_valid(me):
		var t := clampf(inverse_lerp(-SITE_HALF_X, SITE_HALF_X, me.global_position.x), 0.0, 1.0)
		var at: Vector2 = to_px.call(CircuitDiorama.ring_unit(district + t))
		draw_circle(at, 5.0, UiStyle.TERRACOTTA)
		draw_arc(at, 5.0, 0.0, TAU, 16, UiStyle.CREAM, 1.5, true)
	draw_string(font, Vector2(MAP * 0.5 - 5, 13), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiStyle.TERRACOTTA)
	# ── The compass: north as it lies in the view ──
	var c := Vector2(MAP + GAP + ROSE * 0.5, MAP * 0.5)
	var r := ROSE * 0.5 - 4.0
	draw_circle(c, r + 3.0, Color(UiStyle.PARCHMENT_DEEP, 0.7))
	draw_arc(c, r + 3.0, 0.0, TAU, 32, UiStyle.RULE, 1.0, true)
	var dir := _north_on_screen()
	if dir == Vector2.ZERO:
		return
	var side := dir.orthogonal() * r * 0.28
	draw_colored_polygon(PackedVector2Array([c + dir * r, c + side, c - side]), UiStyle.TERRACOTTA)
	draw_colored_polygon(PackedVector2Array([c - dir * r, c + side, c - side]), UiStyle.INK_SOFT)
	var label := c + dir * (r + 12.0) - Vector2(5, -5)
	draw_string(font, label, "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiStyle.TERRACOTTA)

# North on the site, through the camera: which way it points on screen
func _north_on_screen() -> Vector2:
	var cam := get_viewport().get_camera_3d()
	var me := Player.local
	if cam == null or me == null or not is_instance_valid(me):
		return Vector2.ZERO
	var p := me.global_position
	var d := cam.unproject_position(p + north_on_site(district) * 4.0) - cam.unproject_position(p)
	return d.normalized()
