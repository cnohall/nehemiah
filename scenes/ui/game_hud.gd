extends CanvasLayer

# In-game HUD. Reads GameState (mirrored on every peer) and is fed player/enemy
# numbers by Main. Player cards and the Steam invite panel are built in code.

signal begin_requested   # host pressed "Begin the work" (Main forwards to DayDirector)
signal bots_changed      # host changed Settings.bot_count / bot_skill (Main refits the crew)
signal ready_pressed         # local player is done with the dusk tally (Main → DayDirector)
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
const CREW_H        := 40.0    # …plus one line per worker's share (multiplayer)
const MARKS_H       := 64.0    # …plus the section's marks on its last day…
const READY_H       := 56.0    # …plus who's ready to go on
const SUB_LINE_H    := 28.0    # …plus each extra line under the title (days to spare, the campaign)
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
	["throw", "Sling — charge, then throw"],
	["horn", "Horn — call the crew"],   # only in sections with the horn
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
var _touch: TouchControls
var _pause_btn: Button
var _room_chip: Control
var _pause_begin: Button     # host, while gathering: start from the menu (gamepad path)
var _gather_hint: Label
var _pad_lost_note: Label   # pause menu line shown after the pad in use disconnects
var _tally: VBoxContainer
var _last_tally := {}   # the latest dusk numbers (a replay's end screen shows its marks)
var _horn_row: Control
var _pause_what: Label       # controls card: what the pause key does
var _host_refreshers: Array[Callable] = []   # bot / difficulty rows (gather panel + pause menu)
var _host_page: VBoxContainer   # phones: the menu's bot / difficulty rows, on a page of their own
var _hidden_for_host: Array[Control] = []
var _tally_band: CanvasItem   # second layer of the band: numbers stay legible over world labels
var _ready_row: ReadyRow      # under the tally: hold [E] to go on, who else is ready
var _tally_waiting: Array = []   # latest DayDirector ready state for the tally
var _slot_colors: Array[Color] = [Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]
var _next_line: Label        # day plaque: what to do next, for the local player
var _next_box: Control       # phones: the pill it moves into, bottom-centre
var _next_poll := 0.0
const NEXT_POLL := 0.25
const KNOCKED_MS := 4000
var _knocked_until := 0   # ticks (ms): "Next:" line says a finished piece fell
var _last_done := 0
var _last_total := 0
var _sun_row: HBoxContainer  # day plaque: the sun clock (GameState.sun)
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
	if TouchControls.enabled():
		_build_touch_controls()
	else:
		_build_controls_hint()
	_build_next_line()
	_build_next_caption()
	_build_compass()
	_build_sun_row()
	_build_joining_plaque()
	# The practice has no day to count or waves to warn of; its own plaque says the step
	_style_world = not Settings.diegetic_hud   # forces the first _apply_style
	_apply_style()
	# Under the banner and menus, over the world-facing plaques
	var alerts := OffscreenAlerts.new()
	$Root.add_child(alerts)
	$Root.move_child(alerts, banner.get_index())
	# Hold [Tab] / View: a chip over everything near that answers a press
	var lens := ActionLens.new()
	$Root.add_child(lens)
	$Root.move_child(lens, banner.get_index())
	add_child(BotDemo.new())   # "Watch the carpenter — two to a beam"
	if NetworkManager.in_steam_lobby():
		_build_invite_panel()
	if not NetworkManager.room_code().is_empty():
		_build_room_code()
	if Mobile.enabled():
		_apply_mobile_layout(alerts)
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
		if Mobile.enabled():
			_build_host_page(menu, at)
	$Root/PauseMenu/Center/Modal/VBox/SaveHint.visible = GameState.saves_campaign()
	# Someone joined a paused solo game: the world can't stay frozen for them
	NetworkManager.peer_connected.connect(func(_id: int):
		get_tree().paused = false
		$Root/PauseMenu/Center/Modal/VBox/Hint.text = "The game keeps running for your crew while this is open."
		_refresh_controls())
	NetworkManager.peer_disconnected.connect(func(_id: int): _refresh_controls())
	GameState.crew_changed.connect(_on_crew_changed)
	_on_crew_changed(GameState.crew_size)
	if Mobile.enabled():
		_compact_pause_menu()   # no focus ring on touch: nothing to hand focus back to
	else:
		settings.closed.connect($Root/PauseMenu/Center/Modal/VBox/Settings.grab_focus)
	_pad_lost_note = Label.new()
	_pad_lost_note.theme_type_variation = &"Caption"
	_pad_lost_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pad_lost_note.text = "Controller disconnected — reconnect it to carry on"
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
	_toggle_pause()

func _toggle_pause() -> void:
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
	# (phones tap the gather panel's own Begin; the menu wouldn't fit it)
	_show_host_page(false)
	_pause_begin.visible = multiplayer.is_server() and GameState.phase == GameState.Phase.GATHER 		and (InputMode.using_pad or not Mobile.enabled())
	# The menu carries "Begin the work" now; don't show the gather banner's copy behind it
	gather.modulate.a = 0.0
	# One primary action at a time
	$Root/PauseMenu/Center/Modal/VBox/Resume.theme_type_variation = &"GhostButton" if _pause_begin.visible else &"PrimaryButton"
	if not Mobile.enabled():   # no focus ring on touch
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
				invite.text = "Overlay off — use the Crew panel"
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
	_show_host_page(false)
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
	if _logged or GameState.attract or GameState.free_play():
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
	# Phones share one line with the day number: name only
	day_section.text = ("·  %s" % tr(section["name"])) if Mobile.enabled() \
		else "%s  ·  %s" % [tr(section["name"]), GameState.short_ref(section["ref"])]
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
		_show_banner(tr("The sun is low"), tr("Finish before the stars appear — the %s must stand tonight") % tr(GameState.get_current_section()["name"]) \
			if GameState.last_day_of_section() else tr("What isn't built by the stars waits for tomorrow"), 2.2)

func _process(delta: float) -> void:
	if _style_world != Settings.diegetic_hud:
		_apply_style()
	_place_compass()
	if _sun_row != null:
		_refresh_sun()
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
	if _next_box != null:
		_next_box.visible = _next_line.visible

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
		return "Down — a crewmate has to help you up"
	if Time.get_ticks_msec() < _knocked_until:
		return "A finished piece was knocked down — build it back up"
	var left := GameState.targets_total - GameState.targets_done
	# A saboteur strewed a pile: nothing comes from it until it's tidied
	if me.carried_kind.is_empty():
		var mess := get_tree().get_first_node_in_group("scattered_piles")
		if mess != null:
			return tr("The %s pile was strewn — tidy it (%s at the pile)") % [_material_name(mess.kind), InputMode.key("interact")]
	var site := SiteFocus.site()
	if site == null:
		# Only "done" when it is (playtest 2: players thought the wall stood and waited
		# for a day end that never came) — a piece knocked back down still counts
		if left <= 0:
			return "The stretch stands"
		return tr_n("%d piece still to finish — look for the amber footing", "%d pieces still to finish — look for the amber footings", left) % left
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
		return tr("Nothing needs %s now — drop it (%s)") % [_material_name(carry), InputMode.key("drop")]
	if GameState.active_build and site.can_build():
		return (tr("Build it up — %s at the gate") if at_gate else tr("Build it up — %s at the wall")) % InputMode.key("interact")
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
	var work_label := get_node_or_null("Root/DayPlaque/VBox/WorkRow/WorkLabel") as Label   # gone on phones
	if work_label != null:
		work_label.text = "The stretch" if GameState.sun_total > 0.0 else "Today's work"
	var working := GameState.phase == GameState.Phase.WORK
	work_row.visible = working
	phase_label.visible = not working
	match GameState.phase:
		GameState.Phase.GATHER:
			phase_label.text = "Gathering the crew"
		GameState.Phase.STORY:
			phase_label.text = ""
		GameState.Phase.DAWN:
			phase_label.text = "Dawn — ready the workers"
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
					sub += "\n" + tr(GameState.TWIST_INTRO.get(twist, "")).format({"horn": "[%s]" % InputMode.key("horn")})
				if GameState.BOONS.has(GameState.boon):
					var lines := GameState.boon_lines(GameState.boon)
					sub += "\n" + tr("The crew chose: %s") % tr(GameState.BOONS[GameState.boon]["title"])
					sub += "  ·  " + "  ·  ".join(lines["gain"] + lines["cost"])
			if GameState.sun_total > 0.0:
				var pos := GameState.day_in_section(GameState.current_day)
				if pos.x == 0:
					sub += "\n" + tr_n("Raise the whole stretch — %d day before the stars", "Raise the whole stretch — %d days before the stars", pos.y) % pos.y
				elif pos.x == pos.y - 1:
					sub += "\n" + tr("The last day of this stretch — it must stand before the stars appear")
				else:
					sub += "\n" + tr("%d of %d stand — %d days left") % [GameState.targets_done, GameState.targets_total, pos.y - pos.x]
			if first_day and GameState.dawn_saved():
				sub += "\n" + tr("Progress saved — Continue from the title screen")
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
	vb.get_node("Title").text = "The wall is finished" if won else ("The stars appeared" if stars else "The city is overrun")
	vb.get_node("Message").text = WIN_VERSE if won \
		else (tr("The %s was not finished by nightfall. Gather the workers and begin again.") % tr(GameState.get_current_section()["name"]) if stars \
		else tr("Too many enemies reached the inner city. Gather the workers and begin again."))
	vb.get_node("Ref").text = GameState.long_ref(WIN_VERSE_REF) if won else ""
	vb.get_node("Ref").visible = won
	var days_done := GameState.TOTAL_DAYS if won else GameState.current_day - 1
	var sections_done := GameState.SECTIONS.size() if won else GameState.current_section_index
	var stats: Control = vb.get_node("Stats")
	for c in stats.get_children():
		c.queue_free()
	stats.add_child(_stat(str(days_done), "Days built"))
	stats.add_child(_stat("%d / %d" % [sections_done, GameState.SECTIONS.size()], "Sections"))
	stats.add_child(_stat(str(GameState.breaches), "Breaches"))
	if sections_done > 0:
		stats.add_child(_stat("%d / %d" % [GameState.total_marks(), sections_done * GameState.MARKS.size()], "Marks"))
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

# ── End screen: the scribe's map ───────────────────────────

var _end_map: CircuitMap

# The run's map, worn by it (CircuitMap `aged`), fills the screen behind a parchment
# column on the left that holds the words, the reel and the choices. A win closes the
# ring (finale); otherwise the stretch reached pulses.
func _build_end_map(won: bool) -> void:
	if Mobile.enabled():
		return   # phones: the reel and the words fill the width, no room for the map
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
const REEL_PHONE := 0.38  # phones: the reel's column, as a share of the screen width

var _reel: Control
var _reel_tween: Tween
var _vote_note: Label
var _vote_buttons := {}   # choice → Button

# The run's stills (Highlights), one after another while the crew decides
# Phones: too short to stack it over the verdict, so it takes a column on the left
func _build_reel(vb: Control) -> void:
	if _reel:
		_reel.queue_free()
		_reel = null
	var phone := Mobile.enabled()
	var center := $Root/EndScreen/Center as Control
	center.anchor_left = 0.0
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
	if phone:   # fills its column, at most ~0.6 of the monitor size
		var col := get_viewport().get_visible_rect().size.x * REEL_PHONE - Mobile.safe_insets().x - 40.0
		pic.custom_minimum_size = REEL_SIZE * minf(col / REEL_SIZE.x, 0.62)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	frame.add_child(pic)
	var caption := Label.new()
	caption.theme_type_variation = &"Caption"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_color_override("font_color", UiStyle.INK_SOFT)
	caption.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # captions arrive translated
	reel.add_child(caption)
	_reel = reel
	if phone:
		caption.add_theme_font_size_override("font_size", 12)
		$Root/EndScreen.add_child(reel)
		reel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
		reel.anchor_right = REEL_PHONE
		reel.offset_left = Mobile.safe_insets().x + 16.0
		reel.offset_right = 0.0
		center.anchor_left = REEL_PHONE
	else:
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
	buttons.add_theme_constant_override("separation", 8 if Mobile.enabled() else 16)
	for b in _vote_buttons.values():
		b.queue_free()
	_vote_buttons.clear()
	var choices: Array = []   # [choice, label]
	if GameState.is_replay():
		choices.append(["again", "Play it again"])
		var next := GameState.replay_section + 1
		if won and next < GameState.SECTIONS.size():
			choices.append(["next", "Next stretch"])
	elif won:
		choices.append(["again", "Play again"])
	else:
		choices.append(["again", "Try the stretch again"])
	for i in choices.size():
		var b := Button.new()
		b.text = choices[i][1]
		b.custom_minimum_size.x = 0 if Mobile.enabled() else 220
		b.theme_type_variation = &"PrimaryButton" if i == 0 else &"GhostButton"
		var choice: String = choices[i][0]
		b.pressed.connect(func(): vote_cast.emit(choice))
		buttons.add_child(b)
		buttons.move_child(b, i)
		_vote_buttons[choice] = b
	(vb.get_node("Buttons/MenuButton") as Button).theme_type_variation = &"GhostButton"
	if _vote_note == null:
		_vote_note = Label.new()
		_vote_note.theme_type_variation = &"Caption"
		_vote_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_vote_note.add_theme_color_override("font_color", UiStyle.INK_MUTED)
		vb.add_child(_vote_note)
	_vote_note.text = "" if _solo() else tr("The host's pick decides — or most of the crew")

## DayDirector.votes_changed: how many want what
func set_votes(votes: Dictionary) -> void:
	if _vote_note == null:
		return
	var people := 1 + multiplayer.get_peers().size()
	var lines: PackedStringArray = []
	for choice: String in _vote_buttons:
		var n := votes.values().count(choice)
		if n > 0:
			lines.append(tr("%s — %d of %d") % [tr(_vote_buttons[choice].text), n, people])
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
		vb.get_node("Message").text = (tr("A new best for this stretch — %d of 3 marks.") if GameState.rating_improved 			else tr("%d of 3 marks. Your best here stays as it was.")) % got
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
	var sub := tr("Not one enemy got through.") if stats["breaches"] == 0 		else tr_n("%d slipped through — but the wall stands.", "%d slipped through — but the wall stands.", stats["breaches"]) % stats["breaches"]
	var unfinished: int = stats.get("unfinished", 0)
	if unfinished > 0:
		# The stars came first: the day ends, the rest waits for tomorrow
		title = tr("Nightfall on day %d") % day
		sub = tr_n("The stars appeared — %d wall piece left for tomorrow.", "The stars appeared — %d wall pieces left for tomorrow.", unfinished) % unfinished
	# The whole section is done (rated) — say so, and how many days it had to spare
	elif stats.has("marks"):
		title = tr("The %s stands") % tr(section["name"])
		var lost: int = stats["section_breaches"]
		sub = tr("Not one enemy got through.") if lost == 0 \
			else tr_n("%d slipped through — but the wall stands.", "%d slipped through — but the wall stands.", lost) % lost
		sub = tr("Section %d of %d complete  ·  %s") % [GameState.current_section_index + 1,
			GameState.SECTIONS.size(), sub]
		var spare: int = stats.get("spare", 0)
		if GameState.sun_total > 0.0 and spare > 0:
			sub += "\n" + tr_n("Finished with %d day to spare", "Finished with %d days to spare", spare) % spare
	# Where the campaign stands: the far goal in view every evening (a pull to day 52)
	if not GameState.is_replay() and not GameState.attract:
		var stood := GameState.current_section_index + (1 if stats.has("marks") else 0)
		var days_left := GameState.TOTAL_DAYS - day
		sub += "\n" + tr("%d of %d stretches stand  ·  %d days to the fifty-second") % [stood, GameState.SECTIONS.size(), days_left]

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 56)
	_tally.add_child(row)
	# A stretch that stands counts the whole stretch, not just its last day
	var rated := stats.has("marks")
	var pre := "section_" if rated else ""
	var secs := int(stats[pre + "time"])
	var counts: Array = [
		[secs, "Time", func(v: int): return "%d:%02d" % [v / 60, v % 60]],
		[stats[pre + "loads"], "Loads carried", func(v: int): return str(v)],
		[stats[pre + "foes"], "Foes felled", func(v: int): return str(v)],
	]
	if stats.get("scattered", 0) > 0 and not rated:
		counts.append([stats["scattered"], "Piles scattered", func(v: int): return str(v)])
	for i in counts.size():
		var cell := _stat(counts[i][2].call(0), counts[i][1])
		row.add_child(cell)
		_count_up(cell.get_child(0), counts[i][0], counts[i][2], i * TALLY_STEP + 0.5)

	var crew: Array = stats[pre + "crew"]
	if crew.size() > 1:
		_tally.add_child(_crew_line(crew))
	if rated:
		_tally.add_child(_marks_line(stats))
	# The tally stays until everyone is ready (playtest 2) — the title screen's crew
	# has nobody to ask, so there it fades as before
	var waits := not GameState.attract
	if waits:
		_ready_row = ReadyRow.new(false)
		_ready_row.holdable = true
		_ready_row.ready_pressed.connect(ready_pressed.emit)
		_ready_row.begin_now.connect(begin_now_requested.emit)
		_tally.add_child(_ready_row)
		_ready_row.set_waiting(_tally_waiting)

	banner.offset_bottom = BANNER_H + TALLY_H + (CREW_H if crew.size() > 1 else 0.0) 		+ (MARKS_H if rated else 0.0) + (READY_H if waits else 0.0) 		+ sub.count("
") * SUB_LINE_H
	_tally.show()
	_show_banner(title, sub, -1.0 if waits else TALLY_HOLD, true)
	UiFx.stagger(_tally.get_children(), 0.45, 0.12, 0.3)

# The section's three marks, each with what earned it (or what it needed)
func _marks_line(stats: Dictionary) -> Control:
	var mask: int = stats["marks"]
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", 44)
	var secs := int(stats["section_time"])
	var par := int(stats["par"])
	var details := {
		GameState.Mark.PACE: tr("%d:%02d of %d:%02d") % [secs / 60, secs % 60, par / 60, par % 60],
		GameState.Mark.CLEAN: tr("all through the section") if mask & GameState.Mark.CLEAN 			else tr_n("%d got through", "%d got through", stats["section_breaches"]) % stats["section_breaches"],
		GameState.Mark.SOUND: tr("%d%% sound") % roundi(stats["wall"] * 100.0),
	}
	for m: int in GameState.MARKS:
		var earned := bool(mask & m)
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 10)
		var gem := MarkGem.new(earned, 22.0)
		gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.add_child(gem)
		var text := VBoxContainer.new()
		text.add_theme_constant_override("separation", -2)
		text.add_child(_crew_label(GameState.MARK_NAMES[m], UiStyle.TERRACOTTA if earned else UiStyle.INK_MUTED))
		var detail := _crew_label(details[m], UiStyle.INK_SOFT if earned else Color(UiStyle.INK_MUTED, 0.8))
		detail.add_theme_font_size_override("font_size", 15)
		text.add_child(detail)
		chip.add_child(text)
		line.add_child(chip)
	return line

# Each worker's share, in their colour; the day's best carrier and best shot in terracotta
func _crew_line(crew: Array) -> Control:
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", 30)
	var top_loads: int = crew.map(func(r): return r[1]).max()
	var top_foes: int = crew.map(func(r): return r[2]).max()
	for slot in crew.size():
		var r: Array = crew[slot]
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 8)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.color = _slot_colors[slot % _slot_colors.size()]
		chip.add_child(swatch)
		var worker := _worker(r[0])
		var who: String = "You" if r[0] == multiplayer.get_unique_id() \
			else (worker.trade_name() if worker != null else CharacterRig.TRADES[slot % CharacterRig.TRADES.size()])
		chip.add_child(_crew_label(who, UiStyle.INK))
		chip.add_child(_crew_label(tr_n("%d load", "%d loads", r[1]) % r[1], UiStyle.TERRACOTTA if r[1] > 0 and r[1] == top_loads else UiStyle.INK_SOFT))
		chip.add_child(_crew_label("·", UiStyle.INK_MUTED))
		chip.add_child(_crew_label(tr_n("%d foe", "%d foes", r[2]) % r[2], UiStyle.TERRACOTTA if r[2] > 0 and r[2] == top_foes else UiStyle.INK_SOFT))
		line.add_child(chip)
	return line

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

func _stat(value: String, caption: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	var n := Label.new()
	n.theme_type_variation = &"Numeral"
	n.text = value
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.add_theme_color_override("font_color", UiStyle.INK)
	var l := Label.new()
	l.theme_type_variation = &"Eyebrow"
	l.text = caption
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", UiStyle.TERRACOTTA)
	if Mobile.enabled():
		n.add_theme_font_size_override("font_size", 26)
		l.add_theme_font_size_override("font_size", 11)
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
	var bot_row := _host_row([label, fewer, more, skill])
	# Gather panel: point a lone builder at the bots (playtest: nobody found them)
	var nudge := _host_caption()
	nudge.text = "Short of hands? Add bots to the crew."
	nudge.add_theme_color_override("font_color", UiStyle.INK)
	nudge.visible = false
	var rows: Array[Control] = [diff_row, diff_about, nudge, bot_row, skill_about]
	var summary: Button = null
	if not in_menu and Mobile.enabled():
		# Phones: the gather panel keeps the world in view — one line saying how the crew
		# is set, which opens the game menu's crew page to change it
		var tucked := VBoxContainer.new()
		tucked.visible = false
		for c in [diff_row, diff_about, bot_row, skill_about]:
			tucked.add_child(c)
		summary = _bot_button("")
		summary.pressed.connect(func():
			Mobile.haptic()
			_open_pause()
			_show_host_page(true))
		rows = [nudge, summary, tucked]
	for c in rows:
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
		skill.visible = Settings.bot_count > 0
		skill_about.visible = Settings.bot_count > 0
		if summary:
			summary.text = diff.text + "  ·  " + label.text
		fewer.disabled = Settings.bot_count <= 0
		more.disabled = Settings.bot_count >= NetworkManager.MAX_PLAYERS - 1
	_host_refreshers.append(refresh)
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

# Phones: the game menu is too short for the crew rows under Resume, so they go on a
# second page behind one button — the rule and the five rows from _build_bot_row, then Back
func _build_host_page(menu: VBoxContainer, at: int) -> void:
	_host_page = VBoxContainer.new()
	_host_page.add_theme_constant_override("separation", 8)
	_host_page.visible = false
	var rows := menu.get_children().slice(at + 1, at + 6)
	menu.get_child(at).queue_free()   # the rule: the page has its own heading
	menu.add_child(_host_page)
	menu.move_child(_host_page, at)
	for r: Control in rows:
		r.reparent(_host_page)
	var back := Button.new()
	back.text = "Back"
	back.theme_type_variation = &"GhostButton"
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(_show_host_page.bind(false))
	_host_page.add_child(back)
	var open := Button.new()
	open.text = "Crew and difficulty"
	open.theme_type_variation = &"GhostButton"
	open.focus_mode = Control.FOCUS_NONE
	open.pressed.connect(_show_host_page.bind(true))
	menu.add_child(open)
	menu.move_child(open, _host_page.get_index())

func _show_host_page(on: bool) -> void:
	if _host_page == null or _host_page.visible == on:
		return
	var vb := $Root/PauseMenu/Center/Modal/VBox
	if on:
		Mobile.haptic()
		_hidden_for_host.clear()
		for c: Control in vb.get_children():
			if c.visible and c not in [vb.get_node("Eyebrow"), vb.get_node("Title"), _pad_lost_note]:
				c.hide()
				_hidden_for_host.append(c)
		vb.get_node("Title").text = "Crew"
	else:
		for c in _hidden_for_host:
			c.show()
		_hidden_for_host.clear()
		vb.get_node("Title").text = "Paused" if _solo() else "Menu"
	_host_page.visible = on

# Everyone: which trade you work as (Trade) — one tile per trade, your own figure in each
# trade's dress; the caption says what yours is quicker at. Bots take the trades left
# over. Remembered for the next game.
const TRADE_TILE_PX := 46   # portrait size in a trade tile

func _build_trade_row(vb: Control, at: int, in_menu: bool) -> void:
	var tiles := HBoxContainer.new()
	tiles.alignment = BoxContainer.ALIGNMENT_CENTER
	tiles.add_theme_constant_override("separation", 6)
	var about := _host_caption()
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
	refresh.call()

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
			else (UiStyle.TERRACOTTA if b.is_hovered() else UiStyle.INK_SOFT))
		face.modulate = Color.WHITE if b.button_pressed or b.is_hovered() else Color(1, 1, 1, 0.72)
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
	return l

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
	card.name.text = CharacterRig.TRADES[(trade if trade >= 0 else slot) % CharacterRig.TRADES.size()]
	var who: String = tr("You") if is_local else (tr("Bot") if is_bot \
		else (display if not display.is_empty() else tr("Crew %s") % ROMAN[slot]))
	card.who.text = tr("%s · joining…") % who if loading else who
	card.root.modulate.a = 0.6 if loading else 1.0

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
	icon.visible = not k.is_empty()
	if icon.visible and icon.kind != k:
		icon.kind = k
		icon.queue_redraw()

func set_player_color(slot: int, color: Color, trade := -1) -> void:
	if slot >= _cards.size():
		return
	_slot_colors[slot] = color
	(_cards[slot].portrait as CrewPortrait).set_worker(trade if trade >= 0 else slot, color)
	var card := (UiStyle.theme_card() as StyleBoxFlat).duplicate() as StyleBoxFlat
	if Mobile.enabled():
		card.content_margin_left = 5
		card.content_margin_right = 8
		card.content_margin_top = 4
		card.content_margin_bottom = 4
	else:
		card.content_margin_left = 10
		card.content_margin_top = 8
		card.content_margin_bottom = 9
	(_cards[slot].root as PanelContainer).add_theme_stylebox_override("panel", card)

# ── Controls hint ──────────────────────────────────────────

# Phones: on-screen stick + buttons instead of the key legend. Player cards move
# to the top-left (next to the pause button) so the stick's corner stays clear.
func _build_touch_controls() -> void:
	_touch = TouchControls.new()
	_touch.blockers = [pause_menu, settings, end_screen]
	_touch.passthrough = [gather]
	$Root.add_child(_touch)
	$Root.move_child(_touch, banner.get_index())

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
	for slot in MAX_SLOTS:
		var root := PanelContainer.new()
		root.theme_type_variation = &"Card"
		root.custom_minimum_size = Vector2(120 if Mobile.enabled() else 236, 0)
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
		var who := Label.new()
		who.theme_type_variation = &"Eyebrow"
		who.add_theme_font_size_override("font_size", 12)
		vb.add_child(who)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 8)
		vb.add_child(top)
		var name_lbl := Label.new()
		name_lbl.add_theme_font_override("font", UiStyle.tracked(UiStyle.CINZEL_BOLD, 2 if Mobile.enabled() else 1))
		name_lbl.add_theme_font_size_override("font_size", 12 if Mobile.enabled() else 17)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(name_lbl)
		var load_icon := TagIcon.make("stone", 24)
		load_icon.visible = false
		load_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(load_icon)
		var carry := Label.new()
		carry.theme_type_variation = &"Caption"
		carry.add_theme_font_size_override("font_size", 12 if Mobile.enabled() else 14)
		carry.add_theme_color_override("font_color", UiStyle.TERRACOTTA)
		carry.text = "Downed"
		carry.visible = false
		top.add_child(carry)
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
		if Mobile.enabled():
			# Phones: a small portrait and the health bar; the world already shows who's who
			root.custom_minimum_size = Vector2.ZERO
			hb.add_theme_constant_override("separation", 6)
			portrait.custom_minimum_size = Vector2(34, 34)
			who.hide()
			name_lbl.hide()
			bar.custom_minimum_size = Vector2(50, 6)
		players_row.add_child(root)
		_cards.append({ root = root, portrait = portrait, name = name_lbl, who = who,
			carry = carry, bar = bar, fill = fill, load = load_icon })

# ── EOS room code ──────────────────────────────────────────

# The code friends type to join. Bottom-right on PC; a tappable chip on phones.
func _build_room_code() -> void:
	if Mobile.enabled():
		_build_room_chip()
		return
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Card"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 18)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	panel.add_child(hb)
	var lbl := Label.new()
	lbl.theme_type_variation = &"Eyebrow"
	lbl.text = "Room"
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(lbl)
	var code := Label.new()
	code.text = NetworkManager.room_code()
	code.add_theme_font_override("font", UiStyle.tracked(UiStyle.CINZEL_BOLD, 4))
	code.add_theme_font_size_override("font_size", 28)
	code.add_theme_color_override("font_color", UiStyle.INK)
	hb.add_child(code)

# Phones: a tappable chip beside the pause button — tap copies the code to paste
# into a chat app; a check mark confirms.
func _build_room_chip() -> void:
	var chip := Button.new()
	chip.focus_mode = Control.FOCUS_NONE
	chip.icon = UiIcons.get_icon("copy", 18)
	chip.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	chip.add_theme_constant_override("h_separation", 10)
	chip.add_theme_font_override("font", UiStyle.tracked(UiStyle.CINZEL_BOLD, 3))
	chip.add_theme_font_size_override("font_size", 16)
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		chip.add_theme_color_override(c, UiStyle.INK)
	for c: String in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color", "icon_hover_pressed_color"]:
		chip.add_theme_color_override(c, UiStyle.INK_SOFT)
	var pad := Vector2(16, 10)
	var normal := UiStyle.shadowed(UiStyle.bordered(
		UiStyle.box(Color(UiStyle.PARCHMENT, 0.92), pad, 24), Color(UiStyle.RULE, 0.6), 1), 6, 0.18, 2.0)
	chip.add_theme_stylebox_override("normal", normal)
	chip.add_theme_stylebox_override("hover", normal)
	chip.add_theme_stylebox_override("focus", UiStyle.empty())
	var down := UiStyle.bordered(UiStyle.box(UiStyle.PARCHMENT_DEEP, pad, 24), UiStyle.TERRACOTTA, 1)
	chip.add_theme_stylebox_override("pressed", down)
	chip.add_theme_stylebox_override("hover_pressed", down)
	chip.text = NetworkManager.room_code()
	chip.tooltip_text = "Room code — tap to copy"
	chip.custom_minimum_size.y = 48
	chip.pressed.connect(func():
		DisplayServer.clipboard_set(NetworkManager.room_code())
		Mobile.haptic()
		chip.icon = UiIcons.get_icon("check", 18)
		get_tree().create_timer(1.6).timeout.connect(func():
			if is_instance_valid(chip):
				chip.icon = UiIcons.get_icon("copy", 18)))
	$Root.add_child(chip)
	_room_chip = chip

# ── Phone layout ───────────────────────────────────────────

# The scene is laid out for a 1080p monitor; on phones the UI is in dp (≈ 923×411
# landscape), so the plaques trim to essentials and hug the safe-area edges:
#   [II][ROOM ⧉]        [ Day plaque ]        [Threat]
#   crew cards                                  (world)
#   (stick zone)       [ Gather/Begin ]     (action cluster)
func _apply_mobile_layout(alerts: OffscreenAlerts) -> void:
	$Root.theme = Mobile.theme
	var s := Mobile.safe_insets()
	var left := s.x + 12.0
	var right := s.z + 12.0
	var top := s.y + 10.0

	_pause_btn = UiIcons.button("pause", "Menu")
	_pause_btn.pressed.connect(func():
		Mobile.haptic()
		_toggle_pause())
	$Root.add_child(_pause_btn)
	$Root.move_child(_pause_btn, banner.get_index())
	_pause_btn.position = Vector2(left, top)
	var pass_list: Array[Control] = [gather, _pause_btn]
	if _room_chip:
		$Root.move_child(_room_chip, banner.get_index())
		_room_chip.position = Vector2(left + 58.0, top)
		pass_list.append(_room_chip)
	if _touch:
		_touch.passthrough = pass_list

	# Day — a slim top-centre bar: "DAY 1/52 · Sheep Gate" over today's progress.
	# The world (wall stages, their labels) lives right under it, so it stays low.
	var day := $Root/DayPlaque as Control
	day.add_theme_stylebox_override("panel", UiStyle.plaque(Vector2(14, 7), 0.9))
	day.set_anchors_preset(Control.PRESET_CENTER_TOP)
	day.grow_horizontal = Control.GROW_DIRECTION_BOTH
	day.custom_minimum_size.x = 300
	day.offset_left = -150
	day.offset_right = 150
	day.offset_top = top
	day.offset_bottom = top
	$Root/DayPlaque/VBox.add_theme_constant_override("separation", 3)
	var day_row := $Root/DayPlaque/VBox/DayRow as HBoxContainer
	day_row.add_theme_constant_override("separation", 6)
	$Root/DayPlaque/VBox/DayRow/DayWord.add_theme_font_size_override("font_size", 11)
	day_number.add_theme_font_size_override("font_size", 20)
	day_of.add_theme_font_size_override("font_size", 11)
	day_section.reparent(day_row)
	day_section.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	day_section.add_theme_font_size_override("font_size", 13)
	circuit.hide()    # the 52-day strip is desktop detail; the day number says it
	$Root/DayPlaque/VBox/WorkRow/WorkLabel.hide()
	work_count.add_theme_font_size_override("font_size", 12)
	# Today's progress joins the day line: one row, so the plaque stays a slim strip
	# and hides less of the wall's own tags up-screen
	work_row.reparent(day_row)
	work_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	work_bar.custom_minimum_size = Vector2(64, 5)
	phase_label.add_theme_font_size_override("font_size", 11)
	work_row.add_theme_constant_override("separation", 6)

	# Threat — top right, same height as the day bar: the breach pips
	threat.add_theme_stylebox_override("panel", UiStyle.plaque(Vector2(12, 7), 0.9))
	threat.custom_minimum_size.x = 150
	threat.offset_left = -(150 + right)
	threat.offset_right = -right
	threat.offset_top = top
	threat.offset_bottom = top
	$Root/ThreatPlaque/VBox.add_theme_constant_override("separation", 3)
	$Root/ThreatPlaque/VBox/BreachRow.hide()   # the pips carry the count
	breach_pips.custom_minimum_size.y = 12
	breach_pips.tooltip_text = "City breaches"

	# Crew — a column under the pause button, above the thumb stick
	var crew := VBoxContainer.new()
	crew.add_theme_constant_override("separation", 6)
	crew.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Root.add_child(crew)
	$Root.move_child(crew, players_row.get_index())
	for card in players_row.get_children():
		card.reparent(crew)
	crew.position = Vector2(left, top + 60.0)

	# Gather — bottom centre, between the stick and the action cluster
	gather.custom_minimum_size.x = 300
	gather.offset_left = -150
	gather.offset_right = 150
	gather.offset_bottom = -(s.w + 14.0)
	gather.offset_top = gather.offset_bottom
	$Root/GatherPanel/VBox.add_theme_constant_override("separation", 4)
	$Root/GatherPanel/VBox/Eyebrow.hide()   # the day bar already says it

	# Next step — a pill bottom-centre (where Gather was) instead of a third line on the
	# day bar: the wall and its tags are usually up-screen, under the top plaques
	_next_box = PanelContainer.new()
	_next_box.add_theme_stylebox_override("panel", UiStyle.plaque(Vector2(14, 6), 0.9))
	_next_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_next_box.visible = false
	$Root.add_child(_next_box)
	$Root.move_child(_next_box, gather.get_index())
	_next_line.reparent(_next_box, false)
	_next_line.autowrap_mode = TextServer.AUTOWRAP_OFF
	_next_line.custom_minimum_size.x = 0
	_next_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_next_line.add_theme_font_size_override("font_size", 14)
	_next_box.anchor_left = 0.5
	_next_box.anchor_right = 0.5
	_next_box.anchor_top = 1.0
	_next_box.anchor_bottom = 1.0
	_next_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_next_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_next_box.offset_left = 0.0
	_next_box.offset_right = 0.0
	_next_box.offset_bottom = -(s.w + 14.0)
	_next_box.offset_top = _next_box.offset_bottom

	# Day banner — below the plaques, smaller type
	banner.anchor_top = 0.3
	banner.anchor_bottom = 0.3
	banner.offset_bottom = 96
	banner_title.add_theme_font_size_override("font_size", 32)
	banner_sub.add_theme_font_size_override("font_size", 15)
	for n: Control in [$Root/Banner/VBox/TitleRow/RuleL, $Root/Banner/VBox/TitleRow/RuleR]:
		n.custom_minimum_size.x = 56
	$Root/Banner/VBox/TitleRow.add_theme_constant_override("separation", 16)

	# End screen
	var vb := $Root/EndScreen/Center/VBox as VBoxContainer
	vb.custom_minimum_size.x = 480   # fits beside the reel's column
	(vb.get_node("Buttons/MenuButton") as Button).custom_minimum_size.x = 0
	vb.add_theme_constant_override("separation", 8)
	vb.get_node("Eyebrow").add_theme_font_size_override("font_size", 12)
	vb.get_node("Title").add_theme_font_size_override("font_size", 28)
	vb.get_node("Title").autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.get_node("Message").add_theme_font_size_override("font_size", 15)
	vb.get_node("Stats").add_theme_constant_override("separation", 20)
	vb.get_node("StatsGap").custom_minimum_size.y = 0
	vb.get_node("ButtonGap").custom_minimum_size.y = 4
	vb.get_node("Rule").custom_minimum_size.x = 260


	# Edge pointers stay clear of the plaques and the action cluster
	alerts.margin_side = 40.0 + maxf(s.x, s.z)
	alerts.margin_top = top + 90.0
	alerts.margin_bottom = 60.0 + s.w

# Phones: the game menu, compact — Settings and Leave share a row, so it fits a 360dp
# screen. Runs last in _ready: the rows it moves are wired up by path before it.
func _compact_pause_menu() -> void:
	var pm := $Root/PauseMenu/Center/Modal/VBox as VBoxContainer
	$Root/PauseMenu/Center/Modal.custom_minimum_size.x = 420
	pm.get_node("Hint").custom_minimum_size.x = 0
	pm.get_node("Hint").add_theme_font_size_override("font_size", 14)
	pm.get_node("Gap").hide()
	pm.add_theme_constant_override("separation", 8)
	var pair := HBoxContainer.new()
	pair.name = "Pair"
	pair.add_theme_constant_override("separation", 8)
	pm.add_child(pair)
	for n: String in ["Settings", "Leave"]:
		var b := pm.get_node(n) as Button
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.reparent(pair)
	pm.get_node("Resume").focus_mode = Control.FOCUS_NONE

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
