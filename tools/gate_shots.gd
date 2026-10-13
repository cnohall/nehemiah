extends SceneTree

# Close-ups of the gate at the play camera's angle, HUD hidden: the opening bare, then with
# the stretch finished (doors hung, or the gap sealed on a stretch with no gate).
#   Godot --path . --script res://tools/gate_shots.gd -- --nostory <out_dir> [tag] [--day=N]
# Not headless — needs the GPU.

var _out := ""
var _tag := "gate"
var _main: Node3D
var _t := 0.0
var _step := 0
var _frame := 0
var _pending := ""
var _pending_frames := 0

# [time (s), action, arg]
const SCRIPT := [
	[0.5, "begin", null],
	[6.0, "finish", null],
	[7.0, "shot", "wide", 9.0],
	[8.5, "shot", "near", 4.5],
	[9.6, "quit", null],
]

func _initialize() -> void:
	var rest: Array = []
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			rest.append(a)
	_out = rest[0]
	if rest.size() > 1:
		_tag = rest[1]
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(1920, 1080)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_t += delta
	if not _pending.is_empty():
		_pending_frames -= 1
		if _pending_frames <= 0:
			root.get_texture().get_image().save_png("%s/%s_%s.png" % [_out, _tag, _pending])
			_pending = ""
		return false
	while _step < SCRIPT.size() and _t >= SCRIPT[_step][0]:
		var s: Array = SCRIPT[_step]
		_step += 1
		match s[1]:
			"begin": _main.director.begin()
			"finish": _finish()
			"shot":
				_frame_gate(s[3])
				_pending = s[2]
				_pending_frames = 4
				return false
			"quit": return true
	return false

func _frame_gate(size: float) -> void:
	var cam: Camera3D = _main.get_node("Camera3D")
	_main.set_process(false)
	_main.hud.hide()
	cam.size = size
	var focus := Vector3(-4.0, 1.2, 0.0)
	cam.global_position = focus + cam.global_basis.z * 40.0

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
