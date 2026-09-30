extends Node3D

# The breakable jars and baskets about the site (Breakable). Laid out per section on
# every peer — the section's own landmarks first (jars by the stalls, bread by the ovens,
# olive baskets under the trees; SectionTerrain.props), then a few loose clusters inside
# the wall and out on the enemy's side. Deterministic from the section index, so only
# "which ones are broken" crosses the network.
#   every peer: pieces rock when a worker or foe brushes past (local, cosmetic)
#   server:     decides what breaks — sword cuts and sling stones (Player / SlingStone
#               call in), dashes (Player reports them), and foes trampling through
#   dawn:       the city puts out fresh ones; broken ones come back whole

const PIECE := preload("res://scenes/breakable/breakable.gd")
const CLUSTERS_IN  := 6
const CLUSTERS_OUT := 3
const AREA         := Rect2(-21.0, -11.0, 42.0, 24.0)   # where loose clusters may go (x,z)
const WALL_CLEAR   := 3.4    # |z| kept free around the wall line and its working strip
const SPOT_CLEAR   := 2.6    # from piles, build sites, the respawn point, heaps
const CLUSTER_GAP  := 3.5
const BRUSH        := 0.35   # past a piece's radius: close enough to rock it
const TRAMPLE      := 0.2    # past a piece's radius: a foe walking through breaks it
const DASH_REACH   := 0.55
const FLOOR_Y      := 0.1    # top of the floor slab (Player.GROUND_Y)
const DASH_WINDOW  := 0.35   # s a reported dash counts for (it lasts 0.14 s, plus lag)

const NEIGHBOUR    := 1.4    # a piece bursting rocks the others this close
const RIM          := 1      # _touching levels: brushing its side …
const CORE         := 2      # … or walked right into it

var _pieces: Array[Breakable] = []
var _dashing := {}   # server: worker node → [msec until, last position]
var _touching := {}  # every peer: piece → {mover: RIM/CORE}, so it rocks as they come on, not while they stand there

@onready var _terrain: Node3D = get_node("../SectionTerrain")

func _ready() -> void:
	add_to_group("breakable_set")
	_terrain.rebuilt.connect(_rebuild)
	GameState.phase_changed.connect(_on_phase_changed)
	_rebuild()

func _on_phase_changed(phase: GameState.Phase) -> void:
	if phase == GameState.Phase.DAWN:
		for p in _pieces:
			if p.broken:
				p.restore()

func _rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_pieces.clear()
	_touching.clear()
	var index := GameState.current_section_index
	var rng := RandomNumberGenerator.new()
	rng.seed = 7000 + index
	for prop: Array in _terrain.props:
		var at: Vector3 = prop[1]
		if _free(Vector2(at.x, at.z), 0.0, 3.0):
			_place(prop[0], at, rng)
	var centres: Array[Vector2] = []
	_clusters(centres, CLUSTERS_IN, true, rng)
	_clusters(centres, CLUSTERS_OUT, false, rng)

# A few jars and baskets set down together, the way a household leaves them
func _clusters(centres: Array[Vector2], count: int, inside: bool, rng: RandomNumberGenerator) -> void:
	var made := 0
	var tries := 0
	while made < count and tries < 200:
		tries += 1
		var c := Vector2(rng.randf_range(AREA.position.x, AREA.end.x),
			rng.randf_range(WALL_CLEAR, AREA.end.y) if inside else rng.randf_range(AREA.position.y, -WALL_CLEAR))
		if not _free(c, 1.0) or centres.any(func(o: Vector2) -> bool: return o.distance_to(c) < CLUSTER_GAP):
			continue
		centres.append(c)
		made += 1
		var n := rng.randi_range(2, 4)
		var a0 := rng.randf() * TAU
		for i in n:
			var at := c
			if i > 0:
				at += Vector2.RIGHT.rotated(a0 + TAU * i / n) * rng.randf_range(0.55, 0.75)
			if not _free(at, 0.3):
				continue
			var roll := rng.randf()
			# Outside: what the olive pickers and water carriers left; inside, more jars
			var kind := "basket" if roll < (0.45 if not inside else 0.25) else "store" if roll > 0.8 else "jar"
			_place(kind, Vector3(at.x, 0.0, at.y), rng)

func _free(p: Vector2, pad: float, wall_clear := WALL_CLEAR) -> bool:
	if absf(p.y) < wall_clear or _terrain.blocks(p, pad):
		return false
	for k: Vector2 in _terrain.keep_clear():
		if k.distance_to(p) < SPOT_CLEAR:
			return false
	for post: Node3D in get_tree().get_nodes_in_group("watch_posts"):
		if Vector2(post.global_position.x, post.global_position.z).distance_to(p) < SPOT_CLEAR:
			return false
	return true

func _place(kind: String, at: Vector3, rng: RandomNumberGenerator) -> void:
	var piece := PIECE.new() as Breakable
	piece.setup(kind, rng.randi())
	piece.position = Vector3(at.x, FLOOR_Y, at.z)
	add_child(piece)
	_pieces.append(piece)

# ── Every peer: brushed past ──────────────────────────────────

func _physics_process(_delta: float) -> void:
	var movers: Array[Node] = get_tree().get_nodes_in_group("players")
	movers.append_array(get_tree().get_nodes_in_group("enemies"))
	var server := multiplayer.is_server()
	for piece in _pieces:
		if piece.broken:
			continue
		var at := piece.global_position
		var was: Dictionary = _touching.get(piece, {})
		var now := {}
		for m: Node3D in movers:
			var d := Vector2(m.global_position.x - at.x, m.global_position.z - at.z).length()
			if d > piece.radius() + BRUSH:
				continue
			if server and d < piece.radius() + TRAMPLE and m.is_in_group("enemies"):
				_break(piece, at - m.global_position)
				break
			now[m] = CORE if d < piece.radius() else RIM
			if now[m] > was.get(m, 0):
				piece.nudge(m.global_position, now[m] == CORE)
		if now.is_empty():
			_touching.erase(piece)
		else:
			_touching[piece] = now
	if server:
		_check_dashes()

# ── Server: what breaks ───────────────────────────────────────

## Server (Player): a worker just dashed; anything they run through breaks
func note_dash(worker: Node3D) -> void:
	_dashing[worker] = [Time.get_ticks_msec() + int(DASH_WINDOW * 1000.0), worker.global_position]

func _check_dashes() -> void:
	var now := Time.get_ticks_msec()
	for w: Node3D in _dashing.keys():
		var entry: Array = _dashing[w]
		if not is_instance_valid(w) or now > entry[0]:
			_dashing.erase(w)
			continue
		var from: Vector3 = entry[1]
		var to := w.global_position
		entry[1] = to
		# Along the whole stretch covered since last frame, so a fast dash can't skip one
		for piece in _pieces:
			if piece.broken:
				continue
			var p := piece.global_position
			var on := Geometry3D.get_closest_point_to_segment(Vector3(p.x, 0, p.z), Vector3(from.x, 0, from.z), Vector3(to.x, 0, to.z))
			if on.distance_to(Vector3(p.x, 0, p.z)) < piece.radius() + DASH_REACH:
				_break(piece, to - from)

## Server (SlingStone): a stone came down at `at`
func smash_at(at: Vector3, reach: float) -> bool:
	var hit := false
	for piece in _pieces:
		if not piece.broken and _flat(piece.global_position - at).length() < reach + piece.radius():
			_break(piece, piece.global_position - at)
			hit = true
	return hit

## Server (Player): a sword cut from `at` facing `fwd` (flat), `reach` long, ±`arc_deg`
func smash_arc(at: Vector3, fwd: Vector2, reach: float, arc_deg: float) -> bool:
	var hit := false
	for piece in _pieces:
		if piece.broken:
			continue
		var to := Vector2(piece.global_position.x - at.x, piece.global_position.z - at.z)
		if to.length() - piece.radius() > reach:
			continue
		if to.length() > piece.radius() and absf(fwd.angle_to(to)) > deg_to_rad(arc_deg):
			continue
		_break(piece, Vector3(to.x, 0.0, to.y))
		hit = true
	return hit

## Nearest whole piece within `reach` of `at`, or null (Player: is there one to cut at)
func piece_in_reach(at: Vector3, reach: float) -> Breakable:
	var best: Breakable = null
	var best_d := reach
	for piece in _pieces:
		if piece.broken:
			continue
		var d := _flat(piece.global_position - at).length() - piece.radius()
		if d < best_d:
			best_d = d
			best = piece
	return best

func _break(piece: Breakable, dir: Vector3) -> void:
	if piece.broken:
		return
	_smashed.rpc(_pieces.find(piece), _flat(dir))

@rpc("authority", "call_local", "reliable")
func _smashed(i: int, dir: Vector3) -> void:
	if i < 0 or i >= _pieces.size():
		return
	var gone := _pieces[i]
	gone.smash(dir)
	_touching.erase(gone)
	# The ones standing with it rock at the burst
	for p in _pieces:
		if p != gone and _flat(p.global_position - gone.global_position).length() < NEIGHBOUR:
			p.nudge(gone.global_position, true)

## Server: a late joiner sees what's already broken (after GameState, so the section matches)
func send_state_to(peer_id: int) -> void:
	var broken := PackedInt32Array()
	for i in _pieces.size():
		if _pieces[i].broken:
			broken.append(i)
	if not broken.is_empty():
		_sync_broken.rpc_id(peer_id, broken)

@rpc("authority", "reliable")
func _sync_broken(broken: PackedInt32Array) -> void:
	for i in broken:
		if i < _pieces.size():
			_pieces[i].smash(Vector3.ZERO, true)

static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
