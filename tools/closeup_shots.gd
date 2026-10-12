extends SceneTree

# Close-ups of the world's props at the play camera's angle, HUD hidden, for detail review.
#   Godot --path . --script res://tools/closeup_shots.gd -- --nostory <out_dir> [tag] [x,z,size,name ...]
# Default shots: the supply yard, the wall line, the enemy camp, a house row, the work camp.
# Works with any camera turn (the shot backs off along the camera's own axis).

var _out := ""
var _tag := "close"
var _main: Node3D
var _frame := 0
var _t := 0.0
var _step := 0
var _pending := ""
var _pending_frames := 0
var _shots: Array = [
	[Vector2(0.0, 9.5), 8.0, "yard"],
	[Vector2(2.0, 0.0), 8.0, "wall"],
	[Vector2(-2.0, -22.0), 9.0, "camp"],
	[Vector2(6.0, 20.0), 8.0, "houses"],
	[Vector2(-20.5, 8.0), 8.0, "workcamp"],
]

func _initialize() -> void:
	var rest: Array = []
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			rest.append(a)
	_out = rest[0]
	if rest.size() > 1:
		_tag = rest[1]
	if rest.size() > 2:
		_shots.clear()
		for spec: String in rest.slice(2):
			var f := spec.split(",")
			_shots.append([Vector2(float(f[0]), float(f[1])), float(f[2]), f[3]])
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(1920, 1080)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_main.director.begin()
	if _frame < 3:
		return false
	_t += delta
	if not _pending.is_empty():
		_pending_frames -= 1
		if _pending_frames <= 0:
			root.get_texture().get_image().save_png("%s/%s_%s.png" % [_out, _tag, _pending])
			_pending = ""
		return false
	if _step >= _shots.size():
		return true
	if _t >= 6.0 + _step * 0.5:
		var s: Array = _shots[_step]
		_step += 1
		var cam: Camera3D = _main.get_node("Camera3D")
		_main.set_process(false)
		_main.hud.hide()
		cam.size = s[1]
		var focus := Vector3(s[0].x, 0.0, s[0].y)
		cam.global_position = focus + cam.global_basis.z * 40.0
		_pending = s[2]
		_pending_frames = 3
	return false
