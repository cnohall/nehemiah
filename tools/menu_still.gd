extends SceneTree

# The title screen's still (assets/ui/menu_bg.jpg): the menu's own live backdrop
# (GameState.attract), a little way into the day — the wall rising, the crew right of
# the menu, a foe coming on. The menu dissolves from it into the live world. Rerun
# after any art change to the world:
#   Godot --path . --script res://tools/menu_still.gd [-- [--at=<s>[,<s>...]] <out.jpg>]
# Several times → one run, each saved as <out>_<s>.jpg, to pick a frame from.
# Not headless — needs the GPU.

const SHOT_AT := 38.0   # s into the attract run
var _ats: Array[float] = [SHOT_AT]

var _out := "res://assets/ui/menu_bg.jpg"
var _t := 0.0
var _frame := 0
var _multi := false

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--at="):
			_ats.clear()
			for t in a.trim_prefix("--at=").split(","):
				_ats.append(t.to_float())
			_ats.sort()
		elif not a.begins_with("--"):
			_out = a
	_multi = _ats.size() > 1
	root.size = Vector2i(1920, 1080)

func _process(delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		root.get_node("GameState").attract = true
		var main: Node = load("res://scenes/main/main.tscn").instantiate()
		root.add_child(main)
		current_scene = main
	if _frame < 3:
		return false
	_t += delta
	if _t < _ats[0]:
		return false
	var path := ProjectSettings.globalize_path(_out) if _out.begins_with("res://") else _out
	var at: float = _ats.pop_front()
	if _multi:
		path = "%s_%d.jpg" % [path.get_basename(), roundi(at)]
	root.get_texture().get_image().save_jpg(path, 0.9)
	print("menu still → ", path)
	return _ats.is_empty()
