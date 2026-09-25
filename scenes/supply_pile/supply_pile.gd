extends StaticBody3D

# Material stockpile. request_pickup() is server-only (called from Player._server_interact).

@export var kind: String = "stone"   # "stone" | "wood" | "mortar"
@export var count: int = 999

@onready var _visual:     Node3D  = $Visual
@onready var count_label: Label3D = $CountLabel

const COLORS := {
	"stone":  Color(0.68, 0.60, 0.48),
	"wood":   Color(0.50, 0.33, 0.17),
	"mortar": Color(0.86, 0.80, 0.66),
}

func _ready() -> void:
	add_to_group("supply_piles")
	count_label.text = kind.capitalize()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	match kind:
		"stone":  _build_stones(rng)
		"wood":   _build_logs(rng)
		"mortar": _build_mortar(rng)

func request_pickup() -> bool:
	if not multiplayer.is_server() or count <= 0:
		return false
	count -= 1
	return true

# ── Visuals ────────────────────────────────────────────────

func _build_stones(rng: RandomNumberGenerator) -> void:
	# Loose cut blocks, stacked in two rough layers
	for layer in 2:
		var n := 6 - layer * 3
		for i in n:
			var s := Vector3(rng.randf_range(0.55, 0.8), 0.38, rng.randf_range(0.4, 0.55))
			var pos := Vector3(rng.randf_range(-0.5, 0.5) * (1.0 - layer * 0.5), 0.19 + layer * 0.38,
				rng.randf_range(-0.45, 0.45) * (1.0 - layer * 0.5))
			var v := rng.randf_range(-0.06, 0.06)
			var c: Color = COLORS["stone"]
			_add(_box(s), Color(c.r + v, c.g + v, c.b + v), pos, Vector3(0, rng.randf() * TAU, 0))

func _build_logs(rng: RandomNumberGenerator) -> void:
	# Pyramid of timber, 3-2-1
	var r := 0.13
	for layer in 3:
		var n := 3 - layer
		for i in n:
			var cyl := CylinderMesh.new()
			cyl.top_radius = r
			cyl.bottom_radius = r
			cyl.height = rng.randf_range(1.3, 1.6)
			cyl.radial_segments = 10
			var x := (i - (n - 1) * 0.5) * r * 2.05
			var v := rng.randf_range(-0.05, 0.05)
			var c: Color = COLORS["wood"]
			_add(cyl, Color(c.r + v, c.g + v, c.b + v), Vector3(x, r + layer * r * 1.75, 0),
				Vector3(PI / 2, 0, rng.randf_range(-0.05, 0.05)))

func _build_mortar(rng: RandomNumberGenerator) -> void:
	# Clay jars + a heap of lime
	var heap := SphereMesh.new()
	heap.radius = 0.55
	heap.height = 0.5
	_add(heap, COLORS["mortar"], Vector3(0.15, 0.0, 0.1), Vector3.ZERO)
	for i in 3:
		var jar := CylinderMesh.new()
		jar.top_radius = 0.14
		jar.bottom_radius = 0.2
		jar.height = 0.5
		jar.radial_segments = 12
		var a := TAU * i / 3.0 + rng.randf() * 0.4
		_add(jar, Color(0.66, 0.42, 0.28), Vector3(cos(a) * 0.6 - 0.2, 0.25, sin(a) * 0.55), Vector3.ZERO)

func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

func _add(mesh: Mesh, color: Color, pos: Vector3, rot: Vector3) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.92
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	_visual.add_child(mi)
