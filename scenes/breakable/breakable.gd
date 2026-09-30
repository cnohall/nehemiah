class_name Breakable
extends Node3D

# A small household thing standing about the site — a clay water jar, a tall storage
# jar, a reed basket of figs — that rocks when someone brushes past and breaks when
# struck: a sword cut, a sling stone, a dash, or a raider trampling it on the way to the
# wall (Zelda's pots, Hades' urns). Purely a set piece: no collision, nothing inside,
# never in the way of the work. What's left (sherds, a wet patch, spilled grain) stays
# on the ground until dawn, when the city puts out fresh ones (Breakables).
# Built and broken on every peer; Breakables decides on the server what breaks.

const KINDS := ["jar", "store", "basket"]
const SIZE := 1.35   # modelled life-size; drawn bigger so they read beside the chibi crew
const RADIUS := { "jar": 0.26, "store": 0.34, "basket": 0.32 }   # footprint at SIZE 1, for hits and brushes
const CLAY  := Color(0.66, 0.40, 0.25)
const PALE_CLAY := Color(0.78, 0.60, 0.42)
const REED  := Color(0.66, 0.53, 0.30)
const FIG   := Color(0.36, 0.20, 0.26)
const BREAD := Color(0.80, 0.60, 0.34)
const WATER := Color(0.22, 0.30, 0.32, 0.55)
const GRAIN := Color(0.88, 0.80, 0.58)
const WOBBLE_CD := 0.5
const WET_TIME := 9.0   # the splash dries this long after
const MARKER_SHADER := preload("res://assets/shaders/ground_marker.gdshader")

var kind := "jar"
var broken := false

var _tint := Color.WHITE
var _intact: Node3D
var _remains: Node3D
var _wobble: Tween
var _wobble_cd := 0.0

static var _mats := {}

## Called once, before it enters the tree. `seed_` varies the colour, the same on every peer.
func setup(k: String, seed_: int) -> void:
	kind = k
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var v := rng.randf_range(-0.05, 0.05)
	_tint = Color(1.0 + v, 1.0 + v, 1.0 + v * 0.8)
	rotation.y = rng.randf() * TAU
	scale = Vector3.ONE * SIZE

func _ready() -> void:
	add_to_group("breakables")
	_intact = Node3D.new()
	add_child(_intact)
	match kind:
		"jar":    _build_jar()
		"store":  _build_store()
		"basket": _build_basket()
	_add_shadow()

func _process(delta: float) -> void:
	_wobble_cd = maxf(_wobble_cd - delta, 0.0)

func radius() -> float:
	return RADIUS[kind] * SIZE

# ── Looks ─────────────────────────────────────────────────────

func _build_jar() -> void:
	var c := CLAY * _tint
	_mesh(_intact, _sphere(0.24, 0.48), c, Vector3(0, 0.25, 0))
	_mesh(_intact, _cyl(0.08, 0.1, 0.16), c.darkened(0.05), Vector3(0, 0.52, 0))
	_mesh(_intact, _cyl(0.12, 0.11, 0.05), c.lightened(0.08), Vector3(0, 0.61, 0))
	# Two loop handles at the shoulder
	for s: float in [-1.0, 1.0]:
		_mesh(_intact, _cyl(0.03, 0.03, 0.16), c.darkened(0.08), Vector3(s * 0.2, 0.42, 0), Vector3(0, 0, s * 0.5))

func _build_store() -> void:
	var c := PALE_CLAY * _tint
	_mesh(_intact, _sphere(0.3, 0.78), c, Vector3(0, 0.4, 0))
	_mesh(_intact, _cyl(0.14, 0.2, 0.12), c.darkened(0.04), Vector3(0, 0.82, 0))
	_mesh(_intact, _cyl(0.16, 0.15, 0.05), c.lightened(0.06), Vector3(0, 0.9, 0))
	# A painted band round the shoulder
	_mesh(_intact, _cyl(0.285, 0.29, 0.05), Color(0.46, 0.22, 0.14), Vector3(0, 0.55, 0))

func _build_basket() -> void:
	var c := REED * _tint
	_mesh(_intact, _cyl(0.3, 0.22, 0.36), c, Vector3(0, 0.18, 0))
	# Woven bands, and a thick rolled rim
	for y: float in [0.1, 0.22]:
		_mesh(_intact, _cyl(0.27 + y * 0.18, 0.26 + y * 0.18, 0.035), c.darkened(0.18), Vector3(0, y, 0))
	_mesh(_intact, _cyl(0.33, 0.33, 0.06), c.darkened(0.1), Vector3(0, 0.36, 0))
	# Heaped with figs
	_mesh(_intact, _sphere(0.26, 0.14), FIG.darkened(0.25), Vector3(0, 0.37, 0))
	for i in 7:
		var a := TAU * i / 7.0
		_mesh(_intact, _sphere(0.085, 0.15), FIG.lightened(0.06 * (i % 3)), Vector3(cos(a) * 0.15, 0.42, sin(a) * 0.15))
	_mesh(_intact, _sphere(0.09, 0.16), FIG.lightened(0.1), Vector3(0, 0.49, 0))

func _add_shadow() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * radius() * 3.2
	quad.orientation = PlaneMesh.FACE_Y
	var mat := ShaderMaterial.new()
	mat.shader = MARKER_SHADER
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.02
	_intact.add_child(mi)

# ── Brushed past ──────────────────────────────────────────────

## Someone brushed against it: rock away from `from`, then settle. `hard`: walked
## right into it, or a neighbour burst — rocks further, and cuts short a gentle rock
func nudge(from: Vector3, hard := false) -> void:
	if broken or (_wobble_cd > 0.0 and not hard):
		return
	_wobble_cd = WOBBLE_CD
	var push := Vector3(global_position.x - from.x, 0.0, global_position.z - from.z)
	if push.length_squared() < 0.0001:
		push = Vector3.FORWARD
	# Tip about the axis across the push, in the piece's own (yawed) frame
	var axis := (Vector3.UP.cross(push.normalized())).rotated(Vector3.UP, -rotation.y)
	if _wobble:
		_wobble.kill()
	_intact.rotation = Vector3.ZERO
	_wobble = create_tween()
	var tip := (0.22 if kind != "store" else 0.14) * (1.5 if hard else 1.0)
	for step: float in [tip, -tip * 0.55, tip * 0.25, 0.0]:
		# Small angles: tipping about a flat axis is near enough its x/z Euler parts
		_wobble.tween_property(_intact, "rotation", Vector3(axis.x, 0.0, axis.z) * step, 0.09) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	Sfx.play("pot_knock", global_position)

# ── Broken ────────────────────────────────────────────────────

## Every peer: shatter, flung along `dir` (flat; zero = straight up)
func smash(dir: Vector3, quiet := false) -> void:
	if broken:
		return
	broken = true
	if _wobble:
		_wobble.kill()
	_intact.visible = false
	_build_remains(dir, not quiet)
	if quiet:
		return   # a late joiner catching up: just show what's left
	var up := global_position + Vector3(0, 0.35, 0)
	match kind:
		"jar":
			_burst(up, dir, CLAY * _tint, 14, 0.14)
			_droplets(up, dir)
			Sfx.play("shatter", global_position)
			Sfx.play("splash", global_position)
		"store":
			_burst(up + Vector3(0, 0.15, 0), dir, PALE_CLAY * _tint, 18, 0.16)
			DustFx.puff(self, up, 12, 0.7, Color(GRAIN, 0.7))
			Sfx.play("shatter", global_position)
		"basket":
			_burst(up, dir, REED * _tint, 12, 0.11)
			DustFx.puff(self, up, 6, 0.5)
			Sfx.play("basket_crush", global_position)

## Every peer: put a whole one back (dawn)
func restore() -> void:
	broken = false
	if _remains:
		_remains.queue_free()
		_remains = null
	_intact.visible = true
	_intact.rotation = Vector3.ZERO
	_intact.scale = Vector3.ONE * 0.7
	create_tween().tween_property(_intact, "scale", Vector3.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# What lies there after: sherds (the bottom still standing), or the crushed basket.
# `fling`: the loose bits fly out and land as the burst comes down, not already lying there
func _build_remains(dir: Vector3, fling := true) -> void:
	_remains = Node3D.new()
	add_child(_remains)
	_remains.top_level = true   # laid out in world space, whatever way the piece faced
	_remains.global_position = global_position
	_remains.scale = Vector3.ONE * SIZE
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(global_position)
	var flat := Vector3(dir.x, 0.0, dir.z).normalized() if Vector2(dir.x, dir.z).length_squared() > 0.001 else Vector3.ZERO
	var c := (CLAY if kind == "jar" else PALE_CLAY if kind == "store" else REED) * _tint
	match kind:
		"jar", "store":
			var r: float = RADIUS[kind]   # _remains is already scaled by SIZE
			# The foot still standing, its broken edge jagged
			_mesh(_remains, _cyl(r * 0.62, r * 0.5, 0.16), c.darkened(0.06), Vector3(0, 0.08, 0))
			for i in 4:
				var a := TAU * i / 4.0 + rng.randf_range(-0.3, 0.3)
				_mesh(_remains, _box(Vector3(r * 0.5, rng.randf_range(0.08, 0.16), 0.03)), c.darkened(0.03),
					Vector3(cos(a) * r * 0.52, 0.18, sin(a) * r * 0.52), Vector3(rng.randf_range(-0.3, 0.3), PI / 2 - a, 0.0))
			for i in 7:
				var at := flat * rng.randf_range(0.15, 0.55) \
					+ Vector3(rng.randf_range(-0.5, 0.5), 0.02, rng.randf_range(-0.5, 0.5))
				var s := Vector3(rng.randf_range(0.12, 0.2), 0.035, rng.randf_range(0.08, 0.14))
				var sherd := _mesh(_remains, _box(s), c.lightened(rng.randf_range(-0.05, 0.08)), at,
					Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3)))
				sherd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if fling:
					_fly(sherd, rng.randf_range(0.3, 0.45), rng.randf_range(0.15, 0.35))
			if kind == "jar":
				_wet_patch()
			else:
				var heap := _mesh(_remains, _sphere(0.3, 0.12), GRAIN, flat * 0.3)   # spilled grain
				heap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if fling:
					_spill(heap, 0.1)
		"basket":
			var squashed := _mesh(_remains, _cyl(0.32, 0.28, 0.1), c.darkened(0.05), Vector3(0, 0.05, 0), Vector3(0.25, 0, 0.15))
			squashed.scale = Vector3(1.1, 1.0, 0.9)
			# The figs roll out the way it was knocked
			for i in 4:
				var to := (flat if flat != Vector3.ZERO else Vector3.RIGHT.rotated(Vector3.UP, i * 1.6)) \
					.rotated(Vector3.UP, rng.randf_range(-0.8, 0.8)) * rng.randf_range(0.4, 0.9)
				var fig := _mesh(_remains, _sphere(0.07, 0.12), FIG, Vector3(to.x, 0.06, to.z))
				if fling:
					# Out and rolling: a low hop, then along the ground
					_fly(fig, 0.35 + i * 0.05, 0.12)
			var loaf := _mesh(_remains, _sphere(0.16, 0.08), BREAD.darkened(0.05), flat * 0.35 + Vector3(0.1, 0.04, 0))
			if fling:
				_fly(loaf, 0.3, 0.2)

# A loose bit thrown from the middle of the piece, landing where it now lies
func _fly(mi: MeshInstance3D, time: float, hop: float) -> void:
	var land := mi.position
	var spin := mi.rotation
	var from := Vector3(0, 0.3, 0)
	mi.position = from
	mi.create_tween().tween_method(func(t: float) -> void:
		mi.position = from.lerp(land, t) + Vector3.UP * sin(t * PI) * hop
		mi.rotation = spin + Vector3(0, (1.0 - t) * 6.0, 0), 0.0, 1.0, time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

# A heap that spreads out where it was spilled
func _spill(mi: MeshInstance3D, delay: float) -> void:
	mi.scale = Vector3(0.2, 0.4, 0.2)
	mi.create_tween().tween_property(mi, "scale", Vector3.ONE, 0.45) \
		.set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# Dark patch where the water went; it spreads, then dries
func _wet_patch() -> void:
	var disc := _cyl(0.55, 0.55, 0.01)
	disc.radial_segments = 24
	var mi := _mesh(_remains, disc, WATER, Vector3(0, 0.012, 0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := (mi.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.2
	mi.material_override = mat
	mi.scale = Vector3(0.3, 1.0, 0.3)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE, 0.4).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 2.0).set_delay(WET_TIME)

# Pieces flung out and falling back
func _burst(at: Vector3, dir: Vector3, color: Color, amount: int, size: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = 0.7
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	p.direction = (Vector3.UP + flat * 0.8).normalized()
	p.spread = 55.0
	p.initial_velocity_min = 2.2
	p.initial_velocity_max = 4.2
	p.gravity = Vector3(0, -14.0, 0)
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.particle_flag_rotate_y = true
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	# Gone by the time they'd sink through the ground, not blinking out mid-air
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(0.75, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = shrink
	var box := BoxMesh.new()
	box.size = Vector3(size, size * 0.5, size * 0.8)
	box.material = _mat(color)
	p.mesh = box
	_fire(p, at)

# Water thrown up out of the jar
func _droplets(at: Vector3, dir: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 16
	p.lifetime = 0.5
	p.direction = (Vector3.UP + Vector3(dir.x, 0.0, dir.z).normalized() * 0.5).normalized()
	p.spread = 70.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.2
	p.gravity = Vector3(0, -12.0, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.72, 0.86, 0.92, 0.9))
	ramp.set_color(1, Color(0.72, 0.86, 0.92, 0.0))
	p.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	quad.material = DustFx.material()
	p.mesh = quad
	_fire(p, at)

func _fire(p: CPUParticles3D, at: Vector3) -> void:
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.top_level = true
	add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)

# ── Mesh helpers ──────────────────────────────────────────────

func _mesh(parent: Node3D, mesh: Mesh, color: Color, at: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color)
	mi.position = at
	mi.rotation = rot
	parent.add_child(mi)
	return mi

# One material per colour, shared by every piece
static func _mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.9
		_mats[key] = m
	return _mats[key]

static func _sphere(r: float, h: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 12
	m.rings = 6
	return m

static func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = 10
	m.rings = 1
	return m

static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m
