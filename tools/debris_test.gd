extends SceneTree

# Headless check of burned-footing clearing (GDD §6.4 ruins): pull down, haul off, stages open.
#   Godot --headless --path . --script res://tools/debris_test.gd -- --nostory --day=9

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
			if s.has_method("debris_on_pad") and s.recipe() == "burned":
				_wall = s
		print("burned wall: ", _wall.name if _wall else "NONE")
		if _wall == null:
			quit(1)
		return false
	match _state:
		0:
			print("clearing=", _wall._clearing(), " can_build=", _wall.can_build(), " debris=", _wall.debris_on_pad().size())
			print("try_build -> ", _wall.try_build(), " pulled=", _wall.pulled, " cleared=", _wall.cleared)
			_state = 1
			_t = 0
		1:
			if _t == 3:
				print("debris on pad: ", _wall.debris_on_pad().size(), " can_build=", _wall.can_build(), " label=", _wall._label.text)
				for it in _wall.debris_on_pad():
					it.take()
				_state = 2
				_t = 0
		2:
			if _t == 30:
				print("after hauling: cleared=", _wall.cleared, " can_build=", _wall.can_build(), " needs wood=", _wall.needs("wood") or _wall.needs("beam"))
				quit(0 if _wall.cleared else 1)
	return false
