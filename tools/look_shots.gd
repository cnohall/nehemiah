extends SceneTree

# Art-direction check: the same views every run, to compare look changes side by side.
#   Godot --path . --script res://tools/look_shots.gd -- --nostory <out_dir> [tag]
# Shots: gameplay (default camera on the player mid-work), city (south), outside
# (north, enemy side), wide (whole site).

var _out := ""
var _tag := "look"
var _main: Node3D
var _frame := 0
var _t := 0.0
var _step := 0
var _pending := ""      # shot name waiting for the moved camera to render
var _pending_frames := 0

# [time, camera focus (x, z) or null for the live camera, size, name]
const SHOTS := [
	[7.5, null, 0.0, "gameplay"],
	[8.0, Vector2(-2.0, 20.0), 22.0, "city"],
	[8.5, Vector2(0.0, -14.0), 22.0, "outside"],
	[9.0, Vector2(0.0, 4.0), 40.0, "wide"],
]

func _initialize() -> void:
	var rest: Array = []
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			rest.append(a)
	_out = rest[0]
	if rest.size() > 1:
		_tag = rest[1]
	root.size = Vector2i(1920, 1080)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_main.director.begin()
		# A worker near the wall, so characters and props are in frame
		var p: Node3D = _main.get_node("Players").get_child(0)
		p.global_position = Vector3(-1.0, 0.1, 4.0)
	if _frame < 3:
		return false
	_t += delta
	if not _pending.is_empty():
		_pending_frames -= 1
		if _pending_frames <= 0:
			root.get_texture().get_image().save_png("%s/%s_%s.png" % [_out, _tag, _pending])
			_pending = ""
		return false
	if _step >= SHOTS.size():
		return true
	var s: Array = SHOTS[_step]
	if _t >= s[0]:
		_step += 1
		var cam: Camera3D = _main.get_node("Camera3D")
		if s[1] != null:
			_main.set_process(false)
			cam.size = s[2]
			cam.global_position = Vector3(s[1].x, 0.0, s[1].y) + _main.CAM_OFFSET
			_main.hud.hide()
		_pending = s[3]
		_pending_frames = 2
	return false
