extends CanvasLayer
## GameHUD — Simplified Core UI

var _target_health: float = 100.0

@onready var health_bar = $TopLeft/HealthBar
@onready var wave_label = $TopRight/WaveLabel
@onready var progress_label = $TopRight/ProgressLabel
@onready var carried_label = $TopLeft/CarriedLabel
@onready var place_bar = $PlaceBarContainer/VBox/PlaceBar
@onready var place_label = $PlaceBarContainer/VBox/NeedLabel
@onready var game_over_screen = $GameOverScreen
@onready var game_over_title = $GameOverScreen/Center/Panel/Margin/VBox/TitleLabel

func _ready() -> void:
	$PlaceBarContainer.visible = false
	game_over_screen.visible = false
	health_bar.value = 100.0

	# Connect buttons
	var restart_btn = game_over_screen.get_node_or_null("Center/Panel/Margin/VBox/RestartBtn")
	if restart_btn:
		restart_btn.pressed.connect(func(): get_tree().reload_current_scene())

	var quit_btn = game_over_screen.get_node_or_null("Center/Panel/Margin/VBox/QuitBtn")
	if quit_btn:
		quit_btn.pressed.connect(func(): get_tree().quit())

func _process(delta: float) -> void:
	health_bar.value = lerp(health_bar.value, _target_health, 10.0 * delta)

	var hp_pct := _target_health / 100.0
	health_bar.modulate = Color.WHITE
	if hp_pct < 0.3:
		health_bar.modulate = Color(1.0, 0.3, 0.3)
	elif hp_pct < 0.6:
		health_bar.modulate = Color(1.0, 0.85, 0.25)

func update_health(val: float) -> void:
	_target_health = val

func update_carried(m_name: String) -> void:
	if carried_label:
		carried_label.text = "CARRYING: " + m_name.to_upper() if m_name != "" else ""

func update_wave(wave: int) -> void:
	if wave_label:
		wave_label.text = "DAY: %d" % wave

func update_progress(current: int, target: int) -> void:
	if progress_label:
		progress_label.text = "SECTIONS: %d/%d" % [current, target]

func update_place(val: float, max_val: float, message: String = "", color: Color = Color.WHITE) -> void:
	if val > 0 or message != "":
		$PlaceBarContainer.visible = true
		place_bar.max_value = max_val
		place_bar.value = val
		
		if message != "":
			place_label.text = message
			place_label.visible = true
			place_label.modulate = color
			# If we have a message but no progress, it's a 'block' state
			if val <= 0:
				place_bar.modulate = Color(1, 0.4, 0.4, 0.5) # Dim red
			else:
				place_bar.modulate = Color.WHITE
		else:
			place_label.visible = false
			place_bar.modulate = Color.WHITE
	else:
		$PlaceBarContainer.visible = false

func show_game_over(win: bool, _day: int) -> void:
	game_over_screen.visible = true
	game_over_title.text = "VICTORY!" if win else "DEFEAT"
	game_over_title.modulate = Color.GREEN if win else Color.RED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
