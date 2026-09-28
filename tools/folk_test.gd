extends SceneTree

# Friends and Foes, driven like a player would: opens from the menu button, walks the
# lineup with the arrow keys, drags the figure, checks the signature move plays, backs
# out with Esc and reopens. Screenshots along the way.
#   Godot --path . [--resolution WxH] --script res://tools/folk_test.gd -- <out_dir> [--lang=de] [--unlock-all]
# Exit code 0 = every step behaved.

var _out := "."
var _menu: Control
var _page: Control
var _frame := 0
var _fails: Array[String] = []
var _lang := ""
var _moves := {}     # animations the big figure played since the last pick

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lang="):
			_lang = a.trim_prefix("--lang=")
		elif not a.begins_with("--"):
			_out = a
	Engine.max_fps = 60   # frame counts below are timings at 60 fps

func _key(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	var r := InputEventAction.new()
	r.action = action
	Input.parse_input_event(r)

func _mouse(pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	Input.parse_input_event(e)

func _move(pos: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = rel
	Input.parse_input_event(e)

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)

func _process(_delta: float) -> bool:
	_frame += 1
	if _page and _page._rig:
		_moves[_page._rig.animation] = true
	match _frame:
		1:
			if not _lang.is_empty():
				TranslationServer.set_locale(_lang)   # after Settings.apply() in the autoloads
			_menu = load("res://scenes/ui/main_menu.tscn").instantiate()
			root.add_child(_menu)
			current_scene = _menu
		40:
			_page = _menu.get("_folk")
			(_menu.get("_folk_btn") as Button).pressed.emit()
		70:
			_check(_page.visible, "page opens from the menu button")
			_check(_page._selected == 0, "opens on Nehemiah")
			_shot("open")
			_key("ui_right")
		80:
			_check(_page._selected == 1, "→ moves to the Builder")
			_key("ui_left")
			_key("ui_left")
		90:
			_check(_page._selected == ENTRIES_LAST(), "← from the first wraps to the last")
			_moves.clear()
			_page._medals[5].grab_focus()   # scout
		104:
			_shot("scout")
		150:
			_check(not root.get_node("GameState").has_met("scout") or _moves.has("thrust_down"), "scout thrusts when picked (%s)" % ", ".join(_moves.keys()))
			_check(_page._rig.animation == "idle_down", "…and settles back to idle")
			var c: Vector2 = _page._plate.get_global_rect().get_center()
			_mouse(c, true)
			_move(c + Vector2(120, 0), Vector2(120, 0))
		152:
			_check(absf(_page._drag) > 1.0, "dragging the plate turns the figure (%.2f)" % _page._drag)
			_mouse(_page._plate.get_global_rect().get_center(), false)
		300:
			_check(absf(_page._drag) < 1.0, "the figure eases back after the drag")
			_page._medals[7].grab_focus()   # brute
		330:
			_shot("brute")
			_key("ui_cancel")
		340:
			_check(not _page.visible, "Esc closes the page")
			_check((_menu.get("_folk_btn") as Button).has_focus(), "focus returns to the menu button")
			(_menu.get("_folk_btn") as Button).pressed.emit()
		360:
			_check(_page.visible and _page._selected == 0, "reopens on Nehemiah")
			_page._back_btn.grab_focus()
			_key("ui_accept")
		370:
			_check(not _page.visible, "Back button closes the page")
			print("PASS" if _fails.is_empty() else "FAIL: %s" % ", ".join(_fails))
			quit(0 if _fails.is_empty() else 1)
	return false

func ENTRIES_LAST() -> int:
	return _page.ENTRIES.size() - 1

func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, name])
