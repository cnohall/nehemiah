class_name Horn
extends Node3D

# "horn" twist (Valley Gate — Neh. 4:18-20): "At the place where you hear the horn,
# gather to us." Any worker can sound it; everyone hears it, a standard goes up where
# it was blown and teammates off-screen get a pointer to it. Pure communication — the
# crew decides whether to answer. The enemy comes in surges here (WaveManager), which
# is what makes a call worth making.
# Server checks the request and the shared cooldown; every peer shows the call.
#
# The reward is the rally: while a call stands, anyone inside its ring strikes harder
# (RALLY_DAMAGE) and cuts faster (RALLY_SWORD_CD) — "our God will fight for us" (4:20).
# Every peer tracks the calls it was told of, so damage and cooldown read the same
# everywhere; the standard says so in words, and whoever steps in is told once per call.

const COOLDOWN  := 8.0
const CALL_TIME := 9.0
const RING_SIZE := 7.0
const RALLY_RADIUS    := 3.0   # ≈ the drawn ring (RING_SIZE × ring_radius 0.44)
const RALLY_DAMAGE    := 1.5
const RALLY_SWORD_CD  := 0.6   # × the usual sword cooldown
const CLOTH     := Color(0.93, 0.88, 0.74)
const POLE      := Color(0.40, 0.29, 0.18)
const MARKER_SHADER := preload("res://assets/shaders/ground_marker.gdshader")

var _cooldown := 0.0
var _calls: Array = []   # { root, at, until (msec), ring, told: {worker_id: true} }

func _ready() -> void:
	add_to_group("horn")

func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_tend_calls()

## The standing call whose ring holds `pos`, or {}
func call_at(pos: Vector3) -> Dictionary:
	var now := Time.get_ticks_msec()
	for c: Dictionary in _calls:
		if c["until"] > now and Vector2(pos.x - c["at"].x, pos.z - c["at"].z).length() <= RALLY_RADIUS:
			return c
	return {}

## Blow strength for a worker standing at `pos` (1 outside any ring)
func rally_damage(pos: Vector3) -> float:
	return RALLY_DAMAGE if not call_at(pos).is_empty() else 1.0

func rally_sword_cd(pos: Vector3) -> float:
	return RALLY_SWORD_CD if not call_at(pos).is_empty() else 1.0

## The standing call a bot should gather to (the newest), or {}
func open_call() -> Dictionary:
	var now := Time.get_ticks_msec()
	for i in range(_calls.size() - 1, -1, -1):
		if _calls[i]["until"] > now:
			return _calls[i]
	return {}

# Brighten a ring while someone stands in it; tell each human, once per call, what it did
func _tend_calls() -> void:
	var now := Time.get_ticks_msec()
	_calls = _calls.filter(func(c): return c["until"] > now and is_instance_valid(c["root"]))
	if _calls.is_empty():
		return
	var players := get_tree().get_nodes_in_group("players")
	for c: Dictionary in _calls:
		var occupied := false
		for p: Node3D in players:
			if Vector2(p.global_position.x - c["at"].x, p.global_position.z - c["at"].z).length() > RALLY_RADIUS or p.downed:
				continue
			occupied = true
			if p.brain == null and p.is_multiplayer_authority() and not c["told"].has(p.worker_id()):
				c["told"][p.worker_id()] = true
				p._toast("Rallied: your blows land harder here")
		c["ring"].material_override.set_shader_parameter("ring_color", Color(c["color"], 1.0 if occupied else 0.7))

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
	get_tree().call_group("townsfolk", "heard_horn")
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
	# Says what it's for, in words, over the standard
	var tag := Label3D.new()
	tag.text = tr("RALLY: stronger blows here")
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.fixed_size = false
	tag.pixel_size = 0.005
	tag.font_size = 40
	tag.outline_size = 14
	tag.modulate = Color(0.98, 0.93, 0.78)
	tag.outline_modulate = Color(0.16, 0.11, 0.08)
	tag.position = side + Vector3(0.5, 3.45, 0)
	root.add_child(tag)
	_calls.append({ "root": root, "at": at, "color": color, "ring": ring, "told": {},
		"until": Time.get_ticks_msec() + int(CALL_TIME * 1000.0) })
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
