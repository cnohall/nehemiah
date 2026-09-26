extends SceneTree

# Replay flow, end to end (offline): pick a section as the menu would, play it through
# (each day's work is waved through by calling DayDirector._end_day), and screenshot
# the section card, the replay end screen and the map it returns to.
#   Godot --path . --script res://tools/replay_test.gd -- [--section=N] <out_dir>
# Default section 11 (Miphkad Gate, 2 days) keeps it short. The player's real
# user://progress.cfg is put back as it was afterwards.
# Exit code 0 = the run ended in WON with the section rated and the map reopened.

const TIMEOUT := 150.0   # the longest sections run six days

var _out := "."
var _section := 11
var _main: Node
var _frame := 0
var _t := 0.0
var _won_t := -1.0
var _menu_t := -1.0
var _story_shot := false
var _saved: PackedByteArray
var _had_progress := false

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--section="):
			_section = a.trim_prefix("--section=").to_int()
		elif not a.begins_with("--"):
			_out = a
	root.size = Vector2i(1920, 1080)
	_had_progress = FileAccess.file_exists("user://progress.cfg")
	if _had_progress:
		_saved = FileAccess.get_file_as_bytes("user://progress.cfg")

func _process(delta: float) -> bool:
	_frame += 1
	_t += delta
	var gs := root.get_node("GameState")
	if _t > TIMEOUT:
		print("FAIL: timed out in phase %d" % gs.phase)
		return _finish(1)
	if _frame == 1:
		# What the menu does on "Build this stretch"
		gs.replay_section = _section
		gs.picker_return = _section
		_main = load("res://scenes/main/main.tscn").instantiate()
		root.add_child(_main)
		current_scene = _main
		return false
	if _frame == 3:
		_main.director.begin()
	if _menu_t >= 0.0:
		_menu_t += delta
		if _menu_t > 3.0:
			_shot("map")
			var picker = current_scene.get("_picker")
			var ok: bool = picker != null and picker.visible
			print(("PASS" if ok else "FAIL") + ": replay of %s rated %d/3, map reopened: %s" % [
				gs.SECTIONS[_section]["name"], gs.mark_count(gs.best_marks(_section)), ok])
			return _finish(0 if ok else 1)
		return false
	if _main == null or not is_instance_valid(_main):
		return false
	match gs.phase:
		gs.Phase.STORY:
			if not _story_shot and _t > 2.5:
				_shot("card")
				_story_shot = true
				_main.director.force_story_end()
		gs.Phase.WORK:
			_main.director._end_day()
		gs.Phase.WON:
			if _won_t < 0.0:
				_won_t = 0.0
			_won_t += delta
			if _won_t > 3.0:
				_shot("end")
				_main.hud._leave()
				_menu_t = 0.0
		gs.Phase.LOST:
			print("FAIL: lost")
			return _finish(1)
	return false

func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name])

func _finish(code: int) -> bool:
	if _had_progress:
		var f := FileAccess.open("user://progress.cfg", FileAccess.WRITE)
		f.store_buffer(_saved)
		f.close()
	elif FileAccess.file_exists("user://progress.cfg"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://progress.cfg"))
	quit(code)
	return true
