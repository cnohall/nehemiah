extends "res://scenes/player/carriable.gd"
class_name TimberBeam

func _init() -> void:
	material_name = "Timber Beam"
	speed_penalty = 0.2 # 20% slower
	color = Color(0.4, 0.26, 0.13) # Brown

func _setup_visuals() -> void:
	var mesh_inst = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.2, 0.8, 0.2) # Long beam
	mesh_inst.mesh = box
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_inst.material_override = mat
	add_child(mesh_inst)
	mesh_inst.rotation.x = PI/2 # Carry horizontally
