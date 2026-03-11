extends Node
## Handles day/wave progression and enemy spawning

signal wave_started(wave_num: int)
signal wave_cleared(wave_num: int)
signal enemy_spawned(enemy: Node3D)

const MAX_DAYS: int = 52

@export var enemy_scene: PackedScene   ## Scout (default)
@export var brute_scene: PackedScene   ## Brute: slow, tanky, targets blocks
@export var raider_scene: PackedScene  ## Raider: fast, fragile, targets players
@export var spawn_timer: Timer

var current_wave: int = 0
var enemies_alive: int = 0
var is_active: bool = false
var _is_spawning: bool = false
var spawn_center: Vector3 = Vector3.ZERO  ## Updated by main.gd each section load
const SPAWN_RADIUS: float = 35.0          ## Distance from section center

func _ready() -> void:
	if spawn_timer:
		spawn_timer.timeout.connect(_on_spawn_timer_timeout)

func start_next_wave() -> void:
	if current_wave >= MAX_DAYS:
		return
	current_wave += 1
	# No fixed enemy limit anymore - enemies spawn until stop_spawning is called
	if spawn_timer:
		# Very slow start for testing/early game
		if current_wave == 1:
			spawn_timer.wait_time = 10.0
		elif current_wave == 2:
			spawn_timer.wait_time = 7.0
		else:
			spawn_timer.wait_time = max(1.0, 5.0 - (current_wave * 0.2))
		spawn_timer.start()
	wave_started.emit(current_wave)
	is_active = true
	_is_spawning = true

func stop_spawning() -> void:
	_is_spawning = false
	if spawn_timer:
		spawn_timer.stop()
	# If no enemies are left when we stop, clear the wave immediately
	_check_wave_cleared()

func _on_spawn_timer_timeout() -> void:
	if not multiplayer.is_server() or not _is_spawning:
		return
	_spawn_enemy()

func _pick_enemy_scene() -> PackedScene:
	var roll := randf()
	if current_wave <= 8 or brute_scene == null:
		return enemy_scene
	elif current_wave <= 20:
		return brute_scene if roll < 0.30 else enemy_scene
	elif current_wave <= 35:
		if raider_scene and roll < 0.20: return raider_scene
		if roll < 0.60: return brute_scene
		return enemy_scene
	else:
		if raider_scene and roll < 0.40: return raider_scene
		if roll < 0.80: return brute_scene
		return enemy_scene

func _spawn_enemy() -> void:
	var scene := _pick_enemy_scene()
	var enemy = scene.instantiate()
	
	# Early wave enemies are weaker for easier testing/intro
	if current_wave == 1:
		enemy.health = 10.0
		enemy.speed = 2.0
	elif current_wave == 2:
		enemy.health = 15.0
		enemy.speed = 2.5
	
	var interior_dir := Vector3.BACK
	var main = get_tree().current_scene
	if main and main.get("_building_mgr") and main._building_mgr.has_method("get_interior_direction"):
		interior_dir = main._building_mgr.get_interior_direction()
	
	# Spawn on the outside (opposite of interior)
	var exterior_dir := -interior_dir
	var base_angle := atan2(exterior_dir.x, exterior_dir.z)
	var angle := base_angle + (randf() - 0.5) * PI / 2.0
	
	enemy.position = Vector3(
		sin(angle) * SPAWN_RADIUS,
		0.5,
		cos(angle) * SPAWN_RADIUS
	)
	enemy.tree_exiting.connect(_on_enemy_death)
	enemy_spawned.emit(enemy)
	enemies_alive += 1

func _on_enemy_death() -> void:
	enemies_alive -= 1
	_check_wave_cleared()

func _check_wave_cleared() -> void:
	if not _is_spawning and enemies_alive <= 0 and is_active:
		is_active = false
		wave_cleared.emit(current_wave)
