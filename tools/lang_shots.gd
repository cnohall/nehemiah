extends SceneTree

# Screens with the most text, in one language: settings (with the language picker),
# the section picker and the first story card.
#   Godot --path . --script res://tools/lang_shots.gd -- <out_dir> --lang=ko

var _out := ""
var _lang := "en"
var _frame := 0
var _t := 0.0
var _step := 0
var _menu: Node

const STEPS := [
	[1.2, "settings", null],
	[1.8, "shot", "settings"],
	[1.9, "close_settings", null],
	[2.1, "picker", null],
	[3.0, "shot", "picker"],
	[3.1, "picker_locked", null],
	[3.6, "shot", "picker_locked"],
	[3.7, "story", null],
	[6.5, "shot", "story"],
	[6.6, "quit", null],
]

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lang="):
			_lang = a.trim_prefix("--lang=")
		elif not a.begins_with("--"):
			_out = a
	root.size = Vector2i(1920, 1080)
	_menu = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(_menu)
	current_scene = _menu

func _process(delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		TranslationServer.set_locale(_lang)   # after Settings.apply() in the autoloads
	_t += delta
	while _step < STEPS.size() and _t >= STEPS[_step][0]:
		var s: Array = STEPS[_step]
		_step += 1
		match s[1]:
			"shot":
				root.get_texture().get_image().save_png("%s/%s_%s.png" % [_out, s[2], _lang])
			"settings":
				_menu.get_node("SettingsPanel").open()
			"close_settings":
				_menu.get_node("SettingsPanel").hide()
			"picker":
				_menu._open_picker()
			"picker_locked":
				_menu._picker._select(5)
			"story":
				_menu._picker.hide()
				# load(), not the class names: those would compile before the autoloads exist
				var player: Node = load("res://scenes/story/story_player.gd").new()
				_menu.add_child(player)
				player.play(load("res://scenes/story/story_data.gd").BEATS[0])
			"quit":
				return true
	return false
