class_name MarkGem
extends Control

# One section mark (GameState.Mark) as a cut-stone diamond: gold when earned, an empty
# outline when not. `draw_gem` is shared with CircuitMap, which draws marks by the gates.

var lit := false:
	set(v):
		lit = v
		queue_redraw()

# 0..1 sweep of a glint across a lit gem (the tally plays it as each mark lands)
var shine := 0.0:
	set(v):
		shine = v
		queue_redraw()

func _init(is_lit := false, side := 18.0) -> void:
	lit = is_lit
	custom_minimum_size = Vector2(side, side)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(func(): pivot_offset = size * 0.5)

func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5
	if lit and r > 20.0:
		# A big earned gem sits in a soft pool of gold light (spills past its box)
		for i in 6:
			var k := 1.0 - i / 6.0
			draw_circle(size * 0.5, r * (0.7 + 0.13 * i), Color(UiStyle.GOLD, 0.05 * k))
	draw_gem(self, size * 0.5, r, lit)
	if lit and shine > 0.0 and shine < 1.0:
		# A four-point sparkle that swells and fades over the upper-left facet
		var k := sin(shine * PI)
		var c := size * 0.5 + Vector2(-r * 0.25, -r * 0.35)
		var long := r * 0.9 * k
		var thin := r * 0.12 * k
		var col := Color(1, 1, 0.92, k)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -long), c + Vector2(thin, 0), c + Vector2(0, long), c + Vector2(-thin, 0)]), col)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-long, 0), c + Vector2(0, thin), c + Vector2(long, 0), c + Vector2(0, -thin)]), col)

static func draw_gem(ci: CanvasItem, c: Vector2, r: float, is_lit: bool) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.8, 0), c + Vector2(0, r), c + Vector2(-r * 0.8, 0)])
	if is_lit:
		# Cut stone, lit from the upper left: four faces, each its own shade, with a
		# small table (the flat top facet) raised in the middle
		var faces := [
			[pts[0], c, pts[3], UiStyle.GOLD.lerp(UiStyle.CREAM, 0.55)],   # upper left: the light
			[pts[0], pts[1], c, UiStyle.GOLD],                              # upper right
			[pts[3], c, pts[2], UiStyle.GOLD.lerp(UiStyle.AMBER, 0.45)],    # lower left
			[c, pts[1], pts[2], UiStyle.AMBER.darkened(0.12)],              # lower right: shade
		]
		for f: Array in faces:
			ci.draw_colored_polygon(PackedVector2Array([f[0], f[1], f[2]]), f[3])
		if r > 12.0:
			var t := r * 0.32
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -t), c + Vector2(t * 0.8, 0),
				c + Vector2(0, t), c + Vector2(-t * 0.8, 0)]), Color(UiStyle.GOLD.lerp(UiStyle.CREAM, 0.3), 0.9))
		pts.append(pts[0])
		ci.draw_polyline(pts, UiStyle.AMBER.darkened(0.35), maxf(1.0, r * 0.1), true)
	else:
		# Not earned: the setting is cut into the parchment, waiting for its stone
		ci.draw_colored_polygon(pts, Color(UiStyle.DUSK, 0.07))
		var w := maxf(1.0, r * 0.08)
		ci.draw_polyline(PackedVector2Array([pts[3], pts[0], pts[1]]), Color(UiStyle.DUSK, 0.32), w, true)
		ci.draw_polyline(PackedVector2Array([pts[1], pts[2], pts[3]]), Color(UiStyle.INK_MUTED, 0.45), w, true)
		if r > 12.0:   # the lit lower lip of the cut
			var o := Vector2(0, w * 1.2)
			ci.draw_polyline(PackedVector2Array([pts[1] + o, pts[2] + o, pts[3] + o]), Color(UiStyle.CREAM, 0.8), w, true)
