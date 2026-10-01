extends SceneTree

# Shots of the Fountain Gate's households (GDD §5.12):
#   Godot --path . --script res://tools/households_shots.gd -- --nostory --day=34 <out_dir>
var _out := ""
var _main: Node3D
var _frame := 0
var _t := 0.0
var _step := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	root.size = Vector2i(1920, 1080)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_main.fit_bots(0)
		_main.director.begin()
	if _frame < 3:
		return false
	_t += delta
	for e in _main.get_node("Enemies").get_children():
		e.queue_free()
	var gs = root.get_node("GameState")
	if gs.phase != gs.Phase.WORK:
		return false
	var player: Node3D = _main.get_node("Players").get_child(0)
	var spots := [Vector3(-4.5, 0.1, 11.0), Vector3(-12.5, 0.1, 11.0), Vector3(4.0, 0.1, 12.0)]
	if _step < spots.size() and _t > 2.0 + _step * 2.0:
		player.global_position = spots[_step]
		_step += 1
	elif _step >= spots.size() and _t > 2.0 + spots.size() * 2.0 + 1.0:
		return _finish()
	elif _step > 0 and fposmod(_t, 2.0) > 1.6 and fposmod(_t, 2.0) < 1.7:
		root.get_texture().get_image().save_png("%s/households_%d.png" % [_out, _step])
	return false

func _finish() -> bool:
	quit(0)
	return true
