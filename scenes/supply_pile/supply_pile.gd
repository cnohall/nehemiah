extends StaticBody3D

# Material stockpile. request_pickup() is server-only (called from Player._server_interact).
# Rubble heaps ("salvage" twist) are the same thing with a small stock that the server
# refills each dawn; their count replicates so every peer sees them run down.

@export var kind: String = "stone"   # "stone" | "wood" | "mortar" | "beam"
## Present only in sections with this twist; "!twist" = only in sections WITHOUT it
## (empty = always)
@export var twist: String = ""
## Rubble heap look + limited stock (0 = endless stockpile)
@export var rubble_stock: int = 0

var count: int = 999:
	set(value):
		count = value
		if is_node_ready():
			_refresh_active()
			_show_stock()

var _rubble_stones: Array[Node3D] = []

@onready var _visual:     Node3D  = $Visual
@onready var count_label: Label3D = $CountLabel

const COLORS := {
	"stone":  Color(0.68, 0.60, 0.48),
	"wood":   Color(0.50, 0.33, 0.17),
	"mortar": Color(0.86, 0.80, 0.66),
	"beam":   Color(0.46, 0.31, 0.17),
	"lime":   Color(0.92, 0.91, 0.86),
	"water":  Color(0.66, 0.40, 0.26),
}

func _ready() -> void:
	count_label.text = kind.capitalize() + ("s" if kind == "beam" else "")
	Mobile.world_text(count_label)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind) + hash(name)
	if rubble_stock > 0:
		count = rubble_stock
		count_label.text = "Rubble"
		add_to_group("restockable")
		_build_rubble_heap(rng)
		_build_sync()
		GameState.section_changed.connect(_refresh_active.unbind(1))
		_refresh_active()
		return
	match kind:
		"stone":
			_build_pallet(rng)
			_build_stones(rng)
		"wood":
			_build_sleepers(rng)
			_build_logs(rng)
		"mortar":
			_build_reed_mat(rng)
			_build_mortar(rng)
		"beam":
			_build_sleepers(rng)
			_build_beams(rng)
		"lime":
			_build_lime(rng)
		"water":
			_build_water(rng)
	GameState.section_changed.connect(_refresh_active.unbind(1))
	_refresh_active()

# Twist-only piles appear with their section; out of it they're gone entirely
func _refresh_active() -> void:
	var active := _in_section()
	visible = active
	$CollisionShape3D.set_deferred("disabled", not active)
	# An emptied heap stays visible (a scrape of ash) but can't be picked from
	if active and count > 0:
		add_to_group("supply_piles")
	else:
		remove_from_group("supply_piles")

func _in_section() -> bool:
	if twist.is_empty():
		return true
	if twist.begins_with("!"):
		return not GameState.has_twist(twist.substr(1))
	return GameState.has_twist(twist)

func request_pickup() -> bool:
	if not multiplayer.is_server() or count <= 0:
		return false
	count -= 1
	return true

## Server, each dawn: fresh stone turned up from the rubble overnight
func restock() -> void:
	if multiplayer.is_server() and rubble_stock > 0:
		count = rubble_stock

func _build_sync() -> void:
	var cfg := SceneReplicationConfig.new()
	cfg.add_property(^".:count")
	cfg.property_set_replication_mode(^".:count", SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.replication_config = cfg
	NetworkManager.gate_sync(sync)
	add_child(sync)

# ── Visuals ────────────────────────────────────────────────

const ASH := Color(0.30, 0.27, 0.24)

# Burned rubble (Neh. 4:2 "burned as they are"): a low scorched mound with loose
# blocks on top; blocks disappear as the stock runs down
func _build_rubble_heap(rng: RandomNumberGenerator) -> void:
	var mound := SphereMesh.new()
	mound.radius = 1.25
	mound.height = 0.7
	mound.radial_segments = 12
	mound.rings = 4
	_add(mound, ASH.lerp(COLORS["stone"], 0.7), Vector3(0, 0.05, 0), Vector3(0, rng.randf() * TAU, 0))
	for i in rubble_stock:
		var a := TAU * i / rubble_stock + rng.randf_range(-0.3, 0.3)
		var r := rng.randf_range(0.2, 0.8)
		var soot := rng.randf_range(0.1, 0.45)
		var c: Color = COLORS["stone"].lerp(ASH, soot)
		var s := Vector3(rng.randf_range(0.5, 0.75), rng.randf_range(0.3, 0.42), rng.randf_range(0.38, 0.55))
		var mi := _add(_box(s), c, Vector3(cos(a) * r, 0.4 + rng.randf_range(0.0, 0.15), sin(a) * r),
			Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3)))
		_rubble_stones.append(mi)

func _show_stock() -> void:
	for i in _rubble_stones.size():
		_rubble_stones[i].visible = i < count
	if rubble_stock > 0:
		count_label.text = "Rubble" if count > 0 else "Picked clean"

const TIMBER := Color(0.46, 0.34, 0.22)
const REED   := Color(0.66, 0.57, 0.38)
const LIME   := Color(0.88, 0.86, 0.80)

# Each pile sits on what a work yard would really use — distinct shapes, natural colours

# Stone: a low pallet of rough planks (keeps blocks out of the dust)
func _build_pallet(rng: RandomNumberGenerator) -> void:
	for i in 5:
		var v := rng.randf_range(-0.05, 0.04)
		_add(_box(Vector3(1.9, 0.07, 0.34)), Color(TIMBER.r + v, TIMBER.g + v, TIMBER.b + v),
			Vector3(rng.randf_range(-0.04, 0.04), 0.14, -0.8 + i * 0.4), Vector3(0, rng.randf_range(-0.03, 0.03), 0))
	for x: float in [-0.75, 0.0, 0.75]:
		_add(_box(Vector3(0.14, 0.1, 2.0)), TIMBER.darkened(0.25), Vector3(x, 0.06, 0), Vector3.ZERO)

# Wood: two sleeper beams on a patch of bark chips
func _build_sleepers(rng: RandomNumberGenerator) -> void:
	for i in 16:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.5, 1.2)
		var v := rng.randf_range(-0.05, 0.05)
		_add(_box(Vector3(rng.randf_range(0.08, 0.2), 0.02, rng.randf_range(0.05, 0.1))),
			Color(0.45 + v, 0.33 + v, 0.21 + v), Vector3(cos(a) * r, 0.11, sin(a) * r),
			Vector3(0, rng.randf() * TAU, 0))
	for z: float in [-0.5, 0.5]:
		_add(_box(Vector3(1.3, 0.14, 0.18)), TIMBER.darkened(0.15),
			Vector3(0, 0.12, z), Vector3(0, rng.randf_range(-0.06, 0.06), 0))

# Mortar: a woven reed mat with spilled lime around the jars
func _build_reed_mat(rng: RandomNumberGenerator) -> void:
	for i in 7:
		var v := rng.randf_range(-0.04, 0.04)
		_add(_box(Vector3(2.0, 0.03, 0.27)), Color(REED.r + v, REED.g + v, REED.b + v * 0.6),
			Vector3(0, 0.115, -0.84 + i * 0.28), Vector3.ZERO)
	for i in 4:
		var spill := CylinderMesh.new()
		spill.top_radius = rng.randf_range(0.18, 0.35)
		spill.bottom_radius = spill.top_radius
		spill.height = 0.01
		spill.radial_segments = 14
		_add(spill, LIME, Vector3(rng.randf_range(-0.8, 0.8), 0.135, rng.randf_range(-0.8, 0.8)), Vector3.ZERO)

# Long squared timbers, stacked two high across the sleepers
func _build_beams(rng: RandomNumberGenerator) -> void:
	for layer in 2:
		for i in 3 - layer:
			var v := rng.randf_range(-0.04, 0.04)
			var c: Color = COLORS["beam"]
			_add(_box(Vector3(0.24, 0.22, 2.6)), Color(c.r + v, c.g + v, c.b + v),
				Vector3((i - (2 - layer) * 0.5) * 0.3, 0.3 + layer * 0.22, rng.randf_range(-0.08, 0.08)),
				Vector3(0, rng.randf_range(-0.03, 0.03), 0))

# Burnt lime: a pale heap in a low timber bin, sacks leaning on it
func _build_lime(rng: RandomNumberGenerator) -> void:
	for side: Vector3 in [Vector3(0, 0, -0.75), Vector3(0, 0, 0.75)]:
		_add(_box(Vector3(1.7, 0.3, 0.1)), TIMBER, side + Vector3(0, 0.25, 0), Vector3.ZERO)
	for side: Vector3 in [Vector3(-0.85, 0, 0), Vector3(0.85, 0, 0)]:
		_add(_box(Vector3(0.1, 0.3, 1.5)), TIMBER, side + Vector3(0, 0.25, 0), Vector3.ZERO)
	var heap := SphereMesh.new()
	heap.radius = 0.75
	heap.height = 0.55
	_add(heap, COLORS["lime"], Vector3(0, 0.2, 0), Vector3.ZERO)
	for i in 2:
		var sack := SphereMesh.new()
		sack.radius = 0.22
		sack.height = 0.4
		_add(sack, COLORS["lime"].darkened(0.08), Vector3(1.1, 0.2, -0.3 + i * 0.55), Vector3(0, 0, rng.randf_range(-0.3, 0.3)))

# Water: big clay storage jars on a stone slab, a dark damp patch around them
func _build_water(rng: RandomNumberGenerator) -> void:
	var damp := CylinderMesh.new()
	damp.top_radius = 1.1
	damp.bottom_radius = 1.1
	damp.height = 0.01
	_add(damp, Color(0.55, 0.45, 0.32), Vector3(0, 0.105, 0), Vector3.ZERO)
	_add(_box(Vector3(1.8, 0.1, 1.2)), Color(0.66, 0.60, 0.52), Vector3(0, 0.15, 0), Vector3.ZERO)
	for i in 3:
		var x := -0.55 + i * 0.55
		var h := rng.randf_range(0.85, 1.05)
		var jar := SphereMesh.new()
		jar.radius = 0.3
		jar.height = h
		_add(jar, COLORS["water"].darkened(rng.randf_range(0.0, 0.12)), Vector3(x, 0.2 + h * 0.5, 0), Vector3.ZERO)
		var mouth := CylinderMesh.new()
		mouth.top_radius = 0.14
		mouth.bottom_radius = 0.11
		mouth.height = 0.12
		_add(mouth, COLORS["water"].darkened(0.1), Vector3(x, 0.2 + h + 0.02, 0), Vector3.ZERO)

func _build_stones(rng: RandomNumberGenerator) -> void:
	# Loose cut blocks, stacked in two rough layers
	for layer in 2:
		var n := 6 - layer * 3
		for i in n:
			var s := Vector3(rng.randf_range(0.55, 0.8), 0.38, rng.randf_range(0.4, 0.55))
			var pos := Vector3(rng.randf_range(-0.5, 0.5) * (1.0 - layer * 0.5), 0.36 + layer * 0.38,
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
			_add(cyl, Color(c.r + v, c.g + v, c.b + v), Vector3(x, 0.19 + r + layer * r * 1.75, 0),
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

func _add(mesh: Mesh, color: Color, pos: Vector3, rot: Vector3) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.92
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	_visual.add_child(mi)
	return mi
