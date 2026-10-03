extends SceneTree

# Checks the late-section twists offline:
#   Godot --path . --script res://tools/twist_test.gd -- --nostory --day=48 <out_dir>
# - schemes (East Gate, GDD §6.7): Sanballat's man walks up and slows the one he talks at;
#   [E] answers him (a short stop, he leaves, nobody led off). A neighbour's warning, heard,
#   marks the next pack
# - hand-off: dropping a load beside an empty-handed teammate puts it in their hands
# - night (run with --day=38): darkness falls during the work; shots saved to out_dir
# Exit code 0 = every check passed.

var _out := ""
var _main: Node3D
var _frame := 0
var _t := 0.0
var _state := "wait_work"
var _player: Node3D
var _mate: Node3D
var _mark := 0.0
var _fails := 0
var _messenger: Node3D
var _mark_pings := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	root.size = Vector2i(1920, 1080)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_main.director.begin()
	if _frame < 3:
		return false
	_t += delta
	var gs = root.get_node("GameState")
	for e in _main.get_node("Enemies").get_children():
		e.queue_free()   # nobody guards the test worker
	if _t > 120.0:
		_fail("timed out in " + _state)
		return _finish()
	match _state:
		"wait_work":
			if gs.phase == gs.Phase.WORK:
				_player = _main.get_node("Players").get_children().filter(func(p): return not p.is_bot())[0]
				# Bots off: visitors go to whoever is nearest, and a bot answers them too
				for p in _main.get_node("Players").get_children():
					if p != _player:
						_main.get_node("Players").remove_child(p)
						p.queue_free()
				_player.global_position = Vector3(2.0, 0.1, 7.0)
				_mark = _t
				_state = "night" if gs.has_twist("night") else "handoff"
		"night":
			if _t - _mark > 20.0:
				var dl = _main.get_node("DayLight")
				_check(dl.darkness > 0.95, "night fell (darkness %.2f)" % dl.darkness)
				_check(_player.get_node_or_null("Lamp") != null, "worker carries a lamp")
				_main.get_node("Camera3D").size = 22.0
				root.get_texture().get_image().save_png(_out + "/night.png")
				return _finish()
		"handoff":
			# A second worker (server-side logic only; nobody drives it)
			_mate = load("res://scenes/player/player.tscn").instantiate()
			_mate.name = "99"
			_main.get_node("Players").add_child(_mate)
			_mate.set_physics_process(false)   # stands there; only its server-side state matters
			_mate.global_position = _player.global_position + Vector3(1.0, 0, 0)
			_player._set_carried.rpc("stone")
			_player._server_drop.rpc_id(1, _player.global_position)
			_check(_player.carried_kind.is_empty() and _mate.carried_kind == "stone", "load passed hand to hand")
			_mate._set_carried.rpc("")
			_main.get_node("Players").remove_child(_mate)
			_mate.queue_free()
			_player.get_script().local = _player   # the mate took Player.local; give it back (visitor notes)
			_state = "horn" if gs.has_twist("horn") else ("wait_messenger" if gs.has_twist("schemes") else "done")
		"horn":
			if _player._is_busy:
				return false   # still in the hand-off swing
			_press("horn")
			_mark = _t
			_state = "horn_check"
		"horn_check":
			if _t - _mark > 0.6:
				var horn: Node3D = _main.get_node("Horn")
				_check(horn.get_child_count() == 1, "horn raised a standard")
				_check(_pings("Horn") == 1, "horn pointer registered")
				_check(is_equal_approx(horn.rally_damage(_player.global_position), 1.5), "blows ×1.5 inside the ring")
				_check(is_equal_approx(horn.rally_damage(_player.global_position + Vector3(6, 0, 0)), 1.0), "normal blows outside the ring")
				_check(horn.rally_sword_cd(_player.global_position) < 1.0, "quicker cuts inside the ring")
				_press("horn")   # again at once: cooldown
				_state = "horn_cooldown"
				_mark = _t
		"horn_cooldown":
			if _t - _mark > 0.6:
				_check(_main.get_node("Horn").get_child_count() == 1, "second blast refused (cooldown)")
				root.get_texture().get_image().save_png(_out + "/horn.png")
				_state = "surge"
		"surge":
			if _pings("Surge") > 0:
				_check(true, "surge warned at %.1f s into the work" % (_t - _mark))
				_state = "wait_messenger" if gs.has_twist("schemes") else "done"
			elif _t - _mark > 30.0:
				_fail("no surge warning within 30 s")
				return _finish()
		"wait_messenger":
			var ms: Array = _main.get_node("Visitors").get_children()
			if _frame % 60 == 0:
				print("  t=%.0f visitors: %s player %s downed=%s" % [_t, ms.map(func(m): return "%s st=%d" % [m.global_position, m.state]), _player.global_position, _player.downed])
			if not ms.is_empty() and ms[0].state == 1:   # WAITING beside us
				_check(ms[0].kind == 0, "the day's first visitor is Sanballat's man")
				_check(_player._interact_choice(_player.global_position)[1] == ms[0], "messenger takes the [E] focus")
				_check(is_equal_approx(_player.pester_mult(), ms[0].PESTER_MULT), "he slows the work of the one he talks at")
				root.get_texture().get_image().save_png(_out + "/messenger.png")
				_messenger = ms[0]
				_press()
				_mark = _t
				_state = "answered"
		# GDD §6.7: [E] answers him — a short stop, and he goes; nobody is led off
		"answered":
			if _t - _mark > 0.4:
				_check(_player._hold_time > 0.0, "worker stops to answer him")
				_check(_player._led_by == null, "nobody is led away")
				_check(not is_instance_valid(_messenger) or _messenger.state == 3, "answered, he leaves")
				_check(is_equal_approx(_player.pester_mult(), 1.0), "work back to full pace")
				# A neighbour from the villages, by hand (the wave manager sends one only by chance)
				for v in _main.get_node("Visitors").get_children():
					v.queue_free()
				var n: Node3D = load("res://scenes/messenger/messenger.tscn").instantiate()
				n.name = "Neighbour"
				n.position = _player.global_position + Vector3(3, 0, 0)
				_main.get_node("Visitors").add_child(n, true)
				_messenger = n
				_state = "neighbour"
		"neighbour":
			if is_instance_valid(_messenger) and _messenger.state == 1 and _player._hold_time <= 0.0:
				_mark = _t
				_state = "neighbour_note"
		"neighbour_note":
			if _t - _mark > 0.5:   # his note is up: what he says, and [E] Hear him
				root.get_texture().get_image().save_png(_out + "/neighbour.png")
				_check(_messenger.kind == 2, "a neighbour from the villages")
				_check(is_equal_approx(_player.pester_mult(), 1.0), "a neighbour doesn't slow the work")
				var before := _pings("Wave")
				_press()
				_mark = _t
				_state = "heard"
				_mark_pings = before
		"heard":
			if _t - _mark > 0.4:
				_check(not is_instance_valid(_messenger) or _messenger.state == 3, "heard, he leaves")
				if root.get_node("GameState").waves:
					_check(_pings("Wave") > _mark_pings, "his warning marks the next pack")
				# Shemaiah (Miphkad, 6:10-13), in the neighbour's robe: heard first, then followed
				for v in _main.get_node("Visitors").get_children():
					v.queue_free()
				var sh: Node3D = load("res://scenes/messenger/messenger.tscn").instantiate()
				sh.name = "Shemaiah"
				sh.position = _player.global_position + Vector3(3, 0, 0)
				_main.get_node("Visitors").add_child(sh, true)
				_messenger = sh
				_state = "shemaiah"
		"shemaiah":
			if is_instance_valid(_messenger) and _messenger.state == 1 and _player._hold_time <= 0.0:
				_press()
				_mark = _t
				_state = "shem_heard"
		"shem_heard":
			if _t - _mark > 0.4:
				_check(_messenger.heard and _player._led_by == null, "first [E] hears Shemaiah, nobody led")
				_state = "shem_go"
		"shem_go":
			if _player._hold_time <= 0.0 and _messenger.state == 1:
				_press()
				_mark = _t
				_state = "shem_led"
		"shem_led":
			if _t - _mark > 0.6:
				_check(_player._led_by != null, "second [E] goes with him")
				_state = "done"
		"done":
			return _finish()
	return false

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1

func _fail(what: String) -> void:
	_check(false, what)

func _finish() -> bool:
	print("PASS" if _fails == 0 else "FAIL: %d check(s)" % _fails)
	quit(0 if _fails == 0 else 1)
	return true

func _pings(text: String) -> int:
	var alerts = _main.get_tree().get_first_node_in_group("offscreen_alerts")
	return alerts._pings.filter(func(p): return p[2] == text).size()

func _press(action := "interact") -> void:
	Input.action_press(action)
	await create_timer(0.05).timeout
	Input.action_release(action)
