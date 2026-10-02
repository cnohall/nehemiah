extends SceneTree

# Circuit map screenshots: a few section cards.
#   Godot --path . --write-movie <dir>/f.png --fixed-fps 10 --quit-after 200 --script res://tools/map_shots.gd
# Every 40 frames the next card shows; the rise animation plays in the first ~25.

const CARDS := [
	{ "day": 1 },
	{ "day": 5 },
	{ "day": 24 },
	{ "day": 51 },
]
const FRAMES_PER := 40

var _story: CanvasLayer
var _frame := 0

# Loaded at runtime: StoryData needs the GameState autoload, which a --script
# harness doesn't have at compile time
func _process(_delta: float) -> bool:
	if _story == null:
		_story = load("res://scenes/story/story_player.gd").new()
		root.add_child(_story)
		# Sample marks so finished gates show a mix of earned and missed
		var gs := root.get_node("GameState")
		for i in 11:
			gs.section_marks[i] = [7, 5, 3, 1, 6, 0][i % 6]
	if _frame % FRAMES_PER == 0:
		var i := _frame / FRAMES_PER
		if i >= CARDS.size():
			return true
		var card: Dictionary = CARDS[i]
		var slides: Array = load("res://scenes/story/story_data.gd").slides_for_day(card["day"])
		var slide: Dictionary = slides.filter(func(s): return s.has("map"))[0]
		_story.play([slide])
	_frame += 1
	return false
