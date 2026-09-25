extends Control

const GAME_SCENE := "res://scenes/main/main.tscn"
const DRIFT_PX   := 22.0    # slow backdrop pan, each way
const DRIFT_TIME := 16.0
# Phone room-code keypad: the code alphabet (no I/O) in QWERTY order
const KEY_ROWS := ["QWERTYUP", "ASDFGHJKL", "ZXCVBNM"]

@onready var backdrop:      TextureRect = $Backdrop
@onready var column:        Control  = $Content/Column
@onready var menu:          Control  = $Content/Column/Menu
@onready var host_btn:      Button   = $Content/Column/Menu/HostButton
@onready var join_btn:      Button   = $Content/Column/Menu/JoinButton
@onready var settings_btn:  Button   = $Content/Column/Menu/SettingsButton
@onready var quit_btn:      Button   = $Content/Column/Menu/QuitButton
@onready var net_status:    Label    = $Content/Column/NetStatus
@onready var verse:         Control  = $Verse
@onready var join_panel:    Control  = $JoinPanel
@onready var address_input: LineEdit = $JoinPanel/Center/Modal/Content/AddressInput
@onready var connect_btn:   Button   = $JoinPanel/Center/Modal/Content/Footer/ConnectButton
@onready var back_btn:      Button   = $JoinPanel/Center/Modal/Content/Footer/BackButton
@onready var status_label:  Label    = $JoinPanel/Center/Modal/Content/StatusLabel
@onready var settings:      Control  = $SettingsPanel
@onready var fade:          ColorRect = $Fade

var _mobile := false
var _slots: Array[Label] = []
var _code_sheet: Control
var _code_vb: VBoxContainer
var _ip_mode := false
var _last_key_ms := -1000

func _ready() -> void:
	Sfx.play_music("calm")  # back from a finished game, the music may be off
	# Credits sit over bright sand — give them a soft parchment backing
	$Credits.add_theme_stylebox_override("normal", UiStyle.box(Color(UiStyle.PARCHMENT, 0.82), Vector2(12, 6), 3))
	host_btn.pressed.connect(_on_host)
	join_btn.pressed.connect(_on_join)
	settings_btn.pressed.connect(_on_settings)
	quit_btn.pressed.connect(get_tree().quit)
	connect_btn.pressed.connect(_on_connect)
	back_btn.pressed.connect(_on_back)
	address_input.text_submitted.connect(func(_t): _on_connect())
	_mobile = Mobile.enabled()
	if not _mobile:
		settings.closed.connect(settings_btn.grab_focus)
	NetworkManager.lobby_created.connect(_on_lobby_created)
	NetworkManager.lobby_joined.connect(_on_lobby_joined)
	NetworkManager.host_failed.connect(_on_host_failed)
	NetworkManager.online_status_changed.connect(_show_default_status)
	if _mobile:
		_mobile_layout()
	else:
		# Mouse and keyboard share one highlight: hovering an entry focuses it
		for b: Button in menu.get_children():
			b.mouse_entered.connect(b.grab_focus)
	join_panel.hide()
	_show_default_status()
	_intro()

func _unhandled_input(event: InputEvent) -> void:
	if join_panel.visible and _code_sheet and _code_sheet.visible and event is InputEventKey \
			and event.pressed and not event.echo:
		# Hardware keyboard on the phone keypad sheet
		if event.keycode == KEY_BACKSPACE:
			_erase()
			get_viewport().set_input_as_handled()
			return
		var ch := char(event.unicode).to_upper() if event.unicode > 0 else ""
		if ch.length() == 1 and NetworkManager.ROOM_CODE_CHARS.contains(ch):
			_type(ch)
			get_viewport().set_input_as_handled()
			return
	if not event.is_action_pressed("ui_cancel"):
		return
	if join_panel.visible:
		get_viewport().set_input_as_handled()
		_on_back()
	elif _mobile:
		# Android back on the title screen leaves the app, like any root screen
		get_tree().quit()

# ── Presentation ───────────────────────────────────────────

func _intro() -> void:
	fade.show()
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(fade.hide)
	UiFx.stagger(column.get_children().filter(func(c): return c != menu), 0.7, 0.09, 0.25)
	UiFx.stagger(menu.get_children(), 0.45, 0.06, 0.65)
	UiFx.fade_in(verse, 1.0, 1.0)
	if not _mobile:
		host_btn.grab_focus()
	# Backdrop settles from a slight push-in, then drifts
	backdrop.pivot_offset = backdrop.size * 0.5
	backdrop.scale = Vector2.ONE * 1.08
	var settle := create_tween()
	settle.tween_property(backdrop, "scale", Vector2.ONE * 1.035, 2.4) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	settle.tween_callback(_drift)

func _drift() -> void:
	var tw := create_tween().set_loops()
	tw.tween_property(backdrop, "position:x", -DRIFT_PX, DRIFT_TIME).set_trans(Tween.TRANS_SINE)
	tw.tween_property(backdrop, "position:x", DRIFT_PX, DRIFT_TIME * 2.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(backdrop, "position:x", 0.0, DRIFT_TIME).set_trans(Tween.TRANS_SINE)

# ── Network status ─────────────────────────────────────────

# Steam when available; `-- --lan` forces direct IP (e.g. two instances, one PC)
func _use_steam() -> bool:
	return NetworkManager.steam_available() and not OS.get_cmdline_user_args().has("--lan")

# EOS room codes: the default on phones; on PC Steam wins unless `-- --eos`
func _use_eos() -> bool:
	var args := OS.get_cmdline_user_args()
	return NetworkManager.online_available() and not args.has("--lan") 		and (args.has("--eos") or not _use_steam())

func _show_default_status() -> void:
	if host_btn.disabled:
		return  # mid-host: keep the progress/error line
	if _use_eos():
		net_status.text = "Online — host for a room code, or join with one"
	elif _use_steam():
		net_status.text = "Signed in to Steam as %s — invite friends once in game" % NetworkManager.steam_name()
	elif NetworkManager.steam_available():
		net_status.text = "LAN mode — share your IP address to play together"
	elif NetworkManager.online_error().is_empty():
		net_status.text = "Connecting to online services…"
	else:
		net_status.text = "Online unavailable: %s — LAN play only" % NetworkManager.online_error()

# ── Host ───────────────────────────────────────────────────

func _on_host() -> void:
	host_btn.disabled = true
	if _use_eos():
		net_status.text = "Opening a room…"
		NetworkManager.host_online()
	elif _use_steam():
		net_status.text = "Creating Steam lobby…"
		NetworkManager.host_steam()
	else:
		NetworkManager.host()

func _on_host_failed(reason: String) -> void:
	host_btn.disabled = false
	net_status.text = reason

func _on_lobby_created() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)

# ── Join ───────────────────────────────────────────────────

func _on_join() -> void:
	_open_join()

func _open_join() -> void:
	if join_panel.visible:
		return
	join_panel.show()
	UiFx.fade_in(join_panel, 0.18)
	if _code_sheet:
		_set_ip_mode(false)
		address_input.text = ""
		_refresh_slots()
		UiFx.rise_in(_code_sheet.get_child(0), Vector2(0, 24), 0.32)
	else:
		address_input.grab_focus()

func _on_connect() -> void:
	var addr := address_input.text.strip_edges()
	if addr.is_empty():
		status_label.text = "Enter a room code or address first."
		return
	status_label.text = "Connecting…"
	connect_btn.disabled = true
	# 5 letters = EOS room code; Steam lobby ids are 64-bit numbers; else an IP/hostname
	if NetworkManager.is_room_code(addr):
		if not NetworkManager.online_available():
			_join_failed("Online services aren't ready — check your connection.")
			return
		NetworkManager.join_online(addr)
	elif addr.is_valid_int() and addr.length() > 12:
		if not NetworkManager.steam_available():
			_join_failed("That's a Steam lobby code — start Steam first.")
			return
		NetworkManager.join_steam(addr.to_int())
	else:
		NetworkManager.join(addr)

func _on_back() -> void:
	join_panel.hide()
	status_label.text = ""
	connect_btn.disabled = false
	if not _mobile:
		join_btn.grab_focus()

func _on_lobby_joined(success: bool) -> void:
	if success:
		get_tree().change_scene_to_file(GAME_SCENE)
	else:
		var why := NetworkManager.last_error
		_join_failed(why if not why.is_empty() else "Connection failed. Check the address and that the host is running.")

# Panel may be hidden when the join came from a Steam invite, so surface it
func _join_failed(msg: String) -> void:
	_open_join()
	status_label.text = msg
	connect_btn.disabled = false
	if _code_sheet:
		_refresh_slots()
		UiFx.shake(_code_sheet.get_child(0))
		Mobile.haptic(40)

# ── Settings ───────────────────────────────────────────────

func _on_settings() -> void:
	settings.open()

# ── Phone layout ───────────────────────────────────────────

# Title lockup left, two big actions under it (host = filled, join = tonal),
# settings as an icon top-right. No Quit — Android back leaves from here.
func _mobile_layout() -> void:
	var s := Mobile.safe_insets()
	var content := $Content as MarginContainer
	content.add_theme_constant_override("margin_left", int(40 + s.x))
	content.add_theme_constant_override("margin_top", int(20 + s.y))
	content.add_theme_constant_override("margin_right", int(24 + s.z))
	content.add_theme_constant_override("margin_bottom", int(20 + s.w))
	$Content/Column/Eyebrow.add_theme_font_size_override("font_size", 12)
	$Content/Column/SubRow/Subtitle.add_theme_font_size_override("font_size", 22)
	$Content/Column/SubRow/Rule.custom_minimum_size.x = 120
	$Content/Column/MenuGap.custom_minimum_size.y = 22
	$Content/Column/StatusGap.custom_minimum_size.y = 10
	net_status.custom_minimum_size.x = 300
	net_status.add_theme_font_size_override("font_size", 13)

	menu.custom_minimum_size.x = 280
	menu.add_theme_constant_override("separation", 10)
	host_btn.theme_type_variation = &"PrimaryButton"
	host_btn.text = "Host a room"
	join_btn.theme_type_variation = &"GhostButton"
	join_btn.text = "Join with code"
	for b: Button in [host_btn, join_btn]:
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(Mobile.haptic)
	settings_btn.hide()
	quit_btn.hide()
	$Credits.hide()   # lives in Settings › About on phones

	var gear := UiIcons.button("tune", "Settings")
	gear.pressed.connect(_on_settings)
	add_child(gear)
	move_child(gear, verse.get_index())
	gear.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	gear.offset_left = -(48 + 20 + s.z)
	gear.offset_right = -(20 + s.z)
	gear.offset_top = 20 + s.y
	gear.offset_bottom = 68 + s.y

	# Verse: bottom-right, right-aligned over a soft parchment glow from the corner.
	# The art behind it is the wall itself; the glow (like the title-side veil)
	# lifts contrast without boxing the text in.
	var g := Gradient.new()
	g.set_color(0, Color(UiStyle.PARCHMENT, 0.9))
	g.set_color(1, Color(UiStyle.PARCHMENT, 0.0))
	g.add_point(0.5, Color(UiStyle.PARCHMENT, 0.62))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(1, 1)
	tex.fill_to = Vector2(0, 1)
	var glow := TextureRect.new()
	glow.texture = tex
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)
	move_child(glow, verse.get_index())
	glow.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	glow.offset_left = -600
	glow.offset_top = -210
	glow.offset_right = 0
	glow.offset_bottom = 0
	UiFx.fade_in(glow, 1.0, 1.0)

	verse.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	verse.offset_right = -(24 + s.z)
	verse.offset_left = verse.offset_right - 340
	verse.offset_bottom = -(20 + s.w)
	verse.offset_top = verse.offset_bottom - 80
	verse.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	verse.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var text := verse.get_node("Text") as Label
	text.custom_minimum_size.x = 340   # wrap width from the first layout pass
	text.add_theme_font_size_override("font_size", 14)
	for l: Label in [text, verse.get_node("Ref")]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_build_code_sheet()

# Room codes are 5 letters from a 24-letter alphabet, so an in-game keypad beats
# the system keyboard: no IME covering half the landscape screen, no system bars
# popping back, and only valid letters to press. The fifth letter joins.
func _build_code_sheet() -> void:
	_code_sheet = Control.new()
	_code_sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	_code_sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	join_panel.add_child(_code_sheet)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_code_sheet.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Modal"
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	_code_vb = vb

	# Header: back · title · "IP address" escape hatch
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	vb.add_child(head)
	var back := UiIcons.button("back", "Back", 48.0, &"FlatIconButton")
	back.pressed.connect(_on_back)
	head.add_child(back)
	var title := Label.new()
	title.theme_type_variation = &"Heading"
	title.text = "Join a crew"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var ip := Button.new()
	ip.theme_type_variation = &"FlatIconButton"
	ip.text = "IP address"
	ip.focus_mode = Control.FOCUS_NONE
	ip.add_theme_font_override("font", UiStyle.tracked(UiStyle.CINZEL_SEMI, 2))
	ip.add_theme_font_size_override("font_size", 12)
	ip.add_theme_color_override("font_color", UiStyle.INK_MUTED)
	ip.tooltip_text = "Same Wi-Fi, no internet: join by the host's IP"
	ip.pressed.connect(_set_ip_mode.bind(true))
	head.add_child(ip)

	# Five letter tiles
	var slots := HBoxContainer.new()
	slots.alignment = BoxContainer.ALIGNMENT_CENTER
	slots.add_theme_constant_override("separation", 10)
	vb.add_child(slots)
	for i in NetworkManager.ROOM_CODE_LEN:
		var l := Label.new()
		l.custom_minimum_size = Vector2(52, 58)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_override("font", UiStyle.CINZEL_XBOLD)
		l.add_theme_font_size_override("font_size", 28)
		l.add_theme_color_override("font_color", UiStyle.INK)
		slots.add_child(l)
		_slots.append(l)

	status_label.reparent(vb)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.custom_minimum_size = Vector2(0, 20)
	status_label.add_theme_font_size_override("font_size", 14)

	# Keypad
	var pad := VBoxContainer.new()
	pad.add_theme_constant_override("separation", 6)
	vb.add_child(pad)
	var key_n := UiStyle.bordered(UiStyle.box(Color(UiStyle.CREAM, 0.95), Vector2(4, 10), 5), Color(UiStyle.RULE, 0.8), 1, 3)
	var key_p := UiStyle.bordered(UiStyle.box(UiStyle.PARCHMENT_DEEP, Vector2(4, 10), 5), UiStyle.TERRACOTTA, 1, 1)
	for r: int in KEY_ROWS.size():
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 6)
		pad.add_child(row)
		for ch: String in KEY_ROWS[r]:
			row.add_child(_key(ch, key_n, key_p, _type.bind(ch)))
		if r == KEY_ROWS.size() - 1:
			var del := _key("", key_n, key_p, _erase)
			del.icon = UiIcons.get_icon("backspace", 22)
			del.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			del.custom_minimum_size.x = 84
			for c: String in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color"]:
				del.add_theme_color_override(c, UiStyle.INK_SOFT)
			row.add_child(del)

func _key(ch: String, normal: StyleBox, pressed: StyleBox, action: Callable) -> Button:
	var b := Button.new()
	b.text = ch
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(54, 48)
	b.add_theme_font_override("font", UiStyle.CINZEL_BOLD)
	b.add_theme_font_size_override("font_size", 19)
	for c: String in ["font_color", "font_hover_color", "font_focus_color"]:
		b.add_theme_color_override(c, UiStyle.INK)
	for c: String in ["font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, UiStyle.TERRACOTTA_DEEP)
	for st: String in ["normal", "hover", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, normal)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.pressed.connect(func():
		# One tap can arrive twice on Android (touch + emulated mouse): drop the echo
		var now := Time.get_ticks_msec()
		if now - _last_key_ms < 90:
			return
		_last_key_ms = now
		Mobile.haptic(8)
		action.call())
	return b

func _type(ch: String) -> void:
	if connect_btn.disabled or address_input.text.length() >= NetworkManager.ROOM_CODE_LEN:
		return
	address_input.text += ch
	status_label.text = ""
	_refresh_slots()
	if NetworkManager.is_room_code(address_input.text):
		_on_connect()

func _erase() -> void:
	if connect_btn.disabled:
		return
	address_input.text = address_input.text.left(-1)
	status_label.text = ""
	_refresh_slots()

# Filled tiles are ink on cream; the next empty one wears the terracotta cursor
func _refresh_slots() -> void:
	var code := address_input.text
	for i in _slots.size():
		var l := _slots[i]
		l.text = code[i] if i < code.length() else ""
		var next := i == code.length()
		var sb := UiStyle.bordered(UiStyle.box(Color(UiStyle.CREAM, 0.95 if i < code.length() else 0.6), Vector2.ZERO, 6),
			UiStyle.TERRACOTTA if next else Color(UiStyle.RULE, 0.9), 2 if next else 1, 3 if next else 2)
		l.add_theme_stylebox_override("normal", sb)

# Fallback: the original form with the system keyboard, pinned to the top half so
# the keyboard doesn't cover it
func _set_ip_mode(on: bool) -> void:
	_ip_mode = on
	_code_sheet.visible = not on
	var center := $JoinPanel/Center as Control
	center.visible = on
	if on:
		center.anchor_bottom = 0.6
		address_input.text = ""
		address_input.placeholder_text = "e.g. 192.168.1.20"
		$JoinPanel/Center/Modal/Content/Hint.hide()
		$JoinPanel/Center/Modal.custom_minimum_size.x = 480
		status_label.reparent($JoinPanel/Center/Modal/Content)
		$JoinPanel/Center/Modal/Content.move_child(status_label, address_input.get_index() + 1)
		address_input.grab_focus()
	elif status_label.get_parent() != _code_vb:
		status_label.reparent(_code_vb)
		_code_vb.move_child(status_label, 2)
