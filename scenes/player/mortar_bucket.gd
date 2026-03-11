extends "res://scenes/player/carriable.gd"
class_name MortarBucket

func _init() -> void:
	material_name = "Mortar Bucket"
	speed_penalty = 0.1 # 10% slower
	color = Color(0.3, 0.3, 0.35) # Dark bluish gray

func _setup_visuals() -> void:
	var mesh_inst = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.2
	cyl.bottom_radius = 0.15
	cyl.height = 0.3
	mesh_inst.mesh = cyl
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_inst.material_override = mat
	add_child(mesh_inst)
