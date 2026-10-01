extends SceneTree

# The Broad Wall's two faces, stage by stage, on its plain stretches:
#   Godot --path . --script res://tools/thick_shots.gd -- --nostory --day=13 <out_dir>
# Poses the stretch at framing, outer face, both faces and mortared (one shot each)
# and saves <out_dir>/thick_<n>.png with the HUD hidden.

var _out := ""
var _main: Node3D
var _frame := 0
var _t := 0.0
var _step := -1
var _wait := 0
const POSES := [[1, 0], [1, 1], [2, 2], [3, 2]]   # stage, face

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	root.size = Vector2i(1600, 900)
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
	var gs = root.get_node("GameState")
	if _step == -1 and gs.phase == gs.Phase.WORK and _t > 2.0:
		_main.hud.hide()
		var me: Node3D = _main.get_node("Players").get_child(0)
		me.set_physics_process(false)
		me.global_position = Vector3(6.0, 0.1, 4.0)
		(_main.get_node("Camera3D") as Camera3D).size = 16.0
		_step = 0
		_pose()
		_wait = 40
		return false
	if _step >= 0:
		_wait -= 1
		if _wait > 0:
			return false
		var path := "%s/thick_%d.png" % [_out, _step]
		root.get_texture().get_image().save_png(path)
		print("thick_shots: saved ", path)
		_step += 1
		if _step >= POSES.size():
			return true
		_pose()
		_wait = 40
	if _t > 60.0:
		return true
	return false

func _pose() -> void:
	for part in _main.get_node("Wall").get_children():
		if part.is_in_group("wall_sections") and part.is_thick():
			part.face = POSES[_step][1]
			part.stage = POSES[_step][0]
