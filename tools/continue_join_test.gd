extends SceneTree

# Continue hosted over LAN, a second player joins (GDD §5.11): one `--headless ... -- --host`
# plus one `... -- --client`, in separate processes:
#   Godot --headless --path . --script res://tools/continue_join_test.gd -- --host
#   Godot --headless --path . --script res://tools/continue_join_test.gd -- --client
# The host saves a run at day 13, picks it up the way the title's Continue does and opens
# the session; the client must get in (roster received, ready on the host) on day 13.
# The host puts the player's own progress.cfg back afterwards. Exit code 0 = all passed.

var _mode := "host"
var _main: Node
var _gs: Node
var _t := 0.0
var _mark := 0.0
var _frame := 0
var _state := "start"
var _fails := 0
var _had := false
var _backup: PackedByteArray

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
	if _t > 40.0:
		_check(false, "timed out in " + _state)
		return _finish()
	var nm := root.get_node("NetworkManager")
	_gs = root.get_node("GameState")
	match _state:
		"start":
			if _mode == "host":
				_had = FileAccess.file_exists(_gs.PROGRESS_PATH)
				if _had:
					_backup = FileAccess.get_file_as_bytes(_gs.PROGRESS_PATH)
				_gs.reset()
				_gs.section_marks[0] = 7
				_gs._save_campaign(13)
				_gs.restart_day = 13
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
					_check(_gs.current_day == 13, "host: continuing on day 13 (is %d)" % _gs.current_day)
					_check(_main.players_root.has_node(str(peers[0])), "host: the client is in the crew")
					_state = "linger"
					_mark = _t
			elif _main._roster_in and _main.players_root.has_node("1"):
				# The state follows the roster a beat later
				if _t - _mark > 2.0:
					_check(_gs.current_day == 13, "client: on day 13 (is %d)" % _gs.current_day)
					_check(_gs.section_marks[0] == 7, "client: marks came over")
					return _finish()
		"linger":
			if _t - _mark > 5.0:
				return _finish()
	return false

func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1

func _finish() -> bool:
	if _mode == "host":
		if _had:
			var f := FileAccess.open(_gs.PROGRESS_PATH, FileAccess.WRITE)
			f.store_buffer(_backup)
			f.close()
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(_gs.PROGRESS_PATH))
	print("RESULT: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)
	return true
