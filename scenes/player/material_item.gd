extends Node3D
class_name MaterialItem

enum Type { STONE, WOOD, MORTAR }

@export var material_type: Type = Type.STONE

var material_name: String = ""
var speed_penalty: float = 0.0
var color: Color = Color.WHITE
var carrier: Node3D = null

# Configuration per material type — const: identical across all instances, never mutates
const _CONFIG: Dictionary = {
	Type.STONE: {
		"name": "Cut Stone",
		"speed_penalty": 0.4,
		"color": Color(0.72, 0.68, 0.60),  # warm limestone, not neutral gray
		"mesh": "box",
		"size": Vector3(0.55, 0.28, 0.44)  # hewn slab shape, not a perfect cube
	},
	Type.WOOD: {
		"name": "Timber Beam",
		"speed_penalty": 0.15,
		"color": Color(0.50, 0.33, 0.16),  # richer cedar tone
		"mesh": "beam",
		"size": Vector3(0.20, 0.20, 1.05)  # slightly thicker so it reads as a beam
	},
	Type.MORTAR: {
		"name": "Mortar Bucket",
		"speed_penalty": 0.1,
		"color": Color(0.70, 0.68, 0.62),  # cream/ash — mortar is light, not dark blue
		"mesh": "bucket",
		"size": Vector3(0.22, 0.38, 0.0)   # taller bucket
	}
}

func _ready() -> void:
	add_to_group("carriables")
	if multiplayer.is_server():
		set_multiplayer_authority(1)

	_apply_config()
	_setup_visuals()

func _apply_config() -> void:
	var cfg = _CONFIG[material_type]
	material_name = cfg["name"]
	speed_penalty = cfg["speed_penalty"]
	color = cfg["color"]

func _setup_visuals() -> void:
	var cfg = _CONFIG[material_type]
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
			cyl.top_radius    = cfg["size"].x
			cyl.bottom_radius = cfg["size"].x * 0.68  # tapered bucket shape
			cyl.height        = cfg["size"].y
			mesh_inst.mesh = cyl

	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.0
	match material_type:
		Type.STONE:  mat.roughness = 0.92
		Type.WOOD:   mat.roughness = 0.88
		Type.MORTAR: mat.roughness = 0.96
	mesh_inst.material_override = mat
	add_child(mesh_inst)

func pick_up(new_carrier: Node3D) -> void:
	if carrier != null:
		return
	carrier = new_carrier
	if is_inside_tree():
		reparent(carrier)
	
	# Position in front of the player, slightly elevated
	position = Vector3(0, 1.1, -0.45)
	rotation = Vector3.ZERO

func drop(global_pos: Vector3) -> void:
	carrier = null
	var main = get_tree().current_scene
	reparent(main)
	global_position = global_pos
	rotation = Vector3.ZERO

func _process(delta: float) -> void:
	if carrier:
		_update_bobbing(delta)

func _update_bobbing(delta: float) -> void:
	# Simple bobbing animation when moving
	var speed = 0.0
	if carrier is CharacterBody3D:
		speed = carrier.velocity.length()
	
	if speed > 0.1:
		var t = Time.get_ticks_msec() * 0.008
		var bob = sin(t) * 0.05
		position.y = 1.1 + bob
		# Slight sway
		rotation.z = sin(t * 0.5) * 0.05
	else:
		# Smoothly return to idle position
		position.y = lerpf(position.y, 1.1, 10.0 * delta)
		rotation.z = lerpf(rotation.z, 0.0, 10.0 * delta)
