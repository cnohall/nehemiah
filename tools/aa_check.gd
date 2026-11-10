extends SceneTree

# Anti-aliasing modes side by side on (nearly) the same frames: MSAA 2x, SMAA, FXAA.
#   Godot --path . --script res://tools/aa_check.gd -- --nostory <out_dir>
var _out := "res://build/aa"
const MODES := [["msaa2", Viewport.MSAA_2X, Viewport.SCREEN_SPACE_AA_DISABLED],
	["smaa", Viewport.MSAA_DISABLED, Viewport.SCREEN_SPACE_AA_SMAA],
	["fxaa", Viewport.MSAA_DISABLED, Viewport.SCREEN_SPACE_AA_FXAA]]
var _main: Node3D
var _frame := 0
const SHOTS := [[Vector2(3.0, 4.0), 18.0, "play"], [Vector2(6.0, 3.0), 7.0, "close"], [Vector2(-2.0, 12.0), 11.0, "city"]]

func _initialize() -> void:
	var rest: Array = []
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			rest.append(a)
	if rest.size() > 0:
		_out = rest[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(1920, 1080)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_main.director.begin()
		var settings: Node = root.get_node("Settings")
		settings.quality = 2
		settings.render_scale = 1.0
		settings._apply_graphics()
		_main.hud.visible = false
	# Each shot: frame it, then take it at both sizes a few frames apart
	var step := _frame - 30
	if step < 0:
		return false
	# Freeze the world for the shots so the three modes see the same moment
	if step == 0:
		_main.process_mode = Node.PROCESS_MODE_DISABLED
	var m := step / 6
	if m >= MODES.size():
		return true
	if step % 6 == 0:
		root.msaa_3d = MODES[m][1]
		root.screen_space_aa = MODES[m][2]
	if step % 6 == 5:
		root.get_texture().get_image().save_png("%s/%s.png" % [_out, MODES[m][0]])
	return false
