extends SceneTree

# Shots of the Sheep Gate flock moving (Flock): the fold over time, a worker walking
# into the strays, then a loud noise. Also checks no sheep left its fold or clipped
# another. Pass an output directory.
# Godot --path . --script res://tools/sheep_motion.gd -- --nostory <out_dir>

var _main: Node3D
var _output := ""
var _frame := 0
var _flock: Flock
var _player: Node3D
var _bad := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			_output = arg
	DirAccess.make_dir_recursive_absolute(_output)
	root.size = Vector2i(1280, 720)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 4:
		_main.director.begin()
	if _frame == 20:
		_main.set_process(false)
		_main.hud.visible = false
		_flock = _main.get_node("SectionTerrain/Flock")
		_player = _main.get_node("Players").get_child(0)
		_player.global_position = Vector3(10.0, 0.1, 8.0)
		_set_camera(9.0, Vector3(-15.0, 0.0, -7.2))
	if _frame > 20:
		_audit()
	# The fold over ~40 s (at 60 fps)
	if _frame in [30, 330, 630, 930, 1230, 1530, 1830, 2130, 2430]:
		_capture("fold_%04d" % _frame)
	if _frame == 2440:
		_set_camera(9.0, Vector3(-7.0, 0.0, -9.8))
		_capture("strays_before")
	if _frame == 2450:
		_player.global_position = Vector3(-5.5, 0.1, -8.4)
	if _frame in [2470, 2510, 2560]:
		_capture("strays_shy_%04d" % _frame)
	if _frame == 2600:
		_player.global_position = Vector3(10.0, 0.1, 8.0)
		_set_camera(9.0, Vector3(-15.0, 0.0, -7.2))
	if _frame == 2900:
		root.get_node("Sfx").play("shatter", Vector3(-15.0, 0.0, -4.5))
	if _frame in [2915, 2950, 3000]:
		_capture("startle_%04d" % _frame)
	if _frame == 3010:
		print("sheep_motion: %d bad frames" % _bad)
		return true
	return false

# Inside the fold, and no pair closer than the gap (or than they were laid out)
var _start := {}
func _audit() -> void:
	var sheep: Array = _flock.get("_sheep")
	for i in sheep.size():
		var a: Dictionary = sheep[i]
		var ea := Flock._capsule(a.pos, a.yaw, a.s.x)
		if a.pen_r > 0.0 and not Flock.in_pen(ea, a.pen_c, a.pen_r + 0.05, a.s.x):
			_bad += 1
			print("frame %d: sheep %d out of fold" % [_frame, i])
		for j in range(i + 1, sheep.size()):
			var b: Dictionary = sheep[j]
			var d := Flock.apart(ea, Flock._capsule(b.pos, b.yaw, b.s.x))
			var key := i * 100 + j
			if not _start.has(key):
				_start[key] = d
			if d < minf(Flock.RADIUS * (a.s.x + b.s.x), _start[key]) - 0.05:
				_bad += 1
				print("frame %d: sheep %d and %d overlap" % [_frame, i, j])

func _set_camera(size: float, target: Vector3) -> void:
	var cam: Camera3D = _main.get_node("Camera3D")
	cam.size = size
	cam.global_position = target + cam.global_basis.z * _main.CAM_OFFSET.length()

func _capture(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [_output, name])
