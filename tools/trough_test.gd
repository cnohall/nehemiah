extends SceneTree

# The mortar trough is stirred by hand (Fountain Gate, "mixing"), offline:
#   Godot --headless --path . --script res://tools/trough_test.gd -- --nostory --no-waves --day=34
# Lime and water in, nobody at it: stays wet lime. A worker at it: the progress fills and
# the trough holds mortar. Exit code 0 = every check passed.

var _main: Node3D
var _frame := 0
var _t := 0.0
var _fails := 0
var _stage := 0
var _trough: Node3D
var _player: Node3D

func _initialize() -> void:
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _check(ok: bool, what: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1

func _process(delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_main.director.begin()
	if _frame < 3:
		return false
	_t += delta
	var gs = root.get_node("GameState")
	if _stage == 0 and gs.phase == gs.Phase.WORK:
		_main.get_node("WaveManager").stop()
		_player = _main.get_node("Players").get_node_or_null(str(root.multiplayer.get_unique_id()))
		for n in _main.find_children("*", "StaticBody3D", true, false):
			if n.has_method("request_pickup") and n.has_method("work_material") and not n.has_method("scatter") and n.visible:
				_trough = n
		_check(_trough != null and _player != null, "a trough and a worker")
		if _trough == null or _player == null:
			quit(1)
			return true
		_check(not _trough.can_build(), "empty trough: nothing to stir")
		_check(_trough.deposit("lime", 1) and _trough.deposit("water", 1), "lime and water go in")
		_check(_trough.can_build() and not _trough.mortar_ready, "full trough wants stirring")
		_stage = 1
		_t = 0.0
	elif _stage == 1 and _t > 3.0:
		_check(_trough.work().progress == 0.0 and not _trough.mortar_ready, "nobody at it: it does not mix by itself")
		_player.global_position = _trough.global_position + Vector3(0, 0, 1.2)
		_player.building_site = _trough
		_check(_trough.work().add_builder(_player), "a worker takes the paddle")
		_stage = 2
		_t = 0.0
	elif _stage == 2:
		if _trough.mortar_ready:
			_check(_t > 1.0, "stirred in %.1f s" % _t)
			_check(not _trough.can_build() and not _trough.has_lime and not _trough.has_water, "batch done, trough empty")
			_check(_trough.request_pickup() and not _trough.mortar_ready, "the mortar can be taken")
			print("trough_test: ", "FAIL" if _fails > 0 else "PASS")
			quit(1 if _fails > 0 else 0)
			return true
		if _t > 15.0:
			_check(false, "timed out stirring (progress %.2f)" % _trough.work().progress)
			quit(1)
			return true
	return false
