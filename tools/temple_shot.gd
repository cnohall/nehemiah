extends SceneTree

# Explore Jerusalem at the Sheep Gate: shots of the house of God from the lane, the gate and
# the court, in the turned view.
#   Godot --path . --script res://tools/temple_shot.gd -- <out_dir> --unlock-all
# (the feast only shows once the whole wall is built: --unlock-all)
# Not headless — needs the GPU.

const SPOTS := [Vector3(33.0, 0.1, 11.4), Vector3(38.0, 0.1, 14.0), Vector3(24.0, 0.1, 9.0)]

var _out := ""
var _main: Node3D
var _t := 0.0
var _n := 0

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
	# Straight to the Sheep Gate
	if _n == 0:
		_n = 1
		for c in _main.get_children():
			if c.has_method("_enter"):
				c._enter(0)
		return false
	var k := int((_t - 2.5) / 2.2)
	if k >= SPOTS.size() * 2:
		return true
	if k >= 0 and k % 2 == 0 and _n == k + 1:
		_me().global_position = SPOTS[k / 2]
		_n += 1
	elif k >= 0 and k % 2 == 1 and _n == k + 1:
		root.get_texture().get_image().save_png("%s/temple_%d.png" % [_out, k / 2])
		_n += 1
	return false
