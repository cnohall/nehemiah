extends SceneTree

# Checks the late-section twists offline:
#   Godot --path . --script res://tools/twist_test.gd -- --nostory --day=48 <out_dir>
# - schemes (East Gate): a messenger walks up; [E] beside him goes with him (led away,
#   no control), and he lets go after LEAD_TIME
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
				_player = _main.get_node("Players").get_child(0)
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
				_check(_player._interact_choice(_player.global_position)[1] == ms[0], "messenger takes the [E] focus")
				root.get_texture().get_image().save_png(_out + "/messenger.png")
				_press()
				_mark = _t
				_state = "led"
		"led":
			if _t - _mark > 1.5:
				_check(_player._led_by != null, "worker is led away")
				_check(_player.global_position.distance_to(Vector3(2, 0.1, 7)) > 2.0, "worker walked off (%s)" % _player.global_position)
				_state = "released"
		"released":
			if _player._led_by == null:
				var took := _t - _mark
				_check(took > 5.0 and took < 10.0, "released after %.1f s" % took)
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
