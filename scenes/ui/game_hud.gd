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

func _ready() -> void:
	_pause_overlay.visible = false
	_sling_container.visible = false
	_wall_needs.visible = false
	_quit_btn.pressed.connect(func(): get_tree().quit())
	_style_quit_button()
	_setup_sling_fill()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed and not event.echo:
		_toggle_pause()
		get_viewport().set_input_as_handled()

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
	var fill: StyleBoxFlat = _sling_bar.get_meta("fill_style")
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
	_sling_bar.set_meta("fill_style", fill)

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
