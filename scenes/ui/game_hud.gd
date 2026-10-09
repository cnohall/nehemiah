extends CanvasLayer

# In-game HUD. Reads GameState (mirrored on every peer) and is fed player/enemy
# numbers by Main. Player cards and the Steam invite panel are built in code.

signal begin_requested   # host pressed "Begin the work" (Main forwards to DayDirector)
signal bots_changed      # host changed Settings.bot_count / bot_skill (Main refits the crew)
signal ready_pressed         # local player is done with the dusk tally (Main → DayDirector)
signal unready_pressed       # ...and changed their mind
signal begin_now_requested   # host: go on without the ones still at the tally
signal vote_cast(choice: String)   # end screen: "again" | "next" (Main → DayDirector)

var highlights: Highlights   # the run's stills, set by Main (end-screen reel)

const MENU_SCENE    := "res://scenes/ui/main_menu.tscn"
const BANNER_HOLD   := 3.2
# Dusk tally: waits for the cheer and slow-mo to land, then counts the day up
const TALLY_DELAY   := 0.6
const TALLY_HOLD    := 5.6
const TALLY_COUNT   := 0.55    # seconds each number takes to count up
const TALLY_STEP    := 0.3     # between one number starting and the next
const WALL_CAM_HOLD := 3.3     # Main.WALL_CAM_TIME + its lead-in, less a beat
const BANNER_PAD    := 28.0    # space above and below the banner text
const BANNER_H      := 150.0   # Banner offset_bottom: title + sub…
const TALLY_H       := 118.0   # …plus the numbers row…
const CREW_H        := 62.0   # …plus one line per worker's share (multiplayer)
const MARKS_H       := 64.0    # …plus the section's marks on its last day…
const MARKS_BIG_H   := 172.0  # (a finished stretch: big gems, captions beneath)
const STRIP_H       := 32.0    # (an ordinary day: the campaign strip above its counts)
const TALLY_SMALL_H := 84.0   # (and then its counts, smaller)
const READY_H       := 56.0    # …plus who's ready to go on
const BUILDERS_H    := 58.0   # (a finished stretch: the "next to him…" names, one or two lines)
const SUB_LINE_H    := 28.0   # …plus each extra line under the title (days to spare, the campaign)
const BANNER_Y      := 0.2     # Banner anchor: dawn banners up top…
const TALLY_Y       := 0.6     # …the tally low, clear of the cheering crew mid-screen
const MAX_SLOTS     := 4
const ROMAN         := ["I", "II", "III", "IV"]
const WIN_VERSE     := "“So the wall was finished in the twenty-fifth day of Elul, in fifty-two days.”"
const WIN_VERSE_REF := "Nehemiah 6:15"
# Action → what it does; the key / button label comes from InputMode for the device
# in use. Shown while gathering and on day 1, and whenever paused.
const CONTROLS := [
	["move", "Move"],
	["interact", "Pick up · deliver · build"],
	["drop", "Drop"],
	["dash", "Dash"],
	["throw", "Sling: charge, then throw"],
	["horn", "Horn: rally the crew (stronger blows in its ring)"],   # only in sections with the horn
	["reveal", "Hold: what can I do here?"],
	["pause", "Menu"],   # "Pause · menu" when playing alone (see _refresh_controls)
]

@onready var day_number:   Label       = $Root/DayPlaque/VBox/DayRow/DayNumber
@onready var day_of:       Label       = $Root/DayPlaque/VBox/DayRow/DayOf
@onready var day_section:  Label       = $Root/DayPlaque/VBox/Section
@onready var circuit:      CircuitStrip = $Root/DayPlaque/VBox/Circuit
@onready var work_row:     Control     = $Root/DayPlaque/VBox/WorkRow
@onready var work_bar:     ProgressBar = $Root/DayPlaque/VBox/WorkRow/WorkBar
@onready var work_count:   Label       = $Root/DayPlaque/VBox/WorkRow/WorkCount
@onready var phase_label:  Label       = $Root/DayPlaque/VBox/PhaseLabel
@onready var threat:       Control     = $Root/ThreatPlaque
@onready var breach_count: Label       = $Root/ThreatPlaque/VBox/BreachRow/BreachCount
@onready var breach_pips:  PipRow      = $Root/ThreatPlaque/VBox/Pips
@onready var players_row:  VBoxContainer = $Root/Players   # stacked up the left edge, clear of the centre panels
@onready var banner:       Control     = $Root/Banner
@onready var banner_title: Label       = $Root/Banner/VBox/TitleRow/Title
@onready var banner_sub:   Label       = $Root/Banner/VBox/Sub
@onready var end_screen:   Control     = $Root/EndScreen
@onready var pause_menu:   Control     = $Root/PauseMenu
@onready var settings:     Control     = $Root/SettingsPanel
@onready var gather:       Control     = $Root/GatherPanel
@onready var gather_crew:  Label       = $Root/GatherPanel/VBox/Crew

var _cards: Array[Dictionary] = []
var _banner_tween: Tween
var _last_breaches := 0
var _controls: Control
var _controls_tween: Tween
var _pause_begin: Button     # host, while gathering: start from the menu (gamepad path)
var _gather_hint: Label
var _pad_lost_note: Label   # pause menu line shown after the pad in use disconnects
var _tally: VBoxContainer
var _last_tally := {}   # the latest dusk numbers (a replay's end screen shows its marks)
var _horn_row: Control
var _pause_what: Label       # controls card: what the pause key does
var _host_refreshers: Array[Callable] = []   # bot / difficulty rows (gather panel + pause menu)
var _tally_band: CanvasItem   # second layer of the band: numbers stay legible over world labels
var _ready_row: ReadyRow      # under the tally: hold [E] to go on, who else is ready
var _tally_waiting: Array = []   # latest DayDirector ready state for the tally
var _slot_colors: Array[Color] = [Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]
var _next_line: Label        # day plaque: what to do next, for the local player
var _next_poll := 0.0
const NEXT_POLL := 0.25
const KNOCKED_MS := 4000
var _knocked_until := 0   # ticks (ms): "Next:" line says a finished piece fell
var _last_done := 0
var _last_total := 0
var _sun_row: HBoxContainer  # day plaque: the sun clock (GameState.sun)
var _households_line: Label  # day plaque: households fed, Fountain Gate stretch
var _sun_dial: SunDial
var _sun_time: Label
var _sun_warned := false     # "the sun is low" said once a day
# Diegetic HUD (Settings.diegetic_hud): no plaques — the sun tells the time, the scribe
# keeps the record, the watchmen call the threats. The "Next:" line stays, as a caption
# low on the screen.
var _next_caption: Label
var _style_world := false
# Where this stretch lies on the real wall, and which way north is in the view (the same
# plan and needle as Explore Jerusalem's journal), top right under the threat plaque
var _compass: RingCompass

func _ready() -> void:
	# Keeps running while a solo game is paused (menus, settings, fades)
	process_mode = Node.PROCESS_MODE_ALWAYS
	for p: Control in [$Root/DayPlaque, $Root/ThreatPlaque, $Root/GatherPanel, $Root/PauseMenu/Center/Modal]:
		UiStyle.ornament(p)
	_build_player_cards()
	_build_controls_hint()
	_build_next_line()
	_build_next_caption()
	_build_compass()
	_build_sun_row()
	_build_households_line()
	_build_joining_plaque()
	# The practice has no day to count or waves to warn of; its own plaque says the step
	_style_world = not Settings.diegetic_hud   # forces the first _apply_style
	_apply_style()
	# Under the banner and menus, over the world-facing plaques
	var alerts := OffscreenAlerts.new()
	$Root.add_child(alerts)
	$Root.move_child(alerts, banner.get_index())
	$Root.add_child(ForecastChip.new())   # experimental wave forecast (GDD §5.21), hidden unless told
	# Hold [Tab] / View: a chip over everything near that answers a press
	var lens := ActionLens.new()
	$Root.add_child(lens)
	$Root.move_child(lens, banner.get_index())
	add_child(BotDemo.new())   # "Watch the carpenter: two to a beam"
	if NetworkManager.in_steam_lobby():
		_build_invite_panel()
	breach_pips.count = GameState.MAX_BREACHES
	day_of.text = tr("of %d") % GameState.TOTAL_DAYS
	_last_breaches = GameState.breaches

	$Root/EndScreen/Center/VBox/Buttons/MenuButton.pressed.connect(_leave)
	$Root/PauseMenu/Center/Modal/VBox/Resume.pressed.connect(_close_pause)
	$Root/PauseMenu/Center/Modal/VBox/Settings.pressed.connect(settings.open)
	$Root/PauseMenu/Center/Modal/VBox/Leave.pressed.connect(_leave)
	var is_host := multiplayer.is_server()
	$Root/GatherPanel/VBox/Begin.visible = is_host
	$Root/GatherPanel/VBox/Waiting.visible = not is_host
	$Root/GatherPanel/VBox/Begin.pressed.connect(begin_requested.emit)
	# Mouse only: with a pad, A near a stockpile must not also start the day
	$Root/GatherPanel/VBox/Begin.focus_mode = Control.FOCUS_NONE
	_build_gamepad_begin()
	if GameState.trades and not GameState.attract and not GameState.festival:
		_build_trade_row($Root/GatherPanel/VBox, $Root/GatherPanel/VBox/Begin.get_index(), false)
		var pause_vb := $Root/PauseMenu/Center/Modal/VBox
		_build_trade_row(pause_vb, $Root/PauseMenu/Center/Modal/VBox/Settings.get_index(), true)
	if is_host:
		_build_bot_row($Root/GatherPanel/VBox, $Root/GatherPanel/VBox/Begin.get_index(), false)
		# Also from the menu: mid-day, and reachable on a pad
		var menu := $Root/PauseMenu/Center/Modal/VBox
		var at: int = $Root/PauseMenu/Center/Modal/VBox/Settings.get_index()
		var rule := HSeparator.new()
		menu.add_child(rule)
		menu.move_child(rule, at)
		_build_bot_row(menu, at + 1, true)
	$Root/PauseMenu/Center/Modal/VBox/SaveHint.visible = GameState.saves_campaign()
	# Someone joined a paused solo game: the world can't stay frozen for them
	NetworkManager.peer_connected.connect(func(_id: int):
		get_tree().paused = false
		$Root/PauseMenu/Center/Modal/VBox/Hint.text = "The game keeps running for your crew while this is open."
		_refresh_controls())
	NetworkManager.peer_disconnected.connect(func(_id: int): _refresh_controls())
	GameState.crew_changed.connect(_on_crew_changed)
	_on_crew_changed(GameState.crew_size)
	settings.closed.connect($Root/PauseMenu/Center/Modal/VBox/Settings.grab_focus)
	_pad_lost_note = Label.new()
	_pad_lost_note.theme_type_variation = &"Caption"
	_pad_lost_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pad_lost_note.text = "Controller disconnected. Reconnect it to carry on"
	_pad_lost_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pad_lost_note.visible = false
	$Root/PauseMenu/Center/Modal/VBox.add_child(_pad_lost_note)
	$Root/PauseMenu/Center/Modal/VBox.move_child(_pad_lost_note, 0)
	InputMode.pad_lost.connect(_on_pad_lost)

	GameState.day_changed.connect(refresh_day)
	GameState.phase_changed.connect(_on_phase_changed)
	GameState.progress_changed.connect(_on_progress_changed)
	GameState.breaches_changed.connect(_on_breaches_changed)
	refresh_day(GameState.current_day)
	_on_breaches_changed(GameState.breaches)
	_on_phase_changed(GameState.phase)

# Language picked from the pause menu: redo the lines built from format strings
# (plain Labels retranslate themselves)
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		day_of.text = tr("of %d") % GameState.TOTAL_DAYS
		refresh_day(GameState.current_day)
		_on_crew_changed(GameState.crew_size)
		_refresh_gather_hint()
		for r in _host_refreshers:   # trade, difficulty and bot rows
			r.call()

func _unhandled_input(event: InputEvent) -> void:
	# B / Esc backs out of the menu, like every other screen
	var back := event.is_action_pressed("ui_cancel") and not event.is_action_pressed("pause")
	if back and pause_menu.visible and not settings.visible:
		get_viewport().set_input_as_handled()
		_close_pause()
		return
	if not event.is_action_pressed("pause") or end_screen.visible or _story_up():
		return
	get_viewport().set_input_as_handled()
	if pause_menu.visible:
		_close_pause()
	else:
		_open_pause()

func _open_pause() -> void:
	if pause_menu.visible:
		return
	pause_menu.show()
	InputMode.set_menu_open(true)
	# Alone (solo or with bots) the menu really pauses; online the others play on
	get_tree().paused = _solo()
	var vb := $Root/PauseMenu/Center/Modal/VBox
	vb.get_node("Eyebrow").text = "The work waits" if _solo() else "The work goes on"
	vb.get_node("Title").text = "Paused" if _solo() else "Menu"
	vb.get_node("Hint").text = "Nothing moves until you resume." if _solo() \
		else "The game keeps running for your crew while this is open."
	for r in _host_refreshers:
		r.call()
	UiFx.fade_in(pause_menu, 0.16)
	_refresh_controls()
	_pause_begin.visible = multiplayer.is_server() and GameState.phase == GameState.Phase.GATHER
	# The menu carries "Begin the work" now; don't show the gather banner's copy behind it
	gather.modulate.a = 0.0
	# One primary action at a time
	$Root/PauseMenu/Center/Modal/VBox/Resume.theme_type_variation = 			$Root/PauseMenu/Center/Modal/VBox/Settings.theme_type_variation if _pause_begin.visible else &"PrimaryButton"
	(_pause_begin if _pause_begin.visible else $Root/PauseMenu/Center/Modal/VBox/Resume).grab_focus()

# Pad unplugged mid-game: bring the menu up (online play can't freeze, but the player
# at least stops acting on ghost input) and say what happened
func _on_pad_lost() -> void:
	if end_screen.visible or _story_up():
		return
	_open_pause()
	_pad_lost_note.show()

# Gamepad: Start opens the menu with "Begin the work" on top and focused; the gather
# panel says so
func _build_gamepad_begin() -> void:
	_pause_begin = Button.new()
	_pause_begin.text = "Begin the work"
	_pause_begin.theme_type_variation = &"PrimaryButton"
	_pause_begin.visible = false
	_pause_begin.pressed.connect(func():
		_close_pause()
		begin_requested.emit())
	var vb := $Root/PauseMenu/Center/Modal/VBox
	vb.add_child(_pause_begin)
	vb.move_child(_pause_begin, $Root/PauseMenu/Center/Modal/VBox/Resume.get_index())
	# Steam's invite overlay: the gamepad-friendly way to bring friends in
	if NetworkManager.in_steam_lobby():
		var invite := Button.new()
		invite.text = "Invite friends"
		invite.theme_type_variation = &"GhostButton"
		invite.pressed.connect(func():
			if not NetworkManager.open_invite_overlay():
				invite.text = "Overlay off. Use the Crew panel"
				invite.disabled = true)
		vb.add_child(invite)
		vb.move_child(invite, $Root/PauseMenu/Center/Modal/VBox/Settings.get_index())
	_gather_hint = Label.new()
	_gather_hint.theme_type_variation = &"Caption"
	_gather_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	$Root/GatherPanel/VBox.add_child(_gather_hint)
	_refresh_gather_hint()

func _refresh_gather_hint() -> void:
	if _gather_hint != null:
		_gather_hint.visible = InputMode.using_pad and multiplayer.is_server()
		_gather_hint.text = tr("or press %s to begin") % InputMode.key("pause")

func _close_pause() -> void:
	pause_menu.hide()
	get_tree().paused = false
	gather.modulate.a = 1.0
	settings.hide()
	_pad_lost_note.hide()
	InputMode.set_menu_open(false)
	for r in _host_refreshers:
		r.call()
	_refresh_controls()

func _exit_tree() -> void:
	InputMode.set_menu_open(false)
	get_tree().paused = false
	_log_session()

# Playtest 3: where does a session stop? One line per game left (user://sessions.log):
# when, where on the circuit, what was going on, how many played. Stops at a section's
# boundary → the Continue save; stops mid-stretch → teaching and pacing.
const SESSION_LOG := "user://sessions.log"

var _logged := false

func _log_session() -> void:
	# Test harnesses (`--script`) aren't sessions: they'd bury the playtesters' lines
	if _logged or GameState.attract or GameState.free_play() or "--script" in OS.get_cmdline_args():
		return
	_logged = true
	var f := FileAccess.open(SESSION_LOG, FileAccess.READ_WRITE) if FileAccess.file_exists(SESSION_LOG) \
		else FileAccess.open(SESSION_LOG, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	var pos := GameState.day_in_section(GameState.current_day)
	f.store_line("%s  section=%d(%s) day=%d(%d/%d) phase=%s progress=%d/%d crew=%d replay=%d" % [
		Time.get_datetime_string_from_system(), GameState.current_section_index,
		GameState.get_current_section()["name"], GameState.current_day, pos.x + 1, pos.y,
		GameState.Phase.keys()[GameState.phase], GameState.targets_done, GameState.targets_total,
		GameState.crew_size, GameState.replay_section])
	f.close()

# No other people connected (bots don't count): pausing freezes the world
func _solo() -> bool:
	return multiplayer.get_peers().is_empty()

func _leave() -> void:
	_log_session()   # before the reset below wipes where we were
	get_tree().paused = false
	NetworkManager.disconnect_session()
	GameState.reset()
	get_tree().change_scene_to_file(MENU_SCENE)

# ── Day / Section ──────────────────────────────────────────

func refresh_day(day: int) -> void:
	var section := GameState.get_section_for_day(day)
	day_number.text  = str(day)
	day_section.text = "%s  ·  %s" % [tr(section["name"]), GameState.short_ref(section["ref"])]
	circuit.day = day

# ── Next step ──────────────────────────────────────────────

# One plain line under today's work: where the next load goes, or that it's time to
# build. New players read this rather than decoding the world tags.
func _build_next_line() -> void:
	_next_line = Label.new()
	_next_line.theme_type_variation = &"Caption"
	_next_line.add_theme_color_override("font_color", UiStyle.INK)
	_next_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_next_line.custom_minimum_size.x = 300
	_next_line.visible = false
	var vb := $Root/DayPlaque/VBox
	vb.add_child(_next_line)
	vb.move_child(_next_line, work_row.get_index() + 1)

# Fountain Gate stretch: how many hungry households are fed (each adds to the work, Neh. 5)
func _build_households_line() -> void:
	_households_line = Label.new()
	_households_line.theme_type_variation = &"Caption"
	_households_line.add_theme_color_override("font_color", UiStyle.INK)
	_households_line.visible = false
	var vb := $Root/DayPlaque/VBox
	vb.add_child(_households_line)
	vb.move_child(_households_line, work_row.get_index() + 1)

func _refresh_households() -> void:
	if _households_line == null:
		return
	var total := get_tree().get_nodes_in_group("households").size()
	var on := total > 0 and GameState.phase in [GameState.Phase.DAWN, GameState.Phase.WORK]
	_households_line.visible = on
	if on:
		_households_line.text = tr("Households fed: %d of %d") % [GameState.households_fed, total]

# Sun clock under today's work: "Daylight", the arc, minutes left
func _build_sun_row() -> void:
	_sun_row = HBoxContainer.new()
	_sun_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sun_row.add_theme_constant_override("separation", 12)
	_sun_row.visible = false
	var label := Label.new()
	label.theme_type_variation = &"Eyebrow"
	label.text = "Daylight"
	_sun_row.add_child(label)
	_sun_dial = SunDial.new()
	_sun_dial.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sun_dial.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sun_row.add_child(_sun_dial)
	_sun_time = Label.new()
	_sun_time.theme_type_variation = &"Body"
	_sun_time.add_theme_font_size_override("font_size", 15)
	_sun_time.add_theme_color_override("font_color", UiStyle.INK)
	_sun_time.custom_minimum_size.x = 40
	_sun_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_sun_row.add_child(_sun_time)
	var vb := $Root/DayPlaque/VBox
	vb.add_child(_sun_row)
	vb.move_child(_sun_row, work_row.get_index() + 1)

func _refresh_sun() -> void:
	var on := GameState.sun_total > 0.0 and GameState.phase in [GameState.Phase.DAWN, GameState.Phase.WORK]
	_sun_row.visible = on
	if not on:
		return
	var low := GameState.sun_low()
	_sun_dial.t = 1.0 - GameState.sun_left / GameState.sun_total
	_sun_dial.low = low
	_sun_dial.last_day = GameState.last_day_of_section()
	var secs := ceili(GameState.sun_left)
	_sun_time.text = "%d:%02d" % [secs / 60, secs % 60]
	_sun_time.add_theme_color_override("font_color", UiStyle.TERRACOTTA if low else UiStyle.INK)
	if low and not _sun_warned and GameState.phase == GameState.Phase.WORK:
		_sun_warned = true
		Sfx.play("alert")
		_flash(_sun_row, Color(1.0, 0.72, 0.6))
		_show_banner(tr("The sun is low"), tr("Finish before the stars appear: the %s must stand tonight") % tr(GameState.get_current_section()["name"]) \
			if GameState.last_day_of_section() else tr("What isn't built by the stars waits for tomorrow"), 2.2)

func _process(delta: float) -> void:
	if _style_world != Settings.diegetic_hud:
		_apply_style()
	_place_compass()
	if _sun_row != null:
		_refresh_sun()
	_refresh_households()
	_next_poll -= delta
	if _next_poll > 0.0 or _next_line == null:
		return
	_next_poll = NEXT_POLL
	# The practice points the way itself (Tutorial); two voices would talk over each other
	var text := "" if GameState.free_play() else _next_text()
	var line := _next_caption if _style_world else _next_line
	(_next_line if _style_world else _next_caption).visible = false
	line.visible = not text.is_empty()
	line.text = text

# Plaques, or the world telling it (the setting can change mid-game from the menu)
func _apply_style() -> void:
	_style_world = Settings.diegetic_hud
	var plaques := not _style_world and not GameState.free_play() and not end_screen.visible
	$Root/DayPlaque.visible = plaques
	threat.visible = plaques
	_next_poll = 0.0

# Low and centred, clear of the crew cards and the controls card: a slim parchment
# plaque, like the rest of the HUD
func _build_compass() -> void:
	_compass = RingCompass.new()
	_compass.follow_section = true
	$Root.add_child(_compass)
	_compass.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_compass.offset_right = -18.0
	_compass.offset_left = -18.0 - _compass.custom_minimum_size.x

# Under the threat plaque when it's up; out of the way of the story and the end screen
func _place_compass() -> void:
	_compass.visible = not end_screen.visible and GameState.phase != GameState.Phase.STORY
	var top := 18.0
	if threat.visible:
		top = threat.get_global_rect().end.y - $Root.get_global_rect().position.y + 12.0
	_compass.offset_top = top
	_compass.offset_bottom = top + _compass.custom_minimum_size.y

func _build_next_caption() -> void:
	_next_caption = Label.new()
	_next_caption.add_theme_font_override("font", UiStyle.SPECTRAL_ITALIC)
	_next_caption.add_theme_font_size_override("font_size", 21)
	_next_caption.add_theme_color_override("font_color", UiStyle.INK)
	_next_caption.add_theme_stylebox_override("normal", UiStyle.plaque(Vector2(26, 6), 0.95))
	_next_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_next_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_next_caption.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # set translated
	_next_caption.visible = false
	$Root.add_child(_next_caption)
	_next_caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 36)
	_next_caption.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_next_caption.grow_vertical = Control.GROW_DIRECTION_BEGIN

func _next_text() -> String:
	if GameState.phase != GameState.Phase.WORK:
		return ""
	var me := Player.local
	if me == null or not is_instance_valid(me):
		return ""
	if me.downed:
		return "Down. A crewmate has to help you up"
	if Time.get_ticks_msec() < _knocked_until:
		return "A finished piece was knocked down. Build it back up"
	var left := GameState.targets_total - GameState.targets_done
	# A saboteur scattered a pile: nothing comes from it until it's gathered up
	if me.carried_kind.is_empty():
		var mess := get_tree().get_first_node_in_group("scattered_piles")
		if mess != null:
			return tr("The %s pile is scattered. Nothing to take until you gather it up (%s at the pile)") % [_material_name(mess.kind), InputMode.key("interact")]
	var site := SiteFocus.site()
	if site == null:
		# Only "done" when it is (playtest 2: players thought the wall stood and waited
		# for a day end that never came) — a piece knocked back down still counts
		if left <= 0:
			return "The stretch stands"
		return tr_n("%d piece still to finish. Look for the amber footing", "%d pieces still to finish. Look for the amber footings", left) % left
	var line := _site_line(site, me)
	if left == 1 and not line.is_empty():
		return tr("Last piece!  %s") % line
	return line

func _site_line(site: Node3D, me: Player) -> String:
	# One line per place (not "to the %s"): a translation needs the whole sentence
	var at_gate := not site.is_in_group("wall_sections")
	var carry: String = me.carried_kind
	if not carry.is_empty():
		if SiteFocus.matches_carry():
			return (tr("Take the %s to the gate") if at_gate else tr("Take the %s to the wall")) % _material_name(carry)
		return tr("Nothing needs %s now. Drop it (%s)") % [_material_name(carry), InputMode.key("drop")]
	if GameState.active_build and site.can_build():
		return (tr("Build it up: %s at the gate") if at_gate else tr("Build it up: %s at the wall")) % InputMode.key("interact")
	var need: String = site.next_need()
	if need.is_empty():
		return ""
	return (tr("Next: bring %s to the gate") if at_gate else tr("Next: bring %s to the wall")) % _material_name(need)

## A material as a word in a sentence ("stone", "beams"), translated
func _material_name(kind: String) -> String:
	return tr({"beam": "beams"}.get(kind, kind))

func _on_progress_changed(done: int, total: int) -> void:
	# A piece that stood was knocked back down: say so, it no longer counts
	if GameState.phase == GameState.Phase.WORK and total == _last_total and done < _last_done:
		_knocked_until = Time.get_ticks_msec() + KNOCKED_MS
		_flash($Root/DayPlaque, Color(1.0, 0.72, 0.6))
		_next_poll = 0.0
	_last_done = done
	_last_total = total
	_refresh_progress()

func _refresh_progress() -> void:
	# Sun clock: the bar is the whole stretch, not a day's share
	$Root/DayPlaque/VBox/WorkRow/WorkLabel.text = "The stretch" if GameState.sun_total > 0.0 else "Today's work"
	var working := GameState.phase == GameState.Phase.WORK
	work_row.visible = working
	phase_label.visible = not working
	match GameState.phase:
		GameState.Phase.GATHER:
			phase_label.text = "Gathering the crew"
		GameState.Phase.STORY:
			phase_label.text = ""
		GameState.Phase.DAWN:
			phase_label.text = "Dawn. Ready the workers"
		GameState.Phase.DUSK:
			phase_label.text = "The day's work is done"
		GameState.Phase.WON:
			phase_label.text = "The wall is finished"
		GameState.Phase.LOST:
			phase_label.text = "The city has fallen"
	var total := maxi(GameState.targets_total, 1)
	var share := float(GameState.targets_done) / total
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(work_bar, "value", share, 0.35)
	tw.tween_property(circuit, "today_progress", share, 0.35)
	work_count.text = "%d / %d" % [GameState.targets_done, GameState.targets_total]

func _on_breaches_changed(count: int) -> void:
	breach_count.text = "%d / %d" % [count, GameState.MAX_BREACHES]
	breach_pips.filled = count
	var danger := count >= ceili(GameState.MAX_BREACHES * 0.7)
	breach_count.add_theme_color_override("font_color", UiStyle.TERRACOTTA if danger else UiStyle.INK_SOFT)
	if count > _last_breaches:
		_flash(threat, Color(1.0, 0.72, 0.6))
	_last_breaches = count

# ── Phase banners / end screen ─────────────────────────────

## DayDirector.ready_changed: who the dusk tally is still waiting on
func set_ready_state(kind: String, waiting: Array) -> void:
	if kind != "tally":
		return
	_tally_waiting = waiting
	if _ready_row != null and is_instance_valid(_ready_row):
		_ready_row.set_waiting(waiting)

func _on_phase_changed(phase: GameState.Phase) -> void:
	_refresh_progress()
	# A tally held open for the ready check goes when the dusk does
	if phase != GameState.Phase.DUSK and _tally != null and _tally.visible:
		_tally.hide()
		banner.hide()
	gather.visible = phase == GameState.Phase.GATHER
	_refresh_controls()
	var section := GameState.get_current_section()
	match phase:
		GameState.Phase.DAWN:
			_sun_warned = false
			var first_day := GameState.day_in_section(GameState.current_day).x == 0
			var sub: String = (tr("A new stretch: %s  ·  %s") if first_day else "%s  ·  %s") % [tr(section["name"]), GameState.short_ref(section["ref"])]
			# First day of a section that brings something new: say what
			if first_day:
				for twist: String in GameState.new_twists():
					sub += "\n" + tr(GameState.twist_intro(twist)).format({"horn": "[%s]" % InputMode.key("horn")})
				if GameState.BOONS.has(GameState.boon):
					var lines := GameState.boon_lines(GameState.boon)
					sub += "\n" + tr("The crew chose: %s") % tr(GameState.BOONS[GameState.boon]["title"])
					sub += "  ·  " + "  ·  ".join(lines["gain"] + lines["cost"])
			if GameState.sun_total > 0.0:
				var pos := GameState.day_in_section(GameState.current_day)
				if pos.x == 0:
					sub += "\n" + tr_n("Raise the whole stretch: %d day before the stars", "Raise the whole stretch: %d days before the stars", pos.y) % pos.y
				elif pos.x == pos.y - 1:
					sub += "\n" + tr("The last day of this stretch: it must stand before the stars appear")
				else:
					sub += "\n" + tr("%d of %d stand, %d days left") % [GameState.targets_done, GameState.targets_total, pos.y - pos.x]
			if first_day and GameState.dawn_saved():
				sub += "\n" + tr("Progress saved. Continue from the title screen")
			if not GameState.free_play():
				_show_banner(tr("Day %d") % GameState.current_day, sub)
		GameState.Phase.WON:
			# The campaign's ending story plays first; Main calls show_end after it
			if not StoryData.plays_ending():
				_show_end(true)
		GameState.Phase.LOST:
			_show_end(false)

func _show_banner(title: String, sub: String, hold := BANNER_HOLD, with_tally := false) -> void:
	if _tally != null:
		_tally_band.visible = with_tally
	banner_title.text = title
	banner_sub.text = sub
	if _tally != null and not with_tally:
		_tally.hide()
	if not with_tally:
		# Grow the band with the text (a new stretch can bring two twist lines)
		var content := ($Root/Banner/VBox as Control).get_combined_minimum_size().y
		banner.offset_bottom = maxf(BANNER_H, banner.offset_top + content + BANNER_PAD * 2.0)
	banner.anchor_top = TALLY_Y if with_tally else BANNER_Y
	banner.anchor_bottom = banner.anchor_top
	if _banner_tween:
		_banner_tween.kill()
	banner.show()
	banner.modulate.a = 0.0
	banner_sub.modulate.a = 0.0
	_banner_tween = create_tween()
	_banner_tween.tween_property(banner, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_property(banner_sub, "modulate:a", 1.0, 0.5)
	if hold < 0.0:
		return   # stays until the phase moves on (the dusk tally)
	_banner_tween.tween_interval(hold)
	_banner_tween.tween_property(banner, "modulate:a", 0.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_banner_tween.tween_callback(banner.hide)

# Story cards on screen: before a day, or the ending before the end screen
func _story_up() -> bool:
	return GameState.phase == GameState.Phase.STORY 		or (GameState.phase == GameState.Phase.WON and not end_screen.visible)

func show_end(won: bool) -> void:
	if not end_screen.visible:
		_show_end(won)

func _show_end(won: bool) -> void:
	if _banner_tween:
		_banner_tween.kill()
	banner.hide()
	pause_menu.hide()
	for n: Control in [$Root/DayPlaque, threat, players_row]:
		n.hide()
	var vb := $Root/EndScreen/Center/VBox
	vb.get_node("Eyebrow").text = tr("Day %d of %d") % [GameState.current_day, GameState.TOTAL_DAYS]
	var stars := not won and GameState.loss_reason == "stars"
	var demo_end := won and GameState.is_demo() and not GameState.is_replay()
	vb.get_node("Title").text = "The wall is finished" if won else ("The stars appeared" if stars else "The city is overrun")
	vb.get_node("Message").text = WIN_VERSE if won \
		else (tr("The %s was not finished by nightfall. Gather the workers and begin again.") % tr(GameState.get_current_section()["name"]) if stars \
		else tr("Too many enemies reached the inner city. Gather the workers and begin again."))
	vb.get_node("Ref").text = GameState.long_ref(WIN_VERSE_REF) if won else ""
	vb.get_node("Ref").visible = won
	if demo_end:
		vb.get_node("Title").text = tr("The first brute")
		vb.get_node("Message").text = tr("Nine days, two stretches of wall, and the enemy has sent a brute. %d days and %d stretches remain, and they will only grow bolder.") \
			% [GameState.TOTAL_DAYS - GameState.current_day, GameState.SECTIONS.size() - GameState.current_section_index]
		vb.get_node("Ref").hide()
	var days_done := GameState.current_day if demo_end else (GameState.TOTAL_DAYS if won else GameState.current_day - 1)
	var sections_done := GameState.current_section_index if demo_end else (GameState.SECTIONS.size() if won else GameState.current_section_index)
	var stats: Control = vb.get_node("Stats")
	for c in stats.get_children():
		c.queue_free()
	stats.add_child(_stat(str(days_done), "Days built"))
	stats.add_child(_stat("%d / %d" % [sections_done, GameState.SECTIONS.size()], "Sections"))
	stats.add_child(_stat(str(GameState.breaches), "Breaches"))
	if sections_done > 0:
		stats.add_child(_stat("%d / %d" % [GameState.total_marks(), sections_done * GameState.marks_in_play().size()], "Marks"))
	if GameState.is_replay():
		_replay_end(won, vb, stats)
	_build_end_map(won)
	_build_reel(vb)
	_build_vote(won, vb)
	end_screen.show()
	UiFx.fade_in(end_screen, 0.9)
	UiFx.stagger(vb.get_children(), 0.6, 0.08, 0.3)
	var first: Button = vb.get_node("Buttons").get_child(0)
	first.grab_focus()
	_fit_end(vb)

# The reel is the only elastic part: shrink it (16:9) until the buttons sit on screen
func _fit_end(vb: Control) -> void:
	var pic := vb.find_child("*TextureRect*", true, false) as Control
	if pic == null:
		return
	pic.custom_minimum_size = REEL_SIZE
	await get_tree().process_frame
	var over := vb.get_combined_minimum_size().y - (end_screen.size.y - 48.0)
	if over <= 0.0:
		return
	var h := maxf(REEL_SIZE.y - over, 72.0)
	pic.custom_minimum_size = Vector2(h * REEL_SIZE.x / REEL_SIZE.y, h)

# ── End screen: the scribe's map ───────────────────────────

var _end_map: CircuitMap

# The run's map, worn by it (CircuitMap `aged`), fills the screen behind a parchment
# column on the left that holds the words, the reel and the choices. A win closes the
# ring (finale); otherwise the stretch reached pulses.
func _build_end_map(won: bool) -> void:
	if _end_map == null:
		var scrim: ColorRect = $Root/EndScreen/Scrim
		scrim.color.a = 0.0
		_end_map = CircuitMap.new()
		_end_map.aged = true
		_end_map.paper = true
		_end_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
		end_screen.add_child(_end_map)
		end_screen.move_child(_end_map, scrim.get_index() + 1)
		_end_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var column := TextureRect.new()
		var tex := GradientTexture2D.new()
		var g := Gradient.new()
		g.set_color(0, Color(UiStyle.PARCHMENT, 0.97))
		g.set_color(1, Color(UiStyle.PARCHMENT, 0.0))
		g.add_point(0.72, Color(UiStyle.PARCHMENT, 0.9))   # after the ends: it takes index 1
		tex.gradient = g
		column.texture = tex
		column.stretch_mode = TextureRect.STRETCH_SCALE
		column.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		end_screen.add_child(column)
		end_screen.move_child(column, _end_map.get_index() + 1)
		column.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
		column.anchor_right = 0.56
		var center: Control = $Root/EndScreen/Center
		center.anchor_right = 0.48
	_end_map.finale = won and not GameState.is_replay()
	_end_map.section = GameState.replay_section if GameState.is_replay() else GameState.current_section_index
	_end_map.play()

# ── End screen: highlight reel + play again ────────────────

const REEL_SIZE  := Vector2(512, 288)
const REEL_SLIDE := 2.6   # seconds per still

var _reel_tween: Tween
var _vote_note: Label
var _vote_buttons := {}   # choice → Button
var _wishlist_btn: Button   # demo end card

# The run's stills (Highlights), one after another while the crew decides
func _build_reel(vb: Control) -> void:
	var old := vb.get_node_or_null("Reel")
	if old:
		old.queue_free()
	if highlights == null or highlights.shots.is_empty():
		return
	var shots: Array = highlights.shots.duplicate()
	var reel := VBoxContainer.new()
	reel.name = "Reel"
	reel.add_theme_constant_override("separation", 6)
	reel.alignment = BoxContainer.ALIGNMENT_CENTER
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UiStyle.bordered(UiStyle.box(UiStyle.DUSK, Vector2(4, 4), 3), UiStyle.RULE, 1))
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	reel.add_child(frame)
	var pic := TextureRect.new()
	pic.custom_minimum_size = REEL_SIZE
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	frame.add_child(pic)
	var caption := Label.new()
	caption.theme_type_variation = &"Caption"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_color_override("font_color", UiStyle.INK_SOFT)
	caption.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # captions arrive translated
	reel.add_child(caption)
	vb.add_child(reel)
	vb.move_child(reel, 0)
	if _reel_tween:
		_reel_tween.kill()
	_reel_tween = create_tween().set_loops()
	for i in shots.size():
		var shot: Dictionary = shots[i]
		_reel_tween.tween_callback(func():
			pic.texture = shot["tex"]
			caption.text = "%s   ·   %d / %d" % [shot["caption"], i + 1, shots.size()])
		_reel_tween.tween_property(pic, "modulate:a", 1.0, 0.35).from(0.0)
		_reel_tween.tween_interval(REEL_SLIDE)
		_reel_tween.tween_property(pic, "modulate:a", 0.0, 0.35)

# "Play again" / "Next stretch": the host's pick decides, or a majority of the crew
# (DayDirector.cast_vote). Back to the menu stays each person's own choice.
func _build_vote(won: bool, vb: Control) -> void:
	var buttons: HBoxContainer = vb.get_node("Buttons")
	buttons.add_theme_constant_override("separation", 16)
	for b in _vote_buttons.values():
		b.queue_free()
	_vote_buttons.clear()
	var choices: Array = []   # [choice, label]
	if GameState.is_replay():
		choices.append(["again", "Play it again"])
		var next := GameState.replay_section + 1
		if won and next < (GameState.DEMO_SECTIONS if GameState.is_demo() else GameState.SECTIONS.size()):
			choices.append(["next", "Next stretch"])
	elif won:
		choices.append(["again", "Play again"])
	else:
		choices.append(["again", "Try the stretch again"])
	for i in choices.size():
		var b := Button.new()
		b.text = choices[i][1]
		b.custom_minimum_size.x = 220
		b.theme_type_variation = &"PrimaryButton" if i == 0 else &"GhostButton"
		var choice: String = choices[i][0]
		b.pressed.connect(func(): vote_cast.emit(choice))
		buttons.add_child(b)
		buttons.move_child(b, i)
		_vote_buttons[choice] = b
	(vb.get_node("Buttons/MenuButton") as Button).theme_type_variation = &"GhostButton"
	if _wishlist_btn:
		_wishlist_btn.queue_free()
		_wishlist_btn = null
	if won and GameState.is_demo() and not GameState.is_replay() and not GameState.DEMO_WISHLIST_URL.is_empty():
		_wishlist_btn = Button.new()
		_wishlist_btn.text = "Wishlist on Steam"
		_wishlist_btn.custom_minimum_size.x = 220
		_wishlist_btn.theme_type_variation = &"PrimaryButton"
		_wishlist_btn.pressed.connect(func(): OS.shell_open(GameState.DEMO_WISHLIST_URL))
		buttons.add_child(_wishlist_btn)
		buttons.move_child(_wishlist_btn, 0)
		for b in _vote_buttons.values():
			b.theme_type_variation = &"GhostButton"
	if _vote_note == null:
		_vote_note = Label.new()
		_vote_note.theme_type_variation = &"Caption"
		_vote_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_vote_note.add_theme_color_override("font_color", UiStyle.INK_MUTED)
		vb.add_child(_vote_note)
	_vote_note.text = "" if _solo() else tr("The host's pick decides (or most of the crew)")

## DayDirector.votes_changed: how many want what
func set_votes(votes: Dictionary) -> void:
	if _vote_note == null:
		return
	var people := 1 + multiplayer.get_peers().size()
	var lines: PackedStringArray = []
	for choice: String in _vote_buttons:
		var n := votes.values().count(choice)
		if n > 0:
			lines.append(tr("%s: %d of %d") % [tr(_vote_buttons[choice].text), n, people])
	var mine: String = votes.get(multiplayer.get_unique_id(), "")
	for choice: String in _vote_buttons:
		_vote_buttons[choice].disabled = not mine.is_empty()
	_vote_note.text = "   ·   ".join(lines) + ("\n" + tr("Waiting for the host or most of the crew") if not mine.is_empty() else "")

# A replay is one section: name it, show its three marks, and head back to the map
func _replay_end(won: bool, vb: Control, stats: Control) -> void:
	var i := GameState.replay_section
	var sec: Dictionary = GameState.SECTIONS[i]
	vb.get_node("Eyebrow").text = tr("Section %d of %d  ·  %s") % [i + 1, GameState.SECTIONS.size(), GameState.short_ref(sec["ref"])]
	if won:
		vb.get_node("Title").text = tr("The %s stands") % tr(sec["name"])
		var got := GameState.mark_count(GameState.section_marks[i])
		vb.get_node("Message").text = (tr("A new best for this stretch: %d of 3 marks.") if GameState.rating_improved 			else tr("%d of 3 marks. Your best here stays as it was.")) % got
	elif GameState.loss_reason == "stars":
		vb.get_node("Message").text = tr("The stretch was not finished by nightfall. Try it again.")
	else:
		vb.get_node("Message").text = "Too many enemies reached the inner city. Try the stretch again."
	vb.get_node("Ref").hide()
	for c in stats.get_children():
		c.queue_free()
	if won and _last_tally.has("marks"):
		var secs := int(_last_tally["section_time"])
		stats.add_child(_stat("%d:%02d" % [secs / 60, secs % 60], "Time"))
		stats.add_child(_stat(str(_last_tally["section_breaches"]), "Breaches"))
		var marks := _marks_line(_last_tally)
		vb.add_child(marks)
		vb.move_child(marks, stats.get_index() + 1)
	else:
		var built: int = GameState.current_day - GameState.SECTIONS[i]["days"][0]
		stats.add_child(_stat("%d / %d" % [built, sec["days"].size()], "Days built"))
		stats.add_child(_stat(str(GameState.breaches), "Breaches"))
	if GameState.picker_return >= 0:
		vb.get_node("Buttons/MenuButton").text = "Back to the map"

# ── Dusk tally ─────────────────────────────────────────────

## The day's numbers (DayDirector.day_tallied): what the crew did, then who did what
func show_tally(stats: Dictionary) -> void:
	_last_tally = stats
	# A stretch that stands gets its wall cam first (Main)
	var wall_cam := stats.has("names") and not GameState.attract
	await get_tree().create_timer(TALLY_DELAY + (WALL_CAM_HOLD if wall_cam else 0.0), true, false, true).timeout
	if GameState.phase != GameState.Phase.DUSK:
		return
	if _tally == null:
		_tally = VBoxContainer.new()
		_tally.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tally.add_theme_constant_override("separation", 10)
		$Root/Banner/VBox.add_child(_tally)
		_tally_band = $Root/Banner/Band.duplicate()
		$Root/Banner.add_child(_tally_band)
		$Root/Banner.move_child(_tally_band, 1)
	for c in _tally.get_children():
		c.queue_free()

	var day := GameState.current_day
	var section := GameState.get_current_section()
	var title := tr("Day %d complete") % day
	# A clean day says nothing; only a breach earns a line
	var sub := "" if stats["breaches"] == 0 		else tr_n("%d slipped through, but the wall stands.", "%d slipped through, but the wall stands.", stats["breaches"]) % stats["breaches"]
	var unfinished: int = stats.get("unfinished", 0)
	if unfinished > 0:
		# The stars came first: the day ends, the rest waits for tomorrow
		title = tr("Nightfall on day %d") % day
		sub = tr_n("The stars appeared: %d wall piece left for tomorrow.", "The stars appeared: %d wall pieces left for tomorrow.", unfinished) % unfinished
	# The whole section is done (rated) — say so, and how many days it had to spare
	elif stats.has("marks"):
		title = tr("The %s stands") % tr(section["name"])
		# One line: the marks below already say pace, breaches and soundness
		sub = tr("Section %d of %d complete") % [GameState.current_section_index + 1, GameState.SECTIONS.size()]
		# A close call earns its own line (DayDirector._close_call)
		match stats.get("close", ""):
			"stars": sub = tr("By a hair: the last stone was set as the stars came out.") + "\n" + sub
			"gap":   sub = tr("By a hair: the gap closed in the enemy's face.") + "\n" + sub
	# Where the campaign stands: the far goal in view every evening (a pull to day 52)
	var campaign := not GameState.is_replay() and not GameState.attract
	if campaign:
		var days_left := tr("%d days to the fifty-second") % (GameState.TOTAL_DAYS - day)
		sub += ("\n" if unfinished > 0 else "  ·  ") + days_left if sub != "" else days_left

	# A finished stretch leads with its marks (the payoff); an ordinary day with the
	# campaign strip, today's cell filling. Counts beneath either way, smaller.
	var marks_line: Control = null
	var builders_shown := false
	var strip: CircuitStrip = null
	if stats.has("marks") and unfinished == 0:
		var gap := Control.new()
		gap.custom_minimum_size.y = 10
		_tally.add_child(gap)
		marks_line = _marks_line(stats, true)
		_tally.add_child(marks_line)
		var builders := _builders_line()
		if builders:
			builders_shown = true
			_tally.add_child(builders)
		var after := Control.new()  # air between the marks and the counts
		after.custom_minimum_size.y = 8
		_tally.add_child(after)
	elif campaign:
		strip = CircuitStrip.new()
		strip.day = day
		strip.custom_minimum_size = Vector2(600, 22)
		strip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tally.add_child(strip)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 0)
	_tally.add_child(row)
	# A stretch that stands counts the whole stretch, not just its last day
	var rated := stats.has("marks")
	var pre := "section_" if rated else ""
	var secs := int(stats[pre + "time"])
	var counts: Array = [
		[stats[pre + "loads"], "Loads carried", func(v: int): return str(v)],
		[stats[pre + "foes"], "Foes felled", func(v: int): return str(v)],
	]
	if not rated:  # a finished stretch's time is the pace mark's "2:35 of 9:00"
		counts.push_front([secs, "Time", func(v: int): return "%d:%02d" % [v / 60, v % 60]])
	if stats.get("scattered", 0) > 0 and not rated:
		counts.append([stats["scattered"], "Piles scattered", func(v: int): return str(v)])
	for i in counts.size():
		if i > 0:
			row.add_child(_rule_v(40))
		var cell := _stat(counts[i][2].call(0), counts[i][1], 32 if (marks_line or strip) else 0)
		# Equal cells: the numbers sit evenly however long their captions run
		cell.custom_minimum_size.x = 190
		row.add_child(cell)
		_count_up(cell.get_child(0), counts[i][0], counts[i][2], i * TALLY_STEP + 0.5)

	var crew: Array = stats[pre + "crew"]
	if crew.size() > 1:
		_tally.add_child(_crew_line(crew))
	# The tally stays until everyone is ready (playtest 2) — the title screen's crew
	# has nobody to ask, so there it fades as before
	# Simple game: a stretch's last tally moves on by itself (DayDirector.SECTION_DUSK_TIME)
	var waits := not GameState.attract and not (stats.has("marks") and GameState.simplified())
	if waits:
		_ready_row = ReadyRow.new(false)
		_ready_row.holdable = true
		_ready_row.cancellable = true
		_ready_row.ready_pressed.connect(ready_pressed.emit)
		_ready_row.unready_pressed.connect(unready_pressed.emit)
		_ready_row.begin_now.connect(begin_now_requested.emit)
		_tally.add_child(_ready_row)
		_ready_row.set_waiting(_tally_waiting)

	banner.offset_bottom = BANNER_H + (TALLY_SMALL_H if (marks_line or strip) else TALLY_H) + (CREW_H if crew.size() > 1 else 0.0) 		+ (MARKS_BIG_H if marks_line else 0.0) + (BUILDERS_H if marks_line and builders_shown else 0.0) + (STRIP_H if strip else 0.0) + (READY_H if waits else 0.0) 		+ sub.count("\n") * SUB_LINE_H
	_tally.show()
	_show_banner(title, sub, -1.0 if waits or (stats.has("marks") and GameState.simplified()) else TALLY_HOLD, true)
	UiFx.stagger(_tally.get_children(), 0.45, 0.12, 0.3)
	if strip and unfinished == 0:
		# Today's cell fills in: the day's work, banked
		var tw := create_tween()
		tw.tween_interval(0.8)
		tw.tween_property(strip, "today_progress", 1.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_callback(Sfx.play.bind("tally_land"))
	if marks_line:
		# Taller than a plain tally: ride higher so the prompt stays on screen
		banner.anchor_top = 0.5
		banner.anchor_bottom = 0.5
		_pop_marks(marks_line, 0.7)
		# The title lands like a set stone
		banner_title.pivot_offset = banner_title.size * 0.5
		banner_title.scale = Vector2.ONE * 1.08
		create_tween().tween_property(banner_title, "scale", Vector2.ONE, 0.4) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.2)

# The section's three marks, each with what earned it (or what it needed)
func _marks_line(stats: Dictionary, big := false) -> Control:
	var mask: int = stats["marks"]
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", 24 if big else 44)
	var details := {
		GameState.Mark.PACE: tr("day %d of %d") % [stats["section_day"], stats["section_days"]],
		GameState.Mark.CLEAN: tr("all through the section") if mask & GameState.Mark.CLEAN 			else tr_n("%d got through", "%d got through", stats["section_breaches"]) % stats["section_breaches"],
		GameState.Mark.SOUND: tr("%d%% sound") % roundi(stats["wall"] * 100.0),
	}
	for m: int in GameState.marks_in_play():
		var earned := bool(mask & m)
		# Big: the hero of the tally — a large gem with its name and proof stacked beneath
		var chip: BoxContainer = VBoxContainer.new() if big else HBoxContainer.new()
		chip.add_theme_constant_override("separation", 6 if big else 10)
		if big:  # equal columns: the gems sit evenly whatever their captions say
			chip.custom_minimum_size.x = 200
		var gem := MarkGem.new(earned, 68.0 if big else 22.0)
		gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		gem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		chip.add_child(gem)
		var text := VBoxContainer.new()
		text.add_theme_constant_override("separation", -2)
		var name_l := _crew_label(GameState.MARK_NAMES[m], UiStyle.TERRACOTTA if earned else UiStyle.INK_MUTED)
		var detail := _crew_label(details[m], UiStyle.INK_SOFT if earned else Color(UiStyle.INK_MUTED, 0.8))
		detail.add_theme_font_size_override("font_size", 15)
		if big:
			name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name_l.add_theme_font_size_override("font_size", 20)
		text.add_child(name_l)
		text.add_child(detail)
		chip.add_child(text)
		line.add_child(chip)
	return line

# The marks land one at a time: gem pops in, thud and glint if earned, words follow
func _pop_marks(line: Control, delay: float) -> void:
	for i in line.get_child_count():
		var chip: Control = line.get_child(i)
		var gem: MarkGem = chip.get_child(0)
		var text: Control = chip.get_child(1)
		gem.scale = Vector2.ZERO
		text.modulate.a = 0.0
		var tw := create_tween().set_parallel()
		var at := delay + i * 0.42
		tw.tween_property(gem, "scale", Vector2.ONE, 0.38).set_delay(at) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(text, "modulate:a", 1.0, 0.4).set_delay(at + 0.15)
		if gem.lit:
			tw.tween_callback(Sfx.play.bind("tally_land")).set_delay(at + 0.2)
			tw.tween_property(gem, "shine", 1.0, 0.6).from(0.0).set_delay(at + 0.25)

# Each worker's share as a small card edged in their colour, name over numbers;
# the day's best carrier and best shot in terracotta
func _crew_line(crew: Array) -> Control:
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", 12)
	var top_loads: int = crew.map(func(r): return r[1]).max()
	var top_foes: int = crew.map(func(r): return r[2]).max()
	for slot in crew.size():
		var r: Array = crew[slot]
		var card := PanelContainer.new()
		card.custom_minimum_size.x = 150
		var sb := UiStyle.box(Color(UiStyle.PARCHMENT_DEEP, 0.5), Vector2(14, 7), 3)
		sb.border_width_left = 4
		sb.border_color = _slot_colors[slot % _slot_colors.size()]
		card.add_theme_stylebox_override("panel", sb)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", -2)
		card.add_child(vb)
		var worker := _worker(r[0])
		var me: bool = r[0] == multiplayer.get_unique_id()
		var who: String = "You" if me \
			else (worker.trade_name() if worker != null else CharacterRig.TRADES[slot % CharacterRig.TRADES.size()])
		var name_l := _crew_label(who, UiStyle.INK)
		if me:
			name_l.add_theme_font_override("font", UiStyle.SPECTRAL_MEDIUM)
		var name_row := HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 6)
		var mark := CrewMark.make(11)   # the slot's shape, as over their head
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mark.set_mark(slot, _slot_colors[slot % _slot_colors.size()])
		name_row.add_child(mark)
		name_row.add_child(name_l)
		vb.add_child(name_row)
		var nums := HBoxContainer.new()
		nums.add_theme_constant_override("separation", 6)
		nums.add_child(_crew_num(tr_n("%d load", "%d loads", r[1]) % r[1], r[1] > 0 and r[1] == top_loads))
		nums.add_child(_crew_num("·", false, UiStyle.INK_MUTED))
		nums.add_child(_crew_num(tr_n("%d foe", "%d foes", r[2]) % r[2], r[2] > 0 and r[2] == top_foes))
		vb.add_child(nums)
		line.add_child(card)
	return line

func _crew_num(text: String, best: bool, color := UiStyle.INK_SOFT) -> Label:
	var l := _crew_label(text, UiStyle.TERRACOTTA if best else color)
	l.add_theme_font_size_override("font_size", 15)
	if best:
		l.add_theme_font_override("font", UiStyle.SPECTRAL_MEDIUM)
	return l

# Who built this stretch, from Neh 3's "next to him…" chain (StoryData.BUILDERS)
func _builders_line() -> Control:
	var i := GameState.SECTIONS.find(GameState.get_current_section())  # as the title above
	if i < 0 or i >= StoryData.BUILDERS.size():
		return null
	var l := Label.new()
	l.text = tr(StoryData.BUILDERS[i])
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = 640
	l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", UiStyle.SPECTRAL_MEDIUM)
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", UiStyle.INK_SOFT)
	return l

# A hairline between the tally's counts
func _rule_v(h: float) -> Control:
	var r := ColorRect.new()
	r.color = Color(UiStyle.RULE, 0.55)
	r.custom_minimum_size = Vector2(1, h)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _worker(id: int) -> Player:
	for p: Player in get_tree().get_nodes_in_group("players"):
		if p.worker_id() == id:
			return p
	return null

func _crew_label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"Body"
	l.text = text
	l.add_theme_color_override("font_color", color)
	return l

# Tick the number up from zero with a tap per step, then a pop when it lands
func _count_up(label: Label, target: int, fmt: Callable, delay: float) -> void:
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(Sfx.play.bind("tally"))
	tw.tween_method(func(v: float): label.text = fmt.call(int(v)), 0.0, float(target), TALLY_COUNT) 		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		label.text = fmt.call(target)
		label.pivot_offset = label.size * 0.5
		label.scale = Vector2.ONE * 1.18
		Sfx.play("tally_land"))
	tw.tween_property(label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _stat(value: String, caption: String, font_size := 0) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	var n := Label.new()
	n.theme_type_variation = &"Numeral"
	if font_size > 0:
		n.add_theme_font_size_override("font_size", font_size)
	n.text = value
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.add_theme_color_override("font_color", UiStyle.INK)
	var l := Label.new()
	l.theme_type_variation = &"Eyebrow"
	l.text = caption
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", UiStyle.TERRACOTTA)
	v.add_child(n)
	v.add_child(l)
	return v

func _on_crew_changed(size: int) -> void:
	gather_crew.text = tr("%d of %d builders here") % [size, NetworkManager.MAX_PLAYERS]

# Host, while gathering: how hard the enemy presses, and bots to fill the empty places —
# how many, and how good. Each row has a caption saying what the choice means.
# Built twice: in the gather panel (mouse only, like Begin — a pad's A is busy picking
# things up there) and in the pause menu (focusable, and usable mid-day).
func _build_bot_row(vb: Control, at: int, in_menu: bool) -> void:
	# Difficulty
	var diff := _bot_button("", in_menu)
	var diff_about := _host_caption()
	var diff_row := _host_row([diff])
	# Bots
	var label := Label.new()
	label.theme_type_variation = &"Caption"
	var fewer := _bot_button("−", in_menu)
	var more := _bot_button("+", in_menu)
	var skill := _bot_button("", in_menu)
	var skill_about := _host_caption()
	var bot_row := _host_row([label, fewer, more])
	var skill_row := _host_row([skill])
	# Gather panel: point a lone builder at the bots (playtest: nobody found them)
	var nudge := _host_caption()
	nudge.text = "Short of hands? Add bots to the crew."
	nudge.add_theme_color_override("font_color", UiStyle.INK)
	nudge.visible = false
	for c in [diff_row, diff_about, nudge, bot_row, skill_row, skill_about]:
		vb.add_child(c)
		vb.move_child(c, at)
		at += 1
	var refresh := func():
		nudge.visible = not in_menu and Settings.bot_count == 0 \
			and GameState.phase == GameState.Phase.GATHER
		var d: Dictionary = Settings.diff()
		diff.text = tr("Difficulty: %s") % tr(d["name"])
		diff_about.text = tr(d["about"])
		var sk: Dictionary = BotBrain.SKILLS[Settings.bot_skill]
		label.text = tr("Bots: %d") % Settings.bot_count
		skill.text = tr("Bot skill: %s") % tr(sk["name"])
		skill_about.text = tr(sk["about"])
		# Hidden, not removed: they hold the panel's width when there are no bots
		var has_bots := Settings.bot_count > 0
		skill.modulate.a = 1.0 if has_bots else 0.0
		skill.mouse_filter = Control.MOUSE_FILTER_STOP if has_bots else Control.MOUSE_FILTER_IGNORE
		if in_menu:
			skill.focus_mode = Control.FOCUS_ALL if has_bots else Control.FOCUS_NONE
		skill_about.modulate.a = 1.0 if has_bots else 0.0
		fewer.disabled = Settings.bot_count <= 0
		more.disabled = Settings.bot_count >= NetworkManager.MAX_PLAYERS - 1
	_host_refreshers.append(refresh)
	# Size to the widest choice, so cycling never resizes the panel around it
	var skill_texts: Array[String] = []
	var skill_abouts: Array[String] = []
	for s in BotBrain.SKILLS:
		skill_texts.append(tr("Bot skill: %s") % tr(s["name"]))
		skill_abouts.append(tr(s["about"]))
	var diff_texts: Array[String] = []
	var diff_abouts: Array[String] = []
	for d in Settings.DIFFICULTIES:
		diff_texts.append(tr("Difficulty: %s") % tr(d["name"]))
		diff_abouts.append(tr(d["about"]))
	_fit_widest(skill, skill_texts)
	_fit_widest(skill_about, skill_abouts)
	_fit_widest(diff, diff_texts)
	_fit_widest(diff_about, diff_abouts)
	var change := func(count: int, level: int):
		Settings.bot_count = clampi(count, 0, NetworkManager.MAX_PLAYERS - 1)
		Settings.bot_skill = level
		Settings.save()
		for r in _host_refreshers:
			r.call()
		bots_changed.emit()
	fewer.pressed.connect(func(): change.call(Settings.bot_count - 1, Settings.bot_skill))
	more.pressed.connect(func(): change.call(Settings.bot_count + 1, Settings.bot_skill))
	skill.pressed.connect(func(): change.call(Settings.bot_count, (Settings.bot_skill + 1) % BotBrain.SKILLS.size()))
	# Read by the server only (WaveManager, Enemy), so no refit or sync
	diff.pressed.connect(func():
		Settings.difficulty = (Settings.difficulty + 1) % Settings.DIFFICULTIES.size()
		Settings.save()
		for r in _host_refreshers:
			r.call())
	diff.tooltip_text = tr("Click to change")
	skill.tooltip_text = tr("Click to change")
	refresh.call()

# Everyone: which trade you work as (Trade) — one tile per trade, your own figure in each
# trade's dress; the caption says what yours is quicker at. Bots take the trades left
# over. Remembered for the next game.
const TRADE_TILE_PX := 46   # portrait size in a trade tile

func _build_trade_row(vb: Control, at: int, in_menu: bool) -> void:
	var tiles := HBoxContainer.new()
	tiles.alignment = BoxContainer.ALIGNMENT_CENTER
	tiles.add_theme_constant_override("separation", 6)
	var about := _host_caption()
	# The simple game has no trades: the row hides while it's in play (the host may switch)
	var show_row := func():
		if is_instance_valid(tiles):
			tiles.visible = GameState.trades_on()
			about.visible = GameState.trades_on()
	GameState.rules_changed.connect(show_row)
	show_row.call()
	vb.add_child(tiles)
	vb.move_child(tiles, at)
	vb.add_child(about)
	vb.move_child(about, at + 1)
	var group := ButtonGroup.new()
	var portraits: Array[CrewPortrait] = []
	for t in CharacterRig.TRADES.size():
		var tile := _trade_tile(t, group, in_menu)
		tiles.add_child(tile)
		portraits.append(tile.get_meta("portrait"))
		tile.pressed.connect(func(): NetworkManager.choose_trade(t))
	var mine := func() -> int:
		var me := _worker(multiplayer.get_unique_id())
		return me.trade if me != null else maxi(0, Settings.trade)
	var shown_color := [null]   # the colour the portraits wear (a new one re-dresses them)
	var refresh := func():
		var t: int = mine.call()
		for i in tiles.get_child_count():
			var tile := tiles.get_child(i) as Button
			tile.set_pressed_no_signal(i == t)   # no signal, so the group won't clear the rest
			# One person per trade: someone else's is greyed, tagged with their name
			var holder := NetworkManager.trade_holder(i, multiplayer.get_unique_id())
			tile.disabled = holder != 0 and i != t
			tile.tooltip_text = tr("Taken by %s") % _holder_name(holder) if tile.disabled else tr(Trade.ABOUT[i])
			tile.get_meta("paint").call()
		about.text = "%s  ·  %s" % [tr("Your trade: %s") % tr(CharacterRig.TRADES[t]), tr(Trade.ABOUT[t])]
		var me := _worker(multiplayer.get_unique_id())
		var c: Color = me.slot_color if me != null else UiStyle.RULE
		if shown_color[0] != c:
			shown_color[0] = c
			for i in portraits.size():
				portraits[i].set_worker(i, c)
	# The pick goes round the server and comes back with the crew list; Main re-slots first
	if not NetworkManager.crew_info_changed.is_connected(_refresh_rows_later):
		NetworkManager.crew_info_changed.connect(_refresh_rows_later)
	_host_refreshers.append(refresh)
	var about_texts: Array[String] = []
	for t in CharacterRig.TRADES.size():
		about_texts.append("%s  ·  %s" % [tr("Your trade: %s") % tr(CharacterRig.TRADES[t]), tr(Trade.ABOUT[t])])
	_fit_widest(about, about_texts)
	# Lost the race for a trade: say so for a moment, then the caption returns
	NetworkManager.trade_refused.connect(func(taken: int):
		if not is_instance_valid(about):
			return
		about.text = tr("%s was just taken. Pick another trade.") % tr(CharacterRig.TRADES[taken])
		get_tree().create_timer(2.5).timeout.connect(func():
			if is_instance_valid(about):
				refresh.call()), CONNECT_REFERENCE_COUNTED)
	refresh.call()

## Name for a trade's holder: their Steam name, else the colour slot they stand in
func _holder_name(id: int) -> String:
	var n := NetworkManager.name_of(id)
	if not n.is_empty():
		return n
	var w := _worker(id)
	return tr("Player %d") % (w.slot + 1) if w != null and "slot" in w else tr("another player")

# A trade to pick: the worker in its dress, its name under; the chosen one sits pressed
# into the parchment with a terracotta frame
func _trade_tile(t: int, group: ButtonGroup, focusable: bool) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = group
	b.focus_mode = Control.FOCUS_ALL if focusable else Control.FOCUS_NONE
	b.tooltip_text = tr(Trade.ABOUT[t])
	b.custom_minimum_size = Vector2(92, 0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pad := Vector2(4, 6)
	var off := UiStyle.bordered(UiStyle.box(Color(0, 0, 0, 0), pad, 3), Color(UiStyle.RULE, 0.55), 1)
	var hover := UiStyle.bordered(UiStyle.box(Color(UiStyle.TERRACOTTA, 0.07), pad, 3), UiStyle.TERRACOTTA, 1)
	var on := UiStyle.bordered(UiStyle.box(Color(UiStyle.PARCHMENT_DEEP, 0.9), pad, 3), UiStyle.TERRACOTTA, 2, 3)
	for s in ["normal", "disabled"]:
		b.add_theme_stylebox_override(s, off)
	b.add_theme_stylebox_override("hover", hover)
	for s in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(s, on)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_top = pad.y
	col.offset_bottom = -pad.y - 2
	b.add_child(col)
	var face := CrewPortrait.new()
	face.custom_minimum_size = Vector2(TRADE_TILE_PX, TRADE_TILE_PX)
	face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(face)
	var name_l := Label.new()
	name_l.text = CharacterRig.TRADES[t]
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # "Carregador de água" takes two lines
	name_l.add_theme_font_override("font", UiStyle.CINZEL_BOLD)
	name_l.add_theme_font_size_override("font_size", 12)
	name_l.add_theme_constant_override("line_spacing", -3)
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_l)
	var paint := func():
		name_l.add_theme_color_override("font_color", UiStyle.TERRACOTTA_DEEP if b.button_pressed \
			else (UiStyle.TERRACOTTA if b.is_hovered() and not b.disabled else UiStyle.INK_SOFT))
		face.modulate = Color(1, 1, 1, 0.3) if b.disabled \
			else (Color.WHITE if b.button_pressed or b.is_hovered() else Color(1, 1, 1, 0.72))
	b.toggled.connect(func(_on: bool): paint.call())
	b.mouse_entered.connect(paint)
	b.mouse_exited.connect(paint)
	paint.call()
	# A Button doesn't grow for its children: follow the column (a wrapped name is taller)
	var fit := func(): b.custom_minimum_size.y = col.get_combined_minimum_size().y + pad.y * 2 + 2
	col.resized.connect(fit)
	name_l.resized.connect(fit)
	fit.call()
	b.set_meta("portrait", face)
	b.set_meta("paint", paint)
	return b

func _refresh_rows_later() -> void:
	for r in _host_refreshers:
		r.call_deferred()

func _host_row(children: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	for c in children:
		row.add_child(c)
	return row

func _host_caption() -> Label:
	var l := Label.new()
	l.theme_type_variation = &"Caption"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", UiStyle.INK_SOFT)
	# Wraps inside the panel instead of widening it
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

const HOST_WRAP_PX := 400.0   # wrap width the caption height is reserved for (modal 440 less padding)

# Buttons: min width = widest candidate text (hidden/toggled controls keep their slot width).
# Labels wrap, so they reserve the tallest candidate's height instead and never set the width.
func _fit_widest(c: Control, texts: Array[String]) -> void:
	var font := c.get_theme_font("font")
	var px := c.get_theme_font_size("font_size")
	if font == null:
		return
	if c is Label:
		var h := 0.0
		for t in texts:
			h = maxf(h, font.get_multiline_string_size(t, HORIZONTAL_ALIGNMENT_CENTER, HOST_WRAP_PX, px).y)
		c.custom_minimum_size.y = ceilf(h)
		return
	var w := 0.0
	for t in texts:
		w = maxf(w, font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x)
	if c is Button:
		w += c.get_theme_stylebox("normal").get_minimum_size().x
		# Never wider than the panel: a long translation ellipsizes rather than widening it
		w = minf(w, HOST_WRAP_PX)
		c.clip_text = true
		c.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	c.custom_minimum_size.x = ceilf(w)

func _bot_button(text: String, focusable := false) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = &"GhostButton"
	b.focus_mode = Control.FOCUS_ALL if focusable else Control.FOCUS_NONE
	return b

# ── Joining ────────────────────────────────────────────────

var _joining: PanelContainer
var _joining_label: Label

# Top centre, only while someone is still loading in: who, so the rest know to wait
func _build_joining_plaque() -> void:
	_joining = PanelContainer.new()
	_joining.add_theme_stylebox_override("panel", UiStyle.plaque(Vector2(18, 8), 0.9))
	_joining.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Root.add_child(_joining)
	_joining.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 18)
	_joining.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_joining_label = Label.new()
	_joining_label.theme_type_variation = &"Body"
	_joining_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_joining_label.add_theme_color_override("font_color", UiStyle.INK_SOFT)
	_joining.add_child(_joining_label)
	_joining.hide()
	NetworkManager.crew_info_changed.connect(_refresh_joining)
	_refresh_joining()

func _refresh_joining() -> void:
	var lines: PackedStringArray = []
	for id: int in NetworkManager.loading_peers():
		var who := NetworkManager.name_of(id)
		lines.append(tr("%s is joining…") % who if not who.is_empty() else tr("A builder is joining…"))
	_joining_label.text = "\n".join(lines)
	var want := not lines.is_empty()
	if want and not _joining.visible:
		_joining.show()
		UiFx.fade_in(_joining, 0.2)
	elif not want:
		_joining.hide()
	# Anchored to its minimum size: re-centre as the text changes
	_joining.reset_size()
	_joining.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 18)

# ── Player cards ───────────────────────────────────────────

## `display` = their Steam name ("" = none); `loading` = still joining (game not loaded)
func set_player_present(slot: int, present: bool, is_local: bool, is_bot := false,
		display := "", loading := false, trade := -1) -> void:
	if slot >= _cards.size():
		return
	var card: Dictionary = _cards[slot]
	card.root.visible = present
	card.trade = trade
	_card_title(card)
	var who: String = tr("You") if is_local else (tr("Bot") if is_bot \
		else (display if not display.is_empty() else tr("Crew %s") % ROMAN[slot]))
	card.who.text = tr("%s · joining…") % who if loading else who
	card.root.modulate.a = 0.6 if loading else 1.0

## The trade under a card's name — or "Builder" for all with no trades in play (the simple game)
func _card_title(card: Dictionary) -> void:
	var t: int = card.trade if card.trade >= 0 else card.slot
	card.name.text = CharacterRig.TRADES[t % CharacterRig.TRADES.size()] if GameState.trades_on() else "Builder"

func set_player_health(slot: int, frac: float) -> void:
	if slot >= _cards.size():
		return
	var card: Dictionary = _cards[slot]
	card.bar.value = frac
	(card.fill as StyleBoxFlat).bg_color = UiStyle.OLIVE if frac > 0.6 \
		else (UiStyle.AMBER if frac > 0.3 else UiStyle.TERRACOTTA)

# What a worker carries shows over their head in the world; the card only flags trouble
func set_player_downed(slot: int, downed: bool) -> void:
	if slot >= _cards.size():
		return
	_cards[slot].carry.visible = downed
	_cards[slot].portrait.downed = downed

## What the worker has in their arms, as a small icon on their card ("" = nothing)
func set_player_carry(slot: int, kind: String) -> void:
	if slot >= _cards.size():
		return
	var icon: TagIcon = _cards[slot].load
	var k := kind.trim_suffix("s") if kind == "beams" else kind
	icon.modulate.a = 0.0 if k.is_empty() else 1.0
	if not k.is_empty() and icon.kind != k:
		icon.kind = k
		icon.queue_redraw()

func set_player_color(slot: int, color: Color, trade := -1) -> void:
	if slot >= _cards.size():
		return
	_slot_colors[slot] = color
	(_cards[slot].portrait as CrewPortrait).set_worker(trade if trade >= 0 else slot, color)
	(_cards[slot].mark as CrewMark).set_mark(slot, color)
	var card := (UiStyle.theme_card() as StyleBoxFlat).duplicate() as StyleBoxFlat
	card.content_margin_left = 10
	card.content_margin_top = 8
	card.content_margin_bottom = 9
	(_cards[slot].root as PanelContainer).add_theme_stylebox_override("panel", card)

# ── Controls hint ──────────────────────────────────────────

func _build_controls_hint() -> void:
	# Compact, tucked in the bottom-right corner: it used to sit mid-right, over the
	# wall and its tags. Above the invite panel when there is one.
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.plaque(Vector2(12, 9), 0.88))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 18)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	if NetworkManager.in_steam_lobby():
		panel.offset_bottom -= 72
		panel.offset_top -= 72
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	panel.add_child(vb)
	var key_box := UiStyle.bordered(UiStyle.box(UiStyle.PARCHMENT_DEEP, Vector2(7, 1), 3), UiStyle.RULE, 1, 2)
	var keys: Array[Label] = []
	for row: Array in CONTROLS:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		vb.add_child(hb)
		var key := Label.new()
		key.text = InputMode.key(row[0])
		keys.append(key)
		key.add_theme_font_override("font", UiStyle.CINZEL_SEMI)
		key.add_theme_font_size_override("font_size", 11)
		key.add_theme_color_override("font_color", UiStyle.INK)
		key.add_theme_stylebox_override("normal", key_box)
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key.custom_minimum_size.x = 64
		hb.add_child(key)
		var what := Label.new()
		what.theme_type_variation = &"Body"
		what.add_theme_font_size_override("font_size", 14)
		what.text = row[1]
		hb.add_child(what)
		if row[0] == "pause":
			_pause_what = what
		if row[0] == "horn":
			_horn_row = hb
	_controls = panel
	_refresh_controls()
	InputMode.changed.connect(func(_pad: bool):
		for i in keys.size():
			keys[i].text = InputMode.key(CONTROLS[i][0])
		_refresh_gather_hint())

func _refresh_controls() -> void:
	if _controls == null:
		return
	if _horn_row != null:
		_horn_row.visible = GameState.has_twist("horn")
	if _pause_what != null:
		_pause_what.text = "Pause · menu" if _solo() else "Menu"
	var early := GameState.phase == GameState.Phase.GATHER or GameState.current_day == 1 or GameState.festival
	var want := (early and not GameState.is_over()) or pause_menu.visible
	if want == _controls.visible:
		return
	if _controls_tween:
		_controls_tween.kill()
	if want:
		_controls.show()
		UiFx.fade_in(_controls, 0.2)
	else:
		_controls_tween = create_tween()
		_controls_tween.tween_property(_controls, "modulate:a", 0.0, 0.8)
		_controls_tween.tween_callback(_controls.hide)

func _build_player_cards() -> void:
	# The simple game has no trades: every card reads "Builder" (the host may switch mid-game)
	GameState.rules_changed.connect(func():
		for card in _cards:
			_card_title(card))
	for slot in MAX_SLOTS:
		var root := PanelContainer.new()
		root.theme_type_variation = &"Card"
		root.custom_minimum_size = Vector2(236, 0)
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.visible = false
		UiStyle.ornament(root, 4.0)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		root.add_child(hb)
		var portrait := CrewPortrait.new()
		portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(portrait)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 3)
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(vb)
		# "Downed" sits on the eyebrow line and the load icon always keeps its slot
		# (faded when empty), so the card never changes width mid-play
		var who_row := HBoxContainer.new()
		who_row.add_theme_constant_override("separation", 8)
		vb.add_child(who_row)
		var mark := CrewMark.make(13)   # the shape over their head, not just its colour
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		who_row.add_child(mark)
		var who := Label.new()
		who.theme_type_variation = &"Eyebrow"
		who.add_theme_font_size_override("font_size", 12)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		who_row.add_child(who)
		var carry := Label.new()
		carry.theme_type_variation = &"Caption"
		carry.add_theme_font_size_override("font_size", 12)
		carry.add_theme_color_override("font_color", UiStyle.TERRACOTTA)
		carry.text = "Downed"
		carry.visible = false
		who_row.add_child(carry)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 8)
		vb.add_child(top)
		var name_lbl := Label.new()
		name_lbl.add_theme_font_override("font", UiStyle.tracked(UiStyle.CINZEL_BOLD, 1))
		name_lbl.add_theme_font_size_override("font_size", 17)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(name_lbl)
		var load_icon := TagIcon.make("stone", 24)
		load_icon.modulate.a = 0.0
		load_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(load_icon)
		var bar := ProgressBar.new()
		bar.theme_type_variation = &"Meter"
		bar.custom_minimum_size = Vector2(0, 9)
		bar.max_value = 1.0
		bar.value = 1.0
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fill := UiStyle.box(UiStyle.OLIVE, Vector2.ZERO, 2)
		bar.add_theme_stylebox_override("fill", fill)
		vb.add_child(bar)
		players_row.add_child(root)
		_cards.append({ root = root, portrait = portrait, name = name_lbl, who = who, mark = mark,
			carry = carry, bar = bar, fill = fill, load = load_icon, trade = -1, slot = slot })

# ── Steam invite ───────────────────────────────────────────

# Bottom-right: toggle an in-game friend list to invite from, or copy the lobby
# code as a fallback
func _build_invite_panel() -> void:
	var anchor := VBoxContainer.new()
	anchor.add_theme_constant_override("separation", 8)
	$Root.add_child(anchor)
	anchor.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 18)
	anchor.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	anchor.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var list_panel := PanelContainer.new()
	list_panel.theme_type_variation = &"Card"
	list_panel.hide()
	anchor.add_child(list_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(260, 0)
	list_panel.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Card"
	anchor.add_child(panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	panel.add_child(hb)
	var lbl := Label.new()
	lbl.theme_type_variation = &"Eyebrow"
	lbl.text = "Crew"
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(lbl)
	var invite := Button.new()
	invite.theme_type_variation = &"PrimaryButton"
	invite.text = "Invite friends"
	invite.focus_mode = Control.FOCUS_NONE
	invite.pressed.connect(func():
		list_panel.visible = not list_panel.visible
		if list_panel.visible:
			_fill_friend_list(list, scroll))
	hb.add_child(invite)
	var copy := Button.new()
	copy.theme_type_variation = &"GhostButton"
	copy.text = "Copy code"
	copy.tooltip_text = tr("Lobby code %s") % NetworkManager.lobby_code()
	copy.focus_mode = Control.FOCUS_NONE
	copy.pressed.connect(func():
		DisplayServer.clipboard_set(NetworkManager.lobby_code())
		copy.text = "Copied")
	hb.add_child(copy)

func _fill_friend_list(list: VBoxContainer, scroll: ScrollContainer) -> void:
	for c in list.get_children():
		c.queue_free()
	var friends := NetworkManager.online_friends()
	if friends.is_empty():
		var none := Label.new()
		none.text = "No friends online"
		list.add_child(none)
	for f: Dictionary in friends:
		var b := Button.new()
		b.theme_type_variation = &"GhostButton"
		b.text = f.name + ("  · " + tr("in game") if f.in_game else "")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.clip_text = true
		b.pressed.connect(func():
			var ok := NetworkManager.invite_friend(f.id)
			b.text = "%s  · %s" % [f.name, tr("invited") if ok else tr("invite failed")]
			b.disabled = ok)
		list.add_child(b)
	# Grow with the list up to ~8 rows, then scroll
	scroll.custom_minimum_size.y = minf(maxf(friends.size(), 1) * 40.0, 320.0)

# ── Helpers ────────────────────────────────────────────────

func _flash(node: CanvasItem, tint: Color) -> void:
	var tw := node.create_tween()
	tw.tween_property(node, "self_modulate", tint, 0.08)
	tw.tween_property(node, "self_modulate", Color.WHITE, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
