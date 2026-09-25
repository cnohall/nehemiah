class_name UiStyle
extends RefCounted

# Design tokens (OKLCH source in the comments) and the project Theme built from them.
# tools/build_theme.gd saves the Theme to assets/ui/theme.tres, which project.godot
# uses as the global GUI theme — edit tokens here, then re-run the tool.
#   Godot --headless --path . --script res://tools/build_theme.gd
# Phones build a second variant at runtime (build_theme(true), set on the root window
# by Mobile): sizes in dp/sp with 48dp touch targets. Same palette, same identity.

# ── Palette ────────────────────────────────────────────────

const PARCHMENT       := Color(0.959, 0.932, 0.883)  # oklch(95% 0.018 82)   panels
const PARCHMENT_DEEP  := Color(0.899, 0.851, 0.779)  # oklch(89% 0.028 78)   tracks, wells
const CREAM           := Color(0.982, 0.966, 0.933)  # oklch(97.5% 0.012 85) text on dark
const INK             := Color(0.138, 0.094, 0.057)  # oklch(22% 0.025 60)   primary text
const INK_SOFT        := Color(0.391, 0.318, 0.257)  # oklch(45% 0.035 62)   secondary text
const INK_MUTED       := Color(0.573, 0.515, 0.451)  # oklch(62% 0.03 70)    labels, hints
const RULE            := Color(0.716, 0.630, 0.526)  # oklch(72% 0.045 72)   borders, dividers
const TERRACOTTA      := Color(0.676, 0.313, 0.124)  # oklch(54% 0.135 45)   primary accent, danger
const TERRACOTTA_DEEP := Color(0.541, 0.224, 0.082)  # oklch(45% 0.12 42)    pressed, carved lip
const AMBER           := Color(0.825, 0.516, 0.145)  # oklch(68% 0.14 65)    progress, warnings
const GOLD            := Color(0.877, 0.684, 0.339)  # oklch(78% 0.12 80)    ornament, focus
const OLIVE           := Color(0.444, 0.547, 0.239)  # oklch(60% 0.11 125)   health, success
const DUSK            := Color(0.105, 0.068, 0.044)  # oklch(19% 0.02 55)    scrims, shadows

# ── Type ───────────────────────────────────────────────────

const CINZEL          := preload("res://assets/fonts/Cinzel/static/Cinzel-Regular.ttf")
const CINZEL_SEMI     := preload("res://assets/fonts/Cinzel/static/Cinzel-SemiBold.ttf")
const CINZEL_BOLD     := preload("res://assets/fonts/Cinzel/static/Cinzel-Bold.ttf")
const CINZEL_XBOLD    := preload("res://assets/fonts/Cinzel/static/Cinzel-ExtraBold.ttf")
const SPECTRAL        := preload("res://assets/fonts/Spectral/Spectral-Regular.ttf")
const SPECTRAL_MEDIUM := preload("res://assets/fonts/Spectral/Spectral-Medium.ttf")
const SPECTRAL_ITALIC := preload("res://assets/fonts/Spectral/Spectral-Italic.ttf")

## Cinzel is an inscriptional capital face — it wants air between letters
static func tracked(base: Font, spacing: int) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = base
	f.spacing_glyph = spacing
	return f

# ── Stylebox helpers ───────────────────────────────────────

static func box(bg: Color, pad := Vector2(16, 12), radius := 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad.x
	s.content_margin_right = pad.x
	s.content_margin_top = pad.y
	s.content_margin_bottom = pad.y
	s.anti_aliasing = true
	return s

static func bordered(s: StyleBoxFlat, color: Color, width := 1, bottom := -1) -> StyleBoxFlat:
	s.border_color = color
	s.set_border_width_all(width)
	if bottom >= 0:
		s.border_width_bottom = bottom
	return s

static func shadowed(s: StyleBoxFlat, size: int, alpha: float, offset_y := 3.0) -> StyleBoxFlat:
	s.shadow_color = Color(DUSK, alpha)
	s.shadow_size = size
	s.shadow_offset = Vector2(0, offset_y)
	return s

## Parchment tablet with a darker carved lip along the bottom
static func plaque(pad := Vector2(22, 14), alpha := 0.94) -> StyleBoxFlat:
	var s := bordered(box(Color(PARCHMENT, alpha), pad, 3), Color(RULE, 0.55), 1, 3)
	return shadowed(s, 10, 0.22)

static func empty(pad := Vector2.ZERO) -> StyleBoxEmpty:
	var s := StyleBoxEmpty.new()
	s.content_margin_left = pad.x
	s.content_margin_right = pad.x
	s.content_margin_top = pad.y
	s.content_margin_bottom = pad.y
	return s

# ── Theme ──────────────────────────────────────────────────

static func build_theme(mobile := false) -> Theme:
	var t := Theme.new()
	t.default_font = SPECTRAL
	t.default_font_size = 16 if mobile else 18

	_labels(t, mobile)
	_buttons(t, mobile)
	_panels(t, mobile)
	_inputs(t, mobile)
	return t

static func _label(t: Theme, type: String, font: Font, size: int, color: Color) -> void:
	t.set_type_variation(type, "Label")
	t.set_font("font", type, font)
	t.set_font_size("font_size", type, size)
	t.set_color("font_color", type, color)

static func _labels(t: Theme, m: bool) -> void:
	t.set_color("font_color", "Label", INK)
	# Phone sizes follow Material's type scale (body 14–16sp, labels ≥ 12sp)
	_label(t, "Display",  tracked(CINZEL_XBOLD, 6 if m else 10), 76 if m else 124, INK)
	_label(t, "Heading",  tracked(CINZEL_BOLD, 3),   24 if m else 30,  INK)
	_label(t, "Numeral",  CINZEL_BOLD,               26 if m else 34,  INK)
	_label(t, "Eyebrow",  tracked(CINZEL_SEMI, 3 if m else 4), 12 if m else 13, INK_MUTED)
	_label(t, "Caption",  SPECTRAL_ITALIC,           14 if m else 16,  INK_SOFT)
	_label(t, "Body",     SPECTRAL,                  15 if m else 17,  INK_SOFT)
	_label(t, "Verse",    SPECTRAL_ITALIC,           15 if m else 17,  INK_SOFT)

static func _button_colors(t: Theme, type: String, normal: Color, hover: Color, pressed: Color, disabled: Color) -> void:
	t.set_color("font_color", type, normal)
	t.set_color("font_hover_color", type, hover)
	t.set_color("font_focus_color", type, hover)
	t.set_color("font_hover_pressed_color", type, pressed)
	t.set_color("font_pressed_color", type, pressed)
	t.set_color("font_disabled_color", type, disabled)

static func _button_styles(t: Theme, type: String, normal: StyleBox, hover: StyleBox,
		pressed: StyleBox, disabled: StyleBox, focus: StyleBox) -> void:
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("hover_pressed", type, pressed)
	t.set_stylebox("disabled", type, disabled)
	t.set_stylebox("focus", type, focus)

static func _focus_ring(radius := 3) -> StyleBoxFlat:
	var s := bordered(box(Color(0, 0, 0, 0), Vector2.ZERO, radius), GOLD, 2)
	s.draw_center = false
	s.set_expand_margin_all(3)
	return s

static func _buttons(t: Theme, m: bool) -> void:
	# Primary (also the plain Button default, so a stray Button still looks at home).
	# Phones: 14dp vertical pad + 15sp text + lip ≈ 48dp, Material's minimum target.
	var pad := Vector2(24, 14) if m else Vector2(28, 12)
	var r := 4 if m else 2
	var normal  := bordered(box(TERRACOTTA, pad, r), TERRACOTTA_DEEP, 0, 3)
	var hover   := bordered(box(TERRACOTTA.lightened(0.08), pad, r), TERRACOTTA_DEEP, 0, 3)
	var pressed := box(TERRACOTTA_DEEP, pad, r)
	pressed.border_width_top = 3                  # pressed into the stone
	pressed.border_color = Color(DUSK, 0.35)
	var disabled := bordered(box(Color(RULE, 0.55), pad, r), Color(RULE, 0.8), 0, 3)
	for type: String in ["Button", "PrimaryButton"]:
		if type != "Button":
			t.set_type_variation(type, "Button")
		_button_styles(t, type, normal, hover, pressed, disabled, _focus_ring())
		_button_colors(t, type, CREAM, Color.WHITE, CREAM, Color(CREAM, 0.8))
		t.set_font("font", type, tracked(CINZEL_BOLD, 2))
		t.set_font_size("font_size", type, 15 if m else 17)

	# Ghost — secondary actions. Phones get a parchment fill: an outline alone
	# vanishes over bright sand.
	t.set_type_variation("GhostButton", "Button")
	var g_pad := pad + Vector2(0, 1.5) if m else pad
	var g_normal := bordered(box(Color(PARCHMENT, 0.8) if m else Color(0, 0, 0, 0), g_pad, r), Color(RULE, 0.9), 1)
	var g_hover  := bordered(box(Color(TERRACOTTA, 0.07), g_pad, r), TERRACOTTA, 1)
	var g_press  := bordered(box(Color(TERRACOTTA, 0.14), g_pad, r), TERRACOTTA_DEEP, 1)
	_button_styles(t, "GhostButton", g_normal, g_hover, g_press, g_normal, _focus_ring())
	_button_colors(t, "GhostButton", INK_SOFT, TERRACOTTA, TERRACOTTA_DEEP, Color(INK_MUTED, 0.6))
	t.set_font("font", "GhostButton", tracked(CINZEL_BOLD, 2))
	t.set_font_size("font_size", "GhostButton", 15 if m else 16)

	# Icon-only (pause, settings): round parchment disc — 48dp with a 24dp glyph
	t.set_type_variation("IconButton", "Button")
	var i_normal := shadowed(bordered(box(Color(PARCHMENT, 0.92), Vector2(12, 12), 24), Color(RULE, 0.6), 1), 6, 0.18, 2.0)
	var i_press  := bordered(box(PARCHMENT_DEEP, Vector2(12, 12), 24), TERRACOTTA, 1)
	_button_styles(t, "IconButton", i_normal, i_normal, i_press, i_normal, _focus_ring(24))
	for c: String in ["icon_normal_color", "icon_hover_color", "icon_focus_color", "icon_hover_pressed_color"]:
		t.set_color(c, "IconButton", INK_SOFT)
	t.set_color("icon_pressed_color", "IconButton", TERRACOTTA_DEEP)
	# Flat variant for sheet headers — no disc until pressed
	t.set_type_variation("FlatIconButton", "IconButton")
	var f_normal := box(Color(0, 0, 0, 0), Vector2(12, 12), 24)
	_button_styles(t, "FlatIconButton", f_normal, box(Color(TERRACOTTA, 0.08), Vector2(12, 12), 24),
		box(Color(TERRACOTTA, 0.16), Vector2(12, 12), 24), f_normal, _focus_ring(24))

	# Title-screen list entry: bare text; hover/focus lays a terracotta bookmark down the left
	t.set_type_variation("MenuItem", "Button")
	var m_pad := Vector2(22, 9)
	var m_normal := bordered(box(Color(0, 0, 0, 0), m_pad, 0), Color(0, 0, 0, 0), 0)
	m_normal.border_width_left = 3
	var m_hover := bordered(box(Color(PARCHMENT, 0.55), m_pad, 0), TERRACOTTA, 0)
	m_hover.border_width_left = 3
	var m_press := m_hover.duplicate() as StyleBoxFlat
	m_press.bg_color = Color(PARCHMENT_DEEP, 0.7)
	_button_styles(t, "MenuItem", m_normal, m_hover, m_press, m_normal, m_hover)
	_button_colors(t, "MenuItem", INK, TERRACOTTA_DEEP, TERRACOTTA_DEEP, Color(INK_MUTED, 0.7))
	t.set_font("font", "MenuItem", tracked(CINZEL_SEMI, 3))
	t.set_font_size("font_size", "MenuItem", 25)
	t.set_constant("align_to_largest_stylebox", "MenuItem", 1)

	# Segmented toggle (settings choices)
	t.set_type_variation("Segment", "Button")
	var s_pad := Vector2(14, 13) if m else Vector2(18, 9)
	var s_normal := bordered(box(Color(PARCHMENT_DEEP, 0.55), s_pad), Color(RULE, 0.7), 1)
	var s_hover  := bordered(box(Color(PARCHMENT_DEEP, 0.95), s_pad), TERRACOTTA, 1)
	var s_on     := bordered(box(TERRACOTTA, s_pad), TERRACOTTA_DEEP, 1)
	_button_styles(t, "Segment", s_normal, s_hover, s_on, s_normal, _focus_ring())
	_button_colors(t, "Segment", INK_SOFT, TERRACOTTA_DEEP, CREAM, INK_MUTED)
	t.set_font("font", "Segment", tracked(CINZEL_SEMI, 2))
	t.set_font_size("font_size", "Segment", 13 if m else 14)

static func _panels(t: Theme, m: bool) -> void:
	var pl := plaque(Vector2(14, 9)) if m else plaque()
	t.set_stylebox("panel", "PanelContainer", pl)
	t.set_type_variation("Plaque", "PanelContainer")
	t.set_stylebox("panel", "Plaque", pl)
	t.set_type_variation("Card", "PanelContainer")
	t.set_stylebox("panel", "Card", plaque(Vector2(10, 7) if m else Vector2(14, 10), 0.92))
	t.set_type_variation("Modal", "PanelContainer")
	var modal := bordered(box(PARCHMENT, Vector2(28, 22) if m else Vector2(44, 38), 6 if m else 4), Color(RULE, 0.6), 1, 4)
	t.set_stylebox("panel", "Modal", shadowed(modal, 36, 0.4, 10.0))

	t.set_stylebox("panel", "TooltipPanel", bordered(box(Color(DUSK, 0.94), Vector2(10, 6)), Color(GOLD, 0.4), 1))
	t.set_color("font_color", "TooltipLabel", CREAM)
	t.set_font("font", "TooltipLabel", SPECTRAL)
	t.set_font_size("font_size", "TooltipLabel", 15)

static func _inputs(t: Theme, m: bool) -> void:
	# LineEdit — a writing well pressed into the parchment
	var le_pad := Vector2(14, 12) if m else Vector2(16, 11)
	var le := bordered(box(Color(CREAM, 0.9), le_pad), Color(RULE, 0.9), 1, 2)
	var le_focus := bordered(box(CREAM, le_pad), TERRACOTTA, 1, 2)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", le_focus)
	t.set_stylebox("read_only", "LineEdit", le)
	t.set_font("font", "LineEdit", SPECTRAL_MEDIUM)
	t.set_font_size("font_size", "LineEdit", 19)
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", Color(INK_MUTED, 0.75))
	t.set_color("caret_color", "LineEdit", TERRACOTTA)
	t.set_color("selection_color", "LineEdit", Color(GOLD, 0.45))
	t.set_constant("caret_width", "LineEdit", 2)

	# Meter — thin health / progress bar
	t.set_type_variation("Meter", "ProgressBar")
	var track := box(Color(DUSK, 0.16), Vector2.ZERO, 2)
	var fill := box(OLIVE, Vector2.ZERO, 2)
	t.set_stylebox("background", "Meter", track)
	t.set_stylebox("fill", "Meter", fill)
	t.set_stylebox("background", "ProgressBar", track)
	t.set_stylebox("fill", "ProgressBar", fill)

	# HSlider — phones: thicker rail, 28dp thumb (the 48dp target comes from row height)
	var rail_h := 4 if m else 3
	var rail := box(Color(DUSK, 0.18), Vector2(0, rail_h), 3)
	var rail_fill := box(TERRACOTTA, Vector2(0, rail_h), 3)
	t.set_stylebox("slider", "HSlider", rail)
	t.set_stylebox("grabber_area", "HSlider", rail_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", rail_fill)
	var d := 28 if m else 20
	t.set_icon("grabber", "HSlider", _disc(d, CREAM, TERRACOTTA))
	t.set_icon("grabber_highlight", "HSlider", _disc(d, Color.WHITE, TERRACOTTA_DEEP))
	t.set_icon("grabber_disabled", "HSlider", _disc(d, PARCHMENT_DEEP, RULE))
	t.set_stylebox("focus", "HSlider", _focus_ring(4))

## Filled circle with a ring — slider grabber. Rasterised at device pixels and
## shown at `size` UI units, so it stays round under the phone UI scale.
static func _disc(size: int, fill: Color, ring: Color) -> ImageTexture:
	var k := UiIcons.density()
	var d := roundi(size * k)
	var img := Image.create_empty(d, d, false, Image.FORMAT_RGBA8)
	var c := (d - 1) * 0.5
	var r := d * 0.5 - 1.0
	for y in d:
		for x in d:
			var dist := Vector2(x - c, y - c).length()
			var a := clampf(r - dist + 0.5, 0.0, 1.0)
			var col := ring if dist > r - 2.5 * k else fill
			img.set_pixel(x, y, Color(col, col.a * a))
	var tex := ImageTexture.create_from_image(img)
	tex.set_size_override(Vector2i(size, size))
	return tex
