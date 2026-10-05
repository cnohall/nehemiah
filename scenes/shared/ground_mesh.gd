extends MeshInstance3D

# The ground's shape: a heightfield from Terrain, rebuilt for each section. It replaces the
# flat slab's visual only — the collider is still the flat floor, and everything people walk
# on is flat (Terrain), so heights show only on the far side of the valley and up the city's hill.

const FLOOR_TOP := 0.1   # y of the flat slab's top face (the collider)
const NORMAL_EPS := 0.2

var _built := -1

func _ready() -> void:
	GameState.section_changed.connect(_rebuild.unbind(1))
	_rebuild()

func _rebuild() -> void:
	var index := GameState.current_section_index
	if index == _built:
		return
	_built = index
	Terrain.use_section(index)
	var xs := _axis([[-110.0, -60.0, 5.0], [-60.0, 60.0, 2.0], [60.0, 110.0, 5.0]])
	var zs := _axis([[-90.0, -60.0, 3.0], [-60.0, -28.0, 1.0], [-28.0, 24.0, 4.0], [24.0, 64.0, 0.4], [64.0, 90.0, 2.0]])
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	verts.resize(xs.size() * zs.size())
	normals.resize(verts.size())
	var i := 0
	for z in zs:
		for x in xs:
			verts[i] = Vector3(x, FLOOR_TOP + Terrain.height(x, z), z)
			var dx: float = Terrain.height(x + NORMAL_EPS, z) - Terrain.height(x - NORMAL_EPS, z)
			var dz: float = Terrain.height(x, z + NORMAL_EPS) - Terrain.height(x, z - NORMAL_EPS)
			normals[i] = Vector3(-dx, NORMAL_EPS * 2.0, -dz).normalized()
			i += 1
	var indices := PackedInt32Array()
	var w := xs.size()
	for r in zs.size() - 1:
		for c in w - 1:
			var a := r * w + c
			indices.append_array([a, a + 1, a + w, a + 1, a + w + 1, a + w])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = m
	# The terrace risers are steep, the shader reads them from the normal; no shadow
	# from the ground onto itself is needed beyond the sun's
	custom_aabb = AABB(Vector3(-110, -20, -90), Vector3(220, 60, 180))

## Sorted sample positions from [from, to, step] runs (each run ends where the next starts)
static func _axis(runs: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for run: Array in runs:
		var n := roundi((run[1] - run[0]) / run[2])
		for k in n:
			out.append(run[0] + (run[1] - run[0]) * k / n)
	out.append(runs[-1][1])
	return out
