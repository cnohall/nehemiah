class_name Enemy
extends CharacterBody3D

# Server simulates; clients receive position / type / anim / hits via MultiplayerSynchronizer.
# Runners head for the inner city through gaps in the wall; wreckers march on the
# nearest built wall and batter it until it falls back a stage. Nearby workers are
# attacked either way, so only killing them stops the damage.

enum Type { SCOUT, BRUTE, RAIDER, SABOTEUR }

const SPEED        := { Type.SCOUT: 3.5, Type.BRUTE: 2.5, Type.RAIDER: 4.0, Type.SABOTEUR: 4.2 }
const HEALTH       := { Type.SCOUT: 40.0, Type.BRUTE: 100.0, Type.RAIDER: 60.0, Type.SABOTEUR: 30.0 }
const DAMAGE       := { Type.SCOUT: 5.0,  Type.BRUTE: 15.0,  Type.RAIDER: 8.0, Type.SABOTEUR: 0.0 }
const SCALE        := { Type.SCOUT: 1.0, Type.BRUTE: 1.2, Type.RAIDER: 1.0, Type.SABOTEUR: 0.95 }

const AGGRO_RANGE       := 4.5    # start chasing a worker this close
const LEASH_RANGE       := 8.0    # give up the chase beyond this
const ATTACK_RANGE      := 1.6
const WALL_REACH        := 1.3    # footprint distance to count as "at the wall"
const ATTACK_CD         := 1.6
const STAGGER_TIME      := 0.3    # a sling hit knocks the wind out briefly
const HITSTOP_TIME      := 0.09   # sprite holds its frame on a hit
const KNOCK_DECEL       := 40.0   # m/s² a sword shove bleeds off at
const KNOCK_TAKE        := { Type.SCOUT: 1.0, Type.BRUTE: 0.35, Type.RAIDER: 0.8, Type.SABOTEUR: 1.2 }   # share of a shove felt
# The tell (GDD §5.16, `--no-tell`): a foe draws the spear back before it strikes, and the
# blow lands at the end only if the worker is still in reach. A hit in the draw knocks the
# strike aside — any hit, except that a brute shrugs off anything lighter than STEADY
const TELL              := { Type.SCOUT: 0.45, Type.BRUTE: 0.8, Type.RAIDER: 0.35, Type.SABOTEUR: 0.0 }
const TELL_SLACK        := 0.4    # m past ATTACK_RANGE the blow still finds a worker
const STEADY            := { Type.BRUTE: 18.0 }   # least blow that breaks a brute's draw
const REEL_TIME         := 0.45   # knocked aside: stumbling, no strike
# A true shot (Player, GDD §5.16) knocks a foe off his feet for this long
const DOWN_TIME         := { Type.SCOUT: 2.2, Type.BRUTE: 1.5, Type.RAIDER: 1.9, Type.SABOTEUR: 2.4 }   # the clip runs ~2 s (char_anim "knocked")
const REPATH_INTERVAL   := 0.3
const SCAN_INTERVAL     := 0.2    # how often to look around for a new worker / wall
const STUCK_WINDOW      := 0.6    # seconds of no progress before bashing a wall
const STUCK_DIST        := 0.35
const BREACH_Z          := 21.0   # past this line the enemy is inside the city — well behind
const GOAL_Z            := 23.0   # the stockpiles, so the crew can still run a runner down
const GOAL_X_SPREAD     := 12.0
const WRECKER_CHANCE    := 0.5    # share of scouts/raiders that go for the wall; brutes always do
const WALL_STANDOFF     := 0.6    # where a wrecker stands, measured out from the wall face
const SEP_RADIUS        := 1.0    # enemies closer than this (× body scale) push each other apart
const SEP_WEIGHT        := 1.3    # push strength vs. the heading (1 = equal pull)
const SEP_INTERVAL      := 0.12   # neighbour sweep period; the push is reused between sweeps
const SEP_SETTLE_SPEED  := 1.2    # m/s slide that spreads attackers out round their target

# Distinct silhouette per type (CharacterRig.enemy_look), one dark colour family
const _LOOKS := { Type.SCOUT: "scout", Type.BRUTE: "brute", Type.RAIDER: "raider", Type.SABOTEUR: "saboteur" }

# Saboteur (GDD §5.9, Neh. 4:11 "…and cause the work to cease"): he comes for the yard,
# not the wall. In through a gap — or over a finished piece, a slow climb in plain view
# that any hit knocks him off — to the pile the work needs now; strews it (SupplyPile.
# scatter), then another, then out the way he came. He never fights and never counts
# as a breach: the harm he does is lost time.
const SCATTER_TIME := 1.5
const SCATTER_MAX  := 2
const CLIMB_TIME   := 2.5
const CLIMB_STUCK  := 1.0    # no headway this long beside a finished piece → climb it
const CLIMB_CLEAR  := 1.0
const PILE_REACH   := 2.0
const ESCAPE_Z     := -15.0
const CORPSE_TIME := 0.9
# Dusk: the day is lost for them — they turn tail and run for the hills
const FLEE_TIME    := 2.4
const FLEE_SPEED   := 1.5    # × normal speed
const FLEE_Z       := -40.0

@export var type: Type = Type.SCOUT

signal died

# Replicated animation name — server writes, every peer plays it
var anim := "idle_down":
	set(value):
		if _sprite != null and _sprite.animation != value:
			if value.begins_with("thrust"):
				Sfx.play("enemy_swing", global_position)
			elif value.begins_with("brace"):
				Sfx.play("enemy_tell", global_position)
				_sprite.squash(Vector2(0.9, 1.1))   # gathering himself — reads at a glance
			elif value.begins_with("reel"):
				Sfx.play("interrupt", global_position)
			elif value.begins_with("knocked"):
				_sprite.squash(Vector2(1.2, 0.82))
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
			_sprite.recoil(0.32)
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
var _scan_timer := randf() * SCAN_INTERVAL   # staggered so a wave doesn't all scan on one frame
var _stuck_timer := 0.0
var _stuck_origin: Vector3
var _facing := "down"
var _busy := false
var _stagger := 0.0
var _knock := Vector3.ZERO   # shove velocity, spent over the stagger (sword hits)
var _tell := 0.0             # server: seconds left drawing back before the blow lands
var _tell_victim: Node3D
var _tell_at := Vector3.ZERO
var _last_hitter := 0     # server: peer whose stone hit last (credited in the tally)
var _fleeing := false
# Saboteur (server)
var _pile: Node3D
var _scatter_t := 0.0
var _scattered_n := 0
var _escaping := false
var _climb_wall: Node3D
var _climb_t := 0.0
var _no_headway := 0.0
var _sep := Vector3.ZERO   # cached push away from crowding neighbours
var _sep_t := randf() * SEP_INTERVAL
var _pace := randf_range(0.93, 1.07)   # a wave doesn't march in lockstep

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
	GameState.mark_met(_LOOKS[type])
	_sprite.speed_scale = SPEED[type] / 3.5  # stride matches ground speed
	_sprite.play(anim)
	_goal = Vector3(randf_range(-GOAL_X_SPREAD, GOAL_X_SPREAD), 0.0, GOAL_Z)
	_wrecker = type == Type.BRUTE or (type != Type.SABOTEUR and randf() < WRECKER_CHANCE)
	_stuck_origin = global_position
	GameState.phase_changed.connect(_on_phase_changed)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or health <= 0.0:
		return
	if _fleeing:
		_run_away()
		return
	if type == Type.SABOTEUR:
		_saboteur(delta)
		return
	if global_position.z > BREACH_Z:
		GameState.add_breach()
		queue_free()
		return
	_attack_timer = maxf(0.0, _attack_timer - delta)
	if _stagger > 0.0:
		_stagger -= delta
		velocity = _knock
		if _knock != Vector3.ZERO:
			move_and_slide()
			_knock = _knock.move_toward(Vector3.ZERO, KNOCK_DECEL * delta)
		return
	if _tell > 0.0:
		_drawing(delta)
		return
	if _busy:
		return
	_pick_target(delta)
	if _try_attack_player(delta) or _try_attack_wall(delta):
		return
	_move(delta)
	_check_stuck(delta)
	_update_anim()

# ── Targeting ──────────────────────────────────────────────

# Current targets are re-checked every tick; new ones are only scanned for every
# SCAN_INTERVAL (the group sweeps are the costly part with a full wave)
func _pick_target(delta: float) -> void:
	_scan_timer -= delta
	var scan := _scan_timer <= 0.0
	if scan:
		_scan_timer = SCAN_INTERVAL
	_pick_wall(scan)
	if is_instance_valid(_target_player) and not _target_player.downed \
			and _dist_flat(_target_player) < LEASH_RANGE:
		return
	_target_player = null
	if not scan:
		return
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
func _pick_wall(scan: bool) -> void:
	if not _wrecker:
		return
	if is_instance_valid(_target_wall):
		if _target_wall.is_built():
			return
		_target_wall = null
		_wrecker = false
		return
	if not scan:
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
	_move_to(dest, delta)

func _move_to(dest: Vector3, delta: float) -> void:
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
		var dir := step.normalized()
		_refresh_separation(delta)
		var steer := dir + _sep * SEP_WEIGHT
		if steer.length_squared() > 0.0001:
			dir = steer.normalized()
		velocity = dir * SPEED[type] * _pace
		move_and_slide()
	else:
		velocity = Vector3.ZERO

# Soft push away from nearby enemies, stronger the closer they are. Swept on a timer
# and cached so a full wave isn't an O(n²) every physics tick.
func _refresh_separation(delta: float) -> void:
	_sep_t -= delta
	if _sep_t > 0.0:
		return
	_sep_t = SEP_INTERVAL
	_sep = Vector3.ZERO
	var mine: float = SEP_RADIUS * SCALE[type]
	for o in get_tree().get_nodes_in_group("enemies"):
		if o == self or not (o is Node3D):
			continue
		var off: Vector3 = global_position - o.global_position
		off.y = 0.0
		var reach: float = mine + (SEP_RADIUS * SCALE[o.type] - mine) * 0.5
		var d := off.length()
		if d >= reach:
			continue
		if d < 0.02:   # exactly stacked: any direction beats none
			off = Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU)
			d = 0.02
		_sep += off / d * (1.0 - d / reach)

# Standing attackers slide apart so they ring their target instead of piling on one spot
func _settle(delta: float) -> void:
	_refresh_separation(delta)
	if _sep.length_squared() < 0.0025:
		return
	velocity = _sep.limit_length(1.0) * SEP_SETTLE_SPEED
	move_and_slide()
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

func _try_attack_player(delta: float) -> bool:
	if _target_player == null or _dist_flat(_target_player) > ATTACK_RANGE:
		return false
	velocity = Vector3.ZERO
	if _attack_timer <= 0.0:
		_attack(_target_player, _target_player.global_position)
	else:
		_settle(delta)
		anim = "idle_" + _facing
	return true

## At a wall and working on it (watch posts shoot these first)
func is_battering() -> bool:
	return _target_player == null and _target_wall != null \
		and _target_wall.distance_to_point(global_position) <= WALL_REACH

func _try_attack_wall(delta: float) -> bool:
	if _target_player != null or _target_wall == null \
			or _target_wall.distance_to_point(global_position) > WALL_REACH:
		return false
	velocity = Vector3.ZERO
	var at: Vector3 = _target_wall.approach_point(global_position, 0.0)
	if _attack_timer <= 0.0:
		_attack(_target_wall, at)
	else:
		_settle(delta)
		anim = "idle_" + _facing
	return true

func _attack(victim: Node3D, at: Vector3) -> void:
	_attack_timer = ATTACK_CD
	_facing = CharAnim.dir_from_velocity(at - global_position, _facing)
	if GameState.tell and TELL[type] > 0.0:
		_tell = TELL[type]
		_tell_victim = victim
		_tell_at = at
		anim = "brace_" + _facing
		return
	_strike(victim)

# Drawing back: rooted, turning to follow a worker, then the blow
func _drawing(delta: float) -> void:
	velocity = Vector3.ZERO
	if is_instance_valid(_tell_victim) and _tell_victim.is_in_group("players"):
		_facing = CharAnim.dir_from_velocity(_tell_victim.global_position - global_position, _facing)
	_tell -= delta
	if _tell > 0.0:
		return
	var victim := _tell_victim
	_tell_victim = null
	if not is_instance_valid(victim):
		_update_anim()
		return
	if victim.is_in_group("players"):
		# Stepped or dashed out of reach, or already down: the spear finds air
		if victim.downed or _dist_flat(victim) > ATTACK_RANGE + TELL_SLACK:
			_strike(null)
			return
	_strike(victim)

func _strike(victim: Node3D) -> void:
	_busy = true
	anim = "thrust_" + _facing
	if victim != null:
		victim.take_damage(DAMAGE[type] * Settings.diff()["harm"])
	await _sprite.animation_finished
	if is_instance_valid(self):
		_busy = false

## Mid-draw: a blow this heavy knocks the strike aside (a brute only for a solid one)
func _breaks_tell(amount: float) -> bool:
	return _tell > 0.0 and amount >= STEADY.get(type, 0.0)

# ── Animation ──────────────────────────────────────────────

func _update_anim() -> void:
	var moving := velocity.length_squared() > 0.01
	if moving:
		_facing = CharAnim.dir_from_velocity(velocity, _facing)
	anim = ("walk" if moving else "idle") + "_" + _facing

# ── Damage (server) ────────────────────────────────────────

func take_damage(amount: float, by := 0) -> void:
	# Already dead, waiting on queue_free — ignore extra hits so died emits once
	if health <= 0.0 or _fleeing:
		return
	if by != 0:
		_last_hitter = by
	# A saboteur hit mid-climb falls back and starts over; mid-strewing, he loses his grip
	_climb_t = 0.0
	_scatter_t = 0.0
	health = maxf(health - amount, 0.0)
	hits += 1
	if health == 0.0:
		_tell = 0.0
		_die()
		return
	if _tell > 0.0:
		if not _breaks_tell(amount):
			return   # a brute set to strike doesn't flinch at a pebble
		_tell = 0.0
		_tell_victim = null
		_stagger = REEL_TIME
		_knock = Vector3.ZERO
		anim = "reel_" + _facing
		return
	_stagger = STAGGER_TIME
	_knock = Vector3.ZERO

## Server: a true shot — off his feet for a moment, whatever he was about (a draw, a climb,
## battering the wall). Shoved back along `dir` by about `dist` metres as he goes down
func knock_down(dir: Vector3, dist: float) -> void:
	if health <= 0.0 or _fleeing:
		return
	_tell = 0.0
	_tell_victim = null
	_stagger = DOWN_TIME[type]
	anim = "knocked_" + _facing
	knock_back(dir, dist)

## Server: shove back along `dir` by about `dist` metres over the stagger. Call after
## take_damage (which starts the stagger); brutes barely budge.
func knock_back(dir: Vector3, dist: float) -> void:
	if health <= 0.0 or _fleeing:
		return
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	# v0 with constant decel stops after dist: v0 = sqrt(2 * decel * dist)
	_knock = flat * sqrt(2.0 * KNOCK_DECEL * dist * KNOCK_TAKE[type])

# Collapse in place, then free (the spawner despawns it on clients)
func _die() -> void:
	died.emit()
	get_tree().call_group("day_director", "note_foe", _last_hitter)
	remove_from_group("enemies")
	$CollisionShape3D.set_deferred("disabled", true)
	velocity = Vector3.ZERO
	anim = "collapse"
	await get_tree().create_timer(CORPSE_TIME).timeout
	if is_instance_valid(self):
		queue_free()

# ── Rout (dusk) ────────────────────────────────────────────

## Server: stop fighting and run back out the way they came; freed after FLEE_TIME
func flee() -> void:
	if _fleeing or health <= 0.0:
		return
	_fleeing = true
	_busy = false
	remove_from_group("enemies")   # no aim assist, no off-screen pointers
	nav.target_position = Vector3(global_position.x * 1.4, 0.0, FLEE_Z)
	get_tree().create_timer(FLEE_TIME).timeout.connect(queue_free)

func _run_away() -> void:
	var next := nav.get_next_path_position()
	var step := next - global_position
	step.y = 0.0
	if step.length_squared() < 0.01:
		step = Vector3(0, 0, -1)
	velocity = step.normalized() * SPEED[type] * FLEE_SPEED
	move_and_slide()
	_facing = CharAnim.dir_from_velocity(velocity, _facing)
	anim = "run_" + _facing

# Every peer: at dusk the bar goes and the figure shrinks away in a puff before it's freed
func _on_phase_changed(phase: GameState.Phase) -> void:
	if (phase != GameState.Phase.DUSK and phase != GameState.Phase.WON) or health <= 0.0:
		return
	_bar.visible = false
	_sprite.squash(Vector2(0.85, 1.15))   # startled
	await get_tree().create_timer(FLEE_TIME - 0.45).timeout
	if not is_instance_valid(self):
		return
	DustFx.puff(self, global_position + Vector3.UP * 0.5, 10, 0.7)
	create_tween().tween_property(_sprite, "scale", Vector3.ONE * 0.01, 0.35) 		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

# ── Saboteur ───────────────────────────────────────────────

func is_saboteur() -> bool:
	return type == Type.SABOTEUR

## Inside the wall (the off-screen pointer and the watchman's call follow him there)
func is_inside() -> bool:
	return global_position.z > 1.5

func _saboteur(delta: float) -> void:
	if _stagger > 0.0:
		_stagger -= delta
		velocity = _knock
		if _knock != Vector3.ZERO:
			move_and_slide()
			_knock = _knock.move_toward(Vector3.ZERO, KNOCK_DECEL * delta)
		return
	if _climb_wall != null:
		_climbing(delta)
		return
	var dest: Vector3
	if _escaping:
		if global_position.z < ESCAPE_Z:
			queue_free()   # gone back into the hills
			return
		dest = Vector3(global_position.x, 0.0, ESCAPE_Z - 6.0)
	else:
		if not _pile_open(_pile):
			_pile = _choose_pile()
			if _pile == null:
				_escaping = true
				return
		dest = _pile.global_position
		if _dist_flat(_pile) < PILE_REACH:
			velocity = Vector3.ZERO
			_facing = CharAnim.dir_from_velocity(dest - global_position, _facing)
			anim = "thrust_" + _facing
			_scatter_t += delta
			if _scatter_t >= SCATTER_TIME:
				_scatter_t = 0.0
				if _pile.scatter():
					_scattered_n += 1
					get_tree().call_group("day_director", "note_scatter")
				_pile = null
				_escaping = _scattered_n >= SCATTER_MAX
			return
	var before := global_position
	_move_to(dest, delta)
	_update_anim()
	# Walled off: over the finished piece in the way
	if global_position.distance_to(before) < SPEED[type] * delta * 0.25:
		_no_headway += delta
	else:
		_no_headway = 0.0
	if _no_headway >= CLIMB_STUCK:
		_no_headway = 0.0
		var wall := _wall_in_the_way()
		if wall != null:
			_climb_wall = wall
			_climb_t = 0.0

func _pile_open(pile: Node3D) -> bool:
	return is_instance_valid(pile) and pile.is_in_group("supply_piles") and pile.has_method("scatter")

## The pile whose material the work wants now (a target piece's next need); else the nearest
func _choose_pile() -> Node3D:
	var wanted := {}
	for site: Node3D in get_tree().get_nodes_in_group("build_sites"):
		if site.get("is_target") and not site.is_complete():
			var need: String = site.next_need()
			if not need.is_empty():
				wanted[need] = true
	var best: Node3D = null
	var best_score := INF
	for pile: Node3D in get_tree().get_nodes_in_group("supply_piles"):
		if not _pile_open(pile) or pile.kind == "beam" or not pile.is_visible_in_tree():
			continue
		var score := _dist_flat(pile) - (100.0 if wanted.has(pile.kind) else 0.0)
		if score < best_score:
			best_score = score
			best = pile
	return best

func _wall_in_the_way() -> Node3D:
	var best: Node3D = null
	var best_d := WALL_REACH + 0.6
	for site: Node3D in get_tree().get_nodes_in_group("build_sites"):
		if not site.has_method("blocks_workers") or not site.blocks_workers():
			continue
		var d: float = site.distance_to_point(global_position)
		if d < best_d:
			best_d = d
			best = site
	return best

# In plain view at the wall: hauling himself up for CLIMB_TIME (a hit starts it over),
# then down on the far side
func _climbing(delta: float) -> void:
	velocity = Vector3.ZERO
	if not is_instance_valid(_climb_wall):
		_climb_wall = null
		return
	var face: Vector3 = _climb_wall.approach_point(global_position, 0.0)
	_facing = CharAnim.dir_from_velocity(face - global_position, _facing)
	anim = "thrust_" + _facing
	_climb_t += delta
	if _climb_t < CLIMB_TIME:
		return
	var here := _climb_wall.to_local(global_position)
	var far := _climb_wall.to_global(Vector3(here.x, here.y, -here.z))
	var land: Vector3 = _climb_wall.approach_point(far, CLIMB_CLEAR)
	global_position = Vector3(land.x, global_position.y, land.z)
	_climb_wall = null
	_climb_t = 0.0
	_repath_timer = 0.0
