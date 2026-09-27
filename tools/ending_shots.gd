extends SceneTree

# The ending story (StoryData.ENDING): the ring closing, then the two closing cards.
#   Godot --path . --write-movie <dir>/f.png --fixed-fps 10 --quit-after 260 --script res://tools/ending_shots.gd
# Frames 0–119 are the finale map (rise ~20, ring closes by ~70); every 70 after, the next card.

const FIRST_FRAMES := 120
const FRAMES_PER := 70

var _story: CanvasLayer
var _frame := 0
var _slide := 0

# Loaded at runtime: StoryData needs the GameState autoload, which a --script
# harness doesn't have at compile time
func _process(_delta: float) -> bool:
	var ending: Array = load("res://scenes/story/story_data.gd").ENDING
	if _story == null:
		_story = load("res://scenes/story/story_player.gd").new()
		root.add_child(_story)
		# Sample marks so the finished gates show a mix of earned and missed
		var gs := root.get_node("GameState")
		for i in 12:
			gs.section_marks[i] = [7, 5, 3, 1, 6, 0][i % 6]
	var start := 0 if _slide == 0 else FIRST_FRAMES + (_slide - 1) * FRAMES_PER
	if _frame == start:
		if _slide >= ending.size():
			return true
		_story.play([ending[_slide]])
		_slide += 1
	_frame += 1
	return false
