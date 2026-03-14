class_name CityManager
extends Node2D

## Manages the Inner City area, visuals, and breach detection.
## Emits a signal when an enemy enters the protected zone.

signal city_breached(enemy: Node)

# ── Visual Constants ─────────────────────────────────────────────────────────

const CITY_COLOR   := Color(0.18, 0.22, 0.18, 0.6)  # Dark earthy green
const KERB_COLOR   := Color(0.45, 0.40, 0.35)        # Sandstone
const HOUSE_COLOR  := Color(0.55, 0.50, 0.45)        # Lighter stone
const ZONE_Y_START := 20.0   # World Y where the city interior begins
const ZONE_Y_END   := 40.0
const MAP_WIDTH    := 80.0

# Keep alias for backward-compat with enemy.gd references
const ZONE_Z_START := ZONE_Y_START

# ── Variables ─────────────────────────────────────────────────────────────────

var _breach_area: Area2D = null

func _ready() -> void:
	_setup_breach_detection()
	queue_redraw()

func _draw() -> void:
	# Draw the city interior zone
	var zone_rect := Rect2(
		Vector2(-MAP_WIDTH * 0.5, ZONE_Y_START),
		Vector2(MAP_WIDTH, ZONE_Y_END - ZONE_Y_START)
	)
	draw_rect(zone_rect, CITY_COLOR)

	# Kerb line at city entrance
	draw_line(
		Vector2(-MAP_WIDTH * 0.5, ZONE_Y_START),
		Vector2(MAP_WIDTH * 0.5, ZONE_Y_START),
		KERB_COLOR, 1.5
	)

	# Simple house placeholders
	_draw_house(Vector2(-25, 32), Vector2(6, 6))
	_draw_house(Vector2(-10, 35), Vector2(8, 5))
	_draw_house(Vector2( 15, 33), Vector2(5, 5))
	_draw_house(Vector2( 30, 36), Vector2(7, 7))

func _draw_house(pos: Vector2, size: Vector2) -> void:
	var rect := Rect2(pos - size * 0.5, size)
	draw_rect(rect, HOUSE_COLOR)
	draw_rect(rect, Color(0, 0, 0, 0.3), false, 0.8)

func _setup_breach_detection() -> void:
	_breach_area = Area2D.new()
	_breach_area.name = "BreachDetectionArea"
	_breach_area.collision_mask = 4  # Enemy layer

	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(MAP_WIDTH, ZONE_Y_END - ZONE_Y_START)
	col.shape = rect

	_breach_area.add_child(col)
	_breach_area.position = Vector2(0, (ZONE_Y_START + ZONE_Y_END) * 0.5)
	add_child(_breach_area)

	_breach_area.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("enemies"):
		city_breached.emit(body)
