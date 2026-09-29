extends SceneTree

# Trailer footage: one beat of real play per run, recorded by Godot's movie writer.
#   Godot --path . --write-movie <dir>/<beat>.avi --fixed-fps 30 --script res://tools/trailer_shots.gd
#         -- --nostory --day=N [--secs=40] [--zoom=16] [--hud] [--at=X,Z] [--push=2]
# A full crew of four Master-builder bots (the host's own worker gets a brain too) plays
# the day; the camera frames the crew's middle, drifting slowly in by --push metres of
# ortho size over the clip. --at pins the camera to a world point instead. --hud keeps the
# HUD and the usual follow camera. The Music bus is muted: tools/trailer.ps1 lays one
# track under the whole cut; the game's SFX stay in the recording.
# World tags, target marks and pips are hidden as on the title screen (GameState.attract,
# set once the day has begun); --hud shows them.
# Prints "frame N: …" at each phase change and every tenth of the wall, for trimming.

const FPS := 30.0
const CAM_SMOOTH := 0.8
const WALL_LEAD := Vector3(0.0, 0.0, -3.0)   # frame a little toward the wall (screen top-right)

var _main: Node3D
var _frame := 0
var _secs := 40.0
var _zoom := 16.0
var _push := 2.0
var _hud := false
var _at := Vector3.INF
var _cam := Vector3.ZERO
var _last_done := -1
var _saved_count := 0
var _saved_skill := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			_secs = a.trim_prefix("--secs=").to_float()
		elif a.begins_with("--zoom="):
			_zoom = a.trim_prefix("--zoom=").to_float()
		elif a.begins_with("--push="):
			_push = a.trim_prefix("--push=").to_float()
		elif a.begins_with("--at="):
			var xz := a.trim_prefix("--at=").split(",")
			_at = Vector3(xz[0].to_float(), 0.0, xz[1].to_float())
		elif a == "--hud":
			_hud = true
	root.size = Vector2i(1920, 1080)
	var settings := root.get_node("Settings")
	_saved_count = settings.bot_count
	_saved_skill = settings.bot_skill
	settings.bot_count = 3
	settings.bot_skill = 2
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	root.get_node("GameState").phase_changed.connect(func(p): print("frame %d: phase %d" % [_frame, p]))

func _process(_delta: float) -> bool:
	_frame += 1
	var gs := root.get_node("GameState")
	if _frame == 2:
		var host: Node = _main.players_root.get_node("1")
		host.brain = load("res://scenes/bot/bot_brain.gd").new(host, 2)
		AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), true)
		if not _hud:
			_main.hud.hide()
			_main.set_process(false)
			_main.camera.size = _zoom
		_main.director.begin()
		if not _hud:
			gs.attract = true
	if _frame < 3:
		return false
	if gs.phase in [gs.Phase.STORY, gs.Phase.DUSK] and _frame % 30 == 0:
		_main.director.force_ready()
	var done := int(10.0 * gs.targets_done / maxf(1.0, gs.targets_total))
	if done != _last_done:
		_last_done = done
		print("frame %d: wall %d/%d" % [_frame, gs.targets_done, gs.targets_total])
	if not _hud:
		_frame_crew()
	if _frame >= int(_secs * FPS):
		return _finish()
	return false

func _frame_crew() -> void:
	var p := _at
	if p == Vector3.INF:
		p = Vector3.ZERO
		var crew: Array = _main.players_root.get_children()
		for w: Node3D in crew:
			p += w.global_position
		p = p / maxf(1.0, crew.size()) + WALL_LEAD
	var desired: Vector3 = Vector3(p.x, 0.0, p.z) + _main.CAM_OFFSET
	if _frame == 3:
		_cam = desired
	_cam = _cam.lerp(desired, minf(1.0, CAM_SMOOTH / FPS))
	_main.camera.global_position = _cam
	# The dusk tween owns the size while it runs; otherwise a slow push in
	if root.get_node("GameState").phase != root.get_node("GameState").Phase.DUSK:
		_main.camera.size = _zoom - _push * clampf(_frame / (_secs * FPS), 0.0, 1.0)

func _finish() -> bool:
	var settings := root.get_node("Settings")
	settings.bot_count = _saved_count
	settings.bot_skill = _saved_skill
	quit()
	return true
