extends SceneTree

# Draw-call / frame-time probe: a crowd of enemies on an iso camera.
#   Godot --path . --disable-vsync --script res://tools/perf_crowd.gd -- [--old] [--count=40]
var _old := false
var _count := 40
var _frame := 0
var _t0 := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--old":
			_old = true
		elif a.begins_with("--count="):
			_count = int(a.substr(8))
	root.size = Vector2i(1920, 1080)
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-45, -35, 0)
	key.shadow_enabled = true
	stage.add_child(key)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	floor_mesh.mesh = plane
	stage.add_child(floor_mesh)
	var kinds := ["scout", "brute", "raider"]
	for i in _count:
		var look := CharacterRig.enemy_look(kinds[i % 3])
		if _old:
			look["sculpted_body"] = false
			look["sculpted_builder"] = false
		var rig := CharacterRig.new()
		stage.add_child(rig)
		rig.position = Vector3((i % 8 - 3.5) * 1.2, 0, -(i / 8) * 1.2)
		rig.setup(look)
		rig.play("walk_down")
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 14
	stage.add_child(cam)
	cam.look_at_from_position(Vector3(9, 9, 9) + Vector3(0, 0, -2), Vector3(0, 0, -2))

func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 60:
		_t0 = Time.get_ticks_usec()
	if _frame == 360:
		var ms := (Time.get_ticks_usec() - _t0) / 300.0 / 1000.0
		print("%s count=%d draws=%d prims=%d objs=%d frame=%.2f ms" % ["OLD" if _old else "NEW", _count,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), ms])
		return true
	return false
