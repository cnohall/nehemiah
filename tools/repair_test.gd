extends SceneTree

# Mending a battered wall (GDD §5.17):
#   Godot --path . --script res://tools/repair_test.gd
# Forces a finished wall down to low health, then plays it like a player: take mortar,
# deliver it, work it. Exit 0 = health rose by REPAIR_GAIN and the mortar was used up.

const TIMEOUT := 60.0

var _main: Node3D
var _player: Node3D
var _site: Node3D
var _t := 0.0
var _frame := 0
var _wait := 0.0
var _state := "wait"
var _before := 0.0

var _out := ""
var _shots := 0

func _shoot(tag: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, tag])

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	root.size = Vector2i(1280, 720)
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
	if _t > TIMEOUT:
		print("FAIL: timed out in state ", _state)
		quit(1)
		return true
	_wait -= delta
	if _wait > 0.0:
		return false
	var gs = root.get_node("GameState")
	match _state:
		"wait":
			if gs.phase != gs.Phase.WORK:
				return false
			_player = _main.get_node("Players").get_node_or_null(str(root.multiplayer.get_unique_id()))
			for s in _main.get_tree().get_nodes_in_group("wall_sections"):
				if s.get("is_target") and not s.decorative:
					_site = s
					break
			if _player == null or _site == null:
				print("FAIL: no player/site")
				quit(1)
				return true
			_site.stage = _site.Stage.MORTARED
			_site.pending = _site._empty_pending()
			_site.health = _site.MAX_HEALTH
			if _site.repairing() or _site.needs("mortar") or _site.can_build():
				print("FAIL: a healthy wall wants mending")
				quit(1)
				return true
			_site.health = _site.MAX_HEALTH * 0.4
			_before = _site.health
			if not _site.repairing() or not _site.needs("mortar") or _site.needs("stone") or _site.can_build():
				print("FAIL: battered wall state wrong repairing=%s needs=%s can=%s" % [_site.repairing(), _site.needs("mortar"), _site.can_build()])
				quit(1)
				return true
			print("site ", _site.name, " health ", _before, " work_time ", _site.work().work_time)
			if _out != "":
				_player.global_position = _site.approach_point(_site.global_position + Vector3(0, 0, 4), 1.5)
				_state = "shoot"
				_wait = 1.0   # let the camera settle
			else:
				_state = "fetch"
		"shoot":
			_shoot("battered")
			_state = "fetch"
		"fetch":
			var pile := _pile("mortar")
			if pile == null:
				print("FAIL: no mortar pile")
				quit(1)
				return true
			_goto(pile)
			_press()
			_state = "carry"
			_wait = 0.4
		"carry":
			if _player.carried_kind != "mortar":
				print("FAIL: did not pick up mortar (carried '%s')" % _player.carried_kind)
				quit(1)
				return true
			_goto(_site)
			_press()
			_state = "deliver"
			_wait = 0.4
		"deliver":
			if not _player.carried_kind.is_empty() or _site.pending.get("mortar", 0) + (1 if _player._work_site != null else 0) < 1:
				print("FAIL: mortar not delivered (carried '%s' pending %s)" % [_player.carried_kind, _site.pending])
				quit(1)
				return true
			_state = "working"
		"working":
			if _out != "" and _shots < 2 and _site.work().progress > 0.3 * (_shots + 1):
				_shots += 1
				_shoot("work_%d" % _shots)
			if _player._work_site == null and _site.health > _before:
				var gain: float = _site.health - _before
				var want: float = _site.MAX_HEALTH * _site.REPAIR_GAIN
				if absf(gain - want) < 0.01 and _site.pending.get("mortar", 0) == 0:
					print("PASS: mended %.0f -> %.0f in %.1f s" % [_before, _site.health, _t])
					quit(0)
				else:
					print("FAIL: gain %.1f want %.1f pending %s" % [gain, want, _site.pending])
					quit(1)
				return true
	return false

func _pile(kind: String) -> Node3D:
	for p in _main.get_tree().get_nodes_in_group("supply_piles"):
		if p.kind == kind:
			return p
	return null

func _goto(n: Node3D) -> void:
	var from := Vector3(n.global_position.x, 0.1, n.global_position.z + 4.0)
	var p: Vector3 = n.approach_point(from, 0.6) if n.has_method("approach_point") \
		else n.global_position + Vector3(0, 0, 1.2)
	_player.global_position = Vector3(p.x, 0.1, p.z)
	_player.velocity = Vector3.ZERO

func _press() -> void:
	Input.action_press("interact")
	await create_timer(0.05).timeout
	Input.action_release("interact")
