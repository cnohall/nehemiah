extends SceneTree

# End screen → play again (GDD §5.7), offline, windowed (the reel needs a renderer):
#   Godot --path . --script res://tools/again_test.gd -- --nostory --day=10
# - a finished day leaves a still in the highlight reel
# - losing shows the end screen with the reel and a "Try the stretch again" button
# - voting (the host decides alone) reloads the game at the lost stretch's first day
# Exit code 0 = every check passed.

var _main: Node
var _gs: Node
var _frame := 0
var _t := 0.0
var _mark := 0.0
var _state := "start"
var _fails := 0
var _expect_day := 0

# Network: one `--headless ... -- --nostory --host` plus one `... -- --nostory --client`:
# the host loses, votes, and both reload; the client must be back in (roster received,
# ready on the host) in the new scene.
var _mode := "offline"

func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	for a in OS.get_cmdline_user_args():
		if a == "--host" or a == "--client":
			_mode = a.trim_prefix("--")
	if _mode == "offline":
		_main = load("res://scenes/main/main.tscn").instantiate()
		root.add_child(_main)
		current_scene = _main

func _process(delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_t += delta
	if _t > 60.0:
		_check(false, "timed out in " + _state)
		return _finish()
	if _mode != "offline":
		return _network()
	match _state:
		"start":
			_gs = root.get_node("GameState")
			_main.director.begin()
			_state = "work"
		"work":
			if _gs.phase == _gs.Phase.STORY:
				_main.director.force_ready()
			elif _gs.phase == _gs.Phase.WORK:
				_main.get_node("WaveManager").stop()
				_main.director._end_day()
				_mark = _t
				_state = "dusk"
		"dusk":
			if _t - _mark > 2.5:
				var shots: Array = _main.get_node("Highlights").shots
				_check(shots.size() > 0, "the day's end is in the reel (%d stills)" % shots.size())
				_expect_day = _gs.get_current_section()["days"][0]
				_gs.lose("overrun")
				_mark = _t
				_state = "end"
		"end":
			if _t - _mark > 1.5:
				var vb: Control = _main.hud.get_node("Root/EndScreen/Center/VBox")
				_check(_main.hud.end_screen.visible, "end screen up")
				# (phones hang the reel beside the verdict rather than in the column)
				_check(vb.get_node_or_null("Reel") != null or _main.hud.get("_reel") != null, "highlight reel on the end screen")
				var first: Button = vb.get_node("Buttons").get_child(0)
				_check(first.text == "Try the stretch again", "first button: %s" % first.text)
				var out := Array(OS.get_cmdline_user_args()).filter(func(a): return not a.begins_with("--"))
				if not out.is_empty():
					root.get_texture().get_image().save_png(out[0] + "/end.png")
				first.pressed.emit()
				_mark = _t
				_state = "reload"
		"reload":
			if current_scene != null and current_scene != _main and is_instance_valid(current_scene) \
					and current_scene.is_node_ready():
				_check(_gs.phase == _gs.Phase.GATHER, "back to gathering (phase %d)" % _gs.phase)
				_check(_gs.current_day == _expect_day, "starts on day %d (want %d)" % [_gs.current_day, _expect_day])
				return _finish()
	return false

func _network() -> bool:
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
				_state = "wait_crew"
		"wait_crew":
			if _mode == "client":
				if current_scene != _main and current_scene != null and current_scene.is_node_ready():
					_main = current_scene
					_mark = _t
					_state = "back_in"
				return false
			var peers: Array = root.multiplayer.get_peers()
			if not peers.is_empty() and nm.is_peer_ready(peers[0]) and _gs.phase == _gs.Phase.GATHER:
				_gs.lose("overrun")
				_mark = _t
				_state = "vote"
		"vote":
			if _t - _mark > 1.0:
				_main.director.cast_vote("again")
				_state = "reloaded"
		"reloaded":
			if current_scene != _main and current_scene != null and current_scene.is_node_ready():
				_main = current_scene
				_mark = _t
				_state = "back_in"
		"back_in":
			if _mode == "host":
				var peers: Array = root.multiplayer.get_peers()
				if not peers.is_empty() and nm.is_peer_ready(peers[0]):
					_check(_gs.phase == _gs.Phase.GATHER, "host: new run gathering")
					_check(_main.players_root.has_node(str(peers[0])), "host: the client is back in the crew")
					# Stay up a moment so the client can check too
					_state = "linger"
					_mark = _t
			else:
				if _main._roster_in and _main.players_root.has_node("1"):
					_check(_t - _mark < 10.0, "client: back in after the reload (%.1f s)" % (_t - _mark))
					return _finish()
		"linger":
			if _t - _mark > 4.0:
				return _finish()
	return false

func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1

func _finish() -> bool:
	print("again_test: %d failed" % _fails)
	quit(1 if _fails else 0)
	return true
