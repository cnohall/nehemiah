extends CanvasLayer

# In-game HUD. Reads GameState (mirrored on every peer) and is fed player/enemy
# numbers by Main. Banner + end screen are built in code on top of the .tscn panels.

const MENU_SCENE     := "res://scenes/ui/main_menu.tscn"
const INK            := Color(0.13, 0.10, 0.07)
const INK_SOFT       := Color(0.45, 0.36, 0.26)
const TERRACOTTA     := Color(0.66, 0.30, 0.18)
const BANNER_HOLD    := 3.2
const WIN_VERSE      := "“So the wall was completed on the 25th day of Elul, in 52 days.”"
const WIN_VERSE_REF  := "Nehemiah 6:15"

@onready var day_number:  Label = $TopCenter/DayPanel/VBox/DayNumber
@onready var day_section: Label = $TopCenter/DayPanel/VBox/DaySection
@onready var enemy_count: Label = $WavePanel/VBox/EnemyCount

@onready var player_panels: Array = [
	$PlayersPanel/Player1,
	$PlayersPanel/Player2,
	$PlayersPanel/Player3,
	$PlayersPanel/Player4,
]

var _progress: Label
var _breaches: Label
var _banner: PanelContainer
var _banner_title: Label
var _banner_sub: Label
var _banner_tween: Tween
var _end_button: Button

func _ready() -> void:
	_build_progress_line()
	_build_breach_line()
	_build_banner()
	GameState.day_changed.connect(refresh_day)
	GameState.phase_changed.connect(_on_phase_changed)
	GameState.progress_changed.connect(_on_progress_changed)
	GameState.breaches_changed.connect(_on_breaches_changed)
	refresh_day(GameState.current_day)
	_on_breaches_changed(GameState.breaches)
	_on_phase_changed(GameState.phase)

# ── Day / Section ──────────────────────────────────────────

func refresh_day(day: int) -> void:
	var section := GameState.get_section_for_day(day)
	day_number.text  = "Day %d of %d" % [day, GameState.TOTAL_DAYS]
	day_section.text = "%s · %s" % [section["name"], section["ref"]]

func _on_progress_changed(_done: int, _total: int) -> void:
	_refresh_progress()

func _refresh_progress() -> void:
	match GameState.phase:
		GameState.Phase.DAWN:
			_progress.text = "Dawn — ready the workers"
		GameState.Phase.DUSK:
			_progress.text = "Day's work complete"
		_:
			_progress.text = "Today's work  %d / %d" % [GameState.targets_done, GameState.targets_total]

func _on_breaches_changed(count: int) -> void:
	_breaches.text = "City breaches %d / %d" % [count, GameState.MAX_BREACHES]
	_breaches.add_theme_color_override("font_color",
		TERRACOTTA if count >= GameState.MAX_BREACHES * 0.7 else INK_SOFT)

# ── Phase banners ──────────────────────────────────────────

func _on_phase_changed(phase: GameState.Phase) -> void:
	_refresh_progress()
	var section := GameState.get_current_section()
	match phase:
		GameState.Phase.DAWN:
			var first_day := GameState.day_in_section(GameState.current_day).x == 0
			_show_banner("Day %d" % GameState.current_day,
				("A new stretch: %s · %s" if first_day else "%s · %s") % [section["name"], section["ref"]])
		GameState.Phase.DUSK:
			_show_banner("Day %d complete" % GameState.current_day, "Rest, and return at first light.")
		GameState.Phase.WON:
			_show_banner("The wall is finished", "%s\n%s" % [WIN_VERSE, WIN_VERSE_REF], true)
		GameState.Phase.LOST:
			_show_banner("The city is overrun", "Too many enemies reached the inner city.", true)

func _show_banner(title: String, sub: String, final := false) -> void:
	_banner_title.text = title
	_banner_sub.text = sub
	_end_button.visible = final
	if _banner_tween:
		_banner_tween.kill()
	_banner.modulate.a = 0.0
	_banner.visible = true
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.4)
	if not final:
		_banner_tween.tween_interval(BANNER_HOLD)
		_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.6)
		_banner_tween.tween_callback(_banner.hide)

func _on_end_pressed() -> void:
	NetworkManager.disconnect_session()
	GameState.reset()
	get_tree().change_scene_to_file(MENU_SCENE)

# ── Enemy count ────────────────────────────────────────────

func set_enemy_count(count: int) -> void:
	enemy_count.text = str(count)

# ── Player panels ──────────────────────────────────────────

func set_player_health(slot: int, pct: float) -> void:
	if slot >= player_panels.size():
		return
	var bar: ProgressBar = player_panels[slot].get_node_or_null("VBox/HealthBar")
	if bar:
		bar.value = pct * 100.0

func set_player_carry(slot: int, item_name: String) -> void:
	if slot >= player_panels.size():
		return
	var lbl: Label = player_panels[slot].get_node_or_null("VBox/CarryLabel")
	if lbl:
		lbl.text = item_name

func set_player_color(slot: int, color: Color) -> void:
	if slot >= player_panels.size():
		return
	var lbl: Label = player_panels[slot].get_node_or_null("VBox/PlayerName")
	if lbl:
		lbl.add_theme_color_override("font_color", color.darkened(0.25))

# ── Builders ───────────────────────────────────────────────

func _build_progress_line() -> void:
	_progress = _make_label(day_section.get_theme_font("font"), 12, INK)
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	day_section.get_parent().add_child(_progress)

func _build_breach_line() -> void:
	_breaches = _make_label(day_number.get_theme_font("font"), 10, INK_SOFT)
	_breaches.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enemy_count.get_parent().add_child(_breaches)

func _build_banner() -> void:
	_banner = PanelContainer.new()
	_banner.add_theme_stylebox_override("panel", $TopCenter/DayPanel.get_theme_stylebox("panel"))
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.anchor_top = 0.12
	_banner.anchor_bottom = 0.12
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.custom_minimum_size = Vector2(460, 0)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_banner.add_child(vb)
	_banner_title = _make_label(day_number.get_theme_font("font"), 34, INK)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_banner_title)
	_banner_sub = _make_label(day_section.get_theme_font("font"), 16, INK_SOFT)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_banner_sub)
	_end_button = Button.new()
	_end_button.text = "Return to menu"
	_end_button.add_theme_font_override("font", day_number.get_theme_font("font"))
	_end_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_end_button.visible = false
	_end_button.pressed.connect(_on_end_pressed)
	vb.add_child(_end_button)
	add_child(_banner)

func _make_label(font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
