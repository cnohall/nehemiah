class_name SlingStone
extends Node3D

# Visual sling stone on every peer, lobbed on an arc. Damage is applied only on the server.
#   target set  → aim-assisted: homes on the (moving) target, always connects
#   target null → flies to the landing point; hits enemies within IMPACT_RADIUS of it
# Every peer works out what it struck for the sound and the look (thock, chips, the stone
# glancing off); a true shot (Player, GDD §5.16) flies gold and knocks the foe off his feet.

const SPEED         := 16.0
const ARC_HEIGHT    := 0.18   # peak height per metre of distance
const MAX_TIME      := 2.0
const IMPACT_RADIUS := 0.9
const BODY_HEIGHT   := 0.9    # aim at the torso, not the feet
const TRAIL_COLOR   := Color(0.93, 0.88, 0.76, 0.55)
const TRUE_COLOR    := Color(1.0, 0.84, 0.46, 0.85)
const CHIP_COLOR    := Color(0.58, 0.53, 0.46)
const PEBBLE_LIFE   := 3.5    # s a spent stone lies where it fell
const GROUND_Y      := 0.1
const RING_SHADER   := preload("res://assets/shaders/ground_marker.gdshader")

static var _flash_shader: Shader

var shooter := 0            # worker id (Player.worker_id) of the thrower — credited if the stone fells an enemy
var _target: Node3D = null
var _land: Vector3
var _damage: float = 0.0
var _knock := 0.0
var _true := false
var _start: Vector3
var _t := 0.0
var _duration := 0.5
var _arc := 1.0

func init(target: Node3D, land: Vector3, damage: float, knock := 0.0, true_shot := false) -> void:
	_target = target
	_land = land
	_damage = damage
	_knock = knock
	_true = true_shot
	_start = global_position
	var dist := _start.distance_to(_aim())
	_duration = clampf(dist / SPEED, 0.12, MAX_TIME)
	_arc = dist * ARC_HEIGHT
	_add_trail()
	if _true:
		var mi: MeshInstance3D = $Mesh
		mi.scale = Vector3.ONE * 1.3
		var mat := StandardMaterial3D.new()
		mat.albedo_color = CHIP_COLOR
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.8, 0.45)
		mat.emission_energy_multiplier = 1.2
		mi.material_override = mat

func _aim() -> Vector3:
	if _target != null and is_instance_valid(_target):
		return _target.global_position + Vector3(0, BODY_HEIGHT, 0)
	return _land

func _process(delta: float) -> void:
	# Homing target died mid-flight → finish the arc at its last spot
	if _target != null and not is_instance_valid(_target):
		_land = Vector3(_land.x, GROUND_Y, _land.z)
		_target = null
	_t = minf(_t + delta / _duration, 1.0)
	global_position = _start.lerp(_aim(), _t) + Vector3.UP * sin(_t * PI) * _arc
	rotate_x(delta * 25.0)
	if _t >= 1.0:
		_impact()

func _impact() -> void:
	var victim := _victim()
	if multiplayer.is_server():
		if victim != null:
			victim.take_damage(_damage, shooter)
			var dir := victim.global_position - _start
			if _true and victim.has_method("knock_down"):
				victim.knock_down(dir, _knock)
			elif _knock > 0.0:
				victim.knock_back(dir, _knock)
		if _target == null:
			get_tree().call_group("breakable_set", "smash_at", _land, IMPACT_RADIUS * 0.6)
	if victim != null:
		_struck(victim)
	else:
		_puff()
		Sfx.play("sling_miss", global_position)
	queue_free()

# What the stone strikes: the homing target, or the first foe within reach of where it lands
func _victim() -> Node3D:
	if _target != null:
		return _target if _target.is_in_group("enemies") else null
	for enemy: Node3D in get_tree().get_nodes_in_group("enemies"):
		var d := Vector2(enemy.global_position.x - _land.x, enemy.global_position.z - _land.z).length()
		if d <= IMPACT_RADIUS:
			return enemy
	return null

# Every peer: the sound and the look of a hit, and a jolt for whoever threw it
func _struck(victim: Node3D) -> void:
	var at := victim.global_position + Vector3(0, BODY_HEIGHT, 0)
	var back := Vector3(victim.global_position.x - _start.x, 0.0, victim.global_position.z - _start.z).normalized()
	Sfx.play("true_hit" if _true else "stone_thock", at)
	var scene := get_tree().current_scene
	_chips(scene, at, back)
	_pebble(scene, at, -back)
	if _true:
		flash(scene, at, 1.6, 0.22)
		_shock_ring(scene, Vector3(victim.global_position.x, GROUND_Y + 0.05, victim.global_position.z))
	var me := Player.local
	if me != null and me.worker_id() == shooter:
		if _true:
			get_tree().call_group("camera_rig", "shake", 0.28)
			InputMode.rumble(0.5, 0.7, 0.14)
		else:
			get_tree().call_group("camera_rig", "shake", 0.07)
			InputMode.rumble(0.15, 0.2, 0.06)

## A star of light (the stone glinting at full spin, or striking true), gone in `time`
static func flash(parent: Node, at: Vector3, size: float, time: float) -> void:
	if _flash_shader == null:
		_flash_shader = Shader.new()
		_flash_shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_test_disabled, cull_disabled, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.9, 0.65, 1.0);
uniform float fade = 1.0;
void vertex() {
	// Billboard: face the camera whatever the node's turn
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX[0] *= length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX[1] *= length(MODEL_MATRIX[1].xyz);
}
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float core = pow(max(0.0, 1.0 - length(p) * 2.2), 2.0);
	float rays = max(0.0, 1.0 - abs(p.x) * 14.0) * max(0.0, 1.0 - abs(p.y)) +
		max(0.0, 1.0 - abs(p.y) * 14.0) * max(0.0, 1.0 - abs(p.x));
	float a = clamp(core + rays * 0.8, 0.0, 1.0) * fade;
	ALBEDO = tint.rgb * a;
	ALPHA = a;
}
"""
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := ShaderMaterial.new()
	mat.shader = _flash_shader
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = at
	mi.scale = Vector3.ONE * 0.2
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3.ONE, time * 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "rotation:z", 0.6, time)
	tw.tween_method(func(v: float): mat.set_shader_parameter("fade", v), 1.0, 0.0, time).set_delay(time * 0.3)
	tw.chain().tween_callback(mi.queue_free)

# Faint streak behind the stone (world-space particles left in its wake); gold on a true shot
func _add_trail() -> void:
	var p := CPUParticles3D.new()
	p.local_coords = false
	p.amount = 26 if _true else 18
	p.lifetime = 0.3 if _true else 0.22
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
	var c := TRUE_COLOR if _true else TRAIL_COLOR
	var ramp := Gradient.new()
	ramp.set_color(0, c)
	ramp.set_color(1, Color(c.r, c.g, c.b, 0.0))
	p.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16) if _true else Vector2(0.12, 0.12)
	quad.material = DustFx.material()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.mesh = quad
	add_child(p)

# Grit and dust knocked off where the stone strikes, thrown on along its flight
func _chips(scene: Node, at: Vector3, dir: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 14 if _true else 8
	p.lifetime = 0.5
	p.direction = (dir + Vector3.UP * 0.6).normalized()
	p.spread = 40.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.5 if _true else 3.2
	p.gravity = Vector3(0, -12.0, 0)
	p.scale_amount_min = 0.4
	p.scale_amount_max = 0.9
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.87, 0.8, 0.66, 0.9))
	ramp.set_color(1, Color(0.87, 0.8, 0.66, 0.0))
	p.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	quad.material = DustFx.material()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.mesh = quad
	scene.add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)

# The spent stone glances off back the way it came, skips once and lies there a while
func _pebble(scene: Node, at: Vector3, dir: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.12
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = CHIP_COLOR
	mesh.material = mat
	mi.mesh = mesh
	scene.add_child(mi)
	var side := dir.cross(Vector3.UP) * randf_range(-0.6, 0.6)
	var fall := Vector3(at.x, GROUND_Y + 0.05, at.z) + (dir + side).normalized() * randf_range(0.6, 1.0)
	var skip := fall + (dir + side).normalized() * 0.35
	mi.global_position = at
	var tw := mi.create_tween()
	tw.tween_method(func(t: float): mi.global_position = at.lerp(fall, t) + Vector3.UP * sin(t * PI) * 0.45, 0.0, 1.0, 0.32)
	tw.tween_method(func(t: float): mi.global_position = fall.lerp(skip, t) + Vector3.UP * sin(t * PI) * 0.1, 0.0, 1.0, 0.14)
	tw.tween_interval(PEBBLE_LIFE)
	tw.tween_property(mi, "scale", Vector3.ONE * 0.01, 0.4)
	tw.tween_callback(mi.queue_free)

# A ring of dust thrown out along the ground where a true shot fells a foe
func _shock_ring(scene: Node, at: Vector3) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.4, 2.4)
	quad.orientation = PlaneMesh.FACE_Y
	var mat := ShaderMaterial.new()
	mat.shader = RING_SHADER
	mat.set_shader_parameter("shadow_color", Color(0, 0, 0, 0))
	mat.set_shader_parameter("ring_radius", 0.4)
	mat.set_shader_parameter("ring_width", 0.05)
	mat.set_shader_parameter("ring_color", Color(0.95, 0.88, 0.7, 0.8))
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(mi)
	mi.global_position = at
	mi.scale = Vector3.ONE * 0.3
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3.ONE * 1.6, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(a: float): mat.set_shader_parameter("ring_color", Color(0.95, 0.88, 0.7, a)), 0.8, 0.0, 0.4)
	tw.chain().tween_callback(mi.queue_free)
	DustFx.puff(scene, at + Vector3.UP * 0.2, 12, 0.9)

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
