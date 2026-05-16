extends Node

const ENEMY_SCENE := preload("res://scenes/enemy/enemy.tscn")

const SPAWN_RADIUS        := 44.0
const INITIAL_SPAWN_DELAY := 1.5
const SPAWN_INTERVAL_MIN  := 1.2
const SPAWN_INTERVAL_MAX  := 3.5
const BASE_ENEMY_COUNT    := 4
const BRUTE_UNLOCK_DAY    := 8
const RAIDER_UNLOCK_DAY   := 20
const MID_BRUTE_CHANCE    := 0.25   # P(brute) days 9–20; rest scout
# Late-game spawn weights: 45% scout, 25% brute, 30% raider
const LATE_SCOUT_CAP      := 0.45
const LATE_BRUTE_CAP      := 0.70

signal wave_started(total: int)
signal enemy_died
signal wave_cleared

@onready var enemies_root: Node3D = get_parent().get_node("Enemies")

var _queue: Array[Dictionary] = []
var _spawn_timer: float = 0.0
var _alive: int = 0

func _ready() -> void:
	if not multiplayer.is_server():
		return
	GameState.day_changed.connect(_on_day_changed)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if _queue.is_empty():
		return
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		var entry: Dictionary = _queue.pop_front()
		_spawn_timer = entry.get("interval", 2.0)
		_do_spawn(entry["type"])

# ── Public API ─────────────────────────────────────────────

func start_wave(day: int) -> void:
	_queue = _build_queue(day)
	_alive = 0
	_spawn_timer = INITIAL_SPAWN_DELAY
	wave_started.emit(_queue.size())

func get_alive_count() -> int:
	return _alive

# ── Internal ───────────────────────────────────────────────

func _build_queue(day: int) -> Array[Dictionary]:
	var q: Array[Dictionary] = []
	var count := BASE_ENEMY_COUNT + (day / 4)
	for i in count:
		var t: int
		if day <= BRUTE_UNLOCK_DAY:
			t = 0  # SCOUT only
		elif day <= RAIDER_UNLOCK_DAY:
			t = 1 if randf() < MID_BRUTE_CHANCE else 0
		else:
			var roll := randf()
			t = 0 if roll < LATE_SCOUT_CAP else (1 if roll < LATE_BRUTE_CAP else 2)
		q.append({ "type": t, "interval": randf_range(SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_MAX) })
	return q

func _do_spawn(type: int) -> void:
	var angle := randf() * TAU
	var pos := Vector3(cos(angle) * SPAWN_RADIUS, 0.2, sin(angle) * SPAWN_RADIUS)
	var e := ENEMY_SCENE.instantiate()
	e.type = type
	enemies_root.add_child(e, true)
	e.global_position = pos
	e.died.connect(_on_enemy_died)
	_alive += 1

func _on_enemy_died() -> void:
	_alive = maxi(0, _alive - 1)
	enemy_died.emit()
	if _alive == 0 and _queue.is_empty():
		wave_cleared.emit()

func _on_day_changed(day: int) -> void:
	start_wave(day)
