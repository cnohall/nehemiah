extends SceneTree

# Reproducible studio turnarounds, independent of gameplay UI and camera tracking.
# Godot --path . --script res://tools/builder_shots.gd -- <out_dir> [--before] [--body]
var _out := "res://build/builder-review"
var _before := false
var _body_review := false
var _rig: CharacterRig
var _camera: Camera3D
var _frame := 0
var _view := 0
const VIEWS := ["front", "three_quarter", "profile", "back", "full", "gameplay", "build", "hit_flash"]

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--before":
			_before = true
		elif arg == "--body":
			_body_review = true
		elif not arg.begins_with("--"):
			_out = arg
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(1200, 1200)
	root.msaa_3d = Viewport.MSAA_4X
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.40, 0.34, 0.29)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.78, 0.83, 1.0)
	environment.environment.ambient_light_energy = 0.30
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	stage.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -35, 0)
	key.light_color = Color(1, 0.87, 0.70)
	key.light_energy = 1.15
	key.shadow_enabled = true
	stage.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 135, 0)
	fill.light_color = Color(0.65, 0.75, 1)
	fill.light_energy = 0.30
	stage.add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.44, 0.37, 0.30)
	floor_mesh.material_override = floor_material
	stage.add_child(floor_mesh)
	_rig = CharacterRig.new()
	stage.add_child(_rig)
	var look := CharacterRig.worker_look(0, Color(0.16, 0.36, 0.83))
	if _before:
		if _body_review:
			look["sculpted_body"] = false
		else:
			look["sculpted_builder"] = false
	_rig.setup(look)
	_rig.play("idle_down")
	_rig.process_mode = Node.PROCESS_MODE_DISABLED
	_rig._apply_pose()
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(_camera)
	_set_view()

func _set_view() -> void:
	var yaw: float = [0.0, -0.60, -PI * 0.5, PI, -0.45, -0.45, -0.45, -0.60][_view]
	_rig.rotation.y = yaw
	var target := Vector3(0, 1.70, 0)
	_camera.size = 1.30
	var offset := Vector3(0, 0.20, 5)
	if _body_review and _view < 4:
		target = Vector3(0, 1.08, 0)
		_camera.size = 2.75
		offset = Vector3(0, 1.6, 5)
	if _view >= 4 and _view <= 6:
		target = Vector3(0, 1.08, 0)
		_camera.size = 2.75 if _view == 4 else 3.20
		offset = Vector3(0, 1.6 if _view == 4 else 4.5, 5)
	if _view == 6:
		_rig.play("build_down")
		_rig._t = 0.3
		_rig._apply_pose()
	if _view == 7:
		_rig.play("idle_down")
		_rig._t = 0
		_rig._apply_pose()
		_rig._set_flash(1.0)
	_camera.look_at_from_position(target + offset, target)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 12:
		var prefix := "before" if _before else "builder"
		var result := root.get_texture().get_image().save_png("%s/%s_%s.png" % [_out, prefix, VIEWS[_view]])
		if result != OK:
			push_error("Could not save builder review image: %s" % result)
			quit(1)
			return true
		_view += 1
		_frame = 0
		if _view == VIEWS.size():
			print("PASS: builder turnaround and gameplay poses rendered")
			return true
		_set_view()
	return false
