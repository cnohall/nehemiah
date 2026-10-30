extends SceneTree

# Demo build, end to end (offline): the run stops at the dusk of day 9, with a brute sent
# that day, no ending story or credits, and the demo end card.
#   Godot --path . --script res://tools/demo_test.gd -- --demo <out_dir>
# Exit code 0 = day 9 sent a brute, and the end card (not the ending) followed it.

const TIMEOUT := 240.0
const BRUTE_WAIT := 9.0

var _out := "."
var _main: Node
var _frame := 0
var _t := 0.0
var _day9_work := 0.0
var _saw_brute := false
var _won_t := -1.0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	root.size = Vector2i(1920, 1080)

func _process(delta: float) -> bool:
	_frame += 1
	_t += delta
	var gs := root.get_node("GameState")
	if _t > TIMEOUT:
		print("FAIL: timed out on day %d, phase %d" % [gs.current_day, gs.phase])
		quit(1)
		return true
	if _frame == 1:
		if not gs.is_demo():
			print("FAIL: pass `-- --demo`")
			quit(1)
			return true
		_main = load("res://scenes/main/main.tscn").instantiate()
		root.add_child(_main)
		current_scene = _main
		return false
	if _frame == 3:
		_main.director.begin()
	match gs.phase:
		gs.Phase.STORY, gs.Phase.DUSK:
			_main.director.force_ready()
		gs.Phase.WORK:
			if gs.current_day < gs.DEMO_LAST_DAY:
				_main.director._end_day()
			else:
				_day9_work += delta
				for e in _main.enemies_root.get_children():
					if e.type == e.Type.BRUTE:
						_saw_brute = true
				if _day9_work > BRUTE_WAIT:
					_main.director._end_day()
		gs.Phase.WON:
			_won_t = maxf(_won_t, 0.0) + delta
			if _won_t > 2.5:
				var end_up: bool = _main.hud.end_screen.visible
				var title: String = _main.hud.end_screen.get_node("Center/VBox/Title").text
				_shot("demo_end")
				var ok: bool = end_up and gs.current_day == gs.DEMO_LAST_DAY and _saw_brute \
					and not _main.story.is_playing() and not _main.credits.is_playing() and title == "The first brute"
				print(("PASS" if ok else "FAIL") + ": day %d, brute %s, end card %s (%s), story %s, credits %s" \
					% [gs.current_day, _saw_brute, end_up, title, _main.story.is_playing(), _main.credits.is_playing()])
				quit(0 if ok else 1)
				return true
	return false

func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, name])
