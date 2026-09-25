extends SceneTree

# End-to-end check of the carry → deliver → build loop:
#   offline:  Godot --path . --script res://tools/build_test.gd -- --nostory <out_dir>
#   network:  one `--headless ... -- --nostory --host <dir>` process plus one
#             `... -- --nostory --client <dir>` — the client plays, the host serves
# Teleports the player between the supply piles and today's first wall, pressing
# interact like a player would, and prints how long each stage's work took.
# Saves a screenshot mid-work. Exit code 0 = the day's first unit got fully built.

const TIMEOUT := 90.0
const HOST_LIFETIME := 80.0

var _out := ""
var _main: Node3D
var _t := 0.0
var _frame := 0
var _player: Node3D
var _site: Node3D
var _state := "wait"
var _wait := 0.0
var _work_started := -1.0
var _shots := 0
var _shot_phase := 0
var _stages := 0
var _mode := "offline"

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--host":
			_mode = "host"
		elif a == "--client":
			_mode = "client"
		elif not a.begins_with("--"):
			_out = a
	root.size = Vector2i(1920, 1080)
	if _mode == "offline":
		_start_main()

func _start_main() -> void:
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(delta: float) -> bool:
	_frame += 1
	var nm = root.get_node("NetworkManager")
	if _frame == 2 and _mode == "host":
		nm.host()
		_start_main()
	elif _frame == 2 and _mode == "client":
		nm.join("127.0.0.1")
	if _mode == "client" and _main == null:
		# Status flips to connected a moment before the server hands out our peer id
		if root.multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED 				and root.multiplayer.get_unique_id() != 1:
			_start_main()
		return false
	if _mode == "host" and _main != null:
		_t += delta
		# Begin once the client's player exists; then just serve
		if _main.get_node("Players").get_child_count() >= 2 and root.get_node("GameState").phase == 5:
			_main.director.begin()
		if _t > HOST_LIFETIME:
			quit(0)
			return true
		return false
	if _frame == 3 and _mode == "offline":
		_main.director.begin()
	if _frame < 3 or _main == null:
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
			if gs.phase == gs.Phase.WORK:
				_player = _main.get_node("Players").get_node_or_null(str(root.multiplayer.get_unique_id()))
				if _player == null:
					print("players: ", _main.get_node("Players").get_children().map(func(n): return n.name), " me=", root.multiplayer.get_unique_id())
					quit(1)
					return true
				_site = _pick_site()
				print("site: ", _site.name, "  active_build=", gs.active_build)
				_state = "next"
		"next":
			if gs.phase == gs.Phase.DUSK:
				print("PASS: day's work done, %d stages, t=%.1f s" % [_stages, _t])
				quit(0)
				return true
			if _site == null or _site.is_complete() or (_site.next_need() == "" and not _site.can_build()):
				_site = _pick_site()
				if _site == null:
					return false   # waiting on the director
				print("site: ", _site.name)
			if _site.can_build():
				_goto(_site)
				_press()
				_state = "working"
				_work_started = _t
				_shot_phase = 0
				_wait = 0.2
			else:
				var need: String = _site.next_need()
				var pile := _pile_for(need)
				if pile == null:
					print("FAIL: no pile for ", need)
					quit(1)
					return true
				_goto(pile)
				_press()
				_state = "deliver"
				_wait = 0.3
		"deliver":
			if _player.carried_kind.is_empty():
				print("FAIL: pickup failed")
				quit(1)
				return true
			_goto(_site)
			_press()
			_state = "after_deliver"
			_wait = 0.3
		"after_deliver":
			if not gs.active_build or not _site.can_build() or _player._work_site == null:
				_state = "next"
			else:
				_state = "working"
				_work_started = _t
				_shot_phase = 0
		"working":
			var prog: float = _site.work().progress
			if _shots < 12 and prog > 0.25 * (1 + _shot_phase) and _shot_phase < 3:
				_shot_phase += 1
				_shots += 1
				_player.get_viewport().get_texture().get_image().save_png("%s/work_%02d.png" % [_out, _shots])
			if _player._work_site == null:
				_stages += 1
				print("  stage %d raised after %.2f s of work (stage=%s)" % [_stages, _t - _work_started, str(_site.get("stage"))])
				_state = "next"
	return false

func _pick_site() -> Node3D:
	for s in _main.get_tree().get_nodes_in_group("build_sites"):
		if s.get("is_target") and s.has_method("work") and s.work() != null and not s.is_complete() \
				and s.next_need() != "":
			return s
	return null

func _pile_for(kind: String) -> Node3D:
	for p in _main.get_tree().get_nodes_in_group("supply_piles"):
		if p.kind == kind:
			return p
	return null

func _goto(n: Node3D) -> void:
	var p: Vector3 = n.approach_point(_player.global_position, 0.6) if n.has_method("approach_point") \
		else n.global_position + Vector3(0, 0, 1.2)
	_player.global_position = Vector3(p.x, 0.1, p.z)
	_player.velocity = Vector3.ZERO

func _press() -> void:
	# The player reads just_pressed in _physics_process; hold for one tick
	Input.action_press("interact")
	await create_timer(0.05).timeout
	Input.action_release("interact")
