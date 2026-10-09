extends SceneTree

# The close call (GDD §7.1 #6, DayDirector._close_call), offline, on a stretch's last day:
#   Godot --headless --path . --script res://tools/close_call_test.gd -- --nostory --day=8
# - an ordinary finish is not a close call
# - the light nearly gone on the last day → "stars"
# - a foe at the piece that closed it → "gap"; a saboteur there doesn't count
# - the stretch standing with a foe at the last piece: the tally says "gap", the dusk's
#   slow motion goes deeper, the mix drops behind a low-pass, the watch calls it, and the
#   scribe's chronicle keeps it
# Exit code 0 = every check passed.

var _main: Node3D
var _frame := 0
var _t := 0.0
var _fails := 0
var _state := "wait"
var _stats := {}
var _dusk_t := 0.0
# Enemy.Type / WallSection.Stage by value: a --script harness compiles before the autoloads,
# so it can't name the game's classes
const SCOUT := 0
const SABOTEUR := 3
const MORTARED := 3

func _initialize() -> void:
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_main.director.begin()
		_main.director.day_tallied.connect(func(s: Dictionary): _stats = s)
	if _frame < 3:
		return false
	_t += delta
	var gs = root.get_node("GameState")
	if _t > 60.0:
		_check(false, "timed out in state %s" % _state)
		return _finish()
	match _state:
		"wait":
			if gs.phase != gs.Phase.WORK:
				return false
			_check(gs.last_day_of_section(), "day %d is the stretch's last" % gs.current_day)
			_main.get_node("WaveManager").stop()
			for e in _main.get_node("Enemies").get_children():
				e.free()
			_judge(gs)
			_state = "finish"
			_finish_stretch()
		"finish":
			if gs.phase == gs.Phase.DUSK and not _stats.is_empty():
				_check(_stats.get("close", "") == "gap", "the tally says gap (%s)" % _stats.get("close", "none"))
				_check(Engine.time_scale < 0.2, "the slow motion goes deeper (%.2f)" % Engine.time_scale)
				_check(_has_low_pass(), "the mix drops behind a low-pass")
				var called := false
				for watch in get_nodes_in_group("watchmen"):
					for c in watch.get_children():
						for s in c.find_children("*", "Shout", true, false):
							if s.visible and "Just in time" in s.text:
								called = true
				_check(called, "a watchman calls it")
				_check(gs.chronicle[gs.current_section_index].get("close", false), "the chronicle keeps it")
				_state = "after"
		"after":
			_dusk_t += delta / maxf(Engine.time_scale, 0.01)   # real seconds
			if _dusk_t > 2.5:
				_check(is_equal_approx(Engine.time_scale, 1.0), "back to speed (%.2f)" % Engine.time_scale)
				_check(not _has_low_pass(), "the low-pass lets go")
				return _finish()
	return false

# _close_call() straight, before the stretch is finished
func _judge(gs) -> void:
	var d = _main.director
	var last: Node3D = d._units[d._units.size() - 1][0]
	d._last_raised = last
	gs.sun_left = gs.sun_total * 0.5
	_check(d._close_call() == "", "an ordinary finish is not a close call")
	gs.sun_left = d.CLOSE_SUN - 1.0
	_check(d._close_call() == "stars", "the light nearly gone: stars")
	gs.sun_left = gs.sun_total * 0.5
	var sab := _spawn(SABOTEUR, last)
	_check(d._close_call() == "", "a saboteur at the piece doesn't count")
	sab.free()
	var foe := _spawn(SCOUT, last)
	foe._wrecker = true
	_check(d._close_call() == "", "a wrecker battering the piece doesn't count")
	foe._wrecker = false
	_check(d._close_call() == "gap", "a runner at the piece: gap")
	foe.position.z -= 8.0
	_check(d._close_call() == "", "a foe far off: no close call")
	foe.position.z += 8.0

func _spawn(type: int, at: Node3D) -> Node3D:
	var enemies := _main.get_node("Enemies")
	var before := enemies.get_child_count()
	_main.get_node("WaveManager")._do_spawn(type, at.global_position + Vector3(0.0, 0.1, -1.6))
	return enemies.get_child(before)

# Every part up, the last unit's first part last of all (the foe stands at it)
func _finish_stretch() -> void:
	var d = _main.director
	var last: Node3D = d._units[d._units.size() - 1][0]
	var parts: Array = []
	for unit: Array in d._units:
		parts.append_array(unit)
	parts.erase(last)
	parts.append(last)
	for part in parts:
		if "stage" in part:
			part.stage = MORTARED
		elif "finished" in part:
			part.finished = true

func _has_low_pass() -> bool:
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) is AudioEffectLowPassFilter:
			return true
	return false

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1

func _finish() -> bool:
	print("close_call_test: %s" % ("all passed" if _fails == 0 else "%d failed" % _fails))
	Engine.time_scale = 1.0
	quit(1 if _fails else 0)
	return true
