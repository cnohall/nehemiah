extends Node3D

const BLOCK_SIZE  := Vector3(2.0, 0.8, 1.0)
const STONE_COLOR := Color(0.55, 0.52, 0.48)

@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _body: StaticBody3D   = $StaticBody3D

var health: float = 50.0

func _ready() -> void:
	# Ensure mesh and collision match our constant size.
	var box_mesh := _mesh.mesh as BoxMesh
	if box_mesh:
		box_mesh.size = BLOCK_SIZE
	
	var col_shape := _body.get_node("CollisionShape3D").shape as BoxShape3D
	if col_shape:
		col_shape.size = BLOCK_SIZE

	var mat := StandardMaterial3D.new()
	mat.albedo_color = STONE_COLOR
	mat.roughness    = 0.85
	mat.metallic     = 0.0
	_mesh.material_override = mat

func take_damage(amount: float) -> void:
	health -= amount
	# Visual feedback: make the block darker as it takes damage
	var mat := _mesh.material_override as StandardMaterial3D
	if mat:
		var health_pct := health / 50.0
		mat.albedo_color = STONE_COLOR * (0.4 + 0.6 * health_pct)
	
	if health <= 0:
		queue_free()

static func generate_name(pos: Vector3) -> String:
	return "Block_%d_%d_%d" % [
		int(round(pos.x * 100)),
		int(round(pos.y * 100)),
		int(round(pos.z * 100))
	]
