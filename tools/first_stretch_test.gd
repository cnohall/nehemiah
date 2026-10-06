extends SceneTree

# The first stretch (GameState.first_stretch), offline, no bots:
#   Godot --path . --script res://tools/first_stretch_test.gd -- --nostory [--simple]
# Sheep Gate, in either game:
# - timber and stone piles only (no mortar); no watch posts
# - frames cost timber, courses stone, the finish stone; walls start bare
# - a battered finished wall is mended with stone
# Fish Gate: mortar and the watch posts are out, the finish and mending take mortar.
# Exit code 0 = every check passed.

var _main: Node3D
var _frame := 0
var _t := 0.0
var _state := "wait_work"
var _fails := 0
var _gs: Node

func _initialize() -> void:
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
	_gs = root.get_node("GameState")
	for e in _main.get_node("Enemies").get_children():
		e.queue_free()
	if _t > 60.0:
		_fail("timed out in " + _state)
		return _finish()
	if _state == "wait_work" and _gs.phase == _gs.Phase.WORK:
		_state = "running"
		_run()
	return false

func _kinds() -> Array:
	var out := get_nodes_in_group("supply_piles").map(func(p): return p.kind)
	out.sort()
	return out

func _walls() -> Array:
	return get_nodes_in_group("build_sites").filter(func(s): return s.has_method("cost_for") and not s.decorative)

func _posts() -> Array:
	return _main.find_children("*", "", true, false).filter(func(n): return n.has_method("fortify"))

func _run() -> void:
	print("  (%s game)" % ("simple" if _gs.simplified() else "full"))
	_check(_gs.first_stretch(), "Sheep Gate is the first stretch")
	_check(_kinds() == ["stone", "wood"], "timber and stone only (%s)" % [_kinds()])
	_check(not _posts().is_empty() and _posts().all(func(p): return not p.visible) and get_nodes_in_group("watch_posts").is_empty(),
		"no watch posts")
	var walls := _walls()
	var w: Node = walls[0]
	_check(walls.all(func(x): return x.stage == x.Stage.EMPTY or x.recipe() != ""), "walls start bare")
	_check(w.cost_for(w.Stage.FRAMED).keys() == ["wood"], "frames cost timber (%s)" % [w.cost_for(w.Stage.FRAMED)])
	_check(w.cost_for(w.Stage.STACKED).keys() == ["stone"], "courses cost stone")
	_check(w.cost_for(w.Stage.MORTARED).keys() == ["stone"], "the finish costs stone (%s)" % [w.cost_for(w.Stage.MORTARED)])
	w.stage = w.Stage.MORTARED
	w.health = w.MAX_HEALTH * 0.5
	_check(w.repairing() and w.needs("stone") and not w.needs("mortar"), "mending takes stone")

	# The Fish Gate: mortar and posts come in
	_gs._apply(5, 1, _gs.Phase.WORK, 0, 0, 0)
	for _i in 5:
		await process_frame
	_check(not _gs.first_stretch(), "Fish Gate is not")
	_check("mortar" in _kinds(), "mortar out at the Fish Gate (%s)" % [_kinds()])
	_check(_posts().all(func(p): return p.visible), "watch posts at the Fish Gate")
	var f: Node = _walls()[0]
	_check(f.cost_for(f.Stage.MORTARED).has("mortar"), "the finish takes mortar again")
	_finish()

func _check(ok: bool, what: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1

func _fail(what: String) -> void:
	_check(false, what)

func _finish() -> bool:
	print("first_stretch_test: %s" % ("PASS" if _fails == 0 else "%d failed" % _fails))
	quit(0 if _fails == 0 else 1)
	return true
