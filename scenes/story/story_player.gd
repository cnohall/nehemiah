class_name StoryPlayer
extends CanvasLayer

# Full-screen story cards between days (see StoryData). Each peer reads at its own
# pace: `finished` fires when this reader is through (or skipped), then the last card
# waits on the rest of the crew until DayDirector closes it. The host may start early.

signal finished
signal start_now_requested

const FADE        := 0.45
const TYPE_SPEED  := 55.0     # characters per second
const DRIFT_TIME  := 18.0     # slow pan/zoom across each slide
const DRIFT_ZOOM  := 1.12
const DRIFT_PAN   := 36.0
const TEXT_WIDTH  := 1080.0

var _slides: Array = []
var _index := -1
var _done := false
var _waiting := 0

var _root: Control
var _frame: Control           # the "camera": art + backdrop, scaled for the drift
var _art: TextureRect
var _backdrop: StoryBackdrop
var _content: Control
var _eyebrow: Label
var _title: Label
var _text: Label
var _verse: Label
var _ref: Label
var _page: Label
var _hint: Label
var _wait_row: Control
var _wait_label: Label
var _start_now: Button

var _slide_tween: Tween
var _type_tween: Tween
var _drift_tween: Tween

func _ready() -> void:
	layer = 20
	_build()
	_root.hide()

## Start a sequence; does nothing with an empty list
func play(slides: Array) -> void:
	if slides.is_empty():
		return
	_slides = slides
	_index = -1
	_done = false
	_waiting = 0
	_wait_row.hide()
	_hint.show()
	_root.show()
	UiFx.fade_in(_root, 0.7)
	_advance()

## Crew members still reading (from the server); shown once this reader is through
func set_waiting(count: int) -> void:
	_waiting = count
	_refresh_wait()

func close() -> void:
	if not _root.visible:
		return
	_kill_tweens()
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(_root.hide)

func is_playing() -> bool:
	return _root.visible

# ── Input ──────────────────────────────────────────────────

# _input, not _unhandled_input: the full-screen root eats mouse clicks as GUI events.
# Once through, clicks pass so the host's "Begin now" button still works.
func _input(event: InputEvent) -> void:
	if not _root.visible or _done:
		return
	var click: bool = event is InputEventMouseButton and event.pressed \
		and event.button_index == MOUSE_BUTTON_LEFT
	if click or event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_advance()
	elif event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_finish()

# ── Slides ─────────────────────────────────────────────────

func _advance() -> void:
	# First press finishes the typing; the next one turns the page
	if _type_tween and _type_tween.is_running():
		_type_tween.kill()
		_reveal_all()
		return
	if _slide_tween and _slide_tween.is_running():
		return
	_index += 1
	if _index >= _slides.size():
		_finish()
		return
	if _index == 0:
		_show_slide(_slides[0])
		return
	_slide_tween = create_tween()
	_slide_tween.tween_property(_content, "modulate:a", 0.0, FADE * 0.6)
	_slide_tween.parallel().tween_property(_frame, "modulate:a", 0.0, FADE)
	_slide_tween.tween_callback(_show_slide.bind(_slides[_index]))

func _show_slide(slide: Dictionary) -> void:
	var art_path: String = slide.get("art", "")
	var has_art := not art_path.is_empty() and ResourceLoader.exists(art_path)
	_art.visible = has_art
	_backdrop.visible = not has_art
	if has_art:
		_art.texture = load(art_path)
	else:
		_backdrop.sky = slide.get("sky", "dusk")
		_backdrop.built = slide.get("built", 0.0)
		_backdrop.pattern = hash(slide.get("title", "")) + _index
	_set_label(_eyebrow, slide.get("eyebrow", ""))
	_set_label(_title, slide.get("title", ""))
	_set_label(_text, slide.get("text", ""))
	_set_label(_verse, slide.get("verse", ""))
	_set_label(_ref, slide.get("ref", ""))
	_page.text = "%d / %d" % [_index + 1, _slides.size()] if _slides.size() > 1 else ""

	_drift()
	_content.modulate.a = 1.0
	var fade := create_tween().set_parallel()
	fade.tween_property(_frame, "modulate:a", 1.0, FADE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	UiFx.fade_in(_eyebrow, 0.5)
	UiFx.fade_in(_title, 0.6, 0.1)
	_verse.modulate.a = 0.0
	_ref.modulate.a = 0.0

	# Narration types out, then the verse and its reference settle in
	_text.visible_ratio = 0.0
	var chars := _text.get_total_character_count()
	_type_tween = create_tween()
	_type_tween.tween_interval(0.35)
	_type_tween.tween_property(_text, "visible_ratio", 1.0, chars / TYPE_SPEED)
	_type_tween.tween_property(_verse, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_type_tween.parallel().tween_property(_ref, "modulate:a", 1.0, 0.8).set_delay(0.3)

func _reveal_all() -> void:
	_text.visible_ratio = 1.0
	for n: CanvasItem in [_eyebrow, _title, _verse, _ref]:
		n.modulate.a = 1.0

# Ken Burns: zoom in slowly about the centre, alternating the pan per slide
func _drift() -> void:
	if _drift_tween:
		_drift_tween.kill()
	var dir := 1.0 if _index % 2 == 0 else -1.0
	_frame.pivot_offset = _frame.size * 0.5
	_frame.scale = Vector2.ONE * 1.05   # enough overscan that the pan never shows an edge
	_frame.position = Vector2(-DRIFT_PAN * dir, 0)
	_drift_tween = create_tween().set_parallel()
	_drift_tween.tween_property(_frame, "scale", Vector2.ONE * DRIFT_ZOOM, DRIFT_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_drift_tween.tween_property(_frame, "position", Vector2(DRIFT_PAN * dir, -DRIFT_PAN * 0.4), DRIFT_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _finish() -> void:
	if _done:
		return
	_done = true
	if _type_tween:
		_type_tween.kill()
	_reveal_all()
	_hint.hide()
	_refresh_wait()
	finished.emit()

func _refresh_wait() -> void:
	var want := _done and _waiting > 0 and _root.visible
	_wait_row.visible = want
	if not want:
		return
	_wait_label.text = "Waiting for %d builder%s still reading" % [_waiting, "" if _waiting == 1 else "s"]
	_start_now.visible = multiplayer.is_server()

func _kill_tweens() -> void:
	for tw: Tween in [_slide_tween, _type_tween, _drift_tween]:
		if tw:
			tw.kill()

func _set_label(l: Label, value: String) -> void:
	l.text = value
	l.visible = not value.is_empty()

# ── Layout ─────────────────────────────────────────────────

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var black := ColorRect.new()
	black.color = UiStyle.DUSK
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(black)

	_frame = Control.new()
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_frame)
	_backdrop = StoryBackdrop.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_backdrop)
	_art = TextureRect.new()
	_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_art)

	# Vignette, then a dark wash under the text so it reads over any art
	_root.add_child(_gradient_rect(true))
	_root.add_child(_gradient_rect(false))

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 140)
	margin.add_theme_constant_override("margin_top", 80)
	margin.add_theme_constant_override("margin_bottom", 64)
	_root.add_child(margin)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_END
	column.add_theme_constant_override("separation", 28)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.custom_minimum_size.x = TEXT_WIDTH
	content.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(content)
	_content = content

	_eyebrow = _label(&"Eyebrow", 15, UiStyle.GOLD)
	content.add_child(_eyebrow)
	_title = _label(&"Heading", 58, UiStyle.CREAM)
	_title.add_theme_font_override("font", UiStyle.tracked(UiStyle.CINZEL_BOLD, 5))
	content.add_child(_title)
	var rule := ColorRect.new()
	rule.color = Color(UiStyle.GOLD, 0.6)
	rule.custom_minimum_size = Vector2(72, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	content.add_child(rule)
	_text = _label(&"Body", 26, Color(UiStyle.CREAM, 0.92))
	_text.add_theme_constant_override("line_spacing", 6)
	content.add_child(_text)
	_verse = _label(&"Verse", 28, UiStyle.PARCHMENT)
	_verse.add_theme_constant_override("line_spacing", 6)
	content.add_child(_verse)
	_ref = _label(&"Eyebrow", 14, Color(UiStyle.GOLD, 0.85))
	content.add_child(_ref)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 24)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(footer)
	_page = _label(&"Eyebrow", 13, Color(UiStyle.CREAM, 0.5), false)
	footer.add_child(_page)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(spacer)

	_wait_row = HBoxContainer.new()
	_wait_row.add_theme_constant_override("separation", 20)
	footer.add_child(_wait_row)
	_wait_label = _label(&"Caption", 18, Color(UiStyle.CREAM, 0.75), false)
	_wait_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_wait_row.add_child(_wait_label)
	_start_now = Button.new()
	_start_now.theme_type_variation = &"GhostButton"
	_start_now.text = "Begin now"
	_start_now.add_theme_color_override("font_color", UiStyle.CREAM)
	_start_now.pressed.connect(start_now_requested.emit)
	_wait_row.add_child(_start_now)

	_hint = _label(&"Eyebrow", 13, Color(UiStyle.CREAM, 0.55), false)
	_hint.text = "E · Click   Continue          Esc   Skip"
	footer.add_child(_hint)

func _label(variation: StringName, font_size: int, color: Color, wrap := true) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Radial vignette, or a bottom-up wash behind the text
func _gradient_rect(radial: bool) -> TextureRect:
	var g := Gradient.new()
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 256
	tex.height = 256
	if radial:
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.45)
		tex.fill_to = Vector2(1.15, 1.1)
		g.set_color(0, Color(UiStyle.DUSK, 0.0))
		g.set_color(1, Color(UiStyle.DUSK, 0.7))
	else:
		tex.fill_from = Vector2(0.5, 0.35)
		tex.fill_to = Vector2(0.5, 1.0)
		g.set_color(0, Color(UiStyle.DUSK, 0.0))
		g.set_color(1, Color(UiStyle.DUSK, 0.9))
	var r := TextureRect.new()
	r.texture = tex
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
