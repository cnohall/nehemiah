class_name Chunky
extends RefCounted

# The chunky, hand-cut look shared by the world: beveled blocks whose chamfer stays the
# same width in world space however the block is stretched (the shader re-insets the
# chamfer vertices per instance), so a long wall course and a small rubble stone both
# get the same crisp lit edge. Also a faceted variant for foliage and boulders.

const SHADER := preload("res://assets/shaders/chunky.gdshader")
const UNIT_BEVEL := 0.15   # authoring inset of the unit mesh; the shader swaps in the real one

static var _unit: ArrayMesh
static var _mats: Dictionary = {}

## Unit cube (-0.5..0.5) with chamfered edges — pair with block_material()
static func unit_block() -> ArrayMesh:
	if _unit == null:
		_unit = bevel_box(Vector3.ONE, UNIT_BEVEL)
	return _unit

## Timber: chunky block with grain streaks along its length
static func wood_material(bevel := 0.025) -> ShaderMaterial:
	return material(bevel, false, 0.3, 0.22)

## Foliage: smooth, lumpy, strongly lit from above (bright crowns, dark undersides)
static func foliage_material() -> ShaderMaterial:
	if not _mats.has("foliage"):
		var m := material(0.0, false, 0.0).duplicate() as ShaderMaterial
		m.set_shader_parameter("top_light", 0.3)
		m.set_shader_parameter("grain", 0.14)
		m.set_shader_parameter("ground_ao", 0.0)
		_mats["foliage"] = m
	return _mats["foliage"]

## Material for multimesh / vertex-coloured chunky geometry.
##   bevel: world-space chamfer width (0 = leave the mesh as authored)
##   facets: flat-shade each triangle (foliage, boulders)
static func material(bevel := 0.06, facets := false, edge_light := 0.22, streaks := 0.0) -> ShaderMaterial:
	var key := "%.3f|%s|%.2f|%.2f" % [bevel, facets, edge_light, streaks]
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("bevel", bevel)
		m.set_shader_parameter("unit_inset", UNIT_BEVEL if bevel > 0.0 else 0.0)
		m.set_shader_parameter("facets", facets)
		m.set_shader_parameter("edge_light", edge_light)
		m.set_shader_parameter("streaks", streaks)
		_mats[key] = m
	return _mats[key]

## A box of the given size with chamfered edges and corners (flat-shaded faces).
static func bevel_box(size: Vector3, bevel: float) -> ArrayMesh:
	var h := size * 0.5
	var b := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.9)
	var i := h - Vector3.ONE * b    # inner extent
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Main faces
	for axis in 3:
		for s: float in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = s
			var u := (axis + 1) % 3
			var v := (axis + 2) % 3
			var pts: Array[Vector3] = []
			for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var p := Vector3.ZERO
				p[axis] = s * h[axis]
				p[u] = c.x * i[u]
				p[v] = c.y * i[v]
				pts.append(p)
			_quad(st, pts, n)
	# Edge chamfers: between faces (a, sa) and (c, sc), running along the third axis
	for a in 3:
		for c in range(a + 1, 3):
			var t := 3 - a - c
			for sa: float in [-1.0, 1.0]:
				for sc: float in [-1.0, 1.0]:
					var n := Vector3.ZERO
					n[a] = sa
					n[c] = sc
					var pts: Array[Vector3] = []
					for k: Vector2 in [Vector2(1, -1), Vector2(0, -1), Vector2(0, 1), Vector2(1, 1)]:
						var p := Vector3.ZERO
						# k.x = 1: on face a (a out, c inset); 0: on face c
						p[a] = sa * (h[a] if k.x == 1 else i[a])
						p[c] = sc * (i[c] if k.x == 1 else h[c])
						p[t] = k.y * i[t]
						pts.append(p)
					_quad(st, pts, n.normalized())
	# Corner triangles
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var n := Vector3(sx, sy, sz).normalized()
				var pts: Array[Vector3] = [
					Vector3(sx * h.x, sy * i.y, sz * i.z),
					Vector3(sx * i.x, sy * h.y, sz * i.z),
					Vector3(sx * i.x, sy * i.y, sz * h.z)]
				_tri(st, pts[0], pts[1], pts[2], n)
	return st.commit()

## A box with rounded edges and corners (radius r) and smooth normals — the soft,
## toy-figure look for characters. Rounding segments are spaced by angle so the curve
## is even; flat faces stay a single quad strip.
static func round_box(size: Vector3, r: float, seg := 3) -> ArrayMesh:
	var h := size * 0.5
	r = minf(r, minf(h.x, minf(h.y, h.z)) * 0.98)
	var inner := h - Vector3.ONE * r
	# Per-axis sample coordinates on the flat cube, far side to near side
	var coords: Array[PackedFloat32Array] = []
	for axis in 3:
		var c := PackedFloat32Array()
		for j in range(seg, -1, -1):
			c.append(-inner[axis] - r * tan(PI * 0.25 * j / seg))
		for j in range(0, seg + 1):
			c.append(inner[axis] + r * tan(PI * 0.25 * j / seg))
		coords.append(c)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis in 3:
		for s: float in [-1.0, 1.0]:
			var u := (axis + 1) % 3
			var v := (axis + 2) % 3
			var cu: PackedFloat32Array = coords[u]
			var cv: PackedFloat32Array = coords[v]
			var face_n := Vector3.ZERO
			face_n[axis] = s
			for a in cu.size() - 1:
				for b in cv.size() - 1:
					var q: Array[Vector3] = []
					for k: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
						var p := Vector3.ZERO
						p[axis] = s * h[axis]
						p[u] = cu[a + k.x]
						p[v] = cv[b + k.y]
						q.append(p)
					var pts: Array[Vector3] = []
					var ns: Array[Vector3] = []
					for p in q:
						var c := p.clamp(-inner, inner)
						var d := p - c
						var n := d.normalized() if d.length() > 0.00001 else face_n
						pts.append(c + n * r)
						ns.append(n)
					_stri(st, pts[0], pts[1], pts[2], ns[0], ns[1], ns[2], face_n)
					_stri(st, pts[0], pts[2], pts[3], ns[0], ns[2], ns[3], face_n)
	st.index()
	return st.commit()

static func _stri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3, face_n: Vector3) -> void:
	if (b - a).cross(c - a).dot(face_n) > 0.0:
		var t := b
		b = c
		c = t
		var tn := nb
		nb = nc
		nc = tn
	st.set_normal(na)
	st.add_vertex(a)
	st.set_normal(nb)
	st.add_vertex(b)
	st.set_normal(nc)
	st.add_vertex(c)

static func _quad(st: SurfaceTool, p: Array[Vector3], n: Vector3) -> void:
	_tri(st, p[0], p[1], p[2], n)
	_tri(st, p[0], p[2], p[3], n)

# Godot's front faces wind clockwise seen from outside: flip to match the normal
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var tmp := b
		b = c
		c = tmp
	for p: Vector3 in [a, b, c]:
		st.set_normal(n)
		st.add_vertex(p)
