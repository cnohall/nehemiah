extends Control

const GAME_SCENE := "res://scenes/main/main.tscn"
const DRIFT_PX     := 22.0   # slow backdrop pan, each way
const DRIFT_PERIOD := 64.0   # seconds for a full left-right-left sweep
const PUSH_IN_ZOOM := 1.08
const REST_ZOOM    := 1.035  # margin must cover DRIFT_PX at the edges
const SETTLE_TIME  := 2.4

var _rig: Node2D
var _drift_t := 0.0
var _picker: SectionPicker
var _sections_btn: Button

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
	_drift_t += delta
	_animate_backdrop(_drift_t)

# ── Network status ─────────────────────────────────────────

# Steam when available; `-- --lan` forces direct IP (e.g. two instances, one PC)
func _use_steam() -> bool:
	return NetworkManager.steam_available() and not OS.get_cmdline_user_args().has("--lan")

func _show_default_status() -> void:
	if _use_steam():
		net_status.text = "Signed in to Steam as %s — invite friends once in game" % NetworkManager.steam_name()
	elif NetworkManager.steam_available():
		net_status.text = "LAN mode — share your IP address to play together"
	else:
		net_status.text = "Steam unavailable: %s — LAN play only" % NetworkManager.steam_error()

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
	host_btn.disabled = true
	_sections_btn.disabled = true
	if _use_steam():
		net_status.text = "Creating Steam lobby…"
		NetworkManager.host_steam()
	else:
		NetworkManager.host()

func _on_host_failed(reason: String) -> void:
	host_btn.disabled = false
	_sections_btn.disabled = false
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
	var games := NetworkManager.friend_lobbies() if _use_steam() else []
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
		b.text = "Join %s" % g.name
		b.pressed.connect(func():
			status_label.text = "Joining %s…" % g.name
			NetworkManager.join_steam(g.lobby))
		box.add_child(b)
		if first == null:
			first = b
	first.grab_focus()

func _on_connect() -> void:
	var addr := address_input.text.strip_edges()
	if addr.is_empty():
		status_label.text = "Enter an address or lobby code first."
		return
	status_label.text = "Connecting…"
	connect_btn.disabled = true
	# Steam lobby ids are 64-bit numbers; anything else is treated as an IP/hostname
	if addr.is_valid_int() and addr.length() > 12:
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
		_join_failed("Connection failed. Check the address and that the host is running.")

# Panel may be hidden when the join came from a Steam invite, so surface it
func _join_failed(msg: String) -> void:
	_open_join()
	status_label.text = msg
	connect_btn.disabled = false

# ── Settings ───────────────────────────────────────────────

func _on_settings() -> void:
	settings.open()
