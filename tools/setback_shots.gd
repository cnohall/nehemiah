extends SceneTree

# Shots of the setbacks' world cues: the fox over the wall, the scribe's margin notes.
#   Godot --path . --script res://tools/setback_shots.gd -- --nostory --day=14 <out_dir>
var _out := ""
var _main: Node3D
var _frame := 0
var _step := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	root.size = Vector2i(1920, 1080)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_main.director.begin()
	if _frame < 3:
		return false
	var gs = root.get_node("GameState")
	if gs.phase != gs.Phase.WORK:
		return false
	_main.get_node("WaveManager").stop()
	for e in _main.get_node("Enemies").get_children():
		e.queue_free()
	var cam: Camera3D = _main.camera
	if _step == 0:
		_main.set_process(false)
		_main.set_physics_process(false)
		for c in root.find_children("*", "CanvasLayer", true, false):
			c.visible = false
		print("wall piece at ", _main.get_node("Wall/Section3").global_position)
		_main.director._setback_at_dawn()
		root.get_node("GameState").add_journal("Pulled down in the night · Neh. 4:10")
		root.get_node("GameState").add_journal("Short of hands: the hungry were not fed · Neh. 5:5")
		_step = 1
		_frame = 10
	cam.size = 14.0
	var look: Vector3 = _main.get_node("Wall/Section3").global_position
	if _step == 2:
		for n in root.find_children("*", "Node3D", true, false):
			if n.get_script() != null and str(n.get_script().resource_path).ends_with("scribe.gd"):
				look = n.global_position
				for p in _main.get_node("Players").get_children():
					if p.is_multiplayer_authority() and p.brain == null:
						p.global_position = look + Vector3(1.0, 0.0, 2.5)
		cam.size = 6.0
		look += Vector3(0, 2.0, 0)
	cam.global_position = look + Vector3(20, 20, 20)
	cam.look_at(look, Vector3.UP)
	if _frame == 10 + 100 * _step - 100 + 100 and _step == 1:
		pass
	if _step == 1 and _frame >= 170:
		root.get_texture().get_image().save_png(_out + "/fox.png")
		_step = 2
		_frame = 10
	elif _step == 2 and _frame >= 40:
		root.get_texture().get_image().save_png(_out + "/scribe.png")
		quit()
		return true
	return false
