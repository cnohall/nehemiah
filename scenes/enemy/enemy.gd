class_name Enemy
extends CharacterBody3D

# Server simulates; clients receive position / type / anim / hits via MultiplayerSynchronizer.
# Runners head for the inner city through gaps in the wall; wreckers march on the
# nearest built wall and batter it until it falls back a stage. Nearby workers are
# attacked either way, so only killing them stops the damage.

enum Type { SCOUT, BRUTE, RAIDER }

const SPEED        := { Type.SCOUT: 3.5, Type.BRUTE: 2.5, Type.RAIDER: 4.0 }
const HEALTH       := { Type.SCOUT: 40.0, Type.BRUTE: 100.0, Type.RAIDER: 60.0 }
const DAMAGE       := { Type.SCOUT: 5.0,  Type.BRUTE: 15.0,  Type.RAIDER: 8.0  }
const SCALE        := { Type.SCOUT: 1.0, Type.BRUTE: 1.2, Type.RAIDER: 1.0 }

const AGGRO_RANGE       := 4.5    # start chasing a worker this close
const LEASH_RANGE       := 8.0    # give up the chase beyond this
const ATTACK_RANGE      := 1.6
const WALL_REACH        := 1.3    # footprint distance to count as "at the wall"
const ATTACK_CD         := 1.6
const STAGGER_TIME      := 0.3    # a sling hit knocks the wind out briefly
const HITSTOP_TIME      := 0.09   # sprite holds its frame on a hit
const REPATH_INTERVAL   := 0.3
const STUCK_WINDOW      := 0.6    # seconds of no progress before bashing a wall
const STUCK_DIST        := 0.35
const BREACH_Z          := 13.5   # past this line the enemy is inside the city
const GOAL_Z            := 15.0
const GOAL_X_SPREAD     := 12.0
const WRECKER_CHANCE    := 0.5    # share of scouts/raiders that go for the wall; brutes always do
const WALL_STANDOFF     := 0.6    # where a wrecker stands, measured out from the wall face

# Distinct silhouette per type (CharacterRig.enemy_look), one dark colour family
const _LOOKS := { Type.SCOUT: "scout", Type.BRUTE: "brute", Type.RAIDER: "raider" }
const CORPSE_TIME := 0.9

@export var type: Type = Type.SCOUT

signal died

# Replicated animation name — server writes, every peer plays it
var anim := "idle_down":
	set(value):
		if _sprite != null and _sprite.animation != value:
			if value.begins_with("thrust"):
				Sfx.play("enemy_swing", global_position)
			elif value == "collapse":
				Sfx.play("enemy_die", global_position)
		anim = value
		if _sprite != null and _sprite.animation != value:
			_sprite.play(value)

# Replicated hit counter — every change flashes the sprite on all peers
var hits := 0:
	set(value):
		hits = value
		if _sprite != null:
			_sprite.hit_flash()
			_sprite.hitstop(HITSTOP_TIME)
			_sprite.squash(Vector2(1.12, 0.9))
			Sfx.play("enemy_hit", global_position)

# Replicated so clients can draw the health bar
var health: float = -1.0:
	set(value):
		health = value
		if _bar != null:
			_bar.show_health(health / HEALTH[type])
			if health <= 0.0:
				_bar.visible = false  # no bar over a corpse
var _bar: HealthBar
var _target_player: Node3D = null
var _target_wall: Node3D = null
var _wrecker := false
var _goal: Vector3
var _attack_timer := 0.0
var _repath_timer := 0.0
var _stuck_timer := 0.0
var _stuck_origin: Vector3
var _facing := "down"
var _busy := false
var _stagger := 0.0

@onready var nav: NavigationAgent3D = $NavigationAgent3D
@onready var _sprite: CharacterRig = $Figure

func _ready() -> void:
	# Server sets it; clients already received it as spawn state
	if multiplayer.is_server() or health < 0.0:
		health = HEALTH[type]
	_bar = HealthBar.new(0.7, 0.08)
	_bar.position.y = 2.6 * SCALE[type]
	add_child(_bar)
	add_to_group("enemies")
	_sprite.setup(CharacterRig.enemy_look(_LOOKS[type]), SCALE[type])
	_sprite.speed_scale = SPEED[type] / 3.5  # stride matches ground speed
	_sprite.play(anim)
	_goal = Vector3(randf_range(-GOAL_X_SPREAD, GOAL_X_SPREAD), 0.0, GOAL_Z)
	_wrecker = type == Type.BRUTE or randf() < WRECKER_CHANCE
	_stuck_origin = global_position

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or health <= 0.0:
		return
	if global_position.z > BREACH_Z:
		GameState.add_breach()
		queue_free()
		return
	_attack_timer = maxf(0.0, _attack_timer - delta)
	if _stagger > 0.0:
		_stagger -= delta
		velocity = Vector3.ZERO
		return
	if _busy:
		return
	_pick_target()
	if _try_attack_player() or _try_attack_wall():
		return
	_move(delta)
	_check_stuck(delta)
	_update_anim()

# ── Targeting ──────────────────────────────────────────────

func _pick_target() -> void:
	_pick_wall()
	if is_instance_valid(_target_player) and not _target_player.downed \
			and _dist_flat(_target_player) < LEASH_RANGE:
		return
	_target_player = null
	var best := AGGRO_RANGE
	for p in get_tree().get_nodes_in_group("players"):
		if p.downed:
			continue
		var d := _dist_flat(p)
		if d < best:
			best = d
			_target_player = p

# Wreckers lock onto the nearest built wall. Once it's knocked down to bare
# foundation they pour through the breach instead.
func _pick_wall() -> void:
	if not _wrecker:
		return
	if is_instance_valid(_target_wall):
		if _target_wall.is_built():
			return
		_target_wall = null
		_wrecker = false
		return
	var best := INF
	for section in get_tree().get_nodes_in_group("wall_sections"):
		if not section.is_built():
			continue
		var d: float = section.distance_to_point(global_position)
		if d < best:
			best = d
			_target_wall = section

func _dist_flat(n: Node3D) -> float:
	return Vector2(n.global_position.x - global_position.x, n.global_position.z - global_position.z).length()

# ── Movement ───────────────────────────────────────────────

func _move(delta: float) -> void:
	var dest := _goal
	if _target_player:
		dest = _target_player.global_position
	elif _target_wall:
		dest = _target_wall.approach_point(global_position, WALL_STANDOFF)
	_repath_timer -= delta
	if _repath_timer <= 0.0:
		_repath_timer = REPATH_INTERVAL
		nav.target_position = dest
	var next := nav.get_next_path_position()
	var step := next - global_position
	step.y = 0.0
	if step.length_squared() < 0.01:
		# Nav mesh not ready or at the path end — head straight for it
		step = dest - global_position
		step.y = 0.0
	if step.length_squared() > 0.01:
		velocity = step.normalized() * SPEED[type]
		move_and_slide()
	else:
		velocity = Vector3.ZERO

# No progress for a while → something built is in the way; batter it
func _check_stuck(delta: float) -> void:
	_stuck_timer += delta
	if _stuck_timer < STUCK_WINDOW:
		return
	var moved := global_position.distance_to(_stuck_origin)
	_stuck_timer = 0.0
	_stuck_origin = global_position
	if moved > STUCK_DIST:
		return
	var wall := _nearest_wall()
	if wall != null and _attack_timer <= 0.0:
		_attack(wall, wall.global_position)

func _nearest_wall() -> Node3D:
	var best: Node3D = null
	var best_dist := WALL_REACH
	for section in get_tree().get_nodes_in_group("wall_sections"):
		if not section.is_built():
			continue
		var d: float = section.distance_to_point(global_position)
		if d < best_dist:
			best_dist = d
			best = section
	return best

# ── Attack ─────────────────────────────────────────────────

func _try_attack_player() -> bool:
	if _target_player == null or _dist_flat(_target_player) > ATTACK_RANGE:
		return false
	velocity = Vector3.ZERO
	if _attack_timer <= 0.0:
		_attack(_target_player, _target_player.global_position)
	else:
		anim = "idle_" + _facing
	return true

func _try_attack_wall() -> bool:
	if _target_player != null or _target_wall == null \
			or _target_wall.distance_to_point(global_position) > WALL_REACH:
		return false
	velocity = Vector3.ZERO
	var at: Vector3 = _target_wall.approach_point(global_position, 0.0)
	if _attack_timer <= 0.0:
		_attack(_target_wall, at)
	else:
		anim = "idle_" + _facing
	return true

func _attack(victim: Node3D, at: Vector3) -> void:
	_attack_timer = ATTACK_CD
	_facing = CharAnim.dir_from_velocity(at - global_position, _facing)
	_busy = true
	anim = "thrust_" + _facing
	victim.take_damage(DAMAGE[type])
	await _sprite.animation_finished
	if is_instance_valid(self):
		_busy = false

# ── Animation ──────────────────────────────────────────────

func _update_anim() -> void:
	var moving := velocity.length_squared() > 0.01
	if moving:
		_facing = CharAnim.dir_from_velocity(velocity, _facing)
	anim = ("walk" if moving else "idle") + "_" + _facing

# ── Damage (server) ────────────────────────────────────────

func take_damage(amount: float) -> void:
	# Already dead, waiting on queue_free — ignore extra hits so died emits once
	if health <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	hits += 1
	_stagger = STAGGER_TIME
	if health == 0.0:
		_die()

# Collapse in place, then free (the spawner despawns it on clients)
func _die() -> void:
	died.emit()
	remove_from_group("enemies")
	$CollisionShape3D.set_deferred("disabled", true)
	velocity = Vector3.ZERO
	anim = "collapse"
	await get_tree().create_timer(CORPSE_TIME).timeout
	if is_instance_valid(self):
		queue_free()
