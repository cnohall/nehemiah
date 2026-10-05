extends SceneTree

# Build-site sign heights: wall at each stage + a watch post, bare and built.
#   Godot --path . --script res://tools/sign_shots.gd -- --nostory <out_dir>

var _out := ""
var _main: Node3D
var _t := 0.0
var _step := 0
var _frame := 0
var _post: Node3D
var _wall: Node3D

const SCRIPT := [
	[0.5, "begin"],
	[1.5, "setup"],
	[3.0, "near_post"],
	[9.0, "shot", "post_bare"],
	[9.1, "quit"],
]

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	root.size = Vector2i(1280, 720)
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
		var me: Node3D = _main.get_node("Players").get_child(0)
		match s[1]:
			"begin": _main.director.begin()
			"setup":
				_post = get_nodes_in_group("watch_posts")[0]
				for w in _main.get_node("Wall").get_children():
					if w.has_method("is_built") and w.is_target:
						_wall = w
				print("post ", _post.global_position, " wall ", _wall.global_position if _wall else "none")
			"near_post":
				me.global_position = _post.global_position + Vector3(1.2, 0.1, 1.2)
			"stones":
				_post.ammo = 3
			"post_built":
				_post.built = true
			"near_wall":
				_wall.stage = s[2]
				me.global_position = _wall.global_position + Vector3(2.0, 0.1, 3.0)
			"shot":
				root.get_texture().get_image().save_png("%s/%s.png" % [_out, s[2]])
			"quit": return true
	return false
