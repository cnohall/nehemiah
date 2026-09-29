extends SceneTree

# "Walk the City" screenshots at the Water Gate: hear Ezra, fetch branches, raise a
# booth, send a portion. The round of every stretch: festival_tour.gd
#   Godot --path . --script res://tools/festival_shots.gd -- <out_dir> [--lang=ko]
# Not headless — needs the GPU.

var _out := ""
var _main: Node3D
var _t := 0.0
var _step := 0
var _frame := 0

const SCRIPT := [
	[2.5, "shot", "start"],
	[2.6, "goto", Vector3(1.0, 0.1, 8.0)],
	[3.0, "press"], [3.1, "release"],
	[3.6, "shot", "ezra"],
	[3.8, "goto", Vector3(3.0, 0.1, -8.4)],
	[4.2, "press"], [4.3, "release"],
	[4.8, "shot", "branches"],
	[5.0, "goto", Vector3(-7.0, 0.1, 11.2)],
	[5.3, "press"], [5.4, "release"],
	[5.6, "fill_booth"],
	[5.8, "press"], [5.9, "release"],
	[7.4, "shot", "booth_rising"],
	[9.5, "shot", "booth_built"],
	[9.6, "goto", Vector3(8.0, 0.1, 10.2)],
	[9.9, "press"], [10.0, "release"],
	[10.2, "goto", Vector3(-9.5, 0.1, 23.8)],
	[10.5, "press"], [10.6, "release"],
	[11.2, "shot", "portion"],
	[11.5, "quit"],
]

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lang="):
			# Through Settings (not saved), so the autoloads' apply() doesn't undo it
			var settings := root.get_node("Settings")
			settings.language = a.trim_prefix("--lang=")
			settings.apply()
		elif not a.begins_with("--"):
			_out = a
	root.size = Vector2i(1920, 1080)
	root.get_node("GameState").festival = true
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_t += delta
	while _step < SCRIPT.size() and _t >= SCRIPT[_step][0]:
		var s: Array = SCRIPT[_step]
		_step += 1
		match s[1]:
			"goto":
				var me: Node3D = _main.get_node("Players").get_child(0)
				me.global_position = s[2]
			"press": Input.action_press("interact")
			"release": Input.action_release("interact")
			"fill_booth":
				var b: Node = _main.get_node("Festival/Booth0")
				b.pending = b.COST
			"shot":
				var img := root.get_texture().get_image()
				img.save_png("%s/%s.png" % [_out, s[2]])
			"quit": return true
	return false
