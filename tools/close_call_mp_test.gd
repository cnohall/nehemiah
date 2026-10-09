extends SceneTree

# The close call over LAN (DayDirector._close_call), one host and one client, two processes:
#   Godot --headless --path . --script res://tools/close_call_mp_test.gd -- --nostory --day=8 --host
#   Godot --headless --path . --script res://tools/close_call_mp_test.gd -- --nostory --day=8 --client
# The host closes the stretch with a runner at the last piece. The client must get the tally
# with "close" = "gap", hold its breath (slow motion, the low-pass) and keep it in its
# chronicle. Exit code 0 = all passed.

var _mode := "host"
var _main: Node
var _gs: Node
var _t := 0.0
var _mark := 0.0
var _frame := 0
var _state := "start"
var _fails := 0
var _stats := {}

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--host" or a == "--client":
			_mode = a.trim_prefix("--")

func _process(delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_t += delta
	if _t > 70.0:
		_check(false, "timed out in " + _state)
		return _finish()
	var nm := root.get_node("NetworkManager")
	_gs = root.get_node("GameState")
	match _state:
		"start":
			if _mode == "host":
				nm.host(nm.TEST_PORT, 1)
			else:
				nm.join("127.0.0.1", nm.TEST_PORT)
			_state = "connect"
		"connect":
			var up: bool = _mode == "host" or (root.multiplayer.multiplayer_peer.get_connection_status() \
				== MultiplayerPeer.CONNECTION_CONNECTED and root.multiplayer.get_unique_id() != 1)
			if up:
				_main = load("res://scenes/main/main.tscn").instantiate()
				root.add_child(_main)
				current_scene = _main
				_main.director.day_tallied.connect(func(s: Dictionary): _stats = s)
				_state = "wait"
		"wait":
			if _mode == "host":
				var peers: Array = root.multiplayer.get_peers()
				if not peers.is_empty() and nm.is_peer_ready(peers[0]):
					_main.director.begin()
					_state = "work"
			elif _main._roster_in and _main.players_root.has_node("1"):
				_state = "work"
		"work":
			if _gs.phase != _gs.Phase.WORK:
				return false
			if _mode == "host":
				_close_stretch()
				_mark = _t
				_state = "linger"
			else:
				_state = "client_tally"
		"linger":
			if _t - _mark > 8.0:
				return _finish()
		"client_tally":
			if _stats.is_empty():
				return false
			_check(_stats.get("close", "") == "gap", "client: the tally says gap (%s)" % _stats.get("close", "none"))
			_check(Engine.time_scale < 0.2, "client: slow motion (%.2f)" % Engine.time_scale)
			_check(_has_low_pass(), "client: the mix drops behind a low-pass")
			_check(_gs.chronicle[_gs.current_section_index].get("close", false), "client: the chronicle keeps it")
			return _finish()
	return false

func _close_stretch() -> void:
	_main.get_node("WaveManager").stop()
	var enemies := _main.get_node("Enemies")
	for e in enemies.get_children():
		e.free()
	var d = _main.director
	var last: Node3D = d._units[d._units.size() - 1][0]
	_main.get_node("WaveManager")._do_spawn(0, last.global_position + Vector3(0.0, 0.1, -1.6))
	enemies.get_child(enemies.get_child_count() - 1)._wrecker = false
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
	_check(_stats.get("close", "") == "gap", "host: the tally says gap (%s)" % _stats.get("close", "none"))

func _has_low_pass() -> bool:
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) is AudioEffectLowPassFilter:
			return true
	return false

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1

func _finish() -> bool:
	print("close_call_mp_test (%s): %s" % [_mode, "all passed" if _fails == 0 else "%d failed" % _fails])
	Engine.time_scale = 1.0
	quit(1 if _fails else 0)
	return true
