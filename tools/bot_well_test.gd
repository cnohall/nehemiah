extends SceneTree

# A badly hurt bot with free hands and no foe about walks to the well and drinks to full
# (BotBrain Job.DRINK), offline. Exit code 0 = it did.
#   Godot --headless --path . --script res://tools/bot_well_test.gd
# Also prints how long the trip took.

const TIMEOUT := 50.0
const DRINK := 12   # BotBrain.Job.DRINK — class names aren't usable before the autoloads load

var _main: Node
var _frame := 0
var _t := 0.0
var _saved_count := 0
var _saved_skill := 0
var _bot: Node3D
var _mark := 0.0
var _drank := false

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
		_main.director.begin()
	if gs.phase in [gs.Phase.STORY, gs.Phase.DUSK]:
		_main.director.force_ready()
	if _t > TIMEOUT:
		print("FAIL: bot health %.0f, job %d, drinking %s, dist to well %.1f" % [
			_bot.health if _bot else -1.0, _bot.brain._job if _bot else -1, _bot.is_drinking() if _bot else false,
			_bot.global_position.distance_to(get_first_node_in_group("wells").global_position) if _bot else -1.0])
		return _finish(1)
	if gs.phase != gs.Phase.WORK:
		return false
	if _bot == null:
		for p in _main.players_root.get_children():
			if p.brain != null:
				_bot = p
		_main.get_node("WaveManager").stop()
		for e in _main.get_node("Enemies").get_children():
			e.queue_free()
		return false
	if _mark == 0.0:
		_bot.take_damage(70.0)
		_mark = _t
		print("bot hurt to %.0f at %.1f s" % [_bot.health, _t])
		return false
	_drank = _drank or _bot.is_drinking()
	if _drank and _bot.health >= 99.9:
		print("PASS: bot drank to full %.1f s after being hurt" % (_t - _mark))
		return _finish(0)
	return false

func _finish(code: int) -> bool:
	var settings := root.get_node("Settings")
	settings.bot_count = _saved_count
	settings.bot_skill = _saved_skill
	quit(code)
	return true
