extends SceneTree

# The crew (four trades) and the four enemy types side by side, for model and pose review.
#   Godot --path . --script res://tools/cast_lineup.gd -- <out_dir> [tag]
# Views: front, iso (three-quarter from above), back, and "game" (the play camera's
# angle and zoom, so silhouettes can be judged at the size they're actually seen), then
# poses sampled from the animations.
var _out := "res://build/cast"
var _tag := "cast"
var _frame := 0
var _rigs: Array[CharacterRig] = []
var _camera: Camera3D
var _view := 0
var _stage_node: Node3D
const VIEWS := ["front", "iso", "back", "game", "run", "walk", "build", "sword", "windup", "slash", "cheer", "dabke"]
# Animated views: the pose sampled this far into the cycle (seconds)
const POSE_T := { "run": 0.16, "walk": 0.2, "build": 0.27, "sword": 0.12, "windup": 0.6, "slash": 0.2, "cheer": 0.3, "dabke": 0.7 }

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
	root.size = Vector2i(1800, 900)
	root.msaa_3d = Viewport.MSAA_4X
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.52, 0.38)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.95, 0.85, 0.72)
	env.environment.ambient_light_energy = 0.32
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	stage.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -35, 0)
	key.light_color = Color(1, 0.90, 0.76)
	key.light_energy = 1.15
	key.shadow_enabled = true
	stage.add_child(key)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.64, 0.42)
	floor_mesh.material_override = mat
	stage.add_child(floor_mesh)
	_stage_node = stage
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(_camera)

func _spawn() -> void:
	var looks: Array[Dictionary] = []
	for i in 4:
		looks.append(CharacterRig.worker_look(i, Palette.CREW[i]))
	for kind in ["scout", "brute", "raider", "saboteur"]:
		looks.append(CharacterRig.enemy_look(kind))
	var sizes := [1.0, 1.0, 1.0, 1.0, 1.0, 1.2, 1.0, 0.95]   # Enemy.SCALE
	for i in looks.size():
		var rig := CharacterRig.new()
		_stage_node.add_child(rig)
		rig.position = Vector3((i - (looks.size() - 1) * 0.5) * 1.7, 0, 0)
		rig.setup(looks[i], sizes[i])
		rig.play("idle_down")
		rig.process_mode = Node.PROCESS_MODE_DISABLED
		rig._apply_pose()
		_rigs.append(rig)
	_set_view()

func _set_view() -> void:
	var yaw: float = [0.0, -0.6, PI, 0.0, -0.9, -0.9, -0.9, -0.9, -0.9, -0.9, -0.6, -0.6][_view]
	var anim: String = VIEWS[_view] if POSE_T.has(VIEWS[_view]) else "idle"
	for r in _rigs:
		r.rotation.y = yaw
		r.play(anim + "_down")
		r._t = POSE_T.get(anim, 0.0)
		r._blend = 1.0
		r._apply_pose()
		r._secondary(0.016)
	var target := Vector3(0, 1.1, 0)
	if VIEWS[_view] == "game":
		# The play camera: looks down -x -z from high up; figures face "down" screen
		for r in _rigs:
			r.rotation.y = atan2(CharacterRig.DIR_VEC["down"].x, CharacterRig.DIR_VEC["down"].z)
		_camera.size = 12.0
		_camera.look_at_from_position(target + Vector3(14, 16, 14), target)
	else:
		_camera.size = 7.4
		_camera.look_at_from_position(target + Vector3(0, 3.0, 10), target)

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
