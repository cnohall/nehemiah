extends SceneTree

# Sanballat, Tobiah and Geshem on the rise (Leaders), then walking off (Neh. 6:16):
#   Godot --path . --script res://tools/leaders_shots.gd -- --nostory --day=51 <out_dir>
# Fires a SectionBeats beat naming "all" once the work starts, shoots them arriving and
# calling, then ends the day and shoots them leaving. Exit code 0 = they came and went.

var _out := ""
var _main: Node3D
var _frame := 0
var _t := 0.0
var _mark := -1.0
var _step := 0
var _fails := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	root.size = Vector2i(1920, 1080)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_main.fit_bots(0)
		_main.director.begin()
	if _frame < 3:
		return false
	_t += delta
	var gs = root.get_node("GameState")
	for e in _main.get_node("Enemies").get_children():
		e.queue_free()
	var leaders: Node3D = null
	for c in _main.get_children():
		if c.get_script() != null and c.get_script().resource_path.ends_with("leaders.gd"):
			leaders = c
	var player: Node3D = _main.get_node("Players").get_child(0) if _main.get_node("Players").get_child_count() else null
	match _step:
		0:
			if gs.phase == gs.Phase.WORK:
				player.global_position = Vector3(0.0, 0.1, -4.0)
				var beats := _main.get_node_or_null("SectionBeats")
				if beats != null and beats.has_signal("beat_fired"):
					beats.beat_fired.emit(gs.current_section_index, "last", { "leader": "all" })
				_mark = _t
				_step = 1
		1:
			if _t - _mark > 5.0:
				_check(leaders != null and leaders._here.size() == 3, "all three on the rise (%d)" % (leaders._here.size() if leaders else -1))
				root.get_texture().get_image().save_png(_out + "/leaders_rise.png")
				leaders._leave()
				_mark = _t
				_step = 2
		2:
			if _t - _mark > 1.2:
				root.get_texture().get_image().save_png(_out + "/leaders_leave.png")
				_mark = _t
				_step = 3
		3:
			if _t - _mark > 3.0:
				var left := leaders.get_children().filter(func(c): return c is Node3D and not c.is_queued_for_deletion()).size()
				_check(left == 0, "they walked off (%d left)" % left)
				print("RESULT: %s" % ("PASS" if _fails == 0 else "FAIL"))
				quit(0 if _fails == 0 else 1)
				return true
	if _t > 60.0:
		_check(false, "timed out at step %d" % _step)
		quit(1)
		return true
	return false

func _check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok:
		_fails += 1
