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
const BRUTE_UNLOCK_DAY    := 8
const RAIDER_UNLOCK_DAY   := 20
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

# "schemes" twist: messengers to Ono, "four times" a day (Neh. 6:4), one at a time
const MESSENGER_FIRST     := 12.0
const MESSENGER_EVERY     := 24.0
const MESSENGERS_PER_DAY  := 4
# …and between them, now and then, a neighbour from the villages with a warning (4:12, GDD
# §6.7): never the day's first visitor, never two in a row, at most two a day
const NEIGHBOUR_CHANCE    := 0.34
const NEIGHBOURS_PER_DAY  := 2

# Saboteur (GDD §5.9): comes quietly with the trickle, never in a pack, on his own timer.
# One at a time through day 20; from day 21, two with a crew of three or more.
# Not scaled by section pressure; difficulty's pace scales the interval.
const SABOTEUR_DAY        := 6       # the Fish Gate's second day: beams get a day to themselves
const SABOTEUR_FIRST      := 22.0
const SABOTEUR_EVERY      := 50.0
const SABOTEUR_PAIR_DAY   := 21

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
var _demo_brute := false   # demo: the day's first brute has been sent


func start(day: int) -> void:
	if GameState.free_play():
		return   # Tutorial sends its one scout itself
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

func stop() -> void:
	_active = false

func _physics_process(delta: float) -> void:
	if not _active or not multiplayer.is_server():
		return
	_tick_messengers(delta)
	_tick_saboteurs(delta)
	_tick_surges(delta)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = _interval()
	if enemies_root.get_child_count() < _max_alive():
		_do_spawn(_pick_type())

# ── Pacing ─────────────────────────────────────────────────

func _interval() -> float:
	var t := (_day - 1) / float(GameState.TOTAL_DAYS - 1)
	var base := lerpf(INTERVAL_DAY1, INTERVAL_DAY52, t)
	# More workers → more pressure (1 player ×1.3 … 4 players ×0.68)
	base *= 1.3 / (0.7 + 0.3 * _crew())
	base /= _pressure()
	if GameState.has_twist("horn"):
		base *= SURGE_TRICKLE_MULT
	elif GameState.waves:
		base *= WAVE_TRICKLE_MULT
	return base * randf_range(1.0 - INTERVAL_JITTER, 1.0 + INTERVAL_JITTER)


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
			_surge_gap = SURGE_GAP
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
	if Settings.exp_forecast and not horn and not _forecasted and _surge_timer <= FORECAST_LEAD:
		_forecast()
	if was > warn and _surge_timer <= warn:
		if not _warned_early:
			_pick_surge_spots(horn)
		for at in _surge_at:
			_warn_surge.rpc(at, horn, warn)
	elif _surge_timer <= 0.0:
		_surge_gap = 0.0
		_warned_early = false
		_forecasted = false
		if horn:
			_surge_left = roundi((3 + floori(_day / 12.0)) * Settings.diff()["pace"])
			_surge_timer = SURGE_EVERY / _pressure()
		else:
			_surge_left = _pack.size() if not _pack.is_empty() else _wave_size()   # as forecast, even if the crew changed since
			var t := (_day - 1) / float(GameState.TOTAL_DAYS - 1)
			_surge_timer = lerpf(WAVE_EVERY_DAY1, WAVE_EVERY_DAY52, t)

func _wave_size() -> int:
	return roundi((WAVE_BASE + floori(_day / WAVE_PER_DAYS) + floori((_crew() - 1.0) / WAVE_PER_CREW)) * _pressure())

## The next member of the pack: as forecast, or rolled now
func _next_type() -> Enemy.Type:
	return _pack.pop_back() if not _pack.is_empty() else _pick_type()

# ── Experimental: forecast and call early (GDD §5.21) ──────

## Server: roll the coming pack and its spots now and tell every peer what and where
func _forecast() -> void:
	_forecasted = true
	if not _warned_early:
		_pick_surge_spots(false)
		_warned_early = true
	_pack.clear()
	for i in _wave_size():
		_pack.append(_pick_type())
	_tell_forecast(false)

func _tell_forecast(called: bool) -> void:
	var counts := [0, 0, 0]
	for t: int in _pack:
		counts[t] += 1
	_show_forecast.rpc(_surge_at.duplicate(), counts, _surge_timer, called)

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
func _show_forecast(spots: Array, counts: Array, seconds: float, called: bool) -> void:
	var parts: PackedStringArray = []
	if counts[0] > 0:
		parts.append(tr_n("%d scout", "%d scouts", counts[0]) % counts[0])
	if counts[1] > 0:
		parts.append(tr_n("%d brute", "%d brutes", counts[1]) % counts[1])
	if counts[2] > 0:
		parts.append(tr_n("%d raider", "%d raiders", counts[2]) % counts[2])
	var what := ", ".join(parts)
	if called:
		what += tr(" · the crew is spurred")
	get_tree().call_group("forecast_chip", "show_forecast", what, seconds, called)
	for at: Vector3 in spots:
		_ring_spot(at, seconds + 3.0)

# A pulsing ring on the ground where the pack comes in
func _ring_spot(at: Vector3, seconds: float) -> void:
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

func _pick_surge_spots(horn: bool) -> void:
	_surge_at.clear()
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
			_mark_surge.rpc(at, horn, _surge_left * SURGE_GAP)
		return true
	if not _warned_early:
		_pick_surge_spots(horn)
		_warned_early = true
	for at in _surge_at:
		_mark_surge.rpc(at, horn, _surge_timer)
	return true

# A quiet mark (no bell): the bell still rings at the usual warning
@rpc("authority", "call_local", "reliable")
func _mark_surge(at: Vector3, horn: bool, until: float) -> void:
	get_tree().call_group("offscreen_alerts", "ping", at, SURGE_COLOR, "Surge" if horn else "Wave", until + 3.0)

@rpc("authority", "call_local", "reliable")
func _warn_surge(at: Vector3, horn: bool, warn: float) -> void:
	Sfx.play("alert")
	get_tree().call_group("offscreen_alerts", "ping", at, SURGE_COLOR, "Surge" if horn else "Wave", warn + 3.0)
	get_tree().call_group("watchmen", "warn_wave", at, horn)

func _tick_saboteurs(delta: float) -> void:
	if not GameState.saboteur_on() or _day < SABOTEUR_DAY:
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
