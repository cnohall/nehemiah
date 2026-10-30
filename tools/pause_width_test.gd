extends SceneTree

# Pause menu must keep one width and height while trade / difficulty / bot skill / language change.
#   Godot --headless --path . --script res://tools/pause_width_test.gd
# Prints PASS/FAIL.

var _main: Node3D
var _frame := 0
var _step := 0
var _modal: Control
var _sizes: Array = []
var _fails := 0

func _initialize() -> void:
	root.size = Vector2i(1920, 1080)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _snap(tag: String) -> void:
	_sizes.append([tag, _modal.size])
	if tag in ["base", "es", "pt_BR"]:
		for c in _modal.get_node("VBox").get_children():
			if c.visible and c.get_combined_minimum_size().x > 380:
				print("   wide: ", c.name, " ", c.get_class(), " ", c.get_combined_minimum_size().x, " ", c.get("text"))
	print("%-28s %s" % [tag, _modal.size])

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 5 or _frame % 3 != 0:
		return false
	var hud: Node = _main.hud
	if hud == null:
		return false
	if _step == 0:
		_modal = hud.get_node("Root/PauseMenu/Center/Modal")
		hud._open_pause()
		_step = 1
		return false
	var gs: Node = root.get_node("GameState")
	var st: Node = root.get_node("Settings")
	match _step:
		1: _snap("base")
		2: st.difficulty = (st.difficulty + 1) % st.DIFFICULTIES.size(); _refresh(hud)
		3: _snap("difficulty+1")
		4: st.difficulty = (st.difficulty + 1) % st.DIFFICULTIES.size(); _refresh(hud)
		5: _snap("difficulty+2")
		6: st.bot_count = 1; _refresh(hud)
		7: _snap("bots 1")
		8: st.bot_skill = (st.bot_skill + 1) % 3; _refresh(hud)
		9: _snap("bot skill+1")
		10: st.bot_count = 0; _refresh(hud)
		11: _snap("bots 0")
		12: TranslationServer.set_locale("de")
		13: _snap("de")
		14: TranslationServer.set_locale("pt_BR")
		15: _snap("pt_BR")
		16: TranslationServer.set_locale("ko")
		17: _snap("ko")
		18: TranslationServer.set_locale("es")
		19: _snap("es")
		20:
			var w0: float = _sizes[0][1].x
			for s in _sizes:
				if absf(s[1].x - w0) > 0.5:
					print("FAIL width ", s[0], " ", s[1].x, " vs ", w0)
					_fails += 1
			print("PASS" if _fails == 0 else "FAILS: %d" % _fails)
			return true
	_step += 1
	return false

func _refresh(hud: Node) -> void:
	for r in hud._host_refreshers:
		r.call()

func _find(n: Node, cls: String) -> Node:
	for c in n.get_children():
		if c.get_script() != null and c.get_script().get_global_name() == cls:
			return c
		var f := _find(c, cls)
		if f != null:
			return f
	return null
