extends Node
## Owns the wall blueprint registry. Populated on ALL peers.
## Translates historical WallData into a local 80x80 tactical map.
## 2D version: coordinates use Vector2 (x = east/west, y = north/south).

# ── Tactical Map Settings ──────────────────────────────────────────────────

const WORLD_SCALE: float = 3.0    # Scale historical units to game units
const STEP: float = 10.0          # Units per wall block

var _blueprint_positions: Dictionary = {}  # Vector2 -> float (rotation angle)
var _interior_direction: Vector2 = Vector2.DOWN  # positive Y = toward city interior
var _endpoints: Array[Vector2] = []      # the two local endpoints for the current section
var _current_day: int = 1

# ── Registry ──────────────────────────────────────────────────────────────────

func get_section_for_day(day: int) -> Dictionary:
	for sec: Dictionary in WallData.SECTIONS:
		if day >= sec.day_start and day <= sec.day_end:
			return sec
	return WallData.SECTIONS[-1]

func get_interior_direction() -> Vector2:
	return _interior_direction

func get_section_center_for_day(_day: int) -> Vector2:
	return Vector2.ZERO

## Initialises blueprints for the given day's section. Called on ALL peers.
func init_registry_for_day(day: int) -> void:
	_current_day = day
	_blueprint_positions.clear()

	var sec = get_section_for_day(day)
	var a_idx = sec.a
	var b_idx = sec.b

	# 1. Get historical positions (now Vector2)
	var hist_a = WallData.CORNERS[a_idx]
	var hist_b = WallData.CORNERS[b_idx]

	# 2. Compute local endpoints along x-axis
	var dist = hist_a.distance_to(hist_b) * WORLD_SCALE
	var local_a = Vector2(-dist * 0.5, 0)
	var local_b = Vector2(dist * 0.5, 0)
	_endpoints = [local_a, local_b]

	_interior_direction = Vector2.DOWN

	var is_gate: bool = sec.get("name", "").to_lower().contains("gate")
	_register_wall_edge(local_a, local_b, is_gate)

func _register_wall_edge(a: Vector2, b: Vector2, is_gate: bool = false) -> void:
	var edge := b - a
	var dir := edge.normalized()
	var angle := dir.angle()  # 2D rotation angle for the section

	var count := int(floor(edge.length() / STEP))
	var offset = (edge.length() - (count * STEP)) * 0.5
	var middle_index = int(count / 2)

	for i: int in range(count + 1):
		if is_gate and i == middle_index:
			continue

		var pos: Vector2 = a + dir * (float(i) * STEP + offset)
		var snapped_x = snappedf(pos.x, 0.1)
		var snapped_y = snappedf(pos.y, 0.1)
		var key := Vector2(snapped_x, snapped_y)
		if not _blueprint_positions.has(key):
			_blueprint_positions[key] = angle

# ── Queries ───────────────────────────────────────────────────────

func get_nearest(world_pos: Vector2, max_dist: float) -> Vector2:
	var best_key := Vector2.INF
	var best_d2 := max_dist * max_dist
	for key: Vector2 in _blueprint_positions:
		var d2: float = world_pos.distance_squared_to(key)
		if d2 < best_d2:
			best_d2 = d2
			best_key = key
	return best_key

func get_angle(key: Vector2) -> float:
	return _blueprint_positions.get(key, 0.0)

func get_endpoints() -> Array[Vector2]:
	return _endpoints

# ── Mutations ─────────────────────────────────────────────────────────────────

func clear_all() -> void:
	_blueprint_positions.clear()
	_endpoints.clear()

func erase_at(key: Vector2) -> void:
	_blueprint_positions.erase(key)

func restore_at(key: Vector2, angle: float) -> void:
	_blueprint_positions[key] = angle
