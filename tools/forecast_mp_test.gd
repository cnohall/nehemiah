extends SceneTree

# Experimental forecast + call early over LAN (GDD §5.21): one host, one client, two processes:
#   Godot --headless --path . --script res://tools/forecast_mp_test.gd -- --host
#   Godot --headless --path . --script res://tools/forecast_mp_test.gd -- --client
# Only the HOST turns the toggles on; the client keeps its own off. The client must still
# see the forecast chip (counting down, naming the pack) and get spurred when the host calls
# the wave in. Exit code 0 = all passed.

var _mode := "host"
var _main: Node
var _gs: Node
var _set: Node
var _t := 0.0
var _mark := 0.0
var _frame := 0
var _state := "start"
var _fails := 0

func _initialize() -> void:
	root.size = Vector2i(1280, 720)
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
	_set = root.get_node("Settings")
	match _state:
		"start":
			if _mode == "host":
				_gs.reset()
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
				_mark = _t
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
				_set.exp_forecast = true
				_set.exp_call_early = true
				var wm: Node = _main.get_node("WaveManager")
				wm._surge_left = 0
				wm._forecasted = false
				wm._warned_early = false
				wm._surge_timer = 26.0
				_mark = _t
				_state = "host_forecast"
			else:
				_check(not _set.exp_forecast and not _set.exp_call_early, "client: own toggles are off")
				_mark = _t
				_state = "client_chip"
		"host_forecast":
			var wm: Node = _main.get_node("WaveManager")
			if wm._forecasted and _t - _mark > 6.0:   # let the client see the countdown first
				_check(wm.call_early(), "host: call early accepted")
				_mark = _t
				_state = "linger"
		"linger":
			if _t - _mark > 10.0:
				return _finish()
		"client_chip":
			var chip := _chip()
			if chip != null and chip.visible:
				_check(chip.text.begins_with("Wave in") and chip.text.contains("scout"), "client: chip shows '%s'" % chip.text)
				var n := _secs(chip.text)
				_check(n > 0 and n <= 23, "client: countdown is %d s" % n)
				_mark = _t
				_state = "client_spur"
			elif _t - _mark > 40.0:
				_check(false, "client: chip never showed")
				return _finish()
		"client_spur":
			if Time.get_ticks_msec() < _gs.spur_until:
				_check(true, "client: spurred (work x%.2f)" % _gs.mod("work"))
				_check(_gs.mod("work") > 1.0, "client: work is boosted")
				return _finish()
			if _t - _mark > 25.0:
				_check(false, "client: never spurred")
				return _finish()
	return false

func _chip() -> Label:
	var c := get_nodes_in_group("forecast_chip")
	return c[0] if not c.is_empty() else null

func _secs(text: String) -> int:
	var parts := text.split(" ")
	return int(parts[2]) if parts.size() > 2 else -1

func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1

func _finish() -> bool:
	print("RESULT: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)
	return true
