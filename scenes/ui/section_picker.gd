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
const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"]

var _selected := 0
var _map: CircuitMap
var _eyebrow: Label
var _title: Label
var _ref: Label
var _text: Label
var _meta: Label
var _marks: VBoxContainer
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

# Hover picks the stretch under the pointer; a click on the one already picked builds it
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var i := _map.section_at(_map.get_local_mouse_position())
		if i >= 0 and i != _selected:
			_select(i)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := _map.section_at(_map.get_local_mouse_position())
		if i >= 0:
			if i == _selected and _map.unlocked[i]:
				_on_build()
			else:
				_select(i)

func _select(i: int) -> void:
	var changed := i != _selected
	_selected = i
	_map.section = i
	var sec: Dictionary = GameState.SECTIONS[i]
	var days: Array = sec["days"]
	_eyebrow.text = "Section %s of %s · Days %d–%d" % [ROMAN[i], ROMAN[ROMAN.size() - 1], days.front(), days.back()]
	_title.text = sec["name"]
	_ref.text = "Nehemiah %s" % sec["ref"].trim_prefix("Neh. ")
	_text.text = StoryData.SECTION_LINES[i]
	var twists: Array = sec.get("twists", []).map(func(t: String): return TWIST_NAMES.get(t, t))
	_meta.text = "With: %s" % ", ".join(twists) if not twists.is_empty() else "The plain work: carry, build, defend"

	for c in _marks.get_children():
		c.queue_free()
	var best: int = _map.best[i]
	for m: int in GameState.MARKS:
		var earned := best >= 0 and bool(best & m)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var gem := MarkGem.new(earned, 20.0)
		gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(gem)
		row.add_child(_label(&"Body", 20, UiStyle.TERRACOTTA if earned else UiStyle.INK_MUTED, false,
			GameState.MARK_NAMES[m]))
		_marks.add_child(row)

	var open_ := bool(_map.unlocked[i])
	_build_btn.disabled = not open_
	_build_btn.text = "Build again" if best >= 0 else "Build this stretch"
	_lock.visible = not open_
	if not open_:
		_lock.text = "Finish the %s first" % GameState.SECTIONS[i - 1]["name"]
	if changed:
		Sfx.play("tally")

func _on_build() -> void:
	if _map.unlocked[_selected]:
		hide()
		chosen.emit(_selected)

# ── Layout ─────────────────────────────────────────────────

func _build() -> void:
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

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 140)
	margin.add_theme_constant_override("margin_top", 110)
	margin.add_theme_constant_override("margin_bottom", 64)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.custom_minimum_size.x = 620
	column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	column.add_child(_label(&"Eyebrow", 15, UiStyle.TERRACOTTA, false, "Choose a stretch of wall"))
	column.add_child(_gap(28))
	_eyebrow = _label(&"Eyebrow", 14, UiStyle.INK_SOFT, false)
	column.add_child(_eyebrow)
	_title = _label(&"Heading", 58, UiStyle.INK, false)
	_title.add_theme_font_override("font", UiStyle.tracked(UiStyle.CINZEL_BOLD, 5))
	column.add_child(_title)
	_ref = _label(&"Eyebrow", 14, UiStyle.TERRACOTTA, false)
	column.add_child(_ref)
	var rule := ColorRect.new()
	rule.color = UiStyle.AMBER
	rule.custom_minimum_size = Vector2(72, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(rule)
	_text = _label(&"Body", 24, UiStyle.INK)
	_text.add_theme_constant_override("line_spacing", 6)
	_text.custom_minimum_size.y = 96
	column.add_child(_text)
	_meta = _label(&"Body", 19, UiStyle.INK_SOFT, false)
	column.add_child(_meta)
	column.add_child(_gap(18))
	column.add_child(_label(&"Eyebrow", 13, UiStyle.TERRACOTTA, false, "Your best here"))
	_marks = VBoxContainer.new()
	_marks.add_theme_constant_override("separation", 6)
	column.add_child(_marks)
	column.add_child(_gap(30))

	_build_btn = Button.new()
	_build_btn.theme_type_variation = &"PrimaryButton"
	_build_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_build_btn.pressed.connect(_on_build)
	column.add_child(_build_btn)
	_lock = _label(&"Caption", 17, UiStyle.TERRACOTTA_DEEP, false)
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
