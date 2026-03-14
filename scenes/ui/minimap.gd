extends Control
## Simple 2D Minimap aligned with the Isometric Camera.
## Maps 80x80 world coordinates to a 150x150 UI square.

# ── Visual Constants ─────────────────────────────────────────────────────────

const COLOR_BG      := Color(0.1, 0.08, 0.05, 0.7)
const COLOR_BORDER  := Color(0.5, 0.45, 0.35, 1.0)
const COLOR_PLAYER  := Color(0.2, 1.0, 0.4)
const COLOR_ENEMY   := Color(1.0, 0.3, 0.2)
const COLOR_WALL    := Color(0.6, 0.55, 0.5)
const COLOR_CITY    := Color(0.3, 0.4, 0.3, 0.5)

# Material-specific colors for piles
const COLOR_M_STONE  := Color(0.72, 0.68, 0.60)
const COLOR_M_WOOD   := Color(0.58, 0.36, 0.16)
const COLOR_M_MORTAR := Color(0.50, 0.50, 0.58)

@export var map_size: Vector2 = Vector2(150, 150)
@export var world_size: float = 80.0

func _ready() -> void:
	custom_minimum_size = map_size

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	# 1. Background
	draw_rect(Rect2(Vector2.ZERO, map_size), COLOR_BG)

	# 2. Draw Inner City (Z = 20 to 40)
	var interior_dir := Vector3.BACK
	var main = get_tree().current_scene
	var b_mgr = main.get("_building_mgr") if main else null
	if b_mgr and b_mgr.has_method("get_interior_direction"):
		interior_dir = b_mgr.get_interior_direction()

	# Simple rectangle representing the city "behind" the wall
	var city_center = interior_dir * 30.0
	var city_rect_pos = _world_to_map(city_center - Vector3(40, 0, 10))
	var city_rect_size = Vector2(map_size.x, map_size.y * 0.25)
	draw_rect(Rect2(city_rect_pos, city_rect_size), COLOR_CITY)

	# 3. Draw the Wall (using endpoints from BuildingManager)
	if b_mgr and b_mgr.has_method("_blueprint_mgr"):
		var endpoints = b_mgr._blueprint_mgr.get_endpoints()
		if endpoints.size() >= 2:
			var wall_start = _world_to_map(endpoints[0])
			var wall_end   = _world_to_map(endpoints[1])
			draw_line(wall_start, wall_end, COLOR_WALL, 2.5)
	else:
		# Fallback to horizontal center line
		var wall_start = _world_to_map(Vector3(-30, 0, 0))
		var wall_end   = _world_to_map(Vector3( 30, 0, 0))
		draw_line(wall_start, wall_end, COLOR_WALL, 2.0)

	# 4. Draw Supply Piles
	for pile: Node3D in get_tree().get_nodes_in_group("supply_piles"):
		if is_instance_valid(pile):
			_draw_pile_indicator(pile)

	# 5. Draw Enemies (with a combat pulse)
	var pulse = 1.0 + (sin(Time.get_ticks_msec() * 0.01) * 0.2)
	for enemy: Node3D in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy):
			var pos = _world_to_map(enemy.global_position)
			draw_circle(pos, 3.0 * pulse, COLOR_ENEMY)

	# 6. Draw Players (with directional indicator)
	for player: CharacterBody3D in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(player):
			_draw_player_indicator(player)

	# 7. Border
	draw_rect(Rect2(Vector2.ZERO, map_size), COLOR_BORDER, false, 2.0)

func _draw_pile_indicator(pile: Node3D) -> void:
	var pos = _world_to_map(pile.global_position)
	var color = COLOR_M_STONE
	var type = pile.get("material_type")
	match type:
		"wood":   color = COLOR_M_WOOD
		"mortar": color = COLOR_M_MORTAR

	# Draw as a small static square
	var size := Vector2(6, 6)
	draw_rect(Rect2(pos - size * 0.5, size), color)
	draw_rect(Rect2(pos - size * 0.5, size), Color.BLACK, false, 1.0) # Thin outline

func _draw_player_indicator(player: CharacterBody3D) -> void:
	var pos = _world_to_map(player.global_position)
	var is_local = player.is_multiplayer_authority()

	# Draw a small circle for the player body
	draw_circle(pos, 4.0 if is_local else 3.0, COLOR_PLAYER)

	# Draw a "Directional Heading" line
	var dir_vec = player.velocity.normalized()
	if dir_vec.length() < 0.1:
		dir_vec = Vector3.BACK

	var map_dir = Vector2(dir_vec.x, dir_vec.z).normalized()
	map_dir.y = -map_dir.y

	var head_pos = pos + (map_dir * 8.0)
	draw_line(pos, head_pos, COLOR_PLAYER, 1.5)

func _world_to_map(world_pos: Vector3) -> Vector2:
	var nx = (world_pos.x + (world_size * 0.5)) / world_size
	var nz = (world_pos.z + (world_size * 0.5)) / world_size
	return Vector2(nx * map_size.x, nz * map_size.y)
