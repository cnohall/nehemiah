class_name CircuitMap
extends Control

# Jerusalem as a 3D diorama (CircuitDiorama, in a SubViewport) with the wall circuit of
# Nehemiah 3 cut into its 12 sections, and the gate names, marks and foes drawn over it.
# Finished sections stand, the current one glows, the rest lie in rubble. When shown,
# the section just finished raises itself along the ring as the reward.
# `inspect` mode is the night ride of Neh. 2:13-15: every stretch broken, a torch goes
# out by the Valley Gate, round past the Dung Gate to the Fountain Gate, and back.
# `finale` mode is the ending: the last stretch rises, then a gold line runs the whole
# ring from the Sheep Gate back to itself, each stretch lighting as it passes.
# `picker` mode is the replay map (SectionPicker): every section this player has ever
# finished stands with its best marks, `section` is the one selected, locked ones fade.
# `aged`: the scribe's working map, worn by the run (GameState.chronicle) — its edges
# darken and scorch as the days go by, it gets folded, an ink blot marks each stretch
# where the enemy got in, a lamp-oil ring the stretches worked till the stars or past
# their time, and a note in the scribe's hand beside each stretch reached.

const RISE_TIME    := 1.6
const RIDE_TIME    := 7.0
const CLOSE_TIME   := 4.5
const PULSE_SPEED  := 2.4
# The night ride: out through the Valley Gate, on to the Fountain Gate, up the torrent
# valley (Kidron) until the rubble stops the mount, then back the same way
const RIDE_FROM := 5
const RIDE_TO   := 8.4          # fractional gate index: part way up toward the Water Gate
# Where the enemy leaders watch from (Neh. 2:19, 4:7): name, land, unit-space point
const FOES := [
	["Sanballat", "Samaria", Vector2(0.30, -0.10)],
	["Tobiah", "Ammon", Vector2(1.02, 0.70)],
	["Geshem", "Arabia", Vector2(0.28, 1.07)],
]

## Current section index (sections before it stand finished)
var section := 0:
	set(v):
		section = clampi(v, 0, CircuitDiorama.GATES.size() - 1)
		if _diorama:
			_diorama.focus_on(section + 0.5)
var inspect := false
var finale := false
## No gate plaques or foes over the land — the credits roll over it
var quiet := false
var picker := false
var aged := false
## A parchment wash under the text column instead of the dark one (end screen)
var paper := false
## Picker mode, per section: best marks (-1 = never finished) and whether it may be picked
var best: Array = []
var unlocked: Array = []

var _rise := 1.0      # 0..1, the previous section raising itself
var _ride := 0.0      # 0..1 there and back
var _close := 0.0     # 0..1 finale: the gold line round the ring
var _time := 0.0
var _tween: Tween
var _container: SubViewportContainer
var _viewport: SubViewport
var _diorama: CircuitDiorama
var _overlay: Control
var _edge: GradientTexture2D
var _plaque := _make_plaque(false)
var _plaque_here := _make_plaque(true)
var _foe_plaque := _make_foe_plaque()
var _next_tab := _make_next_tab()

func _ready() -> void:
	_container = SubViewportContainer.new()
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE
	_container.add_child(_viewport)
	_diorama = CircuitDiorama.new()
	_viewport.add_child(_diorama)
	_diorama.focus_on(section + 0.5)

	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

	# A wash from the left edge, so the text column reads over the land: parchment
	# under the picker's ink text, dark under the story's cream text
	_edge = GradientTexture2D.new()
	var wash := UiStyle.PARCHMENT if picker or paper else UiStyle.DUSK
	var e := Gradient.new()
	e.set_color(0, Color(wash, 0.92))
	e.set_color(1, Color(wash, 0.0))
	e.add_point(0.5, Color(wash, 0.7))
	_edge.gradient = e

	resized.connect(_layout)
	_layout()

# Dark chip, as the in-game world tags (WorldTag): cream text on walnut, a gold rim
# on the current stretch
func _make_plaque(here: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(6)
	sb.anti_aliasing = true
	sb.bg_color = WorldTag.BG
	sb.set_border_width_all(1)
	sb.border_width_top = 2
	sb.border_color = UiStyle.GOLD if here else WorldTag.BG_EDGE
	if here:
		sb.set_border_width_all(2)
	sb.shadow_color = Color(0.08, 0.05, 0.02, 0.35)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 2)
	return sb

func _make_foe_plaque() -> StyleBoxFlat:
	var sb := _make_plaque(false)
	sb.bg_color = Color(0.36, 0.09, 0.07, 0.92)
	sb.border_color = Color(0.93, 0.50, 0.38, 0.4)
	return sb

func _make_next_tab() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(4)
	sb.anti_aliasing = true
	sb.bg_color = UiStyle.AMBER
	sb.shadow_color = Color(0.08, 0.05, 0.02, 0.35)
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(0, 1)
	return sb

# A small padlock: shackle arc over a body, centred at `c`, `r` half its width
static func _draw_lock(o: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	o.draw_arc(c + Vector2(0, -r * 0.55), r * 0.62, PI, TAU, 12, col, maxf(1.5, r * 0.3), true)
	o.draw_rect(Rect2(c + Vector2(-r, -r * 0.6), Vector2(r * 2.0, r * 1.5)), col)

func _layout() -> void:
	_container.position = Vector2.ZERO
	_container.size = size

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	var pulse := 0.5 + 0.5 * sin(_time * PULSE_SPEED)
	_diorama.set_night(inspect)
	for i in CircuitDiorama.GATES.size():
		var glow := 0.0
		if picker:
			_diorama.set_section(i, best[i] >= 0)
			glow = 0.35 + 0.55 * pulse if i == section else 0.0
		elif inspect:
			_diorama.set_section(i, false)
		elif finale:
			_diorama.set_section(i, true, _rise if i == section else 1.0)
			# Lit as the line passes, then settling to a steady warmth
			var lit := clampf(_close * CircuitDiorama.GATES.size() - i, 0.0, 1.0)
			glow = lit * (0.35 + 0.25 * pulse)
		else:
			_diorama.set_section(i, i < section, _rise if i == section - 1 else 1.0)
			glow = 0.3 + 0.5 * pulse if i == section else 0.0
		_diorama.set_glow(i, glow)
	if inspect:
		var leg := 1.0 - absf(_ride * 2.0 - 1.0)
		_diorama.set_torch(lerpf(RIDE_FROM, RIDE_TO, leg))
	_overlay.queue_redraw()

## Play the entrance: the stretch just finished rises, or the torch sets out
func play() -> void:
	if _tween:
		_tween.kill()
	_time = 0.0
	_rise = 1.0
	_close = 0.0
	if _diorama:
		_diorama.focus_on(-1.0 if inspect or finale else section + 0.5)
	if inspect:
		_ride = 0.0
		_tween = create_tween()
		_tween.tween_property(self, "_ride", 1.0, RIDE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	elif finale:
		_rise = 0.0
		_tween = create_tween()
		_tween.tween_interval(0.5)
		_tween.tween_property(self, "_rise", 1.0, RISE_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.tween_property(self, "_close", 1.0, CLOSE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	elif section > 0:
		_rise = 0.0
		_tween = create_tween()
		_tween.tween_interval(0.5)
		_tween.tween_property(self, "_rise", 1.0, RISE_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## Picker: the section whose gate or stretch is under `point` (local), or -1
func section_at(point: Vector2) -> int:
	var reach := maxf(_unit() * 0.06, 28.0 if Mobile.enabled() else 0.0)   # a fingertip, on phones
	var hit := -1
	for i in CircuitDiorama.GATES.size():
		for t: float in [float(i), i + 0.5]:
			var d := _project(_diorama.ring_world(t, 1.0)).distance_to(point)
			if d < reach:
				reach = d
				hit = i
	return hit

## Picker: the first open stretch not yet finished — where the campaign carries on (-1: all done)
func next_section() -> int:
	for i in best.size():
		if best[i] < 0 and unlocked[i]:
			return i
	return -1

func _done(i: int) -> bool:
	if inspect:
		return false
	if picker:
		return best[i] >= 0
	if finale:
		return i < section or _rise >= 1.0
	return i < section - 1 or (i == section - 1 and _rise >= 1.0)

func _marks(i: int) -> int:
	return best[i] if picker else GameState.section_marks[i]

## Font scale: the old map square, so text sizes match the story card
func _unit() -> float:
	return minf(size.y * 0.72, size.x * 0.42)

## Plaque text: phones see the map at a third of a monitor's height, so its names are
## set larger than the map itself scales — held to a readable floor
func _text(share: float, floor_px: float) -> int:
	return int(maxf(_unit() * share, floor_px) if Mobile.enabled() else _unit() * share)

## World point → this control's local coordinates
func _project(p: Vector3) -> Vector2:
	var v := _diorama.camera.unproject_position(p)
	return _container.position + v * (_container.size / Vector2(_viewport.size))

# ── Overlay ────────────────────────────────────────────────

func _draw_overlay() -> void:
	var o := _overlay
	var unit := _unit()
	o.draw_texture_rect(_edge, Rect2(0, 0, size.x * 0.55, size.y), false)
	var next := next_section() if picker else -1
	if aged and not picker and not inspect:
		_draw_age(o, unit)

	# Picker: stretches not yet built are traced where they will stand, dashed on the
	# ground — the next one in amber, marching; locked ones faint
	if picker:
		for i in CircuitDiorama.GATES.size():
			if best[i] >= 0:
				continue
			var is_next := i == next
			var col := Color(1.0, 0.78, 0.35) if is_next else Color(WorldTag.TEXT, 0.75 if unlocked[i] else 0.5)
			var w := unit * (0.008 if is_next else 0.005)
			var steps := 24
			var phase := fposmod(_time * 1.5, 2.0) if is_next else 0.0
			for k in steps:
				if (k + int(phase)) % 2 == 1:
					continue
				var a := _project(_diorama.ring_world(i + float(k) / steps, 1.0))
				var b := _project(_diorama.ring_world(i + float(k + 1) / steps, 1.0))
				o.draw_line(a, b, Color(UiStyle.DUSK, 0.45), w * 2.0, true)
				o.draw_line(a, b, col, w, true)

	# The current / selected stretch: a gold line along the wall, breathing.
	# The finale draws it round the whole ring as far as it has closed.
	var from := 0.0 if finale else float(section)
	var span := _close * CircuitDiorama.GATES.size() if finale else 1.0
	if not inspect and span > 0.0:
		var pulse := 0.5 + 0.5 * sin(_time * PULSE_SPEED)
		var line := PackedVector2Array()
		var steps := maxi(2, int(span * 24.0))
		for k in steps + 1:
			line.append(_project(_diorama.ring_world(from + span * k / steps, CircuitDiorama.WALL_H + 0.3)))
		# Dark underlay so it reads on the sand, then a bright core
		o.draw_polyline(line, Color(UiStyle.DUSK, 0.35), unit * 0.02, true)
		o.draw_polyline(line, Color(UiStyle.GOLD, 0.35 + 0.3 * pulse), unit * 0.012, true)
		o.draw_polyline(line, Color(1.0, 0.93, 0.72, 0.8 + 0.2 * pulse), unit * 0.005, true)

	if quiet:
		return
	var centre := _project(_diorama.unit_to_world(CircuitDiorama.CENTER))
	var font := UiStyle.CINZEL_SEMI
	for i in CircuitDiorama.GATES.size():
		var p := _project(_diorama.ring_world(i, CircuitDiorama.TOWER.y + 0.4))
		var done := _done(i)
		var here := not inspect and not finale and i == section
		var locked: bool = picker and not unlocked[i]
		var label: String = tr(GameState.SECTIONS[i]["name"])
		var fs := _text(0.03, 15.0) if here else _text(0.021, 11.0)
		var mask := _marks(i)
		var gems := done and mask >= 0
		# A small parchment plaque: the name, and the marks earned there beside it
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var gr := fs * 0.4
		var gw := gr * 2.3 * GameState.MARKS.size() + gr * 0.6 if gems else 0.0
		var lw := fs * 0.9 if locked else 0.0     # a padlock before the name
		var pad := Vector2(fs * 0.5, fs * 0.3)
		var box := Vector2(lw + tw + gw + pad.x * 2.0, fs + pad.y * 2.0)
		var out := (p - centre).normalized()
		var anchor := p + out * unit * 0.026
		var tl: Vector2
		if absf(out.x) < 0.35:
			tl = Vector2(anchor.x - box.x * 0.5, anchor.y if out.y > 0 else anchor.y - box.y)
		else:
			tl = Vector2(anchor.x if out.x >= 0 else anchor.x - box.x, anchor.y - box.y * 0.5)
		var alpha := 0.62 if locked else 0.94
		o.draw_line(p, anchor, Color(WorldTag.BG, alpha * 0.8), 2.0, true)
		o.draw_circle(p, 3.5, UiStyle.GOLD if here else Color(WorldTag.BG, alpha))
		var sb := _plaque_here if here else _plaque
		sb.bg_color = Color(WorldTag.BG, alpha)
		o.draw_style_box(sb, Rect2(tl, box))
		var text_col: Color = Color(1.0, 0.86, 0.55) if here else (WorldTag.TEXT if done else (Color(WorldTag.TEXT_DIM, 0.6) if locked else WorldTag.TEXT_DIM))
		if locked:
			_draw_lock(o, tl + Vector2(pad.x + fs * 0.3, box.y * 0.5 + fs * 0.08), fs * 0.3, text_col)
		o.draw_string(font, tl + Vector2(pad.x + lw, pad.y + fs * 0.8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_col)
		if gems:
			for k in GameState.MARKS.size():
				MarkGem.draw_gem(o, tl + Vector2(pad.x + tw + gr * 1.5 + k * gr * 2.3, box.y * 0.5), gr, bool(mask & GameState.MARKS[k]))
		# The next stretch to build: an amber tab riding on the plaque, bobbing
		if i == next:
			var ns := tr("Next")
			var nfs := int(unit * 0.02)
			var nw := UiStyle.CINZEL_BOLD.get_string_size(ns, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x
			var bob := 2.0 * sin(_time * 3.0)
			var tab := Rect2(tl + Vector2(fs * 0.3, -nfs * 1.25 + bob), Vector2(nw + nfs, nfs * 1.35))
			o.draw_style_box(_next_tab, tab)
			o.draw_string(UiStyle.CINZEL_BOLD, tab.position + Vector2(nfs * 0.5, nfs * 1.0), ns,
				HORIZONTAL_ALIGNMENT_LEFT, -1, nfs, UiStyle.INK)

	# The three who stand against the work, watching from their lands: oxblood chips
	# with a pennant, so the threat reads at a glance. In the finale they fade as the
	# ring closes: "they lost their confidence" (Neh. 6:16)
	var fa := 1.0 - _close if finale else 1.0
	if fa <= 0.0:
		return
	_foe_plaque.bg_color = Color(0.36, 0.09, 0.07, 0.92 * fa)
	_foe_plaque.border_color = Color(0.93, 0.50, 0.38, 0.4 * fa)
	_foe_plaque.shadow_color = Color(0.08, 0.05, 0.02, 0.35 * fa)
	var ink := Color(WorldTag.TEXT, WorldTag.TEXT.a * fa)
	var dim := Color(WorldTag.TEXT_DIM, WorldTag.TEXT_DIM.a * fa)
	var small := _text(0.021, 11.0)
	var tiny := _text(0.016, 9.0)
	for foe: Array in FOES:
		var fp := _project(_diorama.unit_to_world(foe[2]))
		var who: String = tr(foe[0])
		var land: String = tr(foe[1])
		var nf := UiStyle.CINZEL_BOLD
		var lf := UiStyle.SPECTRAL_ITALIC
		var nw := nf.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
		var lw := lf.get_string_size(land, HORIZONTAL_ALIGNMENT_LEFT, -1, tiny).x
		var flag := small * 0.9
		var pad := Vector2(small * 0.5, small * 0.3)
		var box := Vector2(flag + nw + lw + small * 0.5 + pad.x * 2.0, small + pad.y * 2.0)
		var tl := fp - box * 0.5
		o.draw_style_box(_foe_plaque, Rect2(tl, box))
		# Pennant: a pole and a swallow-tailed flag
		var fx := tl + Vector2(pad.x, pad.y)
		o.draw_line(fx + Vector2(flag * 0.15, 0), fx + Vector2(flag * 0.15, small), dim, 1.5, true)
		o.draw_colored_polygon(PackedVector2Array([fx + Vector2(flag * 0.2, 0), fx + Vector2(flag * 0.85, small * 0.12),
			fx + Vector2(flag * 0.62, small * 0.3), fx + Vector2(flag * 0.85, small * 0.48), fx + Vector2(flag * 0.2, small * 0.55)]),
			Color(0.93, 0.36, 0.26, fa))
		var base := tl.y + pad.y + small * 0.8
		o.draw_string(nf, Vector2(fx.x + flag, base), who, HORIZONTAL_ALIGNMENT_LEFT, -1, small, ink)
		o.draw_string(lf, Vector2(fx.x + flag + nw + small * 0.4, base), land, HORIZONTAL_ALIGNMENT_LEFT, -1, tiny, dim)

# ── Age (the scribe's map, worn by the run) ────────────────

const INK_BLOT  := Color(0.13, 0.08, 0.05, 0.8)
const OIL_RING  := Color(0.46, 0.29, 0.12)
const SCORCH    := Color(0.30, 0.17, 0.07)
const NOTE_INK  := Color(0.20, 0.12, 0.07, 0.85)

func _draw_age(o: Control, unit: float) -> void:
	var age := 1.0 if finale else clampf(float(GameState.current_day) / GameState.TOTAL_DAYS, 0.0, 1.0)
	var reached := GameState.SECTIONS.size() if finale else mini(section + 1, GameState.SECTIONS.size())
	# Edges: darkening in bands, deeper as the days go by
	var bands := 14
	var w := unit * 0.012
	for k in bands:
		var a := (0.05 + 0.3 * age) * pow(1.0 - float(k) / bands, 2.0)
		o.draw_rect(Rect2(Vector2(k * w, k * w), size - Vector2(k * w, k * w) * 2.0), Color(SCORCH, a), false, w)
	# Folds: once a third of the way round, again at two thirds
	if reached >= 4:
		_crease(o, Vector2(size.x * 0.62, 0), Vector2(size.x * 0.62, size.y))
	if reached >= 8:
		_crease(o, Vector2(0, size.y * 0.5), Vector2(size.x, size.y * 0.5))
	var centre := _project(_diorama.unit_to_world(CircuitDiorama.CENTER))
	for i in reached:
		var c: Dictionary = GameState.chronicle[i]
		var p := _project(_diorama.ring_world(i + 0.5, 0.0))
		var out := (p - centre).normalized()
		var rng := RandomNumberGenerator.new()
		rng.seed = 4200 + i
		# A lamp-oil ring where the lamp stood through a long day's work
		if c["nightfalls"] > 0 or c["late"]:
			var rc := p + out * unit * 0.07 + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * unit * 0.02
			var rr := unit * rng.randf_range(0.04, 0.05)
			o.draw_circle(rc, rr, Color(OIL_RING, 0.07))
			o.draw_arc(rc, rr, 0.0, TAU, 48, Color(OIL_RING, 0.32), unit * 0.005, true)
			o.draw_arc(rc, rr * 0.93, 0.4, TAU - 0.9, 40, Color(OIL_RING, 0.18), unit * 0.003, true)
			if c["nightfalls"] > 1:
				o.draw_arc(rc + Vector2(rr * 0.35, rr * 0.2), rr * 0.96, 0.0, TAU, 48, Color(OIL_RING, 0.2), unit * 0.004, true)
		# An ink blot where the enemy got in — bigger for more
		if c["breaches"] > 0:
			_blot(o, p + out * unit * 0.035, unit * (0.012 + 0.009 * sqrt(float(c["breaches"]))), rng)
		if not quiet:
			_note(o, p - out * unit * 0.06, _note_for(c), unit, rng)

# Where the sheet was folded: a pale ridge with a shadow along one side
func _crease(o: Control, a: Vector2, b: Vector2) -> void:
	var n := (b - a).orthogonal().normalized()
	o.draw_line(a + n * 2.0, b + n * 2.0, Color(SCORCH, 0.16), 3.0, true)
	o.draw_line(a, b, Color(1.0, 0.97, 0.9, 0.22), 2.0, true)

func _blot(o: Control, c: Vector2, r: float, rng: RandomNumberGenerator) -> void:
	var pts := PackedVector2Array()
	var n := 16
	for k in n:
		var a := TAU * k / n
		pts.append(c + Vector2(cos(a), sin(a)) * r * rng.randf_range(0.72, 1.25))
	o.draw_colored_polygon(pts, INK_BLOT)
	for k in 5:
		var a := rng.randf() * TAU
		o.draw_circle(c + Vector2(cos(a), sin(a)) * r * rng.randf_range(1.5, 2.4), r * rng.randf_range(0.08, 0.2), INK_BLOT)

## What the scribe wrote beside a stretch (one or two short lines)
func _note_for(c: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	if c["breaches"] > 0:
		lines.append(tr_n("%d got in", "%d got in", c["breaches"]) % c["breaches"])
	elif c["done"]:
		lines.append(tr("none got in"))
	if c["nightfalls"] > 0:
		lines.append(tr("worked till the stars"))
	elif c["spare"] > 0:
		lines.append(tr_n("%d day to spare", "%d days to spare", c["spare"]) % c["spare"])
	elif c["knocked"] > 0:
		lines.append(tr("rebuilt what fell"))
	return lines

# Italic, a little aslant, like a hand in the margin
func _note(o: Control, at: Vector2, lines: PackedStringArray, unit: float, rng: RandomNumberGenerator) -> void:
	if lines.is_empty():
		return
	var fs := int(unit * 0.018)
	var font := UiStyle.SPECTRAL_ITALIC
	o.draw_set_transform(at, rng.randf_range(-0.09, 0.02), Vector2.ONE)
	for k in lines.size():
		var tw := font.get_string_size(lines[k], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at_line := Vector2(-tw * 0.5, k * fs * 1.1)
		o.draw_string_outline(font, at_line, lines[k], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(UiStyle.PARCHMENT, 0.55))
		o.draw_string(font, at_line, lines[k], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, NOTE_INK)
	o.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
