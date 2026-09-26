class_name MarkGem
extends Control

# One section mark (GameState.Mark) as a cut-stone diamond: gold when earned, an empty
# outline when not. `draw_gem` is shared with CircuitMap, which draws marks by the gates.

var lit := false:
	set(v):
		lit = v
		queue_redraw()

func _init(is_lit := false, side := 18.0) -> void:
	lit = is_lit
	custom_minimum_size = Vector2(side, side)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	draw_gem(self, size * 0.5, minf(size.x, size.y) * 0.5, lit)

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
		ci.draw_polyline(pts, Color(UiStyle.CREAM, 0.35), maxf(1.0, r * 0.12), true)
