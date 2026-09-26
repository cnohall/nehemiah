extends CanvasLayer

# In-game HUD. Reads GameState (mirrored on every peer) and is fed player/enemy
# numbers by Main. Player cards and the Steam invite panel are built in code.

signal begin_requested   # host pressed "Begin the work" (Main forwards to DayDirector)

const MENU_SCENE    := "res://scenes/ui/main_menu.tscn"
const BANNER_HOLD   := 3.2
# Dusk tally: waits for the cheer and slow-mo to land, then counts the day up
const TALLY_DELAY   := 0.6
const TALLY_HOLD    := 5.6
const TALLY_COUNT   := 0.55    # seconds each number takes to count up
const TALLY_STEP    := 0.3     # between one number starting and the next
const BANNER_PAD    := 28.0    # space above and below the banner text
const BANNER_H      := 150.0   # Banner offset_bottom: title + sub…
const TALLY_H       := 118.0   # …plus the numbers row…
const CREW_H        := 40.0    # …plus one line per worker's share (multiplayer)
const MARKS_H       := 64.0    # …plus the section's marks on its last day
const BANNER_Y      := 0.2     # Banner anchor: dawn banners up top…
const TALLY_Y       := 0.6     # …the tally low, clear of the cheering crew mid-screen
const MAX_SLOTS     := 4
const ROMAN         := ["I", "II", "III", "IV"]
const WIN_VERSE     := "“So the wall was completed on the 25th day of Elul, in 52 days.”"
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
	["pause", "Menu"],
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
var _tally_band: CanvasItem   # second layer of the band: numbers stay legible over world labels
var _slot_colors: Array[Color] = [Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]
var _next_line: Label        # day plaque: what to do next, for the local player
var _next_poll := 0.0
const NEXT_POLL := 0.25

func _ready() -> void:
	for p: Control in [$Root/DayPlaque, $Root/ThreatPlaque, $Root/GatherPanel, $Root/PauseMenu/Center/Modal]:
		UiStyle.ornament(p)
	_build_player_cards()
	_build_controls_hint()
	_build_next_line()
	# Under the banner and menus, over the world-facing plaques
	var alerts := OffscreenAlerts.new()
	$Root.add_child(alerts)
	$Root.move_child(alerts, banner.get_index())
	if NetworkManager.in_steam_lobby():
		_build_invite_panel()
	elif NetworkManager.in_online_room():
		_build_room_panel()
	breach_pips.count = GameState.MAX_BREACHES
	day_of.text = "of %d" % GameState.TOTAL_DAYS
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
	GameState.crew_changed.connect(_on_crew_changed)
	_on_crew_changed(GameState.crew_size)
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

func _unhandled_input(event: InputEvent) -> void:
	# B / Esc backs out of the menu, like every other screen
	var back := event.is_action_pressed("ui_cancel") and not event.is_action_pressed("pause")
	if back and pause_menu.visible and not settings.visible:
		get_viewport().set_input_as_handled()
		_close_pause()
		return
	if not event.is_action_pressed("pause") or end_screen.visible or GameState.phase == GameState.Phase.STORY:
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
	if end_screen.visible or GameState.phase == GameState.Phase.STORY:
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
		_gather_hint.text = "or press %s to begin" % InputMode.key("pause")

func _close_pause() -> void:
	pause_menu.hide()
	gather.modulate.a = 1.0
	settings.hide()
	_pad_lost_note.hide()
	InputMode.set_menu_open(false)
	_refresh_controls()

func _exit_tree() -> void:
	InputMode.set_menu_open(false)

func _leave() -> void:
	NetworkManager.disconnect_session()
	GameState.reset()
	get_tree().change_scene_to_file(MENU_SCENE)

# ── Day / Section ──────────────────────────────────────────

func refresh_day(day: int) -> void:
	var section := GameState.get_section_for_day(day)
	day_number.text  = str(day)
	day_section.text = "%s  ·  %s" % [section["name"], section["ref"]]
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

func _process(delta: float) -> void:
	_next_poll -= delta
	if _next_poll > 0.0 or _next_line == null:
		return
	_next_poll = NEXT_POLL
	var text := _next_text()
	_next_line.visible = not text.is_empty()
	_next_line.text = text

func _next_text() -> String:
	if GameState.phase != GameState.Phase.WORK:
		return ""
	var me := Player.local
	if me == null or not is_instance_valid(me):
		return ""
	if me.downed:
		return "Down — a crewmate can lift you, or wait it out"
	var site := SiteFocus.site()
	if site == null:
		return "The day's stretch is done — keep the wall"
	var place := "gate" if not site.is_in_group("wall_sections") else "wall"
	var carry: String = me.carried_kind
	if not carry.is_empty():
		if SiteFocus.matches_carry():
			return "Take the %s to the %s" % [_material_name(carry), place]
		return "Nothing needs %s now — drop it (%s)" % [_material_name(carry), InputMode.key("drop")]
	if GameState.active_build and site.can_build():
		return "Build it up — %s at the %s" % [InputMode.key("interact"), place]
	var need: String = site.next_need()
	if need.is_empty():
		return ""
	return "Next: bring %s to the %s" % [_material_name(need), place]

static func _material_name(kind: String) -> String:
	return {"beam": "beams", "rubble": "rubble"}.get(kind, kind)

func _on_progress_changed(_done: int, _total: int) -> void:
	_refresh_progress()

func _refresh_progress() -> void:
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

func _on_phase_changed(phase: GameState.Phase) -> void:
	_refresh_progress()
	gather.visible = phase == GameState.Phase.GATHER
	_refresh_controls()
	var section := GameState.get_current_section()
	match phase:
		GameState.Phase.DAWN:
			var first_day := GameState.day_in_section(GameState.current_day).x == 0
			var sub: String = ("A new stretch: %s  ·  %s" if first_day else "%s  ·  %s") % [section["name"], section["ref"]]
			# First day of a section that brings something new: say what
			if first_day:
				for twist: String in GameState.new_twists():
					sub += "\n" + GameState.TWIST_INTRO.get(twist, "").format({"horn": "[%s]" % InputMode.key("horn")})
			_show_banner("Day %d" % GameState.current_day, sub)
		GameState.Phase.WON:
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
	_banner_tween.tween_interval(hold)
	_banner_tween.tween_property(banner, "modulate:a", 0.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_banner_tween.tween_callback(banner.hide)

func _show_end(won: bool) -> void:
	if _banner_tween:
		_banner_tween.kill()
	banner.hide()
	pause_menu.hide()
	for n: Control in [$Root/DayPlaque, threat, players_row]:
		n.hide()
	var vb := $Root/EndScreen/Center/VBox
	vb.get_node("Eyebrow").text = "Day %d of %d" % [GameState.current_day, GameState.TOTAL_DAYS]
	vb.get_node("Title").text = "The wall is finished" if won else "The city is overrun"
	vb.get_node("Message").text = WIN_VERSE if won \
		else "Too many enemies reached the inner city. Gather the workers and begin again."
	vb.get_node("Ref").text = WIN_VERSE_REF if won else ""
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
	end_screen.show()
	UiFx.fade_in(end_screen, 0.9)
	UiFx.stagger(vb.get_children(), 0.6, 0.08, 0.3)
	vb.get_node("Buttons/MenuButton").grab_focus()

# A replay is one section: name it, show its three marks, and head back to the map
func _replay_end(won: bool, vb: Control, stats: Control) -> void:
	var i := GameState.replay_section
	var sec: Dictionary = GameState.SECTIONS[i]
	vb.get_node("Eyebrow").text = "Section %d of %d  ·  %s" % [i + 1, GameState.SECTIONS.size(), sec["ref"]]
	if won:
		vb.get_node("Title").text = "The %s stands" % sec["name"]
		var got := GameState.mark_count(GameState.section_marks[i])
		vb.get_node("Message").text = ("A new best for this stretch — %d of 3 marks." if GameState.rating_improved 			else "%d of 3 marks. Your best here stays as it was.") % got
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
	await get_tree().create_timer(TALLY_DELAY, true, false, true).timeout
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
	var pos := GameState.day_in_section(day)
	var section := GameState.get_current_section()
	var title := "Day %d complete" % day
	var sub := "Not one enemy got through." if stats["breaches"] == 0 		else "%d slipped through — but the wall stands." % stats["breaches"]
	# Last day of a stretch: the whole section is done — say so
	if pos.x == pos.y - 1:
		title = "The %s stands" % section["name"]
		sub = "Section %d of %d complete  ·  %s" % [GameState.current_section_index + 1,
			GameState.SECTIONS.size(), sub]

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 56)
	_tally.add_child(row)
	var secs := int(stats["time"])
	var counts: Array = [
		[secs, "Time", func(v: int): return "%d:%02d" % [v / 60, v % 60]],
		[stats["loads"], "Loads carried", func(v: int): return str(v)],
		[stats["foes"], "Foes felled", func(v: int): return str(v)],
	]
	for i in counts.size():
		var cell := _stat(counts[i][2].call(0), counts[i][1])
		row.add_child(cell)
		_count_up(cell.get_child(0), counts[i][0], counts[i][2], i * TALLY_STEP + 0.5)

	var crew: Array = stats["crew"]
	if crew.size() > 1:
		_tally.add_child(_crew_line(crew))
	var rated := stats.has("marks")
	if rated:
		_tally.add_child(_marks_line(stats))

	banner.offset_bottom = BANNER_H + TALLY_H + (CREW_H if crew.size() > 1 else 0.0) 		+ (MARKS_H if rated else 0.0)
	_tally.show()
	_show_banner(title, sub, TALLY_HOLD, true)
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
		GameState.Mark.PACE: "%d:%02d of %d:%02d" % [secs / 60, secs % 60, par / 60, par % 60],
		GameState.Mark.CLEAN: "all through the section" if mask & GameState.Mark.CLEAN 			else "%d got through" % stats["section_breaches"],
		GameState.Mark.SOUND: "%d%% sound" % roundi(stats["wall"] * 100.0),
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
		var who: String = "You" if r[0] == multiplayer.get_unique_id() else CharacterRig.TRADES[slot % CharacterRig.TRADES.size()]
		chip.add_child(_crew_label(who, UiStyle.INK))
		chip.add_child(_crew_label("%d loads" % r[1], UiStyle.TERRACOTTA if r[1] > 0 and r[1] == top_loads else UiStyle.INK_SOFT))
		chip.add_child(_crew_label("·", UiStyle.INK_MUTED))
		chip.add_child(_crew_label("%d foes" % r[2], UiStyle.TERRACOTTA if r[2] > 0 and r[2] == top_foes else UiStyle.INK_SOFT))
		line.add_child(chip)
	return line

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
	v.add_child(n)
	v.add_child(l)
	return v

func _on_crew_changed(size: int) -> void:
	gather_crew.text = "%d of %d builders here" % [size, NetworkManager.MAX_PLAYERS]

# ── Player cards ───────────────────────────────────────────

func set_player_present(slot: int, present: bool, is_local: bool) -> void:
	if slot >= _cards.size():
		return
	var card: Dictionary = _cards[slot]
	card.root.visible = present
	card.name.text = CharacterRig.TRADES[slot % CharacterRig.TRADES.size()]
	card.who.text = "You" if is_local else "Crew %s" % ROMAN[slot]

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

func set_player_color(slot: int, color: Color) -> void:
	if slot >= _cards.size():
		return
	_slot_colors[slot] = color
	(_cards[slot].portrait as CrewPortrait).set_worker(slot, color)
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
	var early := GameState.phase == GameState.Phase.GATHER or GameState.current_day == 1
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
		var who := Label.new()
		who.theme_type_variation = &"Eyebrow"
		who.add_theme_font_size_override("font_size", 12)
		vb.add_child(who)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 8)
		vb.add_child(top)
		var name_lbl := Label.new()
		name_lbl.add_theme_font_override("font", UiStyle.tracked(UiStyle.CINZEL_BOLD, 1))
		name_lbl.add_theme_font_size_override("font_size", 17)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(name_lbl)
		var load_icon := TagIcon.make("stone", 24)
		load_icon.visible = false
		load_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(load_icon)
		var carry := Label.new()
		carry.theme_type_variation = &"Caption"
		carry.add_theme_font_size_override("font_size", 14)
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
		players_row.add_child(root)
		_cards.append({ root = root, portrait = portrait, name = name_lbl, who = who,
			carry = carry, bar = bar, fill = fill, load = load_icon })

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
	copy.tooltip_text = "Lobby code %s" % NetworkManager.lobby_code()
	copy.focus_mode = Control.FOCUS_NONE
	copy.pressed.connect(func():
		DisplayServer.clipboard_set(NetworkManager.lobby_code())
		copy.text = "Copied")
	hb.add_child(copy)

## Room code (and, in a browser, an invite link) for online rooms
func _build_room_panel() -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Card"
	$Root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 18)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	panel.add_child(hb)
	var lbl := Label.new()
	lbl.theme_type_variation = &"Eyebrow"
	lbl.text = "Room"
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(lbl)
	var code := Label.new()
	code.theme_type_variation = &"Numeral"
	code.text = NetworkManager.room_code()
	code.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(code)
	var link := NetworkManager.invite_link()
	var copy := Button.new()
	copy.theme_type_variation = &"PrimaryButton" if link.is_empty() else &"GhostButton"
	copy.text = "Copy code"
	copy.focus_mode = Control.FOCUS_NONE
	copy.pressed.connect(func():
		DisplayServer.clipboard_set(NetworkManager.room_code())
		copy.text = "Copied")
	hb.add_child(copy)
	if not link.is_empty():
		var share := Button.new()
		share.theme_type_variation = &"PrimaryButton"
		share.text = "Copy invite link"
		share.focus_mode = Control.FOCUS_NONE
		share.pressed.connect(func():
			DisplayServer.clipboard_set(link)
			share.text = "Link copied")
		hb.add_child(share)

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
		b.text = f.name + ("  · in game" if f.in_game else "")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.clip_text = true
		b.pressed.connect(func():
			var ok := NetworkManager.invite_friend(f.id)
			b.text = "%s  · %s" % [f.name, "invited" if ok else "invite failed"]
			b.disabled = ok)
		list.add_child(b)
	# Grow with the list up to ~8 rows, then scroll
	scroll.custom_minimum_size.y = minf(maxf(friends.size(), 1) * 40.0, 320.0)

# ── Helpers ────────────────────────────────────────────────

func _flash(node: CanvasItem, tint: Color) -> void:
	var tw := node.create_tween()
	tw.tween_property(node, "self_modulate", tint, 0.08)
	tw.tween_property(node, "self_modulate", Color.WHITE, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
