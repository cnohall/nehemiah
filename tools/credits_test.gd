extends SceneTree

# Credits from the main menu, driven like a player: press the Credits entry, hold Enter
# (the roll hurries and the menu behind must not react), then Esc skips back to the
# menu with focus on Credits. Screenshots the menu and the roll.
#   Godot --path . --script res://tools/credits_test.gd -- <out_dir>
# Exit code 0 = every step behaved.

var _out := "."
var _menu: Control
var _roll: CanvasLayer
var _frame := 0
var _y0 := 0.0
var _fails: Array[String] = []

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	Engine.max_fps = 60   # frame counts below are timings at 60 fps

func _action(action: String, pressed: bool) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = pressed
	Input.parse_input_event(e)

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)

func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			_menu = load("res://scenes/ui/main_menu.tscn").instantiate()
			root.add_child(_menu)
			current_scene = _menu
		60:
			var btn: Button = _menu.get("_credits_btn")
			btn.grab_focus()
			_shot("menu")
			btn.pressed.emit()
			_roll = _menu.get("_credits")
		200:
			_check(_roll.is_playing(), "Credits entry starts the roll")
			_y0 = _roll._column.position.y
			_action("ui_accept", true)
		260:
			var fast: float = _y0 - _roll._column.position.y
			_check(fast > 58.0 * 2.0, "holding Enter hurries the roll (%.0f px in 1 s)" % fast)
			_check(_roll._column.position.y < _y0, "…without restarting it")
			_action("ui_accept", false)
			_shot("roll")
		270:
			_action("ui_cancel", true)
			_action("ui_cancel", false)
		340:
			_check(not _roll.is_playing(), "Esc skips the roll")
			_check((_menu.get("_credits_btn") as Button).has_focus(), "focus returns to Credits")
			print("PASS" if _fails.is_empty() else "FAIL: %s" % ", ".join(_fails))
			quit(0 if _fails.is_empty() else 1)
	return false

func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, name])
