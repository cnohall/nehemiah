extends SceneTree

# Running smoothness: a body moved on 60 Hz physics ticks while frames render faster, running
# along the line between two of the four animation directions (as a turned camera's diagonal
# does), its velocity wobbling a hair either side of it. Counts how often the figure's facing
# and lean reverse direction frame to frame: a smooth run turns and leans one way at a time.
#   Godot --path . --script res://tools/run_jitter_test.gd --fixed-fps 144 [-- --net]
# `--net`: the position arrives every third tick, as a remote player's does over the network.
# Prints PASS / FAIL with the reversal counts.

var _body: Node3D
var _rig: CharacterRig
var _frame := 0
var _t := 0.0
var _yaws: Array[float] = []
var _leans: Array[float] = []
var _dir := "down"

class Mover extends Node3D:
	var vel := Vector3.ZERO
	var tick := 0
	var net := false
	var pending := Vector3.ZERO
	func _physics_process(delta: float) -> void:
		tick += 1
		# Along +x (exactly between "down" and "right"), wobbling a hair either side
		vel = Vector3(8.0, 0.0, 0.06 * (1.0 if tick % 2 == 0 else -1.0))
		pending += vel * delta
		if not net or tick % 3 == 0:
			position += pending
			pending = Vector3.ZERO

func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	_body = Mover.new()
	(_body as Mover).net = "--net" in OS.get_cmdline_user_args()
	stage.add_child(_body)
	_rig = CharacterRig.new()
	_body.add_child(_rig)
	_rig.setup(CharacterRig.worker_look(0, Palette.CREW[0]))
	_rig.play("run_down")

func _process(delta: float) -> bool:
	_frame += 1
	_t += delta
	var m := _body as Mover
	_dir = CharAnim.dir_from_velocity(m.vel, _dir)
	_rig.play("run_" + _dir)
	if _t > 1.0:
		_yaws.append(_rig.rotation.y)
		_leans.append(_rig._torso.rotation.x)
	if _t < 3.0:
		return false
	var yaw_flips := _reversals(_yaws, 0.002)
	var lean_flips := _reversals(_leans, 0.002)
	var spread := 0.0
	for y in _yaws:
		spread = maxf(spread, absf(angle_difference(y, atan2(1.0, 0.0))))
	print("frames=%d yaw reversals=%d lean reversals=%d max yaw off path=%.3f rad" % [_yaws.size(), yaw_flips, lean_flips, spread])
	var ok := yaw_flips <= 2 and lean_flips <= 2 and spread < 0.12
	print("PASS" if ok else "FAIL")
	return true

# Times the per-frame change flips sign (ignoring changes smaller than eps)
func _reversals(xs: Array[float], eps: float) -> int:
	var n := 0
	var last := 0.0
	for i in range(1, xs.size()):
		var d := angle_difference(xs[i - 1], xs[i])
		if absf(d) < eps:
			continue
		if last != 0.0 and signf(d) != signf(last):
			n += 1
		last = d
	return n
