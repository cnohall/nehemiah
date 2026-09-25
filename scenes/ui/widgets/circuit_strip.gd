class_name CircuitStrip
extends Control

# The 52-day campaign as a strip of the 12 wall sections (Nehemiah 3), each as wide
# as its day count. Finished days fill amber; a diamond marks today.

const GAP := 3.0
const BAR_H := 4.0

var day := 1:
	set(v):
		day = v
		queue_redraw()

func _draw() -> void:
	var sections: Array = GameState.SECTIONS
	var per_day := (size.x - GAP * (sections.size() - 1)) / GameState.TOTAL_DAYS
	var y := (size.y - BAR_H) * 0.5
	var x := 0.0
	var marker_x := -1.0
	for sec: Dictionary in sections:
		var days: Array = sec["days"]
		var w := days.size() * per_day
		var current: bool = days.has(day)
		draw_rect(Rect2(x, y, w, BAR_H), Color(UiStyle.DUSK, 0.14))
		var done := days.filter(func(d): return d < day).size()
		if done > 0:
			draw_rect(Rect2(x, y, done * per_day, BAR_H), UiStyle.AMBER)
		if current:
			draw_rect(Rect2(x - 1, y - 1, w + 2, BAR_H + 2), Color(UiStyle.INK, 0.55), false, 1.0)
			marker_x = x + (done + 0.5) * per_day
		x += w + GAP
	if marker_x >= 0.0:
		var c := Vector2(marker_x, size.y * 0.5)
		var r := size.y * 0.5
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(0, -r), c + Vector2(r * 0.75, 0), c + Vector2(0, r), c + Vector2(-r * 0.75, 0)]),
			UiStyle.INK)
