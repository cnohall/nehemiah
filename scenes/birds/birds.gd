extends Node3D

# Sparrows, doves, pigeons and a raven about the site (Bird). Flocks land on open ground each side of
# the wall, laid out per section from the section index, and live on each peer alone:
# nothing crosses the network, as everything that puts them up already runs everywhere.
#   put up by:  a worker walking into them, a foe coming on (so the flocks outside
#               lift before the enemy is at the wall), and loud things — a dash, a
#               sword swing, a jar breaking, the horn, a breach (Sfx.STARTLES → startle)
#   return:     once it has been quiet about their spot for a while
#   evening:    as the lamps come on (DayLight.lamps) they go to roost, back at dawn

const BIRD := preload("res://scenes/birds/bird.gd")
const FLOCKS_IN  := 1
const FLOCKS_OUT := 1
const AREA_X     := 20.0
const AREA_Z     := Vector2(4.0, 12.5)   # |z| band each side of the wall line
const SPOT_CLEAR := 2.0     # from piles, build sites, the respawn point, heaps
const FLOCK_GAP  := 6.0
const FLOCK_R    := 1.0     # how far a flock's birds sit from its centre
const FLOOR_Y    := 0.1     # top of the floor slab (Player.GROUND_Y)

const WALK_REACH  := 1.8    # past FLOCK_R: a worker walking this close puts them up
const FOE_REACH   := 6.0    # … a foe coming on (a dash is loud: Sfx.STARTLES)
const TOWARD_CAMERA := Vector3(0.7071, 0.0, 0.7071)   # screen-down on the ground (Main's camera)
const CHAIN_REACH := 5.0    # a flock going up puts up others this close
const QUIET_TIME  := Vector2(12.0, 22.0)   # s of calm before they come back
const CALM_PLAYER := 4.5    # nobody this close to the spot …
const CALM_FOE    := 9.0    # … and no foe this close, or the calm starts over
const ROOST_AT    := 0.6    # DayLight.lamps: past this they go to roost
const WAKE_BELOW  := 0.3    # … and don't come back until it's under this

var _flocks: Array[Dictionary] = []   # {spot, kind, birds, away, quiet, call}

@onready var _terrain: Node3D = get_node("../SectionTerrain")
@onready var _light: Node = get_node_or_null("../DayLight")

func _ready() -> void:
	add_to_group("bird_set")
	_terrain.rebuilt.connect(_rebuild)
	GameState.phase_changed.connect(_on_phase_changed)
	_rebuild()

func _on_phase_changed(phase: GameState.Phase) -> void:
	if phase == GameState.Phase.DAWN:
		for f in _flocks:
			if f.away:
				f.quiet = randf_range(1.0, 5.0)

func _rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_flocks.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9000 + GameState.current_section_index
	_lay_out(FLOCKS_IN, 1.0, rng)
	_lay_out(FLOCKS_OUT, -1.0, rng)

func _lay_out(count: int, side: float, rng: RandomNumberGenerator) -> void:
	var made := 0
	var tries := 0
	while made < count and tries < 200:
		tries += 1
		var c := Vector2(rng.randf_range(-AREA_X, AREA_X), side * rng.randf_range(AREA_Z.x, AREA_Z.y))
		if not _free(c) or _flocks.any(func(f: Dictionary) -> bool: return _flat(f.spot).distance_to(c) < FLOCK_GAP):
			continue
		made += 1
		# The city flock mixes warm doves and grey pigeons; sparrows and one
		# larger raven gather outside the wall.
		var kind := "dove" if side > 0.0 else "sparrow"
		var flock := { "spot": Vector3(c.x, FLOOR_Y, c.y), "kind": kind, "birds": [],
			"away": false, "quiet": 0.0, "call": rng.randf_range(1.0, 6.0) }
		var n := rng.randi_range(2, 3) if kind == "dove" else rng.randi_range(3, 5)
		for i in n:
			var at := c + Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(0.0, FLOCK_R)
			var bird := BIRD.new() as Bird
			var look := kind
			if kind == "dove" and i % 2 == 0:
				look = "pigeon"
			elif kind == "sparrow" and i == 0:
				look = "raven"
			bird.setup(look, Vector3(at.x, FLOOR_Y, at.y))
			add_child(bird)
			flock.birds.append(bird)
		_flocks.append(flock)

func _free(p: Vector2) -> bool:
	if _terrain.blocks(p, FLOCK_R + 0.5):
		return false
	for k: Vector2 in _terrain.keep_clear():
		if k.distance_to(p) < SPOT_CLEAR + FLOCK_R:
			return false
	for post: Node3D in get_tree().get_nodes_in_group("watch_posts"):
		if _flat(post.global_position).distance_to(p) < SPOT_CLEAR + FLOCK_R:
			return false
	return true

# ── Every peer ────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	var players := get_tree().get_nodes_in_group("players")
	var foes := get_tree().get_nodes_in_group("enemies")
	var lamps := _lamps()
	for f in _flocks:
		var spot := _flat(f.spot)
		if f.away:
			_wait(f, spot, players, foes, lamps, delta)
			continue
		if lamps > ROOST_AT:
			_put_up(f, f.spot + Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU), false)
			continue
		var from: Variant = null
		for m: Node3D in players:
			if _flat(m.global_position).distance_to(spot) - FLOCK_R < WALK_REACH:
				from = m.global_position
				break
		if from == null:
			for e: Node3D in foes:
				if _flat(e.global_position).distance_to(spot) - FLOCK_R < FOE_REACH:
					from = e.global_position
					break
		if from != null:
			_put_up(f, from)
			continue
		f.call -= delta
		if f.call <= 0.0:
			f.call = randf_range(2.5, 7.0) if f.kind == "sparrow" else randf_range(7.0, 14.0)
			Sfx.play("chirp" if f.kind == "sparrow" else "coo", f.spot)

# Away: count down the calm, then bring them back in
func _wait(f: Dictionary, spot: Vector2, players: Array, foes: Array, lamps: float, delta: float) -> void:
	if not f.birds.all(func(b: Bird) -> bool: return b.state == Bird.State.AWAY):
		return   # still climbing out of sight
	var calm := lamps < WAKE_BELOW
	for m: Node3D in players:
		if _flat(m.global_position).distance_to(spot) < CALM_PLAYER:
			calm = false
	for e: Node3D in foes:
		if _flat(e.global_position).distance_to(spot) < CALM_FOE:
			calm = false
	if not calm:
		f.quiet = maxf(f.quiet, randf_range(QUIET_TIME.x, QUIET_TIME.y) * 0.5)
		return
	f.quiet -= delta
	if f.quiet > 0.0:
		return
	f.away = false
	f.call = randf_range(3.0, 6.0)
	var c := _flat(f.spot)
	for b: Bird in f.birds:
		var at := c + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(0.0, FLOCK_R)
		b.come_back(Vector3(at.x, f.spot.y, at.y), randf_range(0.0, 1.5))

## Sfx (via group "bird_set"): something loud at `at` (null or reach 0 = heard site-wide)
func startle(at: Variant, reach: float) -> void:
	for f in _flocks:
		if f.away:
			continue
		if at == null or reach <= 0.0:
			_put_up(f, f.spot + Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU))
		elif _flat(at).distance_to(_flat(f.spot)) - FLOCK_R < reach:
			_put_up(f, at)

# Off they go, away from `from`; the burst of wings may put up the flocks nearby
func _put_up(f: Dictionary, from: Vector3, chain := true) -> void:
	f.away = true
	f.quiet = randf_range(QUIET_TIME.x, QUIET_TIME.y)
	var away := _across_screen(f.spot - from)
	for b: Bird in f.birds:
		b.flush(away.rotated(Vector3.UP, randf_range(-0.5, 0.5)), randf_range(0.0, 0.18))
	Sfx.play("wings", f.spot)
	if not chain:
		return
	for g in _flocks:
		if not g.away and _flat(g.spot).distance_to(_flat(f.spot)) < CHAIN_REACH:
			_put_up(g, f.spot)

# Flying straight at the camera while climbing, a bird just hangs on screen: turn that
# part of the flight aside so they're seen to go
static func _across_screen(dir: Vector3) -> Vector3:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() < 0.0001:
		d = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	d = d.normalized()
	var toward := d.dot(TOWARD_CAMERA)
	if toward <= 0.0:
		return d
	var side := d - TOWARD_CAMERA * toward
	if side.length_squared() < 0.04:
		side = TOWARD_CAMERA.cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
	return side.normalized()

func _lamps() -> float:
	return _light.lamps if _light else 0.0

static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
