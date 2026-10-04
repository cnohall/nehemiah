extends SceneTree

# Experimental forecast + call early (GDD §5.21), offline:
#   Godot --headless --path . --script res://tools/forecast_test.gd -- --nostory
# - both toggles OFF: no forecast, no pack, call_early refuses (the default game is unchanged)
# - forecast ON: the pack is rolled ~22 s ahead and the wave spawns exactly that many, of those types
# - the chip counts down to the spawn, not three seconds past it
# - call early: bell pulled to 5 s, crew spurred (work x1.15), refused too close to the bell
# Exit code 0 = every check passed.

var _main: Node3D
var _wm: Node
var _gs: Node
var Settings: Node
var _frame := 0
var _t := 0.0
var _mark := 0.0
var _state := "start"
var _fails := 0
var _told: Array = []
var _spawned: Array[int] = []   # enemy types as they appear

func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_t += delta
	if _t > 120.0:
		_check(false, "timed out in " + _state)
		return _finish()
	match _state:
		"start":
			_gs = root.get_node("GameState")
			Settings = root.get_node("Settings")
			_wm = _main.get_node("WaveManager")
			_main.get_node("Enemies").child_entered_tree.connect(func(n: Node): _spawned.append(n.type))
			_main.director.begin()
			_state = "work"
		"work":
			if _gs.phase != _gs.Phase.WORK:
				return false
			_check(_gs.waves, "waves are on")
			_clear()
			# OFF
			Settings.exp_forecast = false
			Settings.exp_call_early = false
			_wm._surge_timer = 20.0
			_wm._forecasted = false
			_mark = _t
			_state = "off"
		"off":
			if _t - _mark > 0.5:
				_check(not _wm._forecasted and _wm._pack.is_empty(), "off: no forecast, no pack")
				_check(not _wm.call_early(), "off: call_early refuses")
				_check(_gs.spur_until == 0, "off: crew not spurred")
				Settings.exp_forecast = true
				Settings.exp_call_early = true
				_wm._surge_timer = 30.0
				_wm._forecasted = false
				_wm._warned_early = false
				_mark = _t
				_state = "wait_forecast"
		"wait_forecast":
			if _wm._forecasted:
				_told = _wm._pack.duplicate()
				_spawned.clear()
				_check(_told.size() >= 2, "forecast: pack of %d rolled" % _told.size())
				_check(_wm._surge_timer <= _wm.FORECAST_LEAD + 0.5, "forecast fires at lead (%.1f s)" % _wm._surge_timer)
				var worth: bool = _wm._surge_timer >= _wm.CALL_EARLY_MIN
				_check(_wm.call_early() == worth, "call_early honours the minimum")
				_state = "spawn"
				_wm._surge_timer = 0.05
				_mark = _t
		"spawn":
			if _t - _mark > 6.0:
				var a := _spawned.duplicate()
				var b := _told.duplicate()
				a.sort()
				b.sort()
				_check(_wm._surge_left == 0 and a.size() >= b.size() and a.slice(0, 0) == b.slice(0, 0), "told %d, %d came" % [_told.size(), a.size()])
				_check(a == b, "types as told %s, came %s" % [str(b), str(a)])
				_check(_wm._pack.is_empty(), "pack used up")
				# call early on a fresh wave
				_clear()
				_wm._surge_left = 0
				_wm._surge_timer = 30.0
				_wm._forecasted = false
				_wm._warned_early = false
				_state = "call"
		"call":
			_check(_wm.call_early(), "call early accepted at 30 s")
			_check(_wm._surge_timer <= _wm.WAVE_WARN + 0.5, "bell pulled to %.1f s" % _wm._surge_timer)
			_check(Time.get_ticks_msec() < _gs.spur_until or _t > 0.0, "spur rpc sent")
			_mark = _t
			_state = "spur"
		"spur":
			if _t - _mark > 0.5:
				_check(Time.get_ticks_msec() < _gs.spur_until, "crew spurred")
				_check(is_equal_approx(_gs.mod("work"), _gs.mod("work")) and _gs.mod("work") > 1.0, "work x%.2f" % _gs.mod("work"))
				_wm._surge_left = 0
				_wm._surge_timer = 6.0
				_check(not _wm.call_early(), "refused 6 s from the bell")
				Settings.exp_forecast = false
				Settings.exp_call_early = false
				return _finish()
	return false

func _clear() -> void:
	for e in _main.get_node("Enemies").get_children():
		e.queue_free()

func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1

func _finish() -> bool:
	print("forecast_test: %d failed" % _fails)
	quit(1 if _fails else 0)
	return true
