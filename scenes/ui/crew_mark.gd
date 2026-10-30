class_name CrewMark
extends Control

# A crew slot's mark: a shape as well as a colour, so who's who reads without colour
# vision (GDD §7 accessibility). The same shape floats over the worker's head (Player's
# pip, a billboard) and sits on their HUD card. Slot order: diamond, circle, a triangle
# pointing down, square.

const INKLINE := Color(0.10, 0.07, 0.04, 0.85)

var slot := 0
var color := Color.WHITE

static func make(px: int) -> CrewMark:
	var m := CrewMark.new()
	m.custom_minimum_size = Vector2(px, px)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return m

func set_mark(s: int, c: Color) -> void:
	slot = s
	color = c
	queue_redraw()

func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5 - 1.5
	var c := size * 0.5
	var w := maxf(1.5, r * 0.22)
	if slot % 4 == 1:
		draw_circle(c, r, color)
		draw_arc(c, r, 0.0, TAU, 32, INKLINE, w, true)
		return
	var pts := outline(slot, r)
	for i in pts.size():
		pts[i] += c
	draw_colored_polygon(pts, color)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, INKLINE, w, true)

## The shape's corners round the centre, radius `r` (the circle is drawn as a circle)
static func outline(s: int, r: float) -> PackedVector2Array:
	match s % 4:
		0: return PackedVector2Array([Vector2(0, -r), Vector2(r * 0.72, 0), Vector2(0, r), Vector2(-r * 0.72, 0)])
		2: return PackedVector2Array([Vector2(-r, -r * 0.7), Vector2(r, -r * 0.7), Vector2(0, r)])
		3: return PackedVector2Array([Vector2(-r * 0.8, -r * 0.8), Vector2(r * 0.8, -r * 0.8), Vector2(r * 0.8, r * 0.8), Vector2(-r * 0.8, r * 0.8)])
	return PackedVector2Array()

## The pip over a worker's head: seen through a billboard material, its outline is the
## slot's shape whatever way the camera turns
static func pip_mesh(s: int) -> Mesh:
	match s % 4:
		1:
			var ball := SphereMesh.new()
			ball.radius = 0.17
			ball.height = 0.34
			ball.radial_segments = 16
			ball.rings = 8
			return ball
		2:
			var cone := CylinderMesh.new()   # side on: a triangle, point down at the worker
			cone.top_radius = 0.22
			cone.bottom_radius = 0.0
			cone.height = 0.36
			cone.radial_segments = 12
			cone.rings = 1
			return cone
		3:
			var box := BoxMesh.new()
			box.size = Vector3(0.3, 0.3, 0.3)
			return box
	var gem := SphereMesh.new()   # 4 segments × 1 ring: front on, a diamond
	gem.radius = 0.16
	gem.height = 0.42
	gem.radial_segments = 4
	gem.rings = 1
	return gem
