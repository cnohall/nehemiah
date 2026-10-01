extends SceneTree

# Run with Godot's windowed renderer. Uses the main scene's actual camera, sun,
# environment, ground material and CharacterRig at the normal gameplay zoom.
#   Godot --path . --script res://tools/old_olive_preview.gd -- <output.png>

var _output := ""
var _frame := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_output = args[0] if not args.is_empty() else "res://tmp/old_olive_preview.png"
	root.size = Vector2i(1920, 1080)
	var stage := Node3D.new()
	root.add_child(stage)
	var source: Node3D = load("res://scenes/main/main.tscn").instantiate()
	for path in ["Camera3D", "Sun", "WorldEnvironment", "Floor/Mesh"]:
		stage.add_child(source.get_node(path).duplicate())
	source.free()
	var tree := OldOlive.new()
	tree.position = Vector3(-1.5, 0, 0)
	tree.rotation.y = PI / 4.0
	stage.add_child(tree)
	var player := CharacterRig.new()
	player.position = Vector3(2.3, 0, -0.6)
	stage.add_child(player)
	player.setup(CharacterRig.worker_look(0, Color(0.24, 0.42, 0.80)))
	player.play("idle_down")

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 8:
		return false
	var shot := root.get_texture().get_image()
	if shot == null:
		push_error("The selected renderer did not supply a viewport image")
	else:
		shot.save_png(_output)
		print("Saved old olive preview: ", _output)
	return true
