extends SceneTree

# Camp reveal (GDD §5.28), rendered: the Jeshanah Gate's last day, the stretch stands, the
# wall cam runs, then the camera looks at the hill where Samaria's army comes in.
#   Godot --path . --script res://tools/camp_reveal_shots.gd -- --nostory --day=12 <out_dir>
#   (--day=23: the Tower of the Ovens' end, Geshem's Arabs)
# Checks: the arrival is built, the camp stages (1 → 2 → 3) by stretch, the tally waits for
# it. Shots at real-time marks to out_dir. Exit code 0 = every check passed.

const MORTARED := 3
const SHOTS := [1.0, 3.8, 5.2, 6.6, 8.2, 9.4]   # real seconds after dusk

var _main: Node3D
var _frame := 0
var _fails := 0
var _state := "wait"
var _out := ""
var _dusk_ms := 0
var _shot := 0
var _arrival_seen := false

func _initialize() -> void:
	root.size = Vector2i(1600, 900)
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_main.director.begin()
	if _frame < 3:
		return false
	var gs = root.get_node("GameState")
	if _frame > 4000:
		_check(false, "timed out in state %s" % _state)
		return _finish()
	match _state:
		"wait":
			if gs.phase != gs.Phase.WORK:
				return false
			var sl = _main.get_node("ScatterLayer")
			var i: int = gs.current_section_index
			print("stretch %d camp stage %d, next %d" % [i, sl.camp_stage(i), sl.camp_stage(i + 1)])
			_check(sl.camp_stage(0) == 1 and sl.camp_stage(2) == 1 and sl.camp_stage(3) == 2 and sl.camp_stage(5) == 3,
				"camp stages by stretch 1/1/2/3")
			_check(sl.camp_reveal_at() != Vector3.INF, "a camp comes after this stretch")
			_main.get_node("WaveManager").stop()
			for e in _main.get_node("Enemies").get_children():
				e.free()
			_finish_stretch()
			_state = "dusk"
		"dusk":
			if gs.phase == gs.Phase.DUSK:
				_dusk_ms = Time.get_ticks_msec()
				_state = "shoot"
		"shoot":
			var t := (Time.get_ticks_msec() - _dusk_ms) / 1000.0
			if _main.has_node("CampArrival"):
				_arrival_seen = true
			if _shot < SHOTS.size() and t >= SHOTS[_shot]:
				if not _out.is_empty():
					root.get_texture().get_image().save_png(_out.path_join("reveal_%d.png" % _shot))
				_shot += 1
			if _shot >= SHOTS.size():
				_check(_arrival_seen, "the arrival was built")
				return _finish()
	return false

func _finish_stretch() -> void:
	var d = _main.director
	for unit: Array in d._units:
		for part in unit:
			if "stage" in part:
				part.stage = MORTARED
			elif "finished" in part:
				part.finished = true

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1

func _finish() -> bool:
	print("camp_reveal_shots: %s" % ("all passed" if _fails == 0 else "%d failed" % _fails))
	Engine.time_scale = 1.0
	quit(1 if _fails else 0)
	return true
