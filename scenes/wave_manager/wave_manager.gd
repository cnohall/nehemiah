extends Node

const ENEMY_SCENE  := preload("res://scenes/enemy/enemy.tscn")
const SPAWN_RADIUS := 44.0

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
	_spawn_timer = 1.5  # Initial delay before first spawn
	wave_started.emit(_queue.size())

func get_alive_count() -> int:
	return _alive

# ── Internal ───────────────────────────────────────────────

func _build_queue(day: int) -> Array[Dictionary]:
	var q: Array[Dictionary] = []
	var count := 4 + (day / 4)
	for i in count:
		var t: int
		if day <= 8:
			t = 0  # SCOUT only
		elif day <= 20:
			t = 0 if randf() > 0.25 else 1  # SCOUT + BRUTE
		else:
			var roll := randf()
			t = 0 if roll < 0.45 else (1 if roll < 0.70 else 2)
		q.append({ "type": t, "interval": randf_range(1.2, 3.5) })
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
