extends SceneTree

# The section-complete tally as a joined player sees it, three people over LAN:
#   Godot --headless --path . --script res://tools/tally_mp_shots.gd -- --nostory --day=8 --host
#   Godot --path . --script res://tools/tally_mp_shots.gd -- --nostory --day=8 --a --win=1483x700 --out=<dir>
#   Godot --headless --path . --script res://tools/tally_mp_shots.gd -- --nostory --day=8 --b
# The host waits for both, then closes the stretch. Client A screenshots the tally a few
# times as it settles and checks the ready row sits inside the screen. Exit 0 = passed.

var _mode := "host"
var _out := ""
var _main: Node
var _gs: Node
var _t := 0.0
var _mark := 0.0
var _frame := 0
var _state := "start"
var _fails := 0
var _stats := {}
var _shots := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a in ["--host", "--a", "--b"]:
			_mode = a.trim_prefix("--")
		elif a.begins_with("--out="):
			_out = a.trim_prefix("--out=")

func _process(delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--win="):
				var wh := a.trim_prefix("--win=").split("x")
				root.size = Vector2i(wh[0].to_int(), wh[1].to_int())
	if _frame < 3:
		return false
	_t += delta
	if _t > 120.0:
		_check(false, "%s: timed out in %s" % [_mode, _state])
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
				if peers.size() >= 2 and peers.all(func(p): return nm.is_peer_ready(p)):
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
				_state = "client_tally" if _mode == "a" else "linger_b"
		"linger":
			if _t - _mark > 25.0:
				return _finish()
		"linger_b":
			if not _stats.is_empty():
				_mark = _t
				_state = "linger"
		"client_tally":
			if _stats.is_empty():
				return false
			_mark = _t
			_state = "shots"
		"shots":
			# Wall cam + delay, then the tally lands and settles
			var at := [6.0, 9.0, 14.0]
			if _shots < at.size() and _t - _mark > at[_shots]:
				_shoot(_shots)
				_shots += 1
			if _shots >= at.size():
				_check_ready_row()
				return _finish()
	return false

# The client's Main can be swapped after joining: find the live one
func _live_main() -> Node:
	for c in root.get_children():
		if c != null and is_instance_valid(c) and "hud" in c and c.hud != null:
			return c
	return null

func _shoot(i: int) -> void:
	var hud = _live_main().hud
	var rr = hud._ready_row
	var vp := root.get_visible_rect().size
	var r: Rect2 = rr.get_global_rect() if rr != null and is_instance_valid(rr) else Rect2()
	var b: Rect2 = hud.banner.get_global_rect()
	print("shot %d  t=%.1f vp=%s factor=%.2f banner=%s scale=%.2f ready=%s visible=%s" % [i, _t, vp,
		root.content_scale_factor, b, hud.banner.scale.x, r, rr.is_visible_in_tree() if rr else false])
	if not _out.is_empty():
		root.get_texture().get_image().save_png(_out.path_join("tally_%d.png" % i))

func _check_ready_row() -> void:
	var hud = _live_main().hud
	var rr = hud._ready_row
	_check(rr != null and is_instance_valid(rr) and rr.is_visible_in_tree(), "a: ready row exists and shows")
	if rr == null or not is_instance_valid(rr):
		return
	var vp := root.get_visible_rect().size
	# Global rect ignores the banner's scale: map the row's corners through the transform
	var xf: Transform2D = rr.get_global_transform()
	var bottom := (xf * Vector2(0, rr.size.y)).y
	var top := (xf * Vector2.ZERO).y
	_check(top >= 0.0 and bottom <= vp.y, "a: ready row on screen (y %.0f..%.0f of %.0f)" % [top, bottom, vp.y])

func _close_stretch() -> void:
	_main.get_node("WaveManager").stop()
	for e in _main.get_node("Enemies").get_children():
		e.free()
	var d = _main.director
	for unit: Array in d._units:
		for part in unit:
			if "stage" in part:
				part.stage = 3
			elif "finished" in part:
				part.finished = true

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1

func _finish() -> bool:
	print("tally_mp_shots (%s): %s" % [_mode, "all passed" if _fails == 0 else "%d failed" % _fails])
	quit(1 if _fails else 0)
	return true
