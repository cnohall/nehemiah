extends CanvasLayer

@onready var health_bar = $TopLeft/HealthBar
@onready var stamina_bar = $TopLeft/StaminaBar
@onready var role_label = $TopLeft/RoleLabel
@onready var carried_label = $TopLeft/CarriedLabel
@onready var wave_label = $TopRight/WaveLabel
@onready var progress_label = $TopRight/ProgressLabel
@onready var gold_label = $TopRight/GoldLabel
@onready var pause_menu = $PauseMenu
@onready var power_bar = $BottomCenter/PowerBar
@onready var place_bar = $PlaceBarContainer/PlaceBar
@onready var game_over_screen = $GameOverScreen
@onready var game_over_title = $GameOverScreen/Center/Panel/Margin/VBox/TitleLabel
@onready var game_over_sub = $GameOverScreen/Center/Panel/Margin/VBox/SubtitleLabel
@onready var game_over_day = $GameOverScreen/Center/Panel/Margin/VBox/DayLabel

var _target_health: float = 100.0
var _target_power: float = 0.0
var _target_stamina: float = 100.0
var _upgrade_panel: Control = null
var _upgrade_gold_label: Label = null
var _upgrade_btns: Dictionary = {}

func _ready() -> void:
	pause_menu.visible = false
	power_bar.visible = false
	place_bar.visible = false
	game_over_screen.visible = false
	health_bar.value = 100.0
	stamina_bar.value = 100.0
	
	_init_upgrade_panel()
	
	# Connect game over buttons
	var restart_btn = game_over_screen.get_node("Center/Panel/Margin/VBox/RestartBtn")
	if restart_btn: restart_btn.pressed.connect(func(): get_tree().reload_current_scene())
	
	var quit_btn = game_over_screen.get_node("Center/Panel/Margin/VBox/QuitBtn")
	if quit_btn: quit_btn.pressed.connect(func(): get_tree().quit())

func _process(delta: float) -> void:
	health_bar.value = lerp(health_bar.value, _target_health, 10.0 * delta)
	stamina_bar.value = lerp(stamina_bar.value, _target_stamina, 10.0 * delta)
	power_bar.value = lerp(power_bar.value, _target_power, 15.0 * delta)

	if power_bar.visible and _target_power <= 0.1 and power_bar.value <= 0.1:
		power_bar.visible = false

	var hp_pct := _target_health / 100.0
	if hp_pct < 0.3:
		health_bar.modulate = Color(1.0, 0.3, 0.3)
	elif hp_pct < 0.6:
		health_bar.modulate = Color(1.0, 0.85, 0.25)
	else:
		health_bar.modulate = Color.WHITE

	stamina_bar.modulate = Color(0.55, 0.55, 0.55) if _target_stamina < 1.0 else Color.WHITE

func update_health(val: float) -> void:
	_target_health = val

func update_stamina(val: float) -> void:
	_target_stamina = val

func update_role(r_name: String) -> void:
	if role_label:
		role_label.text = "ROLE: " + r_name.to_upper()

func update_carried(m_name: String) -> void:
	if carried_label:
		if m_name == "":
			carried_label.text = ""
		else:
			carried_label.text = "CARRYING: " + m_name.to_upper()

func update_wave(wave: int) -> void:
	if wave_label:
		wave_label.text = "DAY: %d" % wave

func update_progress(current: int, target: int) -> void:
	if progress_label:
		progress_label.text = "SECTIONS: %d/%d" % [current, target]

func update_power(val: float, max_val: float) -> void:
	power_bar.max_value = max_val
	_target_power = val
	if val > 0:
		power_bar.visible = true

func update_place(val: float, max_val: float) -> void:
	if val > 0:
		place_bar.visible = true
		place_bar.max_value = max_val
		place_bar.value = val
	else:
		place_bar.visible = false

func update_gold(total: int) -> void:
	if gold_label:
		gold_label.text = "SHEKELS: %d" % total
	if _upgrade_gold_label:
		_upgrade_gold_label.text = "TEAM GOLD: %d" % total

func toggle_upgrades(purchased: Dictionary, gold: int) -> void:
	if _upgrade_panel:
		_upgrade_panel.visible = !_upgrade_panel.visible
		if _upgrade_panel.visible:
			update_upgrades(purchased, gold)

func update_upgrades(purchased: Dictionary, gold: int) -> void:
	if _upgrade_gold_label:
		_upgrade_gold_label.text = "TEAM GOLD: %d" % gold
	
	# We query the UpgradeManager for definitions to avoid duplication
	var up_mgr = get_tree().current_scene.get_node_or_null("UpgradeManager")
	if not up_mgr: return
	
	var defs = up_mgr.UPGRADES
	for uid in defs:
		if _upgrade_btns.has(uid):
			var btn: Button = _upgrade_btns[uid]
			var cost = defs[uid].cost
			var is_purchased = purchased.get(uid, false)
			
			if is_purchased:
				btn.text = "PURCHASED"
				btn.disabled = true
			else:
				btn.text = "BUY (%d)" % cost
				btn.disabled = (gold < cost)

func show_game_over(win: bool, day: int) -> void:
	game_over_screen.visible = true
	game_over_title.text = "VICTORY!" if win else "DEFEAT"
	game_over_title.modulate = Color.GREEN if win else Color.RED
	game_over_day.text = "Day %d" % day
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _init_upgrade_panel() -> void:
	_upgrade_panel = CenterContainer.new()
	_upgrade_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_upgrade_panel.visible = false
	add_child(_upgrade_panel)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.55)
	_upgrade_panel.add_child(bg)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 0)
	_upgrade_panel.add_child(panel)

	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.18, 0.14, 0.10)
	ps.border_color = Color(0.55, 0.42, 0.22)
	ps.border_width_left = 2; ps.border_width_right = 2
	ps.border_width_top = 2; ps.border_width_bottom = 2
	panel.add_theme_stylebox_override("panel", ps)

	var margin := MarginContainer.new()
	for side in ["margin_top","margin_bottom","margin_left","margin_right"]:
		margin.add_theme_constant_override(side, 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "UPGRADES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.50))
	vbox.add_child(title)

	_upgrade_gold_label = Label.new()
	_upgrade_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_upgrade_gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.20))
	vbox.add_child(_upgrade_gold_label)

	vbox.add_child(HSeparator.new())

	var up_mgr = get_tree().current_scene.get_node_or_null("UpgradeManager")
	var defs = {}
	if up_mgr: defs = up_mgr.UPGRADES

	for uid in defs:
		var d: Dictionary = defs[uid]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		vbox.add_child(row)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)

		var nl := Label.new()
		nl.text = d["name"]
		nl.add_theme_font_size_override("font_size", 14)
		nl.add_theme_color_override("font_color", Color(0.95, 0.88, 0.70))
		info.add_child(nl)

		var dl := Label.new()
		dl.text = d["desc"]
		dl.add_theme_font_size_override("font_size", 11)
		dl.modulate = Color(0.7, 0.7, 0.7)
		info.add_child(dl)

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(100, 32)
		btn.text = "BUY (%d)" % d.cost
		btn.pressed.connect(func(): _on_upgrade_pressed(uid))
		row.add_child(btn)
		_upgrade_btns[uid] = btn

func _on_upgrade_pressed(uid: String) -> void:
	var main = get_tree().current_scene
	if main.has_method("request_purchase_upgrade"):
		main.request_purchase_upgrade.rpc_id(1, uid)
