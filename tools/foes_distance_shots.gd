extends SceneTree

# The three foes together on the real map at the play camera's zoom, to judge whether their
# silhouettes read apart at a glance (the question is the shape, so the shots are also
# written as flat black cut-outs).
#   Godot --path . --script res://tools/foes_distance_shots.gd -- --nostory <out_dir> [tag]
# Not headless — needs the GPU.

var _out := ""
var _tag := "foes"
var _main: Node3D
var _t := 0.0
var _frame := 0
var _step := 0
var _pending := ""
var _pending_frames := 0

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
			var img := root.get_texture().get_image()
			img.save_png("%s/%s_%s.png" % [_out, _tag, _pending])
			_pending = ""
			_step += 1
		return false
	if _step == 0 and _t > 0.5:
		_main.director.begin()
		_step = 1
	elif _step == 1 and _t > 4.0:
		_pose()
		_step = 2
	elif _step == 2 and _t > 5.0:
		_pending = "play"
		_pending_frames = 4
		_step = 3
	elif _step == 4:
		return true
	return false

# Three of each kind in a row on open ground north of the wall, walking toward the camera
func _pose() -> void:
	var cam: Camera3D = _main.get_node("Camera3D")
	_main.set_process(false)
	_main.hud.hide()
	var kinds := ["scout", "brute", "raider"]
	var stage := Node3D.new()
	_main.add_child(stage)
	for k in 3:
		for i in 3:
			var look := CharacterRig.enemy_look(kinds[k])
			var rig := CharacterRig.new()
			stage.add_child(rig)
			rig.position = Vector3(-4.0 + k * 4.0 + (i - 1) * 1.4, 0, -8.0 + i * 0.9)
			rig.setup(look, 1.2 if kinds[k] == "brute" else 1.0)
			rig.play("walk_down")
	cam.global_position = Vector3(0.0, 0.8, -7.0) + cam.global_basis.z * 40.0
