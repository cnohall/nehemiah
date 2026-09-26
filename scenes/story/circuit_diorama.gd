class_name CircuitDiorama
extends Node3D

# Jerusalem as a small low-poly diorama for the circuit map (CircuitMap renders it in a
# SubViewport and lays the labels over it). Everything is built in code from the gate
# positions: terrain with the Kidron and Hinnom valleys, the wall ring cut into its 12
# sections (Nehemiah 3), a whitewashed city, the temple, olive trees on the slopes.
# Each section has a standing mesh (rises along its length via `reveal`), a rubble mesh
# and a glow strip on the ground. Colours are sRGB like the game world (vertex colours).

# Gate positions in a unit square (north up = -z), after the usual reconstructions:
# temple mount north-east, the City of David ridge running south, the western hill held
# by the Broad Wall. One per section, in GameState.SECTIONS order; each section's stretch
# runs from its gate to the next one.
const GATES := [
	Vector2(0.70, 0.13),   # Sheep Gate — north-east, by the temple
	Vector2(0.50, 0.10),   # Fish Gate — north
	Vector2(0.30, 0.16),   # Jeshanah (Old City) Gate — north-west
	Vector2(0.18, 0.33),   # Broad Wall — west
	Vector2(0.21, 0.52),   # Tower of Ovens
	Vector2(0.36, 0.70),   # Valley Gate — south-west, on the Tyropoeon
	Vector2(0.52, 0.93),   # Dung Gate — the southern tip
	Vector2(0.62, 0.80),   # Fountain Gate — by the Pool of Shelah
	Vector2(0.68, 0.58),   # Water Gate — Ophel
	Vector2(0.76, 0.42),   # Horse Gate
	Vector2(0.80, 0.30),   # East Gate
	Vector2(0.79, 0.19),   # Inspection (Miphkad) Gate
]
const KIDRON := [Vector2(0.88, -0.2), Vector2(0.89, 0.25), Vector2(0.82, 0.55), Vector2(0.71, 0.86), Vector2(0.56, 1.02), Vector2(0.5, 1.3)]
const HINNOM := [Vector2(0.02, 0.15), Vector2(0.06, 0.55), Vector2(0.24, 0.87), Vector2(0.53, 1.03)]
# The Tyropoeon, the shallow valley through the city between the western hill and Ophel
const TYROPOEON := [Vector2(0.44, 0.12), Vector2(0.47, 0.45), Vector2(0.53, 0.88)]
# Streets kept clear of houses: north–south, east–west, and Valley Gate up to the temple
const STREETS := [
	[Vector2(0.48, 0.12), Vector2(0.50, 0.55), Vector2(0.53, 0.9)],
	[Vector2(0.20, 0.46), Vector2(0.50, 0.44), Vector2(0.74, 0.47)],
	[Vector2(0.36, 0.70), Vector2(0.50, 0.50), Vector2(0.60, 0.27)],
]
const POOL := Vector2(0.595, 0.82)        # Pool of Shelah (Neh. 3:15), by the King's Garden
const TEMPLE := Rect2(0.57, 0.15, 0.13, 0.11)

const W := 44.0            # world size of the unit square
const CENTER := Vector2(0.5, 0.52)
const EDGE := 0.66         # unit radius of the city's own land; beyond it, rolling hills into the haze
const WALL_H := 2.0
const WALL_T := 1.1
const TOWER := Vector3(2.2, 3.2, 2.2)
const SEG := 0.75          # wall segment length (world)
const CAM_DIST := 104.0

const EARTH      := Color(0.80, 0.57, 0.32)
const EARTH_HIGH := Color(0.88, 0.71, 0.46)
const ROCK       := Color(0.62, 0.49, 0.37)
const FAR_HILLS  := Color(0.74, 0.60, 0.44)
const VALLEY     := Color(0.43, 0.49, 0.25)
const STONE      := Color(0.97, 0.93, 0.85)   # the wall: the brightest thing on the land
const STONE_DARK := Color(0.82, 0.75, 0.63)
const RUBBLE     := Color(0.60, 0.50, 0.39)
const CHAR       := Color(0.20, 0.16, 0.13)   # "its gates have been burned with fire" (Neh. 1:3)
const HOUSE      := Color(0.90, 0.86, 0.78)
const MUDBRICK   := Color(0.80, 0.65, 0.47)
const OLIVE_TREE := Color(0.47, 0.53, 0.33)   # silvery olive green
const CYPRESS    := Color(0.20, 0.30, 0.16)
const TRUNK      := Color(0.34, 0.25, 0.17)
const WATER      := Color(0.24, 0.44, 0.52)
const ROOF_RUGS  := [Color(0.70, 0.30, 0.14), Color(0.22, 0.30, 0.55), Color(0.27, 0.52, 0.50), Color(0.78, 0.58, 0.18)]
const GLOW       := Color(1.0, 0.72, 0.30)

const WALL_SHADER := """
shader_type spatial;
render_mode cull_disabled;
// Standing wall: vertex colours are sRGB; UV2 = (position along the section 0..1, base
// height). Vertices beyond `reveal` sink to the base, so the wall rises along its length.
uniform float reveal = 1.0;
uniform vec3 glow : source_color = vec3(1.0, 0.72, 0.3);
uniform float glow_amount = 0.0;
vec3 to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}
void vertex() {
	float k = smoothstep(UV2.x - 0.05, UV2.x + 0.001, reveal);
	VERTEX.y = mix(UV2.y - 0.05, VERTEX.y, k);
}
void fragment() {
	ALBEDO = to_linear(COLOR.rgb);
	ROUGHNESS = 0.92;
	EMISSION = glow * glow_amount;
}
"""
const STRIP_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 color : source_color = vec3(1.0, 0.72, 0.3);
uniform float strength = 0.0;
void fragment() {
	float e = 1.0 - abs(UV.y * 2.0 - 1.0);
	ALBEDO = color;
	ALPHA = e * e * strength;
}
"""

var camera: Camera3D
var _sun: DirectionalLight3D
var _env: Environment
var _torch: OmniLight3D
var _flame: MeshInstance3D
var _standing: Array[MeshInstance3D] = []
var _rubble: Array[MeshInstance3D] = []
var _strips: Array[MeshInstance3D] = []
var _noise := FastNoiseLite.new()
var _focus := Vector3.ZERO
var _focus_goal := Vector3.ZERO
var _time := 0.0
var _night := false

func _ready() -> void:
	_noise.seed = 445
	_noise.frequency = 3.2
	_build_light()
	_build_terrain()
	_build_city()
	_build_trees()
	for i in GATES.size():
		_build_section(i)
	_focus = unit_to_world(CENTER, 0.0) * Vector3(1, 0, 1)
	_focus_goal = _focus
	_place_camera(0.0)

func _process(delta: float) -> void:
	_time += delta
	_focus = _focus.lerp(_focus_goal, minf(1.0, delta * 2.5))
	_place_camera(_time)
	if _torch.visible:
		var f := 0.85 + 0.15 * sin(_time * 17.0) * sin(_time * 7.3)
		_torch.light_energy = 4.0 * f

# ── State (CircuitMap drives these) ────────────────────────

func set_section(i: int, standing: bool, reveal := 1.0) -> void:
	_standing[i].visible = standing
	_rubble[i].visible = not standing or reveal < 1.0
	(_standing[i].material_override as ShaderMaterial).set_shader_parameter("reveal", reveal)

## 0..1 glow along a section (the current or selected one); pulses are the caller's
func set_glow(i: int, amount: float) -> void:
	(_strips[i].material_override as ShaderMaterial).set_shader_parameter("strength", amount)
	(_standing[i].material_override as ShaderMaterial).set_shader_parameter("glow_amount", amount * 0.35)

func set_night(on: bool) -> void:
	_night = on
	# Day: warm sun, cool blue-violet shade (the art direction's hue contrast)
	_sun.light_color = Color(0.55, 0.62, 0.95) if on else Color(1.0, 0.82, 0.6)
	_sun.light_energy = 0.3 if on else 1.55
	_env.ambient_light_color = Color(0.22, 0.26, 0.42) if on else Color(0.56, 0.60, 0.80)
	_env.ambient_light_energy = 0.4 if on else 0.6
	_env.fog_light_color = Color(0.09, 0.10, 0.16) if on else Color(0.80, 0.67, 0.52)
	_env.background_color = _env.fog_light_color
	if not on:
		set_torch(-1.0)

## Torch at ring position t (fractional gate index); t < 0 hides it
func set_torch(t: float) -> void:
	_torch.visible = t >= 0.0
	_flame.visible = _torch.visible
	if t >= 0.0:
		var p := ring_world(t, WALL_H + 0.6)
		_torch.position = p + Vector3(0, 0.6, 0)
		_flame.position = p

## Ease the camera toward a point on the ring (fractional gate index), or back to centre
func focus_on(t: float) -> void:
	var c := unit_to_world(CENTER, 0.0) * Vector3(1, 0, 1)
	if t < 0.0:
		_focus_goal = c
	else:
		_focus_goal = c.lerp(ring_world(t, 0.0) * Vector3(1, 0, 1), 0.22)

# ── Geometry ───────────────────────────────────────────────

func unit_to_world(u: Vector2, lift := 0.0) -> Vector3:
	return Vector3((u.x - 0.5) * W, height(u) + lift, (u.y - 0.5) * W)

## Point on the ring in unit space at fractional gate index t (wraps). Catmull-Rom
## through the gates so the wall bends like masonry laid along a hill.
static func ring_unit(t: float) -> Vector2:
	var n := GATES.size()
	t = fposmod(t, n)
	var i := int(t)
	var u := t - i
	var p0: Vector2 = GATES[(i - 1 + n) % n]
	var p1: Vector2 = GATES[i]
	var p2: Vector2 = GATES[(i + 1) % n]
	var p3: Vector2 = GATES[(i + 2) % n]
	var u2 := u * u
	var u3 := u2 * u
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3)

func ring_world(t: float, lift := 0.0) -> Vector3:
	return unit_to_world(ring_unit(t), lift)

## Ground height at a unit-space point: plateau, two hills, three valleys, the Mount of
## Olives to the east, a little noise; sinks away past the diorama's edge
func height(u: Vector2) -> float:
	var y := 1.6
	y += 1.6 * _gauss(u, Vector2(0.63, 0.21), 0.12)     # temple mount
	y += 0.7 * _gauss(u, Vector2(0.62, 0.55), 0.09)     # Ophel ridge
	y += 1.4 * _gauss(u, Vector2(0.30, 0.40), 0.15)     # western hill
	y -= 0.9 * _trench(_poly_dist(u, TYROPOEON), 0.05)
	y -= 4.6 * _trench(_poly_dist(u, KIDRON), 0.07)
	y -= 3.6 * _trench(_poly_dist(u, HINNOM), 0.065)
	y += 7.0 * smoothstep(0.92, 1.28, u.x)              # Mount of Olives
	y += 0.3 * _noise.get_noise_2d(u.x, u.y)
	var r := u.distance_to(CENTER)
	y += 3.0 * smoothstep(EDGE - 0.04, 1.2, r) * (0.55 + 0.45 * _noise.get_noise_2d(u.x * 0.35 + 3.0, u.y * 0.35))
	return y

func _gauss(u: Vector2, c: Vector2, s: float) -> float:
	return exp(-u.distance_squared_to(c) / (2.0 * s * s))

func _trench(d: float, w: float) -> float:
	return exp(-(d / w) * (d / w))

func _poly_dist(u: Vector2, poly: Array) -> float:
	var best := INF
	for k in poly.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(u, poly[k], poly[k + 1])
		best = minf(best, u.distance_to(q))
	return best

func _ring_polygon(per_gate := 6) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in GATES.size() * per_gate:
		pts.append(ring_unit(k / float(per_gate)))
	return pts

# ── Build ──────────────────────────────────────────────────

func _build_light() -> void:
	_sun = DirectionalLight3D.new()
	# Late-afternoon sun from the south-west: long shadows show the relief
	_sun.rotation_degrees = Vector3(-34, -52, 0)
	_sun.shadow_enabled = true
	_sun.shadow_blur = 1.5
	_sun.directional_shadow_max_distance = 140.0
	add_child(_sun)
	_env = Environment.new()
	_env.background_mode = Environment.BG_CLEAR_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.glow_enabled = true
	_env.glow_intensity = 0.6
	_env.glow_bloom = 0.05
	_env.ssao_enabled = true
	_env.ssao_radius = 1.2
	_env.ssao_intensity = 1.6
	# Distant hills fade into a warm haze (a deep blue one at night)
	_env.fog_enabled = true
	_env.fog_mode = Environment.FOG_MODE_DEPTH
	_env.fog_density = 1.0
	_env.fog_depth_begin = 105.0
	_env.fog_depth_end = 240.0
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)

	_torch = OmniLight3D.new()
	_torch.light_color = Color(1.0, 0.62, 0.25)
	_torch.omni_range = 7.0
	_torch.shadow_enabled = false
	add_child(_torch)
	_flame = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.28
	s.height = 0.56
	_flame.mesh = s
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1.0, 0.8, 0.4)
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.6, 0.2)
	fm.emission_energy_multiplier = 4.0
	_flame.material_override = fm
	add_child(_flame)
	set_night(false)

	camera = Camera3D.new()
	camera.fov = 28.0
	camera.near = 1.0
	camera.far = 320.0
	# Tilt-shift: near and far both soften, so it reads as a model on a table
	var attr := CameraAttributesPractical.new()
	attr.dof_blur_far_enabled = true
	attr.dof_blur_far_distance = CAM_DIST + 16.0
	attr.dof_blur_far_transition = 40.0
	attr.dof_blur_near_enabled = true
	attr.dof_blur_near_distance = CAM_DIST - 26.0
	attr.dof_blur_near_transition = 18.0
	attr.dof_blur_amount = 0.07
	camera.attributes = attr
	add_child(camera)

# Seen from the south, a little east, looking down on the ring; drifts slowly
func _place_camera(t: float) -> void:
	var yaw := deg_to_rad(8.0 + 4.0 * sin(t * 0.12))
	var pitch := deg_to_rad(47.0)
	var dist := CAM_DIST
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	camera.position = _focus + Vector3(0, 1.5, 0) + dir * dist
	camera.look_at(_focus + Vector3(0, 1.5, 0), Vector3.UP)
	# Shifted so the city sits right of centre, clear of the text column on the left
	camera.h_offset = -dist * 0.105

func _build_terrain() -> void:
	var n := 200
	var span := 3.2          # unit-space width covered (−1.1 .. 2.1): land to the horizon
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var grid: Array[Vector3] = []
	var gcol: Array[Color] = []
	var gone: Array[bool] = []     # past the edge: no triangle there (the land ends in the dark)
	for zi in n + 1:
		for xi in n + 1:
			var u := Vector2(0.5 - span * 0.5 + span * xi / n, 0.52 - span * 0.5 + span * zi / n)
			var p := unit_to_world(u)
			grid.append(p)
			gone.append(u.distance_to(CENTER) > 1.55)
	# Colour needs the slope, so it waits until every height is known
	var cell := span * W / n
	for zi in n + 1:
		for xi in n + 1:
			var i := zi * (n + 1) + xi
			var dx := grid[mini(i + 1, zi * (n + 1) + n)].y - grid[maxi(i - 1, zi * (n + 1))].y
			var dz := grid[mini(i + n + 1, grid.size() - 1)].y - grid[maxi(i - n - 1, 0)].y
			var slope := Vector2(dx, dz).length() / (2.0 * cell)
			var u := Vector2(grid[i].x / W + 0.5, grid[i].z / W + 0.5)
			gcol.append(_ground_color(u, grid[i].y, slope))
	for zi in n:
		for xi in n:
			var a := zi * (n + 1) + xi
			var b := a + 1
			var c := a + n + 1
			var d := c + 1
			if gone[a] and gone[b] and gone[c] and gone[d]:
				continue
			for idx: int in [a, b, c, b, d, c]:
				verts.append(grid[idx])
				cols.append(gcol[idx])
	add_child(_mesh(verts, cols, null, _vertex_material()))

## Ochre earth, paler on the heights; bare rock on steep slopes; green valley floors;
## the far hills muted toward the haze
func _ground_color(u: Vector2, y: float, slope: float) -> Color:
	var c := EARTH.lerp(EARTH_HIGH, clampf((y - 1.4) / 2.5, 0.0, 1.0))
	c = c.lerp(ROCK, smoothstep(0.25, 0.8, slope) * 0.7)
	c = c.lerp(VALLEY, clampf((0.4 - y) / 2.5, 0.0, 1.0) * 0.9)
	c = c.lerp(FAR_HILLS, smoothstep(EDGE, 1.3, u.distance_to(CENTER)) * 0.6)
	var v := 1.0 + 0.05 * _noise.get_noise_2d(u.x * 0.8 + 11.0, u.y * 0.8)
	return Color(c.r * v, c.g * v, c.b * v)

func _build_section(i: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 52 + i
	var st := _Boxes.new()
	var rb := _Boxes.new()
	# Sample the stretch at roughly SEG spacing
	var a := ring_unit(i)
	var b := ring_unit(i + 1)
	var approx := a.distance_to(b) * W * 1.15
	var steps := maxi(3, ceili(approx / SEG))
	var pts: Array[Vector3] = []
	for k in steps + 1:
		pts.append(ring_world(i + k / float(steps)))
	for k in steps:
		var p0 := pts[k]
		var p1 := pts[k + 1]
		var mid := (p0 + p1) * 0.5
		var along := (k + 0.5) / steps
		var yaw := atan2(p1.x - p0.x, p1.z - p0.z)
		var length := Vector2(p1.x - p0.x, p1.z - p0.z).length() + 0.12
		var base := minf(p0.y, p1.y) - 0.35
		var top := maxf(p0.y, p1.y) + WALL_H
		var shade: Color = STONE.lerp(STONE_DARK, rng.randf() * 0.35)
		st.add(Vector3(mid.x, (base + top) * 0.5, mid.z), Vector3(WALL_T, top - base, length), yaw, shade, Vector2(along, base))
		if k % 2 == 0:
			st.add(Vector3(mid.x, top + 0.2, mid.z), Vector3(WALL_T * 1.02, 0.4, length * 0.5), yaw, shade, Vector2(along, base))
		# Rubble: broken stubs and fallen blocks
		if rng.randf() > 0.25:
			var h := rng.randf_range(0.0, 0.3)
			rb.add(Vector3(mid.x, base + (0.4 + h) * 0.5, mid.z), Vector3(WALL_T * 1.1, 0.4 + h, length * rng.randf_range(0.5, 0.9)),
				yaw + rng.randf_range(-0.15, 0.15), RUBBLE.lerp(CHAR, maxf(0.0, 0.7 - along * 4.0) + rng.randf() * 0.15),
				Vector2(along, base))
		for s in 2:
			var off := Vector3(rng.randf_range(-1.0, 1.0), 0, rng.randf_range(-1.0, 1.0))
			var q := mid + off
			q.y = height(Vector2(q.x / W + 0.5, q.z / W + 0.5))
			var sz := rng.randf_range(0.14, 0.3)
			rb.add(q + Vector3(0, sz * 0.4, 0), Vector3(sz, sz * 0.8, sz * 1.2), rng.randf() * TAU, RUBBLE, Vector2(along, base))
	# The gate that opens this section: a pair of towers (or one tower for a plain stretch)
	var g := pts[0]
	var dir := (pts[1] - pts[0]).normalized()
	var gyaw := atan2(dir.x, dir.z)
	var side := Vector3(dir.z, 0, -dir.x)
	var gate: bool = GameState.SECTIONS[i].get("gate", true)
	for s: float in [-1.0, 1.0] if gate else [0.0]:
		var c := g + side * s * 1.6
		var base := c.y - 0.4
		st.add(Vector3(c.x, base + TOWER.y * 0.5, c.z), TOWER, gyaw, STONE, Vector2(0.0, base))
		st.add(Vector3(c.x, base + TOWER.y + 0.2, c.z), Vector3(TOWER.x * 1.12, 0.4, TOWER.z * 1.12), gyaw, STONE_DARK, Vector2(0.0, base))
		for m in 4:
			var mo := Vector3(1 if m % 2 else -1, 0, 1 if m < 2 else -1) * TOWER.x * 0.4
			st.add(Vector3(c.x, base + TOWER.y + 0.6, c.z) + Basis(Vector3.UP, gyaw) * mo, Vector3(0.45, 0.4, 0.45), gyaw, STONE, Vector2(0.0, base))
		for m in 4:
			var off := Basis(Vector3.UP, gyaw) * Vector3(rng.randf_range(-0.7, 0.7), 0, rng.randf_range(-0.7, 0.7))
			var h := rng.randf_range(0.3, 0.75)
			rb.add(Vector3(c.x, base + 0.4 + h * 0.5, c.z) + off, Vector3(rng.randf_range(0.6, 1.0), h, rng.randf_range(0.6, 1.0)),
				gyaw + rng.randf_range(-0.4, 0.4), RUBBLE.lerp(CHAR, rng.randf_range(0.2, 0.6)), Vector2(0.0, base))
	if gate:
		# The gateway's lintel between the towers; burned doors and beams in the rubble
		var base := g.y - 0.4
		st.add(Vector3(g.x, base + TOWER.y - 0.55, g.z), Vector3(1.2, 0.8, WALL_T * 1.3), gyaw + PI * 0.5, STONE_DARK, Vector2(0.0, base))
		for k in 3:
			var q := g + side * rng.randf_range(-0.8, 0.8) + dir * rng.randf_range(-0.8, 0.8)
			rb.add(Vector3(q.x, g.y + 0.1, q.z), Vector3(0.18, 0.14, rng.randf_range(1.2, 2.0)), rng.randf() * TAU, CHAR, Vector2(0.0, base))

	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = WALL_SHADER
	mat.shader = sh
	var standing := st.instance(mat)
	add_child(standing)
	_standing.append(standing)
	var rubble := rb.instance(_vertex_material())
	add_child(rubble)
	_rubble.append(rubble)
	_strips.append(_build_strip(pts))

# A soft glowing band on the ground along the stretch
func _build_strip(pts: Array[Vector3]) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var half := 2.2
	for k in pts.size() - 1:
		var d0 := (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized()
		var d1 := (pts[mini(k + 2, pts.size() - 1)] - pts[k]).normalized()
		var n0 := Vector3(d0.z, 0, -d0.x) * half
		var n1 := Vector3(d1.z, 0, -d1.x) * half
		var a0 := _lift(pts[k] + n0)
		var b0 := _lift(pts[k] - n0)
		var a1 := _lift(pts[k + 1] + n1)
		var b1 := _lift(pts[k + 1] - n1)
		for pair: Array in [[a0, 0.0], [b0, 1.0], [a1, 0.0], [b0, 1.0], [b1, 1.0], [a1, 0.0]]:
			verts.append(pair[0])
			uvs.append(Vector2(0, pair[1]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = STRIP_SHADER
	mat.shader = sh
	mat.set_shader_parameter("color", GLOW)
	mi.material_override = mat
	add_child(mi)
	return mi

func _lift(p: Vector3) -> Vector3:
	return Vector3(p.x, height(Vector2(p.x / W + 0.5, p.z / W + 0.5)) + 0.12, p.z)

func _build_city() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 445
	var ring := _ring_polygon()
	var houses := _Boxes.new()
	var rugs := _Boxes.new()
	var step := 1.15 / W
	var y := 0.14
	while y < 0.96:
		var x := 0.12
		while x < 0.88:
			var u := Vector2(x + rng.randf_range(-0.3, 0.3) * step, y + rng.randf_range(-0.3, 0.3) * step)
			x += step
			if not Geometry2D.is_point_in_polygon(u, ring) or TEMPLE.grow(0.015).has_point(u):
				continue
			if _poly_dist(u, Array(ring) + [ring[0]]) < 0.03 or rng.randf() < 0.1 or u.distance_to(POOL) < 0.035:
				continue
			if STREETS.any(func(st: Array): return _poly_dist(u, st) < 0.011):
				continue
			var p := unit_to_world(u)
			var s := Vector3(rng.randf_range(0.5, 1.05), rng.randf_range(0.45, 0.8), rng.randf_range(0.5, 1.05))
			if rng.randf() < 0.15:
				s.y = rng.randf_range(1.05, 1.45)          # an upper room
			var yaw := deg_to_rad(8.0) + (PI * 0.5 if rng.randf() < 0.5 else 0.0) + rng.randf_range(-0.06, 0.06)
			var col := HOUSE.lerp(MUDBRICK, 0.8) if rng.randf() < 0.18 else HOUSE.lerp(STONE, rng.randf() * 0.6)
			houses.add(p + Vector3(0, s.y * 0.5 - 0.2, 0), s + Vector3(0, 0.2, 0), yaw, col, Vector2.ZERO)
			if rng.randf() < 0.25:
				# A lower wing off one side — L-shaped houses round a yard
				var wing := Basis(Vector3.UP, yaw) * Vector3(s.x * 0.75, 0, 0)
				houses.add(p + wing + Vector3(0, s.y * 0.3 - 0.2, 0), Vector3(s.x * 0.5, s.y * 0.6 + 0.2, s.z * 0.8), yaw, col.darkened(0.03), Vector2.ZERO)
			if rng.randf() < 0.16:
				rugs.add(p + Vector3(0, s.y + 0.02, 0), Vector3(s.x * 0.55, 0.05, s.z * 0.45), yaw,
					ROOF_RUGS[rng.randi() % ROOF_RUGS.size()], Vector2.ZERO)
		y += step
	# The temple: a raised court, the sanctuary facing east, the altar before it
	var tc := TEMPLE.get_center()
	var tp := unit_to_world(tc)
	var court := Vector3(TEMPLE.size.x * W, 0.9, TEMPLE.size.y * W)
	houses.add(tp + Vector3(0, 0.2, 0), court, 0.0, STONE_DARK, Vector2.ZERO)
	houses.add(tp + Vector3(-0.8, 1.9, 0), Vector3(3.4, 2.4, 1.6), 0.0, Color(0.97, 0.9, 0.72), Vector2.ZERO)
	houses.add(tp + Vector3(1.6, 0.85, 0), Vector3(0.9, 0.4, 0.9), 0.0, STONE, Vector2.ZERO)
	# Pool of Shelah: water in a stone basin
	var pp := unit_to_world(POOL)
	houses.add(pp + Vector3(0, -0.15, 0), Vector3(3.0, 0.5, 1.9), 0.3, STONE_DARK, Vector2.ZERO)
	rugs.add(pp + Vector3(0, 0.12, 0), Vector3(2.5, 0.05, 1.45), 0.3, WATER, Vector2.ZERO)
	add_child(houses.instance(_vertex_material()))
	add_child(rugs.instance(_vertex_material()))

func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ring := _ring_polygon()
	var trees := _Boxes.new()
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.07
	trunk.bottom_radius = 0.11
	trunk.height = 0.6
	trunk.radial_segments = 5
	trunk.rings = 0
	var crown := SphereMesh.new()
	crown.radius = 0.5
	crown.height = 0.72
	crown.radial_segments = 7
	crown.rings = 3
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.26
	cone.height = 1.9
	cone.radial_segments = 6
	cone.rings = 0
	# Groves: most on the Mount of Olives and in the valleys, a garden by the pool
	var groves := 0
	while groves < 46:
		var c := Vector2(rng.randf_range(-0.4, 1.4), rng.randf_range(-0.3, 1.3))
		var where := smoothstep(0.86, 1.0, c.x) + _trench(_poly_dist(c, KIDRON), 0.07) + _trench(_poly_dist(c, HINNOM), 0.07)
		if c.distance_to(CENTER) > 0.95 or Geometry2D.is_point_in_polygon(c, ring) or rng.randf() > where * 0.9:
			continue
		groves += 1
		_grove(trees, rng, c, rng.randi_range(5, 12), ring, trunk, crown, cone)
	_grove(trees, rng, POOL + Vector2(0.03, 0.07), 10, ring, trunk, crown, cone)   # the King's Garden
	add_child(trees.instance(_vertex_material()))

func _grove(trees: _Boxes, rng: RandomNumberGenerator, c: Vector2, count: int, ring: PackedVector2Array,
		trunk: PrimitiveMesh, crown: PrimitiveMesh, cone: PrimitiveMesh) -> void:
	for k in count:
		var u := c + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.035
		if Geometry2D.is_point_in_polygon(u, ring):
			continue
		var p := unit_to_world(u)
		var sc := rng.randf_range(0.8, 1.25)
		var yaw := rng.randf() * TAU
		if rng.randf() < 0.08:
			trees.add_prim(cone, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc), p + Vector3(0, 0.9 * sc, 0)), CYPRESS)
			continue
		var b := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc)
		trees.add_prim(trunk, Transform3D(b, p + Vector3(0, 0.25 * sc, 0)), TRUNK)
		var green := OLIVE_TREE.lerp(VALLEY, rng.randf() * 0.5)
		trees.add_prim(crown, Transform3D(b, p + Vector3(0, 0.78 * sc, 0)), green)
		trees.add_prim(crown, Transform3D(b.scaled(Vector3.ONE * 0.6), p + b * Vector3(0.28, 0.95, 0.1)), green.lightened(0.06))

func _vertex_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.95
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _mesh(verts: PackedVector3Array, cols: PackedColorArray, uv2: Variant, mat: Material) -> MeshInstance3D:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	if uv2 != null:
		arr[Mesh.ARRAY_TEX_UV2] = uv2
	var st := SurfaceTool.new()
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	st.create_from(m, 0)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi

# Flat-shaded boxes batched into one mesh (vertex colour + UV2 carried through)
class _Boxes:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uv2 := PackedVector2Array()

	func add(center: Vector3, size: Vector3, yaw: float, col: Color, extra: Vector2) -> void:
		var basis := Basis(Vector3.UP, yaw)
		var h := size * 0.5
		# +x −x +y −y +z −z faces (corners listed anticlockwise from outside; emitted clockwise)
		var faces := [
			[Vector3(1, 0, 0), [Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(1, -1, 1)]],
			[Vector3(-1, 0, 0), [Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(-1, 1, -1), Vector3(-1, -1, -1)]],
			[Vector3(0, 1, 0), [Vector3(-1, 1, -1), Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1)]],
			[Vector3(0, -1, 0), [Vector3(-1, -1, 1), Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1)]],
			[Vector3(0, 0, 1), [Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1), Vector3(-1, -1, 1)]],
			[Vector3(0, 0, -1), [Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, -1, -1)]],
		]
		for f: Array in faces:
			var nrm: Vector3 = basis * (f[0] as Vector3)
			var c: Array = f[1]
			# Sides a touch darker than tops — reads as form even in flat light
			var shade := col if (f[0] as Vector3).y > 0.5 else col.darkened(0.06)
			for idx: int in [0, 2, 1, 0, 3, 2]:
				verts.append(center + basis * ((c[idx] as Vector3) * h))
				norms.append(nrm)
				cols.append(shade)
				uv2.append(extra)

	func add_prim(mesh: PrimitiveMesh, xf: Transform3D, col: Color) -> void:
		var arr := mesh.get_mesh_arrays()
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for t in range(0, idx.size(), 3):
			var fn := (xf.basis * (nr[idx[t]] + nr[idx[t + 1]] + nr[idx[t + 2]])).normalized()
			var shade := col.darkened(0.08 * (1.0 - maxf(fn.y, 0.0)))
			for k in 3:
				verts.append(xf * v[idx[t + k]])
				norms.append(fn)
				cols.append(shade)
				uv2.append(Vector2.ZERO)

	func instance(mat: Material) -> MeshInstance3D:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = mat
		return mi
