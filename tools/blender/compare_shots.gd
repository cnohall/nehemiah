extends SceneTree

# The builder as built in code (left of each pair) and baked in Blender (right), in a few
# poses, for review:
#   Godot --path . --fixed-fps 30 --script res://tools/blender/compare_shots.gd -- <out_dir> [tag]
var _out := "res://build/blender/compare"
var _tag := "builder"
var _frame := 0
var _rigs: Array[CharacterRig] = []
var _camera: Camera3D
var _view := 0
var _stage: Node3D
const ANIMS := ["idle_down", "walk_down", "run_down", "build_down"]
const VIEWS := ["front", "iso", "back", "close", "head", "head_side", "body"]
const SHOOT_AT := 40

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
	root.size = Vector2i(1920, 1000)
	root.msaa_3d = Viewport.MSAA_4X
	_stage = Node3D.new()
	root.add_child(_stage)
	current_scene = _stage
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.40, 0.34, 0.29)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.78, 0.83, 1.0)
	env.environment.ambient_light_energy = 0.30
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_stage.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -35, 0)
	key.light_color = Color(1, 0.87, 0.70)
	key.light_energy = 1.15
	key.shadow_enabled = true
	_stage.add_child(key)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.44, 0.37, 0.30)
	floor_mesh.material_override = mat
	_stage.add_child(floor_mesh)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_stage.add_child(_camera)

func _spawn() -> void:
	var look := CharacterRig.worker_look(0, Palette.CREW[0])
	var baked := look.duplicate()
	baked["baked"] = "res://assets/models/figures/builder.glb"
	var i := 0
	for anim: String in ANIMS:
		for l: Dictionary in [look, baked]:
			var rig := CharacterRig.new()
			_stage.add_child(rig)
			rig.position = Vector3((i / 2 - 1.5) * 3.0 + (0.6 if i % 2 == 1 else -0.6), 0, 0)
			rig.setup(l)
			rig.play(anim)
			_rigs.append(rig)
			var meshes := rig.find_children("*", "MeshInstance3D", true, false).size()
			print("%s %s: %d mesh instances" % [anim, "baked" if l.has("baked") else "code", meshes])
			i += 1
	_set_view()

func _set_view() -> void:
	# The figures face the camera's "down" on their own (CharacterRig turns itself): orbit
	# the camera instead
	var yaw: float = [0.0, 0.6, PI, 0.35, 0.25, 0.9, 0.3][_view]
	var v: String = VIEWS[_view]
	var close := v == "close"
	var head := v.begins_with("head") or v == "body"
	var target := Vector3(-4.5, 1.25, 0) if close else (Vector3(-4.5, 1.72 if v != "body" else 0.85, 0) if head else Vector3(0, 1.0, 0))
	_camera.size = 2.4 if close else (1.15 if head else 5.6)
	_camera.look_at_from_position(target + Vector3(sin(yaw) * 8.0, 3.0 if head else (5.0 if close else 6.0), cos(yaw) * 8.0), target)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2 and _rigs.is_empty():
		_spawn()
	if _frame == SHOOT_AT:
		root.get_texture().get_image().save_png("%s/%s_%s.png" % [_out, _tag, VIEWS[_view]])
		_view += 1
		_frame = 3
		if _view == VIEWS.size():
			return true
		_set_view()
	return false
