extends SceneTree

# Render the sheep in the real level, sun and gameplay camera. Pass an output
# directory, then optionally --blockout to inspect anatomy before adding wool.
# Godot --path . --script res://tools/sheep_preview.gd -- --nostory <out_dir> [--blockout]

var _main: Node3D
var _output := ""
var _blockout := false
var _frame := 0
var _prototype: Node3D
var _focus := Vector3.ZERO

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--blockout":
			_blockout = true
		elif not arg.begins_with("--"):
			_output = arg
	DirAccess.make_dir_recursive_absolute(_output)
	root.size = Vector2i(1600, 900)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 4:
		_main.director.begin()
	if _frame == 30:
		_stage()
	if _frame == 65:
		_capture("gameplay")
		_set_camera(6.0, _focus)
	if _frame == 76:
		_capture("close")
		if _blockout:
			return true
		_prototype.visible = false
		_main.get_node("SectionTerrain").visible = true
		_set_camera(9.0, Vector3(-15.0, 0.0, -7.2))
	if _frame == 90:
		_capture("flock")
		return true
	return false

func _stage() -> void:
	_main.set_process(false)
	_main.hud.visible = false
	_main.get_node("SectionTerrain").visible = false
	var player: Node3D = _main.get_node("Players").get_child(0)
	player.global_position = Vector3(12.0, 0.1, -8.0)
	_prototype = load("res://scenes/section_terrain/section_terrain.gd").new()
	_prototype.call("_sheep", Vector3.ZERO, -0.25, "ewe", 0, not _blockout)
	_prototype.call("_flush")
	_prototype.set("_built", root.get_node("GameState").get("current_section_index"))
	_main.add_child(_prototype)
	_prototype.global_position = Vector3(13.65, 0.0, -8.2)
	_focus = (player.global_position + _prototype.global_position) * 0.5
	_set_camera(_main.CAM_SIZE, _focus)

func _set_camera(size: float, target: Vector3) -> void:
	var cam: Camera3D = _main.get_node("Camera3D")
	cam.size = size
	cam.global_position = target + cam.global_basis.z * _main.CAM_OFFSET.length()

func _capture(name: String) -> void:
	var stage := "blockout" if _blockout else "fleece"
	root.get_texture().get_image().save_png("%s/sheep_%s_%s.png" % [_output, stage, name])
