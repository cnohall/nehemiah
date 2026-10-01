extends SceneTree

# The choice card before a new stretch (GDD §6.4), offline:
#   Godot --path . --script res://tools/choice_test.gd -- --day=9 <out_dir> [pick]
# Plays the story to its last card, shoots it, picks an option (left / right from "Keep to
# the plan"; default one left = "Work on till the stars") and checks the boon in play.
# Exit code 0 = every check passed.

var _main: Node3D
var _out := ""
var _pick := ""   # a boon key; empty = the second of the stretch's two
var _frame := 0
var _t := 0.0
var _last_press := 0.0
var _state := "story"
var _fails := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			if _out.is_empty():
				_out = a
			else:
				_pick = a
	root.size = Vector2i(1920, 1080)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _key(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	root.push_input(ev)

func _process(delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_main.director.begin()
		var g = root.get_node("GameState")
		for key: String in g.BOONS:
			var lines: Dictionary = g.boon_lines(key)
			_check(not lines["gain"].is_empty() and not lines["cost"].is_empty(), "%s has a gain and a cost (%s | %s)" % [key, lines["gain"], lines["cost"]])
		for i in g.SECTIONS.size():
			for key: String in g.choices_for(i):
				_check(g.BOONS.has(key), "section %d offers a known boon (%s)" % [i, key])
	if _frame < 3:
		return false
	_t += delta
	var gs = root.get_node("GameState")
	var story = _main.story
	if _t > 120.0:
		_check(false, "timed out in " + _state)
		return _finish()
	match _state:
		"story":
			if not story.is_playing():
				return false
			if story._on_choice_card() and not story._typing() and story._choice_panels.size() > 0 and story._text.visible_ratio >= 1.0:
				_state = "shoot"
				_last_press = _t
			elif _t - _last_press > 0.5:
				_last_press = _t
				_key("interact")
		"shoot":
			if _t - _last_press > 1.5:
				root.get_texture().get_image().save_png("%s/choice.png" % _out)
				_check(story._choice_keys == gs.choices_for(gs.current_section_index), "the stretch's own two options (%s)" % [story._choice_keys])
				if _pick.is_empty():
					_pick = story._choice_keys[1]
				var want: int = story._choice_keys.find(_pick)
				var from: int = story._choice_index
				for i in absi(want - from):
					_key("ui_left" if want < from else "ui_right")
				print("  index ", from, " -> ", story._choice_index, " want ", want, " card=", story._on_choice_card(), " typing=", story._typing())
				_state = "confirm"
				_last_press = _t
		"confirm":
			if _t - _last_press > 0.5:
				_check(story._choice_keys[story._choice_index] == _pick, "picked %s" % _pick)
				_key("interact")
				_state = "dawn"
		"dawn":
			if gs.phase == gs.Phase.DAWN or gs.phase == gs.Phase.WORK:
				_check(gs.boon == _pick, "boon in play is %s (%s)" % [_pick, gs.boon])
				var sec: Dictionary = gs.get_current_section()
				_check(is_equal_approx(gs.pressure(), sec.get("pressure", 1.0) * gs.BOONS[_pick]["mods"].get("pressure", 1.0)), "pressure follows the boon")
				_check(is_equal_approx(gs.mod("harm"), gs.BOONS[_pick]["mods"].get("harm", 1.0)), "harm follows the boon")
				_check(gs.chronicle[gs.current_section_index]["boon"] == _pick, "the scribe wrote it down")
				var posts: Array = _main.get_tree().get_nodes_in_group("watch_posts")
				var raised := posts.filter(func(p): return p.built).size()
				_check((raised == posts.size() and posts.size() > 0) == gs.boon_posts(), "posts raised only where the boon says so (%d of %d)" % [raised, posts.size()])
				_finish()
				return true
	return false

func _check(ok: bool, what: String) -> void:
	print("  ", "ok   " if ok else "FAIL ", what)
	if not ok:
		_fails += 1

func _finish() -> bool:
	print("choice_test: ", "FAIL" if _fails > 0 else "PASS")
	quit(1 if _fails > 0 else 0)
	return true
