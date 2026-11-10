extends SceneTree

# The first day teaches itself (FirstSteps, DayDirector's first-load wait, GDD §5.26):
#   Godot --path . --script res://tools/first_steps_test.gd -- --nostory --hints [<out_dir>]
#     no foe and no sun until the first load; each tag in turn, by really doing each job
#     (real interact RPCs; the load is walked in, no press); a bot's load doesn't end the wait; a sling tag once a foe is near
#   ... -- --nostory --hints --waitout    the wait gives up at FIRST_LOAD_WAIT
#   ... -- --nostory                      hints off: no tag, foes and sun at once
#   ... -- --nostory --hints --learned    all learned: no tag, the wait still holds
# Network, one headless each: ... -- --nostory --hints --host / --client
#     the client's own load ends the wait; its tags are its own, the host learns nothing
# Exit code 0 = every check passed.

var _main: Node
var _gs: Node
var _settings: Node
var _steps: Node
var _frame := 0
var _t := 0.0
var _mark := 0.0
var _state := "start"
var _fails := 0
var _out := ""
var _mode := "offline"
var _peer: ENetMultiplayerPeer

func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	var args := OS.get_cmdline_user_args()
	for a in args:
		if not a.begins_with("--"):
			_out = a
		elif a == "--host" or a == "--client":
			_mode = a.trim_prefix("--")
	_gs = root.get_node("GameState")
	_settings = root.get_node("Settings")
	if _mode == "offline":
		_start_game()

func _start_game() -> void:
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_t += delta
	if _t > 150.0:
		_check(false, "timed out in " + _state)
		return _finish()
	if _mode != "offline":
		return _network()
	match _state:
		"start":
			_main.fit_bots(0)
			if "--learned" in OS.get_cmdline_user_args():
				for l in _lessons():
					_settings.learned[l] = true
			_main.director.begin()
			_state = "to_work"
		"to_work":
			if _gs.phase == _gs.Phase.STORY:
				_main.director.force_ready()
			elif _gs.phase == _gs.Phase.WORK:
				_steps = _find_steps()
				_check(_steps != null, "FirstSteps is on the real game")
				_mark = _t
				var args := OS.get_cmdline_user_args()
				if "--hints" not in args:
					_state = "hints_off"
				elif "--learned" in args:
					_state = "learned"
				elif "--waitout" in args:
					_state = "waitout"
				else:
					_state = "pile"
		"hints_off":
			if _t - _mark > 6.0:
				_check(not _steps._guide.visible, "hints off: no tag")
				_check(_gs.sun_left < _gs.sun_total, "hints off: the sun runs")
				_check(_main.get_node("WaveManager")._active, "hints off: the waves run")
				return _finish()
		"learned":
			if _t - _mark > 5.0:
				_check(not _steps._guide.visible, "all learned: no tag")
				_check(not _steps.speaking, "all learned: the HUD line speaks")
				_check(_gs.sun_held, "all learned: the wait still holds")
				return _finish()
		"waitout":
			if _t - _mark > _main.director.FIRST_LOAD_WAIT + 1.0:
				_check(not _gs.sun_held, "wait gave up: the sun runs")
				_check(_main.get_node("WaveManager")._active, "wait gave up: the waves run")
				return _finish()
		"pile":
			if _t - _mark > 1.0:
				_check(_gs.sun_held, "the sun waits")
				_check(_steps._guide.visible and "Pick up" in _steps._guide.text, "tag on the pile: '%s'" % _steps._guide.text)
				_check(_steps.speaking, "the HUD line stays quiet")
				_shot("pile")
				_mark = _t
				_state = "walk"
		"walk":
			if _t - _mark > _steps.WALK_WAIT:
				_check("Walk" in _steps._guide.text, "standing still: tag says walk ('%s')" % _steps._guide.text)
				_shot("walk")
				_state = "walked"
				_me().global_position += Vector3(_steps.WALK_DONE + 1.0, 0, 0)
				_mark = _t
		"walked":
			if _t - _mark > 0.3:
				_check(_settings.has_learned("walk"), "walking is learned")
				_check("Pick up" in _steps._guide.text, "back to the pile")
				_check(_main.enemies_root.get_child_count() == 0, "still no foe, %.0f s in" % _t)
				# A bot's load does not end the wait
				_main.director.note_load(_me().BOT_ID_BASE + 1)
				_check(_gs.sun_held, "a bot's load doesn't end the wait")
				_take()
				_mark = _t
				_state = "carrying"
		"carrying":
			if _t - _mark > 0.3:
				_check(not _me().carried_kind.is_empty(), "picked up %s" % _me().carried_kind)
				_check(_settings.has_learned("carry"), "carrying is learned")
				_check("Carry it here" in _steps._guide.text, "tag on the wall: '%s'" % _steps._guide.text)
				_check(_steps._trail.visible and _steps._trail.multimesh.visible_instance_count > 0,
					"a trail to the wall (%d prints)" % _steps._trail.multimesh.visible_instance_count)
				_shot("deliver")
				_walk_in()
				_mark = _t
				_state = "at_wall"
		"at_wall":
			if _t - _mark > 0.3:
				_check(_me().loads_brought == 0, "walking in alone doesn't deliver")
				_check("Deliver" in _steps._guide.text, "at the wall the tag names the button: '%s'" % _steps._guide.text)
				_shot("deliver_press")
				_give()
				_mark = _t
				_state = "delivered"
		"delivered":
			if _t - _mark > 0.3:
				_check(_me().loads_brought == 1, "delivered (%d)" % _me().loads_brought)
				_check(_settings.has_learned("deliver"), "delivering is learned")
				_check(not _steps._trail.visible, "the trail is gone once delivered")
				_check(not _gs.sun_held, "the first load lets the sun go")
				_check(_main.get_node("WaveManager")._active, "the first load lets the waves go")
				_mark = _t
				_state = "building"
		"building":
			if _settings.has_learned("build"):
				_check(true, "building is learned (%.0f s after the load)" % (_t - _mark))
				_state = "sling"
				_me()._work_site = null
				_mark = _t
			elif _t - _mark > 0.5:
				# Not yet all in: bring what the site still needs, until the work starts
				if _me().carried_kind.is_empty():
					_take()
				else:
					_give()
				_mark = _t
		"sling":
			var foe: Node3D = _nearest_foe()
			if foe == null:
				return false   # the waves are on: the first scout is coming
			foe.global_position = _me().global_position + Vector3(7, 0, 0)
			_state = "sling_tag"
			_mark = _t
		"sling_tag":
			if _t - _mark > 0.1:
				_check("sling" in _steps._guide.text.to_lower(), "a foe near: '%s'" % _steps._guide.text)
				_shot("sling")
				_me()._charging = true
				_mark = _t
				_state = "sling_aim"
		"sling_aim":
			if _t - _mark > 0.1:
				_check("Aim" in _steps._guide.text, "whirling: '%s'" % _steps._guide.text)
				_me().release_throw()
				_mark = _t
				_state = "sling_done"
		"sling_done":
			if _t - _mark > 0.1:
				_check(_settings.has_learned("sling"), "the sling is learned")
				_check(_settings.all_learned(_lessons()), "all learned")
				_check(not _steps._guide.visible, "no more tags")
				return _finish()
	return false

## Network: the host waits for the client; the client takes a load and delivers it
func _network() -> bool:
	match _state:
		"start":
			_peer = ENetMultiplayerPeer.new()
			if _mode == "host":
				_peer.create_server(24713, 4)
			else:
				_peer.create_client("127.0.0.1", 24713)
			root.multiplayer.multiplayer_peer = _peer
			_start_game()
			_state = "joined"
		"joined":
			if _mode == "host":
				if root.multiplayer.get_peers().size() >= 1:
					_main.fit_bots(0)
					_main.director.begin()
					_state = "to_work"
			elif _me() != null and _gs.phase != _gs.Phase.GATHER:
				_state = "to_work"
		"to_work":
			if _mode == "host" and _gs.phase == _gs.Phase.STORY:
				_main.director.force_ready()
			if _gs.phase == _gs.Phase.WORK:
				_steps = _find_steps()
				_check(_steps != null, "FirstSteps runs here too")
				_mark = _t
				_state = "client_load" if _mode == "client" else "host_wait"
		"host_wait":
			if not _gs.sun_held:
				_check(_main.get_node("WaveManager")._active, "the client's load let the waves go")
				_check(not _settings.has_learned("carry"), "the host learned nothing from it")
				_mark = _t
				_state = "host_done"
			elif _gs.sun_left != _gs.sun_total:
				_check(false, "the sun must wait for the client's load")
				return _finish()
		"host_done":
			if _t - _mark > 6.0:
				return _finish()
		"client_load":
			if _t - _mark > 1.0:
				_check(_gs.sun_held, "client: the sun is held")
				_check("Pick up" in _steps._guide.text, "client: own tag on the pile ('%s')" % _steps._guide.text)
				_take()
				_mark = _t
				_state = "client_give"
		"client_give":
			if _t - _mark > 0.5:
				_check(_settings.has_learned("carry"), "client: carrying is learned")
				_check("Carry it here" in _steps._guide.text, "client: tag on the wall")
				_check(_steps._trail.visible, "client: a trail to the wall")
				_give()
				_mark = _t
				_state = "client_done"
		"client_done":
			if _t - _mark > 0.5:
				_check(_me().loads_brought == 1, "client: delivered (server told the owner)")
				_check(_settings.has_learned("deliver"), "client: delivering is learned")
				_check(not _gs.sun_held, "client: the sun runs again")
				return _finish()
	return false

func _find_steps() -> Node:
	for c in _main.get_children():
		if c.has_method("_work_goal"):
			return c
	return null

func _lessons() -> Array:
	return load("res://scenes/first_steps/first_steps.gd").LESSONS

func _site() -> Node3D:
	return load("res://scenes/shared/site_focus.gd").site()

func _me() -> Node3D:
	return _main.players_root.get_node_or_null(str(root.multiplayer.get_unique_id()))

## Stand at the pile the tag means and press interact, as the player would
func _take() -> void:
	var site: Node3D = _site()
	var pile: Node3D = _steps._pile(_me(), site)
	if pile == null:
		_check(false, "no pile for what the wall needs")
		return
	_me().global_position = pile.global_position + Vector3(1.0, 0, 1.0)
	_me()._server_interact.rpc_id(1, _me().global_position)

## Walk the load up to the wall
func _walk_in() -> void:
	var site: Node3D = _site()
	_me().global_position = site.approach_point(_me().global_position, 0.6)

## Walk the load in and press interact, as the player would
func _give() -> void:
	_walk_in()
	_me()._server_interact.rpc_id(1, _me().global_position)

func _nearest_foe() -> Node3D:
	var foes := get_nodes_in_group("enemies")
	return foes[0] if not foes.is_empty() else null

func _shot(name_: String) -> void:
	if _out != "":
		root.get_texture().get_image().save_png(_out + "/first_steps_%s.png" % name_)

func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1

func _finish() -> bool:
	print("first_steps_test: %d failed" % _fails)
	quit(1 if _fails else 0)
	return true
