extends SceneTree

# Bots, end to end (offline): replay one section with the host standing idle and bots
# doing all the work. Pass = the section stands (WON) before the enemies break through.
#   Godot --headless --path . --script res://tools/bot_test.gd -- [--section=N] [--bots=3] [--skill=2] [--speed=3]
# Prints each day's time and the crew's loads / foes. Settings and progress.cfg are put
# back as they were.
# Network: one `--headless ... -- --host` process (asks for 3 bots, serves) plus one
# `... -- --client`: a person joining a full crew takes a bot's place, so the client must
# see exactly 2 bots, and see them walk and carry. Exit code 0 = it did.

const TIMEOUT := 900.0   # game seconds
const BOT_ID_BASE := 1 << 31   # Player.BOT_ID_BASE — class names aren't usable before the autoloads load

var _section := 0
var _bots := 3
var _skill := 2
var _speed := 3.0
var _main: Node
var _frame := 0
var _t := 0.0
var _saved_count := 0
var _saved_skill := 0
var _saved: PackedByteArray
var _had_progress := false
var _mode := "offline"
var _seen := {}          # client: bot name → [first position, carried something?]

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--section="):
			_section = a.trim_prefix("--section=").to_int()
		elif a.begins_with("--bots="):
			_bots = a.trim_prefix("--bots=").to_int()
		elif a.begins_with("--skill="):
			_skill = a.trim_prefix("--skill=").to_int()
		elif a.begins_with("--speed="):
			_speed = a.trim_prefix("--speed=").to_float()
		elif a == "--host" or a == "--client":
			_mode = a.trim_prefix("--")
	_had_progress = FileAccess.file_exists("user://progress.cfg")
	if _had_progress:
		_saved = FileAccess.get_file_as_bytes("user://progress.cfg")

func _process(delta: float) -> bool:
	_frame += 1
	_t += delta
	var gs := root.get_node("GameState")
	if _t > TIMEOUT:
		print("FAIL: timed out on day %d, %d/%d done" % [gs.current_day, gs.targets_done, gs.targets_total])
		return _finish(1)
	if _mode != "offline":
		return _network(delta)
	if _frame == 1:
		var settings := root.get_node("Settings")
		_saved_count = settings.bot_count
		_saved_skill = settings.bot_skill
		settings.bot_count = _bots
		settings.bot_skill = _skill
		gs.replay_section = _section
		_main = load("res://scenes/main/main.tscn").instantiate()
		root.add_child(_main)
		current_scene = _main
		_main.director.day_tallied.connect(_on_tally)
		return false
	if _frame == 3:
		print("Crew: %d (%d bots, skill %d)" % [gs.crew_size, _bots, _skill])
		Engine.time_scale = _speed
		_main.director.begin()
	if "--trace" in OS.get_cmdline_user_args() and _frame % 60 == 0 and _main:
		for p in _main.players_root.get_children():
			if p.brain != null:
				var b = p.brain
				print("  t=%.0f %s job=%d tgt=%s kind=%s carry=%s pos=(%.1f,%.1f) move=%s path=%d work=%s busy=%s" % [
					_t * _speed, p.name.right(2), b._job, b._target.name if is_instance_valid(b._target) else "-",
					b._fetch_kind, p.carried_kind, p.global_position.x, p.global_position.z, b.move,
					b._path.size(), p._work_site != null, p._is_busy])
				var ch: Array = p._interact_choice(p.global_position)
				print("     choice=%d %s dist=%.2f needs=%s" % [ch[0], ch[1].name if ch[1] else "-",
					b._dist(b._target) if is_instance_valid(b._target) else -1.0,
					b._target.needs(p.carried_kind) if is_instance_valid(b._target) and b._target.has_method("needs") else "?"])
		print("  phase=%d done=%d/%d breaches=%d" % [gs.phase, gs.targets_done, gs.targets_total, gs.breaches])
	match gs.phase:
		gs.Phase.STORY, gs.Phase.DUSK:
			_main.director.force_ready()
		gs.Phase.WON:
			print("PASS: %s stands — %d breaches, %.0f s" % [gs.SECTIONS[_section]["name"], gs.breaches, _t])
			return _finish(0)
		gs.Phase.LOST:
			print("FAIL: lost on day %d" % gs.current_day)
			return _finish(1)
	return false

func _network(_delta: float) -> bool:
	var nm := root.get_node("NetworkManager")
	var gs := root.get_node("GameState")
	if _frame == 1:
		_saved_count = root.get_node("Settings").bot_count
		_saved_skill = root.get_node("Settings").bot_skill
		root.get_node("Settings").bot_count = 3 if _mode == "host" else 0
		root.get_node("Settings").bot_skill = 2
		if _mode == "host":
			nm.host()
			_main = load("res://scenes/main/main.tscn").instantiate()
			root.add_child(_main)
			current_scene = _main
		else:
			nm.join("127.0.0.1")
		return false
	if _main == null:
		if root.multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED 				and root.multiplayer.get_unique_id() != 1:
			_main = load("res://scenes/main/main.tscn").instantiate()
			root.add_child(_main)
			current_scene = _main
		elif _t > 20.0:
			print("FAIL: never connected")
			return _finish(1)
		return false
	var players: Array = _main.players_root.get_children()
	var bots := players.filter(func(p): return p.name.to_int() >= BOT_ID_BASE)
	if _mode == "host":
		if players.size() - bots.size() >= 2 and gs.phase == gs.Phase.GATHER:
			print("Host: client in, %d bots — beginning" % bots.size())
			_main.director.begin()
		if gs.phase in [gs.Phase.STORY, gs.Phase.DUSK]:
			_main.director.force_ready()
		if _t > 70.0:
			return _finish(0)
		return false
	for b in bots:
		if not _seen.has(b.name):
			_seen[b.name] = [b.global_position, false]
		if not b.carried_kind.is_empty():
			_seen[b.name][1] = true
	if _t > 45.0:
		var moved := bots.filter(func(b): return b.global_position.distance_to(_seen[b.name][0]) > 3.0).size()
		var carried := bots.filter(func(b): return _seen[b.name][1]).size()
		# The crew list (NetworkManager.crew_info): both people, neither still loading
		var info: Dictionary = nm.crew_info
		var listed: bool = info.size() == 2 and info.has(1) and info.has(root.multiplayer.get_unique_id()) \
			and nm.loading_peers().is_empty()
		var ok := bots.size() == 2 and moved == 2 and carried >= 1 and listed
		print(("PASS" if ok else "FAIL") + ": client sees %d bots, %d moved, %d carried; crew %d; crew list %s" % [
			bots.size(), moved, carried, gs.crew_size, info])
		return _finish(0 if ok else 1)
	return false

func _on_tally(stats: Dictionary) -> void:
	var rows: Array = stats["crew"].map(func(r): return "%s: %d loads, %d foes" % [
		"bot" if r[0] >= BOT_ID_BASE else "host", r[1], r[2]])
	print("Day %d: %.0f s, %d breaches — %s" % [root.get_node("GameState").current_day,
		stats["time"], stats["breaches"], ", ".join(rows)])
	if stats.has("marks"):
		print("Section: %.0f s, %d loads, %d foes, %d breaches" % [stats["section_time"],
			stats["section_loads"], stats["section_foes"], stats["section_breaches"]])

func _finish(code: int) -> bool:
	Engine.time_scale = 1.0
	var settings := root.get_node("Settings")
	settings.bot_count = _saved_count
	settings.bot_skill = _saved_skill
	if _had_progress:
		var f := FileAccess.open("user://progress.cfg", FileAccess.WRITE)
		f.store_buffer(_saved)
		f.close()
	elif FileAccess.file_exists("user://progress.cfg"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://progress.cfg"))
	quit(code)
	return true
