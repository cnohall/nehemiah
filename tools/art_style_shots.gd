extends SceneTree

# The settings panel's Art style row, then each style picked from it over the title world.
#   Godot --path . --script res://tools/art_style_shots.gd -- <out_dir>
# Puts the player's own art style back afterwards. Not headless - needs the GPU.

var _out := ""
var _menu: Control
var _panel: Control
var _saved := 0
var _t := 0.0
var _step := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a

func _process(delta: float) -> bool:
	var settings := root.get_node("Settings")
	if _menu == null:
		_saved = settings.art_style
		_menu = load("res://scenes/ui/main_menu.tscn").instantiate()
		root.add_child(_menu)
		return false
	_t += delta
	# Let the live world come up behind the menu, then open the panel and walk the styles
	var at := [6.0, 8.0, 10.0, 12.0]
	if _step < at.size() and _t > at[_step]:
		if _step == 0:
			_panel = _menu.find_children("*", "Control", true, false).filter(func(n): return "_style_btns" in n)[0]
			_panel.open()
		else:
			(_panel._style_btns[_step - 1] as Button).pressed.emit()
		_step += 1
		return false
	if _step > 0 and _t > at[_step - 1] + 1.5:
		var name: String = "panel" if _step == 1 else settings.ART_STYLES[_step - 2].to_lower()
		var path := "%s/style_%s.png" % [_out, name]
		if not FileAccess.file_exists(path):
			root.get_texture().get_image().save_png(path)
		if _step == at.size():
			settings.art_style = _saved
			settings.save()
			return true
	return false
