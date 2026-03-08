extends CharacterBody3D

@export var speed: float = 3.0
@export var damage: float = 10.0

@onready var _nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var _attack_area: Area3D = $AttackArea
@onready var _attack_timer: Timer = $AttackTimer

var _target: Node3D = null

func _ready() -> void:
	if not multiplayer.is_server():
		set_physics_process(false)
		return
	
	_attack_timer.timeout.connect(_on_attack_timer_timeout)
	_find_new_target()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_target):
		_find_new_target()
		return

	_nav_agent.target_position = _target.global_position
	
	if _nav_agent.is_navigation_finished():
		return

	var next_path_pos := _nav_agent.get_next_path_position()
	var direction := global_position.direction_to(next_path_pos)
	
	velocity = direction * speed
	move_and_slide()

func _on_attack_timer_timeout() -> void:
	if not multiplayer.is_server():
		return
		
	var bodies := _attack_area.get_overlapping_bodies()
	for body in bodies:
		# Check for building blocks (StaticBody3D inside the block)
		var block = _get_block_from_body(body)
		if block and block.has_method("take_damage"):
			block.take_damage(damage)
			return # Attack one thing at a time

func _get_block_from_body(body: Node) -> Node:
	# The block scene has a StaticBody3D as a child of the root Node3D
	if body is StaticBody3D:
		var parent = body.get_parent()
		if parent and parent.has_method("take_damage"):
			return parent
	return null

func _find_new_target() -> void:
	# 1. Try to find the nearest player
	var players_node := get_tree().current_scene.get_node_or_null("Players")
	if players_node and players_node.get_child_count() > 0:
		_target = players_node.get_child(0) as Node3D
		return

	# 2. If no players, target a random block
	var blocks_node := get_tree().current_scene.get_node_or_null("Blocks")
	if blocks_node and blocks_node.get_child_count() > 0:
		_target = blocks_node.get_child(randi() % blocks_node.get_child_count()) as Node3D
		return
	
	_target = null
