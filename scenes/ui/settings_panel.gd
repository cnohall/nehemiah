extends Control

# Modal settings sheet, shared by the title screen and the in-game menu.
# Writes straight through to the Settings autoload; Esc / Done closes.
# A second page, "Keys", rebinds the keyboard / mouse (built in code).

signal closed

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
@onready var _done:       Button = %Done
@onready var _grid:       GridContainer = $Center/Modal/VBox/Grid
@onready var _title:      Label = $Center/Modal/VBox/Header/Title

const KEY_ROWS := [
	["move_north", "Move up"], ["move_west", "Move left"],
	["move_south", "Move down"], ["move_east", "Move right"],
	["interact", "Pick up · deliver · build"], ["drop", "Drop"],
	["dash", "Dash"], ["throw_charge", "Sling"], ["horn", "Horn"],
	["reveal", "What can I do here?"],
]

var _rumble_on: Button
var _world_hud: Button
var _plaque_hud: Button
var _follow_cam: Button
var _fixed_cam: Button
var _game_view: Button
var _map_view: Button
var _rumble_off: Button
var _hold: Button
var _toggle_mode: Button
var _keys_btn: Button
var _keys_page: VBoxContainer
var _key_buttons := {}      # action → Button
var _reset: Button
var _language: OptionButton
var _window_size: OptionButton
var _window_sizes: Array[Vector2i] = []
var _quality_btns: Array[Button] = []
var _scale_btns: Array[Button] = []
var _style_btns: Array[Button] = []
var _listening := ""        # action waiting for a key press, or ""

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
	_done.pressed.connect(close)
	_build_extra_rows()
	_even_rows()
	_build_keys_page()
	resized.connect(func(): if visible: _fit_modal.call_deferred())

# Every control spans the same width (the widest row's), and a row's choices share it
# evenly — rows of their own natural widths made a ragged right edge
func _even_rows() -> void:
	for i in range(1, _grid.get_child_count(), _grid.columns):
		var c := _grid.get_child(i) as Control
		c.size_flags_horizontal = Control.SIZE_FILL
		if c is HBoxContainer:
			for k in c.get_children():
				if k is Button or k is Slider:
					(k as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL

# The sheet is about 1070 px tall and the UI is boosted in small windows (Settings._fit_ui),
# so a 1280×720 window would clip it: shrink it around its centre until it fits.
func _fit_modal() -> void:
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
	_select_language()
	_select_graphics()
	if _window_size != null:
		_select_window_size()
	_rumble_on.button_pressed    = Settings.rumble
	_rumble_off.button_pressed   = not Settings.rumble
	_world_hud.button_pressed    = Settings.diegetic_hud
	_plaque_hud.button_pressed   = not Settings.diegetic_hud
	_follow_cam.button_pressed   = not Settings.fixed_camera
	_fixed_cam.button_pressed    = Settings.fixed_camera
	_game_view.button_pressed    = not Settings.turn_to_map
	_map_view.button_pressed     = Settings.turn_to_map
	_hold.button_pressed         = not Settings.toggle_charge
	_toggle_mode.button_pressed  = Settings.toggle_charge
	_show_keys(false)
	show()
	_fit_modal.call_deferred()   # after the rows above have laid out
	UiFx.fade_in(self, 0.18)
	_language.grab_focus()

func close() -> void:
	_listening = ""
	Settings.save()
	hide()
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _keys_page.visible:
			_show_keys(false)
		else:
			close()

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

# ── Extra rows / keys page ─────────────────────────────────

func _build_extra_rows() -> void:
	var pair := _segment_row("Rumble", "On", "Off")
	_rumble_on = pair[0]
	_rumble_off = pair[1]
	_rumble_on.pressed.connect(_toggle.bind("rumble", true))
	_rumble_off.pressed.connect(_toggle.bind("rumble", false))
	pair = _segment_row("Day info", "In the world", "Plaques")
	_world_hud = pair[0]
	_plaque_hud = pair[1]
	_world_hud.pressed.connect(_toggle.bind("diegetic_hud", true))
	_plaque_hud.pressed.connect(_toggle.bind("diegetic_hud", false))
	pair = _segment_row("Camera", "Follow", "Fixed")
	_follow_cam = pair[0]
	_fixed_cam = pair[1]
	_follow_cam.pressed.connect(_toggle.bind("fixed_camera", false))
	_fixed_cam.pressed.connect(_toggle.bind("fixed_camera", true))
	pair = _segment_row("View", "Wall across", "North up")
	_game_view = pair[0]
	_map_view = pair[1]
	_game_view.pressed.connect(_toggle.bind("turn_to_map", false))
	_map_view.pressed.connect(_toggle.bind("turn_to_map", true))
	pair = _segment_row("Sling", "Hold", "Toggle")
	_hold = pair[0]
	_toggle_mode = pair[1]
	_hold.pressed.connect(_set_charge_mode.bind(false))
	_toggle_mode.pressed.connect(_set_charge_mode.bind(true))
	_build_graphics_rows()
	if OS.has_feature("pc"):
		_build_window_row()
	_add_label("Keys")
	_keys_btn = Button.new()
	_keys_btn.text = "Rebind keys…"
	_keys_btn.theme_type_variation = &"GhostButton"
	_keys_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_keys_btn.pressed.connect(_show_keys.bind(true))
	_grid.add_child(_keys_btn)
	_build_language_row()

func _build_window_row() -> void:
	_add_label("Window size")
	_window_size = OptionButton.new()
	_window_size.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_window_size.get_popup().auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_window_size.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_window_size.custom_minimum_size = Vector2(300, 0)
	_window_size.item_selected.connect(func(i: int):
		Settings.window_size = _window_sizes[i]
		Settings.apply()
		Settings.save())
	_grid.add_child(_window_size)
	# Directly under Display (the grid's first row; the language row is put ahead of it later)
	_grid.move_child(_grid.get_child(_grid.get_child_count() - 2), 2)
	_grid.move_child(_window_size, 3)

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
	# Trying out drawn looks with playtesters; switches live under the open panel
	_style_btns = _choice_row("Art style", Settings.ART_STYLES, 110)
	for i in _style_btns.size():
		_style_btns[i].pressed.connect(func():
			Settings.art_style = i
			Settings.save())
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
	for i in _style_btns.size():
		_style_btns[i].button_pressed = i == Settings.art_style
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

# Language sits first: someone who can't read the current one should find it at once
func _build_language_row() -> void:
	_add_label("Language")
	_language = OptionButton.new()
	# Each language keeps its own name, whatever the UI is showing
	_language.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_language.get_popup().auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_language.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_language.custom_minimum_size = Vector2(300, 0)
	for row: Array in Settings.LANGUAGES:
		_language.add_item(row[1])
	_language.item_selected.connect(func(i: int):
		Settings.language = Settings.LANGUAGES[i][0]
		Settings.apply()
		Settings.save())
	_grid.add_child(_language)
	var label := _grid.get_child(_grid.get_child_count() - 2)
	_grid.move_child(label, 0)
	_grid.move_child(_language, 1)

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
	_grid.add_child(row)
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
	_grid.add_child(l)

func _set_charge_mode(toggle: bool) -> void:
	_toggle("toggle_charge", toggle)
	InputMode.bindings_changed()   # "Hold RT" ↔ "RT" in the hints

func _build_keys_page() -> void:
	_keys_page = VBoxContainer.new()
	_keys_page.add_theme_constant_override("separation", 22)
	_keys_page.visible = false
	_grid.add_sibling(_keys_page)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 14)
	_keys_page.add_child(grid)
	for row: Array in KEY_ROWS:
		var l := Label.new()
		l.text = row[1]
		l.theme_type_variation = &"Body"
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(l)
		var btn := Button.new()
		btn.theme_type_variation = &"Segment"
		btn.custom_minimum_size = Vector2(200, 0)
		btn.pressed.connect(_listen.bind(row[0]))
		grid.add_child(btn)
		_key_buttons[row[0]] = btn
	var note := Label.new()
	note.theme_type_variation = &"Caption"
	note.text = "Controllers: remap buttons in Steam Input."
	_keys_page.add_child(note)
	_reset = Button.new()
	_reset.text = "Reset to defaults"
	_reset.theme_type_variation = &"GhostButton"
	_reset.pressed.connect(func():
		_listening = ""
		Settings.reset_bindings()
		InputMode.bindings_changed()
		_refresh_keys())
	_done.add_sibling(_reset)
	_done.get_parent().move_child(_reset, 0)

func _show_keys(on: bool) -> void:
	_listening = ""
	_grid.visible = not on
	_keys_page.visible = on
	_reset.visible = on
	if visible:
		_fit_modal.call_deferred()   # the keys page is shorter than the settings grid
	_title.text = "Keys" if on else "Settings"
	_done.text = "Back" if on else "Done"
	if _done.pressed.is_connected(close) == on:
		if on:
			_done.pressed.disconnect(close)
			_done.pressed.connect(_show_keys.bind(false))
		else:
			_done.pressed.disconnect(_show_keys)
			_done.pressed.connect(close)
	if on:
		_refresh_keys()
		_key_buttons[KEY_ROWS[0][0]].grab_focus()
	elif visible:
		_keys_btn.grab_focus()

func _listen(action: String) -> void:
	_refresh_keys()
	_listening = action
	_key_buttons[action].text = "Press a key…"

func _refresh_keys() -> void:
	for action: String in _key_buttons:
		_key_buttons[action].text = InputMode.key_label(action)
