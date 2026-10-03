extends SceneTree

# Section landmarks against everything else on the ground, offline:
#   Godot --headless --path . --script res://tools/layout_test.gd
# Builds every section and lists each landmark piece (SectionTerrain) that crowds the
# wall line, the spawn line, a worker spot or the work camp (ScatterLayer). Debug build only.
# Exit code 0 = nothing crowded.

var _main: Node3D
var _frame := 0

func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	var gs: Node = root.get_node("GameState")
	var terrain: Node3D = _main.get_node("SectionTerrain")
	var total := 0
	for i in gs.SECTIONS.size():
		gs.current_day = gs.SECTIONS[i]["days"][0]   # the yard's layout follows the day
		gs.current_section_index = i
		gs.section_changed.emit(i)
		var lines: Array[String] = terrain.crowded
		print(("PASS  " if lines.is_empty() else "FAIL  ") + "%s (%s)" % [gs.SECTIONS[i]["name"], gs.SECTIONS[i].get("terrain", "-")])
		for line in lines:
			print("      " + line)
		if not lines.is_empty():
			print("      worker spots: %s" % [terrain.keep_clear()])
		total += lines.size()
	print("layout_test: %d crowded" % total)
	quit(1 if total else 0)
	return true
