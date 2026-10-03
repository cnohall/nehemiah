extends SceneTree

# Switching the art style after the game scene reloads (a new day / stretch) must not hit
# the freed LookPass of the old scene:
#   Godot --headless --path . --script res://tools/look_reload_test.gd -- --nostory
# - loads main, reloads it twice (as DayDirector does), then cycles Settings.art_style
# - the live scene's LookPass follows each change
# Exit code 0 = every check passed; the run's output must show no "was freed" / Nil errors.

var _frame := 0
var _fails := 0
var _start_style := 0

func _initialize() -> void:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main

func _process(_delta: float) -> bool:
	_frame += 1
	var settings = root.get_node("Settings")
	match _frame:
		5:
			_start_style = settings.art_style
			reload_current_scene()
		15:
			reload_current_scene()
		25:
			for s in [1, 2, 0, 2, 1, 0]:
				settings.art_style = s
				var look := _look()
				_check(look != null, "LookPass in the live scene")
				if look:
					_check(look.look == LookPass.STYLES[s], "look follows style %d" % s)
		30:
			settings.art_style = _start_style
			print("look_reload_test: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
			quit(1 if _fails else 0)
	return false

func _look() -> LookPass:
	for c in current_scene.get_children():
		if c is LookPass:
			return c
	return null

func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)
