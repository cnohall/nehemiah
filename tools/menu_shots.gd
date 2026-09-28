extends SceneTree

# Title screen over time: the painting, then the live world behind the menu.
#   Godot --path . --script res://tools/menu_shots.gd -- <out_dir> [--size=WxH]
# Shots at the times in SHOTS (seconds); prints GameState's day/phase at each.

const SHOTS := [1.0, 4.0, 8.0, 20.0, 45.0]

var _out := ""
var _t := 0.0
var _next := 0

func _initialize() -> void:
	var res := Vector2i(1920, 1080)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--size="):
			var wh := a.trim_prefix("--size=").split("x")
			res = Vector2i(int(wh[0]), int(wh[1]))
		elif not a.begins_with("--"):
			_out = a
	root.size = res
	var menu: Node = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu

func _process(delta: float) -> bool:
	_t += delta
	if _next < SHOTS.size() and _t >= SHOTS[_next]:
		var gs := root.get_node("GameState")
		print("t=%.0f section=%d day=%d phase=%d attract=%s" % [_t, gs.current_section_index, gs.current_day, gs.phase, gs.attract])
		root.get_texture().get_image().save_png("%s/menu_%02d.png" % [_out, int(SHOTS[_next])])
		_next += 1
	return _next >= SHOTS.size()
