extends SceneTree

# The load cover's maps (LoadCover.go with a section): the circuit map of Jerusalem with
# the stretches before each one standing and that one lit, saved once per section to
# assets/load/map_<i>.jpg. Rendering the live map during a frozen scene load can't work
# (the main thread stalls) and cost frames when it sat hidden, so the cover shows a still.
#   powershell -File tools/load_maps.ps1     (renders all 12, then reimports)
#   Godot --path . --script res://tools/load_maps.gd -- [section ...]
# Not headless: needs the GPU. Re-run after changes to CircuitDiorama or map_look.gdshader.

const SIZE := Vector2i(1600, 900)
const WAIT := 3.2          # s for the camera to ease onto the stretch
const OUT := "res://assets/load/map_%d.jpg"
const QUALITY := 0.82

var _only: Array[int] = []
var _vp: SubViewport
var _map: Control
var _k := -1
var _t := 0.0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			_only.append(int(a))
	if _only.is_empty():
		_only.assign(range(12))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/load"))

func _process(delta: float) -> bool:
	if _vp == null:
		_next()
		return false
	_t += delta
	if _t < WAIT:
		return false
	var img := _vp.get_texture().get_image()
	var path := OUT % _only[_k]
	var err := img.save_jpg(ProjectSettings.globalize_path(path), QUALITY)
	print("saved %s (%s)" % [path, error_string(err)])
	_vp.queue_free()
	if _k + 1 >= _only.size():
		return true
	_next()
	return false

func _next() -> void:
	_k += 1
	_t = 0.0
	_vp = SubViewport.new()
	_vp.size = SIZE
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	_map = load("res://scenes/story/circuit_map.gd").new()
	_map.quiet = true          # names go on the cover as live (translated) text
	_map.section = _only[_k]
	_map.size = Vector2(SIZE)
	_vp.add_child(_map)
