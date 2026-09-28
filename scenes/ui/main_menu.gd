extends Control

const GAME_SCENE := "res://scenes/main/main.tscn"
const DRIFT_PX     := 22.0   # slow backdrop pan, each way
const DRIFT_PERIOD := 64.0   # seconds for a full left-right-left sweep
const PUSH_IN_ZOOM := 1.08
const REST_ZOOM    := 1.035  # margin must cover DRIFT_PX at the edges
const SETTLE_TIME  := 2.4
# Live backdrop: the real game, played by bots (GameState.attract). The painting shows
# until the world has settled, then fades off it; it's also the fallback.
const WORLD_SETTLE  := 2.5   # nav bake, crew posed, dust down
const WORLD_FADE    := 1.8
const WORLD_RESTART := 5.0   # after the crew wins or falls, a breath before a fresh run

var _rig: Node2D
var _drift_t := 0.0
var _picker: SectionPicker
var _folk: FriendsAndFoes
var _folk_btn: Button
var _credits: CreditsRoll
var _credits_btn: Button
var _sections_btn: Button
# Phone room-code keypad: the code alphabet (no I/O) in QWERTY order
const KEY_ROWS := ["QWERTYUP", "ASDFGHJKL", "ZXCVBNM"]
var _world: Node3D
var _world_tween: Tween

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
	# Hug the text: a right-aligned label keeps its box, so size it to one line
	$Credits.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	$Credits.size = $Credits.get_combined_minimum_size()
	$Credits.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_KEEP_SIZE, 32)
	host_btn.pressed.connect(_on_host)
	# Replay map: an entry under Host, and the picker over everything
	_sections_btn = join_btn.duplicate()
	_sections_btn.name = "SectionsButton"
	_sections_btn.text = "Choose a Section"
	menu.add_child(_sections_btn)
	menu.move_child(_sections_btn, host_btn.get_index() + 1)
	_sections_btn.pressed.connect(_open_picker)
	_picker = SectionPicker.new()
	add_child(_picker)
	move_child(_picker, fade.get_index())
	_picker.chosen.connect(_on_section_chosen)
	_picker.closed.connect(_sections_btn.grab_focus)
	# Friends and Foes: an entry under the sections, the page over everything
	_folk_btn = join_btn.duplicate()
	_folk_btn.name = "FolkButton"
	_folk_btn.text = "Friends and Foes"
	menu.add_child(_folk_btn)
	menu.move_child(_folk_btn, _sections_btn.get_index() + 1)
	_folk = FriendsAndFoes.new()
	add_child(_folk)
	move_child(_folk, fade.get_index())
	_folk_btn.pressed.connect(_folk.open)
	_folk.closed.connect(_folk_btn.grab_focus)
	# Credits: an entry above Quit; the roll plays over the menu
	_credits_btn = join_btn.duplicate()
	_credits_btn.name = "CreditsButton"
	_credits_btn.text = "Credits"
	menu.add_child(_credits_btn)
	menu.move_child(_credits_btn, quit_btn.get_index())
	_credits = CreditsRoll.new()
	add_child(_credits)
	_credits_btn.pressed.connect(_credits.play)
	_credits.finished.connect(_credits_btn.grab_focus)
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
	# Back from a replay: straight to the map, on the stretch just played
	GameState.replay_section = -1
	if GameState.picker_return >= 0:
		_picker.open(GameState.picker_return)
		GameState.picker_return = -1
	GameState.game_won.connect(_on_world_over)
	GameState.game_lost.connect(_on_world_over)
	_start_world()

func _exit_tree() -> void:
	GameState.attract = false

# Language picked in Settings: redo the one line built from a format string
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and not host_btn.disabled:
		_show_default_status()

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
	# Backdrop moves on a Node2D rig: Control positions snap to whole pixels
	# (gui/common/snap_controls_to_pixels), which turned a ~2px/s drift into
	# visible one-pixel hops. Node2D transforms stay sub-pixel.
	_rig = Node2D.new()
	add_child(_rig)
	move_child(_rig, backdrop.get_index())
	backdrop.reparent(_rig, false)
	backdrop.set_anchors_preset(Control.PRESET_TOP_LEFT)
	resized.connect(_layout_backdrop)
	_layout_backdrop()
	_animate_backdrop(0.0)

func _layout_backdrop() -> void:
	_rig.position = size * 0.5  # scale about screen centre
	backdrop.position = -size * 0.5
	backdrop.size = size

# Push-in settles while one continuous sine drifts — no stops mid-sweep
func _animate_backdrop(t: float) -> void:
	var k := minf(t / SETTLE_TIME, 1.0)
	var settle := 1.0 - pow(1.0 - k, 4.0)  # quart ease-out
	_rig.scale = Vector2.ONE * lerpf(PUSH_IN_ZOOM, REST_ZOOM, settle)
	_rig.position.x = size.x * 0.5 - sin(t * TAU / DRIFT_PERIOD) * DRIFT_PX

func _process(delta: float) -> void:
	if not backdrop.visible:
		return
	_drift_t += delta
	_animate_backdrop(_drift_t)

# ── Live world ─────────────────────────────────────────────

func _start_world() -> void:
	GameState.attract = true
	_world = load(GAME_SCENE).instantiate()
	add_child(_world)
	move_child(_world, 0)   # 3D draws under every Control anyway; keep the tree honest
	var world := _world
	await get_tree().create_timer(WORLD_SETTLE).timeout
	if world == _world and GameState.attract:
		_fade_backdrop(0.0, WORLD_FADE)

func _fade_backdrop(to: float, time: float) -> Tween:
	if _world_tween:
		_world_tween.kill()
	backdrop.show()
	_world_tween = create_tween()
	_world_tween.tween_property(backdrop, "modulate:a", to, time) 		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if to == 0.0:
		_world_tween.tween_callback(backdrop.hide)
	return _world_tween

# The crew finished the wall or was overrun: the painting covers a fresh start
func _on_world_over() -> void:
	if not GameState.attract:
		return
	var world := _world
	await get_tree().create_timer(WORLD_RESTART).timeout
	if world == _world and GameState.attract:
		_restart_world()

func _restart_world() -> void:
	await _fade_backdrop(1.0, 0.8).finished
	if _world:
		_world.queue_free()
		_world = null
	_start_world()

# A real game is starting: hold the world still and hand GameState back clean
func _stop_world() -> void:
	if not GameState.attract:
		return
	GameState.attract = false
	if _world:
		_world.process_mode = Node.PROCESS_MODE_DISABLED
	GameState.reset()

# Hosting or joining fell through: back to a fresh live world
func _resume_world() -> void:
	if not GameState.attract and is_inside_tree():
		GameState.attract = true
		_restart_world()

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
		net_status.text = tr("Signed in to Steam as %s — invite friends once in game") % NetworkManager.steam_name()
	elif NetworkManager.steam_available():
		net_status.text = "LAN mode — share your IP address to play together"
	elif NetworkManager.online_error().is_empty():
		net_status.text = "Connecting to online services…"
	else:
		net_status.text = "Online unavailable: %s — LAN play only" % NetworkManager.online_error()

# ── Host ───────────────────────────────────────────────────

func _on_host() -> void:
	GameState.replay_section = -1
	_host()

# Opens on the furthest stretch this player may build
func _open_picker() -> void:
	var last := 0
	for i in GameState.SECTIONS.size():
		if GameState.is_unlocked(i):
			last = i
	_picker.open(last)

## Host a game of just one section (the others' marks don't change)
func _on_section_chosen(section_index: int) -> void:
	GameState.replay_section = section_index
	GameState.picker_return = section_index
	_host()

func _host() -> void:
	_stop_world()
	host_btn.disabled = true
	_sections_btn.disabled = true
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
	_sections_btn.disabled = false
	net_status.text = reason
	_resume_world()

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
		_fill_friend_games()

# Friends already playing: one button each, focused first — no code to type
func _fill_friend_games() -> void:
	var content := $JoinPanel/Center/Modal/Content
	var box: VBoxContainer = content.get_node_or_null("FriendGames")
	if box == null:
		box = VBoxContainer.new()
		box.name = "FriendGames"
		box.add_theme_constant_override("separation", 8)
		content.add_child(box)
		content.move_child(box, content.get_node("FieldGap").get_index())
	for c in box.get_children():
		c.queue_free()
	var games: Array[Dictionary] = []
	if _use_steam():
		games = NetworkManager.friend_lobbies()
	if games.is_empty():
		address_input.grab_focus()
		return
	var head := Label.new()
	head.theme_type_variation = &"Eyebrow"
	head.text = "Friends building now"
	box.add_child(head)
	var first: Button = null
	for g: Dictionary in games:
		var b := Button.new()
		b.theme_type_variation = &"PrimaryButton" if first == null else &"GhostButton"
		b.text = tr("Join %s") % g.name
		b.pressed.connect(func():
			status_label.text = tr("Joining %s…") % g.name
			_stop_world()
			NetworkManager.join_steam(g.lobby))
		box.add_child(b)
		if first == null:
			first = b
	first.grab_focus()

func _on_connect() -> void:
	var addr := address_input.text.strip_edges()
	if addr.is_empty():
		status_label.text = "Enter a room code or address first."
		return
	status_label.text = "Connecting…"
	connect_btn.disabled = true
	_stop_world()
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
		_stop_world()   # a Steam invite joins straight from the menu
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
	_resume_world()

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
	$Content/Column/MenuGap.custom_minimum_size.y = 14
	$Content/Column/StatusGap.custom_minimum_size.y = 10
	net_status.custom_minimum_size.x = 300
	net_status.add_theme_font_size_override("font_size", 13)

	menu.custom_minimum_size.x = 280
	host_btn.theme_type_variation = &"PrimaryButton"
	host_btn.text = "Host a room"
	join_btn.theme_type_variation = &"GhostButton"
	join_btn.text = "Join with code"
	_sections_btn.theme_type_variation = &"GhostButton"
	_sections_btn.text = "Choose a section"
	menu.add_theme_constant_override("separation", 8)
	for b: Button in [host_btn, _sections_btn, join_btn]:
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
