extends SceneTree

# The lie of the land (Terrain): three views of a section — as played, looking up the city's
# hill, and pulled right back.
#   Godot --path . --script res://tools/terrain_shots.gd -- --nostory --day=N <out_dir>
# Saves <out_dir>/terrain_<section>_{play,city,wide}.png with the HUD hidden.

const VIEWS := {
	"play": [Vector3(0, 0, 2), 18.0],
	"city": [Vector3(0, 6, 28), 26.0],
	"wide": [Vector3(0, 0, 0), 70.0],
	"foe":  [Vector3(0, -4, -26), 30.0],
	"street": [Vector3(-4, 0, 23), 9.0],   # where the main street is barred (FLAT_CITY)
	"stair":  [Vector3(-4, 2, 28), 9.0],    # the main street climbing the terraces
}

var _out := ""
var _main: Node3D
var _frame := 0
var _t := 0.0
var _view := 0
var _wait := 0

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
		_main.director.begin()
	if _frame < 3:
		return false
	_t += delta
	var gs = root.get_node("GameState")
	if gs.phase != gs.Phase.WORK or _t < 3.0:
		return _t > 60.0
	_main.set_process(false)
	_main.set_physics_process(false)
	_main.hud.hide()
	var names := VIEWS.keys()
	if _view >= names.size():
		return true
	var cam: Camera3D = _main.get_node("Camera3D")
	var v: Array = VIEWS[names[_view]]
	cam.size = v[1]
	cam.global_position = v[0] + _main._cam_offset() * (3.0 if v[1] > 40.0 else 1.0)
	cam.look_at(v[0], Vector3.UP)
	if _wait < 4:
		_wait += 1
		return false
	var path := "%s/terrain_%02d_%s.png" % [_out, gs.current_section_index + 1, names[_view]]
	root.get_texture().get_image().save_png(path)
	print("terrain_shots: saved ", path)
	_view += 1
	_wait = 0
	return false
