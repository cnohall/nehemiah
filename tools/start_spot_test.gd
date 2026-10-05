extends SceneTree

# New stretch → crew back at the start spot, offline:
#   Godot --headless --path . --script res://tools/start_spot_test.gd -- --nostory
# Exit code 0 = every check passed.

var _main: Node
var _gs: Node
var _frame := 0
var _t := 0.0
var _state := "start"
var _fails := 0

func _initialize() -> void:
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_t += delta
	if _t > 40.0:
		_check(false, "timed out in %s (phase %d)" % [_state, root.get_node("GameState").phase])
		return _finish()
	_gs = root.get_node("GameState")
	var me: Node3D = _main.players_root.get_child(0)
	match _state:
		"start":
			_main.director.begin()
			_state = "work"
		"work":
			if _gs.phase == _gs.Phase.STORY:
				_main.director.force_ready()
			elif _gs.phase == _gs.Phase.WORK:
				_main.get_node("WaveManager").stop()
				me.global_position = Vector3(12, 0.1, -5)
				# Day 2 is mid-stretch: nobody is moved
				_gs.advance_day(2)
				_main.director._begin_day()
				_check(me.global_position.distance_to(Vector3(12, 0.1, -5)) < 0.01, "mid-stretch: worker stays put")
				# Day 5 opens the Fish Gate stretch (yard x = -9)
				_gs.advance_day(5)
				_main.director._begin_day()
				# (not `Player.` — naming the class compiles it before the autoloads exist)
				var want: Vector3 = load("res://scenes/player/player.gd").start_spot(0)
				_check(me.global_position.distance_to(want) < 0.01, "new stretch: at start spot %s (is %s)" % [want, me.global_position])
				_check(is_equal_approx(want.x, -9.0), "start spot follows the yard (x %.1f)" % want.x)
				return _finish()
	return false

func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1

func _finish() -> bool:
	print("start_spot_test: %d failed" % _fails)
	quit(1 if _fails else 0)
	return true
