extends Node3D

func _ready() -> void:
	var mesh_inst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.18
	sphere.height = 0.36
	mesh_inst.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.82, 0.08)
	mat.metallic = 0.9
	mat.roughness = 0.15
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.55, 0.0)
	mat.emission_energy_multiplier = 0.6
	mesh_inst.material_override = mat
	add_child(mesh_inst)

	var tween := create_tween().set_loops()
	tween.tween_property(mesh_inst, "position:y", 0.25, 0.55).set_trans(Tween.TRANS_SINE)
	tween.tween_property(mesh_inst, "position:y", -0.05, 0.55).set_trans(Tween.TRANS_SINE)
