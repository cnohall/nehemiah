extends SceneTree

# Learn the basics (Tutorial), offline, windowed:
#   Godot --path . --script res://tools/tutorial_test.gd -- [<out_dir>]
# Plays each step by doing what it asks (straight on the world state), checks the step
# moves on, and that no waves come, the scout and the fallen crewmate appear, and the
# last step offers the way back. Screenshots the panel to out_dir. Exit code 0 = passed.

var _main: Node
var _gs: Node
var _tut: Node
var _frame := 0
var _t := 0.0
var _fails := 0
var _out := ""
var _last_step := -1
var _step_since := 0.0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	root.size = Vector2i(1280, 720)
	root.get_node("GameState").tutorial = true
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(delta: float) -> bool:
	_frame += 1
	if _frame < 5:
		return false
	_t += delta
	if _t > 90.0:
		_check(false, "timed out on step %d" % _last_step)
		return _finish()
	_gs = root.get_node("GameState")
	if _tut == null:
		for c in _main.get_children():
			if c is CanvasLayer and c.has_method("_any_built"):
				_tut = c
		_check(_tut != null, "tutorial running")
		if _tut == null:
			return _finish()
	var i: int = _tut._i
	if i != _last_step:
		_last_step = i
		_step_since = 0.0
		print("  step %d: %s" % [i, _tut._title.text])
		if i == 1 and _out != "":
			root.get_texture().get_image().save_png(_out + "/tutorial.png")
	_step_since += delta
	if _tut._between > 0.0 or _step_since < 0.5:
		return false
	var me: Node3D = _main.players_root.get_node(str(root.multiplayer.get_unique_id()))
	match i:
		0: _tut._step_t = 9.0   # past the intro's read time
		1: me.global_position += Vector3(5, 0, 0)
		2: me._dash_cd = 0.5
		3: me.carried_kind = "stone"
		4: me.carried_kind = ""; _main.director._stats["loads"] = 1
		5: get_nodes_in_group("wall_sections")[0].stage = 1
		6:
			if is_instance_valid(_tut._scout):
				_check(_main.enemies_root.get_child_count() == 1, "a scout, and no waves: %d enemy" % _main.enemies_root.get_child_count())
				_tut._scout.queue_free()
		7:
			if _tut._fallen != null and _tut._fallen.downed:
				_check(true, "crewmate fell")
				_tut._fallen._set_downed.rpc(false)
		8:
			_check(_tut._leave.text == "Back to the title", "last step offers the way back")
			_check(_gs.phase in [_gs.Phase.WORK, _gs.Phase.DAWN], "still at work (phase %d)" % _gs.phase)
			if _out != "":
				root.get_texture().get_image().save_png(_out + "/tutorial_end.png")
			return _finish()
	return false

func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1

func _finish() -> bool:
	print("tutorial_test: %d failed" % _fails)
	quit(1 if _fails else 0)
	return true
