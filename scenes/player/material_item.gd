extends Node2D
class_name MaterialItem

enum Type { STONE, WOOD, MORTAR }

@export var material_type: Type = Type.STONE

var material_name: String = ""
var speed_penalty: float = 0.0
var color: Color = Color.WHITE
var carrier: Node2D = null

# Configuration per material type
var _config = {
	Type.STONE: {
		"name": "Cut Stone",
		"speed_penalty": 0.4,
		"color": Color(0.6, 0.6, 0.6),
	},
	Type.WOOD: {
		"name": "Timber Beam",
		"speed_penalty": 0.15,
		"color": Color(0.4, 0.26, 0.13),
	},
	Type.MORTAR: {
		"name": "Mortar Bucket",
		"speed_penalty": 0.1,
		"color": Color(0.3, 0.3, 0.35),
	}
}

func _ready() -> void:
	add_to_group("carriables")
	if multiplayer.is_server():
		set_multiplayer_authority(1)
	_apply_config()

func _apply_config() -> void:
	var cfg = _config[material_type]
	material_name = cfg["name"]
	speed_penalty = cfg["speed_penalty"]
	color = cfg["color"]
	queue_redraw()

func _draw() -> void:
	if carrier != null:
		return  # Don't draw when carried — position is offset, parent handles it
	match material_type:
		Type.STONE:
			draw_circle(Vector2.ZERO, 4.0, color)
			draw_circle(Vector2.ZERO, 4.0, Color(0, 0, 0, 0.3), false, 0.8)
		Type.WOOD:
			draw_rect(Rect2(Vector2(-6, -2), Vector2(12, 4)), color)
			draw_rect(Rect2(Vector2(-6, -2), Vector2(12, 4)), Color(0, 0, 0, 0.3), false, 0.8)
		Type.MORTAR:
			draw_circle(Vector2.ZERO, 3.5, color)
			# Bucket rim
			draw_arc(Vector2.ZERO, 4.0, 0, TAU, 16, Color(0.2, 0.2, 0.25), 1.5)

func _draw_carried() -> void:
	# Small icon drawn relative to carrier (called when carried)
	match material_type:
		Type.STONE:
			draw_circle(Vector2.ZERO, 3.0, color)
		Type.WOOD:
			draw_rect(Rect2(Vector2(-5, -1.5), Vector2(10, 3)), color)
		Type.MORTAR:
			draw_circle(Vector2.ZERO, 2.5, color)

func pick_up(new_carrier: Node2D) -> void:
	if carrier != null:
		return
	carrier = new_carrier
	if is_inside_tree():
		reparent(carrier)
	position = Vector2(0, -20)  # float above/ahead of carrier

func drop(global_pos: Vector2) -> void:
	carrier = null
	var main = get_tree().current_scene
	reparent(main)
	global_position = global_pos
	queue_redraw()
