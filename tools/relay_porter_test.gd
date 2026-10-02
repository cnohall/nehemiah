extends SceneTree

# Headless check of the relay mat's porter (Dung Gate, "haul"):
#   Godot --headless --path . --script res://tools/relay_porter_test.gd -- --nostory --day=30
# Lays loads on the mat, waits for the porter's trip, prints what the wall received.

var _main: Node3D
var _mat: Node3D
var _boot := 0
var _state := 0
var _t := 0
var _before := {}

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
	if _mat == null:
		for c in _main.get_children():
			if c.get_script() != null and c.get_script().resource_path.ends_with("relay_mat.gd"):
				_mat = c
		print("mat found: ", _mat != null, " visible: ", _mat.visible if _mat else "-", " name: ", _mat.name if _mat else "-")
	if _state == 0:
		for it in _main.get_node("Items").get_children():
			it.queue_free()
		var drop = load("res://scenes/dropped_item/dropped_item.tscn")
		var sl: Array = _mat.slots()
		for i in 6:
			var item = drop.instantiate()
			item.kind = ["stone", "stone", "wood", "mortar", "stone", "wood"][i]
			item.position = Vector3(sl[i].x, 0.1, sl[i].z)
			_main.get_node("Items").add_child(item, true)
		_state = 1
		_t = 0
		for s in root.get_tree().get_nodes_in_group("build_sites"):
			if "pending" in s:
				_before[s.name] = s.pending.duplicate() if s.pending is Dictionary else s.pending
		print("loads on mat: ", _mat.loads())
		return false
	if _state == 1 and _t == 5:
		print("loads after 5 frames (full mat -> trip leaves): ", _mat.loads(), " leg=", _mat._leg, " kinds=", _mat._kinds)
		_state = 2
	if _state == 2 and _mat._leg == 2:
		print("porter turned back after ", _t, " frames; loads left on ground: ", _main.get_node("Items").get_child_count())
		for s in root.get_tree().get_nodes_in_group("build_sites"):
			if "pending" in s and s.pending != _before.get(s.name):
				print("  ", s.name, " pending ", _before.get(s.name), " -> ", s.pending)
		_state = 3
	if _state == 3 and _mat._leg == 0:
		print("porter home, hidden: ", not _mat._porter.visible)
		return true
	if _t > 4000:
		print("TIMEOUT leg=", _mat._leg)
		return true
	return false
