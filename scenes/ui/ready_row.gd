class_name ReadyRow
extends HBoxContainer

# Who's ready, between days (playtest 2): a chip per person in the crew — their colour,
# "You" or their trade, a tick once ready — then the local prompt and, for the host,
# "Begin now" past anyone who's gone quiet. DayDirector owns the state
# (ready_changed); this only shows it and reports the local press.
#   holdable — hold [interact] to mark ready (the dusk tally, where a tap of E is still
#              a habit from the day's work); the story marks you ready by reading on

signal ready_pressed
signal unready_pressed
signal begin_now

const HOLD_TIME := 0.6
const BAR_SIZE := Vector2(180, 6)

var holdable := false
var cancellable := false   # ready can be taken back while others are still out
var _dark := false
var _waiting: Array = []
var _slides: Dictionary = {}   # peer id → Vector2i(slide index, slide count), while reading
var _hold := 0.0
var _have := 0   # people ready / in the crew, for the bar
var _total := 0
var _chips: HBoxContainer
var _prompt: Button
var _fill: ColorRect
var _bar: Control
var _undo: Button
var _begin: Button

func _init(dark: bool) -> void:
	_dark = dark
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 28)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 18)
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chips)

	var prompt_box := VBoxContainer.new()
	prompt_box.add_theme_constant_override("separation", 2)
	prompt_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(prompt_box)
	_prompt = Button.new()
	_prompt.theme_type_variation = &"GhostButton"
	_prompt.focus_mode = Control.FOCUS_NONE
	_prompt.add_theme_color_override("font_color", _text_color())
	_prompt.pressed.connect(_press)
	prompt_box.add_child(_prompt)
	# Fills while the key is held
	_fill = ColorRect.new()
	_fill.color = UiStyle.GOLD if dark else UiStyle.TERRACOTTA
	_fill.custom_minimum_size = Vector2(0, 3)
	_fill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_box.add_child(_fill)
	# How many are ready, as a bar of one segment per person
	_bar = Control.new()
	_bar.custom_minimum_size = BAR_SIZE
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	prompt_box.add_child(_bar)

	_undo = Button.new()
	_undo.theme_type_variation = &"GhostButton"
	_undo.focus_mode = Control.FOCUS_NONE
	_undo.text = "Not ready yet"
	_undo.add_theme_color_override("font_color", _text_color())
	_undo.pressed.connect(unready_pressed.emit)
	_undo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_undo)

	_begin = Button.new()
	_begin.theme_type_variation = &"GhostButton"
	_begin.focus_mode = Control.FOCUS_NONE
	_begin.text = "Begin now"
	_begin.add_theme_color_override("font_color", _text_color())
	_begin.pressed.connect(begin_now.emit)
	_begin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_begin)

## `waiting` = peer ids not ready yet
func set_waiting(waiting: Array) -> void:
	_waiting = waiting
	_hold = 0.0
	refresh()

## Story slides each reader is on (DayDirector.slides_changed): a small bar per chip until they're through
func set_slides(slides: Dictionary) -> void:
	_slides = slides
	refresh()

func is_local_ready() -> bool:
	return not multiplayer.get_unique_id() in _waiting

func refresh() -> void:
	for c in _chips.get_children():
		c.queue_free()
	var people := _people()
	# Alone there's nobody to list — just the prompt
	_chips.visible = people.size() > 1
	if people.size() > 1:
		for entry: Array in people:
			_chips.add_child(_chip(entry[0], entry[1], entry[2]))
	var readied := is_local_ready()
	var key := InputMode.key("interact")
	if not readied:
		_prompt.text = tr("Hold %s when you're ready") % key if holdable else tr("I'm ready")
	elif _waiting.is_empty():
		_prompt.text = tr("Everyone's ready")
	else:
		_prompt.text = tr_n("Waiting for %d builder", "Waiting for %d builders", _waiting.size()) % _waiting.size()
	_prompt.disabled = readied
	_begin.visible = multiplayer.is_server() and readied and not _waiting.is_empty()
	_undo.visible = cancellable and readied and not _waiting.is_empty()
	_undo.text = (key + " · " if holdable else "") + tr("Not ready yet")
	_fill.visible = holdable and not readied
	_total = people.size()
	_have = 0
	for entry: Array in people:
		if not entry[0] in _waiting and not NetworkManager.is_loading(entry[0]):
			_have += 1
	_bar.visible = people.size() > 1
	_bar.queue_redraw()

func _process(delta: float) -> void:
	if not holdable or not is_visible_in_tree() or is_local_ready():
		return
	if Input.is_action_pressed("interact") and not InputMode.gameplay_blocked():
		_hold += delta
		if _hold >= HOLD_TIME:
			_press()
			return
	else:
		_hold = maxf(0.0, _hold - delta * 2.0)
	_fill.custom_minimum_size.x = _prompt.size.x * _hold / HOLD_TIME

## E again takes ready back (the story handles its own keys)
func _unhandled_input(event: InputEvent) -> void:
	if holdable and cancellable and is_visible_in_tree() and is_local_ready() \
			and not _waiting.is_empty() and not InputMode.gameplay_blocked() \
			and event.is_action_pressed("interact") and not event.is_echo():
		unready_pressed.emit()

func _draw_bar() -> void:
	if _total < 1:
		return
	var gap := 3.0
	var w := (BAR_SIZE.x - gap * (_total - 1)) / _total
	var on := UiStyle.GOLD if _dark else UiStyle.OLIVE
	var off := Color(UiStyle.CREAM, 0.2) if _dark else Color(UiStyle.INK, 0.15)
	for i in _total:
		_bar.draw_rect(Rect2(i * (w + gap), 0, w, BAR_SIZE.y), on if i < _have else off)

func _press() -> void:
	if is_local_ready():
		return
	_hold = 0.0
	_fill.custom_minimum_size.x = 0.0
	Sfx.play("tally_land")
	ready_pressed.emit()

# [worker id, colour, name] for each person (not the bots), in slot order
func _people() -> Array:
	var crew := get_tree().get_nodes_in_group("players")
	crew.sort_custom(func(a, b): return a.worker_id() < b.worker_id())
	var out := []
	for slot in crew.size():
		var p: Player = crew[slot]
		if p.is_bot():
			continue
		var id := p.worker_id()
		var who: String = tr("You") if id == multiplayer.get_unique_id() else NetworkManager.name_of(id)
		if who.is_empty():
			who = tr(p.trade_name())
		if NetworkManager.is_loading(id):
			who = tr("%s · joining…") % who
		out.append([id, p.slot_color, who])
	return out

func _chip(id: int, color: Color, who: String) -> Control:
	# Someone still loading in isn't waited on, but isn't ready either
	var readied := not id in _waiting and not NetworkManager.is_loading(id)
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 8)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(12, 12)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.color = color
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(swatch)
	chip.add_child(_label(who, _text_color()))
	# A drawn tick once ready (no font glyph to trust), an open ring while not
	var mark := Control.new()
	mark.custom_minimum_size = Vector2(16, 16)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tick_color := UiStyle.GOLD if _dark else UiStyle.OLIVE
	var ring_color := _muted_color()
	mark.draw.connect(func():
		if readied:
			mark.draw_polyline(PackedVector2Array([Vector2(2, 8.5), Vector2(6.5, 13), Vector2(14, 3.5)]), tick_color, 2.5, true)
		else:
			mark.draw_arc(Vector2(8, 8), 5.5, 0.0, TAU, 20, ring_color, 1.5, true))
	# Still reading: how far through the slides, as a small bar
	if not readied and _slides.has(id):
		var at: Vector2i = _slides[id]
		var frac := float(at.x + 1) / maxf(1.0, at.y)
		var track := Control.new()
		track.custom_minimum_size = Vector2(44, 5)
		track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		track.draw.connect(func():
			track.draw_rect(Rect2(0, 0, 44, 5), Color(ring_color, 0.3))
			track.draw_rect(Rect2(0, 0, 44 * frac, 5), tick_color))
		chip.add_child(track)
	chip.add_child(mark)
	chip.modulate.a = 1.0 if readied else 0.7
	return chip

func _enter_tree() -> void:
	if not NetworkManager.crew_info_changed.is_connected(refresh):
		NetworkManager.crew_info_changed.connect(refresh)

func _exit_tree() -> void:
	if NetworkManager.crew_info_changed.is_connected(refresh):
		NetworkManager.crew_info_changed.disconnect(refresh)

func _label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # names arrive translated / as typed
	l.theme_type_variation = &"Body"
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _text_color() -> Color:
	return UiStyle.CREAM if _dark else UiStyle.INK

func _muted_color() -> Color:
	return Color(UiStyle.CREAM, 0.6) if _dark else UiStyle.INK_MUTED
