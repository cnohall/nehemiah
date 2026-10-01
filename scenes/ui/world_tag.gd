class_name WorldTag
extends Node3D

# A tag floating over something in the world: a small dark plaque with a pointer,
# drawn on a screen overlay (crisp at any zoom, real UI styling) and pinned to this
# node's 3D position every frame. Drop-in for the old Label3D world labels — set
# `text`, `visible`, `modulate`, `position` the same way — and the text is read for
# structure:
#   "Stone 2/5  Mortar 0/1"  → one column per material: icon over count
#   "Stone"                  → icon + name (a supply pile)
#   "Wall 80%"               → a small condition bar
#   "Build  [E]"             → text with the key drawn as a keycap
# Lines split on newlines; segments within a line on double spaces or " · ".

# SHOUT: a call from someone in the world (watchmen, the scribe) — parchment, ink text.
# SCROLL: parchment too, holding a `custom` Control instead of parsed text.
enum Kind { SITE, STATION, TOAST, NOTE, SHOUT, SCROLL }

const MATERIALS := ["stone", "wood", "mortar", "lime", "water", "beam", "beams", "rubble", "branch", "portion"]
const LAYER := 1
const BG       := Color(0.20, 0.14, 0.10, 0.92)
const BG_EDGE  := Color(0.93, 0.80, 0.55, 0.28)
const TEXT     := Color(0.98, 0.95, 0.89)
const TEXT_DIM := Color(0.86, 0.78, 0.66)
const DONE     := Color(0.66, 0.78, 0.40)
const PIP_OFF  := Color(1.0, 0.95, 0.85, 0.22)
const POINTER  := Vector2(16, 9)
const EDGE_MARGIN := 10.0
const PULSE_AMOUNT := 0.07
const DIM := 0.5   # alpha for a site tag that isn't where the next delivery goes
# Phones: UI units are dp, which makes tags ~2× the desktop share of the screen and
# they bury the crew and the enemies you're aiming at — draw them a size down
const MOBILE_SCALE := 0.7
const SHOUT_WRAP_CHARS := 56   # a shout longer than this wraps…
const SHOUT_WIDTH := 460.0     # …at this width
const SEE_THROUGH_ALPHA := 0.3   # a tag over a player fades to this…
const SEE_THROUGH_SPEED := 6.0   # …this fast (per second, 0→1)
const PLAYER_HEIGHT := 2.2       # feet to crown, m: the screen box tested against tags

static var _layer: CanvasLayer
static var _fonts: Dictionary = {}

var kind := Kind.SITE
var text := "":
	set(value):
		if value == text:
			return
		text = value
		_dirty = true
var modulate := Color.WHITE
## Lift on screen, in px, above the projected point
var screen_lift := 0.0
## A gentle breathing scale — the one tag that says "here next"
var pulse := false
## Slide in from the screen edge when the spot is off-screen (false: just hide)
var clamp_to_screen := true
## A site's name stacks word over word (a narrow sign over a narrow thing)
var stack_name := false
## Drawn instead of the parsed text (Kind.SCROLL)
var custom: Control:
	set(value):
		custom = value
		_dirty = true

var _root: Control
var _panel: PanelContainer
var _box: VBoxContainer
var _pointer: Control
var _dirty := true
var _see_through := 0.0   # 0 → solid, 1 → a player is behind the tag

static func make(k: Kind, t := "") -> WorldTag:
	var w := WorldTag.new()
	w.kind = k
	w.text = t
	return w

func _enter_tree() -> void:
	if _root == null:
		_build()
	_overlay(get_viewport()).add_child(_root)

func _exit_tree() -> void:
	if _root != null and _root.get_parent() != null:
		_root.get_parent().remove_child(_root)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _root != null:
		_root.queue_free()

static func _overlay(vp: Viewport) -> CanvasLayer:
	if _layer == null or not is_instance_valid(_layer):
		_layer = CanvasLayer.new()
		_layer.name = "WorldTags"
		_layer.layer = LAYER
		if Mobile.enabled():
			_layer.scale = Vector2.ONE * MOBILE_SCALE
		vp.add_child.call_deferred(_layer)
	return _layer

func _covers_player(cam: Camera3D, rect: Rect2) -> bool:
	for p in get_tree().get_nodes_in_group("players"):
		var body := p as Node3D
		# Own tags (a toast, "Help up") ride on the player — never fade for them
		if body == null or body.is_ancestor_of(self) or cam.is_position_behind(body.global_position):
			continue
		var feet := cam.unproject_position(body.global_position)
		var head := cam.unproject_position(body.global_position + Vector3.UP * PLAYER_HEIGHT)
		var h := absf(feet.y - head.y)
		var box := Rect2(Vector2(feet.x - h * 0.25, minf(head.y, feet.y)), Vector2(h * 0.5, h))
		if rect.intersects(box):
			return true
	return false

func _process(_delta: float) -> void:
	if _root == null:
		return
	if _dirty:
		_rebuild()
	var cam := get_viewport().get_camera_3d()
	var shown := is_visible_in_tree() and cam != null and (not text.is_empty() or custom != null) \
		and not GameState.attract and not cam.is_position_behind(global_position)
	_root.visible = shown
	if not shown:
		return
	# Already in the stretched 2D base space the overlay draws in (canvas_items stretch)
	# — as OffscreenAlerts uses it. An extra window transform here only cancelled out at
	# 1920×1080 and threw tags off at every other size.
	var layer_k := _layer.scale.x   # overlay space → layer space
	var p := cam.unproject_position(global_position) / layer_k
	var vp := get_viewport()
	var sz := _root.get_combined_minimum_size()
	_root.size = sz
	var want := p - Vector2(sz.x * 0.5, sz.y + screen_lift)
	# Keep the tag on screen: slide it in from the edge, pointer hidden while it's off its mark
	var area := vp.get_visible_rect().size / layer_k
	var at := want.clamp(Vector2(EDGE_MARGIN, EDGE_MARGIN), area - sz - Vector2(EDGE_MARGIN, EDGE_MARGIN))
	# Only a tag that matters slides in from the edge: dimmed ones (not where the next
	# load goes) just leave, or they pile up against the edge over one another
	if (not clamp_to_screen or modulate.a < 0.99) and not at.is_equal_approx(want):
		_root.visible = false
		return
	_root.position = at.round()
	if _pointer != null:
		_pointer.modulate.a = 1.0 if at.is_equal_approx(want) else 0.0
	# A worker standing behind the tag shows through it
	var covers := _covers_player(cam, Rect2(at, sz).grow(4.0))
	_see_through = move_toward(_see_through, 1.0 if covers else 0.0, _delta * SEE_THROUGH_SPEED)
	_root.modulate = modulate * Color(1, 1, 1, lerpf(1.0, SEE_THROUGH_ALPHA, _see_through))
	if pulse:
		var k := 1.0 + PULSE_AMOUNT * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005))
		_root.pivot_offset = Vector2(sz.x * 0.5, sz.y)
		_root.scale = Vector2(k, k)
	elif _root.scale != Vector2.ONE:
		_root.scale = Vector2.ONE

# ── Building ───────────────────────────────────────────────

func _build() -> void:
	_root = VBoxContainer.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_theme_constant_override("separation", 0)
	_root.visible = false
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = _bg()
	sb.set_corner_radius_all(9 if kind != Kind.TOAST else 14)
	sb.border_color = UiStyle.RULE if _paper() else BG_EDGE
	sb.set_border_width_all(1)
	sb.border_width_top = 2
	sb.shadow_color = Color(0.08, 0.05, 0.02, 0.35)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	var pad := Vector2(12, 7) if kind == Kind.SHOUT else (Vector2(8, 5) if kind == Kind.SITE else Vector2(10, 5))
	if kind == Kind.SCROLL:
		pad = Vector2(20, 6)   # room for the rolled ends
	sb.content_margin_left = pad.x
	sb.content_margin_right = pad.x
	sb.content_margin_top = pad.y
	sb.content_margin_bottom = pad.y + 1
	sb.anti_aliasing = true
	if kind == Kind.SCROLL:
		# The scroll draws its own sheet and tail (Scribe.ScrollSheet); keep the margins
		var bare := StyleBoxEmpty.new()
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			bare.set_content_margin(side, sb.get_content_margin(side))
		_panel.add_theme_stylebox_override("panel", bare)
	else:
		_panel.add_theme_stylebox_override("panel", sb)
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_root.add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 4)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_box)
	if kind != Kind.TOAST:
		_pointer = Control.new()
		_pointer.custom_minimum_size = Vector2(POINTER.x, POINTER.y)
		_pointer.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pointer.draw.connect(func():
			if kind == Kind.SCROLL:
				return
			var w := POINTER.x
			var h := POINTER.y
			# Shadow, fill over the panel's bottom border, then the border carried round
			# the tip, so the tail reads as part of the panel rather than stuck on
			var edge := UiStyle.RULE if _paper() else BG_EDGE
			_pointer.draw_colored_polygon(PackedVector2Array([Vector2(1, 1), Vector2(w - 1, 1), Vector2(w * 0.5, h + 3)]), Color(0.08, 0.05, 0.02, 0.18))
			_pointer.draw_colored_polygon(PackedVector2Array([Vector2(-0.5, -1.5), Vector2(w + 0.5, -1.5), Vector2(w * 0.5, h)]), _bg())
			_pointer.draw_polyline(PackedVector2Array([Vector2(0, -0.5), Vector2(w * 0.5, h), Vector2(w, -0.5)]), edge, 1.0, true))
		_root.add_child(_pointer)

func _paper() -> bool:
	return kind == Kind.SHOUT or kind == Kind.SCROLL

func _bg() -> Color:
	return Color(UiStyle.PARCHMENT, 0.96) if _paper() else BG

func _ink() -> Color:
	return UiStyle.INK if _paper() else TEXT

func _rebuild() -> void:
	_dirty = false
	for c in _box.get_children():
		if c != custom:
			c.free()
	if custom != null:
		if custom.get_parent() != _box:
			if custom.get_parent() != null:
				custom.get_parent().remove_child(custom)
			_box.add_child(custom)
		return
	for line in text.split("\n", false):
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_box.add_child(row)
		# A shout or a note is prose: kept whole ("Sanballat · Tobiah · Geshem")
		var segs := PackedStringArray([line]) if _paper() or kind == Kind.NOTE 			else line.replace(" · ", "  ").replace("·", "  ").split("  ", false)
		for seg in segs:
			seg = seg.strip_edges()
			if not seg.is_empty():
				row.add_child(_segment(seg))

func _segment(seg: String) -> Control:
	var words := seg.split(" ", false)
	var first := words[0].to_lower()
	# "Stone 2/5" — a material need
	if words.size() == 2 and first in MATERIALS and words[1].contains("/"):
		var parts := words[1].split("/")
		return _need(first, int(parts[0]), int(parts[1]))
	# "Stone" — a pile's name
	if words.size() == 1 and first in MATERIALS:
		var row := _hbox(6)
		row.add_child(TagIcon.make(first, 22))
		# Small caps, like the material names on a site's needs
		row.add_child(_label(seg, "caps", 14, TEXT))
		return row
	# "Wall 80%" — condition bar
	if words.size() == 2 and first == "wall" and words[1].ends_with("%"):
		return _condition(int(words[1].trim_suffix("%")) / 100.0)
	# A site's name ("Watch post") — small caps, like everything else on a dark tag
	if kind == Kind.SITE and not seg.contains("["):
		var l := _label(seg, "caps", 14, TEXT)
		if stack_name and words.size() > 1:
			# Wrapped at the widest word: one word a line, short ones may share
			var font := _font("caps")
			var w := 0.0
			for word in l.text.split(" ", false):
				w = maxf(w, font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.custom_minimum_size.x = ceilf(w) + 2.0
		return l
	return _rich(seg)

func _need(mat: String, have: int, need: int) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var done := have >= need
	var icon := TagIcon.make(mat, 30)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if done:
		icon.modulate = Color(1, 1, 1, 0.55)
	col.add_child(icon)
	# Icon + count only: the sign stays small
	var count := _label("%d/%d" % [have, need], "bold", 17, DONE if done else TEXT)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(count)
	return col

func _condition(f: float) -> Control:
	var row := _hbox(8)
	var bar := PipStrip.new()
	bar.bar = true
	bar.fraction = f
	bar.on = DONE if f > 0.6 else (UiStyle.AMBER if f > 0.3 else UiStyle.TERRACOTTA.lightened(0.15))
	bar.off = PIP_OFF
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	return row

# Plain text, with "[X]" drawn as a keycap
func _rich(seg: String) -> Control:
	var row := _hbox(5)
	var rx := RegEx.create_from_string("\\[([^\\]]+)\\]")
	var at := 0
	for m in rx.search_all(seg):
		var before := seg.substr(at, m.get_start() - at).strip_edges()
		if not before.is_empty():
			row.add_child(_label(before, "italic" if kind == Kind.NOTE else "medium", 18, _ink()))
		row.add_child(_keycap(m.get_string(1)))
		at = m.get_end()
	var rest := seg.substr(at).strip_edges()
	if not rest.is_empty():
		row.add_child(_label(rest, "italic" if kind == Kind.NOTE else "medium", 18, _ink()))
	return row

func _keycap(k: String) -> Control:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiStyle.PARCHMENT
	sb.set_corner_radius_all(4)
	sb.border_color = UiStyle.RULE
	sb.set_border_width_all(1)
	sb.border_width_bottom = 3
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	sb.anti_aliasing = true
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_child(_label(k, "caps_bold", 14, UiStyle.INK))
	return p

func _hbox(sep: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h

func _label(t: String, face: String, size: int, color: Color) -> Label:
	var l := Label.new()
	var shown := tr(t)   # material names, "Wall": small caps need the translation first
	l.text = shown.to_upper() if face.begins_with("caps") else shown
	l.add_theme_font_override("font", _font(face))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("line_spacing", -4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# A long call (a verse read out) wraps instead of running across the screen
	if kind == Kind.SHOUT and shown.length() > SHOUT_WRAP_CHARS:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = SHOUT_WIDTH
	return l

static func _font(face: String) -> Font:
	if not _fonts.has(face):
		match face:
			"caps":      _fonts[face] = UiStyle.tracked(UiStyle.CINZEL_SEMI, 2)
			"caps_bold": _fonts[face] = UiStyle.tracked(UiStyle.CINZEL_BOLD, 1)
			"bold":      _fonts[face] = UiStyle.WORLD_FONT
			"italic":    _fonts[face] = UiStyle.SPECTRAL_ITALIC
			_:           _fonts[face] = UiStyle.SPECTRAL_MEDIUM
	return _fonts[face]


# Pips (one per load) or a thin bar
class PipStrip extends Control:
	var have := 0
	var need := 1
	var fraction := 0.0
	var bar := false
	var on := Color.WHITE
	var off := Color(1, 1, 1, 0.2)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _get_minimum_size() -> Vector2:
		return Vector2(64, 7) if bar else Vector2(need * 9 - 3, 6)

	func _draw() -> void:
		if bar:
			draw_rect(Rect2(Vector2.ZERO, size), off)
			draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * clampf(fraction, 0.0, 1.0), size.y)), on)
			return
		for i in need:
			draw_rect(Rect2(Vector2(i * 9, 0), Vector2(6, 6)), on if i < have else off)
