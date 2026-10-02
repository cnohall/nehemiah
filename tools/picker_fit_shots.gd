extends SceneTree

# The replay map's text column at the window's size, on its tallest stretches - checks
# the column shrinks to fit rather than running off the bottom.
#   Godot --path . --script res://tools/picker_fit_shots.gd -- <out_dir> [section ...]
# Not headless - needs the GPU.

var _out := ""
var _sections: Array[int] = []
var _menu: Control
var _picker: Control
var _t := 0.0
var _k := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			_sections.append(int(a))
		elif not a.begins_with("--"):
			_out = a
	if _sections.is_empty():
		_sections = [7, 11]

func _process(delta: float) -> bool:
	if _menu == null:
		_menu = load("res://scenes/ui/main_menu.tscn").instantiate()
		root.add_child(_menu)
		current_scene = _menu
		return false
	_t += delta
	if _picker == null and _t > 3.0:
		_picker = _menu.find_children("*", "Control", true, false).filter(func(n): return n.has_method("_fit_column"))[0]
		_picker.open(_sections[0])
		_t = 0.0
	elif _picker != null and _t > 2.0:
		var col: Control = _picker._column
		print("section %d: window %s, scale %.2f, column bottom %.0f of %.0f, tallest %.0f" % [_sections[_k],
			root.size, _picker._margin.scale.x, col.get_global_rect().end.y, _picker.size.y, _picker._tallest])
		root.get_texture().get_image().save_png("%s/picker_%d.png" % [_out, _sections[_k]])
		_k += 1
		if _k >= _sections.size():
			return true
		_picker._select(_sections[_k])
		_t = 0.0
	return false
