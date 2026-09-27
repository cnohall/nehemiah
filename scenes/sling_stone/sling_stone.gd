extends Node3D

# Visual sling stone on every peer, lobbed on an arc. Damage is applied only on the server.
#   target set  → aim-assisted: homes on the (moving) target, always connects
#   target null → flies to the landing point; hits enemies within IMPACT_RADIUS of it

const SPEED         := 16.0
const ARC_HEIGHT    := 0.18   # peak height per metre of distance
const MAX_TIME      := 2.0
const IMPACT_RADIUS := 0.9
const BODY_HEIGHT   := 0.9    # aim at the torso, not the feet

var shooter := 0            # peer id of the thrower — credited if the stone fells an enemy
var _target: Node3D = null
var _land: Vector3
var _damage: float = 0.0
var _start: Vector3
var _t := 0.0
var _duration := 0.5
var _arc := 1.0

func _ready() -> void:
	_add_trail()

func init(target: Node3D, land: Vector3, damage: float) -> void:
	_target = target
	_land = land
	_damage = damage
	_start = global_position
	var dist := _start.distance_to(_aim())
	_duration = clampf(dist / SPEED, 0.12, MAX_TIME)
	_arc = dist * ARC_HEIGHT

func _aim() -> Vector3:
	if _target != null and is_instance_valid(_target):
		return _target.global_position + Vector3(0, BODY_HEIGHT, 0)
	return _land

func _process(delta: float) -> void:
	# Homing target died mid-flight → finish the arc at its last spot
	if _target != null and not is_instance_valid(_target):
		_target = null
	_t = minf(_t + delta / _duration, 1.0)
	global_position = _start.lerp(_aim(), _t) + Vector3.UP * sin(_t * PI) * _arc
	if _t >= 1.0:
		_impact()

func _impact() -> void:
	if multiplayer.is_server():
		if _target != null:
			_target.take_damage(_damage, shooter)
		else:
			for enemy: Node3D in get_tree().get_nodes_in_group("enemies"):
				var d := Vector2(enemy.global_position.x - _land.x, enemy.global_position.z - _land.z).length()
				if d <= IMPACT_RADIUS:
					enemy.take_damage(_damage, shooter)
					break
	if _target == null:
		_puff()
		Sfx.play("sling_miss", global_position)
	queue_free()

# Faint streak behind the stone (world-space particles left in its wake)
func _add_trail() -> void:
	var p := CPUParticles3D.new()
	p.local_coords = false
	p.amount = 18
	p.lifetime = 0.22
	p.spread = 0.0
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.0
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 1.0
	p.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0.2))
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.93, 0.88, 0.76, 0.55))
	ramp.set_color(1, Color(0.93, 0.88, 0.76, 0.0))
	p.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.12)
	quad.material = DustFx.material()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.mesh = quad
	add_child(p)

# Small dust kick where a stone lands (so misses read)
func _puff() -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 10
	p.lifetime = 0.6
	p.direction = Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, -4.0, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 0.9
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.87, 0.78, 0.60, 0.7))
	ramp.set_color(1, Color(0.87, 0.78, 0.60, 0.0))
	p.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.45, 0.45)
	quad.material = DustFx.material()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.mesh = quad
	get_tree().current_scene.add_child(p)
	p.global_position = _land + Vector3(0, 0.1, 0)
	p.emitting = true
	p.finished.connect(p.queue_free)
