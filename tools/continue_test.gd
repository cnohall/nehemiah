extends SceneTree

# Campaign save / Continue (GameState.campaign_save), without playing 13 days:
#   Godot --headless --path . --script res://tools/continue_test.gd
# Saves a run as it stood at the Broad Wall's dawn, picks it up again the way the title's
# Continue does (restart_day → apply_restart) and checks the day, the marks and the
# chronicle came back; a win clears the save. The player's own progress.cfg is put back
# as it was afterwards. Exit code 0 = every check passed.

var _fails := 0
var _backup: PackedByteArray
var _had := false

func _process(_delta: float) -> bool:
	var gs = root.get_node("GameState")
	var path: String = gs.PROGRESS_PATH
	_had = FileAccess.file_exists(path)
	if _had:
		_backup = FileAccess.get_file_as_bytes(path)
	gs.reset()
	gs.clear_campaign()
	_check(gs.campaign_save().is_empty(), "no save to begin with")
	# A run three stretches in: marks for the first three, a breach in the chronicle
	gs.section_marks[0] = 7
	gs.section_marks[1] = 3
	gs.section_marks[2] = 1
	gs.chronicle[1]["breaches"] = 2
	gs._save_campaign(13)
	var saved: Dictionary = gs.campaign_save()
	_check(saved.get("day", -1) == 13 and saved.get("section", -1) == 3, "saved at the Broad Wall, day 13")
	# The title's Continue
	gs.reset()
	gs.restart_day = 13
	gs.apply_restart()
	_check(gs.current_day == 13 and gs.current_section_index == 3, "picks up on day 13")
	_check(gs.section_marks[0] == 7 and gs.section_marks[2] == 1 and gs.section_marks[3] == -1, "marks came back")
	_check(gs.chronicle[1]["breaches"] == 2, "the scribe's map came back")
	_check(gs.total_marks() == 3 + 2 + 1, "total marks %d" % gs.total_marks())
	# A new stretch's dawn saves over it; the win clears it
	gs._set_state(18, 4, gs.Phase.DAWN, 0, 0, 0)
	_check(gs.campaign_save().get("day", -1) == 18, "the next stretch's dawn saves day 18")
	gs._set_state(52, 11, gs.Phase.WON, 0, 0, 0)
	_check(gs.campaign_save().is_empty(), "the win clears the save")
	# Put the player's file back
	if _had:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(_backup)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("RESULT: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)
	return true

func _check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok:
		_fails += 1
