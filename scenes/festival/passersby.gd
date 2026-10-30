class_name Passersby
extends Node3D

# The lower city going about its day at the work view's edge (GDD §6.6). Each townsman lives
# behind a real door on the cross street (ScatterLayer.door_spots) and goes out on errands:
# to a neighbour's door, to the well for water (and carries the jar home), up the main street
# to stand and watch the builders, or off down the street out of sight. Then back indoors a
# while. People who meet in the street sometimes stop to talk. The horn stops them to look;
# a breach sends them running for the nearest door. A few sit out the day on their roofs.
# Purely visual: each peer runs its own, nothing is replicated, nobody can be spoken to (the
# Festival has its own Folk). Everyone is indoors by evening.

const COUNT := 8
const KINDS := ["man", "woman", "elder", "child", "woman", "man", "woman", "man"]
const CROSS_Z := 23.75               # the cross street's centre line (ScatterLayer.CROSS_Z)
const GATE_X := -4.0                 # the main street up to the work (ScatterLayer.GATE_X)
const WATCH_Z := 15.2                # top of the main street: as near the work as they come
const STREET_ENDS := [-27.0, 27.0]   # where a stroller goes out of sight down the street
const WELL := Vector2(1.6, 23.75)
const WELL_SPOT := Vector2(1.6, 21.9)    # drawing water, on the street side of the well (outside OBSTACLES)
# Things in the street to walk round: [x, z, radius]. One circle round the well and its
# trough together — two overlapping circles left a crease people got wedged in
const OBSTACLES := [[2.35, 23.95, 2.0]]
const DOOR_ZONE := Rect2(-30.0, 20.0, 60.0, 7.5)   # doors that open onto the cross street, in view

const INDOORS := Vector2(4.0, 16.0)  # seconds behind the door between errands
const WATCH_FOR := Vector2(6.0, 14.0)
const DRAW_FOR := Vector2(2.5, 4.0)
const CHAT_FOR := Vector2(2.5, 5.0)
const CHAT_REACH := 1.4
const CHAT_CHANCE := 0.35
const CHAT_COOLDOWN := 18.0
const GO_INDOORS := 0.72             # DayLight.evening at which the streets empty
const HORN_LOOK := 3.0
const FLEE_TIME := 12.0
const FLEE_SPEED := 2.6
const SITTERS := 6
const WARM_UP := 40.0                # seconds of street life run through before the first frame
const CLAY := Color(0.66, 0.42, 0.27)

enum State { INSIDE, WALK, WAIT }

class Walker:
	extends RefCounted
	var node: Node3D
	var rig: CharacterRig
	var state := State.INSIDE
	var timer := 0.0
	var path: Array[Vector2] = []
	var pos := Vector2.ZERO
	var speed := 1.0
	var lane := 0.0          # which side of the street they keep to
	var errand := ""         # what they do at the end of the path: "door", "well", "watch", "end"
	var look_yaw := NAN      # facing while they wait (NAN: keep the walk's)
	var jar: MeshInstance3D
	var chat_cool := 0.0
	var detour := 0         # going round an obstacle: which way (±1), kept till clear of it
	var resume := false     # a pause in the street (a word, the horn): carry on after it
	var anim := ""

var _walkers: Array[Walker] = []
var _sitters: Array = []   # [Node3D, flat position]
var _doors: Array = []     # [Vector2 threshold point, outward z]
var _day: Node
var _flee := 0.0

func _ready() -> void:
	if GameState.festival:
		return
	add_to_group("townsfolk")
	_day = get_parent().get_node_or_null("DayLight")
	GameState.breaches_changed.connect(_on_breach.unbind(1))
	GameState.section_changed.connect(_reseat.unbind(1))
	_setup.call_deferred()   # ScatterLayer comes after us in the tree: its doors aren't laid out yet

func _setup() -> void:
	var layer := get_parent().get_node_or_null("ScatterLayer") as ScatterLayer
	if layer == null:
		return
	for d: Array in layer.door_spots:
		var at: Vector2 = d[0]
		if DOOR_ZONE.has_point(at):
			_doors.append([at + Vector2(0, d[1] * 0.45), d[1]])
	if _doors.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 3003
	for i in COUNT:
		var w := Walker.new()
		var kind: String = KINDS[i % KINDS.size()]
		w.speed = rng.randf_range(0.8, 1.15) * {"elder": 0.75, "child": 1.2}.get(kind, 1.0)
		w.lane = rng.randf_range(-0.75, 0.75)
		w.timer = rng.randf_range(0.0, INDOORS.y)
		w.pos = _doors[rng.randi() % _doors.size()][0]
		w.node = Node3D.new()
		add_child(w.node)
		w.rig = CharacterRig.new()
		w.node.add_child(w.rig)
		var dye: Color = Palette.DYES[rng.randi() % Palette.DYES.size()]
		w.rig.setup(Folk.look_for(kind, dye, i + 11), 0.62 if kind == "child" else 0.9)
		w.rig.set_ring_color(Color(0, 0, 0, 0))
		_walkers.append(w)
	_seat_sitters(rng)
	# Start mid-morning, not with everyone stepping out of their doors at once
	for _i in int(WARM_UP / 0.25):
		_tick(0.25)
	for w in _walkers:
		_show(w)

func _process(delta: float) -> void:
	if GameState.simplified():   # the simple game keeps the streets still: nothing moving off the work
		visible = false
		return
	var out: bool = _day != null and (_day.evening > GO_INDOORS or _day.darkness > 0.2)
	visible = not out and not _walkers.is_empty()
	_tick(delta)
	for w in _walkers:
		_show(w)
	var hide_sitters := _flee > 0.0
	for sit: Array in _sitters:
		(sit[0] as Node3D).visible = not hide_sitters

func _tick(delta: float) -> void:
	_flee = maxf(0.0, _flee - delta)
	for w in _walkers:
		w.chat_cool = maxf(0.0, w.chat_cool - delta)
		match w.state:
			State.INSIDE:
				if _flee > 0.0:
					continue
				w.timer -= delta
				if w.timer <= 0.0:
					_go_out(w)
			State.WAIT:
				w.timer -= delta
				if w.timer <= 0.0 or _flee > 0.0:
					_next_leg(w)
			State.WALK:
				_walk(w, delta)
	_meet()

# ── Errands ───────────────────────────────────────────────────

func _go_out(w: Walker) -> void:
	var r := randf()
	w.state = State.WALK
	w.look_yaw = NAN
	if r < 0.3:
		w.errand = "door"
		w.path = _route(w.pos, _pick_door(w.pos))
	elif r < 0.55:
		w.errand = "well"
		w.path = _route(w.pos, WELL_SPOT + Vector2(randf_range(-0.6, 0.6), 0.0))
	elif r < 0.8:
		w.errand = "watch"
		w.path = _route(w.pos, Vector2(GATE_X + randf_range(-2.0, 2.0), WATCH_Z + randf_range(-0.4, 0.8)))
	else:
		w.errand = "end"
		var x: float = STREET_ENDS[randi() % 2]
		w.path = _route(w.pos, Vector2(x, CROSS_Z + w.lane))

# Arrived where the path ends: do the errand, then the next leg
func _arrive(w: Walker) -> void:
	match w.errand:
		"well":
			_wait(w, randf_range(DRAW_FOR.x, DRAW_FOR.y), atan2(WELL.x - w.pos.x, WELL.y - w.pos.y))
		"watch":
			_wait(w, randf_range(WATCH_FOR.x, WATCH_FOR.y), PI)   # facing the wall (−z)
		_:
			_go_in(w)

func _next_leg(w: Walker) -> void:
	if w.resume:
		w.resume = false
		w.state = State.WALK
		w.look_yaw = NAN
		return
	if w.errand == "well" and w.jar == null and _flee <= 0.0:
		_give_jar(w)
	if w.errand in ["well", "watch"] or _flee > 0.0:
		w.errand = "door"
		w.state = State.WALK
		w.look_yaw = NAN
		w.path = _route(w.pos, _nearest_door(w.pos) if _flee > 0.0 else _pick_door(w.pos))

func _go_in(w: Walker) -> void:
	w.state = State.INSIDE
	w.timer = randf_range(INDOORS.x, INDOORS.y)
	if w.jar != null:
		w.jar.queue_free()
		w.jar = null
	if w.errand == "end":   # gone down the street: come back out of some door later on
		w.pos = _doors[randi() % _doors.size()][0]

func _wait(w: Walker, secs: float, yaw: float) -> void:
	w.state = State.WAIT
	w.timer = secs
	w.look_yaw = yaw

func _walk(w: Walker, delta: float) -> void:
	if w.path.is_empty():
		_arrive(w)
		return
	var goal: Vector2 = w.path[0]
	var to := goal - w.pos
	var step := w.speed * (FLEE_SPEED if _flee > 0.0 else 1.0) * delta
	if to.length() <= step:
		w.pos = goal
		w.path.pop_front()
		if w.path.is_empty():
			_arrive(w)
		return
	# Heading into the well (or its trough): walk round its rim instead, the way that's nearer the goal
	var dir := to.normalized()
	var rounding := false
	for o: Array in OBSTACLES:
		var c := Vector2(o[0], o[1])
		var off := w.pos - c
		if off.length() < o[2] + 0.35 and _cuts(w.pos, goal, c, o[2]):
			var tangent := Vector2(-off.y, off.x).normalized()
			if w.detour == 0:   # pick a way round once, the shorter one, and keep to it
				w.detour = 1 if tangent.dot(to) >= 0.0 else -1
			dir = (tangent * w.detour + off.normalized() * 0.1).normalized()
			rounding = true
	if not rounding:
		w.detour = 0
	w.pos += dir * step
	w.pos = _clear_of_obstacles(w.pos)

# Down from the door to the street, along it, and up to the other door; the main street is
# the way to the work. Everyone keeps to their own side of the street (lane).
func _route(from: Vector2, to: Vector2) -> Array[Vector2]:
	var lane := CROSS_Z + randf_range(-0.75, 0.75)
	var out: Array[Vector2] = []
	var up_main := from.y < 21.5      # starting from the top of the main street
	var to_main := to.y < 21.5
	if up_main:
		out.append(Vector2(GATE_X + randf_range(-0.8, 0.8), lane))
	else:
		out.append(Vector2(from.x, lane))
	if to_main:
		out.append(Vector2(GATE_X + randf_range(-0.8, 0.8), lane))
		out.append(Vector2(GATE_X + randf_range(-1.0, 1.0), (lane + to.y) * 0.5))
	else:
		out.append(Vector2(to.x, lane))
	out.append(to)
	for k in out.size():
		out[k] = _clear_of_obstacles(out[k])
	return out

## True if the straight walk from a to b passes through the circle (centre c, radius r)
static func _cuts(a: Vector2, b: Vector2, c: Vector2, r: float) -> bool:
	var ab := b - a
	var t := clampf((c - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return (a + ab * t).distance_to(c) < r - 0.02

static func _clear_of_obstacles(p: Vector2) -> Vector2:
	for o: Array in OBSTACLES:
		var c := Vector2(o[0], o[1])
		var off := p - c
		if off.length() < o[2] + 0.1:
			p = c + (off.normalized() if off.length() > 0.01 else Vector2.UP) * (o[2] + 0.12)
	return p

func _pick_door(near: Vector2) -> Vector2:
	# A neighbour, mostly: weight doors within ~15 m
	for _try in 6:
		var d: Vector2 = _doors[randi() % _doors.size()][0]
		if d.distance_to(near) > 2.0 and d.distance_to(near) < 15.0:
			return d
	return _doors[randi() % _doors.size()][0]

func _nearest_door(near: Vector2) -> Vector2:
	var best: Vector2 = _doors[0][0]
	for d: Array in _doors:
		if (d[0] as Vector2).distance_squared_to(near) < best.distance_squared_to(near):
			best = d[0]
	return best

# Two walkers passing close in the street, both free: sometimes they stop for a word
func _meet() -> void:
	for i in _walkers.size():
		var a := _walkers[i]
		if a.state != State.WALK or a.chat_cool > 0.0 or _flee > 0.0:
			continue
		for j in range(i + 1, _walkers.size()):
			var b := _walkers[j]
			if b.state != State.WALK or b.chat_cool > 0.0 or a.pos.distance_to(b.pos) > CHAT_REACH:
				continue
			a.chat_cool = CHAT_COOLDOWN
			b.chat_cool = CHAT_COOLDOWN
			if randf() > CHAT_CHANCE:
				continue
			var secs := randf_range(CHAT_FOR.x, CHAT_FOR.y)
			_wait(a, secs, atan2(b.pos.x - a.pos.x, b.pos.y - a.pos.y))
			_wait(b, secs, atan2(a.pos.x - b.pos.x, a.pos.y - b.pos.y))
			a.resume = true
			b.resume = true
			break

func _give_jar(w: Walker) -> void:
	var anchor := w.rig.carry_anchor()
	if anchor == null:
		return
	w.jar = MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 0.17
	m.height = 0.38
	m.radial_segments = 10
	m.rings = 5
	w.jar.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = CLAY
	mat.roughness = 0.85
	w.jar.material_override = mat
	anchor.add_child(w.jar)

# ── Showing them ──────────────────────────────────────────────

func _show(w: Walker) -> void:
	w.node.visible = w.state != State.INSIDE
	if not w.node.visible:
		return
	w.node.position = Vector3(w.pos.x, 0.1 + Terrain.height(w.pos.x, w.pos.y), w.pos.y)
	if w.state == State.WALK and not w.path.is_empty():
		var d: Vector2 = w.path[0] - w.pos
		if d.length_squared() > 0.0001:
			w.rig.hold_yaw = atan2(d.x, d.y)
		_play(w, ("run_down" if _flee > 0.0 else "walk_down"))
	else:
		if not is_nan(w.look_yaw):
			w.rig.hold_yaw = w.look_yaw
		_play(w, "idle_down")

func _play(w: Walker, anim: String) -> void:
	if anim != w.anim:
		w.anim = anim
		w.rig.play(anim)

## Horn: the street stops and looks toward the wall
func heard_horn() -> void:
	if _flee > 0.0:
		return
	for w in _walkers:
		if w.state == State.WALK:
			_wait(w, HORN_LOOK + randf() * 1.5, PI)
			w.resume = true

func _on_breach() -> void:
	if GameState.breaches <= 0:
		return
	_flee = FLEE_TIME
	for w in _walkers:
		if w.state != State.INSIDE:
			w.resume = false
			w.errand = "door"
			w.state = State.WALK
			w.look_yaw = NAN
			w.path = _route(w.pos, _nearest_door(w.pos))

## People who sit out the day on a few roofs of the lower city
func _seat_sitters(rng: RandomNumberGenerator) -> void:
	var layer := get_parent().get_node_or_null("ScatterLayer") as ScatterLayer
	if layer == null:
		return
	var spots := layer.roof_spots.duplicate()
	for i in mini(SITTERS, spots.size()):
		var at: Vector3 = spots.pop_at(rng.randi() % spots.size())
		var kind: String = KINDS[(i + 2) % KINDS.size()]
		var n := Node3D.new()
		add_child(n)
		var rig := CharacterRig.new()
		n.add_child(rig)
		var dye: Color = Palette.DYES[rng.randi() % Palette.DYES.size()]
		rig.setup(Folk.look_for(kind, dye, i + 40), 0.62 if kind == "child" else 0.9)
		rig.set_ring_color(Color(0, 0, 0, 0))
		rig.hold_yaw = PI + rng.randf_range(-0.6, 0.6)   # looking out toward the work
		rig.play("sway_down")
		_sitters.append([n, at])
	_reseat()

func _reseat() -> void:
	Terrain.use_section(GameState.current_section_index)
	for sit: Array in _sitters:
		var at: Vector3 = sit[1]
		(sit[0] as Node3D).position = Vector3(at.x, at.y + Terrain.height(at.x, at.z), at.z)
