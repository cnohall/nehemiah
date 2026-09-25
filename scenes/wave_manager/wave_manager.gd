extends Node

# Server-only. Streams enemies in while a day's WORK phase is running (DayDirector
# calls start/stop). Spawned enemies replicate to clients via Main/EnemySpawner.

const ENEMY_SCENE := preload("res://scenes/enemy/enemy.tscn")

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

@onready var enemies_root: Node3D = get_parent().get_node("Enemies")
@onready var players_root: Node3D = get_parent().get_node("Players")

var _active := false
var _day := 1
var _timer := 0.0

func start(day: int) -> void:
	_day = day
	_active = true
	_timer = FIRST_SPAWN_DELAY

func stop() -> void:
	_active = false

func _physics_process(delta: float) -> void:
	if not _active or not multiplayer.is_server():
		return
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
	var n := maxi(1, players_root.get_child_count())
	base *= 1.3 / (0.7 + 0.3 * n)
	return base * randf_range(1.0 - INTERVAL_JITTER, 1.0 + INTERVAL_JITTER)

func _max_alive() -> int:
	return mini(MAX_ALIVE_CAP, MAX_ALIVE_BASE + floori(_day / 3.0))

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

func _do_spawn(type: Enemy.Type) -> void:
	var e: Enemy = ENEMY_SCENE.instantiate()
	e.type = type
	e.position = Vector3(randf_range(-SPAWN_X_HALF, SPAWN_X_HALF), 0.1, SPAWN_Z)  # floor top
	# Filter must be in place before add_child — the spawner snapshots visibility on enter
	NetworkManager.gate_sync(e.get_node("MultiplayerSynchronizer"))
	enemies_root.add_child(e, true)
