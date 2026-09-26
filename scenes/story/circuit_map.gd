class_name CircuitMap
extends Control

# Jerusalem from above, north up: the wall circuit of Nehemiah 3 cut into its 12 sections
# (GameState.SECTIONS), drawn as a woodcut on dark ground like StoryBackdrop.
# Finished sections stand in amber, the current one pulses, the rest lie in rubble.
# When shown, the section just finished raises itself along the ring as the reward.
# `inspect` mode is the night ride of Neh. 2:13-15: every stretch broken, a torch goes
# out by the Valley Gate, round past the Dung Gate to the Fountain Gate, and back.

const RISE_TIME    := 1.6
const RIDE_TIME    := 7.0
const PULSE_SPEED  := 2.4
const RING_SAMPLES := 12       # points per section arc

# Gate positions in a unit square (north up), after the usual reconstructions:
# Temple mount north-east, the City of David ridge running south, the western hill
# held by the Broad Wall. One per section, in SECTIONS order; each section's stretch
# runs from its gate to the next one.
const GATES := [
	Vector2(0.70, 0.13),   # Sheep Gate — north-east, by the temple
	Vector2(0.50, 0.10),   # Fish Gate — north
	Vector2(0.30, 0.16),   # Jeshanah (Old City) Gate — north-west
	Vector2(0.18, 0.33),   # Broad Wall — west
	Vector2(0.21, 0.52),   # Tower of Ovens
	Vector2(0.36, 0.70),   # Valley Gate — south-west, on the Tyropoeon
	Vector2(0.52, 0.93),   # Dung Gate — the southern tip
	Vector2(0.62, 0.80),   # Fountain Gate — by the Pool of Shelah
	Vector2(0.68, 0.58),   # Water Gate — Ophel
	Vector2(0.76, 0.42),   # Horse Gate
	Vector2(0.80, 0.30),   # East Gate
	Vector2(0.79, 0.19),   # Inspection (Miphkad) Gate
]
# The night ride: out through the Valley Gate, on to the Fountain Gate, up the torrent
# valley (Kidron) until the rubble stops the mount, then back the same way
const RIDE_FROM := 5
const RIDE_TO   := 8.4          # fractional gate index: part way up toward the Water Gate
# Where the enemy leaders watch from (Neh. 2:19, 4:7): name, bearing (unit square)
const FOES := [
	["Sanballat", "Samaria", Vector2(0.40, 0.0)],
	["Tobiah", "Ammon", Vector2(1.10, 0.62)],
	["Geshem", "Arabia", Vector2(0.30, 1.04)],
]

## Current section index (sections before it stand finished)
var section := 0:
	set(v):
		section = clampi(v, 0, GATES.size() - 1)
		queue_redraw()
var inspect := false:
	set(v):
		inspect = v
		queue_redraw()

var _rise := 1.0      # 0..1, the previous section raising itself
var _ride := 0.0      # 0..1 there and back
var _time := 0.0
var _tween: Tween

func _ready() -> void:
	resized.connect(queue_redraw)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	queue_redraw()

## Play the entrance: the stretch just finished rises, or the torch sets out
func play() -> void:
	if _tween:
		_tween.kill()
	_time = 0.0
	_rise = 1.0
	if inspect:
		_ride = 0.0
		_tween = create_tween()
		_tween.tween_property(self, "_ride", 1.0, RIDE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	elif section > 0:
		_rise = 0.0
		_tween = create_tween()
		_tween.tween_interval(0.5)
		_tween.tween_property(self, "_rise", 1.0, RISE_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

# ── Geometry ───────────────────────────────────────────────

## Map square: the right-hand part of the screen, clear of the card's text column
func _frame() -> Rect2:
	var side := minf(size.y * 0.72, size.x * 0.42)
	var centre := Vector2(size.x * 0.70, size.y * 0.46)
	return Rect2(centre - Vector2(side, side) * 0.5, Vector2(side, side))

func _to_screen(p: Vector2) -> Vector2:
	var f := _frame()
	return f.position + p * f.size

## Point along the ring at fractional gate index t (wraps). Catmull-Rom through the
## gates so the wall bends like masonry laid along a hill, not a polygon.
func _ring(t: float) -> Vector2:
	var n := GATES.size()
	t = fposmod(t, n)
	var i := int(t)
	var u := t - i
	var p0: Vector2 = GATES[(i - 1 + n) % n]
	var p1: Vector2 = GATES[i]
	var p2: Vector2 = GATES[(i + 1) % n]
	var p3: Vector2 = GATES[(i + 2) % n]
	var u2 := u * u
	var u3 := u2 * u
	return _to_screen(0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3))

func _arc(from: float, to: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := maxi(2, ceili((to - from) * RING_SAMPLES))
	for k in steps + 1:
		pts.append(_ring(lerpf(from, to, k / float(steps))))
	return pts

# ── Drawing ────────────────────────────────────────────────

func _draw() -> void:
	var f := _frame()
	var unit := f.size.x
	var ink := Color(UiStyle.CREAM, 0.18)
	var rng := RandomNumberGenerator.new()
	rng.seed = 445

	_draw_land(f)

	# The city inside: temple court, then roofs scattered over the hills
	var inner := PackedVector2Array()
	for k in GATES.size() * 4:
		inner.append(_ring(k / 4.0))
	draw_colored_polygon(inner, Color(UiStyle.DUSK.lerp(UiStyle.AMBER, 0.12), 0.9))
	var temple := Rect2(_to_screen(Vector2(0.58, 0.16)), Vector2(unit * 0.12, unit * 0.10))
	draw_rect(temple, Color(UiStyle.GOLD, 0.16))
	draw_rect(temple, Color(UiStyle.GOLD, 0.45), false, 1.5)
	draw_rect(Rect2(temple.get_center() - Vector2(unit * 0.015, unit * 0.025), Vector2(unit * 0.03, unit * 0.05)),
		Color(UiStyle.GOLD, 0.55))
	for k in 70:
		var p := Vector2(rng.randf_range(0.22, 0.78), rng.randf_range(0.2, 0.88))
		if Geometry2D.is_point_in_polygon(_to_screen(p), inner) and not temple.grow(unit * 0.02).has_point(_to_screen(p)):
			var s := unit * rng.randf_range(0.008, 0.016)
			draw_rect(Rect2(_to_screen(p), Vector2(s, s * 0.8)), Color(UiStyle.CREAM, rng.randf_range(0.05, 0.12)))

	# The wall, section by section
	var n := GATES.size()
	var width := unit * 0.018
	var pulse := 0.5 + 0.5 * sin(_time * PULSE_SPEED)
	for i in n:
		if inspect or i > section:
			_draw_rubble(i, width)
		elif i < section - 1 or (i == section - 1 and _rise >= 1.0):
			_draw_standing(_arc(i, i + 1), width, UiStyle.AMBER)
		elif i == section - 1:
			_draw_rubble(i, width)
			_draw_standing(_arc(i, i + _rise), width * (1.0 + 0.4 * (1.0 - _rise)), UiStyle.GOLD)
		else:
			# Today's work: the stretch glows and breathes
			_draw_rubble(i, width)
			draw_polyline(_arc(i, i + 1), Color(UiStyle.GOLD, 0.15 + 0.25 * pulse), width * 3.2, true)

	# Gates — a block on the ring, the name beside it
	var font := UiStyle.CINZEL_SEMI
	for i in n:
		var p := _ring(i)
		var done := not inspect and (i < section - 1 or (i == section - 1 and _rise >= 1.0))
		var here := not inspect and i == section
		var sz := unit * (0.03 if here else 0.022)
		var col: Color = UiStyle.GOLD if here else (UiStyle.AMBER if done else Color(UiStyle.CREAM, 0.45))
		draw_rect(Rect2(p - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), UiStyle.DUSK)
		draw_rect(Rect2(p - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), col, false, 2.0)
		var label: String = GameState.SECTIONS[i]["name"]
		var fs := int(unit * (0.032 if here else 0.022))
		var out := ((GATES[i] as Vector2) - Vector2(0.5, 0.5)).normalized()
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var anchor := p + out * unit * 0.035
		var pos := anchor + Vector2(0 if out.x >= 0 else -tw, fs * 0.35)
		if absf(out.x) < 0.3:
			pos.x = anchor.x - tw * 0.5
			pos.y = anchor.y + (fs if out.y > 0 else -fs * 0.2)
		var text_col: Color = UiStyle.GOLD if here else Color(UiStyle.CREAM, 0.8 if done else 0.5)
		draw_string_outline(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(UiStyle.DUSK, 0.85))
		draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_col)
		# The marks this run earned there, in a row under the name
		var mask: int = GameState.section_marks[i]
		if done and mask >= 0:
			var r := fs * 0.38
			for k in GameState.MARKS.size():
				MarkGem.draw_gem(self, pos + Vector2(r + k * r * 2.2, fs * 0.7), r, bool(mask & GameState.MARKS[k]))
	# The three who stand against the work, watching from their lands
	var small := int(unit * 0.02)
	for foe: Array in FOES:
		var p := _to_screen(foe[2])
		var who := "%s · %s" % [foe[0], foe[1]]
		var w := UiStyle.SPECTRAL_ITALIC.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
		draw_string(UiStyle.SPECTRAL_ITALIC, p - Vector2(w * 0.5, 0), who, HORIZONTAL_ALIGNMENT_LEFT, -1, small,
			Color(UiStyle.TERRACOTTA.lerp(UiStyle.CREAM, 0.35), 0.75))

	if inspect:
		_draw_torch(unit)
	else:
		_draw_compass(f, unit, ink)

## Hills and valleys: Kidron down the east, Hinnom round the west and south, the
## Mount of Olives rising beyond — faint contour lines, drawn once from a fixed seed
func _draw_land(f: Rect2) -> void:
	var line := Color(UiStyle.CREAM, 0.06)
	for k in 7:
		var r := 0.52 + k * 0.07
		var pts := PackedVector2Array()
		for a in 64 + 1:
			var ang := a / 64.0 * TAU
			var wob := 1.0 + 0.04 * sin(ang * 3.0 + k) + 0.03 * sin(ang * 5.0 + k * 2.0)
			pts.append(_to_screen(Vector2(0.5, 0.52) + Vector2(cos(ang) * 0.8, sin(ang)) * r * 0.5 * wob))
		draw_polyline(pts, line, 1.0, true)
	var valley := Color(UiStyle.DUSK.lerp(Color(0.2, 0.3, 0.35), 0.3), 0.45)
	var kidron := PackedVector2Array()
	for p: Vector2 in [Vector2(0.86, -0.02), Vector2(0.88, 0.25), Vector2(0.80, 0.55), Vector2(0.70, 0.85), Vector2(0.56, 1.02)]:
		kidron.append(_to_screen(p))
	draw_polyline(kidron, valley, f.size.x * 0.03, true)
	var hinnom := PackedVector2Array()
	for p: Vector2 in [Vector2(0.06, 0.20), Vector2(0.08, 0.55), Vector2(0.25, 0.86), Vector2(0.52, 1.02)]:
		hinnom.append(_to_screen(p))
	draw_polyline(hinnom, valley, f.size.x * 0.026, true)
	var tag := int(f.size.x * 0.017)
	for t: Array in [["Kidron", Vector2(0.93, 0.66)], ["Hinnom", Vector2(0.10, 0.74)], ["Mount of Olives", Vector2(0.97, 0.12)]]:
		var w := UiStyle.SPECTRAL_ITALIC.get_string_size(t[0], HORIZONTAL_ALIGNMENT_LEFT, -1, tag).x
		draw_string(UiStyle.SPECTRAL_ITALIC, _to_screen(t[1]) - Vector2(w * 0.5, 0), t[0],
			HORIZONTAL_ALIGNMENT_LEFT, -1, tag, Color(UiStyle.CREAM, 0.28))

func _draw_standing(pts: PackedVector2Array, width: float, col: Color) -> void:
	if pts.size() < 2:
		return
	draw_polyline(pts, Color(UiStyle.DUSK, 0.9), width + 4.0, true)
	draw_polyline(pts, col, width, true)
	# Merlons: a tick every so often across the wall line
	for k in range(1, pts.size() - 1, 2):
		var dir := (pts[k + 1] - pts[k - 1]).normalized()
		var nrm := Vector2(-dir.y, dir.x) * width * 0.55
		draw_line(pts[k] - nrm, pts[k] + nrm, Color(UiStyle.DUSK, 0.55), 1.5)

## Broken stretch: short scattered stubs and fallen stones along the line
func _draw_rubble(i: int, width: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 52 + i   # same stones every frame
	var pts := _arc(i, i + 1)
	var col := Color(UiStyle.CREAM, 0.22)
	for k in range(0, pts.size() - 1):
		if (k + i) % 3 == 1:
			continue
		var a := pts[k]
		var b := a.lerp(pts[k + 1], 0.55)
		draw_line(a, b, col, width * 0.55, true)
		draw_circle(a.lerp(pts[k + 1], 0.8) + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * width,
			width * rng.randf_range(0.15, 0.3), Color(col, 0.18))

func _draw_torch(unit: float) -> void:
	# There and back: 0→0.5 rides out, 0.5→1 rides home
	var leg := 1.0 - absf(_ride * 2.0 - 1.0)
	var p := _ring(lerpf(RIDE_FROM, RIDE_TO, leg))
	# Trail of what he has seen so far
	var seen := _arc(RIDE_FROM, lerpf(RIDE_FROM, RIDE_TO, maxf(leg, 0.001) if _ride < 0.5 else 1.0))
	draw_polyline(seen, Color(UiStyle.GOLD, 0.35), unit * 0.006, true)
	var flicker := 0.85 + 0.15 * sin(_time * 17.0) * sin(_time * 7.3)
	for k in 10:
		draw_circle(p, unit * (0.07 - k * 0.006) * flicker, Color(UiStyle.AMBER, 0.05))
	draw_circle(p, unit * 0.009, UiStyle.GOLD)

func _draw_compass(f: Rect2, unit: float, ink: Color) -> void:
	var c := f.position + Vector2(unit * 0.06, unit * 0.04)
	var fs := int(unit * 0.02)
	draw_line(c + Vector2(0, unit * 0.05), c + Vector2(0, unit * 0.012), ink, 1.5, true)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -unit * 0.004), c + Vector2(-unit * 0.01, unit * 0.018),
		c + Vector2(unit * 0.01, unit * 0.018)]), Color(UiStyle.CREAM, 0.3))
	var w := UiStyle.CINZEL.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(UiStyle.CINZEL, c + Vector2(-w * 0.5, -unit * 0.012), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(UiStyle.CREAM, 0.35))
