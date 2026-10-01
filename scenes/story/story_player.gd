class_name StoryPlayer
extends CanvasLayer

# Full-screen story cards between days (see StoryData). Each peer reads at its own
# pace: `finished` fires when this reader is through (or skipped), then the last card
# waits on the rest of the crew until DayDirector closes it. The host may start early.

signal finished
signal start_now_requested
signal choice_made(key: String)   # this reader's pick on the choice card (GameState.BOONS)

const FADE        := 0.45
const TYPE_SPEED  := 55.0     # characters per second
const DRIFT_TIME  := 18.0     # slow pan/zoom across each slide
const DRIFT_ZOOM  := 1.12
const DRIFT_PAN   := 36.0
const TEXT_WIDTH  := 1080.0

var _slides: Array = []
var _index := -1
var _done := false

var _root: Control
var _frame: Control           # the "camera": art + backdrop, scaled for the drift
var _art: TextureRect
var _backdrop: StoryBackdrop
var _map: CircuitMap
var _twist: TwistCard
var _content: Control
var _eyebrow: Label
var _title: Label
var _text: Label
var _verse: Label
var _ref: Label
var _page: Label
var _hint: Label
var _ready_row: ReadyRow
var _choice_box: HBoxContainer
var _choice_panels: Array[PanelContainer] = []
var _choice_keys: Array = []
var _choice_index := 0
var _hint_text := ""

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
	_ready_row.hide()
	# With company, Esc doesn't skip the day — it says you're through and waits for the rest
	_hint_text = "E · Click   Next          Esc   I'm ready" if _with_company() \
		else "E · Click   Continue          Esc   Skip"
	_hint.text = _hint_text
	_hint.show()
	_root.show()
	UiFx.fade_in(_root, 0.7)
	_advance()

## Who's still reading (DayDirector.ready_changed); shown once this reader is through
func set_ready_state(kind: String, waiting: Array) -> void:
	if kind == "story":
		_ready_row.set_waiting(waiting)

func _with_company() -> bool:
	return get_tree().get_nodes_in_group("players").any(
		func(p): return not p.is_bot() and p.worker_id() != multiplayer.get_unique_id())

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
	# The choice card: pick with left / right or a click, confirm with E (Esc still skips)
	if _on_choice_card() and not _typing() and not (_slide_tween and _slide_tween.is_running()) \
			and _choice_input(event):
		get_viewport().set_input_as_handled()
		return
	var click: bool = event is InputEventMouseButton and event.pressed \
		and event.button_index == MOUSE_BUTTON_LEFT
	if click or event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_advance()
	elif event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_finish()

func _typing() -> bool:
	return _type_tween != null and _type_tween.is_running()

func _on_choice_card() -> bool:
	return _index >= 0 and _index < _slides.size() and _slides[_index].get("choice", false)

## True when the event was the choice card's
func _choice_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in _choice_panels.size():
			if _choice_panels[i].get_global_rect().has_point(event.position):
				_choice_index = i
				_confirm_choice()
				break
		return true   # a click off the options does nothing here
	if event.is_action_pressed("ui_left"):
		_pick(_choice_index - 1)
		return true
	if event.is_action_pressed("ui_right"):
		_pick(_choice_index + 1)
		return true
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode >= KEY_1 and event.keycode < KEY_1 + _choice_panels.size():
		_pick(event.keycode - KEY_1)
		return true
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		_confirm_choice()
		return true
	return false

func _pick(i: int) -> void:
	_choice_index = clampi(i, 0, _choice_panels.size() - 1)
	_refresh_choices()

func _confirm_choice() -> void:
	choice_made.emit(_choice_keys[_choice_index])
	_advance()   # the choice card is the last one: this reader is through

func _fill_choices() -> void:
	for c in _choice_box.get_children():
		c.queue_free()
	_choice_panels.clear()
	_choice_keys = GameState.choices_for(GameState.current_section_index)
	_choice_index = 0
	for key: String in _choice_keys:
		var boon: Dictionary = GameState.BOONS[key]
		var lines := GameState.boon_lines(key)
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(430, 0)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(box)
		var title := _label(&"Heading", 22, UiStyle.CREAM)
		title.text = boon["title"]
		box.add_child(title)
		var ref := _label(&"Eyebrow", 13, Color(UiStyle.GOLD, 0.85))
		ref.text = GameState.long_ref(boon["ref"])
		box.add_child(ref)
		# What it gives, what it costs: worked out from the modifiers, so always the truth
		for line: String in lines["gain"]:
			box.add_child(_effect_line("+  " + line, UiStyle.GOLD))
		for line: String in lines["cost"]:
			box.add_child(_effect_line("−  " + line, Color(UiStyle.TERRACOTTA).lightened(0.25)))
		_choice_box.add_child(panel)
		_choice_panels.append(panel)
	_refresh_choices()

func _effect_line(text: String, color: Color) -> Label:
	var l := _label(&"Body", 17, color)
	l.text = text   # already in the player's language (GameState.boon_lines)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return l

func _refresh_choices() -> void:
	for i in _choice_panels.size():
		var picked := i == _choice_index
		var style := StyleBoxFlat.new()
		style.bg_color = Color(UiStyle.DUSK, 0.82 if picked else 0.55)
		style.border_color = UiStyle.GOLD if picked else Color(UiStyle.CREAM, 0.25)
		style.set_border_width_all(3 if picked else 1)
		style.set_corner_radius_all(6)
		style.set_content_margin_all(16)
		_choice_panels[i].add_theme_stylebox_override("panel", style)
		_choice_panels[i].modulate.a = 1.0 if picked else 0.75

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
	if slide.has("met"):
		GameState.mark_met(slide["met"])
	var art_path: String = slide.get("art", "")
	var has_art := not art_path.is_empty() and ResourceLoader.exists(art_path)
	var has_map := slide.has("map")
	var has_twist := slide.has("twist")
	_art.visible = has_art and not has_map and not has_twist
	_backdrop.visible = not has_art and not has_map
	_map.visible = has_map
	_twist.visible = has_twist
	if has_twist:
		_twist.twist = slide["twist"]
		_backdrop.sky = "dawn"
		_backdrop.built = 0.2
		_backdrop.pattern = hash(slide["twist"])
	# The map sits on the right; the text keeps to a narrower column beside it
	_content.custom_minimum_size.x = TEXT_WIDTH * (0.55 if has_map else 1.0)
	if has_map:
		_map.section = slide["map"]
		_map.inspect = slide.get("inspect", false)
		_map.finale = slide.get("finale", false)
		_map.aged = true   # the scribe's map, worn by the run so far
		_map.play()
	elif has_art:
		_art.texture = load(art_path)
	else:
		_backdrop.sky = slide.get("sky", "dusk")
		_backdrop.built = slide.get("built", 0.0)
		_backdrop.pattern = hash(slide.get("title", "")) + _index
	var has_choice: bool = slide.get("choice", false)
	_choice_box.visible = has_choice
	if has_choice:
		_fill_choices()
		_hint.text = "←  →   Choose          E · Click   Confirm"
	else:
		_hint.text = _hint_text
	_set_label(_eyebrow, slide.get("eyebrow", ""))
	_set_label(_title, slide.get("title", ""))
	_set_label(_text, slide.get("text", ""))
	_set_label(_verse, slide.get("verse", ""))
	var ref: String = slide.get("ref", "")
	_set_label(_ref, GameState.long_ref(ref) if not ref.is_empty() else "")
	_page.text = "%d / %d" % [_index + 1, _slides.size()] if _slides.size() > 1 else ""

	_drift(not has_map and not has_twist)
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

# Ken Burns: zoom in slowly about the centre, alternating the pan per slide.
# The map holds still — its labels should stay crisp and readable.
func _drift(moving := true) -> void:
	if _drift_tween:
		_drift_tween.kill()
	if not moving:
		_frame.scale = Vector2.ONE
		_frame.position = Vector2.ZERO
		return
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
	finished.emit()
	# Who else is still reading — only worth a row with company (the ending's credits
	# follow straight on, nothing waits there)
	_ready_row.visible = _with_company() and GameState.phase == GameState.Phase.STORY
	_ready_row.refresh()

func _kill_tweens() -> void:
	for tw: Tween in [_slide_tween, _type_tween, _drift_tween]:
		if tw:
			tw.kill()

# Slides hold the English text; the Label translates it (auto_translate)
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
	_map = CircuitMap.new()
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.hide()
	_frame.add_child(_map)

	# Vignette, then a dark wash under the text so it reads over any art
	_root.add_child(_gradient_rect(true))
	_root.add_child(_gradient_rect(false))
	_twist = TwistCard.new()
	_twist.set_anchors_preset(Control.PRESET_FULL_RECT)
	_twist.hide()
	_root.add_child(_twist)   # over the washes: the panels are the slide

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
	_choice_box = HBoxContainer.new()
	_choice_box.add_theme_constant_override("separation", 18)
	_choice_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice_box.hide()
	content.add_child(_choice_box)

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

	_ready_row = ReadyRow.new(true)
	_ready_row.hide()
	_ready_row.begin_now.connect(start_now_requested.emit)
	footer.add_child(_ready_row)

	_hint = _label(&"Eyebrow", 13, Color(UiStyle.CREAM, 0.55), false)
	footer.add_child(_hint)

func _label(variation: StringName, font_size: int, color: Color, wrapped := true) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if wrapped:
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
