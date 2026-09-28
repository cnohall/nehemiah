extends SceneTree

# The credits roll on its own, start to finish, then quit. Screenshots every few
# seconds; with --write-movie it records the whole roll as a video.
#   Godot --path . --script res://tools/credits_shots.gd -- <out_dir> [--lang=de]
#   Godot --path . --write-movie build/credits.avi --fixed-fps 30 --script res://tools/credits_shots.gd -- <out_dir> --video
# --video leaves out the in-game "Hold E / Esc" hint. To share it, re-encode with loudness
# brought up to streaming level:
#   ffmpeg -i build/credits.avi -c:v libx264 -crf 18 -pix_fmt yuv420p -af loudnorm=I=-16:TP=-1.5 -c:a aac -b:a 192k build/nehemiah_credits.mp4

const SHOT_EVERY := 6.0

var _out := "."
var _lang := ""
var _video := false
var _roll: CanvasLayer
var _t := 0.0
var _next := 1.5
var _n := 0
var _ended := false

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lang="):
			_lang = a.trim_prefix("--lang=")
		elif a == "--video":
			_video = true
		elif not a.begins_with("--"):
			_out = a

func _process(delta: float) -> bool:
	if _roll == null:
		if not _lang.is_empty():
			TranslationServer.set_locale(_lang)   # after Settings.apply() in the autoloads
		_roll = load("res://scenes/story/credits_roll.gd").new()
		root.add_child(_roll)
		_roll.finished.connect(func(): _ended = true)
		_roll.play()
		if _video:
			_roll._hint.hide()
		return false
	_t += delta
	if _t >= _next:
		root.get_texture().get_image().save_png("%s/credits_%02d.png" % [_out, _n])
		_n += 1
		_next += SHOT_EVERY
	return _ended or _t > 180.0
