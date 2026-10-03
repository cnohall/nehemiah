extends SceneTree

# Friends and Foes in each art style: a friend, a met foe and an unmet one per style.
#   Godot --path . --script res://tools/folk_style_shots.gd -- <out_dir>
# Puts the player's own art style back afterwards. Not headless - needs the GPU.

const PICKS := [0, 5, 8]     # Nehemiah, Sanballat, the fourth leader (unmet until met)
const HOLD := 25

var _out := "."
var _menu: Control
var _page: Control
var _saved := 0
var _frame := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	root.size = Vector2i(1920, 1080)

func _process(_delta: float) -> bool:
	var settings := root.get_node("Settings")
	_frame += 1
	if _frame == 1:
		_saved = settings.art_style
		_menu = load("res://scenes/ui/main_menu.tscn").instantiate()
		root.add_child(_menu)
		current_scene = _menu
		return false
	if _frame == 40:
		_page = _menu.get("_folk")
		_page.open()
	if _frame < 40:
		return false
	var k := (_frame - 40) / HOLD
	var style := k / PICKS.size()
	if style >= settings.ART_STYLES.size():
		settings.art_style = _saved
		return true
	if (_frame - 40) % HOLD == 1:
		settings.art_style = style
		(_page.get("_medals")[PICKS[k % PICKS.size()]] as Control).grab_focus()
	elif (_frame - 40) % HOLD == HOLD - 1:
		root.get_texture().get_image().save_png("%s/%s_%02d.png" % [_out,
			settings.ART_STYLES[style].to_lower(), PICKS[k % PICKS.size()]])
	return false
