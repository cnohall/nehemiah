extends SceneTree

# The simple game (Settings.simple_game, GameState.simplified), offline, no bots:
#   Godot --path . --script res://tools/simple_game_test.gd -- --nostory --day=34 --simple
# - Fountain Gate: no hungry households, no portion pile, the dawn line leaves them out
# - no jars or birds about the site
# - two marks in play; a finished stretch never earns "In good time"
# - a stretch's last tally moves on without the ready check
# - switched back to the full game mid-stretch: households, jars and birds return
# Settings are never saved. Exit code 0 = every check passed.

var _main: Node3D
var _frame := 0
var _t := 0.0
var _mark := 0.0
var _state := "wait_work"
var _fails := 0
var _gs: Node

func _initialize() -> void:
	root.get_node("Settings").simple_game = true
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
	match _state:
		"wait_work":
			if _gs.phase == _gs.Phase.WORK:
				_state = "running"
				_run()
		"tally":
			if _gs.phase != _gs.Phase.DUSK:
				var took := _t - _mark
				_check(took > 9.0 and took < 13.0, "the stretch's tally moves on by itself (%.1f s)" % took)
				return _finish()
	return false

func _run() -> void:
	# Loaded here, not named: in a --script run the class names would compile before the autoloads
	var Trade = load("res://scenes/shared/trade.gd")
	var StoryData = load("res://scenes/story/story_data.gd")
	_check(_gs.simplified(), "the simple game is in play")
	_check(get_nodes_in_group("households").is_empty(), "no hungry households")
	_check(get_nodes_in_group("supply_piles").all(func(p): return p.kind != "portion"), "no portion pile")
	_check(not "households" in _gs.twist_intro("spring"), "dawn line leaves the households out")
	_check(_main.get_node("Breakables").get_child_count() == 0, "no jars (%d)" % _main.get_node("Breakables").get_child_count())
	_check(_main.get_node("Birds")._flocks.is_empty(), "no birds")
	_check(not _main.get_node("Passersby").visible, "no townsfolk in the streets")
	# The flock lives at the Sheep and Miphkad Gates: lay the Sheep Gate out to see it
	_gs._apply(1, 0, _gs.Phase.WORK, 0, 0, 0)
	for _i in 5:
		await process_frame
	var flock = _main.find_child("Flock", true, false)
	_check(flock != null and not flock._sheep.is_empty(), "the Sheep Gate keeps its sheep")
	if flock != null:
		var t0: float = flock._t
		for _i in 30:
			await process_frame
		_check(flock._t == t0, "the sheep stand still")
	_gs._apply(34, 7, _gs.Phase.WORK, 0, 0, 0)
	for _i in 5:
		await process_frame
	_check(_gs.marks_in_play().size() == 2 and not _gs.Mark.PACE in _gs.marks_in_play(), "two marks in play")
	_check(not _gs.trades_on() and Trade.work_pace(0, "stone") == 1.0 and Trade.work_mult() == 1.0, "no trades: plain work at the old times")
	_check(not _gs.saboteur_on(), "no saboteur")
	_check(not StoryData.choice_offered(_gs.current_section_index), "no choice before the stretch")
	_gs.boon = _gs.BOONS.keys()[0]
	_gs.rumour = true
	_check(is_equal_approx(_gs.mod("work"), 1.0) and is_equal_approx(_gs.mod("pressure"), 1.0), "no hidden modifiers (boon, rumour)")
	_gs.boon = ""
	_gs.rumour = false

	# Back to the full game mid-stretch: it all returns, nobody counted hungry
	root.get_node("Settings").simple_game = false
	_gs.share_rules()
	await process_frame
	_check(get_nodes_in_group("households").size() == 3, "full game: three households (%d)" % get_nodes_in_group("households").size())
	_check(get_nodes_in_group("supply_piles").any(func(p): return p.kind == "portion"), "full game: portion pile")
	_check(_main.get_node("Breakables").get_child_count() > 0, "full game: jars")
	_check(not _main.get_node("Birds")._flocks.is_empty(), "full game: birds")
	for _i in 3:
		await process_frame
	_check(_main.get_node("Passersby").visible or _main.get_node("Passersby")._walkers.is_empty(), "full game: townsfolk")
	_check(_gs.hungry_left == 0, "nobody counted hungry by the switch")
	_check(_gs.trades_on() and _gs.saboteur_on() and StoryData.choice_offered(_gs.current_section_index), "full game: trades, saboteur, choice")
	root.get_node("Settings").simple_game = true
	_gs.share_rules()
	await process_frame
	_check(get_nodes_in_group("households").is_empty() and _gs.hungry_left == 0, "simple again: households gone, none hungry")

	# Finish the stretch on its first day: spare days galore, still no "In good time"
	for unit in _main.director._units:
		for part in unit:
			if "finished" in part:
				part.finished = true
			if "stage" in part and "Stage" in part:
				part.stage = part.Stage.MORTARED
	_check(_main.director._section_done(), "stretch stands")
	await process_frame
	if _gs.phase != _gs.Phase.DUSK:   # the last stage landing usually ends the day itself
		_main.director._end_day()
	var mask: int = _main.director._stats.get("marks", -1)
	_check(mask >= 0 and not mask & _gs.Mark.PACE, "no \"In good time\" mark (mask %d)" % mask)
	_check(_main.director._wait_kind.is_empty(), "no ready check on the stretch's last tally")
	_mark = _t
	_state = "tally"

func _check(ok: bool, what: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1

func _fail(what: String) -> void:
	_check(false, what)

func _finish() -> bool:
	print("simple_game_test: %s" % ("PASS" if _fails == 0 else "%d failed" % _fails))
	quit(0 if _fails == 0 else 1)
	return true
