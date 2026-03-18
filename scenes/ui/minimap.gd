extends Control
## Minimap — Isometric-aligned 2D overview.
## World XZ rotated -45° to match the camera angle, so minimap up == screen up.

# ── Constants ─────────────────────────────────────────────────────────────────

const MAP_SIZE    := Vector2(160, 160)
const WORLD_SIZE  := 80.0
# After -45° rotation the 80×80 world fits in a diamond; effective extent = 80/√2 ≈ 56.6 on each axis.
# Using 80*√2 as the denominator keeps the full wall circle visible.
const EFF_SIZE    := WORLD_SIZE * 1.4142   # ≈ 113.1

# Palette — warm earthy tones matching the main-menu
const C_BG            := Color(0.10, 0.08, 0.05, 0.88)
const C_BORDER        := Color(0.78, 0.62, 0.30, 1.00)   # Gold
const C_CITY          := Color(0.22, 0.28, 0.17, 0.55)   # Olive
const C_CITY_EDGE     := Color(0.38, 0.46, 0.28, 0.40)
const C_WALL_NONE     := Color(0.38, 0.32, 0.24, 1.00)   # Unbuilt stone
const C_WALL_DONE     := Color(0.92, 0.86, 0.68, 1.00)   # Finished limestone
const C_PLAYER_LOCAL  := Color(0.98, 0.88, 0.28, 1.00)   # Gold
const C_PLAYER_REMOTE := Color(0.60, 0.90, 0.46, 1.00)   # Lime
const C_ENEMY         := Color(0.88, 0.18, 0.12, 1.00)   # Blood red
const C_PILE_STONE    := Color(0.76, 0.71, 0.62, 1.00)
const C_PILE_WOOD     := Color(0.56, 0.34, 0.12, 1.00)
const C_PILE_MORTAR   := Color(0.58, 0.58, 0.68, 1.00)

# pixels per world unit in the rotated frame
var _scale: float

func _ready() -> void:
	custom_minimum_size = MAP_SIZE
	_scale = MAP_SIZE.x / EFF_SIZE

func _process(_delta: float) -> void:
	queue_redraw()

# ── Main draw ─────────────────────────────────────────────────────────────────

func _draw() -> void:
	var half := MAP_SIZE * 0.5

	# 1. Background
	draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), C_BG)

	# 2. Subtle grid (two lines through centre)
	var grid_col = Color(0.28, 0.22, 0.14, 0.30)
	draw_line(Vector2(half.x, 4), Vector2(half.x, MAP_SIZE.y - 4), grid_col, 1.0)
	draw_line(Vector2(4, half.y), Vector2(MAP_SIZE.x - 4, half.y), grid_col, 1.0)

	# 3. Inner city circle
	draw_circle(half, 24.0, C_CITY)

	# 4. Faint wall-perimeter ring (~radius 35 world units)
	var ring_r := 35.0 * _scale
	_draw_ring(half, ring_r, Color(0.55, 0.45, 0.30, 0.25), 1.0)

	# 5. Wall sections
	for section in get_tree().get_nodes_in_group("wall_sections"):
		if is_instance_valid(section):
			_draw_wall_segment(section)

	# 6. Supply piles
	for pile in get_tree().get_nodes_in_group("supply_piles"):
		if is_instance_valid(pile):
			_draw_pile(pile)

	# 7. Enemies
	var t := Time.get_ticks_msec() * 0.006
	var pulse := 1.0 + sin(t) * 0.25
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy):
			_draw_diamond(_w2m(enemy.global_position), 4.0 * pulse, C_ENEMY)

	# 8. Players
	for player in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(player):
			_draw_player(player)

	# 9. Border — two-pixel gold frame
	draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), C_BORDER, false, 2.0)
	# Inner thin border
	draw_rect(Rect2(Vector2(3, 3), MAP_SIZE - Vector2(6, 6)), Color(0.55, 0.42, 0.18, 0.5), false, 1.0)

	# 10. Compass marker — small arrow in top-right corner pointing "screen up"
	_draw_compass(Vector2(MAP_SIZE.x - 16.0, 16.0))

# ── Element drawers ───────────────────────────────────────────────────────────

func _draw_wall_segment(section: Node3D) -> void:
	var pct: float = 0.0
	if section.get("completion_percent") != null:
		pct = section.get("completion_percent")
	var col := C_WALL_NONE.lerp(C_WALL_DONE, pct / 100.0)
	var mpos := _w2m(section.global_position)

	# Tangent direction of the wall at this point (perpendicular to radial from origin)
	var radial2d := Vector2(section.global_position.x, section.global_position.z)
	if radial2d.length() > 0.1:
		radial2d = radial2d.normalized()
	else:
		radial2d = Vector2.RIGHT
	var tangent_m := _dir2m(radial2d) * 7.0

	var thickness := lerpf(1.5, 3.5, pct / 100.0)
	draw_line(mpos - tangent_m, mpos + tangent_m, col, thickness)

func _draw_pile(pile: Node3D) -> void:
	var pos := _w2m(pile.global_position)
	var col := C_PILE_STONE
	match pile.get("material_type"):
		"wood":   col = C_PILE_WOOD
		"mortar": col = C_PILE_MORTAR
	draw_circle(pos, 4.5, col)
	draw_circle(pos, 2.0, Color(1, 1, 1, 0.4))   # bright centre dot
	_draw_ring(pos, 4.5, col.darkened(0.3), 1.0)

func _draw_player(player: CharacterBody3D) -> void:
	var pos  := _w2m(player.global_position)
	var is_local := player.is_multiplayer_authority()
	var col  := C_PLAYER_LOCAL if is_local else C_PLAYER_REMOTE
	var size := 6.0 if is_local else 4.5

	# Velocity direction in map space — or fallback to last facing
	var vel := player.velocity
	var map_fwd: Vector2
	if vel.length() > 0.5:
		map_fwd = _dir2m(Vector2(vel.x, vel.z)).normalized()
	else:
		# Try to infer from animation name
		map_fwd = Vector2(0, -1)   # default: up

	# Arrow triangle
	var tip   := pos + map_fwd * size
	var left  := pos + map_fwd.rotated(deg_to_rad(140)) * (size * 0.75)
	var right := pos + map_fwd.rotated(deg_to_rad(-140)) * (size * 0.75)
	draw_colored_polygon(PackedVector2Array([tip, left, right]), col)
	draw_polyline(PackedVector2Array([tip, left, right, tip]), col.darkened(0.3), 1.0)

func _draw_diamond(pos: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array([
		pos + Vector2(0, -r),
		pos + Vector2(r, 0),
		pos + Vector2(0,  r),
		pos + Vector2(-r, 0),
	])
	draw_colored_polygon(pts, col)

func _draw_ring(center: Vector2, radius: float, col: Color, width: float) -> void:
	# Approximate circle outline with a polygon
	var pts := PackedVector2Array()
	var steps := 24
	for i in range(steps + 1):
		var a := (float(i) / steps) * TAU
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	draw_polyline(pts, col, width)

func _draw_compass(pos: Vector2) -> void:
	# Tiny north arrow (triangle pointing up = screen up = away from camera)
	var size := 5.0
	var tip   := pos + Vector2(0, -size)
	var bl    := pos + Vector2(-size * 0.5,  size * 0.6)
	var br    := pos + Vector2( size * 0.5,  size * 0.6)
	draw_colored_polygon(PackedVector2Array([tip, bl, br]), C_BORDER)
	draw_string(ThemeDB.fallback_font, pos + Vector2(-3, size * 2.0), "N",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 8, C_BORDER)

# ── Coordinate helpers ────────────────────────────────────────────────────────

## World 3D → minimap 2D (applies -45° rotation to align with camera).
func _w2m(world_pos: Vector3) -> Vector2:
	var wx := world_pos.x
	var wz := world_pos.z
	# Rotate +45° in XZ (-135° + 180°): rx = (wx - wz)/√2,  rz = (wx + wz)/√2
	var rx := (wx - wz) * 0.7071
	var rz := (wx + wz) * 0.7071
	var nx := (rx + EFF_SIZE * 0.5) / EFF_SIZE
	var nz := (rz + EFF_SIZE * 0.5) / EFF_SIZE
	return Vector2(nx * MAP_SIZE.x, nz * MAP_SIZE.y)

## Rotate a 2D world-XZ direction vector by -45° to minimap space.
func _dir2m(dir: Vector2) -> Vector2:
	return Vector2(
		(dir.x - dir.y) * 0.7071,
		(dir.x + dir.y) * 0.7071
	)
