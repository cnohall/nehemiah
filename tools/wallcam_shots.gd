extends SceneTree

# Wall cam screenshots: the stretch is finished at once (loads credited to the crew), then
# the camera runs along it with the names cut in.
#   Godot --path . --script res://tools/wallcam_shots.gd -- --nostory <out_dir> [--day=N]
# Not headless — needs the GPU.

var _out := ""
var _main: Node3D
var _t := 0.0
var _step := 0
var _frame := 0

const SCRIPT := [
	[0.5, "begin"],
	[6.5, "finish"],
	[7.3, "shot", "cam_a"],
	[8.3, "shot", "cam_b"],
	[9.3, "shot", "cam_c"],
	[10.3, "shot", "cam_d"],
	[12.5, "shot", "tally"],
	[12.6, "quit"],
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
			"finish": _finish()
			"shot":
				var img := root.get_texture().get_image()
				img.save_png("%s/%s.png" % [_out, s[2]])
			"quit": return true
	return false

# Credit each unit to a worker in turn, then raise every part
func _finish() -> void:
	var crew: Array = _main.get_node("Players").get_children()
	var units: Array = _main.director._units
	for i in units.size():
		var who: Node = crew[i % crew.size()]
		for k in 3:
			_main.director.note_load(int(who.name), units[i][0])
	for unit: Array in units:
		for part in unit:
			if "stage" in part:
				part.stage = 3
			elif "finished" in part:
				part.finished = true
