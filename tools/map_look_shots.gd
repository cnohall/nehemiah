extends SceneTree

# The circuit map card (day 18, aged, a made-up run) once per diorama look.
#   Godot --path . --script res://tools/map_look_shots.gd -- <out_dir> [look ...]
# Not headless - needs the GPU.

const WAIT := 3.0

var _out := ""
var _looks: Array[int] = []
var _story: CanvasLayer
var _map: Control
var _k := -1
var _t := 0.0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			_looks.append(int(a))
		elif not a.begins_with("--"):
			_out = a
	if _looks.is_empty():
		_looks = [0, 1, 2, 3]
	DisplayServer.window_set_size(Vector2i(1920, 1080))

func _process(delta: float) -> bool:
	if _story == null:
		var gs := root.get_node("GameState")
		var runs := [
			{ "breaches": 0, "done": true, "spare": 2 },
			{ "breaches": 2, "done": true, "nightfalls": 1 },
			{ "breaches": 0, "done": true, "spare": 3 },
			{ "breaches": 0, "done": true, "spare": 3 },
			{ "breaches": 1, "nightfalls": 1 },
		]
		for i in runs.size():
			for key in runs[i]:
				gs.chronicle[i][key] = runs[i][key]
			gs.section_marks[i] = [7, 5, 7, 7, 0][i]
		gs.current_day = 18
		_story = load("res://scenes/story/story_player.gd").new()
		root.add_child(_story)
		var slides: Array = load("res://scenes/story/story_data.gd").slides_for_day(18)
		_story.play([slides.filter(func(s): return s.has("map"))[0]])
		_map = _story.find_children("*", "Control", true, false).filter(func(n): return "look" in n)[0]
		_next()
		return false
	_t += delta
	if _t > WAIT:
		print("window ", DisplayServer.window_get_size(), " root ", root.size)
		root.get_texture().get_image().save_png("%s/look_%d.png" % [_out, _looks[_k]])
		if not _next():
			return true
	return false

func _next() -> bool:
	_k += 1
	_t = 0.0
	if _k >= _looks.size():
		return false
	_map.look = _looks[_k]
	return true
