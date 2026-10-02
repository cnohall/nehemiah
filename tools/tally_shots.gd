extends SceneTree

# The section-complete dusk tally, on its own (no day running): marks pop in, counts below.
#   Godot --path . --write-movie <dir>/f.png --fixed-fps 10 --quit-after 70 --script res://tools/tally_shots.gd
# Frame ~40 has every mark landed. `-- --marks=N` (bitmask, default 7) picks which are earned.

var _hud: Node
var _frame := 0

func _process(_delta: float) -> bool:
	if _hud == null:
		var gs := root.get_node("GameState")
		gs.current_day = 12
		gs.current_section_index = 2
		gs.phase = gs.Phase.DUSK
		var mask := 7
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--marks="):
				mask = a.trim_prefix("--marks=").to_int()
		_hud = load("res://scenes/ui/game_hud.tscn").instantiate()
		root.add_child(_hud)
		if "--day" in OS.get_cmdline_user_args():
			# An ordinary day (`-- --day`): no marks, today's own counts
			_hud.show_tally({"breaches": 0, "time": 155, "loads": 20, "foes": 10, "unfinished": 0,
				"crew": [[1, 8, 2], [2, 5, 3], [3, 3, 4], [4, 4, 1]]})
			_frame += 1
			return false
		_hud.show_tally({
			"breaches": 0, "marks": mask, "section_breaches": 0 if mask & 2 else 2,
			"section_time": 155.0, "par": 540.0, "section_day": 2, "section_days": 5, "pace_needed": 2, "wall": 0.68 if not mask & 4 else 0.95,
			"section_time_": 155, "section_loads": 63, "section_foes": 47, "section_crew": [
				[1, 24, 5], [2, 16, 9], [3, 10, 17], [4, 13, 16]],
			"time": 155, "loads": 20, "foes": 10, "crew": [], "spare": 3, "unfinished": 0,
		})
	_frame += 1
	return false
