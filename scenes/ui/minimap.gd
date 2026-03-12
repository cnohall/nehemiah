extends Control

const MAP_SIZE: float = 160.0
const WORLD_HALF: float = 50.0
const SCALE_F: float = MAP_SIZE / (WORLD_HALF * 2.0)

const BG_COLOR       = Color(0.10, 0.08, 0.06, 0.88)
const BORDER_COLOR   = Color(0.50, 0.42, 0.30, 1.00)
const BOUNDARY_COLOR = Color(0.40, 0.35, 0.25, 0.60)
const BLUEPRINT_COLOR= Color(0.30, 0.50, 0.90, 0.40)
const BLOCK_COLOR    = Color(0.55, 0.52, 0.48, 1.00)
const PLAYER_COLOR   = Color(0.20, 1.00, 0.40, 1.00)
const ENEMY_COLOR    = Color(1.00, 0.20, 0.20, 1.00)
const PILE_COLOR     = Color(1.00, 0.85, 0.20, 1.00)

func _draw() -> void:
	# Background
	draw_rect(Rect2(Vector2.ZERO, Vector2(MAP_SIZE, MAP_SIZE)), BG_COLOR)
	draw_rect(Rect2(Vector2.ZERO, Vector2(MAP_SIZE, MAP_SIZE)), BORDER_COLOR, false, 2.0)
	
	var main = get_tree().current_scene
	if not main: return
	
	# Blueprints
	if "_blueprint_positions" in main:
		for pos in main._blueprint_positions:
			_draw_dot(pos, BLUEPRINT_COLOR, 3.0)
			
	# Wall Sections
	for section in get_tree().get_nodes_in_group("wall_sections"):
		if section is Node3D:
			var color = BLOCK_COLOR
			if section.get("completion_percent", 0.0) >= 100.0:
				color = Color.GOLD
			_draw_dot(section.global_position, color, 4.0)
			
	# Supply Piles
	for pile in get_tree().get_nodes_in_group("supply_piles"):
		if pile is Node3D:
			_draw_dot(pile.global_position, PILE_COLOR, 5.0)
			
	# Players
	for player in get_tree().get_nodes_in_group("players"):
		if player is Node3D and player.visible:
			_draw_dot(player.global_position, PLAYER_COLOR, 4.0)
			
	# Enemies
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is Node3D:
			_draw_dot(enemy.global_position, ENEMY_COLOR, 2.0)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw_dot(world_pos: Vector3, color: Color, size: float) -> void:
	var map_pos := Vector2(
		(world_pos.x + WORLD_HALF) * SCALE_F,
		(world_pos.z + WORLD_HALF) * SCALE_F
	)
	map_pos = map_pos.clamp(Vector2.ZERO, Vector2(MAP_SIZE, MAP_SIZE))
	draw_circle(map_pos, size, color)
