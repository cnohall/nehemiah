extends SceneTree

# Townsfolk (Passersby) never get stuck: runs 30 minutes of street life at 60 fps (headless,
# offline) and fails if anyone out on an errand stays within 0.5 m of one spot for 3 s.
#   Godot --headless --path . --script res://tools/passersby_test.gd
# Errands are random (unseeded), so each run tries different traffic. Exit code 0 = pass.

const MINUTES := 30
const STEP := 1.0 / 60.0
const STUCK_AFTER := 3.0

var _main: Node3D
var _frame := 0
var _anchor := {}
var _since := {}
var _stuck := {}

func _initialize() -> void:
	root.size = Vector2i(640, 360)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false   # Passersby lays itself out a frame late (after ScatterLayer)
	var p = _main.get_node("Passersby")
	if p._walkers.is_empty():
		print("FAIL  no townsfolk")
		quit(1)
		return true
	for i in 600:   # 10 s per frame
		p._tick(STEP)
		for k in p._walkers.size():
			var w = p._walkers[k]
			if w.state != p.State.WALK:
				_since[k] = 0.0
				_anchor[k] = w.pos
				continue
			if w.pos.distance_to(_anchor.get(k, Vector2.INF)) > 0.5:
				_anchor[k] = w.pos
				_since[k] = 0.0
				continue
			_since[k] = _since.get(k, 0.0) + STEP
			if _since[k] > STUCK_AFTER and not _stuck.has(k):
				_stuck[k] = true
				print("STUCK walker ", k, " (", w.errand, ") at ", w.pos, " path ", w.path)
	if _frame >= 3 + MINUTES * 6:
		if _stuck.is_empty():
			print("PASS  %d townsfolk, %d min, nobody stuck" % [p._walkers.size(), MINUTES])
			quit(0)
		else:
			print("FAIL  %d of %d got stuck" % [_stuck.size(), p._walkers.size()])
			quit(1)
		return true
	return false
