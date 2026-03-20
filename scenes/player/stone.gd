extends RigidBody3D

const MIN_HIT_SPEED: float = 2.0
const _IMPACT_SOUND: AudioStream = preload("res://assets/sounds/place_stone.wav")

@export var damage_per_speed: float = 1.2
@export var lifetime: float = 4.0

var _thrower: Node3D = null
var _thrower_id: int = 0

func _ready() -> void:
	scale = Vector3(0.45, 0.45, 0.45)
	gravity_scale = 0.6
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.1
	mat.friction = 0.1
	physics_material_override = mat
	get_tree().create_timer(lifetime).timeout.connect(queue_free)
	contact_monitor = true
	max_contacts_reported = 2
	body_entered.connect(_on_body_entered)
	_add_trail()
	if is_instance_valid(_thrower):
		add_collision_exception_with(_thrower)

func _add_trail() -> void:
	var trail := CPUParticles3D.new()
	trail.emitting = true
	trail.amount = 6
	trail.lifetime = 0.18
	trail.explosiveness = 0.0
	trail.randomness = 0.4
	trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	trail.emission_sphere_radius = 0.05
	trail.direction = Vector3.ZERO
	trail.spread = 180.0
	trail.gravity = Vector3.ZERO
	trail.initial_velocity_min = 0.3
	trail.initial_velocity_max = 0.8
	trail.scale_amount_min = 0.06
	trail.scale_amount_max = 0.14
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.72, 0.68)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail.material_override = mat
	add_child(trail)

func _play_impact_sound() -> void:
	var player := AudioStreamPlayer3D.new()
	player.stream = _IMPACT_SOUND
	player.volume_db = -4.0
	player.pitch_scale = randf_range(2.2, 2.8)
	player.max_distance = 30.0
	get_tree().current_scene.add_child(player)
	player.global_position = global_position
	player.play()
	player.finished.connect(player.queue_free)

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
			if multiplayer.is_server():
				var damage := speed * damage_per_speed
				if body.has_method("take_damage_with_killer"):
					body.take_damage_with_killer(damage, _thrower_id)
				elif body.has_method("take_damage"):
					body.take_damage(damage)
				# Knockback on strong hits
				if speed >= MIN_HIT_SPEED * 1.5 and body.has_method("apply_knockback"):
					var knock_dir := linear_velocity.normalized()
					knock_dir.y = 0.0
					body.apply_knockback(knock_dir, speed * 0.35)
			_spawn_impact_effect()
			_play_impact_sound()
			queue_free()
	elif body is StaticBody3D or body is CSGBox3D:
		_spawn_impact_effect()
		_play_impact_sound()
		# Disappear on wall sections or when slow enough to be done rolling
		if body.get_parent() is WallSection or speed < 2.0:
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
