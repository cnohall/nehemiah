class_name CityManager
extends Node3D

## Manages the Inner City area, visuals, and breach detection.
## Emits a signal when an enemy enters the protected zone.

signal city_breached(enemy: Node)

# ── Visual Constants ─────────────────────────────────────────────────────────

const CITY_COLOR   := Color(0.18, 0.22, 0.18) # Dark earthy green
const KERB_COLOR   := Color(0.45, 0.40, 0.35) # Sandstone
const HOUSE_COLOR  := Color(0.55, 0.50, 0.45) # Lighter stone
const ZONE_Z_START := 20.0
const ZONE_Z_END   := 40.0
const MAP_WIDTH    := 80.0

# ── Variables ─────────────────────────────────────────────────────────────────

var _breach_area: Area3D = null
var _breach_active: bool = false

func _ready() -> void:
	_setup_visuals()
	_setup_breach_detection()

func activate_breach() -> void:
	_breach_active = true

func _setup_visuals() -> void:
	# 1. The Ground Plane (The "District" floor)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(MAP_WIDTH, ZONE_Z_END - ZONE_Z_START)
	floor_mesh.mesh = plane

	var mat := StandardMaterial3D.new()
	mat.albedo_color = CITY_COLOR
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_mesh.material_override = mat
	floor_mesh.position = Vector3(0, 0.01, (ZONE_Z_START + ZONE_Z_END) * 0.5)
	add_child(floor_mesh)

	# 2. The Threshold Kerb (The physical line)
	var kerb := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(MAP_WIDTH, 0.15, 0.3)
	kerb.mesh = box
	var k_mat := StandardMaterial3D.new()
	k_mat.albedo_color = KERB_COLOR
	kerb.material_override = k_mat
	kerb.position = Vector3(0, 0.075, ZONE_Z_START)
	add_child(kerb)

	# 3. Simple Building Placeholders (The "Homes")
	# We place a few simple boxes to give it a "City" feel
	_spawn_house(Vector3(-25, 0, 32), Vector3(6, 4, 6))
	_spawn_house(Vector3(-10, 0, 35), Vector3(8, 3, 5))
	_spawn_house(Vector3( 15, 0, 33), Vector3(5, 5, 5))
	_spawn_house(Vector3( 30, 0, 36), Vector3(7, 4, 8))

	# 4. Identification Label
	var label := Label3D.new()
	label.text = "JERUSALEM — INNER CITY"
	label.font_size = 48
	label.outline_size = 12
	label.modulate = Color(1.0, 0.9, 0.7)
	label.position = Vector3(0, 6, ZONE_Z_END - 2)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

func _spawn_house(pos: Vector3, size: Vector3) -> void:
	var house := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	house.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = HOUSE_COLOR
	house.material_override = mat
	house.position = pos + Vector3(0, size.y * 0.5, 0)
	add_child(house)

func _setup_breach_detection() -> void:
	_breach_area = Area3D.new()
	_breach_area.name = "BreachDetectionArea"
	_breach_area.collision_mask = 4 # Enemy layer

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Covers full width and the city depth
	box.size = Vector3(MAP_WIDTH, 10, ZONE_Z_END - ZONE_Z_START)
	col.shape = box

	_breach_area.add_child(col)
	_breach_area.position = Vector3(0, 5, (ZONE_Z_START + ZONE_Z_END) * 0.5)
	add_child(_breach_area)

	_breach_area.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if _breach_active and body.is_in_group("enemies"):
		city_breached.emit(body)
