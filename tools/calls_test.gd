extends SceneTree

# The call (Calls, GDD §5.25), offline, host + 2 Builder bots at the Sheep Gate:
#   1. bring: a call at a wall OFF the work front (bots never serve those on their own) must
#      send a bot to haul that wall's load there
#   2. cooldown: a second call straight after is ignored
#   3. hold: a call at an empty spot brings a bot to stand by it
#   4. cover: a call while the host works a wall brings a bot to stand by the host
#   5. `on = false` (as `-- --no-calls`): a call does nothing
# Exit code 0 = all passed.
#   Godot --headless --path . --script res://tools/calls_test.gd

const TIMEOUT := 40.0     # per step
const HOLD := 13          # BotBrain.Job.HOLD
const COVER := 11         # BotBrain.Job.COVER

var _main: Node
var _calls: Node
var _frame := 0
var _t := 0.0
var _step := 0
var _saved_count := 0
var _saved_skill := 0
var _host: Node3D
var _bots: Array = []
var _site: Node3D
var _kind := ""
var _had := 0
var _spot := Vector3.ZERO
var _fails := 0

func _process(delta: float) -> bool:
	_frame += 1
	_t += delta
	var gs := root.get_node("GameState")
	if _frame == 1:
		var settings := root.get_node("Settings")
		_saved_count = settings.bot_count
		_saved_skill = settings.bot_skill
		settings.bot_count = 2
		settings.bot_skill = 1
		gs.replay_section = 0
		_main = load("res://scenes/main/main.tscn").instantiate()
		root.add_child(_main)
		current_scene = _main
		return false
	if _frame == 3:
		_main.director.begin()
	if gs.phase in [gs.Phase.STORY, gs.Phase.DUSK]:
		_main.director.force_ready()
	if gs.phase != gs.Phase.WORK:
		return false
	if _host == null:
		for p in _main.players_root.get_children():
			if p.brain == null:
				_host = p
			else:
				_bots.append(p)
		_calls = get_first_node_in_group("calls")
		_t = 0.0
	match _step:
		0: return _bring()
		1: return _cooldown()
		2: return _hold()
		3: return _cover()
		4: return _off()
	return _finish(1 if _fails > 0 else 0)

func _bring() -> bool:
	var front = load("res://scenes/shared/work_front.gd")
	if _site == null:
		for s in get_nodes_in_group("wall_sections"):
			if s.is_target and not front.is_open(s) and not s.next_need().is_empty():
				_site = s
				break
		if _site == null:
			print("SKIP bring: every wall is on the work front")
			return _next()
		_kind = _site.next_need()
		_had = _site.pending.get(_kind, 0)
		_calls.request(_host, _site.global_position)
		var ordered := _bots.filter(func(b): return b.brain._order.get("kind", "") == "bring")
		_check(ordered.size() == 1, "bring: one bot took the order (%s to %s)" % [_kind, _site.name])
		return false
	if _site.pending.get(_kind, 0) > _had or not _site.needs(_kind):
		_check(true, "bring: %s delivered to the closed wall in %.1f s" % [_kind, _t])
		return _next()
	if _t > TIMEOUT:
		_check(false, "bring: nothing delivered (bot jobs %s)" % str(_bots.map(func(b): return b.brain._job)))
		return _next()
	return false

func _cooldown() -> bool:
	_calls._ready_at[_host.worker_id()] = Time.get_ticks_msec() + 1000   # as if just called
	var before := _calls.get_child_count()
	_calls.request(_host, _host.global_position)
	_check(_calls.get_child_count() == before, "cooldown: a call inside 1.2 s is ignored")
	_calls._ready_at.clear()
	for b in _bots:
		b.brain._order = {}
	return _next()

func _hold() -> bool:
	if _spot == Vector3.ZERO:
		# Inside the wall, away from everyone and every site
		_spot = Vector3(_host.global_position.x + 7.0, 0.0, _host.global_position.z + 4.0)
		_calls.request(_host, _spot)
		return false
	for b in _bots:
		if b.brain._job == HOLD and Vector2(b.global_position.x - _spot.x, b.global_position.z - _spot.z).length() < 2.6:
			_check(true, "hold: a bot stands by the call in %.1f s" % _t)
			return _next()
	if _t > 7.5:   # the standard folds at 8 s
		_check(false, "hold: no bot reached the spot (jobs %s)" % str(_bots.map(func(b): return b.brain._job)))
		return _next()
	return false

func _cover() -> bool:
	if _host.building_site == null:
		var site: Node3D = null
		for s in get_nodes_in_group("wall_sections"):
			if s.is_target and (site == null or s.global_position.distance_to(_host.global_position) < site.global_position.distance_to(_host.global_position)):
				site = s
		_host.global_position = site.approach_point(_host.global_position, 0.6)
		_host.building_site = site
		_calls._ready_at.clear()
		_calls.request(_host, _host.global_position)
		var ordered := _bots.filter(func(b): return b.brain._order.get("kind", "") == "cover")
		_check(ordered.size() == 1, "cover: one bot took the order")
		return false
	for b in _bots:
		if b.brain._job == COVER and b.global_position.distance_to(_host.global_position) < 3.5:
			_check(true, "cover: a bot came to the host's side in %.1f s, said \"%s\"" % [
				_t, b._bark_shout.text if b._bark_shout else "?"])
			_host.building_site = null
			return _next()
	if _t > TIMEOUT:
		_check(false, "cover: no bot came (jobs %s)" % str(_bots.map(func(b): return b.brain._job)))
		_host.building_site = null
		return _next()
	return false

func _off() -> bool:
	_calls.on = false
	_calls._ready_at.clear()
	for b in _bots:
		b.brain._order = {}
	var before := _calls.get_child_count()
	_calls.request(_host, _host.global_position)
	_check(_calls.get_child_count() == before and _bots.all(func(b): return b.brain._order.is_empty()),
		"off: no standard, no order")
	_calls.on = true
	return _next()

func _next() -> bool:
	_step += 1
	_t = 0.0
	return false

func _check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok:
		_fails += 1

func _finish(code: int) -> bool:
	var settings := root.get_node("Settings")
	settings.bot_count = _saved_count
	settings.bot_skill = _saved_skill
	quit(code)
	return true
