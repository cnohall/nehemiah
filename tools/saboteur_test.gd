extends SceneTree

# Saboteur (GDD §5.9), offline, no bots:
#   Godot --path . --script res://tools/saboteur_test.gd -- --nostory --day=6 <out_dir>
# - one comes in and strews a pile the work needs; pickups from it are refused
# - a worker tidies it ([E], worked like a stage) and it gives again
# - after two piles he heads back out; the day's tally counts them
# - a sword cut or two brings him down (30 health)
# Screenshots of him at the pile and of a strewn pile. Exit code 0 = every check passed.

var _out := ""
var _main: Node3D
var _frame := 0
var _t := 0.0
var _mark := 0.0
var _state := "wait_work"
var _player: Node3D
var _sab: Node3D
var _pile: Node3D
var _fails := 0
var _shot := false

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
		_main.fit_bots(0)
		_main.director.begin()
	if _frame < 3:
		return false
	_t += delta
	var gs = root.get_node("GameState")
	# Only the saboteur: nothing else to fight
	for e in _main.get_node("Enemies").get_children():
		if e != _sab and e.get("type") != 3:
			e.queue_free()
	if _t > 150.0:
		_fail("timed out in " + _state)
		return _finish()
	match _state:
		"wait_work":
			if gs.phase == gs.Phase.WORK:
				_player = _main.get_node("Players").get_child(0)
				_player.global_position = Vector3(-30.0, 0.1, 20.0)   # well out of his way
				_main.get_node("WaveManager")._do_spawn(3, Vector3(0.0, 0.1, -14.0))
				_state = "find"
		"find":
			for e in _main.get_node("Enemies").get_children():
				if e.get("type") == 3:
					_sab = e
			if _sab != null:
				_check(_sab.is_saboteur(), "a saboteur came")
				_mark = _t
				_state = "strew"
		"strew":
			var strewn: Array = _main.get_tree().get_nodes_in_group("scattered_piles")
			if not _shot and is_instance_valid(_sab) and _sab._scatter_t > 0.8:
				_shot = true
				_focus(_sab.global_position)
				root.get_texture().get_image().save_png(_out + "/saboteur_at_pile.png")
			if not strewn.is_empty():
				_pile = strewn[0]
				print("strewn: %s after %.1f s" % [_pile.kind, _t - _mark])
				_check(not _pile.is_in_group("supply_piles"), "strewn pile leaves the supply group")
				_check(not _pile.request_pickup(), "pickup from a strewn pile refused")
				_focus(_pile.global_position)
				_mark = _t
				_state = "shot_pile"
			elif _t - _mark > 60.0:
				_fail("no pile strewn in 60 s")
				return _finish()
		"shot_pile":
			if _t - _mark > 0.5:
				root.get_texture().get_image().save_png(_out + "/strewn_pile.png")
				_player.global_position = _pile.global_position + Vector3(1.5, 0, 0)
				_mark = _t
				_state = "tidy_press"
		"tidy_press":
			if _t - _mark > 0.3:
				var choice: Array = _player._interact_choice(_player.global_position)
				_check(choice[0] == _player.Act.TIDY, "the press at a strewn pile tidies it")
				_player._server_interact.rpc_id(1, _player.global_position)
				_mark = _t
				_state = "tidying"
		"tidying":
			if not _pile.scattered:
				print("tidied in %.1f s" % (_t - _mark))
				_check(_pile.is_in_group("supply_piles"), "tidied pile gives again")
				_mark = _t
				_state = "second"
			elif _t - _mark > 8.0:
				_fail("tidy never finished (progress %.2f)" % _pile.work().progress)
				return _finish()
		"second":
			# He goes on to a second pile, then out
			if not is_instance_valid(_sab) or _sab._escaping:
				_check(true, "after two piles he heads back out")
				_check(_main.director._stats["scattered"] >= 2, "tally counts %d strewn" % _main.director._stats["scattered"])
				_state = "fight"
				_mark = _t
			elif _t - _mark > 40.0:
				_fail("never left (strewn %d)" % _sab._scattered_n)
				return _finish()
		"fight":
			# A fresh one; two sword cuts
			_sab = null
			_main.get_node("WaveManager")._do_spawn(3, _player.global_position + Vector3(1.2, 0, 0))
			_state = "cut"
			_mark = _t
		"cut":
			for e in _main.get_node("Enemies").get_children():
				if e.get("type") == 3 and e.health > 0.0:
					_sab = e
			if _sab == null:
				return false
			_sab.take_damage(20.0, 1)
			_sab.take_damage(20.0, 1)
			_check(_sab.health <= 0.0, "two cuts fell him")
			return _finish()
	return false

func _focus(at: Vector3) -> void:
	var cam: Camera3D = _main.get_node("Camera3D")
	_player.global_position = at + Vector3(4.0, 0, 4.0)

func _check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok:
		_fails += 1

func _fail(what: String) -> void:
	_check(false, what)

func _finish() -> bool:
	print("RESULT: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)
	return true
