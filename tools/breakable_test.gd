extends SceneTree

# Breakable jars and baskets (Breakables), offline:
#   Godot --headless --path . --script res://tools/breakable_test.gd
# - every section lays some out, none on a worker's spot, a landmark or the wall strip
# - a sword cut, a sling stone, a dash and a foe walking through each break one
# - a worker next to one with no foe about gets the sword for it; with a foe in range, not
# - standing beside one rocks it once, not over and over
# - dawn puts them all back
# Exit code 0 = every check passed.

var _main: Node3D
var _gs: Node
var _set: Node3D
var _frame := 0
var _state := "layout"
var _fails := 0
var _fake: Node3D
var _mark := 0
var _mark_ms := 0
var _player: Node3D
var _trampled: Node3D
var _dashed: Node3D

func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	if _frame == 3:
		_gs = root.get_node("GameState")
		_set = _main.get_node("Breakables")
		_player = _main.get_node("Players").get_child(0)
	if Time.get_ticks_msec() > 60000:
		_check(false, "timed out in " + _state)
		return _finish()
	match _state:
		"layout":
			var terrain: Node3D = _main.get_node("SectionTerrain")
			for i in _gs.SECTIONS.size():
				_gs.current_section_index = i
				_gs.section_changed.emit(i)
				var pieces: Array = _set._pieces
				var bad := []
				for p: Node3D in pieces:
					var at := Vector2(p.global_position.x, p.global_position.z)
					if absf(at.y) < 3.0 or terrain.blocks(at, 0.0):
						bad.append(at)
					for k: Vector2 in terrain.keep_clear():
						if k.distance_to(at) < 1.2:
							bad.append(at)
				_check(pieces.size() >= 12 and bad.is_empty(), "%s: %d pieces, misplaced %s" % [_gs.SECTIONS[i]["name"], pieces.size(), bad])
			_gs.current_section_index = 0
			_gs.section_changed.emit(0)
			_state = "sword"
		"sword":
			var p: Node3D = _set._pieces[0]
			var from := p.global_position - Vector3(1.2, 0, 0)
			_check(_set.smash_arc(from, Vector2(1, 0), 2.4, 65.0) and p.broken, "sword cut breaks one")
			var q: Node3D = _set._pieces.filter(func(x): return not x.broken)[0]
			_check(_set.smash_at(q.global_position + Vector3(0.3, 0, 0), 0.5) and q.broken, "sling stone breaks one")
			# Pot at the feet, no foe: the attack press is a sword cut at it
			var r: Node3D = _set._pieces.filter(func(x): return not x.broken)[0]
			_mark = _set._pieces.find(r)
			_player.global_position = r.global_position + Vector3(0.9, 0, 0)
			var near: Node3D = _player._pot_in_reach()
			_check(near != null and _player.global_position.distance_to(near.global_position) - near.radius() < _player.POT_REACH,
				"pot at the feet takes the cut")
			_fake = Node3D.new()
			_fake.add_to_group("enemies")
			_main.add_child(_fake)
			_fake.global_position = _player.global_position + Vector3(6, 0, 0)
			_check(_player._pot_in_reach() == null, "not with a foe in sling range")
			# A foe walks through the one at the feet
			_fake.global_position = r.global_position + Vector3(0.1, 0, 0)
			_trampled = r
			_mark_ms = Time.get_ticks_msec()
			_state = "trample"
		"trample":
			# Waits by the clock: headless process frames outrun the physics ticks
			if not _trampled.broken and _since() < 0.5:
				return false
			var r: Node3D = _trampled
			_check(r.broken, "foe tramples one")
			_fake.queue_free()
			var d: Node3D = _set._pieces.filter(func(x): return not x.broken)[0]
			_player.global_position = d.global_position - Vector3(2, 0, 0)
			_set.note_dash(_player)
			_player.global_position = d.global_position + Vector3(2, 0, 0)
			_set._check_dashes()
			_check(d.broken, "dash through one breaks it")
			# Standing at a jar's side rocks it once, not over and over
			var s: Node3D = _set._pieces.filter(func(x): return not x.broken)[0]
			_dashed = s
			_player.global_position = s.global_position + Vector3(s.radius() + 0.2, 0, 0)
			_mark_ms = Time.get_ticks_msec()
			_state = "lean"
		"lean":
			if _dashed._wobble_cd == 0.0 and _since() < 0.3:
				return false
			_check(_dashed._wobble_cd > 0.0, "brushing up to one rocks it")
			_state = "stand"
		"stand":
			if _since() < 1.2:
				return false
			_check(_dashed._wobble_cd == 0.0 and _player.global_position.distance_to(_dashed.global_position) < _dashed.radius() + 0.35,
				"standing beside one doesn't keep rocking it")
			_gs.set_phase(_gs.Phase.DAWN)
			var whole: bool = _set._pieces.all(func(p): return not p.broken)
			_check(whole, "dawn puts them back")
			return _finish()
	return false

func _since() -> float:
	return (Time.get_ticks_msec() - _mark_ms) / 1000.0

func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1

func _finish() -> bool:
	print("breakable_test: %d failed" % _fails)
	quit(1 if _fails else 0)
	return true
