extends SceneTree

# NetworkManager's version check (NetFingerprint via SceneMultiplayer auth), over LAN:
#   Godot --headless --path . --script res://tools/version_check_test.gd -- --host
#   Godot --headless --path . --script res://tools/version_check_test.gd -- --client=same
#   Godot --headless --path . --script res://tools/version_check_test.gd -- --client=other --net-salt=x
#   Godot --headless --path . --script res://tools/version_check_test.gd -- --client=legacy
# same: admitted. other: refused at once, with the version message, never admitted.
# legacy: a build from before the check (sends no auth) is dropped by the host's timeout.
# The host serves the three clients one after another and expects exactly one admission.
# Exit code 0 = passed.

const TIMEOUT := 36.0   # host's serving window

var _mode := ""
var _client := ""
var _t := 0.0
var _frame := 0
var _started := false
var _admitted := 0
var _failed := 0
var _joined := 0     # client: lobby_joined(true)
var _refused := 0    # client: lobby_joined(false)
var _error := ""
var _dropped := false   # legacy client: the host hung up

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--host":
			_mode = "host"
		elif a.begins_with("--client="):
			_mode = "client"
			_client = a.trim_prefix("--client=")

func _process(delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_t += delta
	var nm: Node = root.get_node("NetworkManager")
	if not _started:
		_started = true
		if _mode == "host":
			nm.peer_connected.connect(func(_id): _admitted += 1)
			(root.multiplayer as SceneMultiplayer).peer_authentication_failed.connect(func(_id): _failed += 1)
			nm.host(nm.TEST_PORT, 1)
		else:
			if _client == "legacy":
				(root.multiplayer as SceneMultiplayer).auth_callback = Callable()   # as an old build
				root.multiplayer.server_disconnected.connect(func(): _dropped = true)
			nm.lobby_joined.connect(func(ok: bool):
				if ok: _joined += 1
				else: _refused += 1
				_error = nm.join_error)
			nm.join("127.0.0.1", nm.TEST_PORT)
		return false
	if _mode == "host":
		# Serve for a fixed window (the legacy client needs AUTH_TIMEOUT to be dropped)
		if _t > TIMEOUT:
			return _finish([
				[_admitted == 1, "host: only the same build admitted (%d)" % _admitted],
				[_failed >= 1, "host: the legacy build timed out of auth (%d)" % _failed],
				[root.multiplayer.get_peers().is_empty(), "host: nobody left connected"],
			])
		return false
	match _client:
		"same":
			if _joined > 0 or _refused > 0 or _t > 10.0:
				return _finish([[_joined == 1 and _refused == 0, "same build: admitted"]])
		"other":
			if _joined > 0 or _refused > 0 or _t > 10.0:
				return _finish([
					[_refused == 1 and _joined == 0, "other build: refused"],
					[_error == nm.VERSION_MISMATCH, "other build: told why ('%s')" % _error],
					[_t < 5.0, "other build: at once (%.1f s)" % _t],
				])
		"legacy":
			# An old build would be admitted locally at once; what matters is the host drops it
			if _dropped or _t > nm.AUTH_TIMEOUT + 8.0:
				return _finish([[_dropped, "legacy build: dropped by the host (%.1f s)" % _t]])
	return false

func _finish(checks: Array) -> bool:
	var ok := true
	for c: Array in checks:
		print(("PASS " if c[0] else "FAIL ") + c[1])
		ok = ok and c[0]
	print("version_check_test (%s%s): %s" % [_mode, "" if _client.is_empty() else " " + _client, "passed" if ok else "FAILED"])
	quit(0 if ok else 1)
	return true
