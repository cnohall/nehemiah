extends SceneTree

# Phone-layout screenshots of the title-screen pages: menu, section picker, Friends and
# Foes, the credits roll, settings and join. Desktop preview at phone dp via --touch:
#   Godot --path . --resolution 1848x822 --fixed-fps 30 --script res://tools/mobile_menu_shots.gd -- --touch <out_dir> [--dp=360] [--met] [--lang=de]
# --dp overrides the preview height in dp (small phones ≈ 360, tablets 520+).
# --met marks every foe as met, so the lineup shows faces instead of silhouettes.

var _frame := 0
var _out := "user://shots"
var _steps := []
var _menu: Control

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	DirAccess.make_dir_recursive_absolute(_out)
	change_scene_to_file("res://scenes/ui/main_menu.tscn")
	var args := OS.get_cmdline_user_args()
	var lang := ""
	for a in args:
		if a.begins_with("--lang="):
			lang = a.trim_prefix("--lang=")
	var m := func(): return current_scene
	_steps = [
		[5, func(): _setup(lang, args.has("--met"))],
		[150, func(): _shot("01_menu")],
		[155, func(): m.call()._open_picker()],
		[185, func(): _shot("02_picker")],
		[186, func(): m.call()._picker._select(1)],
		[200, func(): _shot("03_picker_locked")],
		[201, func(): m.call()._picker._select(11)],
		[215, func(): _shot("04_picker_last")],
		[216, func(): m.call()._picker.close(); m.call()._folk.open()],
		[250, func(): _shot("05_folk")],
		[251, func(): m.call()._folk._medals[5].grab_focus(); m.call()._folk._select(5)],
		[285, func(): _shot("06_folk_scout")],
		[286, func(): m.call()._folk._medals[6].grab_focus(); m.call()._folk._select(6)],
		[320, func(): _shot("07_folk_sanballat")],
		[321, func(): m.call()._folk._select(3)],
		[355, func(): _shot("08_folk_carpenter")],
		[356, func(): m.call()._folk.close(); m.call()._credits.play()],
		[420, func(): _shot("09_credits_start")],
		[421, func(): _credits_to(0.45)],
		[430, func(): _shot("10_credits_mid")],
		[431, func(): _credits_to(1.0)],
		[440, func(): _shot("11_credits_end")],
		[441, func(): m.call()._credits._finish()],
		[480, func(): m.call()._on_settings()],
		[510, func(): _shot("12_settings")],
		[511, func(): m.call().settings.close(); m.call()._open_join()],
		[540, func(): _shot("13_join")],
		[541, func(): quit()],
	]

func _setup(lang: String, met: bool) -> void:
	if not lang.is_empty():
		TranslationServer.set_locale(lang)
	if met:
		var gs := root.get_node("GameState")
		gs.has_met("scout")   # loads the saved set first
		for k: String in gs.MET_AT:
			gs._met[k] = true   # in memory only: mark_met would save it

# Jump the roll to a share of its run (0 = first line at the fold, 1 = resting at the end)
func _credits_to(k: float) -> void:
	var c = current_scene._credits
	var start: float = c._clip.size.y
	var end_y: float = c._clip.size.y * 0.6 - c._column.size.y
	c._wait = 0.0
	c._column.position.y = lerpf(start, end_y + 1.0, k)

func _process(_delta: float) -> bool:
	_frame += 1
	while not _steps.is_empty() and _frame >= _steps[0][0]:
		var step: Array = _steps.pop_front()
		step[1].call()
	return false

func _shot(name: String) -> void:
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("shot ", name)
