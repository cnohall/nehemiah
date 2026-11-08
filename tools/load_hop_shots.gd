extends SceneTree

# Frames of a load hopping: pile → arms, arms → ground, ground → arms, arms → wall (LoadFlight).
#   Godot --path . --write-movie <dir>/f.png --fixed-fps 30 --script res://tools/load_hop_shots.gd -- --nostory
# Prints the movie frame of each event; the hop is the next ~8 frames.

var _main: Node3D
var _player: Node3D
var _site: Node3D
var _frame := 0
var _t := -1.0
var _step := 0
const STEPS := [0.6, 1.6, 2.8, 3.8, 5.0]

func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_main.director.begin()
	var gs = root.get_node("GameState")
	if _t < 0.0:
		if gs.phase == gs.Phase.WORK:
			_player = _main.get_node("Players").get_child(0)
			for s in _main.get_tree().get_nodes_in_group("build_sites"):
				if s.has_method("next_need") and s.next_need() != "":
					_site = s
					break
			_t = 0.0
		return false
	_t += delta
	gs.breaches = 0
	if _step >= STEPS.size() or _t < STEPS[_step]:
		return false
	var need: String = _site.next_need()
	match _step:
		0:
			var pile := _pile_for(need)
			_put(pile.approach_point(_site.global_position, 0.4))
			_press("interact")
			print("frame %d: pickup %s" % [_frame, need])
		1:
			_put(_player.global_position + Vector3(1.5, 0, 0))
			_press("drop")
			print("frame %d: drop" % _frame)
		2:
			_press("interact")   # the load just dropped, at our feet
			print("frame %d: pickup item" % _frame)
		3:
			_put(_site.approach_point(_site.global_position + Vector3(0, 0, 4), 0.6))
			_press("interact")
			print("frame %d: deliver" % _frame)
		4:
			quit(0)
			return true
	_step += 1
	return false

func _pile_for(kind: String) -> Node3D:
	for p in _main.get_tree().get_nodes_in_group("supply_piles"):
		if p.kind == kind:
			return p
	return _main.get_tree().get_nodes_in_group("supply_piles")[0]

func _put(p: Vector3) -> void:
	_player.global_position = Vector3(p.x, 0.1, p.z)
	_player.velocity = Vector3.ZERO

func _press(action: String) -> void:
	Input.action_press(action)
	await create_timer(0.05).timeout
	Input.action_release(action)
