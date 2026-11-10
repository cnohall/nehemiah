extends SceneTree

# Post pass A/B on one still frame: grabs the game (no PostFX), then draws that image through
# the scene's current PostFX shader and through <candidate.gdshader>, saves both and the
# difference, and prints the per-channel error in 8-bit steps.
#   Godot --path . --script res://tools/postfx_check.gd -- --nostory <out_dir> <candidate.gdshader>
var _out := "res://build/postfx"
var _candidate := "res://assets/shaders/post_fx.gdshader"
var _main: Node3D
var _frame := 0
var _raw: Image
var _old_code := ""
var _rect: ColorRect
var _shots: Array[Image] = []

func _initialize() -> void:
	var rest: Array = []
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			rest.append(a)
	if rest.size() > 0:
		_out = rest[0]
	if rest.size() > 1:
		_candidate = rest[1]
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(1920, 1080)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_main.director.begin()
	if _frame == 40:
		var vig: ColorRect = _main.get_node("PostFX/Vignette")
		_old_code = (vig.material as ShaderMaterial).shader.code
		_main.get_node("PostFX").hide()
	if _frame == 44:
		_raw = root.get_texture().get_image()
		_raw.save_png("%s/raw.png" % _out)
		_main.queue_free()
		var layer := CanvasLayer.new()
		root.add_child(layer)
		var still := TextureRect.new()
		still.texture = ImageTexture.create_from_image(_raw)
		still.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.add_child(still)
		_rect = ColorRect.new()
		_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_rect.material = _material(_old_code)
		layer.add_child(_rect)
	if _frame == 48:
		_shots.append(root.get_texture().get_image())
		var sh: Shader = load(_candidate)
		_rect.material = _material(sh.code)
	if _frame == 52:
		_shots.append(root.get_texture().get_image())
		_report()
		return true
	return false

func _material(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m

func _report() -> void:
	var a := _shots[0]
	var b := _shots[1]
	a.save_png("%s/old.png" % _out)
	b.save_png("%s/new.png" % _out)
	var diff := Image.create(a.get_width(), a.get_height(), false, Image.FORMAT_RGB8)
	var total := 0.0
	var worst := 0.0
	var over2 := 0
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var e := maxf(absf(ca.r - cb.r), maxf(absf(ca.g - cb.g), absf(ca.b - cb.b))) * 255.0
			total += e
			worst = maxf(worst, e)
			if e > 2.0:
				over2 += 1
			diff.set_pixel(x, y, Color.WHITE * clampf(e / 16.0, 0.0, 1.0))
	diff.save_png("%s/diff.png" % _out)
	var n := float(a.get_width() * a.get_height())
	print("postfx A/B: mean %.3f, max %.1f (8-bit steps), %.3f%% of pixels off by more than 2" % [total / n, worst, over2 / n * 100.0])
