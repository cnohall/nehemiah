extends CharacterBody3D

# Enemy types unlock by day (GDD §2)
enum Type { SCOUT, BRUTE, RAIDER }

const SPEED        := { Type.SCOUT: 3.5, Type.BRUTE: 2.5, Type.RAIDER: 4.0 }
const HEALTH       := { Type.SCOUT: 40.0, Type.BRUTE: 120.0, Type.RAIDER: 60.0 }
const DAMAGE       := { Type.SCOUT: 5.0,  Type.BRUTE: 15.0,  Type.RAIDER: 8.0  }
const ATTACK_RANGE := 2.0
const ATTACK_CD    := 2.0

@export var type: Type = Type.SCOUT

signal died

var health: float
var target: Node3D = null
var attack_timer: float = 0.0

@onready var nav: NavigationAgent3D = $NavigationAgent3D

func _ready() -> void:
	health = HEALTH[type]
	add_to_group("enemies")
	# Defer so NavigationServer has synced the map before pathfinding
	call_deferred("_find_target")

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_navigate()
	attack_timer = maxf(0.0, attack_timer - delta)
	if attack_timer == 0.0:
		_try_attack()

# ── Navigation ─────────────────────────────────────────────

func _navigate() -> void:
	if target == null:
		_find_target()
		return
	nav.target_position = target.global_position
	if nav.is_navigation_finished():
		return
	var next := nav.get_next_path_position()
	velocity = (next - global_position).normalized() * SPEED[type]
	move_and_slide()

func _find_target() -> void:
	# Priority: nearest player → wall sections → inner city (TODO: wall + city targets)
	var best: Node3D = null
	var best_dist := INF
	for p in get_tree().get_nodes_in_group("players"):
		var d := global_position.distance_squared_to(p.global_position)
		if d < best_dist:
			best_dist = d
			best = p
	target = best

# ── Attack ─────────────────────────────────────────────────

func _try_attack() -> void:
	if target == null:
		return
	if global_position.distance_to(target.global_position) > ATTACK_RANGE:
		return
	attack_timer = ATTACK_CD
	if target.has_method("take_damage"):
		target.take_damage(DAMAGE[type])

# ── Damage ─────────────────────────────────────────────────

func take_damage(amount: float) -> void:
	health = clampf(health - amount, 0.0, HEALTH[type])
	if health == 0.0:
		died.emit()
		queue_free()
