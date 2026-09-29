extends SceneTree

# Walk the City, round the whole wall: from the Water Gate, walk off the west end again
# and again; a shot of each stretch's middle, and of the arrival end.
#   Godot --path . --script res://tools/festival_tour.gd -- <out_dir>
# Not headless — needs the GPU.

const STEP := 3.0   # seconds per stretch

var _out := ""
var _main: Node3D
var _t := 0.0
var _leg := -1
var _phase := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	root.size = Vector2i(1920, 1080)
	root.get_node("GameState").festival = true
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _me() -> Node3D:
	return _main.get_node("Players").get_child(0)

func _process(delta: float) -> bool:
	_t += delta
	if _t < 2.0:
		return false
	var leg := int((_t - 2.0) / STEP)
	var k := fmod(_t - 2.0, STEP)
	if leg != _leg:
		_leg = leg
		_phase = 0
	if leg >= 13:
		return true
	var gs: Node = root.get_node("GameState")
	if _phase == 0 and k > 0.1:
		_phase = 1
		_me().global_position = Vector3(38.0, 0.1, 14.0 if gs.current_section_index == 0 else 6.0)   # the temple court fills the east end there
	elif _phase == 1 and k > 0.6:
		_phase = 2
		_shot("%02d_%d_arrive" % [leg, gs.current_section_index])
		_me().global_position = Vector3(0.0, 0.1, 7.5)
	elif _phase == 2 and k > 1.4:
		_phase = 3
		_shot("%02d_%d_middle" % [leg, gs.current_section_index])
		print("tour: section %d  view_yaw %.2f" % [gs.current_section_index, _main.view_yaw])
		_me().global_position = Vector3(-43.0, 0.1, 6.0)   # off the west end: on round
	return false

func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, name])
