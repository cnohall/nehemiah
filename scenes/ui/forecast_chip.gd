class_name ForecastChip
extends Label

# Experimental wave forecast (GDD §5.21): a parchment chip, top centre under the plaques,
# "Wave in 18 s · 3 scouts, 1 brute". WaveManager tells every peer through `show_forecast`.

const TOP := 150.0

var _what := ""
var _until := 0   # msec the wave comes in (its bell)
var _called := false

func _ready() -> void:
	add_to_group("forecast_chip")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_type_variation = &"Body"
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_theme_font_size_override("font_size", 17)
	add_theme_color_override("font_color", UiStyle.INK)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UiStyle.PARCHMENT, 0.92)
	sb.border_color = UiStyle.DUSK.lerp(UiStyle.TERRACOTTA, 0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(8)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	add_theme_stylebox_override("normal", sb)
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	position.y = TOP
	hide()

func show_forecast(what: String, seconds: float, called: bool) -> void:
	_what = what
	_called = called
	_until = Time.get_ticks_msec() + int(seconds * 1000.0)
	show()

func _process(_delta: float) -> void:
	var left := (_until - Time.get_ticks_msec()) / 1000.0
	if left < -1.5 or GameState.is_over() or GameState.phase != GameState.Phase.WORK:
		hide()
		return
	text = tr("Wave in %d s · %s") % [maxi(0, ceili(left)), _what] if left > 0.0 else tr("They come! · %s") % _what
	reset_size()
	position.y = TOP
