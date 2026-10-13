extends SceneTree

# One close-up of the wall with each stage side by side: bare footing, framed, stacked, mortared.
#   Godot --path . --script res://tools/wall_stage_shots.gd -- --nostory <out_dir> [tag]
# Section1..Section4's neighbours are set to different stages, so one frame shows the whole
# build order at the play camera's angle, HUD hidden. Not headless — needs the GPU.

var _out := ""
var _tag := "stages"
var _main: Node3D
var _t := 0.0
var _step := 0
var _frame := 0
var _pending := ""
var _pending_frames := 0

# [time (s), action, arg]
const SCRIPT := [
	[0.5, "begin", null],
	[5.0, "stages", null],
	[6.5, "shot", "all"],
	[8.0, "frame", "wide"],
	[9.5, "shot", "wide"],
	[10.0, "quit", null],
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
			"stages": _stages()
			"frame":
				pass
			"shot":
				_frame_wall(15.0 if s[2] == "all" else 7.0, -4.0 if s[2] == "all" else 8.0)
				_pending = s[2]
				_pending_frames = 4
				return false
			"quit": return true
	return false

func _frame_wall(size: float, x: float) -> void:
	var cam: Camera3D = _main.get_node("Camera3D")
	_main.set_process(false)
	_main.hud.hide()
	cam.size = size
	cam.global_position = Vector3(x, 0.8, 0.0) + cam.global_basis.z * 40.0

func _stages() -> void:
	var wall: Node = _main.get_node("Wall")
	var order := ["Section1", "Section3", "Section4"]
	var stages := [0, 1, 3]
	for i in order.size():
		var part: Node = wall.get_node(order[i])
		part.stage = stages[i]
	# The right tower stands finished, to give the finished face next to the rest
	wall.get_node("TowerRight").stage = 3
