extends SceneTree

# Phone-layout screenshots on desktop (dp preview via --touch):
#   Godot --path . --resolution 1848x822 --script res://tools/mobile_shots.gd -- --touch <out_dir>
# Title → join keypad → settings sheet → hosted game HUD → game menu → story.

var _frame := 0
var _out := "user://shots"
var _steps := []

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	DirAccess.make_dir_recursive_absolute(_out)
	change_scene_to_file("res://scenes/ui/main_menu.tscn")
	var menu := func(): return current_scene
	_steps = [
		[160, func(): _shot("1_menu")],
		[165, func(): menu.call()._open_join(); menu.call()._type("K"); menu.call()._type("P")],
		[200, func(): _shot("2_join")],
		[205, func(): menu.call()._on_back(); menu.call()._on_settings()],
		[240, func(): _shot("3_settings")],
		[245, func(): menu.call().settings.close(); root.get_node("NetworkManager").host()],
		[400, func(): _shot("4_hud")],
		[405, func(): current_scene.hud._toggle_pause()],
		[430, func(): _shot("5_pause")],
		[435, func(): current_scene.hud._toggle_pause(); current_scene.director.begin()],
		[500, func(): _shot("6_story")],
		[505, func(): quit()],
	]

func _process(_delta: float) -> bool:
	_frame += 1
	while not _steps.is_empty() and _frame >= _steps[0][0]:
		var step: Array = _steps.pop_front()
		step[1].call()
	return false

func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(_out.path_join(name + ".png"))
	print("shot ", name)
