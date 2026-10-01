extends SceneTree

# Jeshanah's old and burned units at dawn of the work: one shot.
#   Godot --path . --script res://tools/ruins_shots.gd -- --nostory --day=9 <out_dir>

var _out := ""
var _main: Node3D
var _frame := 0
var _t := 0.0
var _posed := false
var _wait := 60

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	root.size = Vector2i(1600, 900)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_main.director.begin()
	if _frame < 3:
		return false
	_t += delta
	var gs = root.get_node("GameState")
	if not _posed and gs.phase == gs.Phase.WORK:
		_posed = true
		_main.get_node("WaveManager").stop()
		_main.hud.hide()
		var me: Node3D = _main.get_node("Players").get_child(0)
		me.set_physics_process(false)
		me.global_position = Vector3(-4.0, 0.1, 4.0)
		(_main.get_node("Camera3D") as Camera3D).size = 18.0
		return false
	if _posed:
		_wait -= 1
		if _wait == 0:
			root.get_texture().get_image().save_png("%s/ruins.png" % _out)
			return true
	return _t > 40.0
