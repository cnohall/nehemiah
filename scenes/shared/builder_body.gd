extends RefCounted

# Builder-only clothing, anatomy and equipment. Dimensions use the original
# hip/shoulder/hand pivots, so all gameplay animation and carry anchors still fit.
# Detailed surfaces and woven reeds are cached; the basket weave is batched into
# two meshes rather than hundreds of individual draw calls.
const HIP := 0.36
const LINEN := Color(0.89, 0.82, 0.66)
const LEATHER := Color(0.34, 0.16, 0.075)
const EDGE := Color(0.48, 0.28, 0.13)
const BRONZE := Color(0.61, 0.40, 0.19)
# Joints, in the limb's own (unstretched) space: the knee and ankle down the leg from the
# hip pivot, the elbow down the arm from the shoulder. Parts below each are hung on it
const KNEE_Y := -0.13
const ANKLE_Y := -0.2
const ELBOW_Y := -0.2
# Hem heights (torso space, before its stretch) and flares, short build → tall: the tunic
# just past the knee, the long robe to the ankle, whatever the legs (CharacterRig.build)
const HEM_SHORT := Vector2(-0.123, -0.215)
const HEM_LONG := Vector2(-0.30, -0.545)
const FLARE_SHORT := Vector2(0.370, 0.345)
const FLARE_LONG := Vector2(0.385, 0.375)
static var _cache: Dictionary = {}
static var _material: ShaderMaterial
var _rig: Node3D
var _skin: Color
var _linen := LINEN
var _belt := LEATHER
var _long := false
var _gear := false   # cross strap, shoulder harness and hip pouches
var _trim := LINEN
var _grown := 0.0      # the rig's build (CharacterRig._grown)
var _hem := 0.0        # this figure's hem height and flare at that build
var _flare := 0.0
var _g := ""           # cache-key suffix for meshes that follow the build

func build(rig: Node3D, look: Dictionary) -> Array[Node3D]:
	_rig = rig
	_skin = look["skin"]
	_linen = look.get("robe", LINEN)
	_trim = look.get("trim", _linen.darkened(0.15))
	_grown = rig._grown
	var long_robe: bool = look.get("long_robe", false)
	var hem: Vector2 = HEM_LONG if long_robe else HEM_SHORT
	var fl: Vector2 = FLARE_LONG if long_robe else FLARE_SHORT
	_hem = lerpf(hem.x, hem.y, _grown)
	_flare = lerpf(fl.x, fl.y, _grown)
	_g = "_g%d" % roundi(_grown * 100.0)
	_belt = look.get("belt_color", LEATHER)
	_long = look.get("long_robe", false)
	_gear = look.get("strap", false)
	var sleeve_cloth: bool = not look.get("bare_arms", true)
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = preload("res://assets/shaders/builder_body.gdshader")
	_rig._torso = _rig._pivot(_rig._body, Vector3(0, HIP, 0))
	_tunic()
	if look.has("armour"):
		_corselet(look["armour"])
	if look.has("vest"):
		_vest(look["vest"])
	_leatherwork()
	if look.has("cape"):
		_cloak(look["cape"])
	if look.get("basket", false):
		_basket(look.get("basket_stones", true))
	var legs: Array[Node3D] = []
	var arms: Array[Node3D] = []
	var hands: Array[Node3D] = []
	for side: float in [1.0, -1.0]:
		var leg: Node3D = _rig._pivot(_rig._body, Vector3(side * 0.163, HIP, 0))
		_leg(leg, side)
		legs.append(leg)
		var arm: Node3D = _rig._pivot(_rig._torso, Vector3(side * 0.36, 0.50, 0))
		arms.append(arm)
		hands.append(_arm(arm, side, sleeve_cloth))
		_joint_leg(leg)
		_joint_arm(arm)
	_rig._leg_l = legs[0]
	_rig._leg_r = legs[1]
	_rig._arm_l = arms[0]
	_rig._arm_r = arms[1]
	_rig._carry_anchor = _rig._pivot(_rig._torso, Vector3(0, 0.4, 0.42))
	return hands

func _part(parent: Node3D, mesh: Mesh, color: Color, pos := Vector3.ZERO, kind := 0.0, rot := Vector3.ZERO) -> MeshInstance3D:
	var part: MeshInstance3D = _rig._part(parent, mesh, color, pos, rot)
	part.material_override = _material
	part.set_instance_shader_parameter("surface_kind", kind)
	return part

func _oval(parent: Node3D, size: Vector3, color: Color, pos: Vector3, kind := 0.0, rot := Vector3.ZERO) -> void:
	_part(parent, _rig._ellipsoid(size, true), color, pos, kind, rot)

func _soft(parent: Node3D, size: Vector3, color: Color, pos: Vector3, kind := 2.0, rot := Vector3.ZERO) -> void:
	_part(parent, _rig._soft(size, minf(size.x, minf(size.y, size.z)) * 0.22), color, pos, kind, rot)

func _tunic() -> void:
	var torso: Node3D = _rig._torso
	# Skin inside the V-neck. The collar overlaps it instead of a painted triangle.
	_oval(torso, Vector3(0.25, 0.25, 0.22), _skin, Vector3(0, 0.555, 0.006))
	_part(torso, _surface("tunic", 20, 40, func(u: float, v: float) -> Vector3:
		var a := u * TAU
		# Broad upper chest and shoulder shelf, then a clean taper into the belt.
		# The final inward turn leaves the existing neck and head proportions intact.
		var width := 0.300 + 0.054 * smoothstep(0.18, 0.72, v) - 0.140 * smoothstep(0.78, 1.0, v)
		var depth := 0.210 + 0.027 * smoothstep(0.20, 0.65, v) - 0.063 * smoothstep(0.80, 1.0, v)
		var y := 0.20 + v * 0.38
		# The front neck edge drops into a V, back edge stays at the nape.
		if sin(a) > 0:
			y -= pow(v, 8) * 0.13 * pow(maxf(0.0, 1.0 - absf(cos(a)) * 2.0), 1.15)
		var crease := 0.008 * sin(a * 7.0 + v * 5.0) * sin(v * PI)
		crease += 0.004 * sin(a * 13.0 - v * 9.0) * (1.0 - v)
		return Vector3(cos(a) * (width + crease), y, sin(a) * (depth + crease))
	), _linen, Vector3.ZERO, 1.0)
	# The skirt hangs from the belt on its own pivot, so it can lag a step behind the body
	# and flare round the knees (CharacterRig._secondary)
	const BELT := 0.2
	var skirt: Node3D = _rig._pivot(torso, Vector3(0, BELT, 0))
	_rig._skirt = skirt
	var hem_y := _hem
	var flare := _flare
	_part(skirt, _surface(("skirt_long" if _long else "skirt") + _g, 16, 40, func(u: float, v: float) -> Vector3:
		var a := u * TAU
		var radius := lerpf(flare, 0.300, pow(v, 0.85))
		# Folds deepen toward the hem: long vertical pleats from the belt, a few broad ones
		var folds := (sin(a * 9.0 + 0.4) * 0.014 + sin(a * 5.0 - 0.8) * 0.007 + sin(a * 17.0 + 1.3) * 0.004) * pow(1.0 - v, 0.7)
		var y := hem_y + v * (0.217 - hem_y) + pow(1.0 - v, 4) * (sin(a * 3.0 + 0.5) * 0.012 + cos(a * 9.0) * 0.006)
		return Vector3(cos(a) * (radius + folds), y - BELT, sin(a) * (radius * 0.72 + folds))
	), _linen, Vector3.ZERO, 1.0)
	# Folded linen lapels cross over the chest; their edges sit on the cloth surface.
	_ribbon(torso, "collar_left", [Vector3(-0.16, 0.571, 0.11), Vector3(-0.13, 0.53, 0.18), Vector3(0.015, 0.43, 0.239), Vector3(0.115, 0.32, 0.225)], 0.046, 0.008, _linen.lightened(0.06), 1.0)
	_ribbon(torso, "collar_right", [Vector3(0.16, 0.571, 0.11), Vector3(0.12, 0.53, 0.19), Vector3(-0.045, 0.42, 0.245), Vector3(-0.14, 0.27, 0.214)], 0.047, 0.009, _linen.lightened(0.08), 1.0)
	_ribbon(torso, "wrap_seam", [Vector3(-0.13, 0.29, 0.216), Vector3(-0.15, 0.25, 0.22), Vector3(-0.155, 0.21, 0.224), Vector3(-0.16, 0.17, 0.228)], 0.011, 0.004, _linen.darkened(0.12), 1.0)
	# Below the belt the wrap's edge falls with the skirt, opening a little toward the hem
	var seam_r := flare * 0.72
	_ribbon(skirt, ("wrap_seam_skirt_long" if _long else "wrap_seam_skirt") + _g, [Vector3(-0.16, 0.17 - BELT, 0.232),
		Vector3(-0.17, 0.0 - BELT, 0.25), Vector3(-0.18, (hem_y + 0.1) * 0.6 - BELT, seam_r * 0.92),
		Vector3(-0.19, hem_y + 0.012 - BELT, seam_r * 0.97)], 0.011, 0.004, _linen.darkened(0.12), 1.0)
	# Raised hem follows the same irregular folds as the skirt, a woven band in a darker thread
	var hem: Array[Vector3] = []
	for i in 65:
		var a := TAU * i / 64.0
		var f := sin(a * 9.0 + 0.4) * 0.014 + sin(a * 5.0 - 0.8) * 0.007 + sin(a * 17.0 + 1.3) * 0.004
		hem.append(Vector3(cos(a) * (flare + f), hem_y + 0.004 + sin(a * 3.0 + 0.5) * 0.012 + cos(a * 9.0) * 0.006 - BELT, sin(a) * (flare * 0.72 + f)))
	_part(skirt, _tube(("hem_long" if _long else "hem") + _g, hem, 0.006, 6), _linen.darkened(0.08), Vector3.ZERO, 1.0)
	var band: Array[Vector3] = []
	for p in hem:
		band.append(p + Vector3(0, 0.035, 0) + Vector3(p.x, 0, p.z).normalized() * -0.004)
	_part(skirt, _tube(("hem_band_long" if _long else "hem_band") + _g, band, 0.0045, 5), _hem_band_color(), Vector3.ZERO, 1.0)

## The woven band above the hem: the trim's thread, never quite the cloth's own colour
func _hem_band_color() -> Color:
	var c := _trim
	if absf(c.get_luminance() - _linen.get_luminance()) < 0.06:
		c = _linen.darkened(0.2)
	return c

## The tunic's girth at height v (0 at the belt, 1 at the neck): (half-width, half-depth)
static func _tunic_girth(v: float) -> Vector2:
	return Vector2(0.300 + 0.054 * smoothstep(0.18, 0.72, v) - 0.140 * smoothstep(0.78, 1.0, v),
		0.210 + 0.027 * smoothstep(0.20, 0.65, v) - 0.063 * smoothstep(0.80, 1.0, v))

## Open vest (the overseer's, the governor's): a woollen coat over the tunic, open down the
## front so the linen shows, armholes for the sleeves, its skirts falling with the tunic's.
## Every edge is bound in a darker braid
func _vest(cloth: Color) -> void:
	const GAP := 0.30          # half the front opening, in radians round the body
	const OVER := 0.010        # stands this far off the tunic
	var torso: Node3D = _rig._torso
	var braid := cloth.darkened(0.32)
	var angle := func(u: float) -> float: return PI * 0.5 + GAP + u * (TAU - GAP * 2.0)
	_part(torso, _open_surface("vest", 12, 36, func(u: float, v: float) -> Vector3:
		var a: float = angle.call(u)
		var g := _tunic_girth(v * 0.9)
		var y := 0.17 + v * 0.9 * 0.38
		return Vector3(cos(a) * (g.x + OVER), y, sin(a) * (g.y + OVER))
	), cloth, Vector3.ZERO, 8.0)
	var skirt: Node3D = _rig._skirt
	var hem_y := _hem * 0.62
	var flare := _flare
	_part(skirt, _open_surface(("vest_skirt_long" if _long else "vest_skirt") + _g, 10, 36, func(u: float, v: float) -> Vector3:
		var a: float = angle.call(u)
		var y := lerpf(hem_y, 0.19, v)
		var t := clampf((0.217 - y) / (0.217 - _hem), 0.0, 1.0)
		var r := lerpf(0.300, flare, pow(t, 1.0 / 0.85)) + OVER + 0.004
		return Vector3(cos(a) * r, y - 0.2, sin(a) * (r * 0.72 + 0.006))
	), cloth, Vector3.ZERO, 8.0)
	# The braid: down each front edge from the shoulder to the hem, and round the hem
	for side: float in [-1.0, 1.0]:
		var a := PI * 0.5 - side * GAP
		var up: Array[Vector3] = []
		for i in 9:
			var v := i / 8.0
			var g := _tunic_girth(v * 0.9)
			up.append(Vector3(cos(a) * (g.x + OVER + 0.003), 0.17 + v * 0.9 * 0.38, sin(a) * (g.y + OVER + 0.003)))
		_part(torso, _tube("vest_edge%s" % side, up, 0.012, 6), braid, Vector3.ZERO, 2.0)
		var down: Array[Vector3] = []
		for i in 7:
			var y := lerpf(0.19, hem_y, i / 6.0)
			var t := clampf((0.217 - y) / (0.217 - _hem), 0.0, 1.0)
			var r := lerpf(0.300, flare, pow(t, 1.0 / 0.85)) + OVER + 0.007
			down.append(Vector3(cos(a) * r, y - 0.2, sin(a) * (r * 0.72 + 0.006)))
		_part(skirt, _tube("vest_skirt_edge%s%s%s" % [side, _long, _g], down, 0.012, 6), braid, Vector3.ZERO, 2.0)
	var hem: Array[Vector3] = []
	for i in 41:
		var a: float = angle.call(i / 40.0)
		var t := clampf((0.217 - hem_y) / (0.217 - _hem), 0.0, 1.0)
		var r := lerpf(0.300, flare, pow(t, 1.0 / 0.85)) + OVER + 0.007
		hem.append(Vector3(cos(a) * r, hem_y - 0.2, sin(a) * (r * 0.72 + 0.006)))
	_part(skirt, _tube("vest_hem%s%s" % [_long, _g], hem, 0.012, 6), braid, Vector3.ZERO, 2.0)

## A foe's corselet: rows of small bronze-and-leather scales on a leather backing from the
## shoulders to the hips, its lower edge cut straight, a collar of leather at the neck
func _corselet(metal: Color) -> void:
	var torso: Node3D = _rig._torso
	_part(torso, _surface("corselet", 14, 40, func(u: float, v: float) -> Vector3:
		var a := u * TAU
		var g := _tunic_girth(v * 0.93)
		var y := 0.10 + v * 0.93 * 0.48
		if y < 0.2:
			g = _tunic_girth(0.0) + Vector2(0.02, 0.02) * (0.2 - y) / 0.1
		return Vector3(cos(a) * (g.x + 0.008), y, sin(a) * (g.y + 0.008))
	), metal, Vector3.ZERO, 7.0)
	var rim: Array[Vector3] = []
	for i in 49:
		var a := TAU * i / 48.0
		var g := _tunic_girth(0.0) + Vector2(0.02, 0.02)
		rim.append(Vector3(cos(a) * (g.x + 0.018), 0.10, sin(a) * (g.y + 0.018)))
	_part(torso, _tube("corselet_rim", rim, 0.014, 6), metal.darkened(0.35), Vector3.ZERO, 2.0)
	var collar: Array[Vector3] = []
	for i in 41:
		var a := TAU * i / 40.0
		var g := _tunic_girth(0.93)
		collar.append(Vector3(cos(a) * (g.x + 0.02), 0.10 + 0.93 * 0.48, sin(a) * (g.y + 0.02)))
	_part(torso, _tube("corselet_collar", collar, 0.02, 6), LEATHER, Vector3.ZERO, 2.0)

## A cloak pinned at the throat, falling down the back from a gathered fold over the
## shoulders. The pivot is the rig's cape, so it streams behind a run
func _cloak(cloth: Color) -> void:
	var torso: Node3D = _rig._torso
	_rig._cape = _rig._pivot(torso, Vector3(0, 0.56, -0.22))
	_part(_rig._cape, _open_surface("cloak", 10, 18, func(u: float, v: float) -> Vector3:
		var x := (0.5 - u) * lerpf(0.58, 0.74, v)
		# Bent round the back, with deep vertical folds toward the hem
		var curve := (x * x) * 1.2
		var fold := sin(u * PI * 5.0) * 0.022 * v
		return Vector3(x, -v * 0.78, -0.03 + curve + fold)
	), cloth, Vector3.ZERO, 8.0)
	# The inner face, a shade darker, so the cloak has a back as well as a front
	_part(_rig._cape, _open_surface("cloak_lining", 10, 18, func(u: float, v: float) -> Vector3:
		var x := (u - 0.5) * lerpf(0.58, 0.74, v)
		var curve := (x * x) * 1.2
		var fold := sin((1.0 - u) * PI * 5.0) * 0.022 * v
		return Vector3(x, -v * 0.78, -0.022 + curve + fold)
	), cloth.darkened(0.25), Vector3.ZERO, 8.0)
	_part(torso, _rig._ellipsoid(Vector3(0.62, 0.12, 0.44)), cloth.darkened(0.06), Vector3(0, 0.555, -0.03), 8.0)
	_oval(torso, Vector3(0.07, 0.07, 0.04), BRONZE.lightened(0.15), Vector3(0, 0.53, 0.205), 6.0)

static func _open_surface(key: String, rows: int, segments: int, point: Callable) -> Mesh:
	if _cache.has(key):
		return _cache[key]
	var vertices := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	var cols := segments + 1
	for i in rows + 1:
		for j in cols:
			var tex := Vector2(float(j) / segments, float(i) / rows)
			vertices.append(point.call(tex.x, tex.y))
			uv.append(tex)
			if i < rows and j < segments:
				var k := i * cols + j
				indices.append_array(PackedInt32Array([k, k + 1, k + cols, k + 1, k + 1 + cols, k + cols]))
	_cache[key] = _mesh(vertices, indices, uv)
	return _cache[key]

func _leatherwork() -> void:
	var torso: Node3D = _rig._torso
	_part(torso, _surface("belt", 4, 48, func(u: float, v: float) -> Vector3:
		var a := u * TAU
		return Vector3(cos(a) * (0.317 + sin(v * PI) * 0.005), 0.182 + v * 0.109 + 0.008 * cos(a + 0.5), sin(a) * (0.23 + sin(v * PI) * 0.005))
	), _belt, Vector3.ZERO, 2.0)
	for edge in 3:
		var points: Array[Vector3] = []
		for i in 65:
			var a := TAU * i / 64.0
			points.append(Vector3(cos(a) * 0.320, 0.191 + edge * 0.044 + 0.008 * cos(a + 0.5), sin(a) * 0.235))
		_part(torso, _tube("belt_edge%s" % edge, points, 0.0035, 6), EDGE.darkened(0.1), Vector3.ZERO, 2.0)
	if _gear:
		_ribbon(torso, "cross_strap", [Vector3(0.26, 0.562, 0.16), Vector3(0.20, 0.52, 0.31), Vector3(-0.105, 0.36, 0.31), Vector3(-0.22, 0.245, 0.205)], 0.074, 0.013, LEATHER, 2.0)
	for edge: float in ([-1.0, 1.0] if _gear else []):
		var offset := Vector3(edge * 0.022, edge * 0.019, 0.009)
		_ribbon(torso, "strap_piping%s" % edge, [Vector3(0.26, 0.562, 0.16) + offset, Vector3(0.20, 0.52, 0.31) + offset, Vector3(-0.105, 0.36, 0.31) + offset, Vector3(-0.22, 0.245, 0.205) + offset], 0.004, 0.003, EDGE, 2.0)
	# A rectangular buckle with a real open centre and a separate tongue.
	_soft(torso, Vector3(0.086, 0.080, 0.020), LEATHER.darkened(0.15), Vector3(0.053, 0.235, 0.241))
	for side: float in [-1.0, 1.0]:
		_soft(torso, Vector3(0.012, 0.082, 0.022), BRONZE, Vector3(0.053 + side * 0.046, 0.235, 0.258), 6.0)
		_soft(torso, Vector3(0.101, 0.012, 0.022), BRONZE, Vector3(0.053, 0.235 + side * 0.035, 0.258), 6.0)
	_soft(torso, Vector3(0.068, 0.008, 0.016), BRONZE, Vector3(0.065, 0.238, 0.272), 6.0)
	_ribbon(torso, "belt_tail", [Vector3(0.09, 0.23, 0.258), Vector3(0.115, 0.16, 0.27), Vector3(0.10, 0.035, 0.283), Vector3(0.13, -0.045, 0.274)], 0.065, 0.014, _belt, 2.0)
	for i in 3:
		_oval(torso, Vector3(0.010, 0.013, 0.006), LEATHER.darkened(0.50), Vector3(0.11, 0.14 - i * 0.045, 0.284), 2.0)
	for side: float in ([-1.0, 1.0] if _gear else []):
		var pouch: Node3D = _rig._pivot(torso, Vector3(side * 0.285, 0.075, -0.12))
		pouch.rotation.z = side * -0.08
		_soft(pouch, Vector3(0.15, 0.19, 0.13), LEATHER.lightened(0.035), Vector3.ZERO)
		_soft(pouch, Vector3(0.16, 0.087, 0.045), LEATHER, Vector3(0, 0.066, 0.062))
		_soft(pouch, Vector3(0.028, 0.097, 0.016), EDGE.darkened(0.15), Vector3(0, 0.041, 0.088))
		_oval(pouch, Vector3(0.018, 0.018, 0.010), BRONZE, Vector3(0, 0.015, 0.1), 6.0)
		for stitch in 5:
			_soft(pouch, Vector3(0.007, 0.003, 0.004), EDGE, Vector3(-0.06 + stitch * 0.03, 0.036, 0.086))
		_ribbon(torso, "shoulder_harness%s" % side, [Vector3(side * 0.19, 0.44, 0.18), Vector3(side * 0.21, 0.68, 0.07), Vector3(side * 0.21, 0.62, -0.21), Vector3(side * 0.21, 0.30, -0.272)], 0.051, 0.012, LEATHER, 2.0, Vector3(side, 0, 0))

func _arm(arm: Node3D, side: float, sleeve_cloth := false) -> Node3D:
	# Short sleeves close over the upper arm, falling in a soft fold (not puffed)
	_part(arm, _loft("sleeve", [Vector4(-0.175, 0.100, 0.102, 0), Vector4(-0.10, 0.110, 0.108, 0), Vector4(-0.01, 0.110, 0.108, 0), Vector4(0.055, 0.060, 0.070, 0)], 0.005), _linen, Vector3.ZERO, 1.0)
	_part(arm, _loft("cuff", [Vector4(-0.192, 0.103, 0.105, 0), Vector4(-0.178, 0.109, 0.110, 0), Vector4(-0.139, 0.109, 0.110, 0), Vector4(-0.13, 0.103, 0.105, 0)], 0.002), _linen.darkened(0.05), Vector3.ZERO, 1.0)
	_part(arm, _loft("forearm", [Vector4(-0.408, 0.060, 0.061, 0.008), Vector4(-0.36, 0.071, 0.070, 0.004), Vector4(-0.27, 0.092, 0.078, 0), Vector4(-0.215, 0.087, 0.079, 0), Vector4(-0.17, 0.091, 0.084, 0)], 0.0), _linen.darkened(0.04) if sleeve_cloth else _skin)
	# The elbow: a ball at the joint so a bent arm has no gap, the point of it behind
	var forearm := _linen.darkened(0.04) if sleeve_cloth else _skin
	_oval(arm, Vector3(0.16, 0.16, 0.16), forearm, Vector3(0, ELBOW_Y + 0.002, 0))
	_oval(arm, Vector3(0.10, 0.10, 0.04), forearm, Vector3(0, -0.244, -0.064))
	var hand: Node3D = _rig._pivot(arm, Vector3(0, -0.425, 0.005))
	# The fist drawn smaller on its own pivot, so what the hand holds keeps its size
	var fist: Node3D = _rig._pivot(hand, Vector3.ZERO)
	fist.scale = Vector3.ONE * 0.8
	_soft(fist, Vector3(0.166, 0.154, 0.135), _skin, Vector3(0, -0.018, 0), 0.0)
	for finger in 4:
		var x := -0.059 + finger * 0.039
		var y := -0.039 - absf(finger - 1.5) * 0.006
		_oval(fist, Vector3(0.043, 0.089, 0.077), _skin, Vector3(x, y, 0.058))
		_oval(fist, Vector3(0.030, 0.028, 0.024), _skin.lightened(0.03), Vector3(x, y + 0.022, 0.087))
	_oval(fist, Vector3(0.071, 0.11, 0.072), _skin, Vector3(side * -0.079, 0.005, 0.023), 0.0, Vector3(0.2, 0, side * -0.42))
	return hand

func _leg(leg: Node3D, side: float) -> void:
	# In two lengths that meet under the kneecap, so the knee can bend (_joint_leg)
	_part(leg, _loft("thigh", [Vector4(-0.155, 0.082, 0.087, 0.014), Vector4(-0.12, 0.083, 0.087, 0.014), Vector4(-0.07, 0.089, 0.084, 0.010), Vector4(0.015, 0.087, 0.083, 0)], 0.0), _skin)
	_part(leg, _loft("shin", [Vector4(-0.285, 0.065, 0.063, 0), Vector4(-0.22, 0.075, 0.075, 0), Vector4(-0.15, 0.081, 0.087, 0.015), Vector4(-0.105, 0.081, 0.086, 0.015)], 0.0), _skin)
	_oval(leg, Vector3(0.123, 0.092, 0.075), _skin.lightened(0.02), Vector3(0, -0.135, 0.066))
	_soft(leg, Vector3(0.20, 0.045, 0.31), LEATHER.darkened(0.44), Vector3(0, -HIP + 0.025, 0.051))
	_soft(leg, Vector3(0.19, 0.020, 0.30), EDGE.darkened(0.28), Vector3(0, -HIP + 0.049, 0.052))
	_oval(leg, Vector3(0.165, 0.10, 0.25), _skin, Vector3(0, -HIP + 0.095, 0.05))
	for i in 5:
		var diameter := 0.038 - i * 0.003
		var x := side * (-0.062 + i * 0.031)
		_oval(leg, Vector3(diameter, 0.04, 0.056 - i * 0.004), _skin, Vector3(x, -HIP + 0.078, 0.163 - i * 0.003))
	_ribbon(leg, "toe_strap", [Vector3(-0.097, -0.295, 0.080), Vector3(-0.08, -0.22, 0.07), Vector3(0.08, -0.22, 0.07), Vector3(0.097, -0.295, 0.080)], 0.067, 0.014, LEATHER, 2.0, Vector3.UP)
	_ribbon(leg, "instep_strap", [Vector3(-0.098, -0.292, 0.014), Vector3(-0.065, -0.212, 0.003), Vector3(0.065, -0.212, -0.017), Vector3(0.095, -0.292, -0.035)], 0.052, 0.014, LEATHER, 2.0, Vector3.UP)
	_part(leg, _loft("ankle_strap", [Vector4(-0.231, 0.080, 0.079, 0), Vector4(-0.22, 0.089, 0.085, 0), Vector4(-0.172, 0.089, 0.088, 0), Vector4(-0.166, 0.079, 0.080, 0)], 0), LEATHER)
	_oval(leg, Vector3(0.012, 0.024, 0.024), BRONZE, Vector3(side * 0.092, -0.193, 0.025), 6.0)

## Hang the leg below the knee on a knee pivot, and the foot below the ankle on an ankle
## pivot under it, keeping every part where it was (the rig bends them: CharacterRig)
func _joint_leg(leg: Node3D) -> void:
	var knee: Node3D = _rig._pivot(leg, Vector3(0, KNEE_Y, 0))
	var ankle: Node3D = _rig._pivot(knee, Vector3(0, ANKLE_Y - KNEE_Y, 0))
	for c: Node in leg.get_children():
		var n := c as Node3D
		if n == null or n == knee:
			continue
		var top := n.position.y
		var mid := n.position.y
		if n is MeshInstance3D:
			var box: AABB = (n as MeshInstance3D).mesh.get_aabb()
			top = n.position.y + box.end.y * n.scale.y
			mid = n.position.y + box.get_center().y * n.scale.y
		if top <= ANKLE_Y + 0.002:
			n.reparent(ankle, false)
			n.position.y -= ANKLE_Y
		elif mid < KNEE_Y:
			n.reparent(knee, false)
			n.position.y -= KNEE_Y
	_rig._knees.append(knee)
	_rig._ankles.append(ankle)

## Hang the forearm and hand on an elbow pivot
func _joint_arm(arm: Node3D) -> void:
	var elbow: Node3D = _rig._pivot(arm, Vector3(0, ELBOW_Y, 0))
	for c: Node in arm.get_children():
		var n := c as Node3D
		if n == null or n == elbow:
			continue
		var mid := n.position.y
		if n is MeshInstance3D:
			mid = n.position.y + (n as MeshInstance3D).mesh.get_aabb().get_center().y * n.scale.y
		if mid < ELBOW_Y:
			n.reparent(elbow, false)
			n.position.y -= ELBOW_Y
	_rig._elbows.append(elbow)

func _basket(stones: bool) -> void:
	var basket: Node3D = _rig._pivot(_rig._torso, Vector3(0, 0.43, -0.40))
	basket.rotation.x = -0.10
	_part(basket, _loft("basket_core", [Vector4(-0.25, 0.21, 0.125, 0), Vector4(-0.17, 0.25, 0.16, 0), Vector4(0.07, 0.305, 0.196, 0), Vector4(0.24, 0.325, 0.211, 0)], 0), Color(0.36, 0.21, 0.09), Vector3.ZERO, 3.0)
	_part(basket, _weave(false), Color(0.64, 0.39, 0.16), Vector3.ZERO, 3.0)
	_part(basket, _weave(true), Color(0.75, 0.48, 0.21), Vector3.ZERO, 3.0)
	for braid in 2:
		var rim: Array[Vector3] = []
		for i in 193:
			var a := TAU * i / 192.0
			var phase := a * 28 + braid * PI
			rim.append(Vector3(cos(a) * (0.331 + cos(phase) * 0.010), 0.246 + sin(phase) * 0.010, sin(a) * (0.219 + cos(phase) * 0.010)))
		_part(basket, _tube("rim%s" % braid, rim, 0.017, 8), Color(0.78, 0.53, 0.25).darkened(braid * 0.06), Vector3.ZERO, 3.0)
	if stones:
		var rubble := [Vector4(-0.20, 0.27, -0.015, 0.16), Vector4(0.01, 0.285, 0.055, 0.19), Vector4(0.18, 0.275, -0.015, 0.17), Vector4(-0.09, 0.37, -0.015, 0.17), Vector4(0.09, 0.39, 0.015, 0.15), Vector4(-0.22, 0.30, 0.09, 0.12)]
		for i in rubble.size():
			var rock: Vector4 = rubble[i]
			_part(basket, _rig._bbox(Vector3(rock.w, rock.w * 0.85, rock.w * 0.83), 0.025), Color(0.55, 0.53, 0.52).lightened((i % 3) * 0.06), Vector3(rock.x, rock.y, rock.z), 4.0, Vector3(i * 0.21, i * 0.71, 0.2))

# Elliptical loft, smooth interpolation between anatomical/clothing cross sections.
# Vector4 = height, radius X, radius Z, centre Z.
static func _loft(key: String, rings: Array, folds: float) -> Mesh:
	return _surface(key, (rings.size() - 1) * 4, 28, func(u: float, v: float) -> Vector3:
		var f := v * (rings.size() - 1)
		var i := mini(int(f), rings.size() - 2)
		var t := f - i
		var a: Vector4 = rings[maxi(0, i - 1)]
		var b: Vector4 = rings[i]
		var c: Vector4 = rings[i + 1]
		var d: Vector4 = rings[mini(rings.size() - 1, i + 2)]
		var r := (2.0 * b + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t * t + (-a + 3.0 * b - 3.0 * c + d) * t * t * t) * 0.5
		var angle := u * TAU
		var crease := sin(angle * 7 + v * 3) * folds
		return Vector3(cos(angle) * (r.y + crease), r.x, sin(angle) * (r.z + crease) + r.w)
	)

static func _surface(key: String, rows: int, segments: int, point: Callable) -> Mesh:
	if _cache.has(key):
		return _cache[key]
	var vertices := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in rows + 1:
		for j in segments:
			var tex := Vector2(float(j) / segments, float(i) / rows)
			vertices.append(point.call(tex.x, tex.y))
			uv.append(tex)
			if i < rows:
				var k := i * segments + j
				var next := i * segments + (j + 1) % segments
				indices.append_array(PackedInt32Array([k, next, k + segments, next, next + segments, k + segments]))
	_cache[key] = _mesh(vertices, indices, uv)
	return _cache[key]

func _ribbon(parent: Node3D, key: String, points: Array, width: float, thickness: float, color: Color, kind: float, outward := Vector3.BACK) -> void:
	if not _cache.has(key):
		var vertices := PackedVector3Array()
		var uv := PackedVector2Array()
		var indices := PackedInt32Array()
		const SIDES := 12
		const STEPS := 24
		for i in STEPS + 1:
			var t := float(i) / STEPS
			var p: Vector3 = points[0].bezier_interpolate(points[1], points[2], points[3], t)
			var tangent: Vector3 = points[0].bezier_derivative(points[1], points[2], points[3], t).normalized()
			var side := tangent.cross(outward).normalized()
			var normal := side.cross(tangent).normalized()
			for j in SIDES:
				var a := j * TAU / SIDES
				vertices.append(p + side * cos(a) * width * 0.5 + normal * sin(a) * thickness * 0.5)
				uv.append(Vector2(float(j) / SIDES, t))
				if i < STEPS:
					var k := i * SIDES + j
					var next := i * SIDES + (j + 1) % SIDES
					indices.append_array(PackedInt32Array([k, next, k + SIDES, next, next + SIDES, k + SIDES]))
		_cache[key] = _mesh(vertices, indices, uv)
	_part(parent, _cache[key], color, Vector3.ZERO, kind)

static func _tube(key: String, points: Array[Vector3], radius: float, sides: int) -> Mesh:
	if _cache.has(key):
		return _cache[key]
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var uv := PackedVector2Array()
	_append_tube(vertices, indices, uv, points, radius, sides)
	_cache[key] = _mesh(vertices, indices, uv)
	return _cache[key]

static func _append_tube(vertices: PackedVector3Array, indices: PackedInt32Array, uv: PackedVector2Array, points: Array[Vector3], radius: float, sides: int) -> void:
	var start := vertices.size()
	for i in points.size():
		var tangent := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		var across := tangent.cross(Vector3.UP).normalized()
		if across.length_squared() < 0.1:
			across = tangent.cross(Vector3.RIGHT).normalized()
		var normal := across.cross(tangent).normalized()
		for j in sides:
			var a := j * TAU / sides
			vertices.append(points[i] + (across * cos(a) + normal * sin(a)) * radius)
			uv.append(Vector2(float(j) / sides, float(i) / (points.size() - 1)))
			if i < points.size() - 1:
				var k := start + i * sides + j
				var next := start + i * sides + (j + 1) % sides
				indices.append_array(PackedInt32Array([k, next, k + sides, next, next + sides, k + sides]))

static func _weave(vertical: bool) -> Mesh:
	var key := "weave%s" % vertical
	if _cache.has(key):
		return _cache[key]
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var uv := PackedVector2Array()
	for row in (24 if vertical else 9):
		var points: Array[Vector3] = []
		var count := 48 if vertical else 96
		for i in count + 1:
			var t := float(i) / count if vertical else row / 8.0
			var a := row * TAU / 24 if vertical else i * TAU / count
			var radius := lerpf(0.215, 0.325, pow(t, 0.7))
			var depth := lerpf(0.131, 0.211, pow(t, 0.7))
			var over := 0.005 * cos(t * TAU * 8 + a * 12) * (1 if vertical else -1)
			points.append(Vector3(cos(a) * (radius + over), -0.235 + t * 0.46, sin(a) * (depth + over)))
		_append_tube(vertices, indices, uv, points, 0.010 if vertical else 0.017, 6)
	_cache[key] = _mesh(vertices, indices, uv)
	return _cache[key]

static func _mesh(vertices: PackedVector3Array, indices: PackedInt32Array, uv: PackedVector2Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var surface := SurfaceTool.new()
	surface.create_from(mesh, 0)
	surface.generate_normals()
	return surface.commit()
