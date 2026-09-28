extends SceneTree

# Playtest 2 fixes (GDD §5.7), offline:
#   Godot --headless --path . --script res://tools/playtest2_test.gd -- --nostory
# - a watch post raised while the crew gathers is bare again when day 1 begins
# - a worker who falls with nobody else standing gets back up on their own, at full health
# - [E] at a finished wall from outside climbs the worker over to the inside
# - hung gate doors are on the enemies-only layer, not one workers collide with
# Exit code 0 = every check passed.

var _main: Node3D
var _gs: Node
var _frame := 0
var _t := 0.0
var _mark := 0.0
var _state := "gather"
var _fails := 0
var _post: Node3D
var _player: Node3D

func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	if _frame == 3:
		_gs = root.get_node("GameState")
		_player = _main.get_node("Players").get_child(0)
	_t += delta
	if _t > 60.0:
		_check(false, "timed out in " + _state)
		return _finish()
	match _state:
		"gather":
			_post = get_nodes_in_group("watch_posts")[0]
			while _post.needs("wood"):
				_post.deposit("wood", 1)
			_check(_post.try_build() and _post.built, "post raised while gathering")
			_main.director.begin()
			_state = "dawn"
		"dawn":
			if _gs.phase == _gs.Phase.DAWN or _gs.phase == _gs.Phase.WORK:
				_check(not _post.built, "gathering post is bare at day 1")
				_state = "work"
		"work":
			if _gs.phase != _gs.Phase.WORK:
				return false
			_main.get_node("WaveManager").stop()
			for e in _main.get_node("Enemies").get_children():
				e.queue_free()
			_player.take_damage(1000.0)
			_check(_player.downed, "worker downed")
			_mark = _t
			_state = "downed"
		"downed":
			if not _player.downed:
				var crew := _main.get_node("Players").get_child_count()
				if crew == 1:
					_check(_t - _mark > 7.0, "alone: back up after the countdown (%.1f s)" % (_t - _mark))
				else:
					print("  (crew of %d: helped up after %.1f s)" % [crew, _t - _mark])
				_check(is_equal_approx(_player.health, _player.MAX_HEALTH), "full health on revive (%.0f)" % _player.health)
				_climb_setup()
		"climb":
			if _t - _mark > 1.2:
				_check(_player.global_position.z > 0.5, "climbed over to the inside (z %.1f)" % _player.global_position.z)
				var gate: Node3D = _main.get_node("Wall/SheepGate")
				if _gs.has_gate():
					_check(gate._door_body.collision_layer & 2 == 0 and gate._door_body.collision_layer & _player.collision_mask == 0,
						"gate doors don't block workers (layer %d)" % gate._door_body.collision_layer)
				return _finish()
	return false

func _climb_setup() -> void:
	var wall: Node3D = _main.get_node("Wall/Section3")
	wall.stage = wall.Stage.MORTARED
	var outside := wall.global_position + Vector3(0.5, 0.1, -1.4)
	_player.global_position = outside
	var choice: Array = _player._interact_choice(outside)
	_check(choice[0] == _player.Act.CLIMB, "[E] outside a finished wall climbs (act %d)" % choice[0])
	_player._server_interact.rpc_id(1, outside)
	_mark = _t
	_state = "climb"

func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1

func _finish() -> bool:
	print("playtest2_test: %d failed" % _fails)
	quit(1 if _fails else 0)
	return true
