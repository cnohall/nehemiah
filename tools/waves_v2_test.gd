extends SceneTree

# Waves v2 (GDD §5.27), offline:
#   Godot --headless --path . --script res://tools/waves_v2_test.gd -- --nostory --day=21
#   (add --old-waves for the old rhythm: the "no trickle" check then expects a trickle)
# - no foe comes outside a warned pack (a wave's or a beat's)
# - every pack has a shape the day allows, never the same twice running
# - arc: lull < build < peak for the same shape
# - a unit raised pulls the next pack 9 s sooner, never inside the floor
# - a beat's pack pushes the next wave back and restarts the three
# - prints foes per minute, to set against --old-waves
# Exit code 0 = every check passed.

const RUN := 150.0   # game seconds of watching

var _main: Node3D
var _wm: Node
var _gs: Node
var _beats: Node
var _frame := 0
var _t := 0.0
var _mark := 0.0
var _state := "start"
var _fails := 0
var _spawns := 0
var _shapes: Array[String] = []
var _last_no := 0

func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _on_spawn(n: Node) -> void:
	if n.get("type") == null or n.get("type") == 3:   # 3 = saboteur: his own timer
		return
	_spawns += 1

func _process(delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_t += delta
	if _t > RUN + 60.0:
		_check(false, "timed out in " + _state)
		return _finish()
	match _state:
		"start":
			_gs = root.get_node("GameState")
			_wm = _main.get_node("WaveManager")
			_beats = _main.get_node("SectionBeats")
			_main.get_node("Enemies").child_entered_tree.connect(_on_spawn)
			_main.director.begin()
			_state = "work"
		"work":
			if _gs.phase != _gs.Phase.WORK:
				return false
			_beats.enabled = false   # beats are checked by hand below
			_gs.set_sun(999.0, 999.0)   # a long day to watch
			Engine.time_scale = 4.0
			_mark = _t
			_state = "watch"
		"watch":
			if _wm._wave_no != _last_no:
				_last_no = _wm._wave_no
				_shapes.append(_wm._last_shape)
			if _gs.phase != _gs.Phase.WORK or _t - _mark > RUN:
				Engine.time_scale = 1.0
				var minutes := (_t - _mark) / 60.0
				print("phase %d, breaches %d" % [_gs.phase, _gs.breaches])
				print("RESULT %s day %d: %d foes in %.1f min = %.1f / min, %d outside a pack, shapes %s" % [
					"old" if _wm.old_waves else "v2", _gs.current_day, _spawns, minutes, _spawns / maxf(0.01, minutes), _wm.trickled, str(_shapes)])
				if _wm.old_waves:
					_check(_wm.trickled > 0, "old waves: the trickle still runs (%d)" % _wm.trickled)
					return _finish()
				_check(_wm.trickled == 0, "no foe outside a pack (%d)" % _wm.trickled)
				_check(_shapes.size() >= 2, "packs came (%d)" % _shapes.size())
				var allowed := ["wave", "rush", "pincer", "ram", "raid"]
				var ok := true
				for i in _shapes.size():
					if not _shapes[i] in allowed or (i > 0 and _shapes[i] == _shapes[i - 1]):
						ok = false
				_check(ok, "shapes known, never twice running")
				_state = "units"
		"units":
			_wm._active = true
			_wm._shape = "wave"
			var sizes := []
			for k in 3:
				_wm._wave_no = k
				sizes.append(_wm._wave_size())
			_check(sizes[0] <= sizes[1] and sizes[1] <= sizes[2] and sizes[0] < sizes[2], "arc lull < build < peak %s" % str(sizes))
			_wm._wave_no = 1
			# Progress pull
			_wm._surge_left = 0
			_wm._surge_timer = 30.0
			_wm._last_done = _gs.targets_done
			_gs.set_progress(_gs.targets_done + 1, _gs.targets_total)
			_check(is_equal_approx(_wm._surge_timer, 30.0 - _wm.PROGRESS_PULL), "unit raised: next pack at %.1f s" % _wm._surge_timer)
			_wm._surge_timer = 12.0
			_gs.set_progress(_gs.targets_done + 1, _gs.targets_total)
			_check(is_equal_approx(_wm._surge_timer, _wm.PULL_FLOOR), "pull held at the floor (%.1f s)" % _wm._surge_timer)
			# Beat push
			_wm._surge_timer = 6.0
			_wm._wave_no = 2
			_wm.beat_taken()
			_check(_wm._surge_timer >= _wm.BEAT_PUSH and _wm._wave_no == 0, "beat: next wave at %.1f s, three restarted" % _wm._surge_timer)
			return _finish()
	return false

func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1

func _finish() -> bool:
	Engine.time_scale = 1.0
	print("%d failed" % _fails)
	quit(1 if _fails > 0 else 0)
	return true
