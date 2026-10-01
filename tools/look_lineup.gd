extends SceneTree

# Lineup of every sculpted look side by side, for style review.
#   Godot --path . --script res://tools/look_lineup.gd -- <out_dir> [tag]
var _out := "res://build/lineup"
var _tag := "lineup"
var _frame := 0
var _rigs: Array[CharacterRig] = []
var _camera: Camera3D
var _view := 0
var _stage_node: Node3D
const VIEWS := ["front", "iso", "back"]

func _initialize() -> void:
	var rest: Array = []
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			rest.append(a)
	if rest.size() > 0:
		_out = rest[0]
	if rest.size() > 1:
		_tag = rest[1]
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(1920, 900)
	root.msaa_3d = Viewport.MSAA_4X
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.40, 0.34, 0.29)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.78, 0.83, 1.0)
	env.environment.ambient_light_energy = 0.30
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	stage.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -35, 0)
	key.light_color = Color(1, 0.87, 0.70)
	key.light_energy = 1.15
	stage.add_child(key)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.44, 0.37, 0.30)
	floor_mesh.material_override = mat
	stage.add_child(floor_mesh)
	_stage_node = stage
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 9.5
	stage.add_child(_camera)

# Folk reads autoloads, so it is only loaded once the tree is running.
func _spawn() -> void:
	var stage := _stage_node
	var looks: Array[Dictionary] = []
	for i in 4:
		looks.append(CharacterRig.worker_look(i, Palette.CREW[i]))
	for kind in ["man", "woman", "child", "elder", "governor", "priest", "scribe"]:
		looks.append(_folk_look(kind))
	for kind in ["scout", "brute", "raider"]:
		looks.append(CharacterRig.enemy_look(kind))
	var cols := 7
	for i in looks.size():
		var rig := CharacterRig.new()
		stage.add_child(rig)
		rig.position = Vector3((i % cols - (cols - 1) * 0.5) * 1.5, 0, -(i / cols) * 3.2)
		rig.setup(looks[i])
		rig.play("idle_down")
		rig.process_mode = Node.PROCESS_MODE_DISABLED
		rig._apply_pose()
		_rigs.append(rig)
		print("parts[%d]=%d" % [i, rig._parts.size()])
	_set_view()

func _folk_look(kind: String) -> Dictionary:
	return load("res://scenes/festival/folk.gd").look_for(kind, Palette.INDIGO, 1)

func _set_view() -> void:
	var yaw: float = [0.0, -0.6, PI][_view]
	for r in _rigs:
		r.rotation.y = yaw
	var target := Vector3(0, 0.6, -3.2)
	_camera.look_at_from_position(target + Vector3(0, 6.0, 8), target)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2 and _rigs.is_empty():
		_spawn()
	if _frame == 12 and not _rigs.is_empty():
		root.get_texture().get_image().save_png("%s/%s_%s.png" % [_out, _tag, VIEWS[_view]])
		_view += 1
		_frame = 0
		if _view == VIEWS.size():
			return true
		_set_view()
	return false
