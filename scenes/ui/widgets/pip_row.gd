class_name PipRow
extends Control

# Row of diamond pips — `filled` of `count` are solid, the rest outlined.

@export var count := 10:
	set(v):
		count = v
		queue_redraw()
@export var filled := 0:
	set(v):
		filled = v
		queue_redraw()
@export var fill_color := UiStyle.TERRACOTTA:
	set(v):
		fill_color = v
		queue_redraw()
@export var empty_color := Color(UiStyle.INK_SOFT, 0.45)

func _draw() -> void:
	if count <= 0:
		return
	var step := size.x / count
	var r := minf(size.y, step) * 0.45
	for i in count:
		var c := Vector2(step * (i + 0.5), size.y * 0.5)
		var pts := PackedVector2Array([
			c + Vector2(0, -r), c + Vector2(r * 0.8, 0), c + Vector2(0, r), c + Vector2(-r * 0.8, 0)])
		if i < filled:
			draw_colored_polygon(pts, fill_color)
		else:
			pts.append(pts[0])
			draw_polyline(pts, empty_color, 1.2, true)
