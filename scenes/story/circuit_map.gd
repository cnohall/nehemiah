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
	var wash := UiStyle.PARCHMENT if picker else UiStyle.DUSK
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
		var gr := fs * 0.32
		var gw := gr * 2.2 * GameState.MARKS.size() + gr * 0.6 if gems else 0.0
		var pad := Vector2(fs * 0.5, fs * 0.3)
		var box := Vector2(tw + gw + pad.x * 2.0, fs + pad.y * 2.0)
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
		o.draw_string(font, tl + Vector2(pad.x, pad.y + fs * 0.8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_col)
		if gems:
			for k in GameState.MARKS.size():
				MarkGem.draw_gem(o, tl + Vector2(pad.x + tw + gr * 1.6 + k * gr * 2.2, box.y * 0.5), gr, bool(mask & GameState.MARKS[k]))

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
