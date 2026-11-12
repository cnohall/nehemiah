extends SceneTree

# Stills of the load cover: a stretch's map + verse, and the network wait with its tips.
#   Godot --path . --resolution 1920x1080 --script res://tools/load_cover_shots.gd -- <out_dir> [--lang=ko] [section ...]
# A section of -1 is the wait (painting + tip). Not headless: needs the GPU.

const WAIT := 0.8

var _out := ""
var _shots: Array[int] = []
var _cover: Node
var _k := -1
var _t := 0.0
var _lang := "en"

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lang="):
			_lang = a.trim_prefix("--lang=")
		elif a.is_valid_int():
			_shots.append(int(a))
		elif not a.begins_with("--"):
			_out = a
	if _shots.is_empty():
		_shots = [0, 1, 11, -1]

func _process(delta: float) -> bool:
	if _cover == null:
		TranslationServer.set_locale(_lang)
		_cover = root.get_node("LoadCover")
		_next()
		return false
	_t += delta
	if _t < WAIT:
		return false
	var name := "wait" if _shots[_k] < 0 else "section_%d" % _shots[_k]
	var path := _out.path_join("cover_%s_%s.png" % [_lang, name])
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
	if _k + 1 >= _shots.size():
		return true
	_next()
	return false

func _next() -> void:
	_k += 1
	_t = 0.0
	var s := _shots[_k]
	if s < 0:
		_cover.wait("Opening the gates", TranslationServer.translate("Creating Steam lobby…"), func(): pass)
	else:
		# go() without the scene change: what it puts up before the load
		_cover._stop_tips()
		_cover._cancel_btn.hide()
		_cover._set_scene(s)
		var gs := root.get_node("GameState")
		_cover._set_text(gs.SECTIONS[s]["name"], gs.short_ref(load("res://scenes/story/story_data.gd").VERSES[s][1]))
		_cover._root.modulate.a = 1.0
		_cover._root.show()
