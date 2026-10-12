extends SceneTree

# Settings → Advanced → Figures, switched in the middle of a day: every figure is rebuilt at
# the new build, and what the player carries stays at the chest. Nothing is saved.
#   Godot --path . --script res://tools/figures_switch_test.gd -- --nostory
# Prints PASS / FAIL.

var _main: Node3D
var _frame := 0
var _ok := true

func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _check(what: String, cond: bool) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	_ok = _ok and cond

func _process(_delta: float) -> bool:
	_frame += 1
	var settings: Node = root.get_node("Settings")
	var p: Node3D = _main.get_node("Players").get_child(0)
	match _frame:
		3:
			_main.director.begin()
		30:
			p.carried_kind = "stone"
			p._rebuild_carry_prop()
			_check("starts short", p._sprite._grown == 0.0)
		40:
			settings.tall_figures = true
		45:
			_check("tall after the switch", p._sprite._grown == 1.0)
			_check("the load is still at the chest", is_instance_valid(p._carry_front) and p._carry_front.is_inside_tree()
				and p._carry_front.get_parent() == p._sprite.carry_anchor())
			var all_tall := true
			for r in get_nodes_in_group(&"character_rigs"):
				all_tall = all_tall and r._grown == 1.0
			_check("every figure rebuilt (%d)" % get_nodes_in_group(&"character_rigs").size(), all_tall)
			settings.tall_figures = false
		50:
			_check("short again", p._sprite._grown == 0.0)
			_check("…load still held", is_instance_valid(p._carry_front) and p._carry_front.is_inside_tree())
		60:
			print("PASS" if _ok else "FAIL")
			return true
	return false
