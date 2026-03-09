extends Node3D

const BLOCK_SIZE  := Vector3(2.0, 0.8, 1.0)
const STONE_COLOR := Color(0.55, 0.52, 0.48)
const BEVEL_COLOR := Color(0.65, 0.62, 0.58)

@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _bevel: MeshInstance3D = $BevelMesh
@onready var _body: StaticBody3D   = $StaticBody3D

var health: float = 50.0

func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = STONE_COLOR
	mat.roughness    = 0.85
	_mesh.material_override = mat
	
	var bev_mat := StandardMaterial3D.new()
	bev_mat.albedo_color = BEVEL_COLOR
	bev_mat.roughness = 0.7
	_bevel.material_override = bev_mat

func take_damage(amount: float) -> void:
	health -= amount
	var main = get_tree().current_scene
	if main.has_method("_spawn_floating_text"):
		main._spawn_floating_text.rpc(global_position + Vector3(0, 1, 0), str(int(amount)), Color.LIGHT_GRAY)

	var health_pct := health / 50.0
	_mesh.material_override.albedo_color = STONE_COLOR * (0.4 + 0.6 * health_pct)
	_bevel.material_override.albedo_color = BEVEL_COLOR * (0.4 + 0.6 * health_pct)
	
	if health <= 0:
		if main.has_method("add_shake"):
			main.add_shake(0.1)
		queue_free()

static func generate_name(pos: Vector3) -> String:
	return "Block_%d_%d_%d" % [int(round(pos.x * 100)), int(round(pos.y * 100)), int(round(pos.z * 100))]
