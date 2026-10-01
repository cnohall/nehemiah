extends SceneTree

# Checks the Tower of Ovens night raid (GDD §5.15, Neh. 4:11) offline:
#   Godot --headless --path . --script res://tools/raid_test.gd -- --nostory --day=20
# - with a finished piece standing the watch calls it (warn) on the stretch's 3rd day
# - the next dawn pulls that piece down two stages
# - a stocked watch post turns it back; --no-setbacks leaves everything alone
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
	var piece: Node3D = d._units[2][0]
	_check(d._units[2].size() == 1, "unit 2 is a single piece")
	_check(not d._raid_pending, "nothing called while nothing stands")
	piece.stage = 3
	d._setback_at_dawn()
	_check(d._raid_pending, "the watch calls it on day %d" % gs.current_day)
	d._setback_at_dawn()
	_check(piece.stage == 1, "dawn pulled the piece down two stages (stage %d)" % piece.stage)
	_check(not d._raid_pending, "the call is spent")
	var strewn := get_nodes_in_group("scattered_piles").size()
	_check(strewn >= 1 and strewn <= d.RAID_STREWN, "yard piles left in rubble (%d)" % strewn)
	# A stocked watch post turns it back
	piece.stage = 3
	var posts := get_nodes_in_group("watch_posts")
	_check(not posts.is_empty(), "the stretch has watch posts")
	if not posts.is_empty():
		posts[0].built = true
		posts[0].ammo = 6
		d._raid_pending = true
		d._setback_at_dawn()
		_check(piece.stage == 3, "a stocked post held the raid (stage %d)" % piece.stage)
	return _finish()

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1

func _finish() -> bool:
	print("raid_test: %s" % ("all passed" if _fails == 0 else "%d failed" % _fails))
	quit(1 if _fails else 0)
	return true
