extends RigidBody3D

@export var damage_per_speed: float = 1.2
@export var lifetime: float = 4.0
const MIN_HIT_SPEED: float = 2.0

var _shadow: MeshInstance3D = null
var _thrower: Node3D = null
var _thrower_id: int = 0

func _ready() -> void:
	gravity_scale = 1.0
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.6
	mat.friction = 0.3
	physics_material_override = mat
	get_tree().create_timer(lifetime).timeout.connect(queue_free)
	contact_monitor = true
	max_contacts_reported = 2
	body_entered.connect(_on_body_entered)
	if is_instance_valid(_thrower):
		add_collision_exception_with(_thrower)
	_init_shadow()

func set_thrower(path: NodePath) -> void:
	if path.is_empty(): return
	_thrower = get_node_or_null(path)
	if is_instance_valid(_thrower):
		_thrower_id = int(_thrower.name)
		if is_inside_tree():
			add_collision_exception_with(_thrower)

func _init_shadow() -> void:
	_shadow = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.2
	mesh.bottom_radius = 0.2
	mesh.height = 0.01
	_shadow.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0, 0, 0, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow.material_override = mat
	get_tree().current_scene.add_child.call_deferred(_shadow)

func _process(_delta: float) -> void:
	if is_instance_valid(_shadow):
		var space_state := get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3.DOWN * 10.0)
		query.collision_mask = 1 | 2
		var result := space_state.intersect_ray(query)
		if not result.is_empty():
			_shadow.global_position = result.position + Vector3(0, 0.01, 0)
			_shadow.visible = true
		else:
			_shadow.visible = false

func _exit_tree() -> void:
	if is_instance_valid(_shadow):
		_shadow.queue_free()

func _on_body_entered(body: Node) -> void:
	if body is CharacterBody3D and body.is_in_group("players"):
		return
	
	var speed := linear_velocity.length()
	if body.is_in_group("enemies") or body.is_in_group("temple"):
		if speed >= MIN_HIT_SPEED:
			var dmg_mult: float = get_tree().current_scene.get("stone_damage_mult") if get_tree().current_scene else 1.0
			var damage = speed * damage_per_speed * dmg_mult
			if body.has_method("take_damage_with_killer"):
				body.take_damage_with_killer(damage, _thrower_id)
			elif body.has_method("take_damage"):
				body.take_damage(damage)
			_spawn_impact_effect()
			queue_free()
	elif body is StaticBody3D or body is CSGBox3D:
		_spawn_impact_effect()
		# Only disappear if moving very slowly after a bounce
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
