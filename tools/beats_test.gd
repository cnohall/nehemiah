extends SceneTree

# Checks section beats (GDD §6.4) offline:
#   Godot --headless --path . --script res://tools/beats_test.gd -- --nostory --day=9
# - with half the stretch standing the "half" beat fires once, is announced (beat_fired)
#   and its warned pack comes in after the warning
# - with one unit left the "last" beat fires
# - neither fires twice
# Exit code 0 = every check passed.

var _main: Node3D
var _frame := 0
var _t := 0.0
var _state := "wait_work"
var _mark := 0.0
var _fails := 0
var _gs: Node
var _beats: Node
var _heard: Array = []
var _before := 0

func _initialize() -> void:
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_gs = root.get_node("GameState")
		_beats = _main.get_node("SectionBeats")
		_beats.beat_fired.connect(func(i, key, _b): _heard.append([i, key]))
		_main.director.begin()
	if _frame < 3:
		return false
	_t += delta
	if _t > 90.0:
		_fail("timed out in " + _state)
		return _finish()
	var waves: Node = _main.get_node("WaveManager")
	var enemies: Node = _main.get_node("Enemies")
	match _state:
		"wait_work":
			if _gs.phase == _gs.Phase.WORK:
				waves.stop()   # only the beat's pack from here on
				_gs.sun_left = 999.0
				_check(_gs.targets_total == 6, "six units in the stretch (%d)" % _gs.targets_total)
				_finish_units(3)
				_state = "half"
				_mark = _t
		"half":
			if _heard.size() == 1 and _before == 0:
				_check(_heard[0][1] == "half", "half beat fired (%s)" % [_heard[0]])
				for e in enemies.get_children():
					e.queue_free()
				_before = -1
				_mark = _t
			elif _before == -1 and _t - _mark > _beats.WARN + 3.0:
				var n := enemies.get_child_count()
				_check(n >= 2, "warned pack came in (%d foes)" % n)
				_check(_heard.size() == 1, "half beat fired once (%d)" % _heard.size())
				_finish_units(5)
				_state = "last"
				_mark = _t
		"last":
			if _heard.size() == 2:
				_check(_heard[1][1] == "last", "last beat fired (%s)" % [_heard[1]])
				_state = "quiet"
				_mark = _t
			elif _t - _mark > 5.0:
				_fail("last beat never fired")
				return _finish()
		"quiet":
			if _t - _mark > 3.0:
				_check(_heard.size() == 2, "no beat twice (%d)" % _heard.size())
				return _finish()
	return false

# Server: raise the first `n` units in build order to finished
func _finish_units(n: int) -> void:
	var wall := _main.get_node("Wall")
	for k in n:
		var node: Node = wall.get_node(_main.director.UNIT_ORDER[k])
		var parts: Array = node.get_children().filter(func(c): return c.has_method("try_build"))
		if node.has_method("try_build"):
			parts.append(node)
		for p in parts:
			if p.is_complete():
				continue
			if "finished" in p:
				p.finished = true   # the gate's doors step
			else:
				p.stage = 3         # WallSection.Stage.MORTARED

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1

func _fail(what: String) -> void:
	_check(false, what)

func _finish() -> bool:
	print("beats_test: %s" % ("all passed" if _fails == 0 else "%d failed" % _fails))
	quit(1 if _fails else 0)
	return true
