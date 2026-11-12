extends Control

# Modal settings sheet, shared by the title screen and the in-game menu.
# Writes straight through to the Settings autoload; Esc / Done closes.
# One page per tab along the top (General, Display, Audio, Controls, Experimental);
# a pad's shoulder buttons step between them.
# Phones: a full-height side sheet from the right (Material side sheet): no tabs, the
# pages stacked in one scroll (no window/vsync rows, no Controls page), then the version
# and the credits; tap outside or back closes.

signal closed

const SHEET_WIDTH := 420.0   # room for German labels beside a slider

## Phones: Settings › About rolls the credits through this, when the screen has them
var on_credits := Callable()

@onready var _windowed:   Button = %Windowed
@onready var _fullscreen: Button = %Fullscreen
@onready var _vsync_on:   Button = %VsyncOn
@onready var _vsync_off:  Button = %VsyncOff
@onready var _shake_on:   Button = %ShakeOn
@onready var _shake_off:  Button = %ShakeOff
@onready var _volume:     HSlider = %Volume
@onready var _volume_val: Label  = %VolumeValue
@onready var _music:      HSlider = %Music
@onready var _music_val:  Label  = %MusicValue
@onready var _sfx:        HSlider = %Sfx
@onready var _sfx_val:    Label  = %SfxValue
@onready var _voice:      HSlider = %Voice
@onready var _voice_val:  Label  = %VoiceValue
@onready var _done:       Button = %Done
@onready var _modal:      PanelContainer = $Center/Modal

const KEY_ROWS := [
	["move_north", "Move up"], ["move_west", "Move left"],
	["move_south", "Move down"], ["move_east", "Move right"],
	["interact", "Pick up · deliver · build"], ["drop", "Drop"],
	["dash", "Dash"], ["throw_charge", "Sling"], ["horn", "Horn"],
	["call", "Call"], ["reveal", "What can I do here?"],
]

# Settings property → row label (GDD §5.21)
const EXPERIMENTS := [
	["exp_call_early", "Call waves early"],
]

enum { GENERAL, DISPLAY, AUDIO, CONTROLS, EXPERIMENTAL }
const TABS := ["General", "Display", "Audio", "Controls", "Experimental"]
# Every page's columns line up, so switching tabs doesn't shift the controls sideways
const LABEL_W := 190.0
const CONTROL_W := 360.0

var _exp_btns := {}         # Settings property → [Off, On]
var _forecast_btns: Array[Button]   # indexed by Settings.FORECAST_*
var _hints_on: Button
var _hints_off: Button
var _stats_on: Button
var _stats_off: Button
var _rumble_on: Button
var _rumble_off: Button
var _follow_cam: Button
var _fixed_cam: Button
var _game_view: Button
var _map_view: Button
var _pages_box: VBoxContainer
var _pages: Array[GridContainer] = []   # indexed by tab
var _tab_btns: Array[Button] = []
var _tab := GENERAL                     # kept between openings
var _target: GridContainer   # the grid rows are being added to
var _key_buttons := {}      # action → Button
var _reset: Button
var _language: OptionButton
var _window_size: OptionButton
var _window_sizes: Array[Vector2i] = []
var _quality_btns: Array[Button] = []
var _scale_btns: Array[Button] = []
var _listening := ""        # action waiting for a key press, or ""
var _tab_bar: HBoxContainer
var _sheet_tween: Tween
var _credits_btn: Button

func _ready() -> void:
	hide()
	_windowed.pressed.connect(_toggle.bind("fullscreen", false))
	_fullscreen.pressed.connect(_toggle.bind("fullscreen", true))
	_vsync_on.pressed.connect(_toggle.bind("vsync", true))
	_vsync_off.pressed.connect(_toggle.bind("vsync", false))
	_shake_on.pressed.connect(_toggle.bind("screen_shake", true))
	_shake_off.pressed.connect(_toggle.bind("screen_shake", false))
	_volume.value_changed.connect(_on_volume)
	_volume.drag_ended.connect(func(_changed): Settings.save())
	_music.value_changed.connect(_on_music)
	_music.drag_ended.connect(func(_changed): Settings.save())
	_sfx.value_changed.connect(_on_sfx)
	_sfx.drag_ended.connect(func(_changed): Settings.save())
	_voice.value_changed.connect(_on_voice)
	_voice.drag_ended.connect(func(_changed): Settings.save())
	_done.pressed.connect(close)
	_build_tabs()
	_build_pages()
	for g in _pages:
		_even_rows(g)
	if Mobile.enabled():
		_build_side_sheet()
	resized.connect(func(): if visible: _fit_modal.call_deferred())

# Every control spans the same width, and a row's choices share it evenly — rows of their
# own natural widths made a ragged right edge
func _even_rows(grid: GridContainer) -> void:
	for i in range(1, grid.get_child_count(), grid.columns):
		(grid.get_child(i - 1) as Control).custom_minimum_size.x = LABEL_W
		var c := grid.get_child(i) as Control
		c.size_flags_horizontal = Control.SIZE_FILL
		c.custom_minimum_size.x = maxf(c.custom_minimum_size.x, CONTROL_W)
		if c is HBoxContainer:
			for k in c.get_children():
				if k is Button or k is Slider:
					(k as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL

# The pages share the tallest one's height (the sheet doesn't jump between tabs), and the
# UI is boosted in small windows (Settings._fit_ui), so a 1280×720 window could clip it:
# shrink it around its centre until it fits.
func _fit_modal() -> void:
	if Mobile.enabled():
		return   # phones use the side sheet, sized in dp
	# A hidden grid's cached minimum goes stale: measure each page shown, then put them back
	var tallest := 0.0
	for g in _pages:
		var was := g.visible
		g.visible = true
		g.update_minimum_size()
		tallest = maxf(tallest, g.get_combined_minimum_size().y)
		g.visible = was
	_pages_box.custom_minimum_size.y = tallest
	# Scale the Center node: a Container resets its children's scale whenever it re-sorts
	var center := $Center as Control
	var need := ($Center/Modal as Control).get_combined_minimum_size().y
	var s := clampf(size.y * 0.97 / need, 0.5, 1.0) if need > 0.0 else 1.0
	center.pivot_offset = center.size / 2.0
	center.scale = Vector2(s, s)

func open() -> void:
	_windowed.button_pressed   = not Settings.fullscreen
	_fullscreen.button_pressed = Settings.fullscreen
	# Run inside the editor's Game tab, the editor owns the window
	var fixed := not Settings.can_change_window()
	for b: Button in [_windowed, _fullscreen]:
		b.disabled = fixed
		b.tooltip_text = "Embedded in the editor: run the game floating to change the window" if fixed else ""
	_vsync_on.button_pressed   = Settings.vsync
	_vsync_off.button_pressed  = not Settings.vsync
	_shake_on.button_pressed   = Settings.screen_shake
	_shake_off.button_pressed  = not Settings.screen_shake
	_volume.set_value_no_signal(Settings.volume * 100.0)
	_volume_val.text = "%d%%" % roundi(_volume.value)
	_music.set_value_no_signal(Settings.music_volume * 100.0)
	_music_val.text = "%d%%" % roundi(_music.value)
	_sfx.set_value_no_signal(Settings.sfx_volume * 100.0)
	_sfx_val.text = "%d%%" % roundi(_sfx.value)
	_voice.set_value_no_signal(Settings.voice_volume * 100.0)
	_voice_val.text = "%d%%" % roundi(_voice.value)
	_select_language()
	_select_graphics()
	if _window_size != null:
		_select_window_size()
	_rumble_on.button_pressed    = Settings.rumble
	_rumble_off.button_pressed   = not Settings.rumble
	_follow_cam.button_pressed   = not Settings.fixed_camera
	_fixed_cam.button_pressed    = Settings.fixed_camera
	_game_view.button_pressed    = not Settings.turn_to_map
	_map_view.button_pressed     = Settings.turn_to_map
	_hints_on.button_pressed      = Settings.hints
	_hints_off.button_pressed     = not Settings.hints
	if _stats_on != null:
		_stats_on.button_pressed  = Settings.share_stats
		_stats_off.button_pressed = not Settings.share_stats
	_forecast_btns[Settings.exp_forecast].button_pressed = true
	for key: String in _exp_btns:
		_exp_btns[key][0].button_pressed = not Settings.get(key)
		_exp_btns[key][1].button_pressed = Settings.get(key)
	_show_tab(_tab)
	show()
	_fit_modal.call_deferred()   # after the rows above have laid out
	UiFx.fade_in(self, 0.18)
	if Mobile.enabled():
		_credits_btn.visible = on_credits.is_valid()
		_slide_in()
	else:
		_tab_btns[_tab].grab_focus()

func close() -> void:
	_listening = ""
	Settings.save()
	hide()
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
	elif event is InputEventJoypadButton and event.pressed and _listening.is_empty() \
			and event.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
		get_viewport().set_input_as_handled()
		var step := -1 if event.button_index == JOY_BUTTON_LEFT_SHOULDER else 1
		_show_tab(wrapi(_tab + step, 0, TABS.size()))
		_tab_btns[_tab].grab_focus()

# Rebinding grabs the very next key / click before the GUI or ui_* actions see it
func _input(event: InputEvent) -> void:
	if _listening.is_empty() or not visible:
		return
	var bind: InputEvent = null
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode != KEY_ESCAPE:
			var k := InputEventKey.new()
			k.physical_keycode = event.physical_keycode
			bind = k
	elif event is InputEventMouseButton and event.pressed and event.button_index not in [
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		var m := InputEventMouseButton.new()
		m.button_index = event.button_index
		bind = m
	elif not (event is InputEventJoypadButton and event.pressed):
		return   # motion etc.; Esc or a pad button cancels below
	get_viewport().set_input_as_handled()
	var action := _listening
	_listening = ""
	if bind != null:
		Settings.rebind(action, bind)
		InputMode.bindings_changed()
	_refresh_keys()
	_key_buttons[action].grab_focus()

func _toggle(key: String, value: bool) -> void:
	Settings.set(key, value)
	Settings.apply()
	Settings.save()
	if key == "fullscreen" and _window_size != null:
		_window_size.disabled = value
	# The camera moves in Main._process, which stops while paused: show the change now
	if key in ["fixed_camera", "turn_to_map"]:
		var scene := get_tree().current_scene
		if scene != null and scene.has_method("refresh_camera"):
			scene.refresh_camera()

func _on_volume(v: float) -> void:
	Settings.volume = v / 100.0
	Settings.apply()
	_volume_val.text = "%d%%" % roundi(v)

func _on_music(v: float) -> void:
	Settings.music_volume = v / 100.0
	Settings.apply()
	_music_val.text = "%d%%" % roundi(v)

func _on_sfx(v: float) -> void:
	Settings.sfx_volume = v / 100.0
	Settings.apply()
	_sfx_val.text = "%d%%" % roundi(v)

func _on_voice(v: float) -> void:
	Settings.voice_volume = v / 100.0
	Settings.apply()
	_voice_val.text = "%d%%" % roundi(v)

# ── Phone side sheet ───────────────────────────────────────

func _build_side_sheet() -> void:
	var s := Mobile.safe_insets()
	var vbox := $Center/Modal/VBox as VBoxContainer
	# Out of the centring container: pinned to the right edge, full height
	_modal.reparent(self, false)
	_modal.custom_minimum_size = Vector2.ZERO
	_place_sheet()
	var sheet := UiStyle.box(UiStyle.PARCHMENT, Vector2(24, 16), 0)
	sheet.corner_radius_top_left = 16
	sheet.corner_radius_bottom_left = 16
	sheet.content_margin_right = 24 + s.z
	sheet.content_margin_top = 12 + s.y
	sheet.content_margin_bottom = 16 + s.w
	_modal.add_theme_stylebox_override("panel", UiStyle.shadowed(sheet, 24, 0.35, 0.0))
	$Center.hide()
	vbox.add_theme_constant_override("separation", 14)

	# Header: title left, close right
	var head := HBoxContainer.new()
	vbox.add_child(head)
	vbox.move_child(head, 0)
	vbox.get_node("Header").reparent(head)
	var header := head.get_child(0) as Control
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var close_btn := UiIcons.button("close", "Close", 48.0, &"FlatIconButton")
	close_btn.pressed.connect(close)
	head.add_child(close_btn)
	_tab_bar.hide()

	# No display rows: phones are always fullscreen and vsync'd
	for c: Control in [_windowed.get_parent(), _vsync_on.get_parent()]:
		c.hide()
		c.get_parent().get_child(c.get_index() - 1).hide()   # its label
	for slider: HSlider in [_volume, _music, _sfx, _voice]:
		slider.custom_minimum_size = Vector2(130, 48)   # the whole row is the target
	for b: Button in [_shake_on, _shake_off]:
		b.custom_minimum_size = Vector2(65, 48)   # the pair spans a slider's width
	_pages_box.add_theme_constant_override("separation", 14)
	for i in _pages.size():
		var g := _pages[i]
		g.add_theme_constant_override("h_separation", 20)
		g.add_theme_constant_override("v_separation", 4)
		_phone_rows(g)
		if i != GENERAL and i != CONTROLS:
			# The tab's name heads its stretch of the one scroll
			var h := Label.new()
			h.text = TABS[i]
			h.theme_type_variation = &"Eyebrow"
			_pages_box.add_child(h)
			_pages_box.move_child(h, g.get_index())
	_done.get_parent().hide()
	_language.custom_minimum_size.x = 0
	_language.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# The rows scroll under the fixed header on a short screen; at their foot, the
	# version and the credits (off the title screen on phones)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	vbox.move_child(scroll, _pages_box.get_index())
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 14)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	_pages_box.reparent(rows)
	var version := Label.new()
	version.theme_type_variation = &"Caption"
	version.add_theme_font_size_override("font_size", 12)
	version.add_theme_color_override("font_color", UiStyle.INK_MUTED)
	version.text = "v%s" % ProjectSettings.get_setting("application/config/version", "")
	version.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	version.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	version.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var about := HBoxContainer.new()
	about.add_theme_constant_override("separation", 12)
	rows.add_child(about)
	about.add_child(version)
	_credits_btn = Button.new()
	_credits_btn.theme_type_variation = &"GhostButton"
	_credits_btn.text = "Credits"
	_credits_btn.focus_mode = Control.FOCUS_NONE
	_credits_btn.pressed.connect(func(): on_credits.call())
	about.add_child(_credits_btn)

	# Tap outside the sheet closes it
	$Scrim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			close())

# Every choice row shares the sheet's width evenly: the desktop's fixed column widths
# (LABEL_W + CONTROL_W) and segment widths would push the sheet off the right edge
func _phone_rows(grid: GridContainer) -> void:
	for c in grid.get_children():
		if c is HBoxContainer:
			(c as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
			(c as Control).custom_minimum_size.x = 0
			for k in c.get_children():
				if k is Button and not (k in [_shake_on, _shake_off]):
					(k as Button).custom_minimum_size = Vector2(0, 48)
					(k as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
					(k as Button).add_theme_font_size_override("font_size", 12)
					(k as Button).add_theme_font_override("font", UiStyle.tracked(UiStyle.CINZEL_SEMI, 0))
					(k as Button).clip_text = true
		elif c is Label and (c as Label).theme_type_variation == &"Caption":
			(c as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			(c as Label).custom_minimum_size.x = 0
		elif c is Label and c.get_index() % grid.columns == 0:
			(c as Label).custom_minimum_size.x = 0
			(c as Label).size_flags_horizontal = Control.SIZE_FILL   # the choices get the spare width
		elif c is Control:
			(c as Control).custom_minimum_size.x = 0

# Pinned right, full height. Re-applied on open: a container that briefly outgrew
# its anchors keeps the larger offsets.
func _place_sheet() -> void:
	_modal.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_modal.offset_left = -(SHEET_WIDTH + Mobile.safe_insets().z)
	_modal.offset_right = 0
	_modal.offset_top = 0
	_modal.offset_bottom = 0

func _slide_in() -> void:
	if _sheet_tween:
		_sheet_tween.kill()
	_place_sheet()
	var w := _modal.offset_left
	_modal.position.x = get_viewport_rect().size.x
	_sheet_tween = create_tween()
	_sheet_tween.tween_property(_modal, "position:x", get_viewport_rect().size.x + w, 0.28) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

# ── Tabs and pages ─────────────────────────────────────────

# The tab row takes the place of the rule under the title: each tab stands on its own
# stretch of it
func _build_tabs() -> void:
	var bar := HBoxContainer.new()
	_tab_bar = bar
	bar.add_theme_constant_override("separation", 0)
	var group := ButtonGroup.new()
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i]
		b.theme_type_variation = &"Tab"
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_show_tab.bind(i))
		bar.add_child(b)
		_tab_btns.append(b)
	var rule := $Center/Modal/VBox/Rule
	rule.add_sibling(bar)
	rule.queue_free()

func _build_pages() -> void:
	var grid := $Center/Modal/VBox/Grid as GridContainer   # the scene's rows, dealt out below
	_pages_box = VBoxContainer.new()
	grid.add_sibling(_pages_box)
	for i in TABS.size():
		var g := GridContainer.new()
		g.columns = 2
		g.add_theme_constant_override("h_separation", grid.get_theme_constant("h_separation"))
		g.add_theme_constant_override("v_separation", grid.get_theme_constant("v_separation"))
		_pages_box.add_child(g)
		_pages.append(g)

	# General: language first, so someone who can't read the current one finds it at once
	_target = _pages[GENERAL]
	_build_language_row()
	var pair := _segment_row("Camera", "Follow", "Fixed")
	_follow_cam = pair[0]
	_fixed_cam = pair[1]
	_follow_cam.pressed.connect(_toggle.bind("fixed_camera", false))
	_fixed_cam.pressed.connect(_toggle.bind("fixed_camera", true))
	pair = _segment_row("View", "Wall across", "North up")
	_game_view = pair[0]
	_map_view = pair[1]
	_game_view.pressed.connect(_toggle.bind("turn_to_map", false))
	_map_view.pressed.connect(_toggle.bind("turn_to_map", true))
	_build_hints_row()
	if Telemetry.available():
		_build_stats_row()

	_target = _pages[DISPLAY]
	_move_row(_windowed.get_parent())
	if OS.has_feature("pc") and not Mobile.enabled():
		_build_window_row()
	_move_row(_vsync_on.get_parent())
	_build_graphics_rows()
	_move_row(_shake_on.get_parent())

	_target = _pages[AUDIO]
	for slider: HSlider in [_volume, _music, _sfx, _voice]:
		_move_row(slider.get_parent())

	_target = _pages[CONTROLS]
	pair = _segment_row("Rumble", "On", "Off")
	_rumble_on = pair[0]
	_rumble_off = pair[1]
	_rumble_on.pressed.connect(_toggle.bind("rumble", true))
	_rumble_off.pressed.connect(_toggle.bind("rumble", false))
	_build_key_rows()

	_target = _pages[EXPERIMENTAL]
	_build_experimental_rows()

	grid.queue_free()

## Moves one of the scene's rows (its label, then `control`) onto the page being built
func _move_row(control: Control) -> void:
	var label := control.get_parent().get_child(control.get_index() - 1)
	label.reparent(_target, false)
	control.reparent(_target, false)

func _show_tab(i: int) -> void:
	_tab = i
	_listening = ""
	for k in _pages.size():
		# Phones stack every page in the sheet's scroll; Controls is pad / keyboard only
		_pages[k].visible = k != CONTROLS if Mobile.enabled() else k == i
	_tab_btns[i].button_pressed = true   # unpresses the rest of the group; `pressed` stays quiet
	_reset.visible = i == CONTROLS
	if i == CONTROLS:
		_refresh_keys()

## A small section heading across the page's label column
func _heading(text: String) -> void:
	var h := Label.new()
	h.text = text
	h.theme_type_variation = &"Eyebrow"
	_target.add_child(h)
	_target.add_child(Control.new())

## A caption under the row above, in the controls' column
func _note_row(text: String) -> void:
	_add_label("")
	var note := Label.new()
	note.theme_type_variation = &"Caption"
	note.text = text
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A wrapped label sizes its height from its width; on a hidden page nothing lays it
	# out, so give it the column's width up front or it measures one word per line
	note.custom_minimum_size.x = CONTROL_W
	note.size.x = CONTROL_W
	_target.add_child(note)

# First-day hints (FirstSteps): turning them on shows every one again
func _build_hints_row() -> void:
	var pair := _segment_row("Hints", "On", "Off")
	_hints_on = pair[0]
	_hints_off = pair[1]
	_hints_on.pressed.connect(func():
		Settings.learned.clear()
		_toggle("hints", true))
	_hints_off.pressed.connect(_toggle.bind("hints", false))
	_note_row("A tag over your next job until you have done it once. Turning them on shows them all again.")

# Anonymous play stats (Telemetry), web only: where a game stops and how smoothly it ran
func _build_stats_row() -> void:
	_heading("Privacy")
	var pair := _segment_row("Play stats", "On", "Off")
	_stats_on = pair[0]
	_stats_off = pair[1]
	_stats_on.pressed.connect(_toggle.bind("share_stats", true))
	_stats_off.pressed.connect(_toggle.bind("share_stats", false))
	_note_row("Anonymous: where a game stops and how it runs. No name, no account, nothing kept on your device.")

# Ideas being tried with playtesters (GDD §5.21): the host's pick rules
func _build_experimental_rows() -> void:
	# Solo (the default): on when one person plays, with or without bots
	_forecast_btns = _choice_row("Wave forecast", ["Off", "Solo", "Always"], 100)
	for i in _forecast_btns.size():
		_forecast_btns[i].pressed.connect(func():
			Settings.exp_forecast = i
			Settings.save())
	for row: Array in EXPERIMENTS:
		var pair := _segment_row(row[1], "Off", "On")
		_exp_btns[row[0]] = pair
		pair[0].pressed.connect(_toggle.bind(row[0], false))
		pair[1].pressed.connect(_toggle.bind(row[0], true))
	_note_row("Host's choice. Ideas on trial.")

# Keyboard / mouse rebinds, a row per action; Reset sits in the footer while this tab is open
func _build_key_rows() -> void:
	_heading("Keys")
	for row: Array in KEY_ROWS:
		_add_label(row[1])
		var btn := Button.new()
		btn.theme_type_variation = &"Segment"
		btn.pressed.connect(_listen.bind(row[0]))
		_target.add_child(btn)
		_key_buttons[row[0]] = btn
	_refresh_keys()   # an empty button is shorter: label them now, so the page measures true
	_note_row("Controllers: remap buttons in Steam Input.")
	_reset = Button.new()
	_reset.text = "Reset keys"
	_reset.theme_type_variation = &"GhostButton"
	_reset.pressed.connect(func():
		_listening = ""
		Settings.reset_bindings()
		InputMode.bindings_changed()
		_refresh_keys())
	_done.add_sibling(_reset)
	_done.get_parent().move_child(_reset, 0)

func _build_window_row() -> void:
	_add_label("Window size")
	_window_size = OptionButton.new()
	_window_size.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_window_size.get_popup().auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_window_size.item_selected.connect(func(i: int):
		Settings.window_size = _window_sizes[i]
		Settings.apply()
		Settings.save())
	_target.add_child(_window_size)

# Sizes that fit this screen; "Current" stands for a window the player sized by hand.
# A picked size only takes effect windowed, so the row is greyed in fullscreen.
func _select_window_size() -> void:
	_window_size.clear()
	_window_sizes = Settings.available_window_sizes()
	var cur := DisplayServer.window_get_size() if not Settings.fullscreen else Settings.window_size
	var sel := -1
	for i in _window_sizes.size():
		_window_size.add_item("%d × %d" % [_window_sizes[i].x, _window_sizes[i].y])
		if _window_sizes[i] == cur:
			sel = i
	if sel == -1:
		_window_sizes.append(Vector2i.ZERO)
		_window_size.add_item("%d × %d" % [cur.x, cur.y] if cur != Vector2i.ZERO else "Default")
		sel = _window_sizes.size() - 1
	_window_size.select(sel)
	_window_size.disabled = Settings.fullscreen or not Settings.can_change_window()

func _build_graphics_rows() -> void:
	_quality_btns = _choice_row("Graphics", Settings.QUALITIES.map(func(q): return q["name"]), 110)
	for i in _quality_btns.size():
		_quality_btns[i].pressed.connect(func():
			Settings.quality = i
			_save_graphics())
	if not Settings.can_scale_3d():
		return   # web: the browser's renderer can't scale the 3D view
	_scale_btns = _choice_row("3D resolution",
		Settings.RENDER_SCALES.map(func(s): return "%d%%" % roundi(s * 100.0)), 90)
	for i in _scale_btns.size():
		_scale_btns[i].pressed.connect(func():
			Settings.render_scale = Settings.RENDER_SCALES[i]
			Settings.auto_scale = false
			_save_graphics())

func _save_graphics() -> void:
	Settings.apply()
	Settings.save()

func _select_graphics() -> void:
	for i in _quality_btns.size():
		_quality_btns[i].button_pressed = i == Settings.quality
	# The nearest preset: an auto step-down or an old cfg can leave an in-between value
	var nearest := 0
	for i in Settings.RENDER_SCALES.size():
		if absf(Settings.RENDER_SCALES[i] - Settings.render_scale) \
				< absf(Settings.RENDER_SCALES[nearest] - Settings.render_scale):
			nearest = i
	for i in _scale_btns.size():
		_scale_btns[i].button_pressed = i == nearest

func _build_language_row() -> void:
	_add_label("Language")
	_language = OptionButton.new()
	# Each language keeps its own name, whatever the UI is showing
	_language.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_language.get_popup().auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for row: Array in Settings.LANGUAGES:
		_language.add_item(row[1])
	_language.item_selected.connect(func(i: int):
		Settings.language = Settings.LANGUAGES[i][0]
		Settings.apply()
		Settings.save())
	_target.add_child(_language)

func _select_language() -> void:
	var current := Settings.current_language()
	for i in Settings.LANGUAGES.size():
		if Settings.LANGUAGES[i][0] == current:
			_language.select(i)

func _segment_row(label: String, a: String, b: String) -> Array[Button]:
	return _choice_row(label, [a, b], 150)

func _choice_row(label: String, options: Array, width: int) -> Array[Button]:
	_add_label(label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	_target.add_child(row)
	var group := ButtonGroup.new()
	var out: Array[Button] = []
	for text: String in options:
		var btn := Button.new()
		btn.text = text
		btn.theme_type_variation = &"Segment"
		btn.toggle_mode = true
		btn.button_group = group
		btn.custom_minimum_size = Vector2(width, 0)
		row.add_child(btn)
		out.append(btn)
	return out

func _add_label(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"Body"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target.add_child(l)

func _listen(action: String) -> void:
	_refresh_keys()
	_listening = action
	_key_buttons[action].text = "Press a key…"

func _refresh_keys() -> void:
	for action: String in _key_buttons:
		_key_buttons[action].text = InputMode.key_label(action)
