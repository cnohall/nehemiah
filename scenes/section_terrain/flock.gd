class_name Flock
extends Node3D

# The sheep about the Sheep Gate (SectionTerrain._sheepfold). Cosmetic, so each peer
# animates its own and nothing crosses the network. Each sheep is a body mesh and a
# head mesh (its parts merged, one draw call each); all the legs share two MultiMeshes
# (front, hind) and all the ears one, posed from here every frame.
#   idle:   graze, nibbling, then look up and about; ears flick, the body sways;
#           now and then a sheep turns in place
#   wander: amble a metre or two and stop — the fold flock inside the fold walls, the
#           strays near where they were set down, clear of the stone, the wall's work
#           strip and the spots workers use
#   shy:    from workers and foes close by, and loud things (Sfx.STARTLES → startle)
# Each sheep is a capsule from rump to nose; a move is only taken if that capsule stays
# clear of the others (where they stand and where they're headed).

enum State { IDLE, TURN, WALK }

const WALK_SPEED   := 0.3     # m/s
const SHY_SPEED    := 1.3
const TURN_SPEED   := 1.0     # rad/s
const SHY_TURN     := 2.6
const STRIDE       := 0.62    # m per leg cycle, at ewe size
const LEG_SWING    := 0.42    # rad
const HIP_Y        := 0.62    # up the leg mesh (sheep units)
const HEAD_ROOT    := Vector3(0.52, 0.78, 0)   # the neck pivot (SectionTerrain._sheep)
const GRAZE_PITCH  := -0.56
const WALK_PITCH   := -0.14
const ALERT_PITCH  := 0.1
const RUMP         := -0.86   # capsule ends along +X (sheep units)
const NOSE         := 1.45
const SHOULDER     := 0.7
const NOSE_OVER    := 0.75    # how far past the fold's inside the nose may reach (sheep units)
const RADIUS       := 0.3     # capsule radius (sheep units)
const STRAY_RANGE  := 2.4     # how far a stray goes from where it was set down
const PLAYER_REACH := 2.4
const FOE_REACH    := 5.0
const SHY_COOL     := 2.5     # s before a sheep will shy again
const WALL_CLEAR   := 1.5     # past WALL_STRIP
const SPOT_CLEAR   := 1.8     # from SectionTerrain.keep_clear()
const BUSH_CLEAR   := 0.5     # body from a bush's centre, past the sheep's own girth (the nose may browse in)
const GAP          := 0.2     # between two sheep's girths

## SectionTerrain: blocks() and keep_clear() for the strays
var terrain: Node3D
var _wall_strip: Rect2
var _bushes: Array[Vector2] = []   # ScatterLayer's and SectionTerrain's, local
var _sheep: Array[Dictionary] = []
var _mat: Material
var _leg_meshes: Array[Mesh] = []   # front, hind
var _ear_mesh: Mesh
var _legs: Array[MultiMesh] = []    # front, hind: two legs of each sheep in each
var _ears: MultiMesh
var _rng := RandomNumberGenerator.new()
var _t := 0.0

func setup(owner_terrain: Node3D, wall_strip: Rect2, mat: Material, front_leg: Mesh, hind_leg: Mesh, ear: Mesh, seed_value: int) -> void:
	terrain = owner_terrain
	_wall_strip = wall_strip.grow(WALL_CLEAR)
	_mat = mat
	_leg_meshes = [front_leg, hind_leg]
	_ear_mesh = ear
	_rng.seed = seed_value

## One sheep, from SectionTerrain._sheep. `pen_r` > 0: it stays within that of `pen_c`
## (rump and nose both); otherwise it strays near `at`.
func add_sheep(at: Vector3, yaw: float, s: Vector3, body: Mesh, head: Mesh, leg_color: Color, ear_color: Color,
		head_turn: float, grazing: bool, pen_c: Vector3, pen_r: float) -> void:
	var b := MeshInstance3D.new()
	b.mesh = body
	b.material_override = _mat
	var h := MeshInstance3D.new()
	h.mesh = head
	h.material_override = _mat
	var sh := {
		"pos": Vector2(at.x, at.z), "yaw": yaw, "s": s, "body": b, "head": h,
		"leg_color": leg_color, "ear_color": ear_color, "head_turn": head_turn,
		"home": Vector2(at.x, at.z), "pen_c": Vector2(pen_c.x, pen_c.z), "pen_r": pen_r,
		"state": State.IDLE, "target": Vector2(at.x, at.z), "target_yaw": yaw, "speed": WALK_SPEED, "turn": TURN_SPEED,
		"timer": _rng.randf_range(3.0, 12.0), "graze": grazing, "graze_timer": _rng.randf_range(2.0, 8.0),
		"pitch": GRAZE_PITCH if grazing else 0.0, "head_yaw": head_turn, "head_yaw_to": head_turn,
		"ear": [1.0, 1.0], "ear_timer": _rng.randf_range(0.5, 4.0), "gait": 0.0, "step": 0.0,
		"phase": _rng.randf() * TAU, "shy": 0.0, "alert": 0.0,
	}
	_sheep.append(sh)

func _ready() -> void:
	add_to_group("sheep_flocks")
	# The ground layout is the same in every section, so these hold until we're rebuilt
	for layer: Node3D in [terrain.get_node_or_null("../ScatterLayer"), terrain]:
		if layer:
			for b: Vector2 in layer.get("bush_spots"):
				_bushes.append(_local(layer.global_transform * Vector3(b.x, 0.0, b.y)))
	for sh in _sheep:
		add_child(sh.body)
		add_child(sh.head)
	for i in 2:
		_legs.append(_multimesh(_leg_meshes[i], _sheep.size() * 2))
	_ears = _multimesh(_ear_mesh, _sheep.size() * 2)
	for i in _sheep.size():
		for k in 2:
			_legs[0].set_instance_color(i * 2 + k, _sheep[i].leg_color)
			_legs[1].set_instance_color(i * 2 + k, _sheep[i].leg_color)
			_ears.set_instance_color(i * 2 + k, _sheep[i].ear_color)
	_pose_all()

func _multimesh(mesh: Mesh, count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _mat
	add_child(mmi)
	return mm

# ── Every frame ───────────────────────────────────────────────

func _process(delta: float) -> void:
	if _sheep.is_empty():
		return
	_t += delta
	var players := get_tree().get_nodes_in_group("players")
	var foes := get_tree().get_nodes_in_group("enemies")
	for sh in _sheep:
		sh.shy = maxf(sh.shy - delta, 0.0)
		sh.alert = maxf(sh.alert - delta, 0.0)
		if sh.shy <= 0.0:
			_sense(sh, players, PLAYER_REACH)
			if sh.shy <= 0.0:
				_sense(sh, foes, FOE_REACH)
		_move(sh, delta)
		_head(sh, delta)
	_pose_all()

func _sense(sh: Dictionary, near: Array, reach: float) -> void:
	for n: Node3D in near:
		var p := _local(n.global_position)
		if p.distance_to(sh.pos) < reach * sh.s.x + 0.6:
			_shy(sh, p)
			return

func _move(sh: Dictionary, delta: float) -> void:
	var size: float = sh.s.x
	match sh.state:
		State.IDLE:
			sh.step = move_toward(sh.step, 0.0, delta * 3.0)
			sh.timer -= delta
			if sh.timer <= 0.0:
				sh.timer = _rng.randf_range(6.0, 15.0)
				var r := _rng.randf()
				if r < 0.5:
					_wander(sh)
				elif r < 0.8:
					_turn_in_place(sh)
		State.TURN:
			sh.step = move_toward(sh.step, 1.0, delta * 4.0)
			var d := angle_difference(sh.yaw, sh.target_yaw)
			var turn := clampf(d, -sh.turn * delta, sh.turn * delta)
			sh.yaw += turn
			sh.gait += absf(turn) * 0.5 / (STRIDE * size)   # small steps round on the spot
			if absf(d) < 0.01:
				sh.state = State.WALK if sh.pos.distance_to(sh.target) > 0.05 else State.IDLE
		State.WALK:
			sh.step = move_toward(sh.step, 1.0, delta * 4.0)
			var to: Vector2 = sh.target - sh.pos
			var dist := to.length()
			var go := minf(dist, sh.speed * delta)
			if dist > 0.001:
				sh.pos += to / dist * go
				sh.yaw = rotate_toward(sh.yaw, _yaw_of(to), delta * 2.0)
			sh.gait += go / (STRIDE * size)
			if dist - go < 0.01:
				sh.state = State.IDLE
				sh.speed = WALK_SPEED
				sh.timer = _rng.randf_range(5.0, 12.0)

# Head: graze and look up by turns while standing; carried low walking, high alarmed
func _head(sh: Dictionary, delta: float) -> void:
	var pitch_to := 0.0
	if sh.alert > 0.0:
		pitch_to = ALERT_PITCH
	elif sh.state != State.IDLE:
		pitch_to = WALK_PITCH
	else:
		sh.graze_timer -= delta
		if sh.graze_timer <= 0.0:
			sh.graze = not sh.graze
			sh.graze_timer = _rng.randf_range(4.0, 11.0) if sh.graze else _rng.randf_range(1.8, 5.0)
			sh.head_yaw_to = sh.head_turn + (_rng.randf_range(-0.12, 0.12) if sh.graze else _rng.randf_range(-0.4, 0.4))
		elif not sh.graze and _rng.randf() < delta * 0.35:
			sh.head_yaw_to = sh.head_turn + _rng.randf_range(-0.4, 0.4)   # looks about
		if sh.graze:
			# Nibbling: short bobs, in bursts
			var burst := smoothstep(0.2, 0.6, sin(_t * 0.9 + sh.phase))
			pitch_to = GRAZE_PITCH - 0.05 * burst * (0.5 + 0.5 * sin(_t * 9.0 + sh.phase))
	var rate := 2.4 if sh.alert > 0.0 else 1.3
	sh.pitch = lerpf(sh.pitch, pitch_to, 1.0 - exp(-delta * rate * 2.0))
	sh.head_yaw = lerpf(sh.head_yaw, sh.head_yaw_to, 1.0 - exp(-delta * 1.6))
	# Ears: a quick flick now and then, one or both
	for k in 2:
		if sh.ear[k] < 1.0:
			sh.ear[k] = minf(sh.ear[k] + delta / 0.28, 1.0)
	sh.ear_timer -= delta
	if sh.ear_timer <= 0.0:
		sh.ear_timer = _rng.randf_range(1.2, 5.0)
		var k := _rng.randi() % 3
		if k < 2:
			sh.ear[k] = 0.0
		else:
			sh.ear = [0.0, 0.0]

# ── Choices ───────────────────────────────────────────────────

# Amble a metre or two, somewhere it fits — of a few such spots, the roomiest
func _wander(sh: Dictionary) -> void:
	var best := Vector2.INF
	var room := -1.0
	var found := 0
	for i in 14:
		var dir := Vector2.RIGHT.rotated(_rng.randf() * TAU)
		var to: Vector2 = sh.pos + dir * _rng.randf_range(0.7, 2.0) * sh.s.x
		if not _fits(sh, to, _yaw_of(dir), true):
			continue
		var r := _room(sh, to, _yaw_of(dir))
		if r > room:
			room = r
			best = to
		found += 1
		if found == 3:
			break
	if best != Vector2.INF:
		_go(sh, best, WALK_SPEED, TURN_SPEED)

# How far the nearest other sheep would be
func _room(sh: Dictionary, p: Vector2, yaw: float) -> float:
	var ends := _capsule(p, yaw, sh.s.x)
	var r := INF
	for o in _sheep:
		if o != sh:
			r = minf(r, apart(ends, _capsule(o.target, o.target_yaw, o.s.x)))
	return r

func _turn_in_place(sh: Dictionary) -> void:
	for i in 6:
		var yaw: float = sh.yaw + _rng.randf_range(0.5, 1.5) * (1.0 if _rng.randf() < 0.5 else -1.0)
		if _fits(sh, sh.pos, yaw, false):
			sh.target = sh.pos
			sh.target_yaw = yaw
			sh.turn = TURN_SPEED
			sh.state = State.TURN
			return

## Sfx (via group "sheep_flocks"): something loud at `at` (null or reach 0 = heard site-wide)
func startle(at: Variant, reach: float) -> void:
	for sh in _sheep:
		if sh.shy > 0.0:
			continue
		if at == null or reach <= 0.0:
			_shy(sh, sh.pos + Vector2.RIGHT.rotated(_rng.randf() * TAU))
		elif _local(at).distance_to(sh.pos) < reach * 1.4:
			_shy(sh, _local(at))

# Head up, and off a little way from `from` if there's room; else just face away
func _shy(sh: Dictionary, from: Vector2) -> void:
	sh.shy = SHY_COOL
	sh.alert = _rng.randf_range(2.5, 4.0)
	sh.graze = false
	sh.graze_timer = sh.alert + _rng.randf_range(1.0, 3.0)
	var away: Vector2 = sh.pos - from
	if away.length_squared() < 0.0001:
		away = Vector2.RIGHT.rotated(_rng.randf() * TAU)
	away = away.normalized()
	for bend: float in [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6]:
		var dir := away.rotated(bend + _rng.randf_range(-0.15, 0.15))
		var to: Vector2 = sh.pos + dir * _rng.randf_range(1.0, 2.0) * sh.s.x
		if _fits(sh, to, _yaw_of(dir), true):
			_go(sh, to, SHY_SPEED, SHY_TURN)
			return
	if _fits(sh, sh.pos, _yaw_of(away), false):
		sh.target = sh.pos
		sh.target_yaw = _yaw_of(away)
		sh.turn = SHY_TURN
		sh.state = State.TURN

func _go(sh: Dictionary, to: Vector2, speed: float, turn: float) -> void:
	sh.target = to
	sh.target_yaw = _yaw_of(to - sh.pos)
	sh.speed = speed
	sh.turn = turn
	sh.state = State.TURN

# Would the sheep fit turning to `yaw` where it stands and (`path`) walking on to `p`?
# Checked at a few poses along the way, against where the others stand and where
# they're headed. A pair already closer than the gap (as laid out) may not get closer.
func _fits(sh: Dictionary, p: Vector2, yaw: float, path: bool) -> bool:
	var poses := []
	for k in [1, 2, 3]:
		poses.append([sh.pos, lerp_angle(sh.yaw, yaw, k / 3.0)])
	if path:
		for t in [0.33, 0.66, 1.0]:
			poses.append([sh.pos.lerp(p, t), yaw])
	var now := _capsule(sh.pos, sh.yaw, sh.s.x)
	for pose: Array in poses:
		var ends := _capsule(pose[0], pose[1], sh.s.x)
		if sh.pen_r > 0.0:
			if not in_pen(ends, sh.pen_c, sh.pen_r, sh.s.x):
				return false
		elif not _stray_ok(sh, pose[0], ends):
			return false
		if not _clear_of_bushes(sh, ends):
			return false
		for o in _sheep:
			if o == sh:
				continue
			var gap: float = minf(RADIUS * (sh.s.x + o.s.x) + GAP, apart(now, _capsule(o.pos, o.yaw, o.s.x)))
			for o_at: Array in _taken(o):
				if apart(ends, _capsule(o_at[0], o_at[1], o.s.x)) < gap:
					return false
	return true

# Rump to shoulders clear of every bush (unless it already stands in one)
func _clear_of_bushes(sh: Dictionary, ends: Array[Vector2]) -> bool:
	var shoulder := ends[0].lerp(ends[1], (SHOULDER - RUMP) / (NOSE - RUMP))
	var now := _capsule(sh.pos, sh.yaw, sh.s.x)
	var now_shoulder := now[0].lerp(now[1], (SHOULDER - RUMP) / (NOSE - RUMP))
	var clear: float = RADIUS * sh.s.x + BUSH_CLEAR
	for b in _bushes:
		if b.distance_squared_to(ends[0]) > 9.0 and b.distance_squared_to(ends[1]) > 9.0:
			continue
		var d := Geometry2D.get_closest_point_to_segment(b, ends[0], shoulder).distance_to(b)
		if d < clear and d < Geometry2D.get_closest_point_to_segment(b, now[0], now_shoulder).distance_to(b):
			return false
	return true

# Where another sheep is and will be before it next stands still
static func _taken(o: Dictionary) -> Array:
	if o.state == State.IDLE:
		return [[o.pos, o.yaw]]
	return [[o.pos, o.yaw], [o.pos, o.target_yaw], [o.pos.lerp(o.target, 0.5), o.target_yaw], [o.target, o.target_yaw]]

## Rump and shoulders inside the fold; the head, carried above the low wall, may reach over it
static func in_pen(ends: Array[Vector2], c: Vector2, r: float, size: float) -> bool:
	var shoulder := ends[0].lerp(ends[1], (SHOULDER - RUMP) / (NOSE - RUMP))
	return ends[0].distance_to(c) <= r and shoulder.distance_to(c) <= r and ends[1].distance_to(c) <= r + NOSE_OVER * size

## Gap between two sheep's capsule cores
static func apart(a: Array[Vector2], b: Array[Vector2]) -> float:
	var c := Geometry2D.get_closest_points_between_segments(a[0], a[1], b[0], b[1])
	return c[0].distance_to(c[1])

func _stray_ok(sh: Dictionary, at: Vector2, ends: Array[Vector2]) -> bool:
	if at.distance_to(sh.home) > STRAY_RANGE:
		return false
	for e: Vector2 in [at, ends[0], ends[1]]:
		if _wall_strip.has_point(e) or terrain.blocks(e, 0.3):
			return false
	for k: Vector2 in terrain.keep_clear():
		if k.distance_to(at) < SPOT_CLEAR:
			return false
	return true

# ── Posing ────────────────────────────────────────────────────

func _pose_all() -> void:
	for i in _sheep.size():
		var sh := _sheep[i]
		var s: Vector3 = sh.s
		var p: Vector2 = sh.pos
		var root := Transform3D(Basis(Vector3.UP, sh.yaw), Vector3(p.x, _ground(p), p.y))
		# Breathing sway, a little bob in the stride
		var bob: float = 0.018 * s.y * absf(sin(sh.gait * TAU)) * sh.step
		var roll: float = 0.016 * sin(_t * 0.8 + sh.phase) + 0.03 * sin(sh.gait * TAU) * sh.step
		var body := root * Transform3D(Basis(Vector3.RIGHT, roll), Vector3(0, bob, 0))
		sh.body.transform = body
		var head := body * Transform3D(Basis(Vector3.BACK, sh.pitch) * Basis(Vector3.UP, sh.head_yaw), HEAD_ROOT * s)
		sh.head.transform = head
		# Legs from the hip, diagonal pairs together
		var hip := Vector3(0, HIP_Y * s.y, 0)
		var k := 0
		for x: float in [0.42, -0.55]:   # front, hind
			for side: float in [-1.0, 1.0]:
				var pair := 0.0 if (x > 0.0) == (side > 0.0) else 0.5
				var swing: float = LEG_SWING * sh.step * sin(TAU * (sh.gait + pair))
				var leg := root * Transform3D(Basis(Vector3.BACK, swing), Vector3(x, 0, side * 0.31) * s + hip) \
					* Transform3D(Basis.from_scale(s), -hip)
				_legs[0 if x > 0.0 else 1].set_instance_transform(i * 2 + (k % 2), leg)
				k += 1
		# Ears: the tip lifts on a flick
		for e in 2:
			var side := 1.0 if e == 0 else -1.0
			var flick := -0.6 * sin(PI * sh.ear[e])
			var at := Vector3(0.83, 1.2, side * 0.17) - HEAD_ROOT
			var ear := head * Transform3D(Basis(Vector3.UP, 0.0 if side > 0.0 else PI) * Basis.from_scale(s) * Basis(Vector3.RIGHT, flick), at * s)
			_ears.set_instance_transform(i * 2 + e, ear)

func _ground(p: Vector2) -> float:
	var o := global_position
	return Terrain.height(p.x + o.x, p.y + o.z) - o.y

func _local(v: Vector3) -> Vector2:
	var l := to_local(v)
	return Vector2(l.x, l.z)

# Rump and nose, on the ground
static func _capsule(at: Vector2, yaw: float, size: float) -> Array[Vector2]:
	var fwd := Vector2(cos(yaw), -sin(yaw))
	return [at + fwd * RUMP * size, at + fwd * NOSE * size]

# Yaw that faces a sheep (+X forward) along `dir` on the ground (x, z)
static func _yaw_of(dir: Vector2) -> float:
	return atan2(-dir.y, dir.x)
