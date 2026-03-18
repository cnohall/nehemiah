extends Node
## Handles day/wave progression and enemy spawning.
## Day transitions are driven by wall completion (main.gd), not enemy count.

signal wave_started(wave_num: int)
signal enemy_spawned(enemy: Node3D)

const MAX_DAYS: int = 52
const SPAWN_RADIUS: float = 35.0

@export var enemy_scene: PackedScene
@export var spawn_timer: Timer

var current_wave: int = 0
var is_active: bool = false
var spawn_center: Vector3 = Vector3.ZERO

var _is_spawning: bool = false

func _ready() -> void:
	if spawn_timer:
		spawn_timer.timeout.connect(_on_spawn_timer_timeout)

func start_next_wave() -> void:
	if current_wave >= MAX_DAYS:
		return
	current_wave += 1
	if spawn_timer:
		spawn_timer.wait_time = maxf(1.5, 6.0 - current_wave * 0.15)
		spawn_timer.start()
	is_active = true
	_is_spawning = true
	wave_started.emit(current_wave)

func stop_spawning() -> void:
	_is_spawning = false
	is_active = false
	if spawn_timer:
		spawn_timer.stop()

func _on_spawn_timer_timeout() -> void:
	if not multiplayer.is_server() or not _is_spawning:
		return
	_spawn_enemy()

func _spawn_enemy() -> void:
	if enemy_scene == null:
		return

	var enemy := enemy_scene.instantiate()
	enemy.health = 25.0 + current_wave * 2.0
	enemy.speed  = 3.0  + current_wave * 0.05

	var interior_dir := Vector3.BACK
	var main := get_tree().current_scene
	var b_mgr = main.get("_building_mgr") if main else null
	if b_mgr and b_mgr.has_method("get_interior_direction"):
		interior_dir = b_mgr.get_interior_direction()

	var exterior_dir := -interior_dir
	var base_angle   := atan2(exterior_dir.x, exterior_dir.z)
	var angle        := base_angle + (randf() - 0.5) * PI * 0.5

	enemy.position = Vector3(sin(angle), 0.5, cos(angle)) * SPAWN_RADIUS
	enemy_spawned.emit(enemy)
