extends SceneTree

# North-up view (Settings.turn_to_map), the campaign compass, the true sun and the
# watchmen's quarters on one section:
#   Godot --path . --script res://tools/view_shots.gd -- --nostory --day=N <out_dir> [--turn]
# Saves <out_dir>/view_<section>_<turn|across>_<morning|evening>.png. Not headless.

var _out := ""
var _turn := false
var _main: Node3D
var _t := 0.0
var _step := 0
var _frame := 0

const SCRIPT := [
	[0.5, "begin"],
	[1.5, "goto", Vector3(0, 0.1, 6)],
	[5.0, "wave"],
	[5.6, "shot", "morning"],
	[5.7, "evening"],
	[9.0, "shot", "evening"],
	[9.1, "quit"],
]

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--turn":
			_turn = true
		elif not a.begins_with("--"):
			_out = a
	root.get_node("Settings").turn_to_map = _turn
	root.size = Vector2i(1920, 1080)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_t += delta
	var gs: Node = root.get_node("GameState")
	while _step < SCRIPT.size() and _t >= SCRIPT[_step][0]:
		var s: Array = SCRIPT[_step]
		_step += 1
		match s[1]:
			"begin": _main.director.begin()
			"goto":
				var me: Node3D = _main.get_node("Players").get_child(0)
				me.global_position = s[2]
			"wave":
				var i: int = gs.current_section_index
				var RingCompass: GDScript = load("res://scenes/festival/ring_compass.gd")   # not at compile: autoloads come later
				print("view: section %d %s  yaw %.2f  west end %s  east end %s" % [i, gs.get_current_section()["name"],
					_main.view_yaw, RingCompass.quarter(i, Vector3(-1, 0, -1)), RingCompass.quarter(i, Vector3(1, 0, -1))])
				call_group("watchmen", "warn_wave", Vector3(-12, 0, -14), false)
			"evening":
				gs.set_sun(gs.sun_total, gs.sun_total * 0.08)
			"shot":
				var img := root.get_texture().get_image()
				img.save_png("%s/view_%d_%s_%s.png" % [_out, gs.current_section_index, "turn" if _turn else "across", s[2]])
			"quit": return true
	return false
