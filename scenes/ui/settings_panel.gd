extends Control

# Modal settings sheet, shared by the title screen and the in-game menu.
# Writes straight through to the Settings autoload; Esc / Done closes.
# Phones: a full-height side sheet from the right (Material side sheet) with audio
# only — no window/vsync choices — plus the credits; tap outside or back closes.

signal closed

const SHEET_WIDTH := 380.0
const CREDITS := "Music: “The Desert of Dreams” by insydnis (CC-BY 3.0) · “Desert theme” by yd (CC0)\nSound effects: Kenney.nl (CC0)"

@onready var _windowed:   Button = %Windowed
@onready var _fullscreen: Button = %Fullscreen
@onready var _vsync_on:   Button = %VsyncOn
@onready var _vsync_off:  Button = %VsyncOff
@onready var _volume:     HSlider = %Volume
@onready var _volume_val: Label  = %VolumeValue
@onready var _music:      HSlider = %Music
@onready var _music_val:  Label  = %MusicValue
@onready var _sfx:        HSlider = %Sfx
@onready var _sfx_val:    Label  = %SfxValue
@onready var _done:       Button = %Done
@onready var _modal:      PanelContainer = $Center/Modal

var _sheet_tween: Tween

func _ready() -> void:
	hide()
	_windowed.pressed.connect(_toggle.bind("fullscreen", false))
	_fullscreen.pressed.connect(_toggle.bind("fullscreen", true))
	_vsync_on.pressed.connect(_toggle.bind("vsync", true))
	_vsync_off.pressed.connect(_toggle.bind("vsync", false))
	_volume.value_changed.connect(_on_volume)
	_volume.drag_ended.connect(func(_changed): Settings.save())
	_music.value_changed.connect(_on_music)
	_music.drag_ended.connect(func(_changed): Settings.save())
	_sfx.value_changed.connect(_on_sfx)
	_sfx.drag_ended.connect(func(_changed): Settings.save())
	_done.pressed.connect(close)
	if Mobile.enabled():
		_build_side_sheet()

func open() -> void:
	_windowed.button_pressed   = not Settings.fullscreen
	_fullscreen.button_pressed = Settings.fullscreen
	_vsync_on.button_pressed   = Settings.vsync
	_vsync_off.button_pressed  = not Settings.vsync
	_volume.set_value_no_signal(Settings.volume * 100.0)
	_volume_val.text = "%d%%" % roundi(_volume.value)
	_music.set_value_no_signal(Settings.music_volume * 100.0)
	_music_val.text = "%d%%" % roundi(_music.value)
	_sfx.set_value_no_signal(Settings.sfx_volume * 100.0)
	_sfx_val.text = "%d%%" % roundi(_sfx.value)
	show()
	UiFx.fade_in(self, 0.18)
	if Mobile.enabled():
		_slide_in()
	else:
		(_fullscreen if Settings.fullscreen else _windowed).grab_focus()

func close() -> void:
	Settings.save()
	hide()
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

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

	# Audio only: phones are always fullscreen and vsync'd
	for n in ["DisplayLabel", "DisplayRow", "VsyncLabel", "VsyncRow"]:
		vbox.get_node("Grid/" + n).hide()
	var grid := vbox.get_node("Grid") as GridContainer
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 4)
	for slider: HSlider in [_volume, _music, _sfx]:
		slider.custom_minimum_size = Vector2(150, 48)   # the whole row is the target
	_done.get_parent().hide()

	# Credits, moved off the title screen
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)
	var about := Label.new()
	about.theme_type_variation = &"Eyebrow"
	about.text = "About"
	vbox.add_child(about)
	var credits := Label.new()
	credits.theme_type_variation = &"Caption"
	credits.add_theme_font_size_override("font_size", 13)
	credits.text = CREDITS
	credits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credits.custom_minimum_size.x = SHEET_WIDTH - 48.0   # a wrap width from the start
	vbox.add_child(credits)

	# Tap outside the sheet closes it
	$Scrim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			close())

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
