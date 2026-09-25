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

func _ready() -> void:
	_build_player_cards()
	if NetworkManager.in_steam_lobby():
		_build_invite_panel()
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
	if not event.is_action_pressed("pause") or end_screen.visible:
		return
	get_viewport().set_input_as_handled()
	if pause_menu.visible:
		_close_pause()
	else:
		pause_menu.show()
		UiFx.fade_in(pause_menu, 0.16)
		$Root/PauseMenu/Center/Modal/VBox/Resume.grab_focus()

func _close_pause() -> void:
	pause_menu.hide()

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

func _on_progress_changed(_done: int, _total: int) -> void:
	_refresh_progress()

func _refresh_progress() -> void:
	var working := GameState.phase == GameState.Phase.WORK
	work_row.visible = working
	phase_label.visible = not working
	match GameState.phase:
		GameState.Phase.GATHER:
			phase_label.text = "Gathering the crew"
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
	var section := GameState.get_current_section()
	match phase:
		GameState.Phase.DAWN:
			var first_day := GameState.day_in_section(GameState.current_day).x == 0
			_show_banner("Day %d" % GameState.current_day,
				("A new stretch: %s  ·  %s" if first_day else "%s  ·  %s") % [section["name"], section["ref"]])
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

func set_player_carry(slot: int, item_name: String) -> void:
	if slot >= _cards.size():
		return
	var lbl: Label = _cards[slot].carry
	if item_name == "Downed":
		lbl.text = "Downed"
		lbl.add_theme_color_override("font_color", UiStyle.TERRACOTTA)
	elif item_name.is_empty():
		lbl.text = "Empty-handed"
		lbl.add_theme_color_override("font_color", UiStyle.INK_MUTED)
	else:
		lbl.text = "Carrying %s" % item_name.to_lower()
		lbl.add_theme_color_override("font_color", UiStyle.INK_SOFT)

func set_player_color(slot: int, color: Color) -> void:
	if slot >= _cards.size():
		return
	(_cards[slot].swatch as ColorRect).color = color

func _build_player_cards() -> void:
	for slot in MAX_SLOTS:
		var root := PanelContainer.new()
		root.theme_type_variation = &"Card"
		root.custom_minimum_size = Vector2(250, 0)
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
		name_lbl.add_theme_font_size_override("font_size", 15)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(name_lbl)
		var carry := Label.new()
		carry.theme_type_variation = &"Caption"
		carry.add_theme_font_size_override("font_size", 14)
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
		set_player_carry(slot, "")

# ── Steam invite ───────────────────────────────────────────

# Bottom-right: open the Steam invite overlay, or copy the lobby code for when
# the overlay isn't available (running from the editor)
func _build_invite_panel() -> void:
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
	lbl.text = "Crew"
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(lbl)
	var invite := Button.new()
	invite.theme_type_variation = &"PrimaryButton"
	invite.text = "Invite friends"
	invite.focus_mode = Control.FOCUS_NONE
	invite.pressed.connect(NetworkManager.invite_friends)
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

# ── Helpers ────────────────────────────────────────────────

func _flash(node: CanvasItem, tint: Color) -> void:
	var tw := node.create_tween()
	tw.tween_property(node, "self_modulate", tint, 0.08)
	tw.tween_property(node, "self_modulate", Color.WHITE, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
