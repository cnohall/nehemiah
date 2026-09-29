class_name SectionPicker
extends Control

# Replay map (main menu → "Choose a Section"): the circuit with every stretch this player
# has finished standing, their best marks beside each gate. Pick one to host a game of
# just that section (GameState.replay_section). A section opens once the one before it
# has been finished; the Sheep Gate is always open.

signal chosen(section_index: int)
signal closed

const TWIST_NAMES := {
	"doors": "Doors", "beams": "Beams", "salvage": "Salvage", "mixing": "Mortar mixing",
	"thick": "Double-thick wall", "horn": "The horn",
	"haul": "Long haul", "spring": "The spring", "night": "Night watch", "cramped": "Narrow lanes",
	"schemes": "Schemes",
}
const FOE_NAMES := { "scout": "Scout", "brute": "Brute", "raider": "Raider", "messenger": "Messenger" }
const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"]

var _selected := 0
var _map: CircuitMap
var _eyebrow: Label
var _title: Label
var _ref: Label
var _text: Label
var _twists: HFlowContainer
var _twist_note: Label
var _foes: HFlowContainer
var _marks: BoxContainer
var _build_btn: Button
var _back_btn: Button
var _lock: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	hide()

func open(section_index := 0) -> void:
	_map.best = []
	_map.unlocked = []
	for i in GameState.SECTIONS.size():
		_map.best.append(GameState.best_marks(i))
		_map.unlocked.append(GameState.is_unlocked(i))
	show()
	UiFx.fade_in(self, 0.35)
	_select(clampi(section_index, 0, GameState.SECTIONS.size() - 1))
	if Mobile.enabled():
		return   # no focus ring on touch
	if _build_btn.disabled:
		_back_btn.grab_focus()
	else:
		_build_btn.grab_focus()

func close() -> void:
	hide()
	closed.emit()

# ── Input ──────────────────────────────────────────────────

# Left/right walk the ring (up/down stay with the buttons); Esc backs out
func _input(event: InputEvent) -> void:
	if not visible:
		return
	var n := GameState.SECTIONS.size()
	if event.is_action_pressed("ui_left"):
		get_viewport().set_input_as_handled()
		_select((_selected - 1 + n) % n)
	elif event.is_action_pressed("ui_right"):
		get_viewport().set_input_as_handled()
		_select((_selected + 1) % n)
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()

# Hover picks the stretch under the pointer; a click on the one already picked builds it.
# Phones: a tap only picks (a drag across the map would pick whatever the finger passed,
# and the next tap would build it); the Build button builds.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not Mobile.enabled():
		var i := _map.section_at(_map.get_local_mouse_position())
		if i >= 0 and i != _selected:
			_select(i)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := _map.section_at(_map.get_local_mouse_position())
		if i >= 0:
			if i == _selected and _map.unlocked[i] and not Mobile.enabled():
				_on_build()
			else:
				_select(i)

func _select(i: int) -> void:
	var changed := i != _selected
	_selected = i
	_map.section = i
	var sec: Dictionary = GameState.SECTIONS[i]
	var days: Array = sec["days"]
	_eyebrow.text = tr("Section %s of %s · Days %d–%d") % [ROMAN[i], ROMAN[ROMAN.size() - 1], days.front(), days.back()]
	_title.text = tr(sec["name"])
	_ref.text = GameState.long_ref(sec["ref"])
	_text.text = tr(StoryData.SECTION_LINES[i])
	_fill_details(i)

	for c in _marks.get_children():
		c.queue_free()
	var best: int = _map.best[i]
	for m: int in GameState.MARKS:
		var earned := best >= 0 and bool(best & m)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var gem := MarkGem.new(earned, 16.0 if Mobile.enabled() else 20.0)
		gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		gem.tooltip_text = GameState.MARK_NAMES[m]
		row.add_child(gem)
		if Mobile.enabled():
			_marks.add_child(row)
			continue
		row.add_child(_label(&"Body", 20, UiStyle.TERRACOTTA if earned else UiStyle.INK_MUTED, false,
			GameState.MARK_NAMES[m]))
		_marks.add_child(row)

	var open_ := bool(_map.unlocked[i])
	_build_btn.disabled = not open_
	_build_btn.text = "Build again" if best >= 0 else "Build this stretch"
	_lock.visible = not open_
	if not open_:
		_lock.text = tr("Finish the %s first") % tr(GameState.SECTIONS[i - 1]["name"])
	if changed:
		Sfx.play("tally")

# What the stretch holds: its twists, and the foes who come there. Locked stretches keep
# their twists to themselves; a foe this player hasn't met yet shows as "?".
func _fill_details(i: int) -> void:
	for box: Control in [_twists, _foes]:
		for c in box.get_children():
			c.queue_free()
	var sec: Dictionary = GameState.SECTIONS[i]
	var twists: Array = sec.get("twists", [])
	var open_ := bool(_map.unlocked[i])
	if not open_:
		_twists.add_child(_chip("? ? ?", false))
	elif twists.is_empty():
		_twists.add_child(_chip(tr("The plain work"), false))
	for t: String in twists if open_ else []:
		_twists.add_child(_chip(tr(TWIST_NAMES.get(t, t)), true))
	# What's new here, in a sentence — unless everything is (the finale)
	var before: Array = GameState.SECTIONS[i - 1].get("twists", []) if i > 0 else []
	var fresh: Array = twists.filter(func(t): return t not in before)
	var lines: Array = fresh.map(func(t: String): return tr(GameState.TWIST_INTRO.get(t, "")).format({"horn": "[%s]" % InputMode.key("horn")}))
	_twist_note.text = "" if not open_ else ("
".join(lines) if fresh.size() <= 2 else tr("Everything the wall has asked of you, all at once."))
	_twist_note.visible = not _twist_note.text.is_empty()

	# Once a foe has shown up, it keeps coming (GameState.MET_AT: where each first shows)
	for k: String in FOE_NAMES.keys().filter(func(k: String): return GameState.MET_AT[k] <= i):
		var met := GameState.has_met(k)
		_foes.add_child(_chip(tr(FOE_NAMES[k]) if met else "?", met, true))

func _chip(text: String, strong: bool, foe := false) -> Label:
	var l := _label(&"Eyebrow", 11 if Mobile.enabled() else 13, UiStyle.CREAM if strong else UiStyle.INK_SOFT, false, text)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # already translated
	var bg: Color = (Color(0.42, 0.12, 0.09) if foe else UiStyle.INK_SOFT) if strong else Color(UiStyle.INK, 0.08)
	l.add_theme_stylebox_override("normal", UiStyle.box(bg, Vector2(10, 4), 3))
	return l

func _on_build() -> void:
	if _map.unlocked[_selected]:
		hide()
		chosen.emit(_selected)

# ── Layout ─────────────────────────────────────────────────

func _build() -> void:
	# Phones: a narrower column in phone type, its details scrolling between a fixed
	# header (back · title) and the Build button, so nothing runs off a short screen
	var m := Mobile.enabled()
	if m:
		theme = Mobile.theme
	var bg := ColorRect.new()
	bg.color = UiStyle.PARCHMENT
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_map = CircuitMap.new()
	_map.picker = true
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_map)
	if m:
		_map.offset_left = 200   # the city clear of the text column

	var s := Mobile.safe_insets() if m else Vector4.ZERO
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", int(16 + s.x) if m else 140)
	margin.add_theme_constant_override("margin_top", int(8 + s.y) if m else 110)
	margin.add_theme_constant_override("margin_bottom", int(12 + s.w) if m else 64)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6 if m else 10)
	column.custom_minimum_size.x = 380 if m else 620
	column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	# Details: on phones in a scroll between the header and the button
	var details := column
	if m:
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 4)
		column.add_child(head)
		_back_btn = UiIcons.button("back", "Back", 48.0, &"FlatIconButton")
		_back_btn.pressed.connect(close)
		head.add_child(_back_btn)
		var t := _label(&"Eyebrow", 12, UiStyle.TERRACOTTA, false, "Choose a stretch of wall")
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(t)
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.mouse_filter = Control.MOUSE_FILTER_PASS
		column.add_child(scroll)
		details = VBoxContainer.new()
		details.add_theme_constant_override("separation", 6)
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scroll.add_child(details)
	else:
		column.add_child(_label(&"Eyebrow", 15, UiStyle.TERRACOTTA, false, "Choose a stretch of wall"))
		column.add_child(_gap(28))
	_eyebrow = _label(&"Eyebrow", 12 if m else 14, UiStyle.INK_SOFT, false)
	details.add_child(_eyebrow)
	_title = _label(&"Heading", 28 if m else 58, UiStyle.INK, false)
	_title.add_theme_font_override("font", UiStyle.tracked(UiStyle.CINZEL_BOLD, 3 if m else 5))
	details.add_child(_title)
	_ref = _label(&"Eyebrow", 12 if m else 14, UiStyle.TERRACOTTA, false)
	details.add_child(_ref)
	var rule := ColorRect.new()
	rule.color = UiStyle.AMBER
	rule.custom_minimum_size = Vector2(72, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	details.add_child(rule)
	_text = _label(&"Body", 14 if m else 24, UiStyle.INK)
	_text.add_theme_constant_override("line_spacing", 3 if m else 6)
	_text.custom_minimum_size.y = 0 if m else 96
	details.add_child(_text)
	_twists = HFlowContainer.new()
	_twists.add_theme_constant_override("h_separation", 6 if m else 8)
	_twists.add_theme_constant_override("v_separation", 6 if m else 8)
	details.add_child(_twists)
	_twist_note = _label(&"Body", 13 if m else 18, UiStyle.INK_SOFT)
	details.add_child(_twist_note)
	details.add_child(_gap(2 if m else 6))
	var foe_row := HBoxContainer.new()
	foe_row.add_theme_constant_override("separation", 12)
	details.add_child(foe_row)
	var foe_head := _label(&"Eyebrow", 12 if m else 13, UiStyle.TERRACOTTA, false, "Foes here")
	foe_head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foe_row.add_child(foe_head)
	_foes = HFlowContainer.new()
	_foes.add_theme_constant_override("h_separation", 6 if m else 8)
	_foes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foe_row.add_child(_foes)
	# Phones: the marks as a row of gems after the foes
	_marks = HBoxContainer.new() if m else VBoxContainer.new()
	_marks.add_theme_constant_override("separation", 4 if m else 6)
	if m:
		var best_row := HBoxContainer.new()
		best_row.add_theme_constant_override("separation", 12)
		details.add_child(best_row)
		var best := _label(&"Eyebrow", 12, UiStyle.TERRACOTTA, false, "Your best here")
		best.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		best_row.add_child(best)
		_marks.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		best_row.add_child(_marks)
	else:
		details.add_child(_gap(18))
		details.add_child(_label(&"Eyebrow", 13, UiStyle.TERRACOTTA, false, "Your best here"))
		details.add_child(_marks)
	column.add_child(_gap(6 if m else 30))

	_build_btn = Button.new()
	_build_btn.theme_type_variation = &"PrimaryButton"
	_build_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_build_btn.pressed.connect(_on_build)
	_lock = _label(&"Caption", 14 if m else 17, UiStyle.TERRACOTTA_DEEP, false)
	if m:
		# The button, and why it's locked, side by side: one row at the foot
		var foot := HBoxContainer.new()
		foot.add_theme_constant_override("separation", 14)
		column.add_child(foot)
		_build_btn.focus_mode = Control.FOCUS_NONE
		_build_btn.pressed.connect(Mobile.haptic)
		foot.add_child(_build_btn)
		_lock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_lock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_lock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		foot.add_child(_lock)
		return
	column.add_child(_build_btn)
	column.add_child(_lock)
	_back_btn = Button.new()
	_back_btn.theme_type_variation = &"GhostButton"
	_back_btn.text = "Back"
	_back_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_back_btn.pressed.connect(close)
	column.add_child(_back_btn)
	for b: Button in [_build_btn, _back_btn]:
		b.mouse_entered.connect(b.grab_focus)

	var hint := _label(&"Eyebrow", 13, UiStyle.INK_MUTED, false,
		"← →  or  Click   Choose          Esc   Back")
	# Bottom-left, on the parchment wash — the land on the right is too bright for it
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.position += Vector2(140, -64)
	add_child(hint)

func _label(variation: StringName, font_size: int, color: Color, wrap := true, text := "") -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
