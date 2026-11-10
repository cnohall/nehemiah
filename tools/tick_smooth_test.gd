extends SceneTree

# TickSmooth: a body moved on 60 Hz physics, drawn at 144 fps. Without the smoother the
# drawn step per frame swings between 0 and a whole tick's travel; with it each frame moves
# about the same. Also checks physics still runs from the true spot and that a teleport
# between ticks snaps instead of sliding.
#   Godot --headless --path . --script res://tools/tick_smooth_test.gd --fixed-fps 144 [-- --off]

const SPEED := 6.0

class Mover extends Node3D:
	var ticks := 0
	var true_pos := Vector3.ZERO   # where physics alone would have it
	var bad := 0
	func _physics_process(delta: float) -> void:
		if not position.is_equal_approx(true_pos):
			bad += 1               # physics saw a blended spot
		ticks += 1
		position += Vector3(SPEED * delta, 0, 0)
		true_pos = position

class Watcher extends Node:
	var body: Node3D
	var last := Vector3.ZERO
	var steps: Array[float] = []
	func _process(_d: float) -> void:
		steps.append(body.global_position.x - last.x)
		last = body.global_position

var _m: Mover
var _w: Watcher
var _frame := 0
var _off := false

func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	_off = "--off" in OS.get_cmdline_user_args()
	var stage := Node3D.new()
	root.add_child(stage)
	_m = Mover.new()
	stage.add_child(_m)
	if not _off:
		_m.add_child(TickSmooth.new())
	_w = Watcher.new()
	_w.body = _m
	_w.process_priority = 500
	stage.add_child(_w)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 150:
		# Teleport between ticks, as to_start() or an RPC does
		_m.global_position = Vector3(100, 0, 0)
		_m.true_pos = _m.global_position
	if _frame < 300:
		return false
	var s := _w.steps.slice(20, 140)   # steady run, before the teleport
	var lo := 1e9
	var hi := -1e9
	for v in s:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var expect := SPEED / 144.0
	var after := _w.steps.slice(152, 160)
	var slid := after.any(func(v: float) -> bool: return absf(v) > 1.0)
	print("per-frame step min %.4f max %.4f (ideal %.4f)  physics saw blend %d  slide after teleport %s"
		% [lo, hi, expect, _m.bad, slid])
	var smooth := hi - lo < expect * 0.5
	var ok := (not smooth) if _off else (smooth and _m.bad == 0 and not slid)
	print("PASS" if ok else "FAIL")
	quit(0 if ok else 1)
	return true
