extends SceneTree

# Temp: sling wind-up / cast poses on 8 aim yaws, iso camera, rig only (+ whirl copy).

var _out := "."
var _frame := 0
var _rigs: Array = []
var _whirls: Array = []
var _angle := 0.0
var _t := 0.0
var _phase := "windup"
var _shots := {0.3: "a_windup", 0.55: "b_windup", 0.85: "c_windup"}
var _slash_shots := {0.05: "d_cock", 0.11: "e_cock2", 0.19: "f_release", 0.26: "g_follow", 0.36: "h_settle"}

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	root.size = Vector2i(1600, 900)

func _setup() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 9.0
	world.add_child(cam)
	cam.global_transform = Transform3D(Basis(Vector3(0.707107, 0, -0.707107), Vector3(-0.408248, 0.816497, -0.408248), Vector3(0.57735, 0.57735, 0.57735)), Vector3(20, 21, 20))
	var sun := DirectionalLight3D.new()
	world.add_child(sun)
	sun.rotation_degrees = Vector3(-55, 40, 0)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.85, 0.78, 0.62)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.66, 0.6)
	world.add_child(env)
	var rig_script: GDScript = load("res://scenes/shared/character_rig.gd")
	for i in 8:
		var holder := Node3D.new()
		world.add_child(holder)
		# Row along the screen's horizontal (camera right)
		holder.position = Vector3(0.707107, 0, -0.707107) * (i - 3.5) * 1.9
		var rig: Node3D = rig_script.new()
		holder.add_child(rig)
		rig.setup(rig_script.worker_look(i % 4, Color(0.7, 0.3, 0.2)))
		rig.aim_yaw = i * TAU / 8.0
		rig.play("windup_down")
		_rigs.append(rig)
		var w := Node3D.new()
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new(); sm.radius = 0.09; sm.height = 0.15
		mi.mesh = sm
		mi.position.x = 0.42
		w.add_child(mi)
		var cord := MeshInstance3D.new()
		var cm := BoxMesh.new(); cm.size = Vector3(0.42, 0.03, 0.03)
		cord.mesh = cm; cord.position.x = 0.21
		w.add_child(cord)
		w.top_level = true
		world.add_child(w)
		_whirls.append(w)
		rig.posed.connect(_place.bind(i))

func _place(_delta: float, i: int) -> void:
	var rig: Node3D = _rigs[i]
	var w: Node3D = _whirls[i]
	w.visible = _phase == "windup" or _t < 0.19
	rig.whirl_phase = _angle
	var cam := root.get_camera_3d()
	var fig: Basis = rig.global_basis.orthonormalized()
	var fwd := Vector3(fig.z.x, 0.0, fig.z.z).normalized()
	var side := Vector3(fig.x.x, 0.0, fig.x.z).normalized()
	var to_cam := cam.global_basis.z
	if side.dot(to_cam) < 0.0:
		side = -side
	var z := (side + to_cam).normalized()
	var y := (Vector3.UP - z * z.dot(Vector3.UP)).normalized()
	var x := y.cross(z)
	var spin := -1.0 if x.dot(fwd) > 0.0 else 1.0
	w.global_transform = Transform3D(Basis(x, y, z) * Basis(Vector3.BACK, _angle * spin), rig.hand_position())

func _process(delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_setup()
		return false
	_t += delta
	_angle += lerpf(9.0, 24.0, minf(_t / 0.9, 1.0)) * delta
	var shots: Dictionary = _shots if _phase == "windup" else _slash_shots
	for at: float in shots.keys():
		if _t >= at:
			root.get_texture().get_image().save_png("%s/%s.png" % [_out, shots[at]])
			shots.erase(at)
			break
	if _phase == "windup" and _t >= 1.0:
		_phase = "slash"
		_t = 0.0
		for r in _rigs:
			r.play("slash_down")
	elif _phase == "slash" and _t >= 0.5:
		return true
	return false
