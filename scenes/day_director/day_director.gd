extends Node

# Server-side day loop (GDD "sprint model"):
#   GATHER — before day 1: players join and walk around, nothing spawns
#   STORY — story cards before the day (StoryData); waits until every reader is through
#   DAWN  — today's wall units are marked, short breather, no spawns
#   WORK  — enemies stream in; day ends when every target unit is fully built
#   DUSK  — enemies flee, the crew cheers, the day's tally shows; then the next day begins
# Moving into a new circuit section (Nehemiah 3) resets the wall to bare foundations.

const DAWN_TIME        := 5.0
const DUSK_TIME        := 9.0   # long enough to read the tally (title screen: nobody to wait for)
const DUSK_MIN         := 4.0   # the cheer plays out even if everyone is ready at once
const CELEBRATE_STEP   := 0.12  # seconds between each finished unit's flourish
const NAV_REBAKE_DELAY := 0.4
const REPAIR_ON_DAWN   := 0.5   # fraction of lost health restored overnight
const SUN_RESYNC       := 2.0   # seconds between sun-clock corrections to clients

# Every peer: Main shows/hides the StoryPlayer on these
signal story_started(day: int)
signal story_ended
# Every peer: who the story / tally is still waiting on ("story" | "tally" | "" = none)
signal ready_changed(kind: String, waiting: Array)
# Every peer: end-screen picks so far, peer_id → "again" | "next"
signal votes_changed(votes: Dictionary)
# Every peer: the day's numbers, for the dusk tally card
signal day_tallied(stats: Dictionary)

# Build order within a section: the named gate first, then outward (WorkFront)
const UNIT_ORDER := WorkFront.UNIT_ORDER

@onready var _wall: Node3D                = get_parent().get_node("Wall")
@onready var _waves: Node                 = get_parent().get_node("WaveManager")
@onready var _enemies: Node3D             = get_parent().get_node("Enemies")
@onready var _items: Node3D               = get_parent().get_node("Items")
@onready var _nav: NavigationRegion3D     = get_parent().get_node("NavRegion")

var _units: Array = []     # each unit = Array of wall sections (gate = both pillars)
var _targets: Array = []   # units that must be finished today
var _timer := 0.0
var _nav_rebake_in := -1.0
var _story_day := 0          # server: last day whose story has played
# Server: a ready check between days — the story ("story") or the dusk tally ("tally")
# waits until every peer in the scene is through. peer_id → true while not yet ready.
var _wait_kind := ""
var _waiting := {}
var _votes := {}   # server: end-screen picks, peer_id → "again" | "next"
# Server: today's numbers. "crew" is peer_id → { loads, foes }
var _stats := {}
var _breaches_at_dawn := 0
# Server: this section so far, for its rating
var _section_time := 0.0
var _section_breaches := 0   # GameState.breaches when the section began
var _section_ono := 0        # workers who went with the messenger ("schemes")
# Server: loads each worker brought to each unit this section — unit index → { peer_id: loads }.
# When the stretch stands, each piece is carved with the name of the one who carried most.
var _credit := {}
var _sun_resync := 0.0

func _ready() -> void:
	add_to_group("day_director")
	_reset_stats()
	GameState.phase_changed.connect(_on_phase_changed)
	for unit_name: String in UNIT_ORDER:
		var node := _wall.get_node(unit_name)
		# A gate is its pillars plus itself (the doors step); a wall is just itself
		var parts: Array = node.get_children().filter(func(c): return c.has_method("try_build"))
		if node.has_method("try_build"):
			parts.append(node)
		_units.append(parts)
		for part in parts:
			part.stage_changed.connect(_on_stage_changed.unbind(1))
	# Parse the tagged scene roots (floor, wall, supplies, houses) rather than the
	# region's own (empty) children. Set here: the .tscn key doesn't round-trip.
	_nav.navigation_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	_nav.navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	GameState.game_lost.connect(_on_game_over)
	GameState.game_won.connect(_on_game_over)
	NetworkManager.peer_disconnected.connect(_on_peer_left)
	set_process(multiplayer.is_server())

## Server: open the session — the crew gathers until the host calls begin()
func start() -> void:
	GameState.reset()
	GameState.apply_replay()
	GameState.apply_debug_start_day()
	GameState.apply_restart()   # after --day=N: a restart picks its own day

## Server: host is ready — day 1 starts
func begin() -> void:
	if multiplayer.is_server() and GameState.phase == GameState.Phase.GATHER:
		_begin_day()

func _process(delta: float) -> void:
	_tick_nav(delta)
	match GameState.phase:
		GameState.Phase.DAWN:
			_timer -= delta
			if _timer <= 0.0:
				GameState.set_phase(GameState.Phase.WORK)
				_waves.start(GameState.current_day)
		GameState.Phase.WORK:
			_stats["time"] += delta
			_section_time += delta
			_tick_sun(delta)
		GameState.Phase.DUSK:
			_timer -= delta
			if _timer <= 0.0 and _waiting.is_empty():
				_close_wait()
				# A replay is one section: it ends when that section stands
				var pos := GameState.day_in_section(GameState.current_day)
				var done := _section_done()
				if GameState.is_replay() and (done or pos.x == pos.y - 1):
					GameState.set_phase(GameState.Phase.WON)
				elif GameState.sun and done and pos.x < pos.y - 1:
					# Sun clock: the stretch stood early — the days to spare are skipped,
					# the next stretch starts tomorrow (the last one wins at once)
					var next := GameState.current_section_index + 1
					if next >= GameState.SECTIONS.size():
						GameState.set_phase(GameState.Phase.WON)
					elif GameState.advance_day(GameState.SECTIONS[next]["days"][0]):
						_begin_day()
				elif GameState.advance_day():
					_begin_day()

# ── Day flow ───────────────────────────────────────────────

func _begin_day() -> void:
	_waves.stop()
	if _story_day != GameState.current_day and not StoryData.disabled() and not GameState.attract \
			and not StoryData.slides_for_day(GameState.current_day).is_empty():
		_start_story()
		return
	var pos := GameState.day_in_section(GameState.current_day)
	var fresh_section := pos.x == 0
	if fresh_section:
		_section_time = 0.0
		_section_breaches = GameState.breaches
		_section_ono = 0
		_credit.clear()
		for item in _items.get_children():
			item.queue_free()  # new stretch of wall, fresh work site
		# Posts start bare too — including any raised while the crew was still gathering
		# (section_changed doesn't fire going from the gathering into the first day)
		get_tree().call_group("watch_posts", "reset_slot")
	for unit in _units:
		for part in unit:
			if fresh_section:
				part.reset_slot()
			else:
				part.repair(REPAIR_ON_DAWN)
			part.is_target = false

	if GameState.sun:
		# Sun clock: the whole stretch is the goal, worked over its days of equal light;
		# a day ends at the stars (or when the stretch stands)
		_targets = _units.duplicate()
		var light := GameState.day_length()
		GameState.set_sun(light, light)
	else:
		# Split the section's units evenly over its days; the last day takes the remainder
		var from := floori(_units.size() * pos.x / float(pos.y))
		var to := floori(_units.size() * (pos.x + 1) / float(pos.y))
		_targets = _units.slice(from, to)
		GameState.set_sun(0.0, 0.0)
	for unit in _targets:
		for part in unit:
			part.is_target = true

	get_tree().call_group("restockable", "restock")
	_reset_stats()
	GameState.set_phase(GameState.Phase.DAWN)
	_update_progress()
	_timer = DAWN_TIME
	_request_nav_rebake()

# Server: the sun clock runs down; at the stars the day ends with whatever is built.
# On a section's last day that loses the run (Neh. 4:21 — they worked till the stars).
func _tick_sun(delta: float) -> void:
	if GameState.sun_total <= 0.0:
		return
	_sun_resync -= delta
	if _sun_resync <= 0.0:
		_sun_resync = SUN_RESYNC
		GameState.set_sun(GameState.sun_total, GameState.sun_left)
	if GameState.sun_left > 0.0 or GameState.targets_done >= GameState.targets_total:
		return
	if GameState.last_day_of_section():
		print("DayDirector: the stars appeared — %s unfinished (%d of %d units)" % [
			GameState.get_current_section()["name"], GameState.targets_done, GameState.targets_total])
		GameState.set_sun(GameState.sun_total, 0.0)
		GameState.lose("stars")
	else:
		_end_day(true)

func _end_day(nightfall := false) -> void:
	_waves.stop()
	_stats["unfinished"] = GameState.targets_total - GameState.targets_done if nightfall else 0
	if GameState.sun_total > 0.0:
		print("DayDirector: day %d — work %.0f s of %.0f s daylight%s" % [GameState.current_day,
			_stats["time"], GameState.sun_total, ", nightfall with %d unfinished" % _stats["unfinished"] if nightfall else ""])
	GameState.set_sun(GameState.sun_total, GameState.sun_left)
	GameState.set_phase(GameState.Phase.DUSK)
	for e in _enemies.get_children():
		e.flee()
	# Nobody sits out the celebration: the fallen get up, the builders down tools
	for p in get_parent().get_node("Players").get_children():
		if p.building_site != null:
			p.building_site.work().remove_builder(p)
			p.stop_building_from_server()
		if p.downed:
			p._set_downed.rpc(false)
	_stats["breaches"] = GameState.breaches - _breaches_at_dawn
	_stats["crew"] = _crew_rows()
	if _section_done():
		var pos := GameState.day_in_section(GameState.current_day)
		_stats["spare"] = pos.y - 1 - pos.x
		_rate_section()
	for id: int in _scene_peers():
		_tally.rpc_id(id, _stats)
	# The tally stays up until everyone has read it (playtest 2); the title screen's bot
	# crew has nobody to wait for
	if GameState.attract:
		_timer = DUSK_TIME
	else:
		_timer = DUSK_MIN
		_open_wait("tally")

# Server: the section's last unit stands — one mark each for pace, no breaches, a sound wall
func _rate_section() -> void:
	var i := GameState.current_section_index
	var par := GameState.par_time()
	var health := _wall_health()
	var mask := 0
	if _section_time <= par:
		mask |= GameState.Mark.PACE
	if GameState.breaches == _section_breaches:
		mask |= GameState.Mark.CLEAN
	if health >= GameState.SOUND_WALL:
		mask |= GameState.Mark.SOUND
	print("DayDirector: %s rated %d/3 — time %.0f s (par %.0f), breaches %d, wall %d%%" % [
		GameState.SECTIONS[i]["name"], GameState.mark_count(mask), _section_time, par,
		GameState.breaches - _section_breaches, roundi(health * 100.0)])
	GameState.rate_section(i, mask)
	_stats["marks"] = mask
	_stats["section_time"] = _section_time
	_stats["par"] = par
	_stats["section_breaches"] = GameState.breaches - _section_breaches
	_stats["wall"] = health
	_stats["section_ono"] = _section_ono
	_stats["names"] = _carvings()

## Per unit in build order: whose name goes on it (worker id, 0 = nobody carried to it)
func _carvings() -> Array:
	var out := []
	for i in _units.size():
		var best := 0
		var most := 0
		var by: Dictionary = _credit.get(i, {})
		for id: int in by:
			if by[id] > most:
				most = by[id]
				best = id
		out.append(best)
	return out

func _section_done() -> bool:
	return _units.all(func(unit): return unit.all(func(p): return p.is_complete()))

## Average health of every wall part in the section, 0..1 (doors have none)
func _wall_health() -> float:
	var sum := 0.0
	var n := 0
	for unit in _units:
		for part in unit:
			if "health" in part:
				sum += part.health / part.MAX_HEALTH
				n += 1
	return sum / n if n else 1.0

func _on_game_over() -> void:
	_waves.stop()
	if GameState.phase == GameState.Phase.WON:
		# "All the nations round about… lost heart" (Neh. 6:16): they withdraw
		for e in _enemies.get_children():
			e.flee()

# ── Story ──────────────────────────────────────────────────

# Server: everyone present reads; the day begins once they're all through
func _start_story() -> void:
	_story_day = GameState.current_day
	GameState.set_phase(GameState.Phase.STORY)
	for id: int in _scene_peers():
		_show_story.rpc_id(id, _story_day)
	_open_wait("story")

func _end_story() -> void:
	_close_wait()
	for id: int in _scene_peers():
		_hide_story.rpc_id(id)
	_begin_day()

## Server: a late joiner sees the story in progress (not waited on)
func send_story_to(peer_id: int) -> void:
	if GameState.phase == GameState.Phase.STORY:
		_show_story.rpc_id(peer_id, _story_day)
	if not _wait_kind.is_empty():
		_set_ready_state.rpc_id(peer_id, _wait_kind, _waiting.keys())

# ── Ready check (story cards, dusk tally) ──────────────────

## Every peer: the local player is through the story / ready to leave the tally
func mark_ready() -> void:
	if multiplayer.is_server():
		_peer_ready(1)
	else:
		_ready_from_peer.rpc_id(1)

## Server: host pressed "Begin now" — don't wait for the slow ones
func force_ready() -> void:
	if not multiplayer.is_server():
		return
	match _wait_kind:
		"story":
			if GameState.phase == GameState.Phase.STORY:
				_end_story()
		"tally":
			_waiting.clear()
			_broadcast_ready()

func _open_wait(kind: String) -> void:
	_wait_kind = kind
	_waiting.clear()
	for id: int in _scene_peers():
		_waiting[id] = true
	_broadcast_ready()

func _close_wait() -> void:
	if _wait_kind.is_empty():
		return
	_wait_kind = ""
	_waiting.clear()
	_broadcast_ready()

@rpc("any_peer", "reliable")
func _ready_from_peer() -> void:
	if multiplayer.is_server():
		_peer_ready(multiplayer.get_remote_sender_id())

func _peer_ready(id: int) -> void:
	if _wait_kind.is_empty() or not _waiting.erase(id):
		return
	if _waiting.is_empty() and _wait_kind == "story":
		_end_story()   # the tally leaves at the end of the dusk (_process)
	else:
		_broadcast_ready()

func _broadcast_ready() -> void:
	for id: int in _scene_peers():
		_set_ready_state.rpc_id(id, _wait_kind, _waiting.keys())

# ── End screen vote: play again / next stretch ─────────────

## Every peer: the local player's pick on the end screen ("again" | "next")
func cast_vote(choice: String) -> void:
	if multiplayer.is_server():
		_peer_vote(1, choice)
	else:
		_vote_from_peer.rpc_id(1, choice)

@rpc("any_peer", "reliable")
func _vote_from_peer(choice: String) -> void:
	if multiplayer.is_server():
		_peer_vote(multiplayer.get_remote_sender_id(), choice)

# Server: the host's pick decides at once; otherwise a majority of the people present
func _peer_vote(id: int, choice: String) -> void:
	if not GameState.is_over() or not choice in ["again", "next"]:
		return
	_votes[id] = choice
	var people := _scene_peers()
	var count := _votes.values().count(choice)
	for peer: int in people:
		_set_votes.rpc_id(peer, _votes)
	if id == 1 or count * 2 > people.size():
		_restart(choice)

@rpc("authority", "call_local", "reliable")
func _set_votes(votes: Dictionary) -> void:
	votes_changed.emit(votes)

# Server: set up the next run, then every peer reloads the game scene together. Peers go
# back to "loading" so nothing replicates into a scene that's being torn down; each one
# asks for the roster again once its new Main is up (Main._request_roster).
func _restart(choice: String) -> void:
	_votes.clear()
	if GameState.is_replay():
		if choice == "next" and GameState.replay_section + 1 < GameState.SECTIONS.size():
			GameState.replay_section += 1
			GameState.picker_return = GameState.replay_section
	elif GameState.phase == GameState.Phase.LOST:
		GameState.restart_day = GameState.get_current_section()["days"][0]
	print("DayDirector: play again (%s) — replay %d, from day %d" % [choice, GameState.replay_section, GameState.restart_day])
	var peers := _scene_peers()   # before readiness resets, or nobody hears about it
	NetworkManager.reset_scene_readiness()
	for id: int in peers:
		if id != multiplayer.get_unique_id():
			_reload.rpc_id(id, GameState.replay_section, GameState.picker_return)
	_reload(GameState.replay_section, GameState.picker_return)

@rpc("authority", "call_remote", "reliable")
func _reload(replay: int, picker: int) -> void:
	GameState.replay_section = replay
	GameState.picker_return = picker
	get_tree().paused = false
	Engine.time_scale = 1.0
	var restart := GameState.restart_day
	GameState.reset()
	GameState.restart_day = restart
	get_tree().reload_current_scene.call_deferred()

# Host plus every client whose Main scene exists — a peer still loading in has
# nowhere to receive these RPCs (it catches up via send_story_to)
func _scene_peers() -> Array[int]:
	var ids: Array[int] = [multiplayer.get_unique_id()]
	for id in multiplayer.get_peers():
		if NetworkManager.is_peer_ready(id):
			ids.append(id)
	return ids

func _on_peer_left(id: int) -> void:
	if multiplayer.is_server():
		_peer_ready(id)

@rpc("authority", "call_local", "reliable")
func _show_story(day: int) -> void:
	story_started.emit(day)

@rpc("authority", "call_local", "reliable")
func _set_ready_state(kind: String, waiting: Array) -> void:
	ready_changed.emit(kind, waiting)

@rpc("authority", "call_local", "reliable")
func _hide_story() -> void:
	story_ended.emit()

# ── Tally ──────────────────────────────────────────────────

func _reset_stats() -> void:
	_stats = { "time": 0.0, "loads": 0, "foes": 0, "breaches": 0, "crew": {} }
	_breaches_at_dawn = GameState.breaches

func _crew_entry(peer_id: int) -> Dictionary:
	if not _stats["crew"].has(peer_id):
		_stats["crew"][peer_id] = { "loads": 0, "foes": 0 }
	return _stats["crew"][peer_id]

## Server: a worker delivered a load to the wall (`site`: where it went)
func note_load(peer_id: int, site: Node = null) -> void:
	if GameState.phase == GameState.Phase.WORK:
		_stats["loads"] += 1
		_crew_entry(peer_id)["loads"] += 1
	for i in _units.size():
		if site in _units[i]:
			var by: Dictionary = _credit.get_or_add(i, {})
			by[peer_id] = by.get(peer_id, 0) + 1

## Server: a worker went down to Ono with the messenger
func note_ono() -> void:
	_section_ono += 1

## Server: an enemy fell (peer_id = whose stone landed last, 0 if unknown)
func note_foe(peer_id: int) -> void:
	if GameState.phase == GameState.Phase.WORK:
		_stats["foes"] += 1
		if peer_id != 0:
			_crew_entry(peer_id)["foes"] += 1

# One row per worker present, in slot order (Main sorts players by peer id)
func _crew_rows() -> Array:
	var ids: Array = get_parent().get_node("Players").get_children().map(func(p): return int(p.name))
	ids.sort()
	return ids.map(func(id: int):
		var e: Dictionary = _stats["crew"].get(id, { "loads": 0, "foes": 0 })
		return [id, e["loads"], e["foes"]])

@rpc("authority", "call_local", "reliable")
func _tally(stats: Dictionary) -> void:
	day_tallied.emit(stats)

# Every peer: the units finished today pop and puff one after another along the wall
func _on_phase_changed(phase: GameState.Phase) -> void:
	if phase != GameState.Phase.DUSK:
		return
	var i := 0
	for site in get_tree().get_nodes_in_group("build_sites"):
		if site.get("is_target") and site.has_method("celebrate"):
			get_tree().create_timer(0.2 + i * CELEBRATE_STEP).timeout.connect(
				func(): if is_instance_valid(site): site.celebrate())
			i += 1

# ── Progress ───────────────────────────────────────────────

func _on_stage_changed() -> void:
	if not multiplayer.is_server():
		return
	_request_nav_rebake()
	_update_progress()
	if GameState.phase == GameState.Phase.WORK and GameState.targets_done >= GameState.targets_total:
		_end_day()

func _update_progress() -> void:
	var done := _targets.filter(func(unit): return unit.all(func(p): return p.is_complete())).size()
	GameState.set_progress(done, _targets.size())

# ── Navigation ─────────────────────────────────────────────

# Built walls change the walkable area; rebake (debounced, threaded) so enemies
# path toward the remaining gaps instead of walking into finished stone.
func _request_nav_rebake() -> void:
	_nav_rebake_in = NAV_REBAKE_DELAY

func _tick_nav(delta: float) -> void:
	if _nav_rebake_in < 0.0:
		return
	_nav_rebake_in -= delta
	if _nav_rebake_in <= 0.0:
		if _nav.is_baking():
			_nav_rebake_in = NAV_REBAKE_DELAY
		else:
			_nav_rebake_in = -1.0
			_nav.bake_navigation_mesh(true)
