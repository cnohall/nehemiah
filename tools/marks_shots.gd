extends SceneTree

# Crew marks (CrewMark: a shape per slot over each head and on the HUD cards) and the close
# call (DayDirector._close_call) on screen:
#   Godot --path . --script res://tools/marks_shots.gd -- --nostory --day=8 <out_dir>
# Not headless — needs the GPU. Three bots join; the crew stands in a row by the yard,
# then the stretch closes with a scout at the last piece.

var _out := ""
var _main: Node3D
var _frame := 0
var _t := 0.0
var _state := "wait"
var _at := 0.0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	root.size = Vector2i(1600, 900)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_main.fit_bots(3)
	if _frame == 5:
		_main.director.begin()
	if _frame < 5:
		return false
	_t += delta
	var gs = root.get_node("GameState")
	if _t > 90.0:
		print("marks_shots: timed out in ", _state)
		quit(1)
		return true
	match _state:
		"wait":
			if gs.phase == gs.Phase.WORK:
				_main.get_node("WaveManager").stop()
				_state = "line_up"
				_at = _t
		"line_up":
			# Bots keep wanting to work: hold them in a row each frame
			var crew: Array = _main.get_node("Players").get_children()
			var base: Vector3 = crew[0].global_position if _t - _at < 0.1 else _row_base
			if _t - _at < 0.1:
				_row_base = base
			for i in crew.size():
				var p: Node3D = crew[i]
				p.global_position = base + Vector3(1.6 * i, 0.0, 0.0)
				p.velocity = Vector3.ZERO
			if _t - _at > 2.0:
				_shot("marks")
				_state = "close"
				_at = _t
		"close":
			_close_stretch()
			_state = "after"
			_at = _t
		"after":
			var real := _t - _at
			if real > 0.12 and not _took_close:
				_took_close = true
				_shot("close_call")
			if gs.phase == gs.Phase.DUSK and real > 6.0:
				_shot("close_tally")
				# The reel's own still of the moment (Highlights, kind "close")
				var kept := false
				for s: Dictionary in _main.get_node("Highlights").shots:
					if s["kind"] == "close":
						(s["tex"] as ImageTexture).get_image().save_png("%s/close_reel.png" % _out)
						print("shot close_reel: ", s["caption"])
						kept = true
				quit(0 if kept else 1)
				return true
	return false

var _row_base := Vector3.ZERO
var _took_close := false

func _close_stretch() -> void:
	var d = _main.director
	var last: Node3D = d._units[d._units.size() - 1][0]
	var enemies := _main.get_node("Enemies")
	_main.get_node("WaveManager")._do_spawn(0, last.global_position + Vector3(0.0, 0.1, -1.4))
	enemies.get_child(enemies.get_child_count() - 1)._wrecker = false   # a runner for the gap
	var parts: Array = []
	for unit: Array in d._units:
		parts.append_array(unit)
	parts.erase(last)
	parts.append(last)
	for part in parts:
		if "stage" in part:
			part.stage = 3
		elif "finished" in part:
			part.finished = true

func _shot(tag: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, tag])
	print("shot ", tag)
