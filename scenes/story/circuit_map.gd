class_name CircuitMap
extends Control

# Jerusalem as a 3D diorama (CircuitDiorama, in a SubViewport) with the wall circuit of
# Nehemiah 3 cut into its 12 sections, and the gate names, marks and foes drawn over it.
# Finished sections stand, the current one glows, the rest lie in rubble. When shown,
# the section just finished raises itself along the ring as the reward.
# `inspect` mode is the night ride of Neh. 2:13-15: every stretch broken, a torch goes
# out by the Valley Gate, round past the Dung Gate to the Fountain Gate, and back.
# `picker` mode is the replay map (SectionPicker): every section this player has ever
# finished stands with its best marks, `section` is the one selected, locked ones fade.

const RISE_TIME    := 1.6
const RIDE_TIME    := 7.0
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
var picker := false
## Picker mode, per section: best marks (-1 = never finished) and whether it may be picked
var best: Array = []
var unlocked: Array = []

var _rise := 1.0      # 0..1, the previous section raising itself
var _ride := 0.0      # 0..1 there and back
var _time := 0.0
var _tween: Tween
var _container: SubViewportContainer
var _viewport: SubViewport
var _diorama: CircuitDiorama
var _overlay: Control
var _edge: GradientTexture2D
var _plaque := _make_plaque(false)
var _plaque_here := _make_plaque(true)

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

func _make_plaque(here: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(3)
	sb.anti_aliasing = true
	if here:
		sb.set_border_width_all(2)
		sb.border_color = UiStyle.TERRACOTTA
	else:
		sb.set_border_width_all(1)
		sb.border_width_bottom = 2
		sb.border_color = Color(UiStyle.RULE, 0.8)
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
	if _diorama:
		_diorama.focus_on(-1.0 if inspect else section + 0.5)
	if inspect:
		_ride = 0.0
		_tween = create_tween()
		_tween.tween_property(self, "_ride", 1.0, RIDE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	elif section > 0:
		_rise = 0.0
		_tween = create_tween()
		_tween.tween_interval(0.5)
		_tween.tween_property(self, "_rise", 1.0, RISE_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## Picker: the section whose gate or stretch is under `point` (local), or -1
func section_at(point: Vector2) -> int:
	var reach := _unit() * 0.06
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
	return i < section - 1 or (i == section - 1 and _rise >= 1.0)

func _marks(i: int) -> int:
	return best[i] if picker else GameState.section_marks[i]

## Font scale: the old map square, so text sizes match the story card
func _unit() -> float:
	return minf(size.y * 0.72, size.x * 0.42)

## World point → this control's local coordinates
func _project(p: Vector3) -> Vector2:
	var v := _diorama.camera.unproject_position(p)
	return _container.position + v * (_container.size / Vector2(_viewport.size))

# ── Overlay ────────────────────────────────────────────────

func _draw_overlay() -> void:
	var o := _overlay
	var unit := _unit()
	o.draw_texture_rect(_edge, Rect2(0, 0, size.x * 0.55, size.y), false)

	# The current / selected stretch: a gold line along the wall, breathing
	if not inspect:
		var pulse := 0.5 + 0.5 * sin(_time * PULSE_SPEED)
		var line := PackedVector2Array()
		for k in 25:
			line.append(_project(_diorama.ring_world(section + k / 24.0, CircuitDiorama.WALL_H + 0.3)))
		# Dark underlay so it reads on the sand, then a bright core
		o.draw_polyline(line, Color(UiStyle.DUSK, 0.35), unit * 0.02, true)
		o.draw_polyline(line, Color(UiStyle.GOLD, 0.35 + 0.3 * pulse), unit * 0.012, true)
		o.draw_polyline(line, Color(1.0, 0.93, 0.72, 0.8 + 0.2 * pulse), unit * 0.005, true)

	var centre := _project(_diorama.unit_to_world(CircuitDiorama.CENTER))
	var font := UiStyle.CINZEL_SEMI
	for i in CircuitDiorama.GATES.size():
		var p := _project(_diorama.ring_world(i, CircuitDiorama.TOWER.y + 0.4))
		var done := _done(i)
		var here := not inspect and i == section
		var locked: bool = picker and not unlocked[i]
		var label: String = GameState.SECTIONS[i]["name"]
		var fs := int(unit * (0.03 if here else 0.021))
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
		var alpha := 0.78 if locked else 0.94
		o.draw_line(p, anchor, Color(UiStyle.INK_SOFT, alpha * 0.8), 1.5, true)
		o.draw_circle(p, 3.0, UiStyle.TERRACOTTA if here else Color(UiStyle.PARCHMENT, alpha))
		var sb := _plaque_here if here else _plaque
		sb.bg_color = Color(UiStyle.PARCHMENT, alpha)
		o.draw_style_box(sb, Rect2(tl, box))
		var text_col: Color = UiStyle.TERRACOTTA_DEEP if here else (UiStyle.INK if done else (UiStyle.INK_MUTED if locked else UiStyle.INK_SOFT))
		o.draw_string(font, tl + Vector2(pad.x, pad.y + fs * 0.8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_col)
		if gems:
			for k in GameState.MARKS.size():
				MarkGem.draw_gem(o, tl + Vector2(pad.x + tw + gr * 1.6 + k * gr * 2.2, box.y * 0.5), gr, bool(mask & GameState.MARKS[k]))

	# The three who stand against the work, watching from their lands
	var small := int(unit * 0.02)
	for foe: Array in FOES:
		var fp := _project(_diorama.unit_to_world(foe[2]))
		var who := "%s · %s" % [foe[0], foe[1]]
		var w := UiStyle.SPECTRAL_ITALIC.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
		o.draw_string_outline(UiStyle.SPECTRAL_ITALIC, fp - Vector2(w * 0.5, 0), who, HORIZONTAL_ALIGNMENT_LEFT, -1, small,
			4, Color(UiStyle.PARCHMENT, 0.85))
		o.draw_string(UiStyle.SPECTRAL_ITALIC, fp - Vector2(w * 0.5, 0), who, HORIZONTAL_ALIGNMENT_LEFT, -1, small,
			UiStyle.TERRACOTTA_DEEP)
