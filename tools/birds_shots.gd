extends SceneTree

# Birds and the lamps in the windows, screenshots:
#   Godot --path . --script res://tools/birds_shots.gd -- --nostory <out_dir>
# Not headless — needs the GPU.

var _out := ""
var _main: Node3D
var _t := 0.0
var _step := 0
var _frame := 0
var _flock: Dictionary

const SCRIPT := [
	[0.5, "begin"],
	[5.0, "near"],
	[7.5, "shot", "birds_ground"],
	[7.6, "walk_in"],
	[7.95, "shot", "birds_flush"],
	[8.5, "shot", "birds_climb"],
	[8.6, "city"],
	[8.7, "evening"],
	[10.5, "shot", "lamps_half"],
	[10.6, "night"],
	[13.5, "shot", "lamps_all"],
	[13.6, "quit"],
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
	var me: Node3D = _main.get_node("Players").get_child(0)
	var gs: Node = root.get_node("GameState")
	while _step < SCRIPT.size() and _t >= SCRIPT[_step][0]:
		var s: Array = SCRIPT[_step]
		_step += 1
		match s[1]:
			"begin": _main.director.begin()
			"near":
				var birds: Node = _main.get_node("Birds")
				_flock = birds._flocks.filter(func(f): return f.spot.z > 0.0 and f.kind == "sparrow")[0]
				me.global_position = _flock.spot - Vector3(2.6, 0, 2.6)   # the flock just below on screen
			"walk_in": me.global_position = _flock.spot - Vector3(1.6, 0, 1.6)
			"city": me.global_position = Vector3(8, 0.1, 13)
			"evening": gs.set_sun(gs.sun_total, gs.sun_total * 0.12)
			"night": gs.set_sun(gs.sun_total, gs.sun_total * 0.01)
			"shot":
				var img := root.get_texture().get_image()
				img.save_png("%s/%s.png" % [_out, s[2]])
			"quit": return true
	return false
