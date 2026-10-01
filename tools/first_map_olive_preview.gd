extends SceneTree

# Capture the Sheep Gate map with its normal close-follow camera framing.
#   Godot --path . --script res://tools/first_map_olive_preview.gd -- <output.png>

var _main
var _output := ""
var _frame := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_output = args[0] if not args.is_empty() else "res://art/vegetation/first_map_olive.png"
	root.size = Vector2i(1920, 1080)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_main.set_process(false)
		var camera: Camera3D = _main.get_node("Camera3D")
		camera.size = _main.CAM_SIZE
		var focus := Vector3(-19, 0, -7)
		camera.global_position = focus + _main.CAM_OFFSET
		camera.look_at(focus, Vector3.UP)
		_main.get_node("PostFX").hide()
		if _main.hud != null:
			_main.hud.hide()
		if _main.story != null:
			_main.story.hide()
	if _frame < 12:
		return false
	var image := root.get_texture().get_image()
	if image == null:
		push_error("Renderer did not provide a viewport image")
	else:
		image.save_png(_output)
		print("Saved first map olive preview: ", _output)
	return true
