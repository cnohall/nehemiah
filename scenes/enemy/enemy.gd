extends CharacterBody3D

@export var speed: float = 3.0
@export var damage: float = 10.0
@export var health: float = 25.0
@export var player_aggro_range: float = 8.0
@export var mesh_color: Color = Color(1, 0, 0)
@export var body_scale: float = 1.0
@export var gold_value: int = 1

@onready var _nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var _attack_area: Area3D = $AttackArea
@onready var _attack_timer: Timer = $AttackTimer
@onready var _mesh: MeshInstance3D = $MeshInstance3D

var _target: Node3D = null
var _health_bar: Sprite3D = null
var _health_pb: ProgressBar = null
var _health_bar_timer: float = 0.0
const HEALTH_BAR_SHOW_TIME: float = 3.0

func _ready() -> void:
	add_to_group("enemies")
	_init_health_bar()
	_apply_visuals()

	if not multiplayer.is_server():
		set_physics_process(false)
		return
	
	_attack_timer.timeout.connect(_on_attack_timer_timeout)
	_find_new_target()

func _apply_visuals() -> void:
	if not is_instance_valid(_mesh): return
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
	if not multiplayer.is_server(): return
	
	_update_target_priority()
	
	if not is_instance_valid(_target):
		_nav_agent.target_position = Vector3.ZERO # Head to Temple
	else:
		_nav_agent.target_position = _target.global_position
	
	if _nav_agent.is_navigation_finished():
		velocity = Vector3.ZERO
		return

	var next_path_pos := _nav_agent.get_next_path_position()
	var direction := global_position.direction_to(next_path_pos)
	
	velocity = direction * speed
	move_and_slide()

func _update_target_priority() -> void:
	var players_node := get_tree().current_scene.get_node_or_null("Players")
	if players_node:
		var nearest_player: Node3D = null
		var min_dist := player_aggro_range
		for player in players_node.get_children():
			if not player is Node3D or player.visible == false: continue
			var dist = global_position.distance_to(player.global_position)
			if dist < min_dist:
				min_dist = dist
				nearest_player = player
		if nearest_player:
			_target = nearest_player
			return

	if is_instance_valid(_target) and _target.is_in_group("players"):
		_target = null 

	if not is_instance_valid(_target):
		_find_new_target()

func take_damage(amount: float) -> void:
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
		if hb_pct < 0.3: _health_pb.modulate = Color(1, 0.2, 0.2)
		elif hb_pct < 0.6: _health_pb.modulate = Color(1, 0.8, 0.2)
	
	if health <= 0:
		_on_death()

func _on_death() -> void:
	var main := get_tree().current_scene
	if main.has_method("drop_shekel"):
		main.drop_shekel(global_position, gold_value)
	queue_free()

func _on_attack_timer_timeout() -> void:
	if not multiplayer.is_server(): return
	var bodies := _attack_area.get_overlapping_bodies()
	for body in bodies:
		if body.is_in_group("players") and body.has_method("take_damage"):
			body.take_damage(damage)
			return
	for body in bodies:
		var block = _get_block_from_body(body)
		if block and block.has_method("take_damage"):
			var top_block = _get_top_block_in_stack(block)
			if top_block and top_block.has_method("take_damage"):
				top_block.take_damage(damage)
				return 

func _get_block_from_body(body: Node) -> Node:
	if body is StaticBody3D:
		var parent = body.get_parent()
		if parent and parent.has_method("take_damage"): return parent
	return null

func _get_top_block_in_stack(block: Node3D) -> Node3D:
	var blocks_node := get_tree().current_scene.get_node_or_null("Blocks")
	if not blocks_node: return block
	var target_pos = block.global_position
	var top_block = block
	for other_block in blocks_node.get_children():
		if not other_block is Node3D or other_block == block: continue
		var other_pos = other_block.global_position
		if abs(other_pos.x - target_pos.x) < 0.1 and abs(other_pos.z - target_pos.z) < 0.1:
			if other_pos.y > top_block.global_position.y: top_block = other_block
	return top_block

func _find_new_target() -> void:
	var blocks_node := get_tree().current_scene.get_node_or_null("Blocks")
	if blocks_node and blocks_node.get_child_count() > 0:
		var stacks = {} 
		for block in blocks_node.get_children():
			if not block is Node3D: continue
			var pos = block.global_position
			var key = Vector2(snappedf(pos.x, 0.1), snappedf(pos.z, 0.1))
			if not stacks.has(key) or pos.y > stacks[key].global_position.y: stacks[key] = block
		var top_blocks = stacks.values()
		if top_blocks.size() > 0:
			_target = top_blocks[randi() % top_blocks.size()] as Node3D
			return
	_target = null
