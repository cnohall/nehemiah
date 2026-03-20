extends Control
## GameHUD — Health/stamina bars, sling charge bar, wall needs, pause overlay.
## Each piece is driven by player signals connected in main.gd.

signal pause_changed(is_paused: bool)

var _target_health:  float = 100.0
var _target_stamina: float = 100.0
var _paused:         bool  = false

@onready var _health_bar:    ProgressBar = $Panel/Margin/VBox/HealthBar
@onready var _stamina_bar:   ProgressBar = $Panel/Margin/VBox/StaminaBar
@onready var _pause_overlay: Control     = $PauseOverlay
@onready var _quit_btn:      Button      = $PauseOverlay/Center/Panel/Margin/VBox/QuitBtn
@onready var _sling_container: Control     = $SlingContainer
@onready var _sling_bar:       ProgressBar = $SlingContainer/SlingBar
@onready var _sling_label:     Label       = $SlingContainer/SlingLabel
@onready var _wall_needs:      Control     = $WallNeeds
@onready var _stone_label:     Label       = $WallNeeds/Margin/HBox/StoneLabel
@onready var _wood_label:      Label       = $WallNeeds/Margin/HBox/WoodLabel
@onready var _mortar_label:    Label       = $WallNeeds/Margin/HBox/MortarLabel

var _city_panel: Control = null
var _city_bar: ProgressBar = null
var _city_fill_style: StyleBoxFlat = null
var _sling_fill_style: StyleBoxFlat = null
var _damage_flash: ColorRect = null
var _day_label: Label = null

func _ready() -> void:
	_pause_overlay.visible = false
	_sling_container.visible = false
	_wall_needs.visible = false
	_quit_btn.pressed.connect(func(): get_tree().quit())
	_style_quit_button()
	_setup_sling_fill()
	_create_city_hp_bar()
	_create_damage_flash()
	_create_day_label()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed and not event.echo:
		_toggle_pause()
		get_viewport().set_input_as_handled()

func _create_city_hp_bar() -> void:
	_city_panel = PanelContainer.new()
	_city_panel.anchor_left = 1.0
	_city_panel.anchor_right = 1.0
	_city_panel.offset_left = -180.0
	_city_panel.offset_top = 16.0
	_city_panel.offset_right = -16.0
	_city_panel.offset_bottom = 74.0
	_city_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.065, 0.042, 0.90)
	panel_style.set_border_width_all(1)
	panel_style.border_color = Color(0.50, 0.40, 0.22, 0.8)
	panel_style.set_corner_radius_all(4)
	_city_panel.add_theme_stylebox_override("panel", panel_style)
	_city_panel.visible = false
	add_child(_city_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	_city_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	margin.add_child(vbox)

	var label := Label.new()
	label.text = "JERUSALEM"
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color(0.82, 0.72, 0.48, 1.0))
	var font = load("res://assets/fonts/Cinzel-Regular.ttf")
	if font:
		label.add_theme_font_override("font", font)
	vbox.add_child(label)

	_city_bar = ProgressBar.new()
	_city_bar.custom_minimum_size = Vector2(140, 14)
	_city_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_city_bar.max_value = 100
	_city_bar.value = 100
	_city_bar.show_percentage = false
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.10, 0.08, 0.05, 1.0)
	bg_style.set_corner_radius_all(3)
	_city_bar.add_theme_stylebox_override("background", bg_style)
	_city_fill_style = StyleBoxFlat.new()
	_city_fill_style.bg_color = Color(0.68, 0.14, 0.10, 1.0)
	_city_fill_style.set_corner_radius_all(3)
	_city_bar.add_theme_stylebox_override("fill", _city_fill_style)
	vbox.add_child(_city_bar)

func update_city_hp(current: float, max_hp: float) -> void:
	if not is_instance_valid(_city_panel):
		return
	_city_panel.visible = current < max_hp
	if not is_instance_valid(_city_bar):
		return
	_city_bar.value = current / max_hp * 100.0
	if _city_fill_style:
		_city_fill_style.bg_color = Color(0.9, 0.1, 0.1) if current < max_hp * 0.3 else Color(0.68, 0.14, 0.10)

func _process(delta: float) -> void:
	_health_bar.value  = lerpf(_health_bar.value,  _target_health,  10.0 * delta)
	_stamina_bar.value = lerpf(_stamina_bar.value, _target_stamina, 10.0 * delta)
	_health_bar.modulate  = Color(1.0, 0.55, 0.55) if _target_health  < 30.0 else Color.WHITE
	_stamina_bar.modulate = Color(1.0, 0.80, 0.40) if _target_stamina < 25.0 else Color.WHITE

# ── Player signal callbacks ───────────────────────────────────────────────────

func update_health(val: float) -> void:
	_target_health = val

func update_stamina(val: float, max_val: float) -> void:
	_target_stamina = val / max_val * 100.0

func update_sling(charge: float, reloading: bool, reload_pct: float) -> void:
	if charge < 0.0:
		_sling_container.visible = false
		return
	_sling_container.visible = true
	var fill := _sling_fill_style
	if not fill:
		return
	if reloading:
		_sling_bar.value     = reload_pct * 100.0
		fill.bg_color        = Color(0.38, 0.35, 0.28)
		_sling_label.text    = "RELOADING"
		_sling_label.modulate = Color(0.60, 0.58, 0.52)
	else:
		_sling_bar.value = charge * 100.0
		fill.bg_color    = Color(0.88 + charge * 0.07, 0.70 - charge * 0.45, 0.12 - charge * 0.10)
		if charge >= 0.95:
			_sling_label.text     = "RELEASE!"
			_sling_label.modulate = Color(1.0, 0.50, 0.18)
		else:
			_sling_label.text     = "CHARGING"
			_sling_label.modulate = Color(0.92, 0.82, 0.48)

func update_wall_needs(stone: int, wood: int, mortar: int) -> void:
	if stone < 0 or (stone == 0 and wood == 0 and mortar == 0):
		_wall_needs.visible = false
		return
	_wall_needs.visible   = true
	_stone_label.visible  = stone  > 0
	_wood_label.visible   = wood   > 0
	_mortar_label.visible = mortar > 0
	if stone  > 0: _stone_label.text  = "STONE \u00d7%d"  % stone
	if wood   > 0: _wood_label.text   = "TIMBER \u00d7%d" % wood
	if mortar > 0: _mortar_label.text = "MORTAR \u00d7%d" % mortar

# ── Pause ─────────────────────────────────────────────────────────────────────

func _toggle_pause() -> void:
	_paused = not _paused
	_pause_overlay.visible = _paused
	pause_changed.emit(_paused)

# ── Setup helpers ─────────────────────────────────────────────────────────────

func _setup_sling_fill() -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.88, 0.70, 0.12)
	fill.set_corner_radius_all(2)
	_sling_bar.add_theme_stylebox_override("fill", fill)
	_sling_fill_style = fill

	# Minimum-charge threshold marker — releasing before this line does nothing.
	# Positioned at MIN_CHARGE / MAX_CHARGE along the bar width using anchors.
	var ratio := Slinger.MIN_CHARGE / Slinger.MAX_CHARGE
	var marker := ColorRect.new()
	marker.color = Color(1.0, 0.95, 0.75, 0.70)
	marker.anchor_left   = ratio
	marker.anchor_right  = ratio
	marker.anchor_top    = 0.1
	marker.anchor_bottom = 0.9
	marker.offset_left   = -1.0
	marker.offset_right  =  1.0  # 2 px wide
	marker.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_sling_bar.add_child(marker)

func _create_damage_flash() -> void:
	_damage_flash = ColorRect.new()
	_damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_damage_flash.color = Color(0.75, 0.08, 0.04, 0.0)
	_damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_damage_flash)

func flash_damage(amount: float) -> void:
	if not is_instance_valid(_damage_flash):
		return
	var peak := clampf(amount / 100.0 * 0.55, 0.12, 0.55)
	_damage_flash.color.a = peak
	var tween := create_tween()
	tween.tween_property(_damage_flash, "color:a", 0.0, 0.45)\
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

func _create_day_label() -> void:
	_day_label = Label.new()
	_day_label.anchor_left   = 0.0
	_day_label.anchor_right  = 0.0
	_day_label.anchor_top    = 0.0
	_day_label.anchor_bottom = 0.0
	_day_label.offset_left   = 16.0
	_day_label.offset_right  = 180.0
	_day_label.offset_top    = 110.0
	_day_label.offset_bottom = 134.0
	_day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_day_label.add_theme_font_size_override("font_size", 13)
	_day_label.add_theme_color_override("font_color", Color(0.92, 0.82, 0.56))
	_day_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.065, 0.042, 0.88)
	bg.set_corner_radius_all(3)
	bg.content_margin_left   = 8.0
	bg.content_margin_right  = 8.0
	bg.content_margin_top    = 4.0
	bg.content_margin_bottom = 4.0
	_day_label.add_theme_stylebox_override("normal", bg)
	_day_label.visible = false
	add_child(_day_label)

func update_day(wave: int, max_days: int) -> void:
	if not is_instance_valid(_day_label):
		return
	_day_label.text = "Day %d / %d" % [wave, max_days]
	_day_label.visible = true

func _style_quit_button() -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.10, 0.08, 0.05, 1.0)
	normal.set_border_width_all(1)
	normal.border_color = Color(0.50, 0.40, 0.22, 0.8)
	normal.set_corner_radius_all(3)

	var hover := normal.duplicate()
	hover.bg_color     = Color(0.18, 0.14, 0.08, 1.0)
	hover.border_color = Color(0.78, 0.62, 0.30, 1.0)

	_quit_btn.add_theme_stylebox_override("normal",  normal)
	_quit_btn.add_theme_stylebox_override("hover",   hover)
	_quit_btn.add_theme_stylebox_override("pressed", normal)
	_quit_btn.add_theme_stylebox_override("focus",   StyleBoxEmpty.new())
