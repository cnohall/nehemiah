extends SceneTree

# Diegetic HUD screenshots: the scribe's scroll, the watchmen's calls, the sun low.
#   Godot --path . --script res://tools/hud_shots.gd -- --nostory <out_dir> [--day=N]
# Not headless — needs the GPU.

var _out := ""
var _main: Node3D
var _t := 0.0
var _step := 0
var _frame := 0

const SCRIPT := [
	[0.5, "begin"],
	[6.5, "shot", "work_start"],
	[6.6, "wave"],
	[7.2, "shot", "wave_call"],
	[7.4, "piece"],
	[8.0, "shot", "piece_call"],
	[8.2, "breach"],
	[8.8, "shot", "breach_call"],
	[9.0, "evening"],
	[12.0, "shot", "sun_low"],
	[12.1, "quit"],
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
			"wave": call_group("watchmen", "warn_wave", Vector3(-12, 0, -14), false)
			"piece":
				var w: Node = _main.get_node("Wall/Section3")
				w.stage = 3
			"breach": root.get_node("GameState").add_breach()
			"evening":
				var gs: Node = root.get_node("GameState")
				gs.set_sun(gs.sun_total, gs.sun_total * 0.08)
			"shot":
				var img := root.get_texture().get_image()
				img.save_png("%s/%s.png" % [_out, s[2]])
			"quit": return true
	return false
