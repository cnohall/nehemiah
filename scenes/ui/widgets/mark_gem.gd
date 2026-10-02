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
		ci.draw_colored_polygon(pts, UiStyle.GOLD)
		# Facet: the upper-left face catches the light
		ci.draw_colored_polygon(PackedVector2Array([pts[0], c, pts[3]]), Color(UiStyle.CREAM, 0.45))
		pts.append(pts[0])
		ci.draw_polyline(pts, UiStyle.AMBER.darkened(0.3), maxf(1.0, r * 0.14), true)
	else:
		pts.append(pts[0])
		ci.draw_polyline(pts, Color(UiStyle.INK_MUTED, 0.7), maxf(1.0, r * 0.12), true)
