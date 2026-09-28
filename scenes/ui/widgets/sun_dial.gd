class_name SunDial
extends Control

# The day's sun clock (GameState.sun, Neh. 4:21 "from the rising of the morning till
# the stars appeared"): a low arc cut into the plaque, the sun travelling from dawn on
# the left to the stars on the right. The travelled part fills amber; in the last
# quarter the sun reddens toward terracotta. On a section's last day the star at the
# end is terracotta — nightfall there loses the run.

const ARC_H     := 9.0     # rise of the arc above its ends
const TRACK_W   := 2.5
const SUN_R     := 6.5
const STAR_R    := 5.0
const SEGMENTS  := 32

## 0 at dawn → 1 at the stars
var t := 0.0:
	set(v):
		t = clampf(v, 0.0, 1.0)
		queue_redraw()
var low := false:
	set(v):
		low = v
		queue_redraw()
var last_day := false:
	set(v):
		last_day = v
		queue_redraw()

func _init() -> void:
	custom_minimum_size = Vector2(0, ARC_H + SUN_R * 2.0 + 2.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _point(k: float) -> Vector2:
	var left := SUN_R + 1.0
	var right := size.x - STAR_R * 2.0 - 4.0
	var base := size.y - SUN_R - 1.0
	return Vector2(lerpf(left, right, k), base - sin(k * PI) * ARC_H)

func _draw() -> void:
	var track := PackedVector2Array()
	for i in SEGMENTS + 1:
		track.append(_point(i / float(SEGMENTS)))
	draw_polyline(track, UiStyle.RULE, TRACK_W, true)
	var done := PackedVector2Array()
	var n := maxi(1, ceili(SEGMENTS * t))
	for i in n + 1:
		done.append(_point(minf(i / float(SEGMENTS), t)))
	if t > 0.0:
		draw_polyline(done, UiStyle.TERRACOTTA if low else UiStyle.AMBER, TRACK_W, true)
	# The stars at the end of the day
	var star := Vector2(size.x - STAR_R - 1.0, size.y - SUN_R - 1.0)
	_draw_star(star, STAR_R, UiStyle.TERRACOTTA if last_day else UiStyle.INK_SOFT)
	# The sun: gold, reddening as the light goes
	var sun := _point(t)
	var c := UiStyle.GOLD.lerp(UiStyle.TERRACOTTA, 1.0 if low else 0.0)
	draw_circle(sun, SUN_R + 1.5, Color(UiStyle.INK, 0.35))
	draw_circle(sun, SUN_R, c)

func _draw_star(c: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var a := i * PI / 4.0 - PI / 2.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.38))
	draw_colored_polygon(pts, color)
