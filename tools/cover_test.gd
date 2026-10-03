extends SceneTree

# Bots cover a person at work (BotBrain Job.COVER) and say so (Player.bark), offline:
# the host is set to working a wall, a foe is put beside them, and one Builder bot must
# take up COVER, come within reach and show its call. Exit code 0 = it did.
#   Godot --headless --path . --script res://tools/cover_test.gd
# Also prints the crew weight with that bot (a Builder counts 0.75).

const TIMEOUT := 40.0
const COVER := 11   # BotBrain.Job.COVER — class names aren't usable before the autoloads load

var _main: Node
var _frame := 0
var _t := 0.0
var _saved_count := 0
var _saved_skill := 0
var _host: Node3D
var _bot: Node3D
var _foe: Node3D
var _covered := false

func _process(delta: float) -> bool:
	_frame += 1
	_t += delta
	var gs := root.get_node("GameState")
	if _frame == 1:
		var settings := root.get_node("Settings")
		_saved_count = settings.bot_count
		_saved_skill = settings.bot_skill
		settings.bot_count = 1
		settings.bot_skill = 1
		gs.replay_section = 0
		_main = load("res://scenes/main/main.tscn").instantiate()
		root.add_child(_main)
		current_scene = _main
		return false
	if _frame == 3:
		print("Crew: %d, weight %.2f, cost tier %d, solo work ×%.2f" % [
			gs.crew_size, gs.crew_weight, gs.cost_crew(), gs.solo_mult(0.75)])
		_main.director.begin()
	if gs.phase in [gs.Phase.STORY, gs.Phase.DUSK]:
		_main.director.force_ready()
	if _t > TIMEOUT:
		print("FAIL: bot job %s, dist %.1f, called %s" % [
			_bot.brain._job if _bot else -1, _bot.global_position.distance_to(_host.global_position) if _bot else -1.0,
			_bot._bark_shout != null if _bot else false])
		return _finish(1)
	if gs.phase != gs.Phase.WORK:
		return false
	if _host == null:
		for p in _main.players_root.get_children():
			if p.brain == null:
				_host = p
			else:
				_bot = p
		# The host at the nearest of today's walls, as if working it
		var site: Node3D = null
		for s in get_nodes_in_group("wall_sections"):
			if s.is_target and (site == null or s.global_position.distance_to(_host.global_position) < site.global_position.distance_to(_host.global_position)):
				site = s
		_host.global_position = site.approach_point(_host.global_position, 0.6)
		_host.building_site = site
		_bot.global_position = _host.global_position + Vector3(10, 0, 4)
		return false
	# Keep a foe beside the host (any will do; one is spawned if none is out yet)
	if not is_instance_valid(_foe):
		var foes := get_nodes_in_group("enemies")
		if foes.is_empty():
			return false
		_foe = foes[0]
	_foe.global_position = _host.global_position + Vector3(0, 0, -3)
	if _bot.brain._job == COVER:
		_covered = true
	var near := _bot.global_position.distance_to(_host.global_position) < 3.5
	if _covered and near and _bot._bark_shout != null:
		print("PASS: bot covered the host at %.1f m in %.1f s and called \"%s\"" % [
			_bot.global_position.distance_to(_host.global_position), _t, _bot._bark_shout.text])
		return _finish(0)
	return false

func _finish(code: int) -> bool:
	var settings := root.get_node("Settings")
	settings.bot_count = _saved_count
	settings.bot_skill = _saved_skill
	quit(code)
	return true
