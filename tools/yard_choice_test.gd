extends SceneTree

# Yard choice (GDD §5.28), offline:
#   Godot --path . --script res://tools/yard_choice_test.gd -- --nostory --day=13 [out_dir]
# - the Broad Wall's first dawn opens two rings and holds the dawn
# - the host standing in the second ring for a moment closes it: boon "watch", in play
# - the chosen standard stays, the rings go, and the work starts a few seconds later
# - no story card carries the choice (StoryData)
# Shots to out_dir when given (rendered: run without --headless). Exit code 0 = all passed.

var _main: Node3D
var _frame := 0
var _t := 0.0
var _mark := 0.0
var _fails := 0
var _state := "wait"
var _out := ""

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

func _shot(name: String) -> void:
	if not _out.is_empty():
		root.get_texture().get_image().save_png(_out.path_join(name + ".png"))

func _process(delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_main.director.begin()
	if _frame < 3:
		return false
	_t += delta
	var gs = root.get_node("GameState")
	var yard = _main.get_node("YardChoice")
	if _t > 90.0:
		_check(false, "timed out in state %s" % _state)
		return _finish()
	match _state:
		"wait":
			if gs.phase != gs.Phase.DAWN:
				return false
			var slides: Array = load("res://scenes/story/story_data.gd").slides_for_day(gs.current_day)
			_check(slides.filter(func(s): return s.get("choice", false)).is_empty(), "no story card carries the choice")
			_check(yard.open, "the Broad Wall's first dawn opens the yard choice")
			_check(gs.boon == "", "nothing in play yet")
			_mark = _t
			_state = "held"
		"held":
			if _t - _mark < 7.0:
				return false
			_shot("choice_open")
			_check(gs.phase == gs.Phase.DAWN and yard.open, "the dawn waits for the crew")
			var host = _main.get_node("Players").get_child(0)
			host.global_position = yard.ring_at(1) + Vector3(0, 0.1, 0)
			_mark = _t
			_state = "stand"
		"stand":
			if yard.open:
				var host = _main.get_node("Players").get_child(0)
				host.global_position = yard.ring_at(1) + Vector3(0, 0.1, 0)
				if _t - _mark > 6.0:
					_check(false, "the choice closed after the host stood in a ring")
					return _finish()
				return false
			_check(_t - _mark < 3.0, "closed %.1f s after standing in" % (_t - _mark))
			_check(gs.boon == "watch", "the second ring: %s" % gs.boon)
			_check(gs.mod("harm") < 1.0 and gs.mod("work") < 1.0, "in play: harm x%.2f, work x%.2f" % [gs.mod("harm"), gs.mod("work")])
			_mark = _t
			_state = "after"
		"after":
			if _t - _mark > 1.0 and _t - _mark < 1.1:
				_shot("choice_made")
			if gs.phase == gs.Phase.WORK:
				_check(_t - _mark < 5.0, "work starts %.1f s after the pick" % (_t - _mark))
				var left: int = yard.get_children().filter(func(n): return not n.is_queued_for_deletion()).size()
				_check(left == 1, "only the chosen standard stays (%d)" % left)
				_check(gs.chronicle[gs.current_section_index].get("boon", "") == "watch", "the scribe's chronicle keeps it")
				return _finish()
	return false

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1

func _finish() -> bool:
	print("yard_choice_test: %s" % ("all passed" if _fails == 0 else "%d failed" % _fails))
	quit(1 if _fails else 0)
	return true
