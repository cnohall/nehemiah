extends SceneTree

# Friends & Foes page: one shot per chosen entry, for figure and plate review.
#   Godot --path . --script res://tools/foes_shots.gd -- <out_dir> [i,j,k]
# Entries default to the builder, Nehemiah, a brute and Sanballat (whatever is at those
# indices); everyone counts as met for the run (not saved).
var _out := ""
var _picks: Array[int] = [0, 4, 8, 12]
var _page: Control
var _frame := 0
var _step := 0

func _initialize() -> void:
	var rest: Array = []
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			rest.append(a)
	_out = rest[0]
	if rest.size() > 1:
		_picks.clear()
		for p in String(rest[1]).split(","):
			_picks.append(int(p))
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(1920, 1080)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		# In memory only: mark_met would write the player's progress file
		var gs: Node = root.get_node("GameState")
		gs._load_met()
		var page_script: GDScript = load("res://scenes/ui/friends_and_foes.gd")
		for e: Dictionary in page_script.ENTRIES:
			gs._met[e["key"]] = true
		_page = page_script.new()
		root.add_child(_page)
		_page.set_anchors_preset(Control.PRESET_FULL_RECT)
		_page.open()
	if _frame < 30:
		return false
	var at := (_frame - 30) % 40
	if at == 0:
		if _step >= _picks.size():
			return true
		_page._select(mini(_picks[_step], _page.ENTRIES.size() - 1))
	elif at == 39:
		root.get_texture().get_image().save_png("%s/foes_%d.png" % [_out, _picks[_step]])
		_step += 1
	return false
