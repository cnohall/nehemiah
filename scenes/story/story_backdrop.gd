class_name StoryBackdrop
extends Control

# Drawn stand-in for story art: sky, far hills and the city wall in silhouette,
# standing as far as `built` says. Deliberately plain — a woodcut, not a painting.

const HORIZON  := 0.60    # of height
const WALL_BASE := 0.80
const WALL_H   := 0.15
const SEGMENTS := 30
const TOWERS   := [6, 15, 24]
# sky top, horizon, sun/moon
const SKIES := {
	"night": [Color(0.047, 0.055, 0.094), Color(0.176, 0.161, 0.216), Color(0.93, 0.91, 0.84)],
	"dawn":  [Color(0.227, 0.192, 0.278), Color(0.918, 0.604, 0.357), Color(1.0, 0.878, 0.62)],
	"day":   [Color(0.463, 0.576, 0.667), Color(0.925, 0.855, 0.72),  Color(1.0, 0.965, 0.86)],
	"dusk":  [Color(0.176, 0.098, 0.106), Color(0.804, 0.412, 0.196), Color(1.0, 0.749, 0.45)],
}

var sky := "dusk":
	set(v):
		sky = v
		queue_redraw()
var built := 0.0:
	set(v):
		built = clampf(v, 0.0, 1.0)
		queue_redraw()
var pattern := 1:          # seeds stars, hills and rubble so each slide differs
	set(v):
		pattern = v
		queue_redraw()

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	var w := size.x
	var h := size.y
	var s: Array = SKIES.get(sky, SKIES["dusk"])
	var top: Color = s[0]
	var glow: Color = s[1]
	var sun_col: Color = s[2]
	var horizon := h * HORIZON
	var rng := RandomNumberGenerator.new()
	rng.seed = pattern

	# Sky
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, horizon + 2), Vector2(0, horizon + 2)]),
		PackedColorArray([top, top, glow, glow]))
	if sky == "night":
		for i in 160:
			var p := Vector2(rng.randf() * w, pow(rng.randf(), 1.4) * horizon)
			draw_circle(p, rng.randf_range(0.7, 1.9), Color(sun_col, rng.randf_range(0.25, 0.85)))

	# Sun or moon, low on the horizon at dawn/dusk
	var lift: float = { "night": 0.34, "day": 0.38, "dawn": 0.07, "dusk": 0.1 }.get(sky, 0.1)
	var sun := Vector2(w * rng.randf_range(0.62, 0.78), horizon - h * lift)
	var r := h * (0.028 if sky == "night" else 0.045)
	for i in 16:
		draw_circle(sun, r * (5.0 - i * 0.25), Color(sun_col, 0.018))
	draw_circle(sun, r, sun_col)

	# Two hill ridges, the far one hazed toward the sky
	var land := top.lerp(Color.BLACK, 0.45)
	_ridge(horizon, h * 0.07, glow.lerp(land, 0.45), rng, h)
	_ridge(horizon + h * 0.05, h * 0.05, glow.lerp(land, 0.75), rng, h)

	# Wall — standing segments full height with merlons, the rest broken stubs
	var ink := land.lerp(Color.BLACK, 0.35)
	var rim := Color(glow, 0.45)
	var base := h * WALL_BASE
	var seg_w := w / SEGMENTS
	for i in SEGMENTS:
		var x := i * seg_w
		var standing := (i + 0.5) / SEGMENTS <= built
		var tower := i in TOWERS
		var hgt := h * WALL_H * (1.35 if tower else 1.0)
		if not standing:
			hgt *= rng.randf_range(0.12, 0.4)
		var y := base - hgt
		draw_rect(Rect2(x - 0.5, y, seg_w + 1.0, hgt + 1.0), ink)
		if standing:
			var m := seg_w / 5.0
			for k in [0, 2, 4]:
				draw_rect(Rect2(x + k * m, y - m * 0.9, m, m * 0.9 + 1.0), ink)
				draw_line(Vector2(x + k * m, y - m * 0.9), Vector2(x + (k + 1) * m, y - m * 0.9), rim, 1.5)
		else:
			# Jagged top and fallen stones at the foot
			var pts := PackedVector2Array([Vector2(x, y + 1)])
			for k in 4:
				pts.append(Vector2(x + seg_w * (k + 0.5) / 4.0, y - rng.randf_range(0.0, h * 0.012)))
			pts.append(Vector2(x + seg_w, y + 1))
			draw_colored_polygon(pts, ink)
			for k in 3:
				draw_circle(Vector2(x + rng.randf() * seg_w, base + rng.randf_range(-4, 6)), rng.randf_range(3, 9), ink)
	# Ground
	draw_rect(Rect2(0, base, w, h - base), ink.lerp(Color.BLACK, 0.3))

func _ridge(base: float, amp: float, col: Color, rng: RandomNumberGenerator, h: float) -> void:
	var pts := PackedVector2Array()
	var f1 := rng.randf_range(0.002, 0.004)
	var f2 := rng.randf_range(0.007, 0.012)
	var ph := rng.randf() * TAU
	var step := 24.0
	var x := 0.0
	while x <= size.x + step:
		pts.append(Vector2(x, base - amp * (0.6 + 0.3 * sin(x * f1 + ph) + 0.15 * sin(x * f2 + ph * 2.0))))
		x += step
	pts.append(Vector2(size.x + step, h))
	pts.append(Vector2(0, h))
	draw_colored_polygon(pts, col)
