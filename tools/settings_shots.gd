extends SceneTree

# The settings sheet: the main page, then the Advanced page. Nothing is saved.
#   Godot --path . --script res://tools/settings_shots.gd -- <out_dir>
var _out := ""
var _panel: Control
var _frame := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(1920, 1080)
	var bg := ColorRect.new()
	bg.color = Color(0.45, 0.38, 0.30)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	_panel = load("res://scenes/ui/settings_panel.tscn").instantiate()
	root.add_child(_panel)
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_panel.open()
	elif _frame == 20:
		root.get_texture().get_image().save_png("%s/settings_main.png" % _out)
		_panel._show_page(_panel._adv_page)
	elif _frame == 40:
		root.get_texture().get_image().save_png("%s/settings_advanced.png" % _out)
		return true
	return false
