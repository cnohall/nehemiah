extends SceneTree

# Campaign ending, end to end (offline): start at day 51 (the Miphkad Gate), wave each
# day's work through, and check that the win plays the ending story, then the credits,
# and shows the end screen only after both. Screenshots the ring closing and the end screen.
#   Godot --path . --script res://tools/ending_test.gd -- --day=51 <out_dir>
# Exit code 0 = ending and credits shown, end screen held back until they're through.

const TIMEOUT := 90.0

var _out := "."
var _main: Node
var _frame := 0
var _t := 0.0
var _won_t := -1.0
var _held := false
var _rolled := false

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
		print("FAIL: timed out in phase %d" % gs.phase)
		quit(1)
		return true
	if _frame == 1:
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
			_main.director._end_day()
		gs.Phase.WON:
			if _won_t < 0.0:
				_won_t = 0.0
			_won_t += delta
			var end_up: bool = _main.hud.end_screen.visible
			if _won_t > 7.0 and not _held:
				_held = _main.story.is_playing() and not end_up
				_shot("ending")
				if not _held:
					print("FAIL: story playing %s, end screen %s" % [_main.story.is_playing(), end_up])
					quit(1)
					return true
				_main.story._finish()   # as Esc would
			elif _held and not _rolled and _won_t > 12.0:
				_rolled = _main.credits.is_playing() and not end_up
				_shot("credits")
				if not _rolled:
					print("FAIL: credits playing %s, end screen %s" % [_main.credits.is_playing(), end_up])
					quit(1)
					return true
				_main.credits._finish()
			elif _rolled and _won_t > 14.5:
				_shot("end")
				print(("PASS" if end_up else "FAIL") + ": ending, then credits, then end screen: %s" % end_up)
				quit(0 if end_up else 1)
				return true
	return false

func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, name])
