extends SceneTree

# The hungry households of the Fountain Gate (GDD §5.12, Neh. 5), offline, no bots:
#   Godot --path . --script res://tools/households_test.gd -- --nostory --day=34 <out_dir>
# - three households and a portion pile stand in this stretch, nowhere else
# - a worker takes a portion, [E] beside a household delivers it, they're fed
# - each family fed adds 6% to the work; a second portion to the same household is refused
# - the walls never count them as a site, and nothing is left behind in the next stretch
# Exit code 0 = every check passed.

var _out := ""
var _main: Node3D
var _frame := 0
var _t := 0.0
var _state := "wait_work"
var _fails := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	root.size = Vector2i(1920, 1080)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_main.fit_bots(0)
		_main.director.begin()
	if _frame < 3:
		return false
	_t += delta
	var gs = root.get_node("GameState")
	for e in _main.get_node("Enemies").get_children():
		e.queue_free()
	if _t > 60.0:
		_fail("timed out in " + _state)
		return _finish()
	if _state == "wait_work" and gs.phase == gs.Phase.WORK:
		_state = "running"
		_run(gs)
	return false

func _run(gs: Node) -> void:
	var player: Node3D = _main.get_node("Players").get_child(0)
	var hh: Node = _main.get_node("Households")
	var piles := get_nodes_in_group("supply_piles").filter(func(p): return p.kind == "portion")
	_check(piles.size() == 1, "one portion pile stands (%d)" % piles.size())
	var fam := get_nodes_in_group("households")
	_check(fam.size() == 3, "three hungry households (%d)" % fam.size())
	_check(get_nodes_in_group("build_sites").all(func(s): return not s.has_method("talk")), "walls don't count them as sites")
	var base: float = gs.mod("work")
	# Take a portion, walk to the first household, deliver
	for i in fam.size():
		var f = fam[i]
		player.global_position = f.global_position + Vector3(0, 0, 1.2)
		player._set_carried.rpc("portion")
		await process_frame
		var choice: Array = player._interact_choice(player.global_position)
		_check(choice[0] == player.Act.DELIVER and choice[1] == f, "[E] beside household %d delivers (%s)" % [i, choice])
		player._deliver(choice[1], player.global_position)
		_check(not f.hungry, "household %d is fed" % i)
		_check(player.carried_kind == "", "portion left the hands")
		_check(is_equal_approx(gs.mod("work"), base * (1.0 + 0.06 * (i + 1)) / 1.0) or absf(gs.mod("work") - (1.0 + 0.06 * (i + 1))) < 0.001,
			"work +%d%% (%.2f)" % [6 * (i + 1), gs.mod("work")])
	# A fed household takes no more
	player._set_carried.rpc("portion")
	await process_frame
	var again: Array = player._interact_choice(player.global_position)
	_check(again[1] == null, "a fed household refuses another")
	_check(get_nodes_in_group("households").is_empty(), "no hungry household left")
	player._set_carried.rpc("")
	# Next stretch: gone, and the bonus with them
	gs._apply(gs.SECTIONS[8]["days"][0], 8, gs.Phase.DAWN, 0, 0, 0)
	await process_frame
	await process_frame
	_check(gs.households_fed == 0, "bonus reset in the next stretch")
	_check(get_nodes_in_group("households").is_empty() and get_nodes_in_group("folk").is_empty(), "families gone in the next stretch")
	_check(get_nodes_in_group("supply_piles").all(func(p): return p.kind != "portion"), "portion pile gone in the next stretch")
	_finish()

func _check(ok: bool, what: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1

func _fail(what: String) -> void:
	_check(false, what)

func _finish() -> bool:
	print("households_test: %s" % ("PASS" if _fails == 0 else "%d failed" % _fails))
	quit(0 if _fails == 0 else 1)
	return true
