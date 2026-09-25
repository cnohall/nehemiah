class_name CircuitStrip
extends Control

# The 52-day campaign as a strip of the 12 wall sections (Nehemiah 3), each as wide
# as its day count, cut into the plaque like engraved wells. Finished days fill amber.
# The current section stands taller and splits into day cells; today's cell fills
# with today's work.

const GAP := 3.0
const BAR_H := 5.0
const CUR_H := 10.0
const CELL_GAP := 2.0
const CUR_SHARE := 0.24

var day := 1:
	set(v):
		day = v
		queue_redraw()

## 0..1 share of today's work done — fills today's cell
var today_progress := 0.0:
	set(v):
		today_progress = clampf(v, 0.0, 1.0)
		queue_redraw()

func _draw() -> void:
	var sections: Array = GameState.SECTIONS
	var span := size.x - GAP * (sections.size() - 1)
	# The current section gets at least CUR_SHARE of the strip so its day cells read;
	# the rest share what's left in proportion to their day counts.
	var cur_days := 0
	for sec: Dictionary in sections:
		if (sec["days"] as Array).has(day):
			cur_days = (sec["days"] as Array).size()
	var cur_w := maxf(span * cur_days / GameState.TOTAL_DAYS, span * CUR_SHARE) if cur_days else 0.0
	var per_day := (span - cur_w) / maxi(GameState.TOTAL_DAYS - cur_days, 1)
	var x := 0.0
	for sec: Dictionary in sections:
		var days: Array = sec["days"]
		var current := days.has(day)
		var w := cur_w if current else days.size() * per_day
		if current:
			_draw_current(Rect2(x, (size.y - CUR_H) * 0.5, w, CUR_H), days)
		else:
			var r := Rect2(x, (size.y - BAR_H) * 0.5, w, BAR_H)
			_well(r)
			if days.back() < day:
				_fill(r)
		x += w + GAP

func _draw_current(r: Rect2, days: Array) -> void:
	var n := days.size()
	var cell_w := (r.size.x - CELL_GAP * (n - 1)) / n
	for i in n:
		var cell := Rect2(r.position.x + i * (cell_w + CELL_GAP), r.position.y, cell_w, r.size.y)
		var d: int = days[i]
		_well(cell)
		if d < day:
			_fill(cell)
		elif d == day:
			_pill(cell, Color(UiStyle.AMBER, 0.25), 2)
			if today_progress > 0.0:
				_fill(Rect2(cell.position, Vector2(cell.size.x * today_progress, cell.size.y)))

## Engraved channel: dark bed, shadowed top lip, lit bottom edge
func _well(r: Rect2) -> void:
	_pill(Rect2(r.position + Vector2(0, 1), r.size), Color(UiStyle.CREAM, 0.9), 2)
	_pill(r, Color(UiStyle.DUSK, 0.16), 2)
	draw_line(r.position + Vector2(1, 0.5), Vector2(r.end.x - 1, r.position.y + 0.5), Color(UiStyle.DUSK, 0.22), 1.0)

## Amber inlay with a gold highlight along the top
func _fill(r: Rect2) -> void:
	_pill(r, UiStyle.AMBER, 2)
	if r.size.x > 2.0:
		draw_line(r.position + Vector2(1, 0.5), Vector2(r.end.x - 1, r.position.y + 0.5), Color(UiStyle.GOLD, 0.9), 1.0)

func _pill(r: Rect2, c: Color, radius: int) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	draw_style_box(sb, r)
