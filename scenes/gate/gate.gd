extends Node3D

# Lintel spans the opening once both pillars are fully built.

const LINTEL_SIZE := Vector3(3.4, 0.55, 1.0)
const LINTEL_Y    := 2.2

@onready var _pillars: Array = [$PillarLeft, $PillarRight]

var _lintel: MeshInstance3D

func _ready() -> void:
	_lintel = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = LINTEL_SIZE
	_lintel.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.74, 0.65, 0.50)
	mat.roughness = 0.95
	_lintel.material_override = mat
	_lintel.position = Vector3(0, LINTEL_Y + LINTEL_SIZE.y * 0.5, 0)
	add_child(_lintel)
	for p in _pillars:
		p.stage_changed.connect(_refresh.unbind(1))
	_refresh()

func _refresh() -> void:
	_lintel.visible = _pillars.all(func(p): return p.stage == p.Stage.MORTARED)
