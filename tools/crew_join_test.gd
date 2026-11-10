extends SceneTree

# Three people over LAN: does every client see every person who joined? Three processes:
#   Godot --headless --path . --script res://tools/crew_join_test.gd -- --host
#   Godot --headless --path . --script res://tools/crew_join_test.gd -- --a
#   Godot --headless --path . --script res://tools/crew_join_test.gd -- --b     (start ~25 s after A)
# B must connect after A's Main is up (headless Main takes ~9 s to load): earlier, A's
# own roster request already lists B and the test proves nothing — check the timeline.
# Client A stops listening for "a peer connected" once its Main is up, the way a missed
# relay notice looks (Steam), so it only sees B if the host tells it. B arrives late.
# Then B leaves: A must drop B. Exit code 0 = all passed.

var _mode := "host"
var _main: Node
var _t := 0.0
var _mark := 0.0
var _frame := 0
var _state := "start"
var _fails := 0

func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	for a in OS.get_cmdline_user_args():
		if a in ["--host", "--a", "--b"]:
			_mode = a.trim_prefix("--")

func _people() -> int:
	return _main.players_root.get_children().filter(func(p): return not p.is_bot()).size()

func _process(delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_t += delta
	if _t > 90.0:
		_check(false, "%s: timed out in %s" % [_mode, _state])
		return _finish()
	var nm := root.get_node("NetworkManager")
	match _state:
		"start":
			if _mode == "host":
				nm.host(nm.TEST_PORT, 1)
			else:
				nm.join("127.0.0.1", nm.TEST_PORT)
			_state = "connect"
		"connect":
			var up: bool = _mode == "host" or (root.multiplayer.multiplayer_peer.get_connection_status() \
				== MultiplayerPeer.CONNECTION_CONNECTED and root.multiplayer.get_unique_id() != 1 and 1 in root.multiplayer.get_peers())
			if up:
				_main = load("res://scenes/main/main.tscn").instantiate()
				root.add_child(_main)
				current_scene = _main
				if _mode == "a":
					nm.peer_connected.disconnect(_main._on_peer_connected)
				print("%s (%d): Main up at %s" % [_mode, root.multiplayer.get_unique_id(), _clock()])
				_main.players_root.child_entered_tree.connect(func(n): print("%s: + %s at %s" % [_mode, n.name, _clock()]))
				_main.players_root.child_exiting_tree.connect(func(n): print("%s: - %s at %s" % [_mode, n.name, _clock()]))
				_main.tree_exiting.connect(func(): print("%s: Main gone at %s" % [_mode, _clock()]))
				_mark = _t
				_state = "wait"
		"wait":
			if _people() == 3:
				print("%s: sees all 3 people" % _mode)
				_mark = _t
				_state = "leave" if _mode == "b" else "after"
		"leave":
			# B goes after a beat; the others should drop it
			if _t - _mark > 3.0:
				root.multiplayer.multiplayer_peer.close()
				return _finish()
		"after":
			if _people() == 2:
				print("%s: B gone" % _mode)
				if _mode == "host":
					_mark = _t
					_state = "linger"   # keep the session up until A has checked too
				else:
					return _finish()
		"linger":
			if _t - _mark > 4.0:
				return _finish()
	return false

func _clock() -> String:
	return "%.1f" % fmod(Time.get_unix_time_from_system(), 100.0)

func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1

func _finish() -> bool:
	print("%s done, %d failed" % [_mode, _fails])
	quit(1 if _fails > 0 else 0)
	return true
