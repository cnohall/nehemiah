extends RigidBody3D

const MIN_HIT_SPEED: float = 2.0

@export var damage_per_speed: float = 1.2
@export var lifetime: float = 4.0

var _thrower: Node3D = null
var _thrower_id: int = 0

func _ready() -> void:
	gravity_scale = 0.0
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.1
	mat.friction = 0.1
	physics_material_override = mat
	get_tree().create_timer(lifetime).timeout.connect(queue_free)
	contact_monitor = true
	max_contacts_reported = 2
	body_entered.connect(_on_body_entered)
	if is_instance_valid(_thrower):
		add_collision_exception_with(_thrower)

func set_thrower(path: NodePath) -> void:
	if path.is_empty(): return
	_thrower = get_node_or_null(path)
	if is_instance_valid(_thrower):
		_thrower_id = int(_thrower.name)
		if is_inside_tree():
			add_collision_exception_with(_thrower)

func _on_body_entered(body: Node) -> void:
	if body is CharacterBody3D and body.is_in_group("players"):
		return

	var speed := linear_velocity.length()
	if body.is_in_group("enemies"):
		if speed >= MIN_HIT_SPEED:
			var damage = speed * damage_per_speed
			if body.has_method("take_damage_with_killer"):
				body.take_damage_with_killer(damage, _thrower_id)
			elif body.has_method("take_damage"):
				body.take_damage(damage)
			_spawn_impact_effect()
			queue_free()
	elif body is StaticBody3D or body is CSGBox3D:
		_spawn_impact_effect()
		if speed < 2.0:
			queue_free()

func _spawn_impact_effect() -> void:
	var impact := CPUParticles3D.new()
	impact.amount = 8
	impact.explosiveness = 1.0
	impact.lifetime = 0.3
	impact.one_shot = true
	impact.emitting = true
	impact.spread = 180.0
	impact.gravity = Vector3(0, -5, 0)
	impact.initial_velocity_min = 2.0
	impact.initial_velocity_max = 4.0
	impact.scale_amount_min = 0.1
	impact.scale_amount_max = 0.3
	var mesh := SphereMesh.new()
	impact.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.6, 0.6)
	impact.material_override = mat
	get_tree().current_scene.add_child(impact)
	impact.global_position = global_position
	get_tree().create_timer(0.5).timeout.connect(impact.queue_free)
