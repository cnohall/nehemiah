extends CharacterBody2D

enum Behavior { ATTACK_WALL, SNEAK }

const HEALTH_BAR_SHOW_TIME: float = 3.0
const ATTACK_REACH: float = 2.5
const CITY_TARGET := Vector2(0, CityManager.ZONE_Y_START + 5.0)

@export var speed: float = 3.0
@export var damage: float = 10.0
@export var health: float = 25.0
@export var player_aggro_range: float = 12.0
@export var mesh_color: Color = Color(1, 0, 0)
@export var body_scale: float = 1.0
@export var sneak_chance: float = 0.25

var _behavior: Behavior = Behavior.ATTACK_WALL
var _target: Node2D = null
var _health_bar_visible: bool = false
var _health_bar_timer: float = 0.0
var _max_health: float = 25.0
var _last_target_pos: Vector2 = Vector2.INF

@onready var _nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var _attack_area: Area2D = $AttackArea
@onready var _attack_timer: Timer = $AttackTimer

func _ready() -> void:
	add_to_group("enemies")
	_max_health = health

	if not multiplayer.is_server():
		set_physics_process(false)
		return

	_attack_timer.timeout.connect(_on_attack_timer_timeout)

	# Wall layer (2) must be in collision masks so enemies are physically blocked
	collision_mask |= 2
	_attack_area.collision_mask |= 2

	_behavior = Behavior.SNEAK if randf() < sneak_chance else Behavior.ATTACK_WALL
	_init_target()

func _draw() -> void:
	# Enemy body
	var radius := 8.0 * body_scale
	draw_circle(Vector2.ZERO, radius, mesh_color)
	draw_arc(Vector2.ZERO, radius, 0, TAU, 16, Color(0, 0, 0, 0.3), 1.5)

	# Health bar (shown after taking damage)
	if _health_bar_visible:
		var bw := 20.0
		var bh := 2.5
		var by := -radius - 5.0
		draw_rect(Rect2(Vector2(-bw * 0.5, by), Vector2(bw, bh)), Color(0.1, 0.1, 0.1, 0.7))
		var ratio := clampf(health / _max_health, 0.0, 1.0)
		var hcol := Color(0.9, 0.2, 0.2)
		if ratio > 0.6:
			hcol = Color(0.2, 0.8, 0.2)
		elif ratio > 0.3:
			hcol = Color(0.9, 0.7, 0.1)
		draw_rect(Rect2(Vector2(-bw * 0.5, by), Vector2(bw * ratio, bh)), hcol)

func _process(delta: float) -> void:
	if _health_bar_timer > 0.0:
		_health_bar_timer -= delta
		if _health_bar_timer <= 0.0:
			_health_bar_visible = false
			queue_redraw()

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	_update_target_priority()

	var target_pos := Vector2.ZERO
	if is_instance_valid(_target):
		target_pos = _target.global_position
		# If targeting a wall section, target the closest point on its boundary
		if _target is WallSection:
			var local_pos = _target.to_local(global_position)
			local_pos.x = clamp(local_pos.x, -5.0, 5.0)
			local_pos.y = clamp(local_pos.y, -1.0, 1.0)
			target_pos = _target.to_global(local_pos)

	if target_pos.distance_to(_last_target_pos) > 0.5:
		_nav_agent.target_position = target_pos
		_last_target_pos = target_pos

	if _nav_agent.is_navigation_finished():
		# For player targets: keep pushing directly once nav considers itself done
		if is_instance_valid(_target) and _target.is_in_group("players"):
			var to_player := _target.global_position - global_position
			if to_player.length() > 0.8:
				velocity = to_player.normalized() * speed
			else:
				velocity = Vector2.ZERO
		else:
			velocity = velocity.move_toward(Vector2.ZERO, speed)
	else:
		var next_path_pos := _nav_agent.get_next_path_position()
		var direction := global_position.direction_to(next_path_pos)
		velocity = direction * speed

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
		main._spawn_floating_text.rpc(global_position + Vector2(0, -12), str(int(amount)), Color.RED)
	_health_bar_visible = true
	_health_bar_timer = HEALTH_BAR_SHOW_TIME
	queue_redraw()
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

	# Priority 2: Wall Sections (physics overlap via StaticBody2D)
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
		_target = null
		_nav_agent.target_position = CITY_TARGET
		return

	# Attackers: nearest attackable wall section
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

	# No attackable wall — chase the nearest player
	var nearest_player := _find_nearest_player(INF)
	if nearest_player:
		_target = nearest_player
		return

	_target = null

func _find_nearest_player(max_dist: float) -> Node2D:
	var players_node := get_tree().current_scene.get_node_or_null("Players")
	if not players_node:
		return null
	var best: Node2D = null
	var best_dist := max_dist
	for player in players_node.get_children():
		if not player is Node2D or not player.visible:
			continue
		var d := global_position.distance_to(player.global_position)
		if d < best_dist:
			best_dist = d
			best = player
	return best
