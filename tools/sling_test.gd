extends SceneTree

# The sling pass (GDD §5.16), offline, no bots:
#   Godot --path . --script res://tools/sling_test.gd -- --nostory [<out_dir>]
# - true_offset: glints at full charge and every TRUE_PERIOD after
# - the tell: a scout draws back before the blow; it lands if you stand there, finds air
#   if you step out of reach, and is knocked aside by a hit in the draw
# - a brute shrugs off a light blow mid-draw, not a solid one
# - a true shot strikes ×1.5 and knocks the foe off his feet; a plain one only shoves
# - `GameState.true_shot` off: a "true" release is a plain throw
# - a sword cut in the draw turns the blow: ×RIPOSTE_MULT and off his feet, even a brute;
#   with `GameState.riposte` off it only knocks the strike aside
# Screenshots (out_dir): the draw, the aim ring with the closing ring, a foe knocked down,
# a turned blow.
# Exit code 0 = every check passed.

var _out := ""
var _main: Node3D
var _frame := 0
var _t := 0.0
var _mark := 0.0
var _state := "wait_work"
var _player: Node3D
var _foe: Node3D
var _hp := 0.0
var _foe_hp := 0.0
var _foe_at := Vector3.ZERO
var _fails := 0
var _gs: Node
# Loaded once the game is up: a --script harness compiles before the autoloads exist, so
# it can't name the game's classes directly
var _P: GDScript
var _E: GDScript
var _T: GDScript

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	root.size = Vector2i(1920, 1080)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_main.fit_bots(0)
		_main.director.begin()
	if _frame < 3:
		return false
	if _P == null:
		_P = load("res://scenes/player/player.gd")
		_E = load("res://scenes/enemy/enemy.gd")
		_T = load("res://scenes/shared/trade.gd")
	_t += delta
	_gs = root.get_node("GameState")
	# Only the foe under test
	for e in _main.get_node("Enemies").get_children():
		if e != _foe:
			e.queue_free()
	if _player != null:
		_player.health = _P.MAX_HEALTH if _state != "stand" else _player.health
	if _t > 120.0:
		_fail("timed out in " + _state)
		return _finish()
	match _state:
		"wait_work":
			if _gs.phase == _gs.Phase.WORK:
				_player = _main.get_node("Players").get_child(0)
				_player.global_position = Vector3(0.0, 0.1, -4.0)
				_check(is_zero_approx(_P.true_offset(_P.SLING_CHARGE_TIME)), "a glint at full charge")
				_check(absf(_P.true_offset(_P.SLING_CHARGE_TIME + _P.TRUE_PERIOD * 2.0)) < 0.001, "…and every beat after")
				_check(_P.true_offset(_P.SLING_CHARGE_TIME + 0.3) > _P.TRUE_HALF, "between beats is outside the window")
				_check(_P.true_offset(0.5) < -_P.TRUE_HALF, "before full charge is outside the window")
				_spawn(0, Vector3(1.1, 0, -1.1))
				_state = "stand"
		"stand":
			# Stand still through the draw: the blow lands at its end, not at its start
			if _bracing():
				if _mark == 0.0:
					_mark = _t
					_hp = _player.health
					_shot("sling_brace")
				elif _t - _mark > 0.1 and _t - _mark < _E.TELL[0] - 0.1:
					_check(_player.health == _hp, "no harm while he draws back")
					_mark = -1.0
			elif _mark == -1.0 and _player.health < _hp:
				_check(true, "the blow lands after the draw (%.0f → %.0f)" % [_hp, _player.health])
				_next("dodge")
		"dodge":
			_player.health = _P.MAX_HEALTH
			if _bracing() and _mark == 0.0:
				_mark = _t
				_player.global_position += Vector3(-3.5, 0, 0)   # a dash out of reach
			elif _mark > 0.0 and _t - _mark > _E.TELL[0] + 0.2:
				_check(_player.health == _P.MAX_HEALTH, "stepped out of reach: the spear finds air")
				_player.global_position = _foe.global_position + Vector3(1.2, 0, 0)
				_next("interrupt")
		"interrupt":
			_player.health = _P.MAX_HEALTH
			if _bracing() and _mark == 0.0:
				_mark = _t
				_foe.take_damage(4.0, 1)
				_check(String(_foe.anim).begins_with("reel"), "a hit in the draw knocks the strike aside (%s)" % _foe.anim)
			elif _mark > 0.0 and _t - _mark > _E.TELL[0] + 0.2:
				_check(_player.health == _P.MAX_HEALTH, "…and no blow lands")
				_foe.queue_free()
				_foe = null
				_spawn(1, Vector3(1.3, 0, 0))
				_next("brute")
		"brute":
			_player.health = _P.MAX_HEALTH
			if _bracing() and _mark == 0.0:
				_mark = _t
				_foe.take_damage(10.0, 1)
				_check(String(_foe.anim).begins_with("brace") and _foe._tell > 0.0, "a brute shrugs off a pebble mid-draw")
				_foe.take_damage(_E.STEADY[1], 1)
				_check(String(_foe.anim).begins_with("reel"), "…but not a solid blow")
				_next("true_shot")
		"true_shot":
			# A brute well off, so the shot's knock is clear; full charge, released on the glint
			if _mark == 0.0:
				_mark = _t
				_foe.queue_free()
				_foe = null
				_spawn(1, Vector3(4.2, 0, -4.2))   # off to the screen-right, clear of the herald
				_foe._pace = 0.0   # stands his ground (still knocked about) for the shot
				_player.set_physics_process(false)
				_show_aim()
			elif _t - _mark > 0.15 and _foe_hp == 0.0:
				_foe_hp = _foe.health
				_foe_at = _foe.global_position
				_player._server_sling.rpc_id(1, _player.global_position, _foe.global_position, 1.0, false, true)
				_mark = _t
				_shot_at(0.15, "sling_flight")
				_shot_at(0.4, "sling_impact")
			elif _foe_hp > 0.0 and _t - _mark > 0.75:
				var took: float = _foe_hp - _foe.health
				var plain: float = _P.SLING_MAX_DAMAGE * _T.hit_mult(_player.trade)
				_check(absf(took - plain * _P.TRUE_MULT) < 0.5, "a true shot strikes ×%.1f (%.1f)" % [_P.TRUE_MULT, took])
				_check(String(_foe.anim).begins_with("knocked"), "…and knocks him off his feet (%s)" % _foe.anim)
				var pushed: float = _flat(_foe.global_position - _player.global_position) - _flat(_foe_at - _player.global_position)
				_check(pushed > 0.2, "…thrown back %.2f m" % pushed)
				_shot("sling_knocked")
				_next("plain")
		"plain":
			if _mark == 0.0:
				_mark = _t
				_foe_hp = _foe.health
				_gs.true_shot = false
				_player._server_sling.rpc_id(1, _player.global_position, _foe.global_position, 1.0, false, true)
			elif _t - _mark > 2.0:
				var took: float = _foe_hp - _foe.health
				var plain: float = _P.SLING_MAX_DAMAGE * _T.hit_mult(_player.trade)
				_check(absf(took - plain) < 0.5, "true shots off: a plain throw (%.1f)" % took)
				_check(not String(_foe.anim).begins_with("knocked"), "…that doesn't knock him down (%s)" % _foe.anim)
				_gs.true_shot = true
				_foe.queue_free()
				_foe = null
				_player.set_physics_process(true)
				_spawn(1, Vector3(1.3, 0, 0))
				_next("riposte")
		"riposte":
			# A sword cut in a brute's draw: struck ×RIPOSTE_MULT and off his feet
			_player.health = _P.MAX_HEALTH
			if _bracing() and _mark == 0.0:
				_mark = _t
				_foe_hp = _foe.health
				_cut()
				_shot_at(0.05, "sword_riposte")
				_shot_at(0.12, "sword_riposte2")
			elif _mark > 0.0 and _foe_hp > 0.0 and _t - _mark > 0.1:
				var took: float = _foe_hp - _foe.health
				var cut: float = _P.SWORD_DAMAGE * _T.hit_mult(_player.trade) * _P.RIPOSTE_MULT
				_check(absf(took - cut) < 0.5, "a cut in the draw strikes ×%.1f (%.1f)" % [_P.RIPOSTE_MULT, took])
				_check(String(_foe.anim).begins_with("knocked"), "…and takes even a brute off his feet (%s)" % _foe.anim)
				_foe.queue_free()
				_foe = null
				_spawn(0, Vector3(1.2, 0, 0))
				_gs.riposte = false
				_next("riposte_off")
		"riposte_off":
			_player.health = _P.MAX_HEALTH
			if _bracing() and _mark == 0.0:
				_mark = _t
				_foe_hp = _foe.health
				_cut()
			elif _mark > 0.0 and _foe_hp > 0.0 and _t - _mark > 0.1:
				var took: float = _foe_hp - _foe.health
				var cut: float = _P.SWORD_DAMAGE * _T.hit_mult(_player.trade)
				_check(absf(took - cut) < 0.5, "riposte off: a plain cut (%.1f)" % took)
				_check(String(_foe.anim).begins_with("reel"), "…that only knocks the strike aside (%s)" % _foe.anim)
				_gs.riposte = true
				return _finish()
	return false

func _spawn(type: int, off: Vector3) -> void:
	_main.get_node("WaveManager")._do_spawn(type, _player.global_position + off)
	for e in _main.get_node("Enemies").get_children():
		if e.type == type and not e.is_queued_for_deletion():
			_foe = e

# The server's half of a sword cut, straight at the foe under test
func _cut() -> void:
	var d: Vector3 = _foe.global_position - _player.global_position
	_player._server_sword.rpc_id(1, _player.global_position, atan2(d.x, d.z))

func _bracing() -> bool:
	return is_instance_valid(_foe) and String(_foe.anim).begins_with("brace")

# The owner's aim, as if whirling just before a glint: aim ring, closing ring, dotted arc
func _show_aim() -> void:
	_player._charge = 1.0
	_player._held = _P.SLING_CHARGE_TIME + _P.TRUE_PERIOD - 0.2
	_player._update_aim(_foe.global_position)
	_check(_player._approach.visible, "a ring closes on the aim ring before the glint")
	_check(_player._arc_dots[0].visible, "the flight arc is drawn")
	_diag()

func _diag() -> void:
	for i in 4:
		_player._update_aim(_foe.global_position)
		await process_frame
	await _shot("sling_aim")
	_player._cancel_charge()

func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()

func _shot_at(after: float, name: String) -> void:
	if _out == "":
		return
	await create_timer(after).timeout
	_shot(name)

func _next(state: String) -> void:
	_state = state
	_mark = 0.0
	_foe_hp = 0.0

func _shot(name: String) -> void:
	if _out == "":
		return
	await process_frame
	root.get_texture().get_image().save_png(_out + "/" + name + ".png")

func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1

func _fail(what: String) -> void:
	_check(false, what)

func _finish() -> bool:
	print("sling_test: %d failed" % _fails)
	quit(1 if _fails else 0)
	return true
