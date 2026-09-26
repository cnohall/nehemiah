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
]

var _rumble_on: Button
var _rumble_off: Button
var _hold: Button
var _toggle_mode: Button
var _keys_btn: Button
var _keys_page: VBoxContainer
var _key_buttons := {}      # action → Button
var _reset: Button
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
	_build_keys_page()

func open() -> void:
	_windowed.button_pressed   = not Settings.fullscreen
	_fullscreen.button_pressed = Settings.fullscreen
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
	_rumble_on.button_pressed    = Settings.rumble
	_rumble_off.button_pressed   = not Settings.rumble
	_hold.button_pressed         = not Settings.toggle_charge
	_toggle_mode.button_pressed  = Settings.toggle_charge
	_show_keys(false)
	show()
	UiFx.fade_in(self, 0.18)
	(_fullscreen if Settings.fullscreen else _windowed).grab_focus()

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
	pair = _segment_row("Sling", "Hold", "Toggle")
	_hold = pair[0]
	_toggle_mode = pair[1]
	_hold.pressed.connect(_set_charge_mode.bind(false))
	_toggle_mode.pressed.connect(_set_charge_mode.bind(true))
	_add_label("Keys")
	_keys_btn = Button.new()
	_keys_btn.text = "Rebind keys…"
	_keys_btn.theme_type_variation = &"GhostButton"
	_keys_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_keys_btn.pressed.connect(_show_keys.bind(true))
	_grid.add_child(_keys_btn)

func _segment_row(label: String, a: String, b: String) -> Array[Button]:
	_add_label(label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	_grid.add_child(row)
	var group := ButtonGroup.new()
	var out: Array[Button] = []
	for text in [a, b]:
		var btn := Button.new()
		btn.text = text
		btn.theme_type_variation = &"Segment"
		btn.toggle_mode = true
		btn.button_group = group
		btn.custom_minimum_size = Vector2(150, 0)
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
