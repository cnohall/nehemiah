extends Node3D

# "horn" twist (Valley Gate — Neh. 4:18-20): "At the place where you hear the horn,
# gather to us." Any worker can sound it; everyone hears it, a standard goes up where
# it was blown and teammates off-screen get a pointer to it. Pure communication — the
# crew decides whether to answer. The enemy comes in surges here (WaveManager), which
# is what makes a call worth making.
# Server checks the request and the shared cooldown; every peer shows the call.

const COOLDOWN  := 8.0
const CALL_TIME := 9.0
const RING_SIZE := 6.0
const CLOTH     := Color(0.93, 0.88, 0.74)
const POLE      := Color(0.40, 0.29, 0.18)
const MARKER_SHADER := preload("res://assets/shaders/ground_marker.gdshader")

var _cooldown := 0.0

func _ready() -> void:
	add_to_group("horn")

func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)

## Server: a worker wants to sound the horn here. False if it was just blown.
func request(worker: Node3D, at: Vector3) -> bool:
	if not multiplayer.is_server() or not GameState.has_twist("horn") \
			or GameState.phase != GameState.Phase.WORK or _cooldown > 0.0:
		return false
	_cooldown = COOLDOWN
	_sound.rpc(Vector3(at.x, 0.0, at.z), worker.slot_color)
	return true

@rpc("authority", "call_local", "reliable")
func _sound(at: Vector3, color: Color) -> void:
	Sfx.play("horn")
	get_tree().call_group("camera_rig", "shake", 0.12)
	get_tree().call_group("offscreen_alerts", "ping", at, color, "Horn", CALL_TIME)
	_raise_standard(at, color)

# A pole with a cloth standard in the caller's colour and a slow ring on the ground
func _raise_standard(at: Vector3, color: Color) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = at
	# Pole beside the caller (screen-right), not hidden behind them
	var side := Vector3(1, 0, -1).normalized() * 1.3
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.08
	cyl.height = 3.4
	pole.mesh = cyl
	pole.material_override = _mat(POLE)
	pole.position = side + Vector3(0, 1.7, 0)
	root.add_child(pole)
	var flag := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.1, 0.7, 0.04)
	flag.mesh = box
	flag.material_override = _mat(color.lerp(CLOTH, 0.15))
	flag.position = side + Vector3(0.58, 2.95, 0)
	root.add_child(flag)
	var ring := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.orientation = PlaneMesh.FACE_Y
	quad.size = Vector2(RING_SIZE, RING_SIZE)
	ring.mesh = quad
	var rm := ShaderMaterial.new()
	rm.shader = MARKER_SHADER
	rm.set_shader_parameter("shadow_color", Color(0, 0, 0, 0))
	rm.set_shader_parameter("ring_color", Color(color, 0.85))
	rm.set_shader_parameter("ring_radius", 0.44)
	rm.set_shader_parameter("ring_width", 0.025)
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position.y = 0.14
	root.add_child(ring)
	# Rise, breathe, then fold away
	root.scale = Vector3(1, 0.01, 1)
	var tw := root.create_tween()
	tw.tween_property(root, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var pulse := ring.create_tween().set_loops(int(CALL_TIME / 0.9))
	pulse.tween_property(ring, "scale", Vector3.ONE * 1.1, 0.45).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(ring, "scale", Vector3.ONE * 0.92, 0.45).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(CALL_TIME)
	tw.tween_property(root, "scale", Vector3(1, 0.01, 1), 0.3)
	tw.tween_callback(root.queue_free)

static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m
