extends SceneTree

# Checks the arc's other setbacks (GDD §5.15) offline, one stretch per run:
#   Godot --headless --path . --script res://tools/setbacks_test.gd -- --nostory --day=<d>
#   --day=14  Broad Wall: the fox trots over on the stretch's 2nd day (Neh. 4:3)
#   --day=18  hungry households left after the Fountain Gate cost the next stretch work (5:5)
#   --day=49  East Gate: the open letter's rumour weakens work until the Letter is turned away
#   --day=51  Miphkad Gate: Shemaiah comes on the first day; turned away, or followed
# Exit code 0 = every check passed.

var _main: Node3D
var _frame := 0
var _t := 0.0
var _fails := 0

func _initialize() -> void:
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
	if _t > 60.0:
		_check(false, "timed out")
		return _finish()
	if gs.phase != gs.Phase.WORK:
		return false
	_main.get_node("WaveManager").stop()
	var d = _main.director
	var base: float = gs.mod("work")
	match gs.current_day:
		14:
			var fox: Node = get_nodes_in_group("setback_fx")[0]
			d._setback_at_dawn()
			_check(fox._fox != null, "the fox is out on day 14")
		18:
			gs.hungry_left = 0
			gs.hungry_left = 2
			_check(gs.mod("work") < 1.0, "two hungry households slow the work (%.2f)" % gs.mod("work"))
			d._setback_at_dawn()   # day 18 is the stretch's 1st day
			_check(gs.journal.size() >= 1, "the scribe wrote it in the margin: %s" % [gs.journal])
		49:
			d._setback_at_dawn()
			_check(gs.rumour and is_equal_approx(gs.mod("work"), 0.9), "the rumour weakens hands (%.2f)" % gs.mod("work"))
			d.note_refused("Letter")
			_check(not gs.rumour and is_equal_approx(gs.mod("work"), 1.0), "the Letter turned away lifts it")
			_check(gs.journal.size() >= 2, "both notes written")
		51:
			d._shem_t = 41.0
			d._tick_shemaiah(0.1)
			var v := _main.get_node("Visitors")
			_check(v.get_child_count() == 1 and v.get_child(0).name == &"Shemaiah", "Shemaiah came to the wall")
			d.note_refused("Shemaiah")
			_check(gs.journal.size() >= 1, "refused: written down")
			d._tick_shemaiah(0.1)
			_check(v.get_child_count() == 1, "he comes only once")
	return _finish()

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1

func _finish() -> bool:
	print("setbacks_test: %s" % ("all passed" if _fails == 0 else "%d failed" % _fails))
	quit(1 if _fails else 0)
	return true
