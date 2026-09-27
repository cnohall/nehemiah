class_name TagIcon
extends Control

# Little isometric material icons, drawn in code so they stay crisp at any size and
# match the world's chunky look: stone block, log ends, mortar tub, lime sack,
# water jar, beam, rubble. Also used by the HUD.

const INKLINE := Color(0.10, 0.07, 0.04, 0.55)

var kind := "stone"

static func make(k: String, px: int) -> TagIcon:
	var t := TagIcon.new()
	t.kind = k.trim_suffix("s") if k == "beams" else k
	t.custom_minimum_size = Vector2(px, px)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	match kind:
		"stone":  _block(o, s, Vector2(0.5, 0.52), 0.42, 0.26, Color(0.90, 0.88, 0.83))
		"rubble":
			_block(o, s, Vector2(0.34, 0.6), 0.26, 0.18, Color(0.70, 0.66, 0.60))
			_block(o, s, Vector2(0.66, 0.5), 0.24, 0.2, Color(0.62, 0.58, 0.52))
		"wood":   _logs(o, s)
		"beam":   _beam(o, s)
		"mortar": _tub(o, s)
		"lime":   _sack(o, s)
		"water":  _jar(o, s)

func _p(o: Vector2, s: float, x: float, y: float) -> Vector2:
	return o + Vector2(x, y) * s

func _poly(pts: PackedVector2Array, c: Color) -> void:
	draw_colored_polygon(pts, c)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, INKLINE, 1.2, true)

# Isometric block: centre of the top face, half-width, height (fractions of s)
func _block(o: Vector2, s: float, c: Vector2, w: float, h: float, col: Color) -> void:
	var dy := w * 0.5
	var top := c - Vector2(0, h * 0.5)
	var t := [top + Vector2(0, -dy), top + Vector2(w, 0), top + Vector2(0, dy), top + Vector2(-w, 0)]
	var P := func(v: Vector2) -> Vector2: return o + v * s
	var down := Vector2(0, h)
	_poly(PackedVector2Array([P.call(t[3]), P.call(t[2]), P.call(t[2] + down), P.call(t[3] + down)]), col.darkened(0.18))
	_poly(PackedVector2Array([P.call(t[2]), P.call(t[1]), P.call(t[1] + down), P.call(t[2] + down)]), col.darkened(0.34))
	_poly(PackedVector2Array([P.call(t[0]), P.call(t[1]), P.call(t[2]), P.call(t[3])]), col)
	# Chamfer highlight along the front top edges
	draw_polyline(PackedVector2Array([P.call(t[3] + Vector2(0.03, 0.01)), P.call(t[2] + Vector2(0, -0.02)), P.call(t[1] + Vector2(-0.03, 0.01))]),
		Color(1, 1, 1, 0.55), 1.4, true)

func _ellipse(c: Vector2, r: Vector2, n := 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	return pts

func _logs(o: Vector2, s: float) -> void:
	var bark := Color(0.52, 0.32, 0.17)
	var grain := Color(0.86, 0.66, 0.42)
	for c: Vector2 in [Vector2(0.3, 0.68), Vector2(0.7, 0.68), Vector2(0.5, 0.36)]:
		# Log body running back, then the cut end
		var e := _p(o, s, c.x, c.y)
		var back := e + Vector2(s * 0.14, -s * 0.1)
		var r := s * 0.19
		_poly(_ellipse(back, Vector2(r, r)), bark.darkened(0.25))
		draw_colored_polygon(PackedVector2Array([e + Vector2(0, -r), back + Vector2(0, -r), back + Vector2(0, r), e + Vector2(0, r)]), bark.darkened(0.12))
		_poly(_ellipse(e, Vector2(r, r)), bark)
		draw_colored_polygon(_ellipse(e, Vector2(r, r) * 0.72), grain)
		draw_arc(e, r * 0.38, 0, TAU, 16, grain.darkened(0.25), 1.2, true)

func _beam(o: Vector2, s: float) -> void:
	var col := Color(0.70, 0.48, 0.28)
	var a := Vector2(0.1, 0.62)
	var b := Vector2(0.78, 0.28)
	var w := Vector2(0.14, 0.07)
	var h := Vector2(0, 0.16)
	var P := func(v: Vector2) -> Vector2: return o + v * s
	_poly(PackedVector2Array([P.call(a), P.call(a + w), P.call(a + w + h), P.call(a + h)]), col.darkened(0.3))
	_poly(PackedVector2Array([P.call(a + w), P.call(b + w), P.call(b + w + h), P.call(a + w + h)]), col.darkened(0.15))
	_poly(PackedVector2Array([P.call(a), P.call(b), P.call(b + w), P.call(a + w)]), col)

func _tub(o: Vector2, s: float) -> void:
	var wood := Color(0.50, 0.33, 0.19)
	_poly(PackedVector2Array([_p(o, s, 0.12, 0.44), _p(o, s, 0.88, 0.44), _p(o, s, 0.78, 0.88), _p(o, s, 0.22, 0.88)]), wood)
	draw_line(_p(o, s, 0.16, 0.6), _p(o, s, 0.84, 0.6), wood.darkened(0.4), 2.0, true)
	draw_line(_p(o, s, 0.2, 0.78), _p(o, s, 0.8, 0.78), wood.darkened(0.4), 2.0, true)
	_poly(_ellipse(_p(o, s, 0.5, 0.44), Vector2(s * 0.38, s * 0.14)), wood.lightened(0.15))
	draw_colored_polygon(_ellipse(_p(o, s, 0.5, 0.44), Vector2(s * 0.31, s * 0.1)), Color(0.72, 0.70, 0.66))
	draw_colored_polygon(_ellipse(_p(o, s, 0.44, 0.42), Vector2(s * 0.12, s * 0.04)), Color(0.86, 0.85, 0.82))

func _sack(o: Vector2, s: float) -> void:
	var cloth := Color(0.93, 0.91, 0.86)
	_poly(_ellipse(_p(o, s, 0.5, 0.64), Vector2(s * 0.34, s * 0.28)), cloth.darkened(0.08))
	draw_colored_polygon(_ellipse(_p(o, s, 0.45, 0.6), Vector2(s * 0.24, s * 0.2)), cloth)
	_poly(PackedVector2Array([_p(o, s, 0.38, 0.4), _p(o, s, 0.62, 0.4), _p(o, s, 0.68, 0.18), _p(o, s, 0.32, 0.18)]), cloth.darkened(0.04))
	draw_line(_p(o, s, 0.36, 0.38), _p(o, s, 0.64, 0.38), Color(0.55, 0.38, 0.22), 3.0, true)

func _jar(o: Vector2, s: float) -> void:
	var clay := Color(0.76, 0.44, 0.26)
	_poly(_ellipse(_p(o, s, 0.5, 0.6), Vector2(s * 0.3, s * 0.32)), clay)
	draw_colored_polygon(_ellipse(_p(o, s, 0.42, 0.54), Vector2(s * 0.12, s * 0.16)), clay.lightened(0.18))
	_poly(PackedVector2Array([_p(o, s, 0.38, 0.32), _p(o, s, 0.62, 0.32), _p(o, s, 0.6, 0.16), _p(o, s, 0.4, 0.16)]), clay.darkened(0.1))
	_poly(_ellipse(_p(o, s, 0.5, 0.16), Vector2(s * 0.13, s * 0.05)), clay.darkened(0.25))
	draw_colored_polygon(_ellipse(_p(o, s, 0.5, 0.16), Vector2(s * 0.09, s * 0.032)), Color(0.36, 0.62, 0.82))
