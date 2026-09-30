extends SceneTree

# The scribe's aged map on the end screen, with a made-up run in the chronicle.
#   Godot --path . --script res://tools/map_age_shots.gd -- --nostory --day=30 <out_dir> [won]
# Not headless — needs the GPU.

var _out := ""
var _won := false
var _main: Node3D
var _t := 0.0
var _done := false

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "won":
			_won = true
		elif not a.begins_with("--"):
			_out = a
	root.size = Vector2i(1920, 1080)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(delta: float) -> bool:
	_t += delta
	if _t > 1.0 and not _done:
		_done = true
		var gs: Node = root.get_node("GameState")
		var runs := [
			{ "breaches": 0, "done": true, "spare": 2 },
			{ "breaches": 2, "done": true, "nightfalls": 1 },
			{ "breaches": 0, "done": true, "knocked": 2, "late": true },
			{ "breaches": 5, "done": true, "nightfalls": 2 },
			{ "breaches": 1, "done": true, "spare": 1 },
			{ "breaches": 0, "done": true },
			{ "breaches": 3, "nightfalls": 1 },
		]
		var last := 11 if _won else runs.size() - 1
		for i in last + 1:
			var r: Dictionary = runs[i % runs.size()]
			for k in r:
				gs.chronicle[i][k] = r[k]
		if _won:
			gs._set_state(52, 11, gs.Phase.DUSK, gs.breaches, 0, 0)
		_main.hud.show_end(_won)
	if _t > 4.5:
		root.get_texture().get_image().save_png("%s/end_%s.png" % [_out, "won" if _won else "lost"])
		return true
	return false
