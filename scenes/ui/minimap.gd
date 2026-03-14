extends Control
## Simple 2D Minimap for top-down view.
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

	# 2. Draw Inner City (Y = 20 to 40 in world space)
	var city_top    = _world_to_map(Vector2(-40, 20))
	var city_bottom = _world_to_map(Vector2( 40, 40))
	var city_rect   = Rect2(city_top, city_bottom - city_top)
	draw_rect(city_rect, COLOR_CITY)

	# 3. Draw the Wall (using endpoints from BuildingManager)
	var main = get_tree().current_scene
	var b_mgr = main.get("_building_mgr") if main else null
	if b_mgr and b_mgr.has_method("get_endpoints"):
		var endpoints = b_mgr.get_endpoints()
		if endpoints.size() >= 2:
			var wall_start = _world_to_map(endpoints[0])
			var wall_end   = _world_to_map(endpoints[1])
			draw_line(wall_start, wall_end, COLOR_WALL, 2.5)
	else:
		# Fallback horizontal center line
		var wall_start = _world_to_map(Vector2(-30, 0))
		var wall_end   = _world_to_map(Vector2( 30, 0))
		draw_line(wall_start, wall_end, COLOR_WALL, 2.0)

	# 4. Draw Supply Piles
	for pile in get_tree().get_nodes_in_group("supply_piles"):
		if is_instance_valid(pile):
			_draw_pile_indicator(pile)

	# 5. Draw Enemies (with a combat pulse)
	var pulse = 1.0 + (sin(Time.get_ticks_msec() * 0.01) * 0.2)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy):
			var pos = _world_to_map(enemy.global_position)
			draw_circle(pos, 3.0 * pulse, COLOR_ENEMY)

	# 6. Draw Players (with directional indicator)
	for player in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(player):
			_draw_player_indicator(player)

	# 7. Border
	draw_rect(Rect2(Vector2.ZERO, map_size), COLOR_BORDER, false, 2.0)

func _draw_pile_indicator(pile: Node2D) -> void:
	var pos = _world_to_map(pile.global_position)
	var color = COLOR_M_STONE
	var type = pile.get("material_type")
	match type:
		"wood":   color = COLOR_M_WOOD
		"mortar": color = COLOR_M_MORTAR

	var size := Vector2(6, 6)
	draw_rect(Rect2(pos - size * 0.5, size), color)
	draw_rect(Rect2(pos - size * 0.5, size), Color.BLACK, false, 1.0)

func _draw_player_indicator(player: Node2D) -> void:
	var pos = _world_to_map(player.global_position)
	var is_local = player.is_multiplayer_authority()

	draw_circle(pos, 4.0 if is_local else 3.0, COLOR_PLAYER)

	# Directional heading from velocity
	var vel = player.get("velocity")
	if vel is Vector2 and vel.length() > 0.1:
		var map_dir = vel.normalized()
		map_dir.y = -map_dir.y  # flip Y for minimap (world Y+ = down = map Y-)
		var head_pos = pos + (map_dir * 8.0)
		draw_line(pos, head_pos, COLOR_PLAYER, 1.5)

func _world_to_map(world_pos: Vector2) -> Vector2:
	var nx = (world_pos.x + (world_size * 0.5)) / world_size
	var ny = (world_pos.y + (world_size * 0.5)) / world_size
	return Vector2(nx * map_size.x, ny * map_size.y)
