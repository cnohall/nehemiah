extends SceneTree

# Birds (Birds / Bird) and the lamps in the windows (ScatterLayer, DayLight), offline:
#   Godot --headless --path . --script res://tools/birds_test.gd
# - every section lays out flocks on open ground, off the wall strip and the work spots
# - a worker walking into a flock puts it up; a foe coming on puts up the one outside
# - the horn puts every flock up; once it's quiet they fly back in and land
# - evening lights the windows and sends the birds to roost; dawn puts the lamps out
#   and has the birds due back
# Exit code 0 = every check passed.

var _main: Node3D
var _gs: Node
var _birds: Node3D
var _frame := 0
var _state := "layout"
var _fails := 0
var _player: Node3D
var _fake: Node3D
var _mark_ms := 0
var _flock: Dictionary

func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	if _frame == 3:
		_gs = root.get_node("GameState")
		_birds = _main.get_node("Birds")
		_player = _main.get_node("Players").get_child(0)
	if Time.get_ticks_msec() > 90000:
		_check(false, "timed out in " + _state)
		return _finish()
	match _state:
		"layout":
			var terrain: Node3D = _main.get_node("SectionTerrain")
			for i in _gs.SECTIONS.size():
				_gs.current_section_index = i
				_gs.section_changed.emit(i)
				var bad := []
				var inside := 0
				for f: Dictionary in _birds._flocks:
					var at := Vector2(f.spot.x, f.spot.z)
					inside += 1 if at.y > 0.0 else 0
					if absf(at.y) < 3.0 or terrain.blocks(at, 0.5):
						bad.append(at)
					for k: Vector2 in terrain.keep_clear():
						if k.distance_to(at) < 1.5:
							bad.append(at)
				var n: int = _birds._flocks.size()
				_check(n >= 2 and inside > 0 and inside < n and bad.is_empty(),
					"%s: %d flocks (%d inside), misplaced %s" % [_gs.SECTIONS[i]["name"], n, inside, bad])
			_gs.current_section_index = 0
			_gs.section_changed.emit(0)
			_state = "walk"
		"walk":
			_flock = _birds._flocks.filter(func(f): return f.spot.z > 0.0)[0]
			_player.global_position = _flock.spot + Vector3(1.5, 0, 0)
			_mark_ms = Time.get_ticks_msec()
			_state = "walked"
		"walked":
			if not _flock.away and _since() < 0.5:
				return false
			_check(_flock.away, "walking into a flock puts it up")
			_player.global_position = Vector3(0, 0.1, 12)
			_state = "gone"
		"gone":
			if not _all(_flock, Bird.State.AWAY) and _since() < 5.0:
				return false
			_check(_all(_flock, Bird.State.AWAY), "they fly out of sight")
			var out: Dictionary = _birds._flocks.filter(func(f): return f.spot.z < 0.0)[0]
			_fake = Node3D.new()
			_fake.add_to_group("enemies")
			_main.add_child(_fake)
			_fake.global_position = out.spot + Vector3(0, 0, -5.5)
			_flock = out
			_mark_ms = Time.get_ticks_msec()
			_state = "foe"
		"foe":
			if not _flock.away and _since() < 0.5:
				return false
			_check(_flock.away, "a foe coming on puts up the flock outside")
			_fake.queue_free()
			root.get_node("Sfx").play("horn")
			_check(_birds._flocks.all(func(f): return f.away), "the horn puts every flock up")
			_mark_ms = Time.get_ticks_msec()
			_state = "calm"
		"calm":
			# Cut the calm short once they're all out of sight
			if _since() < 3.5:
				return false
			for f: Dictionary in _birds._flocks:
				f.quiet = 0.2
			for p: Node3D in get_nodes_in_group("players"):
				p.global_position = Vector3(0, 0.1, 40)   # out of the way
			_mark_ms = Time.get_ticks_msec()
			_state = "back"
		"back":
			var home: bool = _birds._flocks.all(func(f): return _all(f, Bird.State.GROUND))
			if not home and _since() < 6.0:
				return false
			_check(home, "once it's quiet they fly back in and land")
			_gs.set_phase(_gs.Phase.WORK)
			_gs.set_sun(100.0, 2.0)
			_mark_ms = Time.get_ticks_msec()
			_state = "dusk"
		"dusk":
			var dl: Node = _main.get_node("DayLight")
			var lit := _lit()
			if dl.lamps < 0.99 and _since() < 6.0:
				return false
			_check(lit.x == lit.y and lit.y > 10, "evening lights all the windows (%d of %d)" % [lit.x, lit.y])
			_check(_birds._flocks.all(func(f): return f.away), "the birds go to roost")
			_gs.set_phase(_gs.Phase.DAWN)
			_gs.set_sun(100.0, 100.0)   # a fresh day's light
			# Players and the day's first foes come on at dawn, so just check they're due back
			_check(_birds._flocks.all(func(f): return f.quiet <= 5.0), "dawn brings the birds back")
			_mark_ms = Time.get_ticks_msec()
			_state = "dawn"
		"dawn":
			var lit := _lit()
			if lit.x > 0 and _since() < 6.0:
				return false
			_check(lit.x == 0, "dawn puts the lamps out")
			return _finish()
	return false

# Lit windows, all windows (main scatter + section terrain)
func _lit() -> Vector2i:
	var v := Vector2i.ZERO
	for n: Node in get_nodes_in_group("window_lamps"):
		if n._lamps:
			v += Vector2i(n._lamps.visible_instance_count, n._lamps.instance_count)
	return v

func _all(f: Dictionary, s: int) -> bool:
	return f.birds.all(func(b): return b.state == s)

func _since() -> float:
	return (Time.get_ticks_msec() - _mark_ms) / 1000.0

func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1

func _finish() -> bool:
	print("birds_test: %d failed" % _fails)
	quit(1 if _fails else 0)
	return true
