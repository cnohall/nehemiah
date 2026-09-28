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

# "schemes" twist: messengers to Ono, "four times" a day (Neh. 6:4), one at a time
const MESSENGER_FIRST     := 12.0
const MESSENGER_EVERY     := 24.0
const MESSENGERS_PER_DAY  := 4

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
var _msg_sent := 0


func start(day: int) -> void:
	if GameState.tutorial:
		return   # Tutorial sends its one scout itself
	_day = day
	_active = true
	_timer = FIRST_SPAWN_DELAY
	_msg_timer = MESSENGER_FIRST
	_surge_timer = SURGE_FIRST if GameState.has_twist("horn") else WAVE_FIRST
	_surge_left = 0

	_msg_sent = 0

func stop() -> void:
	_active = false

func _physics_process(delta: float) -> void:
	if not _active or not multiplayer.is_server():
		return
	_tick_messengers(delta)
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
			if _surge_at.is_empty():   # never warned (can't happen in play; be safe)
				_surge_at.append(Vector3(randf_range(-SPAWN_X_HALF, SPAWN_X_HALF), 0.1, SPAWN_Z))
			if enemies_root.get_child_count() < MAX_ALIVE_CAP:
				var spread := SURGE_SPREAD if horn else WAVE_SPREAD
				var off := Vector3(randf_range(-spread, spread), 0, randf_range(-1.0, 1.0))
				_do_spawn(_pick_type(), _surge_at[_surge_left % _surge_at.size()] + off)
		return
	var warn := SURGE_WARN if horn else WAVE_WARN
	var was := _surge_timer
	_surge_timer -= delta
	if was > warn and _surge_timer <= warn:
		_surge_at.clear()
		var spots := 2 if not horn and _day >= WAVE_SPLIT_DAY else 1
		for i in spots:
			# Two spots: one on each half of the front, so the crew has to split
			var lo := -SPAWN_X_HALF if spots == 1 or i == 0 else 2.0
			var hi := SPAWN_X_HALF if spots == 1 or i == 1 else -2.0
			_surge_at.append(Vector3(randf_range(lo, hi), 0.1, SPAWN_Z))
		for at in _surge_at:
			_warn_surge.rpc(at, horn, warn)
	elif _surge_timer <= 0.0:
		_surge_gap = 0.0
		if horn:
			_surge_left = roundi((3 + floori(_day / 12.0)) * Settings.diff()["pace"])
			_surge_timer = SURGE_EVERY / _pressure()
		else:
			_surge_left = roundi((WAVE_BASE + floori(_day / WAVE_PER_DAYS) + floori((_crew() - 1.0) / WAVE_PER_CREW)) * _pressure())
			var t := (_day - 1) / float(GameState.TOTAL_DAYS - 1)
			_surge_timer = lerpf(WAVE_EVERY_DAY1, WAVE_EVERY_DAY52, t)

@rpc("authority", "call_local", "reliable")
func _warn_surge(at: Vector3, horn: bool, warn: float) -> void:
	Sfx.play("alert")
	get_tree().call_group("offscreen_alerts", "ping", at, SURGE_COLOR, "Surge" if horn else "Wave", warn + 3.0)

func _tick_messengers(delta: float) -> void:
	if not GameState.has_twist("schemes") or _msg_sent >= MESSENGERS_PER_DAY:
		return
	_msg_timer -= delta
	if _msg_timer > 0.0 or visitors_root.get_child_count() > 0:
		return
	_msg_timer = MESSENGER_EVERY
	_msg_sent += 1
	var m: Node3D = MESSENGER_SCENE.instantiate()
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
