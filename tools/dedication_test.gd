extends SceneTree

# The dedication walk (Neh. 12:31-43) in Explore Jerusalem: stand at the Valley Gate, talk to a
# company's leader, then follow it round the ring to the temple, where both companies meet.
#   Godot --headless --path . --script res://tools/dedication_test.gd -- --unlock-all [--choir=0|1]
# Add --write-movie <dir>/f.png --fixed-fps 10 for frames (not headless).

var _main: Node3D
var _fest
var _t := 0.0
var _choir := 1
var _started := false
var _fails := 0
var _districts := []
var _last_d := -1
var _shots := ""
var _shot_at := {}   # seconds → name

func _ok(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		_fails += 1

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--choir="):
			_choir = a.trim_prefix("--choir=").to_int()
		if a.begins_with("--shots="):
			_shots = a.trim_prefix("--shots=")
	root.size = Vector2i(1920, 1080)
	root.get_node("GameState").festival = true
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	Engine.time_scale = 3.0

func _me() -> Node3D:
	return _main.get_node("Players").get_child(0)

func _process(delta: float) -> bool:
	_t += delta / Engine.time_scale
	if _fest == null:
		for c in _main.get_children():
			if "_dedication" in c:
				_fest = c
		return false
	if _fest._district < 0 or _fest._dedication == null:
		return false
	var ded = _fest._dedication
	if _fest._district != _last_d:
		_last_d = _fest._district
		_districts.append(_last_d)
		_shot_at[_t + 1.2] = "d%d_%d" % [_districts.size(), _last_d]
	for k in _shot_at.keys():
		if _t >= k:
			if _shots != "":
				root.get_texture().get_image().save_png("%s/%s.png" % [_shots, _shot_at[k]])
			_shot_at.erase(k)
	if ded._finale and not _shot_at.has(-1.0) and ded._finale_t > 3.0 and _shots != "":
		_shot_at[-1.0] = "finale"
		root.get_texture().get_image().save_png("%s/finale.png" % _shots)
	if not _started:
		if _fest._district != ded.START:
			_fest._enter(ded.START)
			return false
		_started = true
		_ok(ded._staged.size() == 2, "both companies stand at the Valley Gate")
		var lead = ded._staged[_choir][0]
		_me().global_position = lead.global_position + Vector3(0, 0, 2.5)
		lead.talk(_me())
		_ok(ded.active and ded.choir == _choir, "talking to a leader starts the walk")
		return false
	if ded.done:
		_ok(true, "walk finished")
		_ok(_districts.slice(_districts.find(ded.START)) == ded.ROUTES[_choir], "visited %s" % [_districts])
		_ok(_fest._rows["dedication"][0].done, "journal row ticked")
		print("DONE fails=", _fails)
		quit(_fails)
		return true
	if _t > 400.0:
		_ok(false, "timed out in district %d step %d" % [_fest._district, ded.step])
		print("DONE fails=", _fails)
		quit(_fails)
		return true
	# Autopilot: stay just behind the leader; at a stretch's end, walk off it
	var lead2 = ded._leader
	if lead2 != null and is_instance_valid(lead2):
		var w: float = ded.way(_choir)
		if ded._at_end and ded.step < ded.ROUTES[_choir].size() - 1:
			_me().global_position = Vector3(w * (_fest.EDGE_X + 1.0), 0.1, 7.0)
		else:
			_me().global_position = lead2.global_position - ded._heading * 3.0 + Vector3(0, 0, 0.8)
	return false
