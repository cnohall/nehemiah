extends SceneTree

# The city well (GDD §5.22), offline:
#   Godot --headless --path . --script res://tools/well_test.gd -- --nostory
# - the well is in the world and its tag shows only to a hurt worker (plain "Well" far off, "Drink" near)
# - [E] at the lip when hurt and empty-handed drinks; with a load it explains itself instead
# - health climbs while drinking, stops at full, and a blow ends the drink early
# - the "drink at the well" hint fires once, the first time health falls under half
# Exit code 0 = every check passed.

var _main: Node3D
var _gs: Node
var _frame := 0
var _t := 0.0
var _mark := 0.0
var _state := "begin"
var _fails := 0
var _player: Node3D
var _well: Node3D

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
		"begin":
			_main.director.begin()
			_state = "work"
		"work":
			if _gs.phase != _gs.Phase.WORK:
				return false
			_main.get_node("WaveManager").stop()
			for e in _main.get_node("Enemies").get_children():
				e.queue_free()
			_well = get_first_node_in_group("wells")
			_check(_well != null, "the well is in the world")
			_check(not _player._well_told, "no hint before a wound")
			_check(not _well._tag.visible, "healthy: no tag")
			_player.take_damage(70.0)
			_check(is_equal_approx(_player.health, 30.0), "hurt to 30 (%.0f)" % _player.health)
			_check(_player._well_told, "hint told once health fell under half")
			_mark = _t
			_state = "tag_far"
		"tag_far":
			# Wait out the stagger, then look at the tag from where the worker stands (far)
			if _t - _mark < 0.6:
				return false
			_check(_well._tag.visible and _well._tag.text == "Well", "hurt, far: the tag says \"Well\" (%s)" % _well._tag.text)
			_check(_well._tag.pulse, "badly hurt: the tag breathes")
			var far: Array = _player._interact_choice(_player.global_position)
			_check(far[0] != _player.Act.DRINK, "far from the well, [E] does not drink")
			_player.global_position = _lip()
			_state = "load"
			_mark = _t
		"load":
			if _t - _mark < 0.2:
				return false
			_player._set_carried.rpc("stone")
			_mark = _t
			_state = "load_check"
		"load_check":
			if _t - _mark < 0.2:
				return false
			var at: Vector3 = _player.global_position
			var choice: Array = _player._interact_choice(at)
			_check(choice[0] != _player.Act.DRINK, "a load in hand: [E] does not drink")
			_check(String(_player._why_not_needed(at)[0]).begins_with("Set it down"), "…and says why: %s" % _player._why_not_needed(at)[0])
			_check(_well._tag.text == "Set the load down first", "…the tag too (%s)" % _well._tag.text)
			_player._set_carried.rpc("")
			_mark = _t
			_state = "drink_start"
		"drink_start":
			if _t - _mark < 0.2:
				return false
			_check(_well._tag.text.begins_with("Drink"), "hands free at the lip: the tag says \"Drink\" (%s)" % _well._tag.text)
			var at: Vector3 = _player.global_position
			var choice: Array = _player._interact_choice(at)
			_check(choice[0] == _player.Act.DRINK and choice[1] == _well, "hands free at the lip: [E] drinks (act %d)" % choice[0])
			_player._server_interact.rpc_id(1, at)
			_mark = _t
			_state = "drinking"
		"drinking":
			if _t - _mark < 0.5:
				return false
			_check(_player.is_drinking() and _player.drinking_well == _well, "drinking")
			_check(_player.health > 30.0 and _player.health < 100.0, "health climbing (%.0f)" % _player.health)
			_check(not _well._tag.visible, "no tag while drinking")
			_player.take_damage(5.0)
			_mark = _t
			_state = "interrupted"
		"interrupted":
			if _t - _mark < 0.1:
				return false
			_check(not _player.is_drinking() and _player.drinking_well == null, "a blow ends the drink")
			var hp: float = _player.health
			_check(hp > 30.0 and hp < 100.0, "…keeping what was drunk (%.0f)" % hp)
			_mark = _t
			_state = "wait_stagger"
		"wait_stagger":
			if _t - _mark < 0.5:
				return false
			var at: Vector3 = _player.global_position
			_player._server_interact.rpc_id(1, at)
			_mark = _t
			_state = "full"
		"full":
			if _t - _mark < 3.0:
				return false
			_check(is_equal_approx(_player.health, 100.0), "drinks to full health (%.0f)" % _player.health)
			_check(not _player.is_drinking() and _player.drinking_well == null, "…and stops")
			var choice: Array = _player._interact_choice(_player.global_position)
			_check(choice[0] != _player.Act.DRINK, "full health: [E] does not drink")
			_check(not _well._tag.visible, "full health: no tag")
			return _finish()
	return false

# On the street side of the lip (_well.RIM + a step)
func _lip() -> Vector3:
	var c: Vector3 = _well.global_position
	return Vector3(c.x, 0.1, c.z - (_well.RIM + 0.5))

func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1

func _finish() -> bool:
	print("well_test: %d failed" % _fails)
	quit(1 if _fails else 0)
	return true
