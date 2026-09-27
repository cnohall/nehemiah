extends SceneTree

# Offline gameplay screenshots for visual review:
#   Godot --path . --script res://tools/play_shots.gd -- --nostory <out_dir> [script]
# Starts Main as a solo host, begins day 1, drives the player with a short scripted
# input sequence and saves a PNG at each "shot" step. Not headless — needs the GPU.

var _out := ""
var _main: Node3D
var _t := 0.0
var _step := 0
var _frame := 0
var _shot := 0

# [time (s), action, arg] — actions: press/release an input action, shot, begin, pad, quit
const SCRIPT := [
	[0.5, "begin", null],
	[1.0, "shot", "gather_or_dawn"],
	[1.2, "press", "move_south"],
	[2.0, "release", "move_south"],
	[2.1, "shot", "moved"],
	[6.5, "shot", "work_start"],
	[6.6, "press", "interact"],
	[6.7, "release", "interact"],
	[7.0, "shot", "carry"],
	[7.1, "press", "move_north"],
	[8.3, "release", "move_north"],
	[8.4, "shot", "walk_carry"],
	[8.5, "press", "dash"],
	[8.55, "release", "dash"],
	[8.6, "shot", "dash"],
	[12.0, "pad", null],
	[12.1, "press", "throw_charge"],
	[12.8, "shot", "sling_charge"],
	[13.0, "release", "throw_charge"],
	[13.3, "shot", "sling_throw"],
	[16.0, "shot", "enemies"],
	[16.1, "quit", null],
]

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	root.size = Vector2i(1920, 1080)
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
			"begin": _main.director.begin()
			"press": Input.action_press(s[2])
			"release": Input.action_release(s[2])
			"shot":
				_shot += 1
				var img := root.get_texture().get_image()
				img.save_png("%s/%02d_%s.png" % [_out, _shot, s[2]])
			"pad":
				# Pretend a gamepad is in use (stick aim, pad hints)
				var ev := InputEventJoypadButton.new()
				ev.button_index = JOY_BUTTON_LEFT_STICK
				ev.pressed = true
				Input.parse_input_event(ev)
			"quit": return true
	return false
