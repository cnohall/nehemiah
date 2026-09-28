extends SceneTree

# UI screenshots: title menu, then the in-game gather phase, pause menu and a working day.
#   Godot --path . --script res://tools/ui_shots.gd -- --nostory <out_dir> [--pad] [--size=WxH] [--lang=ko]
# `--pad` pretends a gamepad is in use (button labels, focus rings); `--lang` picks the
# UI language for this run only (not saved).

var _out := ""
var _pad := false
var _lang := ""
var _frame := 0
var _t := 0.0
var _step := 0
var _main: Node

const STEPS := [
	[1.5, "shot", "menu"],
	[1.6, "focus_menu", null],
	[1.9, "shot", "menu_focus"],
	[2.0, "start_game", null],
	[3.5, "shot", "gather"],
	[3.6, "pause", null],
	[4.2, "shot", "pause"],
	[4.3, "pause", null],
	[4.5, "begin", null],
	[5.2, "shot", "dawn_banner"],
	[11.0, "shot", "work"],
	[11.1, "quit", null],
]

func _initialize() -> void:
	var res := Vector2i(1920, 1080)
	for a in OS.get_cmdline_user_args():
		if a == "--pad":
			_pad = true
		elif a.begins_with("--lang="):
			_lang = a.trim_prefix("--lang=")
		elif a.begins_with("--size="):
			var wh := a.trim_prefix("--size=").split("x")
			res = Vector2i(int(wh[0]), int(wh[1]))
		elif not a.begins_with("--"):
			_out = a
	root.size = res
	var menu: Node = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu

func _process(delta: float) -> bool:
	_frame += 1
	# After the autoloads: Settings.apply() sets the saved / OS locale in its _ready
	if _frame == 1 and not _lang.is_empty():
		TranslationServer.set_locale(_lang)
	if _frame == 2 and _pad:
		var ev := InputEventJoypadButton.new()
		ev.button_index = JOY_BUTTON_LEFT_STICK
		ev.pressed = true
		Input.parse_input_event(ev)
	_t += delta
	while _step < STEPS.size() and _t >= STEPS[_step][0]:
		var s: Array = STEPS[_step]
		_step += 1
		match s[1]:
			"shot":
				root.get_texture().get_image().save_png("%s/%s%s.png" % [_out, s[2], "_pad" if _pad else ""])
			"focus_menu":
				var f := root.gui_get_focus_owner()
				print("menu focus: ", f.name if f else "<none>")
			"start_game":
				# Out of the tree now, so the menu hands back GameState.attract before Main reads it
				var menu := current_scene
				root.remove_child(menu)
				menu.queue_free()
				_main = load("res://scenes/main/main.tscn").instantiate()
				root.add_child(_main)
				current_scene = _main
			"pause":
				var ev := InputEventAction.new()
				ev.action = "pause"
				ev.pressed = true
				Input.parse_input_event(ev)
			"begin":
				_main.director.begin()
			"quit":
				return true
	return false
