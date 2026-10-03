extends SceneTree

# Headless: bots alone clear a burned footing — every timber off the pad (plus one stray set
# down short of the tip) carried to the tip, nothing left lying, the wall cleared.
#   Godot --headless --path . --script res://tools/bot_debris_test.gd -- --nostory --day=9

const LIMIT := 60 * 90   # frames (~90 s at 60 fps)

var _main: Node3D
var _boot := 0
var _state := 0
var _t := 0
var _wall: Node3D

func _initialize() -> void:
	root.size = Vector2i(640, 360)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _debris() -> Array:
	return root.get_tree().get_nodes_in_group("dropped_items").filter(func(it): return it.kind == "debris")

func _in_hand() -> int:
	return root.get_tree().get_nodes_in_group("players").filter(func(p): return p.carried_kind == "debris").size()

func _process(_delta: float) -> bool:
	_boot += 1
	if _boot == 3:
		_main.fit_bots(3)
		_main.director.begin()
	if _boot < 3:
		return false
	var gs = root.get_node("GameState")
	if gs.phase != gs.Phase.WORK or _main.get_node("Players").get_child_count() < 4:
		return false
	_t += 1
	if _wall == null:
		for s in root.get_tree().get_nodes_in_group("build_sites"):
			if s.has_method("debris_on_pad") and s.recipe() == "burned" and s.is_target:
				_wall = s
		print("burned wall: ", _wall.name if _wall else "NONE")
		if _wall == null:
			quit(1)
		return false
	match _state:
		0:
			_wall.try_build()
			# A stray: halfway between footing and tip, as a player might leave one
			var it: Node3D = _wall.debris_on_pad()[0]
			var tip: Vector3 = _wall.dump_marker().global_position
			it.global_position = Vector3((it.global_position.x + tip.x) * 0.5, it.global_position.y, (it.global_position.z + tip.z) * 0.5)
			print("pulled: on pad=", _wall.debris_on_pad().size(), " total=", _debris().size())
			_state = 1
			_t = 0
		1:
			if OS.get_cmdline_user_args().has("--trace") and _t % 60 == 0:
				for p in root.get_tree().get_nodes_in_group("players"):
					if p.brain != null:
						var tg = p.brain._target
						print("  ", p.name, " job=", p.brain._job, " tgt=", tg.name if is_instance_valid(tg) else "-", " carry=", p.carried_kind, " pos=", p.global_position.snapped(Vector3.ONE * 0.1), " work=", p._work_site != null)
			if _t % 600 == 0:
				print("t=", _t / 60, "s on pad=", _wall.debris_on_pad().size(), " loose=", _debris().size(), " in hand=", _in_hand(), " cleared=", _wall.cleared)
			if _wall.cleared and _debris().is_empty() and _in_hand() == 0:
				print("CLEARED in ", _t / 60.0, "s, nothing left lying")
				quit(0)
			elif _t > LIMIT:
				print("FAIL: on pad=", _wall.debris_on_pad().size(), " loose=", _debris().size(), " in hand=", _in_hand(), " cleared=", _wall.cleared)
				for d in _debris():
					print("  left at ", d.global_position, " tip ", _wall.dump_marker().global_position)
				quit(1)
	return false
