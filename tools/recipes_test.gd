extends SceneTree

# Per-unit recipes (Jeshanah: old + burned units) and the Broad Wall's two faces, offline:
#   Godot --headless --path . --script res://tools/recipes_test.gd -- --nostory --day=9
#   Godot --headless --path . --script res://tools/recipes_test.gd -- --nostory --day=13
# Exit code 0 = every check passed.

var _main: Node3D
var _frame := 0
var _t := 0.0
var _fails := 0
var _done := false

func _initialize() -> void:
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_main.director.begin()
	if _frame < 3:
		return false
	_t += delta
	var gs = root.get_node("GameState")
	if gs.phase == gs.Phase.WORK and not _done:
		_done = true
		_main.get_node("WaveManager").stop()
		gs.sun_left = 999.0
		match gs.current_section_index:
			2:
				_jeshanah()
			3:
				_broad_wall()
			_:
				_fail("run with --day=9 or --day=13")
		print("recipes_test: ", "FAIL" if _fails > 0 else "PASS")
		quit(1 if _fails > 0 else 0)
		return true
	if _t > 40.0:
		_fail("timed out")
		quit(1)
		return true
	return false

func _jeshanah() -> void:
	var old: Node = _main.get_node("Wall/Section1")
	var burned: Node = _main.get_node("Wall/Section3")
	var plain: Node = _main.get_node("Wall/Section4")
	_check(old.stage == old.Stage.STACKED, "old unit starts with its courses standing (%d)" % old.stage)
	_check(old.needs("mortar") and not old.needs("stone"), "old unit wants mortar only")
	_check(not plain.is_built() and plain.needs("wood") or plain.needs("beam"), "plain unit starts bare")
	_check(not burned.cleared and burned.can_build(), "burned unit has charred framing to clear")
	_check(not burned.needs("wood") and not burned.needs("beam") and not burned.needs("stone"), "burned unit takes no loads before it is cleared")
	_check(burned.next_need() == "" and burned.work_material() == "wood", "clearing is pure work")
	_check(burned.try_build() and burned.cleared and not burned.is_built(), "clearing it leaves bare footing")
	_check(burned.needs("wood") or burned.needs("beam"), "a cleared unit is built as usual")
	# A knocked-down old unit loses its courses like any other
	burned.stage = burned.Stage.FRAMED
	burned.reset_slot()
	_check(not burned.cleared, "a fresh section burns it again")

func _broad_wall() -> void:
	var wall: Node = _main.get_node("Wall/Section3")
	_check(wall.is_thick(), "Section3 is a thick wall")
	wall.stage = wall.Stage.FRAMED
	var cost: Dictionary = wall.cost_for(wall.Stage.STACKED)
	var per_face: int = cost["stone"]
	_check(wall.face_name() == "Outer face", "outer face first (%s)" % wall.face_name())
	for i in per_face:
		wall.deposit("stone", 1)
	_check(wall.can_build(), "outer face paid for")
	_check(wall.try_build() and wall.stage == wall.Stage.FRAMED and wall.face == 1, "the outer face stands, the stage does not move yet")
	_check(wall.face_name() == "Inner face" and wall.needs("stone"), "the inner face wants its own stone")
	for i in per_face:
		wall.deposit("stone", 1)
	_check(wall.try_build() and wall.stage == wall.Stage.STACKED, "both faces raise the stone stage")
	_check(wall.face_name() == "" and wall.needs("mortar"), "then the core is mortared")
	wall.take_damage(wall.MAX_HEALTH * 4.0)
	_check(wall.stage == wall.Stage.FRAMED and wall.face == 0, "a knock back to the timber takes both faces")

func _check(ok: bool, what: String) -> void:
	print("  ", "ok   " if ok else "FAIL ", what)
	if not ok:
		_fails += 1

func _fail(what: String) -> void:
	_check(false, what)
