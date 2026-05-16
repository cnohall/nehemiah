extends StaticBody3D

@export var kind: String = "stone"   # "stone" | "wood" | "mortar"
@export var count: int = 999

@onready var mesh_node:   MeshInstance3D = $Mesh
@onready var count_label: Label3D        = $CountLabel

const COLORS := {
	"stone":  Color(0.68, 0.64, 0.55, 1),
	"wood":   Color(0.52, 0.32, 0.14, 1),
	"mortar": Color(0.76, 0.72, 0.58, 1),
}

func _ready() -> void:
	add_to_group("supply_piles")
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLORS.get(kind, Color(0.5, 0.5, 0.5, 1))
	mesh_node.set_surface_override_material(0, mat)
	count_label.text = kind.capitalize()

func request_pickup() -> bool:
	if count <= 0:
		return false
	count -= 1
	return true
