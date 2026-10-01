extends SceneTree

# Every twist card (TwistCard) as the story player shows it, one PNG each.
#   Godot --path . --script res://tools/twist_card_shots.gd -- <out_dir>

const HOLD := 120
const TWISTS := ["doors", "beams", "salvage", "mixing", "thick", "ruins", "horn", "haul", "spring", "night", "cramped", "schemes"]

var _out := ""
var _story: CanvasLayer
var _frame := 0
var _i := -1

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	root.size = Vector2i(1920, 1080)

func _process(_delta: float) -> bool:
	if _story == null:
		_story = load("res://scenes/story/story_player.gd").new()
		root.add_child(_story)
	if _frame % HOLD == HOLD - 1:
		root.get_texture().get_image().save_png(_out.path_join("twist_%s.png" % TWISTS[_i]))
	if _frame % HOLD == 0:
		_i += 1
		if _i >= TWISTS.size():
			return true
		var data = load("res://scenes/story/story_data.gd")
		_story.play([{ "eyebrow": "New at the Fish Gate", "title": data.TWIST_TITLES[TWISTS[_i]], "twist": TWISTS[_i] }])
	_frame += 1
	return false
