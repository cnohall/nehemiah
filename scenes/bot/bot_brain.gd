class_name BotBrain
extends RefCounted

# A bot worker's head. Runs on the host only, inside its Player's _physics_process, and
# drives that Player through the same inputs a person would (Player reads `move`,
# `take_press`, `throw_pressed`, `aim_point`, `charge_goal` when it has a brain), so
# carrying, delivering, working, the sling, beams and networking are the Player's own.
#
# Each think (every skill["think"] seconds) picks one job, in order:
#   revive a fallen worker → take the other end of a lone beam → deliver what's carried →
#   work a wall that has all its loads → fetch what the walls still miss → guard.
# Between thinks it walks the job's path (NavigationServer, the enemies' mesh) and, on top
# of any job, slings at enemies that threaten the wall or the crew.
# Twists it doesn't know yet (horn, haul relays) fall back to the jobs above.

enum Job { IDLE, REVIVE, HELP_BEAM, DELIVER, WORK, FETCH, GUARD }

# Apprentice / Builder / Master builder. think = seconds between decisions; speed = stick
# push (1 = full run); aim_err = metres off the enemy; charge = least wind-up;
# reach = how far a threat is noticed; dawdle = chance to stand about at a decision;
# ono = chance of going with the messenger when he asks; guard = leaves the wall work to
# see off an enemy that comes close; crew = how much of a worker the bot counts as when
# WaveManager sizes the enemy to the crew (a weak bot shouldn't bring a full worker's foes);
# about = the one line the gathering screen shows under the choice
const SKILLS := [
	{ "name": "Apprentice",     "think": 0.7,  "speed": 0.72, "aim_err": 2.2,  "charge": 0.35, "reach": 6.0,  "dawdle": 0.12, "ono": 0.35, "guard": false, "crew": 0.5,
		"about": "Slow, misses often, may wander off" },
	{ "name": "Builder",        "think": 0.4,  "speed": 0.88, "aim_err": 1.0,  "charge": 0.6,  "reach": 8.5,  "dawdle": 0.04, "ono": 0.08, "guard": false, "crew": 0.75,
		"about": "Steady hands, a fair aim" },
	{ "name": "Master builder", "think": 0.18, "speed": 1.0,  "aim_err": 0.35, "charge": 0.8,  "reach": 10.0, "dawdle": 0.0,  "ono": 0.0,  "guard": true,  "crew": 1.0,
		"about": "Quick, sure shot, leaves the work to guard" },
]

const ARRIVE        := 0.5    # close enough to a path point
const REPATH        := 0.6    # seconds between path refreshes
const STUCK_TIME    := 1.0    # no progress for this long → sidestep
const STUCK_DIST    := 0.3
const SIDESTEP_TIME := 0.5
const REVIVE_RANGE  := 60.0   # how far a bot will go to lift a fallen worker — anywhere: there's no self-revive
const BEAM_RANGE    := 12.0
const WALL_THREAT   := 3.5    # an enemy this close to a built wall is battering it
const CREW_THREAT   := 5.0    # …or this close to a worker is after them
const WORK_BREAK    := 4.5    # a Master builder leaves the work for an enemy this close
const FOLLOW_GAP    := 1.6    # holding a beam's far end: keep this close to the carrier
const GUARD_BACK    := 2.5    # guards stand this far inside the wall they watch
const THREAT_BONUS  := 4.0    # metres a harmful enemy is treated as nearer, for the sling
const TROUGH_PRIORITY := 30.0 # fetch score bonus for the trough's lime and water
const SPACING       := 1.2    # workers don't collide: a bot edges away from any this close…
const SPREAD_PUSH   := 0.6    # …this hard (stick units) when right on top of them

# Read by Player
var move := Vector2.ZERO          # screen-space stick, like Input.get_vector
var throw_pressed := false        # Player clears it when the wind-up starts
var aim_point := Vector3.ZERO
var charge_goal := 1.0

var skill: Dictionary
var _p: Player
var _presses := {}
var _think := 0.0
var _job := Job.IDLE
var _target: Node3D               # site / pile / item / worker the job is about
var _fetch_kind := ""             # the material this bot is on its way for
var _dest := Vector3.ZERO
var _path := PackedVector3Array()
var _path_i := 0
var _repath := 0.0
var _stuck_t := 0.0
var _stuck_from := Vector3.ZERO
var _sidestep := 0.0
var _sidestep_dir := Vector3.ZERO
var _dawdle := 0.0
var _foe: Node3D                  # enemy being wound up for
var _aim_off := Vector3.ZERO
var _ono := {}                    # messenger → true/false: go with him when he asks?

func _init(player: Player, skill_index: int) -> void:
	_p = player
	set_skill(skill_index)
	_think = randf() * skill["think"]   # out of step with the other bots from the first decision

func set_skill(index: int) -> void:
	skill = SKILLS[clampi(index, 0, SKILLS.size() - 1)]

## Player: was `action` pressed this frame? (one frame per press, like just_pressed)
func take_press(action: String) -> bool:
	return _presses.erase(action)

func _press(action: String) -> void:
	_presses[action] = true

# ── Every physics frame (host) ─────────────────────────────

func think(delta: float) -> void:
	move = Vector2.ZERO
	if not _can_act():
		throw_pressed = false
		_job = Job.IDLE
		return
	_think -= delta
	_dawdle -= delta
	if _think <= 0.0:
		_think = skill["think"] * randf_range(0.8, 1.2)
		_decide()
	_sling()
	if _p._work_site != null:
		return
	if _dawdle <= 0.0:
		_act(delta)
	_spread()

func _can_act() -> bool:
	if _p.downed or _p._led_by != null or _p._is_busy:
		return false
	return GameState.phase == GameState.Phase.WORK or GameState.phase == GameState.Phase.DAWN

# ── Choosing a job ─────────────────────────────────────────

func _decide() -> void:
	if _p._work_site != null:
		# At the wall: stay with it, unless (Master builder) an enemy is right on us
		if skill["guard"] and _nearest_foe(WORK_BREAK) != null:
			_set_job(Job.GUARD, null)
			_step_off()
		return
	if _p.helping_id != 0:
		_set_job(Job.HELP_BEAM, _p._beam_partner())
		return
	if randf() < skill["dawdle"]:
		_dawdle = randf_range(0.8, 2.0)
		return
	var fallen := _nearest_worker(REVIVE_RANGE, func(w): return w.downed)
	if fallen != null:
		_set_job(Job.REVIVE, fallen)
		return
	if not _p.carried_kind.is_empty():
		# The wall comes first — except a watch post that has run dry, which gets the
		# next stone. Otherwise a post takes what no wall wants.
		var site := _empty_post() if _p.carried_kind == "stone" else null
		if site == null:
			site = _nearest_site(func(s): return s.needs(_p.carried_kind))
		if site == null:
			site = _nearest_post(func(s): return s.needs(_p.carried_kind) and (s.built or _posts_ok()))
		if site != null:
			_set_job(Job.DELIVER, site)
		elif _p.carried_kind in ["lime", "water"] and _trough() != null:
			var trough := _trough()
			if trough.mortar_ready and _dist(trough) < Player.INTERACT_REACH + 1.0:
				# Mortar is waiting in it and our load can't go in until someone takes it:
				# set ours down here (it'll be picked up again) and carry the mortar
				_press("drop")
				_set_job(Job.FETCH, trough)
				_fetch_kind = "mortar"
			else:
				_set_job(Job.DELIVER, trough)   # the next batch: wait by the trough with it
		else:
			_press("drop")   # nobody wants it (the wall moved on) — clear the hands
			_set_job(Job.IDLE, null)
		return
	# Beams go in pairs: take the far end of a lone one, or tag along with a bot on its
	# way to fetch one (unless someone already is)
	var carrier := _nearest_worker(BEAM_RANGE, func(w):
		return (w.carried_kind == "beam" and w._beam_partner() == null 			or w.brain != null and w.brain._fetch_kind == "beam") and not _escorted(w))
	if carrier != null:
		_set_job(Job.HELP_BEAM, carrier)
		return
	if _guards() < _guards_wanted():
		_set_job(Job.GUARD, _site_facing(_foes_near_work()))
		return
	var ready := _nearest_site(func(s): return s.can_build() and s.work() != null \
		and (s.work().builder_count() < 2 or _job == Job.WORK and _target == s))
	if ready == null:
		ready = _nearest_post(func(s): return _posts_ok() and s.can_build() \
			and (s.work().builder_count() < 1 or _job == Job.WORK and _target == s))
	if ready != null:
		_set_job(Job.WORK, ready)
		return
	var source := _pick_fetch()
	if source != null:
		_set_job(Job.FETCH, source)
		return
	_set_job(Job.GUARD, _nearest_site(func(_s): return true))

# Another bot is already on its way to hold this one's beam
func _escorted(w: Node3D) -> bool:
	for b in _p.get_tree().get_nodes_in_group("players"):
		if b != _p and b.brain != null and b.brain._job == Job.HELP_BEAM and b.brain._target == w:
			return true
	return false

# Enemies closing on today's work, and how many bots should stand guard against them:
# one per GUARD_PER foes, always leaving one bot on the building
const GUARD_PER := 4
const GUARD_RANGE := 14.0

func _foes_near_work() -> Array:
	var sites := _p.get_tree().get_nodes_in_group("wall_sections").filter(func(s): return s.is_target)
	return _p.get_tree().get_nodes_in_group("enemies").filter(func(e):
		return sites.any(func(s): return s.distance_to_point(e.global_position) < GUARD_RANGE))

func _guards_wanted() -> int:
	var bots := _p.get_tree().get_nodes_in_group("players").filter(func(w): return w.brain != null).size()
	return mini(ceili(_foes_near_work().size() / float(GUARD_PER)), bots - 1)

func _guards() -> int:
	return _p.get_tree().get_nodes_in_group("players").filter(func(w):
		return w != _p and w.brain != null and w.brain._job == Job.GUARD).size()

# The day's wall nearest the enemies' middle — where a guard stands
func _site_facing(foes: Array) -> Node3D:
	if foes.is_empty():
		return _nearest_site(func(_s): return true)
	var mid := Vector3.ZERO
	for e: Node3D in foes:
		mid += e.global_position
	mid /= foes.size()
	var best: Node3D = null
	var best_d := INF
	for s in _p.get_tree().get_nodes_in_group("wall_sections"):
		if s.is_target and s.distance_to_point(mid) < best_d:
			best_d = s.distance_to_point(mid)
			best = s
	return best

func _set_job(job: Job, target: Node3D) -> void:
	if job != _job or target != _target:
		_path = PackedVector3Array()
		_repath = 0.0
	_job = job
	_target = target
	if job != Job.FETCH:
		_fetch_kind = ""

## What the day's walls still miss, less what others are already carrying or fetching —
## the nearest source of the most-wanted material, or null when it's all covered
func _pick_fetch() -> Node3D:
	var missing := {}
	for s in _sites():
		for kind: String in _missing(s):
			missing[kind] = missing.get(kind, 0) + _missing(s)[kind]
	# Watch posts: one load at a time on top of the wall's needs (timber to raise one,
	# stone to keep one throwing)
	var post := _nearest_post(func(s): return not s.next_need().is_empty() and (s.built or _posts_ok()))
	if post != null:
		var need: String = post.next_need()
		missing[need] = missing.get(need, 0) + 1
	# Mortar comes a batch at a time from the trough: while one mixes, bring the next
	var trough := _trough()
	if trough != null and missing.get("mortar", 0) >= 2:
		for kind: String in ["lime", "water"]:
			missing[kind] = missing.get(kind, 0) + 1
	for w in _p.get_tree().get_nodes_in_group("players"):
		if w == _p:
			continue
		var k: String = w.carried_kind
		if k.is_empty() and w.brain != null:
			k = w.brain._fetch_kind
		if missing.has(k):
			missing[k] -= 1
	var best: Node3D = null
	var best_score := -INF
	for kind: String in missing:
		if missing[kind] <= 0:
			continue
		var src := _nearest_source(kind)
		if src == null:
			continue   # e.g. the trough is still mixing
		var score: float = missing[kind] * 4.0 - _dist(src)
		# The trough is the bottleneck of a mixing section: its lime and water come before
		# more stone for the wall, or a half-filled trough waits all day (and every wall
		# with it, stuck at "needs mortar")
		if kind == "lime" or kind == "water":
			score += TROUGH_PRIORITY
		if score > best_score:
			best_score = score
			best = src
			_fetch_kind = kind
	return best

## The mortar trough, in a "mixing" section (else null)
func _trough() -> Node3D:
	for group in ["build_sites", "supply_piles"]:
		for n in _p.get_tree().get_nodes_in_group(group):
			if "mortar_ready" in n:
				return n
	return null

## kind → loads still to bring for the site's next stage
func _missing(site: Node3D) -> Dictionary:
	if "mortar_ready" in site:
		var want := {}
		for kind: String in ["lime", "water"]:
			if site.needs(kind):
				want[kind] = 1
		return want
	if site.has_method("cost_for") and site.get("pending") is Dictionary:
		var out := {}
		var cost: Dictionary = site.cost_for(site.stage + 1)
		for kind: String in cost:
			var left: int = cost[kind] - site.pending.get(kind, 0)
			if left > 0:
				out[kind] = left
		return out
	var need: String = site.next_need()
	return {} if need.is_empty() else { need: 1 }

# Today's build sites that still want loads: the target walls and gates, plus the trough
func _sites() -> Array:
	return _p.get_tree().get_nodes_in_group("build_sites").filter(func(s):
		return (not "is_target" in s or s.is_target) and not s.next_need().is_empty() and WorkFront.is_open(s))

func _nearest_site(accept: Callable) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for s in _p.get_tree().get_nodes_in_group("build_sites"):
		if "is_target" in s and not s.is_target or not WorkFront.is_open(s):
			continue
		if not accept.call(s):
			continue
		var d := _dist(s)
		if d < best_d:
			best_d = d
			best = s
	return best

# Watch posts (GameState.posts): not among the day's targets, so looked up on their own
func _nearest_post(accept: Callable) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for s in _p.get_tree().get_nodes_in_group("watch_posts"):
		if not s.is_visible_in_tree() or not accept.call(s):
			continue
		var d := _dist(s)
		if d < best_d:
			best_d = d
			best = s
	return best

# Raising a new post is worth the timber only while the wall is on track: not on the
# stretch's last day, and at least as far along as the days gone by
func _posts_ok() -> bool:
	if not GameState.sun:
		return true
	var pos := GameState.day_in_section(GameState.current_day)
	if pos.x == pos.y - 1:
		return false
	return GameState.targets_done >= GameState.targets_total * pos.x / float(pos.y)

# A standing post out of stones that no other bot is already taking stone to
func _empty_post() -> Node3D:
	return _nearest_post(func(s):
		if not s.built or s.ammo > 0:
			return false
		for w in _p.get_tree().get_nodes_in_group("players"):
			if w != _p and w.brain != null and w.brain._job == Job.DELIVER and w.brain._target == s:
				return false
		return true)

# A load of `kind`: lying on the ground, or a pile (the trough counts once it's mixed)
func _nearest_source(kind: String) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for group in ["dropped_items", "supply_piles"]:
		for n in _p.get_tree().get_nodes_in_group(group):
			if n.kind != kind:
				continue
			var d := _dist(n)
			if d < best_d:
				best_d = d
				best = n
	return best

func _nearest_worker(within: float, accept: Callable) -> Node3D:
	var best: Node3D = null
	var best_d := within
	for w in _p.get_tree().get_nodes_in_group("players"):
		if w == _p or not accept.call(w):
			continue
		var d := _dist(w)
		if d < best_d:
			best_d = d
			best = w
	return best

# ── Doing it ───────────────────────────────────────────────

func _act(delta: float) -> void:
	# Gone since we chose it (an item someone else picked up, a teammate who left)
	if _job != Job.IDLE and not is_instance_valid(_target):
		_set_job(Job.IDLE, null)
		return
	match _job:
		Job.REVIVE:
			_go_and_press(_target, Player.REVIVE_REACH - 0.3, Player.Act.REVIVE, delta)
		Job.HELP_BEAM:
			if _p.helping_id != 0:
				_follow_carrier(delta)
			else:
				_go_and_press(_target, Player.BEAM_HELP_REACH - 0.4, Player.Act.HELP, delta)
		Job.DELIVER:
			_go_and_press(_target, Player.INTERACT_REACH - 0.6, Player.Act.DELIVER, delta)
		Job.WORK:
			_go_and_press(_target, Player.INTERACT_REACH - 0.6, Player.Act.WORK, delta)
		Job.FETCH:
			var act := Player.Act.TAKE_ITEM if _target.is_in_group("dropped_items") else Player.Act.TAKE_PILE
			_go_and_press(_target, Player.INTERACT_REACH - 0.6, act, delta)
		Job.GUARD:
			if _target != null:
				_walk_to(_guard_spot(_target), delta, 1.0)

# Walk up to `target`; once in reach, press interact — but only when the press would do
# what we mean (Player._interact_choice), so a messenger at our elbow doesn't get it by
# accident. Sidestep him instead, unless this bot has decided to go.
func _go_and_press(target: Node3D, reach: float, want: Player.Act, delta: float) -> void:
	var choice: Array = _p._interact_choice(_p.global_position)
	if choice[0] == want and choice[1] == target:
		_press("interact")
		return
	if choice[0] == Player.Act.MESSENGER and _p._reach_dist(target, _p.global_position) <= reach + 1.0:
		if _goes_to_ono(choice[1]):
			_press("interact")
		else:
			_steer(_flat(_p.global_position - choice[1].global_position).normalized())
		return
	# Not yet (or something else is nearer to hand): walk right up to it
	var spot: Vector3 = target.approach_point(_p.global_position, 0.6) \
		if target.has_method("approach_point") else target.global_position
	if _flat(spot - _p.global_position).length() > ARRIVE:
		_walk_to(spot, delta, ARRIVE)
	else:
		_steer(_flat(target.global_position - _p.global_position).normalized() * 0.5)

func _goes_to_ono(messenger: Node3D) -> bool:
	if not _ono.has(messenger):
		_ono[messenger] = randf() < skill["ono"]
	return _ono[messenger]

func _follow_carrier(_delta: float) -> void:
	var carrier := _p._beam_partner()
	if carrier == null:
		return
	var off := _flat(carrier.global_position - _p.global_position)
	var dir := _flat(carrier.velocity)
	if off.length() > FOLLOW_GAP:
		dir += off
	if dir.length() > 0.2:
		_steer(dir.normalized())

# Just inside the wall, between it and the yard
func _guard_spot(site: Node3D) -> Vector3:
	var yard := GameState.yard_center()
	var toward_yard := Vector3(yard.x, 0.0, yard.y)
	var at: Vector3 = site.approach_point(toward_yard, GUARD_BACK) if site.has_method("approach_point") else site.global_position
	return at

func _step_off() -> void:
	_steer(_flat(Vector3(randf_range(-1, 1), 0, randf_range(0.2, 1))).normalized())

# ── Sling ──────────────────────────────────────────────────

# Wind up at the most pressing enemy in reach, aim (with this skill's error) while the
# charge builds, and let go once it's enough to carry that far
func _sling() -> void:
	if _p._charging:
		if not is_instance_valid(_foe) or not _foe.is_in_group("enemies"):
			charge_goal = 0.0   # it fell — throw now and move on
			return
		aim_point = _foe.global_position + _aim_off
		return
	if throw_pressed or _p._sling_cd > 0.0 or _p._work_site != null \
			or _p.carried_kind == "beam" or _p.helping_id != 0:
		return
	_foe = _pressing_foe()
	if _foe == null:
		return
	var d := _dist(_foe)
	var need := clampf((d - Player.SLING_MIN_RANGE) / (Player.SLING_MAX_RANGE - Player.SLING_MIN_RANGE) + 0.1, 0.0, 1.0)
	charge_goal = maxf(need, skill["charge"])
	var err: float = skill["aim_err"]
	_aim_off = Vector3(randf_range(-err, err), 0.0, randf_range(-err, err))
	aim_point = _foe.global_position + _aim_off
	throw_pressed = true

# In reach and doing harm: battering a built wall, or on a worker. Nearest wins.
# Any enemy in reach will do; those battering a wall or on a worker count as nearer
func _pressing_foe() -> Node3D:
	var reach: float = minf(skill["reach"], Player.SLING_MAX_RANGE)
	var best: Node3D = null
	var best_score := INF
	for e: Node3D in _p.get_tree().get_nodes_in_group("enemies"):
		var d := _dist(e)
		if d > reach:
			continue
		var score := d - (THREAT_BONUS if _threatens(e) else 0.0)
		if score < best_score:
			best_score = score
			best = e
	return best

func _threatens(e: Node3D) -> bool:
	for w in _p.get_tree().get_nodes_in_group("players"):
		if not w.downed and _flat(w.global_position - e.global_position).length() < CREW_THREAT:
			return true
	for s in _p.get_tree().get_nodes_in_group("wall_sections"):
		if s.is_built() and s.distance_to_point(e.global_position) < WALL_THREAT:
			return true
	return false

func _nearest_foe(within: float) -> Node3D:
	for e: Node3D in _p.get_tree().get_nodes_in_group("enemies"):
		if _dist(e) < within:
			return e
	return null

# ── Walking ────────────────────────────────────────────────

func _walk_to(dest: Vector3, delta: float, arrive: float) -> void:
	var flat_to := _flat(dest - _p.global_position)
	if flat_to.length() <= arrive:
		return
	if _sidestep > 0.0:
		_sidestep -= delta
		_steer(_sidestep_dir)
		return
	_repath -= delta
	if _path.is_empty() or _repath <= 0.0 or _dest.distance_to(dest) > 1.0:
		_plan_path(dest)
	while _path_i < _path.size() and _flat(_path[_path_i] - _p.global_position).length() < ARRIVE:
		_path_i += 1
	var next := dest if _path_i >= _path.size() else _path[_path_i]
	_steer(_flat(next - _p.global_position).normalized())
	_check_stuck(delta)

func _plan_path(dest: Vector3) -> void:
	_dest = dest
	_repath = REPATH
	_path_i = 0
	var map := _p.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		_path = PackedVector3Array()   # not baked yet: head straight there
		return
	_path = NavigationServer3D.map_get_path(map, _p.global_position,
		NavigationServer3D.map_get_closest_point(map, dest), true)

# Walking but not getting anywhere (a pile, a friend, a corner): step aside for a moment
func _check_stuck(delta: float) -> void:
	_stuck_t += delta
	if _stuck_t < STUCK_TIME:
		return
	if _p.global_position.distance_to(_stuck_from) < STUCK_DIST:
		var fwd := _flat(_dest - _p.global_position).normalized()
		_sidestep_dir = fwd.cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
		_sidestep = SIDESTEP_TIME
		_path = PackedVector3Array()
	_stuck_t = 0.0
	_stuck_from = _p.global_position

# Workers pass through each other, so keep bots from sharing a spot: edge away from anyone
# too close (people included — a bot gives way, a person never gets shoved). The beam
# partner and the fallen are left alone; those need us close.
func _spread() -> void:
	var partner := _p._beam_partner()
	var push := Vector3.ZERO
	for w in _p.get_tree().get_nodes_in_group("players"):
		if w == _p or w == partner or w.downed:
			continue
		var off := _flat(_p.global_position - w.global_position)
		var d := off.length()
		if d >= SPACING:
			continue
		if d < 0.05:   # right on top: a way of our own (by id), so the two part
			off = Vector3.RIGHT.rotated(Vector3.UP, float(_p.get_instance_id() % 360))
		push += off.normalized() * (1.0 - d / SPACING)
	if push == Vector3.ZERO:
		return
	move = (move + Vector2(push.dot(Player.SCREEN_RIGHT), push.dot(Player.SCREEN_DOWN)) * SPREAD_PUSH).limit_length(1.0)

# Ground direction → the screen-space stick Player expects (SCREEN_RIGHT/DOWN are orthonormal)
func _steer(dir: Vector3) -> void:
	var v := Vector2(dir.dot(Player.SCREEN_RIGHT), dir.dot(Player.SCREEN_DOWN))
	move = v.limit_length(1.0) * skill["speed"]

func _dist(n: Node3D) -> float:
	return _p._reach_dist(n, _p.global_position)

static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
