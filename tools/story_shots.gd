extends SceneTree

# Every story card that has an illustration, as the player shows it: art, drift, text.
#   Godot --path . --script res://tools/story_shots.gd -- --nostory <out_dir>
# One PNG per slide (story_<n>.png), taken once the narration has typed out.

const HOLD := 150   # frames per slide before the shot

var _out := ""
var _story: CanvasLayer
var _slides: Array = []
var _frame := 0
var _i := -1

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	root.size = Vector2i(1920, 1080)

# StoryData needs the GameState autoload, which a --script harness doesn't have at compile time
func _process(_delta: float) -> bool:
	if _story == null:
		var data = load("res://scenes/story/story_data.gd")
		for i in data.BEATS:
			_slides.append_array(data.BEATS[i])
		_slides.append_array(data.ENDING)
		_slides = _slides.filter(func(s): return s.has("art"))
		_story = load("res://scenes/story/story_player.gd").new()
		root.add_child(_story)
	if _frame % HOLD == 0:
		if _i >= 0:
			var img := root.get_texture().get_image()
			img.save_png(_out.path_join("story_%02d.png" % _i))
		_i += 1
		if _i >= _slides.size():
			return true
		_story.play([_slides[_i]])
	_frame += 1
	return false
