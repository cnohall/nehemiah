extends Control

const GAME_SCENE := "res://scenes/main/main.tscn"
const DRIFT_PX   := 22.0    # slow backdrop pan, each way
const DRIFT_TIME := 16.0

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
	settings.closed.connect(settings_btn.grab_focus)
	NetworkManager.lobby_created.connect(_on_lobby_created)
	NetworkManager.lobby_joined.connect(_on_lobby_joined)
	NetworkManager.host_failed.connect(_on_host_failed)
	NetworkManager.online_status_changed.connect(_show_default_status)
	# Mouse and keyboard share one highlight: hovering an entry focuses it
	for b: Button in menu.get_children():
		b.mouse_entered.connect(b.grab_focus)
	join_panel.hide()
	_show_default_status()
	_intro()

func _unhandled_input(event: InputEvent) -> void:
	if join_panel.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back()

# ── Presentation ───────────────────────────────────────────

func _intro() -> void:
	fade.show()
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(fade.hide)
	UiFx.stagger(column.get_children().filter(func(c): return c != menu), 0.7, 0.09, 0.25)
	UiFx.stagger(menu.get_children(), 0.45, 0.06, 0.65)
	UiFx.fade_in(verse, 1.0, 1.0)
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

# ── Settings ───────────────────────────────────────────────

func _on_settings() -> void:
	settings.open()
