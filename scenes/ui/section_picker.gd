class_name SectionPicker
extends Control

# Replay map (main menu → "Choose a Section"): the circuit with every stretch this player
# has finished standing, their best marks beside each gate. Pick one to host a game of
# just that section (GameState.replay_section). A section opens once the one before it
# has been finished; the Sheep Gate is always open (early beta: all open,
# GameState.ALL_SECTIONS_OPEN).

signal chosen(section_index: int)
signal closed

const TWIST_NAMES := {
	"doors": "Doors", "beams": "Beams", "salvage": "Salvage", "mixing": "Mortar mixing",
	"thick": "Double-thick wall", "ruins": "Old and burned", "horn": "The horn",
	"haul": "Long haul", "spring": "The spring", "night": "Night watch", "cramped": "Narrow lanes",
	"schemes": "Schemes",
}
const FOE_NAMES := { "scout": "Scout", "brute": "Brute", "raider": "Raider", "messenger": "Messenger" }
const COLUMN_W := 520
const TITLE_SIZE := 58
const ROMAN :=["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"]

var _selected := 0
var _map: CircuitMap
var _eyebrow: Label
var _title: Label
var _ref: Label
var _text: Label
var _twists: HFlowContainer
var _twist_note: Label
var _foes: HFlowContainer
var _marks: VBoxContainer
var _mark_gems: Array[MarkGem] = []
var _mark_names: Array[Label] = []
var _build_btn: Button
var _back_btn: Button
var _lock: Label
var _progress: Label
var _progress_bar: Control
var _hint: Label
var _margin: MarginContainer
var _column: VBoxContainer
var _tallest := 0.0   # the column's height on its tallest stretch (_measure_tallest)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	resized.connect(_fit_column)
	InputMode.changed.connect(func(_pad: bool): _update_hint())
	hide()

func open(section_index := 0) -> void:
	_map.best = []
	_map.unlocked = []
	for i in GameState.SECTIONS.size():
		_map.best.append(GameState.best_marks(i))
		_map.unlocked.append(GameState.is_unlocked(i))
	_update_progress()
	_update_hint()
	_tallest = _measure_tallest()
	_fit_column()
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
			_select(i, true)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := _map.section_at(_map.get_local_mouse_position())
		if i >= 0:
			if i == _selected and _map.unlocked[i]:
				_on_build()
			else:
				_select(i)

# A hover sweep across the map stays quiet; a key or click ticks
func _select(i: int, hover := false) -> void:
	var changed := i != _selected and not hover
	_selected = i
	_map.section = i
	var sec: Dictionary = GameState.SECTIONS[i]
	var days: Array = sec["days"]
	_eyebrow.text = tr("Section %s of %s · Days %d–%d") % [ROMAN[i], ROMAN[ROMAN.size() - 1], days.front(), days.back()]
	_title.text = tr(sec["name"])
	# One line, shrunk to fit: a long name (or its translation) mustn't widen the column
	var font := _title.get_theme_font("font")
	var fs := TITLE_SIZE
	while fs > 32 and font.get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > COLUMN_W:
		fs -= 2
	_title.add_theme_font_size_override("font_size", fs)
	_ref.text = GameState.long_ref(sec["ref"])
	_text.text = tr(StoryData.SECTION_LINES[i])
	_fill_details(i)

	var best: int = _map.best[i]
	for k in GameState.MARKS.size():
		var earned := best >= 0 and bool(best & GameState.MARKS[k])
		_mark_gems[k].lit = earned
		_mark_names[k].add_theme_color_override("font_color", UiStyle.TERRACOTTA if earned else UiStyle.INK_SOFT)

	var open_ := bool(_map.unlocked[i])
	# A locked stretch's button can't hold focus (its gold ring would read as pressable)
	if not open_ and _build_btn.has_focus():
		_back_btn.grab_focus()
	_build_btn.disabled = not open_
	_build_btn.focus_mode = Control.FOCUS_ALL if open_ else Control.FOCUS_NONE
	_build_btn.text = "Locked" if not open_ else "Build again" if best >= 0 else "Build this stretch"
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
			box.remove_child(c)   # out now, so the old chips don't show for a frame
			c.queue_free()
	var sec: Dictionary = GameState.SECTIONS[i]
	var twists: Array = sec.get("twists", [])
	var open_ := bool(_map.unlocked[i])
	if not open_:
		_twists.add_child(_chip("? ? ?", false))
	elif twists.is_empty():
		_twists.add_child(_chip(tr("The plain work"), false))
	# New here: amber, like the map's NEXT tag, and spelled out in the note below. Every
	# chip carries its own sentence on hover, so the carried-over ones aren't a mystery.
	var before: Array = GameState.SECTIONS[i - 1].get("twists", []) if i > 0 else []
	var fresh: Array = twists.filter(func(t): return t not in before)
	for t: String in twists if open_ else []:
		var chip := _chip(tr(TWIST_NAMES.get(t, t)), true, false, t in fresh)
		chip.tooltip_text = _intro(t)
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		_twists.add_child(chip)
	# What's new here, in a sentence — unless everything is (the finale)
	var lines: Array = fresh.map(_intro)
	_twist_note.text = "" if not open_ else ("\n".join(lines) if fresh.size() <= 2 else tr("Everything the wall has asked of you, all at once."))
	_twist_note.visible = not _twist_note.text.is_empty()

	# Once a foe has shown up, it keeps coming (GameState.MET_AT: where each first shows)
	for k: String in FOE_NAMES.keys().filter(func(k: String): return GameState.MET_AT[k] <= i):
		var met := GameState.has_met(k)
		_foes.add_child(_chip(tr(FOE_NAMES[k]) if met else "?", met, true))

func _intro(twist: String) -> String:
	return tr(GameState.twist_intro(twist)).format({"horn": "[%s]" % InputMode.key("horn")})

func _chip(text: String, strong: bool, foe := false, fresh := false) -> Label:
	var l := _label(&"Eyebrow", 13, UiStyle.INK if fresh else UiStyle.CREAM if strong else UiStyle.INK_SOFT, false, text)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # already translated
	var bg: Color = UiStyle.AMBER if fresh else (Color(0.42, 0.12, 0.09) if foe else UiStyle.INK_SOFT) if strong else Color(UiStyle.INK, 0.08)
	l.add_theme_stylebox_override("normal", UiStyle.box(bg, Vector2(10, 4), 3))
	return l

func _update_progress() -> void:
	var n := GameState.SECTIONS.size()
	var standing := 0
	var marks := 0
	for b: int in _map.best:
		if b >= 0:
			standing += 1
			for m: int in GameState.MARKS:
				marks += int(bool(b & m))
	var total := n * GameState.MARKS.size()
	if standing == n:
		_progress.text = tr("All %d stretches standing · %d of %d marks") % [n, marks, total]
	else:
		_progress.text = tr("%d of %d stretches standing · %d of %d marks") % [standing, n, marks, total]
	_progress_bar.queue_redraw()

# One segment per stretch: standing ones amber (gold with every mark), the next outlined
func _draw_progress() -> void:
	var c := _progress_bar
	var n := GameState.SECTIONS.size()
	var w := c.size.x / n
	var next := _map.next_section()
	var all_marks: int = GameState.MARKS.reduce(func(a, m): return a | m, 0)
	for i in n:
		var r := Rect2(i * w + 1.5, 0, w - 3.0, c.size.y)
		var b: int = _map.best[i]
		if b == all_marks:   # every mark: full amber with a tick of terracotta beneath
			c.draw_rect(r, UiStyle.AMBER)
			c.draw_rect(Rect2(r.position.x, r.end.y + 2.0, r.size.x, 2.0), UiStyle.TERRACOTTA)
		elif b >= 0:
			c.draw_rect(r, Color(UiStyle.AMBER, 0.55))
		elif i == next:
			c.draw_rect(r, UiStyle.AMBER, false, 1.5)
		else:
			c.draw_rect(r, Color(UiStyle.INK, 0.12))

# The keys for the device in hand: a pad player gets its own face buttons
func _update_hint() -> void:
	if InputMode.using_pad:
		_hint.text = tr("D-Pad   Choose          %s   Build          %s   Back") % [
			InputMode.key("ui_accept"), InputMode.key("ui_cancel")]
	else:
		_hint.text = tr("← →  or  Click   Choose          Esc   Back")

func _on_build() -> void:
	if _map.unlocked[_selected]:
		hide()
		chosen.emit(_selected)

# ── Layout ─────────────────────────────────────────────────

# A stretch with a long note and three foe chips runs the column past a short window
# (the buttons fell off the bottom): shrink the whole column from its top-left corner
# until it fits, as the settings sheet does. One scale for every stretch, from the
# tallest, so the column doesn't jump in size as the player browses. The margin is
# scaled, not the column — a container resets its children's scale.
func _fit_column() -> void:
	if size.y <= 0.0:
		return
	var pad := float(_margin.get_theme_constant("margin_top") + _margin.get_theme_constant("margin_bottom"))
	var need := maxf(_tallest, _column.get_combined_minimum_size().y) + pad
	var s := clampf(size.y / need, 0.6, 1.0)
	_margin.scale = Vector2(s, s)
	_margin.position = Vector2.ZERO
	_margin.size = size / s

## Fill the column with each stretch in turn (the parts that vary: its line, twists,
## note, foes) and keep the tallest; open() then selects the real one
func _measure_tallest() -> float:
	# Before the first layout (the picker is still hidden) everything is 1 px wide and the
	# wrapped text measures a word to a line: give the varying parts their real widths,
	# and sort the chip rows by hand (a flow container only knows its height once sorted)
	for c: Control in [_text, _twist_note, _twists]:
		c.size.x = COLUMN_W
	_foes.size.x = COLUMN_W - _foes.get_parent().get_child(0).get_combined_minimum_size().x - 12
	var tallest := 0.0
	for i in GameState.SECTIONS.size():
		_text.text = tr(StoryData.SECTION_LINES[i])
		_fill_details(i)
		for flow: Container in [_twists, _foes]:
			flow.notification(Container.NOTIFICATION_SORT_CHILDREN)
		tallest = maxf(tallest, _column.get_combined_minimum_size().y)
	return tallest

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
	_margin = margin
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 140)
	margin.add_theme_constant_override("margin_top", 110)
	margin.add_theme_constant_override("margin_bottom", 64)
	add_child(margin)

	var column := VBoxContainer.new()
	_column = column
	column.add_theme_constant_override("separation", 10)
	# Narrow enough that the text stays clear of the gate plaques on the west wall
	column.custom_minimum_size.x = COLUMN_W
	column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	column.add_child(_label(&"Eyebrow", 15, UiStyle.TERRACOTTA, false, "Choose a stretch of wall"))
	# How far round the circuit this player has come: a segment per stretch, and a tally
	var progress := HBoxContainer.new()
	progress.add_theme_constant_override("separation", 14)
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(progress)
	_progress_bar = Control.new()
	_progress_bar.custom_minimum_size = Vector2(12 * 16, 8)
	_progress_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_bar.draw.connect(_draw_progress)
	progress.add_child(_progress_bar)
	_progress = _label(&"Body", 16, UiStyle.INK_SOFT, false)
	_progress.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # already translated
	progress.add_child(_progress)
	column.add_child(_gap(20))
	_eyebrow = _label(&"Eyebrow", 14, UiStyle.INK_SOFT, false)
	column.add_child(_eyebrow)
	_title = _label(&"Heading", TITLE_SIZE, UiStyle.INK, false)
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
	_twists = HFlowContainer.new()
	_twists.add_theme_constant_override("h_separation", 8)
	_twists.add_theme_constant_override("v_separation", 8)
	column.add_child(_twists)
	_twist_note = _label(&"Body", 18, UiStyle.INK_SOFT)
	column.add_child(_twist_note)
	column.add_child(_gap(6))
	var foe_row := HBoxContainer.new()
	foe_row.add_theme_constant_override("separation", 12)
	column.add_child(foe_row)
	var foe_head := _label(&"Eyebrow", 13, UiStyle.TERRACOTTA, false, "Foes here")
	foe_head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foe_row.add_child(foe_head)
	_foes = HFlowContainer.new()
	_foes.add_theme_constant_override("h_separation", 8)
	_foes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foe_row.add_child(_foes)
	column.add_child(_gap(18))
	column.add_child(_label(&"Eyebrow", 13, UiStyle.TERRACOTTA, false, "Your best here"))
	_marks = VBoxContainer.new()
	_marks.add_theme_constant_override("separation", 6)
	column.add_child(_marks)
	for m: int in GameState.MARKS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var gem := MarkGem.new(false, 20.0)
		gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(gem)
		var name_ := _label(&"Body", 20, UiStyle.INK_SOFT, false, GameState.MARK_NAMES[m])
		row.add_child(name_)
		_marks.add_child(row)
		_mark_gems.append(gem)
		_mark_names.append(name_)
	column.add_child(_gap(30))

	# Build and Back side by side: one row, so the column stays short enough for the hint
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(buttons)
	_build_btn = Button.new()
	_build_btn.theme_type_variation = &"PrimaryButton"
	_build_btn.pressed.connect(_on_build)
	buttons.add_child(_build_btn)
	_back_btn = Button.new()
	_back_btn.theme_type_variation = &"GhostButton"
	_back_btn.text = "Back"
	_back_btn.pressed.connect(close)
	buttons.add_child(_back_btn)
	for b: Button in [_build_btn, _back_btn]:
		b.mouse_entered.connect(b.grab_focus)
	# ← → walk the ring, so up/down hop between the two
	_build_btn.focus_neighbor_bottom = _build_btn.get_path_to(_back_btn)
	_back_btn.focus_neighbor_top = _back_btn.get_path_to(_build_btn)
	_lock = _label(&"Caption", 17, UiStyle.TERRACOTTA_DEEP, false)
	column.add_child(_lock)

	# Bottom of the column, on the parchment wash (the land on the right is too bright for
	# it) — in the flow, so a tall column pushes it down rather than running over it
	var push := _gap(12)
	push.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(push)
	_hint = _label(&"Eyebrow", 13, UiStyle.INK_MUTED, false)
	_hint.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # set translated
	column.add_child(_hint)

func _label(variation: StringName, font_size: int, color: Color, wrapped := true, text := "") -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if wrapped:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
