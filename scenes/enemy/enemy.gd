extends CharacterBody3D

enum Behavior { ATTACK_WALL, SNEAK }

const HEALTH_BAR_SHOW_TIME: float = 3.0
const ATTACK_REACH: float = 2.5
const CITY_TARGET := Vector3(0, 0.5, CityManager.ZONE_Z_START + 5.0)

@export var speed: float = 3.0
@export var damage: float = 10.0
@export var health: float = 25.0
@export var player_aggro_range: float = 12.0
@export var mesh_color: Color = Color(1, 0, 0)
@export var body_scale: float = 1.0
@export var sneak_chance: float = 0.25

var _behavior: Behavior = Behavior.ATTACK_WALL
var _target: Node3D = null
var _health_bar: Sprite3D = null
var _health_pb: ProgressBar = null
var _health_bar_timer: float = 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _last_target_pos: Vector3 = Vector3.INF

@onready var _nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var _attack_area: Area3D = $AttackArea
@onready var _attack_timer: Timer = $AttackTimer
@onready var _mesh: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	add_to_group("enemies")
	_init_health_bar()
	_apply_visuals()

	if not multiplayer.is_server():
		set_physics_process(false)
		return

	_attack_timer.timeout.connect(_on_attack_timer_timeout)

	# Wall layer (2) must be in collision masks so enemies are physically blocked
	collision_mask |= 2
	_attack_area.collision_mask |= 2

	_behavior = Behavior.SNEAK if randf() < sneak_chance else Behavior.ATTACK_WALL
	_init_target()

func _apply_visuals() -> void:
	if not is_instance_valid(_mesh):
		return
	var mat := _mesh.get_surface_override_material(0)
	if mat:
		var dup := mat.duplicate() as StandardMaterial3D
		dup.albedo_color = mesh_color
		_mesh.set_surface_override_material(0, dup)
	if body_scale != 1.0:
		_mesh.scale = Vector3(body_scale, body_scale, body_scale)

func _init_health_bar() -> void:
	_health_bar = Sprite3D.new()
	_health_bar.position = Vector3(0, 1.5, 0)
	_health_bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_health_bar.visible = false
	add_child(_health_bar)

	var viewport = SubViewport.new()
	viewport.size = Vector2(100, 12)
	viewport.transparent_bg = true
	add_child(viewport)

	_health_pb = ProgressBar.new()
	_health_pb.size = Vector2(100, 12)
	_health_pb.max_value = health
	_health_pb.value = health
	_health_pb.show_percentage = false

	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.1, 0.6)
	_health_pb.add_theme_stylebox_override("background", bg)

	var fill = StyleBoxFlat.new()
	fill.bg_color = Color(0.9, 0.2, 0.2)
	_health_pb.add_theme_stylebox_override("fill", fill)

	viewport.add_child(_health_pb)
	_health_bar.texture = viewport.get_texture()

func _process(delta: float) -> void:
	if _health_bar_timer > 0.0:
		_health_bar_timer -= delta
		if _health_bar_timer <= 0.0:
			_health_bar.visible = false

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	_update_target_priority()

	var target_pos := Vector3(0, 0.5, 0)
	if is_instance_valid(_target):
		target_pos = _target.global_position
		# If targeting a wall section, target the closest point on its boundary instead of center
		if _target is WallSection:
			# Sections are 10m wide (X) and 1m deep (Z)
			# Project enemy position onto the local bounds of the section
			var local_pos = _target.to_local(global_position)
			local_pos.x = clamp(local_pos.x, -5.0, 5.0)
			local_pos.z = clamp(local_pos.z, -0.5, 0.5)
			target_pos = _target.to_global(local_pos)

	if target_pos.distance_to(_last_target_pos) > 0.5:
		_nav_agent.target_position = target_pos
		_last_target_pos = target_pos

	if _nav_agent.is_navigation_finished():
		# For player targets: keep pushing directly once nav considers itself done —
		# nav stops ~1m short which is often just outside melee reach.
		if is_instance_valid(_target) and _target.is_in_group("players"):
			var to_player := _target.global_position - global_position
			to_player.y = 0.0
			if to_player.length() > 0.8:
				var d := to_player.normalized()
				velocity.x = d.x * speed
				velocity.z = d.z * speed
			else:
				velocity.x = 0.0
				velocity.z = 0.0
		else:
			velocity.x = move_toward(velocity.x, 0.0, speed)
			velocity.z = move_toward(velocity.z, 0.0, speed)
	else:
		var next_path_pos := _nav_agent.get_next_path_position()
		var direction := global_position.direction_to(next_path_pos)
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed

	move_and_slide()

func _update_target_priority() -> void:
	# Break off to fight a player within aggro range
	var nearest_player := _find_nearest_player(player_aggro_range)
	if nearest_player:
		_target = nearest_player
		return

	# Sneakers: drop any stale player target and resume the city run
	if _behavior == Behavior.SNEAK:
		if is_instance_valid(_target) and _target.is_in_group("players"):
			_target = null
			_nav_agent.target_position = CITY_TARGET
		return

	# Drop stale player target when they leave aggro range
	if is_instance_valid(_target) and _target.is_in_group("players"):
		_target = null

	# Drop wall target if it became immune (100%) or already destroyed (0%)
	if is_instance_valid(_target) and _target is WallSection:
		if _target.completion_percent >= 100.0 or _target.completion_percent <= 0.0:
			_target = null

	if not is_instance_valid(_target):
		_find_new_target()

func take_damage(amount: float) -> void:
	take_damage_with_killer(amount, 0)

func take_damage_with_killer(amount: float, killer_id: int) -> void:
	health -= amount
	var main = get_tree().current_scene
	if main.has_method("_spawn_floating_text"):
		main._spawn_floating_text.rpc(global_position + Vector3(0, 1.5, 0), str(int(amount)), Color.RED)
	if is_instance_valid(_health_pb):
		_health_pb.value = health
	if is_instance_valid(_health_bar):
		_health_bar.visible = true
		_health_bar_timer = HEALTH_BAR_SHOW_TIME
		var hb_pct = health / _health_pb.max_value
		if hb_pct < 0.3:
			_health_pb.modulate = Color(1, 0.2, 0.2)
		elif hb_pct < 0.6:
			_health_pb.modulate = Color(1, 0.8, 0.2)
	if health <= 0:
		if killer_id != 0:
			set_meta("killer_id", killer_id)
		_on_death()

func _on_death() -> void:
	queue_free()

func _on_attack_timer_timeout() -> void:
	if not multiplayer.is_server():
		return
	var bodies := _attack_area.get_overlapping_bodies()

	# Priority 1: Players (physics overlap)
	for body in bodies:
		if body.is_in_group("players") and body.has_method("take_damage") and body.visible:
			body.take_damage(damage)
			return

	# Priority 2: Wall Sections (physics overlap via their StaticBody3D)
	for body in bodies:
		var section = _get_section_from_body(body)
		if section and section.has_method("take_damage"):
			section.take_damage(damage)
			return

func _get_section_from_body(body: Node) -> Node:
	var p = body
	while p:
		if p is WallSection:
			return p
		p = p.get_parent()
	return null

func _init_target() -> void:
	await get_tree().physics_frame
	_find_new_target()

func _find_new_target() -> void:
	if _behavior == Behavior.SNEAK:
		# Sneakers run straight for the city through the gate gap.
		# If they can't path there (wall fully blocks), break a wall instead.
		_target = null
		_nav_agent.target_position = CITY_TARGET
		return

	# Attackers: nearest attackable wall section (built but not complete)
	var nearest_wall: WallSection = null
	var min_dist := INF
	for s in get_tree().get_nodes_in_group("wall_sections"):
		if not s is WallSection:
			continue
		if s.completion_percent <= 0.0 or s.completion_percent >= 100.0:
			continue
		var d := global_position.distance_to(s.global_position)
		if d < min_dist:
			min_dist = d
			nearest_wall = s

	if nearest_wall:
		_target = nearest_wall
		return

	# No attackable wall — chase the nearest player (no range limit)
	var nearest_player := _find_nearest_player(INF)
	if nearest_player:
		_target = nearest_player
		return

	# Nothing to do — stay put
	_target = null

func _find_nearest_player(max_dist: float) -> Node3D:
	var players_node := get_tree().current_scene.get_node_or_null("Players")
	if not players_node:
		return null
	var best: Node3D = null
	var best_dist := max_dist
	for player in players_node.get_children():
		if not player is Node3D or not player.visible:
			continue
		var d := global_position.distance_to(player.global_position)
		if d < best_dist:
			best_dist = d
			best = player
	return best
