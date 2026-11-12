extends SceneTree

# Dump a CharacterRig at rest for Blender (tools/blender/build_figure.py): every part's mesh in
# the rig's space with its colour, surface kind, bone and fuse group, and every bone's rest.
#   Godot --headless --path . --script res://tools/blender/export_rig.gd -- <out.json> [slot | enemy kind]
# Coordinates stay Godot's (y up, +z the figure's front); the Blender side converts.

var _out := "res://build/blender/builder_rig.json"
var _fig := "0"
var _frame := 0

func _initialize() -> void:
	var rest: Array = []
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			rest.append(a)
	if rest.size() > 0:
		_out = rest[0]
	if rest.size() > 1:
		_fig = rest[1]

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	var look := code_look(_fig)   # the code rig itself: its pivots and parts
	var rig := CharacterRig.new()
	rig._build(look)
	_export(rig, look)
	rig.free()
	return true

func _export(rig: CharacterRig, look: Dictionary) -> void:
	var bones := BakedFigure.bone_map(rig)
	var bone_of := {}
	for k in bones:
		bone_of[bones[k]] = k
	var keep := BakedFigure.kept_pivots(rig)
	var out_bones := []
	for k in bones:
		var n: Node3D = bones[k]
		var parent := ""
		var p := n.get_parent()
		while p != null and p != rig:
			if bone_of.has(p):
				parent = bone_of[p]
				break
			p = p.get_parent()
		var t := BakedFigure.rig_space(n, rig)
		out_bones.append({"name": k, "parent": parent, "origin": _v(t.origin),
			"basis": _v(t.basis.x) + _v(t.basis.y) + _v(t.basis.z)})
	var parts := []
	var tris := 0
	for mi: GeometryInstance3D in rig._parts:
		if BakedFigure.under_any(mi, keep) or not (mi is MeshInstance3D):
			continue
		var bone := ""
		var beard := false
		var n: Node = mi.get_parent()
		while n != null and n != rig:
			if n.name == &"Beard":
				beard = true
			if bone.is_empty() and bone_of.has(n):
				bone = bone_of[n]
			n = n.get_parent()
		var color: Color = mi.get_instance_shader_parameter("part_color")
		var mat := (mi as MeshInstance3D).material_override as ShaderMaterial
		var sculpt := mat != null and mat.shader.resource_path.ends_with("builder_sculpt.gdshader")
		var kind: Variant = mi.get_instance_shader_parameter("surface_kind")
		var t := BakedFigure.rig_space(mi, rig)
		var nb := t.basis.inverse().transposed()
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		var arrays := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			for i in verts.size():
				idx.append(i)
		var flat_v := PackedFloat32Array()
		var flat_n := PackedFloat32Array()
		for i in verts.size():
			var v := t * verts[i]
			flat_v.append_array([v.x, v.y, v.z])
			var nn := (nb * norms[i]).normalized() if norms.size() > i else Vector3.UP
			flat_n.append_array([nn.x, nn.y, nn.z])
		# Godot winds clockwise from the front; flip to counter-clockwise for Blender
		var flip := PackedInt32Array()
		for i in range(0, idx.size(), 3):
			flip.append_array([idx[i], idx[i + 2], idx[i + 1]])
		tris += idx.size() / 3
		parts.append({"bone": bone, "group": _group(bone, beard, color, look), "color": [color.r, color.g, color.b],
			"kind": -1.0 if sculpt or kind == null else float(kind), "metal": sculpt and mat.get_shader_parameter("metal") == 1.0,
			"v": Array(flat_v), "n": Array(flat_n), "i": Array(flip)})
	var doc := {"bones": out_bones, "parts": parts, "dye": [look["hat_color"].r, look["hat_color"].g, look["hat_color"].b]}
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	var f := FileAccess.open(_out, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc))
	f.close()
	print("exported %d parts, %d tris, %d bones -> %s" % [parts.size(), tris, out_bones.size(), ProjectSettings.globalize_path(_out)])

## Which parts are fused into one surface in Blender: skin, hair, beard, the tunic and skirt.
## Small crisp things (eyes, brows, leatherwork, the basket) keep their own shapes.
func _group(bone: String, beard: bool, c: Color, look: Dictionary) -> String:
	var skin: Color = look["skin"]
	var hair: Color = look["hair"]
	var linen: Color = look.get("robe", CharacterRig.LINEN)
	if bone.begins_with("eye"):
		return "eye"
	if bone.begins_with("tail"):
		return "band"
	if beard:
		return "beard"
	if bone == "head":
		var brow: Color = look.get("brow", hair.darkened(0.12))
		if c.is_equal_approx(brow):
			return "brow"
		if _family(c, skin):
			return "face"
		if _family(c, hair):
			return "hair"
		return "band"
	var side := bone.right(1)
	if bone.begins_with("arm") or bone.begins_with("elbow") or bone.begins_with("hand"):
		# Sleeves join the tunic: one shirt, its shoulders bending with the arms
		return ("arm_%s_skin" % side) if _family(c, skin) else "tunic"
	if bone.begins_with("leg") or bone.begins_with("knee") or bone.begins_with("ankle"):
		return ("leg_%s_skin" % side) if _family(c, skin) else "sandal"
	if bone == "skirt":
		return "skirt"
	if bone == "torso" and (_family(c, linen) or _family(c, skin)):
		return "tunic"
	return "gear"

## c is base lightened or darkened by some amount (Color.lightened / darkened)
static func _family(c: Color, base: Color) -> bool:
	for k in 101:
		var a := k / 100.0
		if _near(c, base.lightened(a)) or _near(c, base.darkened(a)):
			return true
	return false

static func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.006

static func _v(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

## A crew slot ("0".."3"), an enemy kind ("scout", "brute", "raider", "saboteur"), a townsperson
## (Folk.look_for kinds) or "watchman", as built in code
static func code_look(fig: String) -> Dictionary:
	var look: Dictionary
	if fig.is_valid_int():
		look = CharacterRig.worker_look(int(fig), Palette.CREW[int(fig)])
	elif fig == "watchman":
		look = CharacterRig.worker_look(1, Palette.CREW[1])
		look.erase("satchel")
		look.merge({"tool": false, "sword": false, "weapon": "spear"}, true)
	elif fig in ["man", "child"]:
		# Townsfolk (Folk.look_for, which needs the game's autoloads): their bones are those of the
		# crew figure they're built on, set by the head cloth (a band's tails, a wrap's veil)
		look = CharacterRig.worker_look(2, Palette.CREW[2])
	elif fig in ["woman", "elder", "priest", "scribe", "governor"]:
		look = CharacterRig.worker_look(3, Palette.CREW[3])
	else:
		look = CharacterRig.enemy_look(fig)
	look.erase("baked")
	return look
