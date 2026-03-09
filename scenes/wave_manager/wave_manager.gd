extends Node
## Handles wave progression and enemy spawning

signal wave_started(wave_num: int)
signal wave_cleared(wave_num: int)
signal enemy_spawned(enemy: Node3D)

@export var enemy_scene: PackedScene
@export var spawn_timer: Timer

var current_wave: int = 0
var enemies_to_spawn: int = 0
var enemies_alive: int = 0
var is_active: bool = false

func _ready() -> void:
	if spawn_timer:
		spawn_timer.timeout.connect(_on_spawn_timer_timeout)

func start_next_wave() -> void:
	current_wave += 1
	enemies_to_spawn = 5 + (current_wave * 3)
	if spawn_timer:
		spawn_timer.wait_time = max(1.0, 3.0 - (current_wave * 0.2))
		spawn_timer.start()
	
	wave_started.emit(current_wave)
	is_active = true

func _on_spawn_timer_timeout() -> void:
	if not multiplayer.is_server() or not is_active:
		return
	
	if enemies_to_spawn > 0:
		_spawn_enemy()
		enemies_to_spawn -= 1
	else:
		spawn_timer.stop()

func _spawn_enemy() -> void:
	var enemy = enemy_scene.instantiate()
	
	# Spawn at a random position on the edge
	var angle := randf() * PI * 2.0
	var radius := 28.0
	enemy.position = Vector3(cos(angle) * radius, 0.5, sin(angle) * radius)
	
	enemy.tree_exiting.connect(_on_enemy_death)
	enemy_spawned.emit(enemy)
	enemies_alive += 1

func _on_enemy_death() -> void:
	enemies_alive -= 1
	if enemies_to_spawn <= 0 and enemies_alive <= 0:
		is_active = false
		wave_cleared.emit(current_wave)
