extends CanvasLayer
## GameHUD — Simplified Core UI

var _target_health: float = 100.0
var _target_stamina: float = 100.0

@onready var health_bar   = $TopLeft/Margin/Content/HealthBar
@onready var stamina_bar  = $TopLeft/Margin/Content/StaminaBar
@onready var carried_label = $TopLeft/Margin/Content/CarriedLabel
@onready var wave_label    = $TopRight/Margin/Content/WaveLabel
@onready var progress_label = $TopRight/Margin/Content/ProgressLabel
@onready var place_bar     = $PlaceBarContainer/VBox/PlaceBar
@onready var place_label   = $PlaceBarContainer/VBox/NeedLabel
@onready var sling_bar       = $SlingContainer/SlingBar
@onready var sling_label     = $SlingContainer/SlingLabel
@onready var game_over_screen = $GameOverScreen
@onready var game_over_title  = $GameOverScreen/Center/Panel/Margin/VBox/TitleLabel
@onready var section_label = $HistoryPanel/Margin/VBox/SectionLabel
@onready var neh_label     = $HistoryPanel/Margin/VBox/NehLabel
@onready var quote_label   = $HistoryPanel/Margin/VBox/QuoteLabel

func _ready() -> void:
	$PlaceBarContainer.visible = false
	game_over_screen.visible = false
	health_bar.value  = 100.0
	stamina_bar.value = 100.0

	# Sling bar fill — created in code so we can animate the color
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.88, 0.70, 0.12)
	fill.corner_radius_top_left    = 2
	fill.corner_radius_top_right   = 2
	fill.corner_radius_bottom_right = 2
	fill.corner_radius_bottom_left = 2
	sling_bar.add_theme_stylebox_override("fill", fill)
	sling_bar.set_meta("fill_style", fill)

	var restart_btn = game_over_screen.get_node_or_null("Center/Panel/Margin/VBox/RestartBtn")
	if restart_btn:
		restart_btn.pressed.connect(func(): get_tree().reload_current_scene())

	var quit_btn = game_over_screen.get_node_or_null("Center/Panel/Margin/VBox/QuitBtn")
	if quit_btn:
		quit_btn.pressed.connect(func(): get_tree().quit())

func _process(delta: float) -> void:
	health_bar.value  = lerp(health_bar.value,  _target_health,  10.0 * delta)
	stamina_bar.value = lerp(stamina_bar.value, _target_stamina, 10.0 * delta)

	var hp_pct := _target_health / 100.0
	if hp_pct < 0.3:
		health_bar.modulate = Color(1.0, 0.55, 0.55)
	elif hp_pct < 0.6:
		health_bar.modulate = Color(1.0, 0.88, 0.45)
	else:
		health_bar.modulate = Color.WHITE

func update_health(val: float) -> void:
	_target_health = val

func update_stamina(val: float, max_val: float) -> void:
	_target_stamina = val / max_val * 100.0
	stamina_bar.modulate = Color(1.0, 0.62, 0.22) if val < 25.0 else Color.WHITE

func update_carried(m_name: String) -> void:
	if carried_label:
		carried_label.text = m_name.to_upper() if m_name != "" else "—"

func update_wave(wave: int) -> void:
	if wave_label:
		wave_label.text = "DAY  %d" % wave

func update_progress(current: int, target: int) -> void:
	if progress_label:
		progress_label.text = "%d / %d  SECTIONS" % [current, target]

func update_sling(charge: float, reloading: bool, reload_pct: float) -> void:
	if charge < 0.0:
		$SlingContainer.visible = false
		return

	$SlingContainer.visible = true
	var fill: StyleBoxFlat = sling_bar.get_meta("fill_style")

	if reloading:
		sling_bar.value = reload_pct * 100.0
		fill.bg_color   = Color(0.42, 0.40, 0.35)
		sling_label.text = "RELOADING"
		sling_label.modulate = Color(0.7, 0.7, 0.7)
	else:
		sling_bar.value = charge * 100.0
		# Amber → orange-red as charge builds
		fill.bg_color = Color(0.88 + charge * 0.07, 0.70 - charge * 0.45, 0.12 - charge * 0.10)
		if charge >= 0.95:
			sling_label.text    = "RELEASE!"
			sling_label.modulate = Color(1.0, 0.5, 0.2)
		else:
			sling_label.text    = "CHARGING"
			sling_label.modulate = Color(0.92, 0.82, 0.48)

func update_place(val: float, max_val: float, message: String = "",
		color: Color = Color.WHITE) -> void:
	if val > 0 or message != "":
		$PlaceBarContainer.visible = true
		place_bar.max_value = max_val
		place_bar.value = val
		if message != "":
			place_label.text = message
			place_label.visible = true
			place_label.modulate = color
			place_bar.modulate = Color(1, 0.4, 0.4, 0.6) if val <= 0 else Color.WHITE
		else:
			place_label.visible = false
			place_bar.modulate = Color.WHITE
	else:
		$PlaceBarContainer.visible = false

func update_section_info(day: int) -> void:
	for sec: Dictionary in WallData.SECTIONS:
		if day >= sec.day_start and day <= sec.day_end:
			if section_label:
				section_label.text = sec.name.to_upper()
			if neh_label:
				neh_label.text = "Nehemiah " + sec.neh
			if quote_label:
				quote_label.text = "\"" + sec.quote + "\""
			return

func show_game_over(win: bool, _day: int) -> void:
	game_over_screen.visible = true
	game_over_title.text = "VICTORY!" if win else "DEFEAT"
	game_over_title.modulate = Color(0.75, 0.95, 0.55) if win else Color(0.95, 0.35, 0.35)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
