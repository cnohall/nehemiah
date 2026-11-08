extends SceneTree

# NetSmooth over LAN, one host and one client, two processes:
#   Godot --headless --path . --max-fps 60 --script res://tools/net_smooth_mp_test.gd -- --nostory --day=8 --host
#   Godot --headless --path . --max-fps 60 --script res://tools/net_smooth_mp_test.gd -- --nostory --day=8 --client
# Each side runs its own worker round a circle at a steady 5 m/s and watches the other's:
# per frame, how far the remote figure moved against how far it should have. The host also
# sets a raider loose; the client must draw it through a NetSmooth too. Exit code 0 = all passed.

const SPEED := 5.0
const RADIUS := 4.0
const WATCH := 6.0

var _mode := "host"
var _main: Node
var _gs: Node
var _t := 0.0
var _mark := 0.0
var _frame := 0
var _state := "start"
var _fails := 0
var _mine: Node3D
var _theirs: Node3D
var _centre := Vector3.ZERO
var _last := Vector3.ZERO
var _frames := 0
var _bad := 0
var _enemy_seen := false

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--host" or a == "--client":
			_mode = a.trim_prefix("--")

func _process(delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_t += delta
	if _t > 60.0:
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
			var me := str(root.multiplayer.get_unique_id())
			var other := "1" if _mode == "client" else str(root.multiplayer.get_peers()[0])
			if not _main.players_root.has_node(me) or not _main.players_root.has_node(other):
				return false
			_mine = _main.players_root.get_node(me)
			_theirs = _main.players_root.get_node(other)
			_centre = _mine.global_position
			if _mode == "host":
				var wm := _main.get_node("WaveManager")
				wm.stop()
				wm._do_spawn(2, _centre + Vector3(6.0, 0.1, -8.0))
			_mark = _t
			_state = "run"
		"run":
			var a := (_t - _mark) * SPEED / RADIUS
			_mine.global_position = _centre + Vector3(cos(a), 0.0, sin(a)) * RADIUS
			if _mode == "client" and not _enemy_seen:
				for e in _main.get_node("Enemies").get_children():
					if e.has_node("NetSmooth"):
						_enemy_seen = true
			if _t - _mark > WATCH + 2.0:
				return _finish()
	return false

func _init() -> void:
	process_frame.connect(_on_frame)

# After every node's _process: the remote figure has been placed for this frame
func _on_frame() -> void:
	if _state != "run" or _theirs == null or not is_instance_valid(_theirs):
		return
	var p := _theirs.global_position
	p.y = 0.0
	var delta := root.get_process_delta_time()
	if _t - _mark > 1.5 and delta > 0.0:
		_frames += 1
		var ratio := p.distance_to(_last) / (SPEED * delta)
		if ratio < 0.4 or ratio > 2.0:
			_bad += 1
	_last = p

func _finish() -> bool:
	var pct := 100.0 * _bad / maxf(1, _frames)
	print("%s: watched %d frames of the other worker, %.1f%% off-pace" % [_mode, _frames, pct])
	_check(_frames > 150, "%s: enough frames watched" % _mode)
	_check(_theirs != null and _theirs.has_node("NetSmooth"), "%s: the other worker is smoothed" % _mode)
	_check(pct < 5.0, "%s: under 5%% of frames stall or jump (%.1f%%)" % [_mode, pct])
	if _mode == "client":
		_check(_enemy_seen, "client: the raider is smoothed")
	print("net_smooth_mp_test (%s): %s" % [_mode, "all passed" if _fails == 0 else "%d failed" % _fails])
	quit(1 if _fails else 0)
	return true

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1
