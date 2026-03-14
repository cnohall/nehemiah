extends Node3D
class_name MaterialItem

enum Type { STONE, WOOD, MORTAR }

@export var material_type: Type = Type.STONE

var material_name: String = ""
var speed_penalty: float = 0.0
var color: Color = Color.WHITE
var carrier: Node3D = null

# Configuration per material type
var _config = {
	Type.STONE: {
		"name": "Cut Stone",
		"speed_penalty": 0.4,
		"color": Color(0.6, 0.6, 0.6),
		"mesh": "box",
		"size": Vector3(0.4, 0.4, 0.4)
	},
	Type.WOOD: {
		"name": "Timber Beam",
		"speed_penalty": 0.15,
		"color": Color(0.4, 0.26, 0.13),
		"mesh": "beam",
		"size": Vector3(0.15, 0.15, 1.2)
	},
	Type.MORTAR: {
		"name": "Mortar Bucket",
		"speed_penalty": 0.1,
		"color": Color(0.3, 0.3, 0.35),
		"mesh": "bucket",
		"size": Vector3(0.2, 0.3, 0.0) # Used for radius/height
	}
}

func _ready() -> void:
	add_to_group("carriables")
	if multiplayer.is_server():
		set_multiplayer_authority(1)

	_apply_config()
	_setup_visuals()

func _apply_config() -> void:
	var cfg = _config[material_type]
	material_name = cfg["name"]
	speed_penalty = cfg["speed_penalty"]
	color = cfg["color"]

func _setup_visuals() -> void:
	var cfg = _config[material_type]
	var mesh_inst = MeshInstance3D.new()

	match cfg["mesh"]:
		"box":
			var box = BoxMesh.new()
			box.size = cfg["size"]
			mesh_inst.mesh = box
		"beam":
			var box = BoxMesh.new()
			box.size = cfg["size"]
			mesh_inst.mesh = box
		"bucket":
			var cyl = CylinderMesh.new()
			cyl.top_radius = cfg["size"].x
			cyl.bottom_radius = cfg["size"].x * 0.75
			cyl.height = cfg["size"].y
			mesh_inst.mesh = cyl

	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_inst.material_override = mat
	add_child(mesh_inst)

func pick_up(new_carrier: Node3D) -> void:
	if carrier != null:
		return
	carrier = new_carrier
	if is_inside_tree():
		reparent(carrier)
	position = Vector3(0, 1.2, -0.6)
	rotation = Vector3.ZERO

func drop(global_pos: Vector3) -> void:
	carrier = null
	var main = get_tree().current_scene
	reparent(main)
	global_position = global_pos
	rotation = Vector3.ZERO
