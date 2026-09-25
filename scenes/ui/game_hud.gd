extends CanvasLayer

# In-game HUD. Reads GameState (mirrored on every peer) and is fed player/enemy
# numbers by Main. Player cards and the Steam invite panel are built in code.

signal begin_requested   # host pressed "Begin the work" (Main forwards to DayDirector)

const MENU_SCENE    := "res://scenes/ui/main_menu.tscn"
const BANNER_HOLD   := 3.2
const MAX_SLOTS     := 4
const ROMAN         := ["I", "II", "III", "IV"]
const WIN_VERSE     := "“So the wall was completed on the 25th day of Elul, in 52 days.”"
const WIN_VERSE_REF := "Nehemiah 6:15"
# Key → what it does. Shown while gathering and on day 1, and whenever paused.
const CONTROLS := [
	["WASD", "Move"],
	["E", "Pick up · deliver · revive"],
	["G", "Drop"],
	["Space", "Dash"],
	["Hold RMB", "Sling — release to throw"],
	["Esc", "Menu"],
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
@onready var enemy_count:  Label       = $Root/ThreatPlaque/VBox/EnemyRow/EnemyCount
@onready var breach_count: Label       = $Root/ThreatPlaque/VBox/BreachRow/BreachCount
@onready var breach_pips:  PipRow      = $Root/ThreatPlaque/VBox/Pips
@onready var players_row:  HBoxContainer = $Root/Players
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
var _last_enemies := 0
var _controls: Control
var _controls_tween: Tween
var _touch: TouchControls
var _pause_btn: Button
var _room_chip: Control

func _ready() -> void:
	_build_player_cards()
	if TouchControls.enabled():
		_build_touch_controls()
	else:
		_build_controls_hint()
	# Under the banner and menus, over the world-facing plaques
	var alerts := OffscreenAlerts.new()
	$Root.add_child(alerts)
	$Root.move_child(alerts, banner.get_index())
	if NetworkManager.in_steam_lobby():
		_build_invite_panel()
	if not NetworkManager.room_code().is_empty():
		_build_room_code()
	if Mobile.enabled():
		_apply_mobile_layout(alerts)
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
	GameState.crew_changed.connect(_on_crew_changed)
	_on_crew_changed(GameState.crew_size)
	settings.closed.connect($Root/PauseMenu/Center/Modal/VBox/Settings.grab_focus)

	GameState.day_changed.connect(refresh_day)
	GameState.phase_changed.connect(_on_phase_changed)
	GameState.progress_changed.connect(_on_progress_changed)
	GameState.breaches_changed.connect(_on_breaches_changed)
	refresh_day(GameState.current_day)
	_on_breaches_changed(GameState.breaches)
	_on_phase_changed(GameState.phase)

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause") or end_screen.visible or GameState.phase == GameState.Phase.STORY:
		return
	get_viewport().set_input_as_handled()
	_toggle_pause()

func _toggle_pause() -> void:
	if pause_menu.visible:
		_close_pause()
	else:
		pause_menu.show()
		UiFx.fade_in(pause_menu, 0.16)
		_refresh_controls()
		if not Mobile.enabled():   # no focus ring on touch
			$Root/PauseMenu/Center/Modal/VBox/Resume.grab_focus()

func _close_pause() -> void:
	pause_menu.hide()
	_refresh_controls()

func _leave() -> void:
	NetworkManager.disconnect_session()
	GameState.reset()
	get_tree().change_scene_to_file(MENU_SCENE)

# ── Day / Section ──────────────────────────────────────────

func refresh_day(day: int) -> void:
	var section := GameState.get_section_for_day(day)
	day_number.text  = str(day)
	# Phones share one line with the day number: name only
	day_section.text = ("·  %s" % section["name"]) if Mobile.enabled() 		else "%s  ·  %s" % [section["name"], section["ref"]]
	circuit.day = day

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
	create_tween().tween_property(work_bar, "value", float(GameState.targets_done) / total, 0.35) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
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
					sub += "\n" + GameState.TWIST_INTRO.get(twist, "")
			_show_banner("Day %d" % GameState.current_day, sub)
		GameState.Phase.DUSK:
			_show_banner("Day %d complete" % GameState.current_day, "Rest, and return at first light.")
		GameState.Phase.WON:
			_show_end(true)
		GameState.Phase.LOST:
			_show_end(false)

func _show_banner(title: String, sub: String) -> void:
	banner_title.text = title
	banner_sub.text = sub
	if _banner_tween:
		_banner_tween.kill()
	banner.show()
	banner.modulate.a = 0.0
	banner_sub.modulate.a = 0.0
	_banner_tween = create_tween()
	_banner_tween.tween_property(banner, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_property(banner_sub, "modulate:a", 1.0, 0.5)
	_banner_tween.tween_interval(BANNER_HOLD)
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
	end_screen.show()
	UiFx.fade_in(end_screen, 0.9)
	UiFx.stagger(vb.get_children(), 0.6, 0.08, 0.3)
	vb.get_node("Buttons/MenuButton").grab_focus()

func _stat(value: String, caption: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	var n := Label.new()
	n.theme_type_variation = &"Numeral"
	n.text = value
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.add_theme_color_override("font_color", UiStyle.CREAM)
	var l := Label.new()
	l.theme_type_variation = &"Eyebrow"
	l.text = caption
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", UiStyle.GOLD)
	v.add_child(n)
	v.add_child(l)
	return v

func _on_crew_changed(size: int) -> void:
	gather_crew.text = "%d of %d builders here" % [size, NetworkManager.MAX_PLAYERS]

# ── Enemy count ────────────────────────────────────────────

func set_enemy_count(count: int) -> void:
	if count == _last_enemies:
		return
	enemy_count.text = str(count)
	enemy_count.add_theme_color_override("font_color", UiStyle.TERRACOTTA_DEEP if count > 0 else UiStyle.INK)
	_last_enemies = count

# ── Player cards ───────────────────────────────────────────

func set_player_present(slot: int, present: bool, is_local: bool) -> void:
	if slot >= _cards.size():
		return
	var card: Dictionary = _cards[slot]
	card.root.visible = present
	card.name.text = "You" if is_local else "Builder %s" % ROMAN[slot]

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

func set_player_color(slot: int, color: Color) -> void:
	if slot >= _cards.size():
		return
	(_cards[slot].swatch as ColorRect).color = color

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
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.plaque(Vector2(16, 12), 0.9))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE, 18)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	var title := Label.new()
	title.theme_type_variation = &"Eyebrow"
	title.text = "Controls"
	vb.add_child(title)
	var key_box := UiStyle.bordered(UiStyle.box(UiStyle.PARCHMENT_DEEP, Vector2(7, 1), 3), UiStyle.RULE, 1, 2)
	for row: Array in CONTROLS:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		vb.add_child(hb)
		var key := Label.new()
		key.text = row[0]
		key.add_theme_font_override("font", UiStyle.CINZEL_SEMI)
		key.add_theme_font_size_override("font_size", 13)
		key.add_theme_color_override("font_color", UiStyle.INK)
		key.add_theme_stylebox_override("normal", key_box)
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key.custom_minimum_size.x = 78
		hb.add_child(key)
		var what := Label.new()
		what.theme_type_variation = &"Body"
		what.add_theme_font_size_override("font_size", 15)
		what.text = row[1]
		hb.add_child(what)
	_controls = panel
	_refresh_controls()

func _refresh_controls() -> void:
	if _controls == null:
		return
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
		root.custom_minimum_size = Vector2(120 if Mobile.enabled() else 190, 0)
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.visible = false
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 6)
		root.add_child(vb)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 8)
		vb.add_child(top)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(8, 8)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(swatch)
		var name_lbl := Label.new()
		name_lbl.add_theme_font_override("font", UiStyle.tracked(UiStyle.CINZEL_BOLD, 2))
		name_lbl.add_theme_font_size_override("font_size", 12 if Mobile.enabled() else 15)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(name_lbl)
		var carry := Label.new()
		carry.theme_type_variation = &"Caption"
		carry.add_theme_font_size_override("font_size", 12 if Mobile.enabled() else 14)
		carry.add_theme_color_override("font_color", UiStyle.TERRACOTTA)
		carry.text = "Downed"
		carry.visible = false
		top.add_child(carry)
		var bar := ProgressBar.new()
		bar.theme_type_variation = &"Meter"
		bar.custom_minimum_size = Vector2(0, 6)
		bar.max_value = 1.0
		bar.value = 1.0
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fill := UiStyle.box(UiStyle.OLIVE, Vector2.ZERO, 2)
		bar.add_theme_stylebox_override("fill", fill)
		vb.add_child(bar)
		players_row.add_child(root)
		_cards.append({ root = root, swatch = swatch, name = name_lbl,
			carry = carry, bar = bar, fill = fill })

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
	work_bar.custom_minimum_size.y = 5
	phase_label.add_theme_font_size_override("font_size", 11)
	$Root/DayPlaque/VBox/WorkRow.add_theme_constant_override("separation", 8)

	# Threat — top right, same height as the day bar: enemies, then breach pips
	threat.add_theme_stylebox_override("panel", UiStyle.plaque(Vector2(12, 7), 0.9))
	threat.custom_minimum_size.x = 150
	threat.offset_left = -(150 + right)
	threat.offset_right = -right
	threat.offset_top = top
	threat.offset_bottom = top
	$Root/ThreatPlaque/VBox.add_theme_constant_override("separation", 3)
	enemy_count.add_theme_font_size_override("font_size", 20)
	$Root/ThreatPlaque/VBox/Rule.hide()
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
	vb.custom_minimum_size.x = 560
	vb.add_theme_constant_override("separation", 8)
	vb.get_node("Eyebrow").add_theme_font_size_override("font_size", 12)
	vb.get_node("Title").add_theme_font_size_override("font_size", 40)
	vb.get_node("Message").add_theme_font_size_override("font_size", 16)
	vb.get_node("Stats").add_theme_constant_override("separation", 40)
	vb.get_node("StatsGap").custom_minimum_size.y = 6
	vb.get_node("ButtonGap").custom_minimum_size.y = 8
	vb.get_node("Rule").custom_minimum_size.x = 260

	# Game menu — narrower
	$Root/PauseMenu/Center/Modal.custom_minimum_size.x = 340
	$Root/PauseMenu/Center/Modal/VBox/Hint.custom_minimum_size.x = 280
	$Root/PauseMenu/Center/Modal/VBox.add_theme_constant_override("separation", 10)

	# Edge pointers stay clear of the plaques and the action cluster
	alerts.margin_side = 40.0 + maxf(s.x, s.z)
	alerts.margin_top = top + 90.0
	alerts.margin_bottom = 60.0 + s.w

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
