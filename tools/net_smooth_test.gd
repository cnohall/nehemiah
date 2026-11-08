extends SceneTree

# NetSmooth under a rough connection, one process, no network:
#   Godot --headless --path . --max-fps 60 --script res://tools/net_smooth_test.gd
# A fake remote figure runs a straight line at 5 m/s; its 20 Hz snapshots arrive late by
# 40 ms plus up to 80 ms of jitter (so in bunches, and out of order), with 5% lost, and one
# teleport. Per frame, how far the figure moves against how far it should: smoothed vs raw
# (newest snapshot, the old behaviour). Exit code 0 = all passed.

const SPEED := 5.0
const SEND_EVERY := 0.05
const LATENCY := 0.04
const JITTER := 0.08
const LOSS := 0.05
const RUN := 8.0
const TELEPORT_AT := 5.0

var _fig: Node3D
var _t := 0.0
var _send_t := 0.0
var _queue: Array = []   # [arrive_at, Vector4]
var _last := Vector3.ZERO
var _raw_last := Vector3.ZERO
var _raw := Vector3.ZERO
var _frames := 0
var _bad := 0
var _raw_bad := 0
var _teleported := false
var _fails := 0
var _done := false

func _initialize() -> void:
	seed(7)
	_fig = Node3D.new()
	_fig.set_multiplayer_authority(2)   # owned by "someone else"
	root.add_child(_fig)

func _true_x(sender_t: float) -> float:
	return SPEED * sender_t + (20.0 if sender_t > TELEPORT_AT else 0.0)

func _process(delta: float) -> bool:
	_t += delta
	# Sender: a snapshot every 50 ms, sent into a rough pipe
	while _send_t <= _t:
		var x := _true_x(_send_t)
		var v := Vector4(x, 0.0, 0.0, NetSmooth.now() - (_t - _send_t))
		if randf() > LOSS:
			_queue.append([_send_t + LATENCY + randf() * JITTER, v])
		_send_t += SEND_EVERY
	# Receiver: whatever has arrived, in arrival order
	_queue.sort_custom(func(a, b): return a[0] < b[0])
	while not _queue.is_empty() and _queue[0][0] <= _t:
		var v: Vector4 = _queue.pop_front()[1]
		NetSmooth.receive(_fig, v)
		if v.x > _raw.x or v.x < _raw.x - 10.0:
			_raw = Vector3(v.x, 0, 0)
	return false

# Measured once the frame's processing is done
func _init() -> void:
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if _fig == null or _done:
		return
	var delta := get_root().get_process_delta_time()
	var p := _fig.position
	if _t > 1.0 and delta > 0.0:
		var jump := p.x - _last.x
		var raw_jump := _raw.x - _raw_last.x
		if jump > 10.0:
			_teleported = true
		elif not _near_teleport():
			_frames += 1
			var ratio := jump / (SPEED * delta)
			if ratio < 0.4 or ratio > 2.0:
				_bad += 1
			var raw_ratio := raw_jump / (SPEED * delta)
			if raw_ratio < 0.4 or raw_ratio > 2.0:
				_raw_bad += 1
	_last = p
	_raw_last = _raw
	if _t > RUN:
		_finish()

func _near_teleport() -> bool:
	return absf(_t - TELEPORT_AT - 0.15) < 0.35

func _finish() -> void:
	_done = true
	var pct := 100.0 * _bad / maxf(1, _frames)
	var raw_pct := 100.0 * _raw_bad / maxf(1, _frames)
	print("frames %d: smoothed off-pace %.1f%%, raw off-pace %.1f%%" % [_frames, pct, raw_pct])
	_check(_frames > 100, "enough frames measured")
	_check(pct < 5.0, "smoothed: under 5%% of frames stall or jump (%.1f%%)" % pct)
	_check(raw_pct > pct * 3.0, "raw is much rougher (%.1f%% vs %.1f%%)" % [raw_pct, pct])
	_check(_teleported, "a teleport snaps instead of sliding")
	_check(absf(_fig.position.x - _true_x(_t - 0.1 - LATENCY)) < 2.0,
		"lags the truth by about the buffer (%.2f vs %.2f)" % [_fig.position.x, _true_x(_t - 0.1 - LATENCY)])
	print("net_smooth_test: %s" % ("all passed" if _fails == 0 else "%d failed" % _fails))
	quit(1 if _fails else 0)

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1
