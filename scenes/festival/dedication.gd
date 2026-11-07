class_name Dedication
extends Node

# The dedication of the wall (Neh. 12:27-43), in Explore Jerusalem once the whole wall stands.
# At the Valley Gate (12:31, where the two companies set out) Ezra's company waits to go one
# way round the ring and Nehemiah's the other; talk to either leader and the walk begins.
# Both choirs go round on the inside, a stretch at a time, and meet in the house of God at the
# Sheep Gate (12:40), where they rejoice: "the joy of Jerusalem was heard even far away".
#   Ezra's company goes toward -x (Ash Heaps, Fountain, Water, Horse, East, Miphkad Gates)
#   Nehemiah's goes toward +x (Tower of the Ovens, Broad Wall, Jeshanah, Fish Gate)
# The text has them walk ON the wall; here they walk beside it — the wall is not climbable.
# You walk with them: the company waits when you fall behind, and stops at the end of each
# stretch until you go on round. Nothing here is timed. Festival owns the districts and calls
# `district_ready` each time it lays one; the choir is rebuilt at the edge you arrive by.

signal finished

const START      := 5       # the Valley Gate
const ROUTES := [
	[5, 6, 7, 8, 9, 10, 11, 0],   # Ezra's company
	[5, 4, 3, 2, 1, 0],           # Nehemiah's company
]
const LANE_Z     := 7.0     # inside the wall, clear of houses and booths
const STREET_Z   := 14.0    # the street before the temple court's gate (Temple.COURT)
const COURT_AT   := Vector3(Temple.GATE_X, 0.1, 7.0)   # where the leader stands inside the court
const OTHER_AT   := Vector3(Temple.AXIS_X + 0.5, 0.1, 4.2)   # where the other company waits
const SPEED      := 5.2
const WAIT       := 11.0    # you this far behind the leader: the company stands and waits
const TRAIL_STEP := 0.25
const SPACING    := 1.9
const SINGERS    := 5
const CLOSE      := 22.0    # the finale holds this long before the walk is over

const LEADERS := [
	["Ezra, with the first company", "scribe", Palette.MUREX,
		[["Come, the wall is finished. We go round it giving thanks, on the right hand, to the house of God.", "see Neh. 12:31"],
		 ["Follow us round: the Gate of the Ash Heaps, the Fountain Gate, the Water Gate, and on to the temple.", "see Neh. 12:37"]]],
	["Nehemiah, with the second company", "governor", Palette.SAFFRON,
		[["Two great companies, to give thanks and go in procession. Walk with us, the other way round.", "see Neh. 12:31"],
		 ["Over the Tower of the Ovens, the Broad Wall, the Old Gate, the Fish Gate, and so to the house of God.", "see Neh. 12:38-39"]]],
]
const SINGER_LINES := [
	["We keep the dedication with gladness, with thanksgiving and with singing, with cymbals, harps and lyres.", "see Neh. 12:27"],
	["They offered great sacrifices that day and rejoiced.", "see Neh. 12:43"],
	["The women and the children rejoiced too.", "see Neh. 12:43"],
]

var active := false
var done := false
var choir := -1
var step := 0

var _fest: Festival
var _root: Node3D
var _leader: Folk
var _singers: Array[Folk] = []
var _staged: Array = []            # [[leader, singers], [leader, singers]] at the Valley Gate
var _others: Array[Folk] = []      # the company not walked with, walking off its own way
var _trail := PackedVector3Array()
var _path: Array[Vector3] = []
var _heading := Vector3.RIGHT
var _at_end := false
var _hinted := false
var _finale := false
var _finale_t := 0.0
var _finale_goals := {}   # Folk → where they stand in the court, until they get there

func _init(festival: Festival) -> void:
	_fest = festival

## +1 / -1: the way along a stretch's x this company walks
static func way(c: int) -> float:
	return -1.0 if c == 0 else 1.0

## Called by Festival each time it lays a stretch (feast only)
func district_ready(d: int, root: Node3D) -> void:
	_root = root
	_leader = null
	_singers = []
	_others = []
	_staged = []
	_finale = false
	_hinted = false
	if not active:
		if d == START:
			_stage_start()
		return
	var idx: int = ROUTES[choir].find(d)
	if idx < 0:
		return   # off the way: the company waits where you left it
	step = idx
	_spawn_walking(d)

# ── The two companies at the Valley Gate ───────────────────

func _stage_start() -> void:
	for c in 2:
		var row: Array = LEADERS[c]
		var d := way(c)
		# Each company stands on the side it leads off toward, the singers behind: no crossing
		var lead_at := Vector3(d * 6.0, 0.1, LANE_Z)
		var leader := _make(row[0], row[1], row[2], lead_at, row[3], 7 + c)
		leader.halt(lead_at + Vector3(d, 0, 0) * 4.0)
		leader.talked.connect(_on_leader_talked.bind(c))
		var singers: Array[Folk] = []
		for i in SINGERS:
			var s := _singer(c, i, lead_at, d)
			s.halt(lead_at + Vector3(d, 0, 0) * 4.0)
			singers.append(s)
		_staged.append([leader, singers])

func _on_leader_talked(_f: Folk, c: int) -> void:
	if active or _staged.is_empty():
		return
	active = true
	done = false
	choir = c
	step = 0
	_leader = _staged[c][0]
	_singers.assign(_staged[c][1])
	for f: Folk in _staged[1 - c][1]:
		_others.append(f)
	_others.append(_staged[1 - c][0])
	_staged = []
	_begin_trail()
	_set_path(START)
	Sfx.play("tally_land")
	_fest.announce(_fest.tr("The dedication of the wall"),
		_fest.tr("%s  ·  walk with the company round to the house of God") % GameState.short_ref("Neh. 12:31"))
	_fest.refresh_journal()

# ── Walking ────────────────────────────────────────────────

func _spawn_walking(d: int) -> void:
	var w := way(choir)
	var x0 := -w * Festival.ARRIVE_X + w * 4.0   # ahead of you as you arrive
	var at := Vector3(x0, 0.1, LANE_Z)
	if d == ROUTES[choir].back():
		at.z = STREET_Z   # the last stretch comes in along the street
	var row: Array = LEADERS[choir]
	_leader = _make(row[0], row[1], row[2], at, row[3], 7 + choir)
	_singers = []
	for i in SINGERS:
		_singers.append(_singer(choir, i, at, w))
	_begin_trail()
	_set_path(d)

func _singer(c: int, i: int, lead_at: Vector3, w: float) -> Folk:
	var kinds := ["priest", "priest", "priest", "priest", "priest"] if c == 0 else ["priest", "man", "priest", "woman", "man"]
	var back := SPACING * (i / 2 + 1)
	var side := 1.0 if i % 2 == 0 else -1.0
	var at := lead_at + Vector3(-w * back, 0.0, side * 1.25)
	var s := _make("", kinds[i], Palette.DYES[(i + c * 2) % Palette.DYES.size()], at,
		[SINGER_LINES[(i + c) % SINGER_LINES.size()]], 20 + i + c * 7)
	return s

func _make(who: String, kind: String, dye: Color, at: Vector3, lines: Array, seed_i: int) -> Folk:
	var f := Folk.new()
	f.who = who
	f.lines = lines
	f.look = Folk.look_for(kind, dye, seed_i)
	f.position = at
	_root.add_child(f)
	return f

func _begin_trail() -> void:
	_heading = Vector3(way(choir), 0, 0)
	_trail = PackedVector3Array()
	var p := _leader.position
	for k in 40:
		_trail.append(p - _heading * (40 - k) * TRAIL_STEP)
	_trail.append(p)
	_at_end = false

# The leader's way through this stretch: straight along the wall to the far edge — or, in
# the last, along the street to the temple's gate and in
func _set_path(d: int) -> void:
	var w := way(choir)
	_path = []
	if d == ROUTES[choir].back():
		_path.append(Vector3(Temple.GATE_X, 0.1, STREET_Z))
		_path.append(COURT_AT)
	else:
		_path.append(Vector3(w * (Festival.EDGE_X - 2.0), 0.1, _leader.position.z))

func _process(delta: float) -> void:
	for f in _others.duplicate():
		if not is_instance_valid(f):
			_others.erase(f)
			continue
		if f.march_to(Vector3(-way(choir) * (Festival.EDGE_X - 1.0), 0.1, f.position.z), SPEED, delta):
			_others.erase(f)
			f.queue_free()
	if not active or _leader == null or not is_instance_valid(_leader):
		return
	if _finale:
		_finale_t += delta
		for f: Folk in _finale_goals.keys():
			if not is_instance_valid(f):
				_finale_goals.erase(f)
			elif f.march_to(_finale_goals[f], SPEED, delta):
				_finale_goals.erase(f)
				f.halt(Vector3(Temple.AXIS_X, 0.1, Temple.ALTAR_AT.z))   # turned to the house and its altar
				f.rejoice()
		if _finale_t > CLOSE and active:
			_end()
		return
	var me := Player.local
	var behind := 0.0
	if me != null and is_instance_valid(me):
		var to_me := me.global_position - _leader.global_position
		behind = maxf(0.0, -(to_me.x * _heading.x + to_me.z * _heading.z))   # how far behind the leader you are
		if Vector2(to_me.x, to_me.z).length() > WAIT * 3.0:
			behind = maxf(behind, WAIT * 3.0)
	var moving := false
	if not _at_end and behind <= WAIT and not _path.is_empty():
		var target := _path[0]
		var dir := target - _leader.position
		dir.y = 0.0
		if dir.length() > 0.01:
			_heading = dir.normalized()
		if _leader.march_to(target, SPEED, delta):
			_path.remove_at(0)
			if _path.is_empty():
				_at_end = true
		moving = true
		if _trail[_trail.size() - 1].distance_to(_leader.position) >= TRAIL_STEP:
			_trail.append(_leader.position)
	for i in _singers.size():
		var s := _singers[i]
		if not is_instance_valid(s):
			continue
		var goal := _formation(i)
		if moving:
			s.march_to(goal, SPEED * 1.5, delta)
		elif s.march_to(goal, SPEED, delta):
			s.halt(s.position + _heading * 4.0)
	if not moving:
		_leader.halt(_leader.position + _heading * 4.0)
	if _at_end:
		_arrived()

func _formation(i: int) -> Vector3:
	var back := SPACING * (i / 2 + 1)
	var idx := maxi(0, _trail.size() - 1 - int(back / TRAIL_STEP))
	var p := _trail[idx]
	var side := 1.0 if i % 2 == 0 else -1.0
	var perp := Vector3(-_heading.z, 0, _heading.x)
	return p + perp * side * 1.25

# The end of this stretch (wait for you to go on round) — or of the whole way (the court)
func _arrived() -> void:
	if step == ROUTES[choir].size() - 1:
		_start_finale()
	elif not _hinted:
		_hinted = true
		var next: int = ROUTES[choir][step + 1]
		_fest.announce(_fest.tr("On to the %s") % _fest.tr(GameState.SECTIONS[next]["name"]),
			_fest.tr("The company waits at the end of the wall. Walk on round"))

# ── Both companies in the house of God ─────────────────────

func _start_finale() -> void:
	_finale = true
	_finale_t = 0.0
	_finale_goals = {}
	Sfx.play_jingle("won")
	var other := 1 - choir
	var row: Array = LEADERS[other]
	# The other company is already in the court, waiting; ours files in to stand beside it
	var leader := _make(row[0], row[1], row[2], OTHER_AT + Vector3(2.4, 0, -0.8), row[3], 7 + other)
	leader.halt(_leader.position)
	leader.rejoice()
	for i in SINGERS:
		var s := _singer(other, i, OTHER_AT, 0.0)
		s.position = OTHER_AT + Vector3(i * 1.25 - 1.0, 0, 0.9 * (i % 2))
		s.halt(Vector3(Temple.AXIS_X, 0.1, Temple.ALTAR_AT.z))
		s.rejoice()
	_finale_goals[_leader] = Vector3(Temple.GATE_X + 1.0, 0.1, 5.4)
	for i in _singers.size():
		_finale_goals[_singers[i]] = Vector3(Temple.GATE_X - 2.2 + i * 1.25, 0.1, 6.2 + 0.9 * (i % 2))
	_fest.announce(_fest.tr("The joy of Jerusalem was heard far away"),
		_fest.tr("%s  ·  both companies stand in the house of God") % GameState.short_ref("Neh. 12:43"), 6.0)

func _end() -> void:
	active = false
	done = true
	choir = -1
	finished.emit()
