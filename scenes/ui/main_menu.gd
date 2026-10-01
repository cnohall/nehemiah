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
var _world: Node3D
var _world_tween: Tween

@onready var backdrop:      TextureRect = $Backdrop
@onready var column:        Control  = $Content/Column
@onready var menu:          Control  = $Content/Column/Menu
@onready var more:          Control  = $Content/Column/More
@onready var host_btn:      Button   = $Content/Column/Menu/HostButton
@onready var join_btn:      Button   = $Content/Column/Menu/JoinButton
@onready var settings_btn:  Button   = $Content/Column/More/SettingsButton
@onready var quit_btn:      Button   = $Content/Column/More/QuitButton
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
	_build_continue()
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
	# Big entries start a game; everything else sits in the small row under them
	# Friends and Foes: first in the small row, the page over everything
	_folk_btn = settings_btn.duplicate()
	_folk_btn.name = "FolkButton"
	_folk_btn.text = "Friends and Foes"
	more.add_child(_folk_btn)
	more.move_child(_folk_btn, 0)
	_folk = FriendsAndFoes.new()
	add_child(_folk)
	move_child(_folk, fade.get_index())
	_folk_btn.pressed.connect(_folk.open)
	_folk.closed.connect(_folk_btn.grab_focus)
	# Learn the basics: a solo practice walked through step by step (Tutorial)
	var learn := join_btn.duplicate() as Button
	learn.name = "LearnButton"
	learn.text = "Learn the Basics"
	menu.add_child(learn)
	menu.move_child(learn, join_btn.get_index() + 1)
	learn.pressed.connect(_on_learn)
	# Explore Jerusalem: the Festival of Booths, a sandbox with no clock and no enemy
	var walk := join_btn.duplicate() as Button
	walk.name = "FestivalButton"
	walk.text = "Explore Jerusalem"
	menu.add_child(walk)
	menu.move_child(walk, learn.get_index() + 1)
	walk.pressed.connect(_on_festival)
	# Credits: in the small row before Quit; the roll plays over the menu
	_credits_btn = settings_btn.duplicate()
	_credits_btn.name = "CreditsButton"
	_credits_btn.text = "Credits"
	more.add_child(_credits_btn)
	more.move_child(_credits_btn, quit_btn.get_index())
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
	settings.closed.connect(settings_btn.grab_focus)
	NetworkManager.lobby_created.connect(_on_lobby_created)
	NetworkManager.lobby_joined.connect(_on_lobby_joined)
	NetworkManager.host_failed.connect(_on_host_failed)
	_style_more()
	# Mouse and keyboard share one highlight: hovering an entry focuses it
	for b in menu.get_children() + more.get_children():
		if b is Button:
			b.mouse_entered.connect(b.grab_focus)
	join_panel.hide()
	_show_default_status()
	_intro()
	# Back from a replay: straight to the map, on the stretch just played
	GameState.replay_section = -1
	GameState.tutorial = false
	GameState.festival = false
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
	if join_panel.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back()

# ── Presentation ───────────────────────────────────────────

# The small row reads as text, not buttons: no box, an amber underline on focus,
# a dot between entries; the first lines up with the big entries' text
func _style_more() -> void:
	var btns := more.get_children()
	for i in btns.size():
		var b: Button = btns[i]
		var pad_l := 22.0 if i == 0 else 8.0
		var plain := StyleBoxFlat.new()
		plain.bg_color = Color(0, 0, 0, 0)
		plain.set_content_margin_all(6)
		plain.content_margin_left = pad_l
		plain.content_margin_right = 8
		plain.border_width_bottom = 2
		plain.border_color = Color(0, 0, 0, 0)
		var lit := plain.duplicate() as StyleBoxFlat
		lit.border_color = UiStyle.TERRACOTTA
		for st in ["normal", "disabled"]:
			b.add_theme_stylebox_override(st, plain)
		for st in ["hover", "pressed", "hover_pressed", "focus"]:
			b.add_theme_stylebox_override(st, lit)
		if i > 0:
			var dot := Label.new()
			dot.text = "·"
			dot.theme_type_variation = &"Caption"
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			more.add_child(dot)
			more.move_child(dot, b.get_index())

func _intro() -> void:
	fade.show()
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(fade.hide)
	UiFx.stagger(column.get_children().filter(func(c): return c != menu and c != more), 0.7, 0.09, 0.25)
	UiFx.stagger(menu.get_children() + more.get_children(), 0.45, 0.06, 0.65)
	UiFx.fade_in(verse, 1.0, 1.0)
	(_continue_btn if _continue_btn else host_btn).grab_focus()
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

func _show_default_status() -> void:
	if _use_steam():
		net_status.text = tr("Signed in to Steam as %s — invite friends once in game") % NetworkManager.steam_name()
	elif NetworkManager.steam_available():
		net_status.text = "LAN mode — share your IP address to play together"
	else:
		net_status.text = tr("Steam unavailable: %s — LAN play only") % tr(NetworkManager.steam_error())

# ── Host ───────────────────────────────────────────────────

func _on_host() -> void:
	GameState.replay_section = -1
	GameState.restart_day = -1
	_host()

# A campaign saved at the dawn of its latest stretch: first on the menu, named by where
# it stands. Host becomes "New Game" beside it.
var _continue_btn: Button

func _build_continue() -> void:
	var saved := GameState.campaign_save()
	if saved.is_empty():
		return
	_continue_btn = host_btn.duplicate() as Button
	_continue_btn.name = "ContinueButton"
	_continue_btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_continue_btn.text = tr("Continue — %s, day %d") % [tr(GameState.SECTIONS[saved["section"]]["name"]), saved["day"]]
	_continue_btn.tooltip_text = tr("Resumes at the start of this stretch. Progress is saved at the dawn of each new stretch.")
	menu.add_child(_continue_btn)
	menu.move_child(_continue_btn, host_btn.get_index())
	_continue_btn.pressed.connect(func():
		GameState.replay_section = -1
		GameState.restart_day = saved["day"]
		_host())
	host_btn.text = "New Game"
	host_btn.theme_type_variation = join_btn.theme_type_variation

# Solo, offline: no hosting, the game scene runs as its own server
func _on_learn() -> void:
	_stop_world()
	# A join or host still in flight would land us in someone's game as a client
	NetworkManager.disconnect_session()
	GameState.replay_section = -1
	GameState.tutorial = true
	get_tree().change_scene_to_file(GAME_SCENE)

# Solo, offline, like the practice: the city at the Festival of Booths
func _on_festival() -> void:
	_stop_world()
	NetworkManager.disconnect_session()
	GameState.replay_section = -1
	GameState.festival = true
	get_tree().change_scene_to_file(GAME_SCENE)

# Opens on the first stretch not yet built (the last one once all stand)
func _open_picker() -> void:
	var at := GameState.SECTIONS.size() - 1
	for i in GameState.SECTIONS.size():
		if GameState.is_unlocked(i) and GameState.best_marks(i) < 0:
			at = i
			break
	_picker.open(at)

## Host a game of just one section (the others' marks don't change)
func _on_section_chosen(section_index: int) -> void:
	GameState.replay_section = section_index
	GameState.picker_return = section_index
	_host()

func _host() -> void:
	_stop_world()
	host_btn.disabled = true
	_sections_btn.disabled = true
	if _continue_btn:
		_continue_btn.disabled = true
	if _use_steam():
		net_status.text = "Creating Steam lobby…"
		NetworkManager.host_steam()
	else:
		NetworkManager.host()

func _on_host_failed(reason: String) -> void:
	host_btn.disabled = false
	_sections_btn.disabled = false
	if _continue_btn:
		_continue_btn.disabled = false
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
			connect_btn.disabled = true   # in flight: Back cancels it
			_stop_world()
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
	_stop_world()
	# Steam lobby ids are 64-bit numbers; anything else is treated as an IP/hostname
	if addr.is_valid_int() and addr.length() > 12:
		if not NetworkManager.steam_available():
			_join_failed("That's a Steam lobby code — start Steam first.")
			return
		NetworkManager.join_steam(addr.to_int())
	else:
		NetworkManager.join(addr)

func _on_back() -> void:
	# Backing out mid-connect: drop the attempt, or it lands later as a client
	if connect_btn.disabled:
		NetworkManager.disconnect_session()
		_resume_world()
	join_panel.hide()
	status_label.text = ""
	connect_btn.disabled = false
	join_btn.grab_focus()

func _on_lobby_joined(success: bool) -> void:
	if success:
		_stop_world()   # a Steam invite joins straight from the menu
		get_tree().change_scene_to_file(GAME_SCENE)
	else:
		_join_failed("Connection failed. Check the address and that the host is running.")

# Panel may be hidden when the join came from a Steam invite, so surface it
func _join_failed(msg: String) -> void:
	_open_join()
	status_label.text = msg
	connect_btn.disabled = false
	_resume_world()

# ── Settings ───────────────────────────────────────────────

func _on_settings() -> void:
	settings.open()
