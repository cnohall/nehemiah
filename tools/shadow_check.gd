extends SceneTree

# Sun shadow map sizes side by side on the same frames: play zoom and close.
#   Godot --path . --script res://tools/shadow_check.gd -- --nostory <out_dir> [size_a] [size_b]
var _out := "res://build/shadows"
var _sizes := [8192, 4096]
var _main: Node3D
var _frame := 0
const SHOTS := [[Vector2(3.0, 4.0), 18.0, "play"], [Vector2(6.0, 3.0), 7.0, "close"], [Vector2(-2.0, 12.0), 11.0, "city"]]

func _initialize() -> void:
	var rest: Array = []
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			rest.append(a)
	if rest.size() > 0:
		_out = rest[0]
	if rest.size() > 2:
		_sizes = [int(rest[1]), int(rest[2])]
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(1920, 1080)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_main.director.begin()
		var settings: Node = root.get_node("Settings")
		settings.quality = 2
		settings.render_scale = 1.0
		settings._apply_graphics()
		_main.hud.visible = false
	# Each shot: frame it, then take it at both sizes a few frames apart
	var step := _frame - 30
	if step < 0:
		return false
	var shot := step / 20
	if shot >= SHOTS.size():
		return true
	var t := step % 20
	var s: Array = SHOTS[shot]
	if t == 0:
		var cam: Camera3D = _main.get_node("Camera3D")
		cam.size = s[1]
		cam.global_position = Vector3(s[0].x, 0.0, s[0].y) + _main.CAM_OFFSET
		RenderingServer.directional_shadow_atlas_set_size(_sizes[0], true)
	if t == 8:
		root.get_texture().get_image().save_png("%s/%s_%d.png" % [_out, s[2], _sizes[0]])
		RenderingServer.directional_shadow_atlas_set_size(_sizes[1], true)
	if t == 16:
		root.get_texture().get_image().save_png("%s/%s_%d.png" % [_out, s[2], _sizes[1]])
	return false
