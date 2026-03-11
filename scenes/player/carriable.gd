extends Node3D
class_name Carriable

@export var material_name: String = "Material"
@export var speed_penalty: float = 0.1 # 0.1 = 10% slower
@export var color: Color = Color.WHITE

var carrier: Node3D = null

func _ready() -> void:
	add_to_group("carriables")
	if multiplayer.is_server():
		set_multiplayer_authority(1)
	_setup_visuals()

func _setup_visuals() -> void:
	var mesh_inst = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.4, 0.4, 0.4)
	mesh_inst.mesh = box
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_inst.material_override = mat
	add_child(mesh_inst)

func pick_up(new_carrier: Node3D) -> void:
	if carrier != null: return
	carrier = new_carrier
	
	# Parent to carrier
	if is_inside_tree():
		reparent(carrier)
	
	position = Vector3(0, 1.2, -0.6) # Carry in front of player
	rotation = Vector3.ZERO

func drop(global_pos: Vector3) -> void:
	carrier = null
	var main = get_tree().current_scene
	reparent(main)
	global_position = global_pos
	rotation = Vector3.ZERO

@rpc("any_peer", "call_local", "reliable")
func request_pickup() -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	# Logic handled in player for now
