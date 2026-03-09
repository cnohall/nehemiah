extends CharacterBody3D

@export var speed: float = 3.0
@export var damage: float = 10.0
@export var health: float = 60.0 

@onready var _nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var _attack_area: Area3D = $AttackArea
@onready var _attack_timer: Timer = $AttackTimer

var _target: Node3D = null
var _health_bar: Sprite3D = null
var _health_pb: ProgressBar = null
var _health_bar_timer: float = 0.0
const HEALTH_BAR_SHOW_TIME: float = 3.0

func _ready() -> void:
	_init_health_bar()
	
	if not multiplayer.is_server():
		set_physics_process(false)
		return
	
	_attack_timer.timeout.connect(_on_attack_timer_timeout)
	_find_new_target()

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

func take_damage(amount: float) -> void:
	health -= amount
	
	if is_instance_valid(_health_pb):
		_health_pb.value = health
	
	if is_instance_valid(_health_bar):
		_health_bar.visible = true
		_health_bar_timer = HEALTH_BAR_SHOW_TIME
		
		# Optional: Modulate color based on health percentage
		var health_pct = health / _health_pb.max_value
		if health_pct < 0.3:
			_health_pb.modulate = Color(1, 0.2, 0.2) # Deep red for critical
		elif health_pct < 0.6:
			_health_pb.modulate = Color(1, 0.8, 0.2) # Orange/Yellow for damaged
	
	if health <= 0:
		_on_death()

func _on_death() -> void:
	# Add any death effects here before queue_free
	queue_free()

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
