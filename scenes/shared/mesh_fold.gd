class_name MeshFold
extends RefCounted

# Folds many small static meshes into one, each piece's colour baked into its vertices
# (linear). A figure or a supply pile built from dozens of parts then costs one draw
# (+ one shadow) instead of dozens. Materials that read the colour: toon_part /
# builder_sculpt multiply COLOR in; `vertex_material()` for plain props.

static var _vertex_mat: StandardMaterial3D

## items: [mesh, Transform3D, Color or null (= white)], all triangle meshes
static func fold(items: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var colors := PackedColorArray()
	for it: Array in items:
		var mesh: Mesh = it[0]
		var c: Color = (it[2] as Color).srgb_to_linear() if it[2] != null else Color.WHITE
		for s in mesh.get_surface_count():
			st.append_from(mesh, s, it[1])
			var run := PackedColorArray()
			run.resize((mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
			run.fill(c)
			colors.append_array(run)
	var arrays := st.commit_to_arrays()
	var n := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	if colors.size() != n:
		push_error("MeshFold: colours don't line up with vertices")
		colors.resize(n)
	arrays[Mesh.ARRAY_COLOR] = colors
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out

## Matte material that takes its albedo from the baked vertex colours
static func vertex_material() -> StandardMaterial3D:
	if _vertex_mat == null:
		_vertex_mat = StandardMaterial3D.new()
		_vertex_mat.vertex_color_use_as_albedo = true
		_vertex_mat.vertex_color_is_srgb = false   # baked linear
		_vertex_mat.roughness = 0.92
	return _vertex_mat
