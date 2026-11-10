extends Node

# Server-only. Streams enemies in while a day's WORK phase is running (DayDirector
# calls start/stop). Spawned enemies replicate to clients via Main/EnemySpawner.

const ENEMY_SCENE := preload("res://scenes/enemy/enemy.tscn")
const MESSENGER_SCENE := preload("res://scenes/messenger/messenger.tscn")

const SPAWN_Z             := -14.0   # outside, north of wall
const SPAWN_X_HALF        := 18.0
const FIRST_SPAWN_DELAY   := 4.0
const INTERVAL_DAY1       := 7.0     # seconds between spawns on day 1…
const INTERVAL_DAY52      := 2.0     # …tightening linearly to day 52
const INTERVAL_JITTER     := 0.3
const MAX_ALIVE_BASE      := 5
const MAX_ALIVE_CAP       := 24      # also a performance ceiling
const BRUTE_UNLOCK_DAY    := 7      # first brute on day 8, the Fish Gate's last: a new foe once the stretch's lesson is known
const RAIDER_UNLOCK_DAY   := 16     # first raider on day 17, the Broad Wall's last
const MID_BRUTE_CHANCE    := 0.25    # P(brute) days 9–20; rest scout
# Late-game spawn weights: 45% scout, 25% brute, 30% raider
const LATE_SCOUT_CAP      := 0.45
const LATE_BRUTE_CAP      := 0.70
# "horn" twist (Valley Gate): the enemy comes up the valley in surges — a warning, then a
# pack at one spot — over a thinner trickle
const SURGE_FIRST         := 14.0
const SURGE_EVERY         := 24.0
const SURGE_WARN          := 3.5     # pointer + bell before the pack appears
const SURGE_SPREAD        := 1.8
const SURGE_GAP           := 0.35    # seconds between members of one pack
const SURGE_TRICKLE_MULT  := 1.8     # the steady stream thins out between surges
const SURGE_COLOR         := Color(0.86, 0.38, 0.26)
# Waves everywhere else (GameState.waves, GDD §5.6): the same warn-then-pack rhythm,
# gentler and further apart than the valley's surges. Pack size grows with the day and
# the crew; from WAVE_SPLIT_DAY a wave comes at two places at once. Tuned so trickle +
# waves bring about as many enemies as the plain trickle did — the change is rhythm.
const WAVE_FIRST          := 18.0
const WAVE_EVERY_DAY1     := 38.0
const WAVE_EVERY_DAY52    := 26.0
const WAVE_WARN           := 5.0     # long enough to stock a watch post or take up a sling
const WAVE_BASE           := 2
const WAVE_PER_DAYS       := 10.0    # one more in each pack every 10 days…
const WAVE_PER_CREW       := 2       # …and one more for every two workers past the first
const WAVE_SPREAD         := 3.0
const WAVE_SPLIT_DAY      := 21
const WAVE_TRICKLE_MULT   := 2.0
# Experimental (GDD §5.21): forecast the pack this long before its bell; calling it early
# pulls the bell forward and spurs the crew (GameState.SPUR_*)
const FORECAST_LEAD       := 22.0
const CALL_EARLY_MIN      := 12.0    # a call this close to the bell isn't worth a spur
# The forecast's route (Thronefall's night paths): dashes from the ring to just inside the
# wall, drawn out from the spot, and the pack's count over where it meets the wall
const ROUTE_END_Z         := 3.0
const ROUTE_DASH          := 0.9     # metres from one dash to the next
const ROUTE_FROM_RING     := 3.8     # the first dash just outside the ring (radius 3.5 m)
const ROUTE_DRAW_TIME     := 1.4
const ROUTE_TAG_Z         := -3.0    # the count stands on the route here, outside the wall

# "schemes" twist: messengers to Ono, "four times" a day (Neh. 6:4), one at a time
const MESSENGER_FIRST     := 12.0
const MESSENGER_EVERY     := 24.0
const MESSENGERS_PER_DAY  := 4
# …and between them, now and then, a neighbour from the villages with a warning (4:12, GDD
# §6.7): never the day's first visitor, never two in a row, at most two a day
const NEIGHBOUR_CHANCE    := 0.34
const NEIGHBOURS_PER_DAY  := 2

# Saboteur (GDD §5.9): comes quietly with the trickle, never in a pack, on his own timer.
# One at a time through day 20; from day 21, two with a crew of three or more. Only from the
# Water Gate: the torch that answers him is that stretch's own lesson.
# Not scaled by section pressure; difficulty's pace scales the interval.
const SABOTEUR_SECTION    := 8       # the Water Gate (night)
const SABOTEUR_FIRST      := 22.0
const SABOTEUR_EVERY      := 50.0
const SABOTEUR_PAIR_DAY   := 21

# Waves v2 (Nov 2026, GDD §5.27): no trickle. Every foe comes in a warned pack, so the
# quiet between packs is real building time and each pack is an event. A pack carries
# the foes the trickle would have sent over its cycle. Packs run in threes through the
# day (lull, build, peak), each has a shape the watch names (what to do, not only that
# something comes), and raising a unit brings the next one sooner (Neh. 4:7, "they heard
# that the repairing… went forward"). A section beat takes the place of the next wave.
# `-- --old-waves`: the trickle and the plain clock as before, to A/B.
var old_waves: bool = "--old-waves" in OS.get_cmdline_user_args()
const ARC                 := [0.75, 1.0, 1.3]   # lull, build, peak
const PROGRESS_PULL       := 9.0     # a unit raised brings the next pack this much sooner…
const PULL_FLOOR          := 9.0     # …but never inside this (the bell's 5 s plus a breath)
const BEAT_PUSH           := 20.0    # a section beat's pack: the next wave waits at least this
# Shape → [size factor, seconds between members]. Scouts are slight, so a rush is many;
# brutes and raiders are heavy, so fewer
const SHAPES := {
	"wave":   [1.0, 0.35],
	"rush":   [1.25, 0.2],
	"pincer": [1.0, 0.35],
	"ram":    [0.7, 0.6],
	"raid":   [0.8, 0.35],
}
const SHAPE_NAMES := { "wave": "Wave", "rush": "Rush", "pincer": "Pincer", "ram": "Ram", "raid": "Raid" }
const RAM_X               := 3.0     # a ram comes straight at the gate
const RUSH_X_MIN          := 8.0     # a rush comes round one end

@onready var enemies_root: Node3D = get_parent().get_node("Enemies")
@onready var players_root: Node3D = get_parent().get_node("Players")
@onready var visitors_root: Node3D = get_parent().get_node("Visitors")

var _active := false
var _day := 1
var _timer := 0.0
var _msg_timer := 0.0
var _surge_timer := 0.0
var _surge_at: Array[Vector3] = []   # where the warned pack(s) will come in
var _surge_left := 0       # members of the current pack still to come
var _surge_gap := 0.0
var _msg_sent := 0          # Sanballat's men today (the four, then the letter)
var _nb_sent := 0           # neighbours today
var _last_neighbour := false
var _warned_early := false  # a neighbour already told where the next pack comes in
var _sab_timer := 0.0
var _pack: Array[int] = []   # the forecast pack's types, spawned as told
var _forecasted := false
var _forecast_marks: Array[Node] = []   # every peer: ring, route, tag of the told wave
var _demo_brute := false   # demo: the day's first brute has been sent
var _shape := "wave"        # the coming pack's shape (v2)
var _last_shape := ""
var _wave_no := 0           # packs sent today: its place in the arc
var _last_done := 0         # units standing when last looked (progress pull)
var trickled := 0           # foes the trickle sent (tests: v2 must send none)


func _ready() -> void:
	GameState.progress_changed.connect(_on_progress)

func start(day: int) -> void:
	if GameState.free_play():
		return   # no enemy at the festival
	_day = day
	_active = true
	_timer = FIRST_SPAWN_DELAY
	_msg_timer = MESSENGER_FIRST
	_surge_timer = SURGE_FIRST if GameState.has_twist("horn") else WAVE_FIRST
	_surge_left = 0

	_msg_sent = 0
	_nb_sent = 0
	_last_neighbour = false
	_warned_early = false
	_pack.clear()
	_forecasted = false
	_demo_brute = false
	_sab_timer = SABOTEUR_FIRST
	_shape = "wave"
	_last_shape = ""
	_wave_no = 0
	_last_done = GameState.targets_done

func stop() -> void:
	_active = false

## v2: packs carry every foe (no trickle), unless waves are off altogether
func packs_only() -> bool:
	return not old_waves and (GameState.waves or GameState.has_twist("horn"))

func _physics_process(delta: float) -> void:
	if not _active or not multiplayer.is_server():
		return
	_tick_messengers(delta)
	_tick_saboteurs(delta)
	_tick_surges(delta)
	if packs_only() and not _demo_brute_due():   # the demo's brute still walks in alone, early
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = _interval()
	if enemies_root.get_child_count() < _max_alive():
		trickled += 1
		_do_spawn(_pick_type())

# ── Pacing ─────────────────────────────────────────────────

func _interval() -> float:
	return _base_interval() * randf_range(1.0 - INTERVAL_JITTER, 1.0 + INTERVAL_JITTER)

## The trickle's mean gap between foes (v2 never runs it, but sizes packs by it)
func _base_interval() -> float:
	var t := (_day - 1) / float(GameState.TOTAL_DAYS - 1)
	var base := lerpf(INTERVAL_DAY1, INTERVAL_DAY52, t)
	# More workers → more pressure (1 player ×1.3 … 4 players ×0.68)
	base *= 1.3 / (0.7 + 0.3 * _crew())
	base /= _pressure()
	if GameState.has_twist("horn"):
		base *= SURGE_TRICKLE_MULT
	elif GameState.waves:
		base *= WAVE_TRICKLE_MULT
	return base

## v2: the foes the old trickle sent over `cycle` seconds (it was held to _max_alive)
func _trickle_share(cycle: float) -> float:
	return cycle / _base_interval()

## Seconds from one wave to the next (not the valley's surges)
func _wave_every() -> float:
	return lerpf(WAVE_EVERY_DAY1, WAVE_EVERY_DAY52, (_day - 1) / float(GameState.TOTAL_DAYS - 1))


## Per-section pace (breather / finale) times the host's difficulty
func _pressure() -> float:
	return GameState.pressure() * Settings.diff()["pace"]

## Workers the enemy is sized to: a person counts whole, a bot by its skill's "crew"
func _crew() -> float:
	var n := 0.0
	for p in players_root.get_children():
		n += p.brain.skill["crew"] if p.brain != null else 1.0
	return maxf(1.0, n)


func _max_alive() -> int:
	return mini(MAX_ALIVE_CAP, roundi((MAX_ALIVE_BASE + floori(_day / 3.0)) * _pressure()))

func _pick_type() -> Enemy.Type:
	# Demo: the last day must show the first brute, not leave it to the 25% roll
	if GameState.is_demo() and _day == GameState.DEMO_LAST_DAY and not _demo_brute:
		_demo_brute = true
		return Enemy.Type.BRUTE
	if _day <= BRUTE_UNLOCK_DAY:
		return Enemy.Type.SCOUT
	if _day <= RAIDER_UNLOCK_DAY:
		return Enemy.Type.BRUTE if randf() < MID_BRUTE_CHANCE else Enemy.Type.SCOUT
	var roll := randf()
	if roll < LATE_SCOUT_CAP:
		return Enemy.Type.SCOUT
	if roll < LATE_BRUTE_CAP:
		return Enemy.Type.BRUTE
	return Enemy.Type.RAIDER

# Valley Gate surges ("horn") or, everywhere else, waves: a warning, then a pack from
# the warned spot(s), one after another
func _tick_surges(delta: float) -> void:
	var horn := GameState.has_twist("horn")
	if not horn and not GameState.waves:
		return
	if _surge_left > 0:
		_surge_gap -= delta
		if _surge_gap <= 0.0:
			_surge_gap = SHAPES[_shape][1] if packs_only() and not horn else SURGE_GAP
			_surge_left -= 1
			if _surge_left == 0:
				_pack.clear()   # a pack the cap held back must not leak into the next
			if _surge_at.is_empty():   # never warned (can't happen in play; be safe)
				_surge_at.append(Vector3(randf_range(-SPAWN_X_HALF, SPAWN_X_HALF), 0.1, SPAWN_Z))
			if enemies_root.get_child_count() < MAX_ALIVE_CAP:
				var spread := SURGE_SPREAD if horn else WAVE_SPREAD
				var off := Vector3(randf_range(-spread, spread), 0, randf_range(-1.0, 1.0))
				_do_spawn(_next_type(), _surge_at[_surge_left % _surge_at.size()] + off)
		return
	var warn := SURGE_WARN if horn else WAVE_WARN
	var was := _surge_timer
	_surge_timer -= delta
	if _forecast_on() and not horn and not _forecasted and _surge_timer <= FORECAST_LEAD:
		_forecast()
	if was > warn and _surge_timer <= warn:
		if not _warned_early:
			_pick_surge_spots(horn)
		for at in _surge_at:
			_warn_surge.rpc(at, horn, warn, _shape_label())
	elif _surge_timer <= 0.0:
		_surge_gap = 0.0
		_warned_early = false
		_forecasted = false
		if horn:
			var n: float = (3 + floori(_day / 12.0)) * Settings.diff()["pace"]
			if packs_only():
				n += _trickle_share(SURGE_EVERY / _pressure())
			_surge_left = clampi(roundi(n), 1, MAX_ALIVE_CAP)
			_surge_timer = SURGE_EVERY / _pressure()
		else:
			_surge_left = _pack.size() if not _pack.is_empty() else _wave_size()   # as forecast, even if the crew changed since
			_surge_timer = _wave_every()
		_wave_no += 1
		_last_shape = _shape

func _wave_size() -> int:
	var n: float = (WAVE_BASE + floori(_day / WAVE_PER_DAYS) + floori((_crew() - 1.0) / WAVE_PER_CREW)) * _pressure()
	if not packs_only():
		return roundi(n)
	n += _trickle_share(_wave_every())
	n *= ARC[_wave_no % ARC.size()] * SHAPES[_shape][0]
	return clampi(roundi(n), 1, _max_alive())

## The next member of the pack: as forecast, or rolled now (`i` counts down to 0)
func _next_type() -> Enemy.Type:
	return _pack.pop_back() if not _pack.is_empty() else _shape_type(_surge_left)

## v2: one member of a pack of the coming shape. Rush = scouts; ram = brutes with scouts
## to screen them; raid = raiders with a scout. Wave and pincer: the day's usual mix.
## Old waves and the valley's surges: always the usual mix.
func _shape_type(i: int) -> Enemy.Type:
	if not packs_only() or GameState.has_twist("horn") or _demo_brute_due():
		return _pick_type()
	match _shape:
		"rush":
			return Enemy.Type.SCOUT
		"ram":
			return Enemy.Type.BRUTE if i % 3 != 2 else Enemy.Type.SCOUT
		"raid":
			return Enemy.Type.RAIDER if i % 3 != 2 else Enemy.Type.SCOUT
	return _pick_type()

func _demo_brute_due() -> bool:
	return GameState.is_demo() and _day == GameState.DEMO_LAST_DAY and not _demo_brute

## v2: the coming pack's shape, from those the day allows: never the same twice running,
## and the peak of each three the heaviest the day has
func _roll_shape() -> void:
	var can: Array[String] = ["wave"]
	if _day >= 2:
		can.append("rush")
	if GameState.current_section_index >= 1:
		can.append("pincer")
	if _day > BRUTE_UNLOCK_DAY:
		can.append("ram")
	if _day > RAIDER_UNLOCK_DAY:
		can.append("raid")
	if can.size() > 1:
		can.erase(_last_shape)
	var peak := _wave_no % ARC.size() == ARC.size() - 1
	_shape = can[can.size() - 1] if peak else can[randi() % can.size()]

## v2, server: the work went forward. Each unit raised brings the next pack sooner; a pack
## already told is told again with its new time
func _on_progress(done: int, _total: int) -> void:
	if not _active or not multiplayer.is_server() or not packs_only():
		_last_done = done
		return
	var raised := done - _last_done
	_last_done = done
	if raised <= 0 or _surge_left > 0 or _surge_timer <= PULL_FLOOR:
		return
	_surge_timer = maxf(PULL_FLOOR, _surge_timer - PROGRESS_PULL * raised)
	if _forecasted:
		_tell_forecast(false)

## Server (SectionBeats): a beat's pack is coming, so the next wave stands back: one pack
## at a time, and the beat counts as the peak
func beat_taken() -> void:
	if not _active or not packs_only() or _surge_left > 0:
		return
	if _surge_timer < BEAT_PUSH:
		_surge_timer = BEAT_PUSH
		if _forecasted:
			_tell_forecast(false)
	if not GameState.has_twist("horn"):
		_wave_no = 0   # the next wave starts a new three, from the lull

# ── Experimental: forecast and call early (GDD §5.21) ──────

## The host's forecast setting: Solo counts the people playing (bots aside)
func _forecast_on() -> bool:
	match Settings.exp_forecast:
		Settings.FORECAST_ALWAYS:
			return true
		Settings.FORECAST_SOLO:
			return players_root.get_children().filter(func(p): return p.brain == null).size() == 1
	return false

## Server: roll the coming pack and its spots now and tell every peer what and where
func _forecast() -> void:
	_forecasted = true
	if not _warned_early:
		_pick_surge_spots(false)
		_warned_early = true
	_pack.clear()
	for i in _wave_size():
		_pack.append(_shape_type(i))
	_tell_forecast(false)

func _tell_forecast(called: bool) -> void:
	var counts := [0, 0, 0]
	for t: int in _pack:
		counts[t] += 1
	var routes := []
	for at in _surge_at:
		routes.append(_route(at))
	_show_forecast.rpc(_surge_at.duplicate(), routes, counts, _surge_timer, called, _shape_label())

## What the watch calls the coming pack: its shape (v2), else just a wave
func _shape_label() -> String:
	return SHAPE_NAMES[_shape] if packs_only() else "Wave"

## Server: the way the pack will walk, from its spot to just inside the wall. Most of a
## pack heads for the stockpiles (Enemy._goal) through whatever gap the nav mesh leaves
func _route(at: Vector3) -> PackedVector3Array:
	var goal := Vector3(clampf(at.x, -Enemy.GOAL_X_SPREAD, Enemy.GOAL_X_SPREAD), 0.0, Enemy.GOAL_Z)
	var path := PackedVector3Array()
	var map := enemies_root.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) != 0:
		path = NavigationServer3D.map_get_path(map, NavigationServer3D.map_get_closest_point(map, at),
			NavigationServer3D.map_get_closest_point(map, goal), true)
	if path.size() < 2:
		path = PackedVector3Array([at, goal])   # not baked (tests): straight at it
	var out := PackedVector3Array([path[0]])
	for i in range(1, path.size()):
		var a := out[out.size() - 1]
		if path[i].z <= ROUTE_END_Z:
			out.append(path[i])
			continue
		out.append(a.lerp(path[i], clampf((ROUTE_END_Z - a.z) / maxf(0.001, path[i].z - a.z), 0.0, 1.0)))
		break
	return out

## Server: a worker calls the next wave in. False when it isn't allowed or isn't worth it.
func call_early() -> bool:
	if not _active or not Settings.exp_call_early or GameState.simplified() or GameState.has_twist("horn") or not GameState.waves 			or _surge_left > 0 or _surge_timer < CALL_EARLY_MIN:
		return false
	_surge_timer = WAVE_WARN + 0.01
	if not _forecasted:
		_forecast()
	else:
		_tell_forecast(true)
	_spur.rpc()
	return true

@rpc("authority", "call_local", "reliable")
func _spur() -> void:
	GameState.spur_until = Time.get_ticks_msec() + int(GameState.SPUR_SECONDS * 1000.0)

@rpc("authority", "call_local", "reliable")
func _show_forecast(spots: Array, routes: Array, counts: Array, seconds: float, called: bool, shape := "Wave") -> void:
	var parts: PackedStringArray = []
	if counts[0] > 0:
		parts.append(tr_n("%d scout", "%d scouts", counts[0]) % counts[0])
	if counts[1] > 0:
		parts.append(tr_n("%d brute", "%d brutes", counts[1]) % counts[1])
	if counts[2] > 0:
		parts.append(tr_n("%d raider", "%d raiders", counts[2]) % counts[2])
	var pack := ", ".join(parts)
	if shape != "Wave":
		pack = "%s: %s" % [tr(shape), pack]
	var what := pack + (tr(" · the crew is spurred") if called else "")
	get_tree().call_group("forecast_chip", "show_forecast", what, seconds, called)
	# A wave called early is told again: its marks replace the first ones
	for n in _forecast_marks:
		if is_instance_valid(n):
			n.queue_free()
	_forecast_marks.clear()
	for i in spots.size():
		_forecast_marks.append(_ring_spot(spots[i], seconds + 3.0))
		if i < routes.size() and routes[i].size() >= 2:
			_forecast_marks.append(_draw_route(routes[i], seconds + 3.0))
			# Split waves: each spot's count is a share of the pack, so the tag only on one
			if spots.size() == 1:
				_forecast_marks.append(_route_tag(routes[i], pack, seconds + 3.0))

# Dashes along the pack's way in, drawn out from the ring toward the wall
func _draw_route(points: PackedVector3Array, seconds: float) -> Node3D:
	var at: Array[Transform3D] = []
	var carry := ROUTE_FROM_RING
	for i in range(1, points.size()):
		var a := points[i - 1]
		var seg := Vector3(points[i].x - a.x, 0.0, points[i].z - a.z)
		var length := seg.length()
		if length < 0.001:
			continue
		var dir := seg / length
		var basis := Basis.looking_at(dir, Vector3.UP)
		var d := carry
		while d < length:
			var p := a + dir * d
			at.append(Transform3D(basis, Vector3(p.x, maxf(p.y, 0.1) + 0.05, p.z)))
			d += ROUTE_DASH
		carry = d - length
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var dash := QuadMesh.new()
	dash.orientation = PlaneMesh.FACE_Y
	dash.size = Vector2(0.22, 0.55)
	mm.mesh = dash
	mm.instance_count = at.size()
	for i in at.size():
		mm.set_instance_transform(i, at[i])
	mm.visible_instance_count = 0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(SURGE_COLOR, 0.8)
	var line := MultiMeshInstance3D.new()
	line.multimesh = mm
	line.material_override = mat
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(line)
	line.create_tween().tween_method(func(v: float): mm.visible_instance_count = int(v),
		0.0, float(at.size()), ROUTE_DRAW_TIME)
	get_tree().create_timer(seconds).timeout.connect(line.queue_free)
	return line

# The pack's count, standing on its route where it meets the wall: where the crew looks
func _route_tag(points: PackedVector3Array, text: String, seconds: float) -> Node3D:
	var spot := points[points.size() - 1]
	for i in range(1, points.size()):
		if points[i].z >= ROUTE_TAG_Z:
			var a := points[i - 1]
			spot = a.lerp(points[i], clampf((ROUTE_TAG_Z - a.z) / maxf(0.001, points[i].z - a.z), 0.0, 1.0))
			break
	var tag := Label3D.new()
	tag.text = text
	tag.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # already translated
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.pixel_size = 0.012   # read from the play camera, not up close like a call's words
	tag.font_size = 40
	tag.outline_size = 14
	tag.modulate = Color(0.98, 0.93, 0.78)
	tag.outline_modulate = Color(0.16, 0.11, 0.08)
	add_child(tag)
	tag.global_position = Vector3(spot.x, 1.2, spot.z)
	get_tree().create_timer(seconds).timeout.connect(tag.queue_free)
	return tag

# A pulsing ring on the ground where the pack comes in
func _ring_spot(at: Vector3, seconds: float) -> Node3D:
	var ring := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.orientation = PlaneMesh.FACE_Y
	quad.size = Vector2(8.0, 8.0)
	ring.mesh = quad
	var rm := ShaderMaterial.new()
	rm.shader = preload("res://assets/shaders/ground_marker.gdshader")
	rm.set_shader_parameter("shadow_color", Color(0, 0, 0, 0))
	rm.set_shader_parameter("ring_color", Color(SURGE_COLOR, 0.85))
	rm.set_shader_parameter("ring_radius", 0.44)
	rm.set_shader_parameter("ring_width", 0.03)
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.global_position = Vector3(at.x, 0.14, at.z)
	var pulse := ring.create_tween().set_loops(maxi(1, int(seconds / 0.9)))
	pulse.tween_property(ring, "scale", Vector3.ONE * 1.12, 0.45).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(ring, "scale", Vector3.ONE * 0.9, 0.45).set_trans(Tween.TRANS_SINE)
	get_tree().create_timer(seconds).timeout.connect(ring.queue_free)
	return ring

func _pick_surge_spots(horn: bool) -> void:
	_surge_at.clear()
	if packs_only() and not horn:
		_roll_shape()
		var side := -1.0 if randf() < 0.5 else 1.0
		match _shape:
			"pincer":
				for s in [-1.0, 1.0]:
					_surge_at.append(Vector3(s * randf_range(RUSH_X_MIN, SPAWN_X_HALF), 0.1, SPAWN_Z))
			"rush":
				_surge_at.append(Vector3(side * randf_range(RUSH_X_MIN, SPAWN_X_HALF), 0.1, SPAWN_Z))
			"ram":
				_surge_at.append(Vector3(randf_range(-RAM_X, RAM_X), 0.1, SPAWN_Z))
			"raid":   # for the piles: in on the side of the yard
				var yard := 1.0 if GameState.yard_center().x >= 0.0 else -1.0
				_surge_at.append(Vector3(yard * randf_range(RUSH_X_MIN, SPAWN_X_HALF), 0.1, SPAWN_Z))
			_:
				_surge_at.append(Vector3(randf_range(-SPAWN_X_HALF, SPAWN_X_HALF), 0.1, SPAWN_Z))
		return
	var spots := 2 if not horn and _day >= WAVE_SPLIT_DAY else 1
	for i in spots:
		# Two spots: one on each half of the front, so the crew has to split
		var lo := -SPAWN_X_HALF if spots == 1 or i == 0 else 2.0
		var hi := SPAWN_X_HALF if spots == 1 or i == 1 else -2.0
		_surge_at.append(Vector3(randf_range(lo, hi), 0.1, SPAWN_Z))

## Server: a neighbour from the villages (Neh. 4:12, Messenger) tells where the next pack
## comes in: its spot is chosen now and marked until it comes, long before the bell.
## A pack already coming in: he points at it. False when there are no warned packs (no waves).
func warn_early() -> bool:
	var horn := GameState.has_twist("horn")
	if not _active or (not horn and not GameState.waves):
		return false
	if _surge_left > 0:
		for at in _surge_at:
			_mark_surge.rpc(at, horn, _surge_left * SURGE_GAP, _shape_label())
		return true
	if not _warned_early:
		_pick_surge_spots(horn)
		_warned_early = true
	for at in _surge_at:
		_mark_surge.rpc(at, horn, _surge_timer, _shape_label())
	return true

# A quiet mark (no bell): the bell still rings at the usual warning
@rpc("authority", "call_local", "reliable")
func _mark_surge(at: Vector3, horn: bool, until: float, shape := "Wave") -> void:
	get_tree().call_group("offscreen_alerts", "ping", at, SURGE_COLOR, "Surge" if horn else shape, until + 3.0)

@rpc("authority", "call_local", "reliable")
func _warn_surge(at: Vector3, horn: bool, warn: float, shape := "Wave") -> void:
	Sfx.play("alert")
	get_tree().call_group("offscreen_alerts", "ping", at, SURGE_COLOR, "Surge" if horn else shape, warn + 3.0)
	get_tree().call_group("watchmen", "warn_wave", at, horn, shape)

func _tick_saboteurs(delta: float) -> void:
	if not GameState.saboteur_on() or GameState.current_section_index < SABOTEUR_SECTION:
		return
	_sab_timer -= delta
	if _sab_timer > 0.0:
		return
	var most := 2 if _day >= SABOTEUR_PAIR_DAY and _crew() >= 3.0 else 1
	var alive := enemies_root.get_children().filter(func(e): return e.type == Enemy.Type.SABOTEUR and e.health > 0.0).size()
	if alive >= most:
		_sab_timer = 5.0
		return
	_sab_timer = SABOTEUR_EVERY / Settings.diff()["pace"]
	_do_spawn(Enemy.Type.SABOTEUR)

func _tick_messengers(delta: float) -> void:
	# With the rumour out (DayDirector, Neh. 6:5) the fifth messenger carries the open letter
	var limit := MESSENGERS_PER_DAY + (1 if GameState.rumour else 0)
	if not GameState.has_twist("schemes") or _msg_sent >= limit:
		return
	_msg_timer -= delta
	if _msg_timer > 0.0 or visitors_root.get_child_count() > 0:
		return
	_msg_timer = MESSENGER_EVERY
	var m: Node3D = MESSENGER_SCENE.instantiate()
	var neighbour := not Messenger.old_rules and _msg_sent > 0 and not _last_neighbour 		and _nb_sent < NEIGHBOURS_PER_DAY and randf() < NEIGHBOUR_CHANCE
	_last_neighbour = neighbour
	if neighbour:
		_nb_sent += 1
		m.name = "Neighbour"
		_msg_timer = MESSENGER_EVERY * 0.5   # a short call: the four (and the letter) still fit the day
	else:
		_msg_sent += 1
		if _msg_sent > MESSENGERS_PER_DAY:
			m.name = "Letter"
	# In from the side, along the inside of the wall
	m.position = Vector3(26.0 if randf() < 0.5 else -26.0, 0.1, randf_range(7.0, 12.0))
	NetworkManager.gate_sync(m.get_node("MultiplayerSynchronizer"))
	visitors_root.add_child(m, true)

func _do_spawn(type: Enemy.Type, at := Vector3.INF) -> void:
	var e: Enemy = ENEMY_SCENE.instantiate()
	e.type = type
	e.position = at if at != Vector3.INF else Vector3(randf_range(-SPAWN_X_HALF, SPAWN_X_HALF), 0.1, SPAWN_Z)  # floor top
	# Filter must be in place before add_child — the spawner snapshots visibility on enter
	NetworkManager.gate_sync(e.get_node("MultiplayerSynchronizer"))
	enemies_root.add_child(e, true)
