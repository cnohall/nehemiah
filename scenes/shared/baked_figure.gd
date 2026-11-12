class_name BakedFigure
extends Node3D

## A figure modelled in Blender (tools/blender) worn over a CharacterRig's pivots: one skinned
## mesh in place of the rig's ~150 parts. The rig still builds and animates its pivots as
## before; every bone is named after one (bone_map) and takes that pivot's motion since the
## figure was built: B = P_now · P_rest⁻¹ · B_rest (in rig space). The props that come and go
## (hammer, paddle, sword) stay as the rig's own parts.

const SHADER := preload("res://assets/shaders/baked_figure.gdshader")
const SHADER_TEX := preload("res://assets/shaders/baked_figure_tex.gdshader")
static var _material: ShaderMaterial
static var _textured := {}           # glb path → ShaderMaterial (figures with painted textures)

var _rig: Node3D
var _skeleton: Skeleton3D
var _bones: Array[int] = []          # parent before child
var _pivots: Array[Node3D] = []
var _rest: Array[Transform3D] = []   # P_rest⁻¹ · S · B_rest per bone (S: skeleton in rig space)
var _s_inv := Transform3D.IDENTITY

## Bone name → the rig pivot it follows. The same names are written by the exporter
## (tools/blender/export_rig.gd) and given to the armature in Blender.
static func bone_map(rig: Node3D) -> Dictionary:
	var m := {"root": rig._body, "torso": rig._torso, "skirt": rig._skirt, "head": rig._head,
		"arm_l": rig._arm_l, "arm_r": rig._arm_r, "leg_l": rig._leg_l, "leg_r": rig._leg_r}
	# Sides are built +x first (BuilderBody.build): l is the figure's own left
	var sides := ["l", "r"]
	for i in mini(2, rig._elbows.size()):
		m["elbow_" + sides[i]] = rig._elbows[i]
	for i in mini(2, rig._hands.size()):
		m["hand_" + sides[i]] = rig._hands[i]
	for i in mini(2, rig._knees.size()):
		m["knee_" + sides[i]] = rig._knees[i]
	for i in mini(2, rig._ankles.size()):
		m["ankle_" + sides[i]] = rig._ankles[i]
	for e: Node3D in rig._eyes:
		m["eye_l" if e.position.x > 0.0 else "eye_r"] = e
	for i in rig._tails.size():
		m["tail_%d" % i] = rig._tails[i]
	if rig._veil != null:
		m["veil"] = rig._veil
	if rig._cape != null:
		m["cape"] = rig._cape
	for k in m.keys():
		if m[k] == null:
			m.erase(k)
	return m

## The props kept as the rig's own parts: shown and hidden by the pose (CharacterRig._tool_visible)
static func kept_pivots(rig: Node3D) -> Array:
	return [rig._tool, rig._paddle, rig._sword, rig._belt_sword, rig._belt_tool].filter(func(n): return n != null)

## `node`'s transform in the rig's own space, by its parents (works off the tree too)
static func rig_space(node: Node3D, rig: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n := node
	while n != null and n != rig:
		t = n.transform * t
		n = n.get_parent() as Node3D
	return t

static func under_any(node: Node, roots: Array) -> bool:
	var n := node
	while n != null:
		if n in roots:
			return true
		n = n.get_parent()
	return false

## Swap the rig's parts for the baked mesh at `path`. Called at the end of CharacterRig._build,
## so the pivots are still at rest, as they were when the figure was exported.
static func apply(rig: Node3D, path: String) -> BakedFigure:
	var scene := load(path) as PackedScene
	if scene == null:
		push_warning("BakedFigure: no scene at %s" % path)
		return null
	var keep := kept_pivots(rig)
	var kept: Array[GeometryInstance3D] = []
	for p: GeometryInstance3D in rig._parts:
		if under_any(p, keep):
			kept.append(p)
		else:
			p.free()
	rig._parts.assign(kept)
	var fig := BakedFigure.new()
	fig.name = "Baked"
	rig.add_child(fig)
	fig._setup(rig, scene.instantiate(), _material_for(path))
	return fig

## Figures from build_crew.py come with textures beside the glb (<name>_albedo.png, _normal,
## _aux); the fused ones (build_figure.py) carry their paint per vertex.
static func _material_for(path: String) -> ShaderMaterial:
	var base := path.get_basename()
	if ResourceLoader.exists(base + "_albedo.png"):
		if not _textured.has(path):
			var m := ShaderMaterial.new()
			m.shader = SHADER_TEX
			m.set_shader_parameter("albedo_tex", load(base + "_albedo.png"))
			m.set_shader_parameter("normal_tex", load(base + "_normal.png"))
			m.set_shader_parameter("aux_tex", load(base + "_aux.png"))
			_textured[path] = m
		return _textured[path]
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	return _material

func _setup(rig: Node3D, inst: Node3D, material: ShaderMaterial) -> void:
	_rig = rig
	add_child(inst)
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = material
		mi.set_instance_shader_parameter("dye", rig._look.get("dye", rig._look.get("hat_color", Color.WHITE)))
		rig._parts.append(mi)
	var found := inst.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return
	_skeleton = found[0]
	var s := rig_space(_skeleton, rig)
	_s_inv = s.affine_inverse()
	var map := bone_map(rig)
	var order: Array = []
	for b in _skeleton.get_bone_count():
		var bone_name := _skeleton.get_bone_name(b)
		if not map.has(bone_name):
			# A look without head-band tails has no pivot for them: the bone rides its parent
			if not bone_name.begins_with("tail_"):
				push_warning("BakedFigure: no pivot for bone %s" % bone_name)
			continue
		var depth := 0
		var p := _skeleton.get_bone_parent(b)
		while p >= 0:
			depth += 1
			p = _skeleton.get_bone_parent(p)
		order.append([depth, b])
	order.sort_custom(func(a, b): return a[0] < b[0])
	for o in order:
		var b: int = o[1]
		var pivot: Node3D = map[_skeleton.get_bone_name(b)]
		_bones.append(b)
		_pivots.append(pivot)
		_rest.append(rig_space(pivot, rig).affine_inverse() * s * _skeleton.get_bone_global_rest(b))

## Follow the pivots (after the rig's pose and its secondary motion)
func pose() -> void:
	if _skeleton == null:
		return
	var rig_inv := _rig.global_transform.affine_inverse() if _rig.is_inside_tree() else Transform3D.IDENTITY
	for i in _bones.size():
		var p := rig_inv * _pivots[i].global_transform if _rig.is_inside_tree() else rig_space(_pivots[i], _rig)
		_skeleton.set_bone_global_pose(_bones[i], _s_inv * p * _rest[i])
