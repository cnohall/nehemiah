class_name DroppedItem
extends Node3D

# Material left on the ground (Overcooked-style): anyone can pick it up again.
# Server spawns it into Main/Items; ItemSpawner replicates it with its kind.

const COLORS := {
	"stone":  Color(0.72, 0.68, 0.60),
	"wood":   Color(0.50, 0.33, 0.17),
	"mortar": Color(0.86, 0.80, 0.66),
	"beam":   Color(0.46, 0.31, 0.17),
	"lime":   Color(0.90, 0.88, 0.82),
	"water":  Color(0.66, 0.40, 0.26),   # the clay jar it's carried in
}
const MARKER_SHADER := preload("res://assets/shaders/ground_marker.gdshader")
# Lift so each prop rests on the floor instead of sinking into it
const REST_Y := { "stone": 0.14, "wood": 0.08, "mortar": 0.13, "beam": 0.11, "lime": 0.14, "water": 0.2 }

@export var kind: String = "stone"

var _taken := false

func _ready() -> void:
	add_to_group("dropped_items")
	var prop := build_prop(kind)
	prop.position.y = REST_Y.get(kind, 0.15)
	prop.rotation.y = hash(name) % 628 / 100.0  # every peer agrees on the angle
	add_child(prop)
	_add_marker()
	# Small pop so a drop reads at a glance
	prop.scale = Vector3.ONE * 0.6
	prop.create_tween().tween_property(prop, "scale", Vector3.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# Soft contact shadow so the load sits on the ground
func _add_marker() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.1, 1.1)
	quad.orientation = PlaneMesh.FACE_Y
	var mat := ShaderMaterial.new()
	mat.shader = MARKER_SHADER
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.02
	add_child(mi)

## Server: claim the item. True once; the item then leaves every peer.
func take() -> bool:
	if not multiplayer.is_server() or _taken:
		return false
	_taken = true
	queue_free()
	return true

## Mesh for a material, shared by carried loads and dropped items
static func build_prop(material_kind: String) -> Node3D:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLORS.get(material_kind, Color.GRAY)
	mat.roughness = 0.9
	match material_kind:
		"wood":
			for z: float in [-0.09, 0.09]:
				var log_mesh := CylinderMesh.new()
				log_mesh.top_radius = 0.08
				log_mesh.bottom_radius = 0.08
				log_mesh.height = 0.9
				_add_mesh(root, log_mesh, mat, Vector3(0, 0, z), Vector3(0, 0, PI / 2))
		"stone":
			var block := BoxMesh.new()
			block.size = Vector3(0.45, 0.28, 0.32)
			_add_mesh(root, block, mat, Vector3.ZERO, Vector3(0, 0.4, 0))
		"beam":
			# Squared timber, long axis on local X (carriers lay it between their shoulders)
			var beam := BoxMesh.new()
			beam.size = Vector3(2.6, 0.22, 0.24)
			_add_mesh(root, beam, mat, Vector3.ZERO, Vector3.ZERO)
			for x: float in [-1.0, 1.0]:
				var end := BoxMesh.new()
				end.size = Vector3(0.04, 0.23, 0.25)
				_add_mesh(root, end, mat.duplicate(), Vector3(x * 1.29, 0, 0), Vector3.ZERO)
		"lime":
			# Sack of burnt lime, tied at the neck
			var sack := SphereMesh.new()
			sack.radius = 0.22
			sack.height = 0.34
			_add_mesh(root, sack, mat, Vector3.ZERO, Vector3.ZERO)
			var tie := CylinderMesh.new()
			tie.top_radius = 0.05
			tie.bottom_radius = 0.08
			tie.height = 0.1
			_add_mesh(root, tie, mat, Vector3(0, 0.19, 0), Vector3.ZERO)
		"water":
			# Clay water jar
			var body := SphereMesh.new()
			body.radius = 0.19
			body.height = 0.4
			_add_mesh(root, body, mat, Vector3.ZERO, Vector3.ZERO)
			var neck := CylinderMesh.new()
			neck.top_radius = 0.09
			neck.bottom_radius = 0.07
			neck.height = 0.14
			_add_mesh(root, neck, mat, Vector3(0, 0.22, 0), Vector3.ZERO)
		"mortar":
			var basket := CylinderMesh.new()
			basket.top_radius = 0.22
			basket.bottom_radius = 0.16
			basket.height = 0.26
			_add_mesh(root, basket, mat, Vector3.ZERO, Vector3.ZERO)
	return root

static func _add_mesh(root: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	root.add_child(mi)
