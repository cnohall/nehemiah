extends SceneTree

# Friends and Foes screenshots: the main menu, a few entries on the page, then the
# section picker's detail panel on a few stretches.
#   Godot --path . --script res://tools/folk_shots.gd -- <out_dir> [--unlock-all]
# Without --unlock-all, foes this player hasn't met show as silhouettes.

const PICKS := [0, 1, 5, 7, 8, 9, 10, 11]
const SECTIONS := [0, 2, 5, 10, 11]
const HOLD := 30

var _out := "."
var _menu: Control
var _page: Control
var _frame := 0
var _pick := -1

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	root.size = Vector2i(1920, 1080)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_menu = load("res://scenes/ui/main_menu.tscn").instantiate()
		root.add_child(_menu)
		current_scene = _menu
	elif _frame == 60:
		_shot("menu")
		_page = _menu.get("_folk")
		_page.open()
		_pick = 0
	elif _pick >= 0 and (_frame - 60) % HOLD == HOLD - 1:
		if _pick < PICKS.size():
			_shot("folk_%02d" % PICKS[_pick])
		else:
			_shot("picker_%02d" % SECTIONS[_pick - PICKS.size()])
		_pick += 1
		if _pick == PICKS.size():
			_page.close()
			_menu._open_picker()
		if _pick >= PICKS.size() + SECTIONS.size():
			return true
		if _pick < PICKS.size():
			_page._medals[PICKS[_pick]].grab_focus()
		else:
			_menu._picker._select(SECTIONS[_pick - PICKS.size()])
	return false

func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, name])
