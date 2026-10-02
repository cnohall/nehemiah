class_name Bird
extends Node3D

# One bird about the site — a sparrow, dove, pigeon or raven —
# pecking and hopping on the ground until something comes too close, then off and up
# and away out of sight; a while later it flies back in and lands near where it was.
# Purely cosmetic and local to each peer: Birds decides when a flock goes and returns.

enum State { GROUND, FLEE, AWAY, RETURN }

const SIZE := 1.8          # drawn bigger than life so they read beside the chibi crew
const FLEE_TIME := 3.2     # s climbing away before it's gone from sight
const RETURN_TIME := 2.6   # s gliding back in
const WANDER := 0.9        # how far it pecks about from where it landed
const FLAP_RATE := 34.0    # rad/s of wing phase in the air

const LOOKS := {
	#            body                        head                        wing                        tail                        scale
	"sparrow": [Color(0.55, 0.40, 0.27), Color(0.47, 0.42, 0.38), Color(0.40, 0.28, 0.18), Color(0.36, 0.27, 0.20), 1.0],
	"dove":    [Color(0.77, 0.60, 0.44), Color(0.68, 0.48, 0.34), Color(0.62, 0.42, 0.31), Color(0.49, 0.32, 0.26), 1.25],
	"pigeon":  [Color(0.65, 0.64, 0.66), Color(0.48, 0.49, 0.55), Color(0.73, 0.71, 0.72), Color(0.36, 0.35, 0.42), 1.35],
	"raven":   [Color(0.16, 0.17, 0.22), Color(0.12, 0.13, 0.18), Color(0.22, 0.23, 0.29), Color(0.11, 0.12, 0.17), 1.6],
}
const BEAK := Color(0.24, 0.20, 0.18)

var kind := "sparrow"
var state := State.GROUND

var _spot := Vector3.ZERO   # where it landed; it wanders about this
var _body: Node3D
var _wings: Array[Node3D] = []
var _vel := Vector3.ZERO
var _delay := 0.0
var _t := 0.0
var _next := 0.0            # s until the next peck / hop / look round
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _flap := 0.0
var _busy: Tween

static var _mats := {}

func setup(k: String, at: Vector3) -> void:
	kind = k
	_spot = at
	position = at
	rotation.y = randf() * TAU
	scale = Vector3.ONE * SIZE * LOOKS[kind][4]
	_next = randf_range(0.2, 2.0)

func _ready() -> void:
	var look: Array = LOOKS[kind]
	_body = Node3D.new()
	add_child(_body)
	_part(_sphere(0.1, 0.2), look[0], Vector3(0, 0.13, 0), Vector3.ZERO, Vector3(1.1, 1.0, 1.65)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_part(_sphere(0.075, 0.15), look[1], Vector3(0, 0.235, -0.115))
	_part(_sphere(0.069, 0.08), look[0].lightened(0.13), Vector3(0, 0.12, -0.105), Vector3.ZERO, Vector3(1.0, 0.75, 0.9))
	if kind == "pigeon":
		_part(_sphere(0.077, 0.09), Color(0.36, 0.48, 0.43), Vector3(0, 0.205, -0.075), Vector3.ZERO, Vector3(1.08, 0.85, 1.0))
		_part(_sphere(0.078, 0.07), Color(0.49, 0.36, 0.48), Vector3(0, 0.19, -0.04), Vector3.ZERO, Vector3(1.08, 0.7, 1.0))
	_part(_cyl(0.0, 0.023, 0.075 if kind == "raven" else 0.05), BEAK, Vector3(0, 0.218, -0.208), Vector3(-PI * 0.5, 0, 0))
	for side: float in [-1.0, 1.0]:
		_part(_sphere(0.014, 0.025), Color(0.92, 0.58, 0.19) if kind == "raven" else Color(0.14, 0.1, 0.09), Vector3(side * 0.069, 0.253, -0.155))
		_part(_sphere(0.005, 0.009), Color(0.95, 0.9, 0.79), Vector3(side * 0.079, 0.26, -0.16))
		_part(_box(Vector3(0.013, 0.075, 0.012)), Color(0.54, 0.29, 0.25) if kind != "raven" else BEAK, Vector3(side * 0.05, 0.055, 0.06))
		for toe in 3:
			_part(_box(Vector3(0.009, 0.01, 0.045)), Color(0.54, 0.29, 0.25) if kind != "raven" else BEAK, Vector3(side * 0.05 + (toe - 1) * 0.014, 0.018, 0.024))
	for i in 5:
		_part(_sphere(0.024, 0.035), look[3], Vector3((i - 2) * 0.022, 0.115, 0.19 + absf(i - 2) * 0.008), Vector3(0.3, 0, 0), Vector3(0.8, 0.65, 2.6))
	for s: float in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(s * 0.07, 0.15, 0.0)
		_body.add_child(pivot)
		var wing := MeshInstance3D.new()
		wing.mesh = _sphere(0.14, 0.28)
		wing.material_override = _mat(look[2])
		wing.position = Vector3(s * 0.1, 0, 0.025)
		wing.scale = Vector3(1.0, 0.11, 0.64)
		wing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(wing)
		for feather in 5:
			var f := MeshInstance3D.new()
			f.mesh = _sphere(0.028, 0.056)
			f.material_override = _mat(look[2].darkened(0.06 + 0.055 * (feather % 2)))
			f.position = Vector3(s * (0.12 + feather * 0.018), 0.004, 0.08 - feather * 0.027)
			f.scale = Vector3(0.9, 1.0, 2.2)
			pivot.add_child(f)
		_wings.append(pivot)
	_fold(1.0)

# ── Driven by Birds ───────────────────────────────────────────

## Take off after `delay`, flying along `dir` (flat) and up
func flush(dir: Vector3, delay: float) -> void:
	if state == State.FLEE or state == State.AWAY:
		return
	if _busy:
		_busy.kill()
	state = State.FLEE
	_delay = delay
	_t = 0.0
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	_vel = flat.normalized() * randf_range(3.0, 4.0) + Vector3.UP * randf_range(4.5, 5.5)

## Fly back in from out of sight and land near `at`, after `delay`
func come_back(at: Vector3, delay: float) -> void:
	if state != State.AWAY:
		return
	state = State.RETURN
	_spot = at
	_to = at
	_delay = delay
	_t = 0.0
	_from = at + Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU) * 16.0 + Vector3.UP * 9.0

func is_home() -> bool:
	return state == State.GROUND

# ── Motion ────────────────────────────────────────────────────

func _process(delta: float) -> void:
	match state:
		State.GROUND:
			_next -= delta
			if _next <= 0.0 and not (_busy and _busy.is_running()):
				_idle()
		State.FLEE:
			if _delay > 0.0:
				_delay -= delta
				return
			_t += delta
			# Beat hard off the ground, then level out and speed away
			_vel.y = move_toward(_vel.y, 2.2, 3.0 * delta)
			var flat := Vector3(_vel.x, 0.0, _vel.z)
			_vel += flat.normalized() * 4.0 * delta
			position += _vel * delta
			_face(_vel, 0.5)
			_beat(delta, 1.0)
			if _t > FLEE_TIME:
				state = State.AWAY
				visible = false
		State.RETURN:
			if _delay > 0.0:
				_delay -= delta
				return
			visible = true
			_t += delta
			var s := minf(_t / RETURN_TIME, 1.0)
			var e := 1.0 - (1.0 - s) * (1.0 - s)
			var was := position
			position = _from.lerp(_to, e)
			position.y = lerpf(_from.y, _to.y, 1.0 - pow(1.0 - s, 3.0))
			_face(position - was, 0.3)
			if s < 0.7:
				_beat(delta, 0.8)
			else:
				_fold(0.0)   # wings held out, gliding in
				_body.rotation.x = lerpf(0.0, 0.5, (s - 0.7) / 0.3)   # flare to land
			if s >= 1.0:
				_land()

func _land() -> void:
	state = State.GROUND
	_body.rotation.x = 0.0
	rotation.x = 0.0
	rotation.z = 0.0
	_busy = create_tween()
	_busy.tween_method(_fold, 0.0, 1.0, 0.25)
	_next = randf_range(0.5, 1.5)

func _face(dir: Vector3, climb: float) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.000001:
		return
	rotation.y = atan2(-flat.x, -flat.z)
	rotation.x = clampf(atan2(dir.y, flat.length()), -climb, climb)

func _beat(delta: float, strength: float) -> void:
	_flap += FLAP_RATE * delta
	var a := sin(_flap) * 0.9 * strength + 0.1
	_wings[0].rotation.z = -a
	_wings[1].rotation.z = a
	_wings[0].scale.x = 1.0
	_wings[1].scale.x = 1.0

# 1 = folded against the body, 0 = held out level
func _fold(k: float) -> void:
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		_wings[i].rotation.z = -s * 0.55 * k
		_wings[i].scale.x = lerpf(1.0, 0.45, k)

# ── On the ground ─────────────────────────────────────────────

func _idle() -> void:
	var roll := randf()
	_busy = create_tween()
	if roll < 0.5:
		# Peck, once or twice
		for i in randi_range(1, 2):
			_busy.tween_property(_body, "rotation:x", -0.6, 0.07)
			_busy.tween_property(_body, "rotation:x", 0.0, 0.1)
		_next = randf_range(0.4, 1.6)
	elif roll < 0.85:
		# Sparrows hop; doves walk a few steps, heads bobbing
		var to := _spot + Vector3(randf_range(-WANDER, WANDER), 0.0, randf_range(-WANDER, WANDER))
		var d := to - position
		if d.length() > 0.35:
			to = position + d.normalized() * 0.35
		rotation.y = atan2(-(to.x - position.x), -(to.z - position.z))
		var steps := 1 if kind == "sparrow" else 3
		var from := position
		for i in steps:
			var at := from.lerp(to, float(i + 1) / steps)
			var lift := 0.08 if kind == "sparrow" else 0.0
			_busy.tween_property(self, "position", at + Vector3.UP * lift, 0.07)
			_busy.parallel().tween_property(_body, "position:z", -0.03 if kind == "dove" else 0.0, 0.07)
			_busy.tween_property(self, "position", at, 0.07)
			_busy.parallel().tween_property(_body, "position:z", 0.0, 0.07)
		_next = randf_range(0.3, 1.2)
	else:
		# Look round
		_busy.tween_property(self, "rotation:y", rotation.y + randf_range(-1.2, 1.2), 0.12)
		_next = randf_range(0.6, 2.0)

# ── Mesh helpers ──────────────────────────────────────────────

func _part(mesh: Mesh, color: Color, at: Vector3, rot := Vector3.ZERO, sc := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color)
	mi.position = at
	mi.rotation = rot
	mi.scale = sc
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(mi)
	return mi

static func _mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.9
		_mats[key] = m
	return _mats[key]

static func _sphere(r: float, h: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 8
	m.rings = 4
	return m

static func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = 6
	m.rings = 1
	return m

static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m
