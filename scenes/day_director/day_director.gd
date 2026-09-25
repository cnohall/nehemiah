extends Node

# Server-side day loop (GDD "sprint model"):
#   GATHER — before day 1: players join and walk around, nothing spawns
#   STORY — story cards before the day (StoryData); waits until every reader is through
#   DAWN  — today's wall units are marked, short breather, no spawns
#   WORK  — enemies stream in; day ends when every target unit is fully built
#   DUSK  — enemies withdraw, then the next day begins
# Moving into a new circuit section (Nehemiah 3) resets the wall to bare foundations.

const DAWN_TIME        := 5.0
const DUSK_TIME        := 6.0
const NAV_REBAKE_DELAY := 0.4
const REPAIR_ON_DAWN   := 0.5   # fraction of lost health restored overnight

# Every peer: Main shows/hides the StoryPlayer on these
signal story_started(day: int)
signal story_waiting_changed(count: int)
signal story_ended

# Build order within a section: the named gate first, then outward to the towers
const UNIT_ORDER := ["SheepGate", "Section1", "Section3", "TowerLeft", "Section4", "TowerRight"]

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
var _story_readers := {}     # server: peer_id → true while still reading

func _ready() -> void:
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
	GameState.apply_debug_start_day()

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
		GameState.Phase.DUSK:
			_timer -= delta
			if _timer <= 0.0 and GameState.advance_day():
				_begin_day()

# ── Day flow ───────────────────────────────────────────────

func _begin_day() -> void:
	_waves.stop()
	if _story_day != GameState.current_day and not StoryData.disabled() \
			and not StoryData.slides_for_day(GameState.current_day).is_empty():
		_start_story()
		return
	var pos := GameState.day_in_section(GameState.current_day)
	var fresh_section := pos.x == 0
	if fresh_section:
		for item in _items.get_children():
			item.queue_free()  # new stretch of wall, fresh work site
	for unit in _units:
		for part in unit:
			if fresh_section:
				part.reset_slot()
			else:
				part.repair(REPAIR_ON_DAWN)
			part.is_target = false

	# Split the section's units evenly over its days; the last day takes the remainder
	var from := floori(_units.size() * pos.x / float(pos.y))
	var to := floori(_units.size() * (pos.x + 1) / float(pos.y))
	_targets = _units.slice(from, to)
	for unit in _targets:
		for part in unit:
			part.is_target = true

	get_tree().call_group("restockable", "restock")
	GameState.set_phase(GameState.Phase.DAWN)
	_update_progress()
	_timer = DAWN_TIME
	_request_nav_rebake()

func _end_day() -> void:
	GameState.set_phase(GameState.Phase.DUSK)
	_waves.stop()
	_clear_enemies()
	_timer = DUSK_TIME

func _on_game_over() -> void:
	_waves.stop()
	if GameState.phase == GameState.Phase.WON:
		_clear_enemies()

func _clear_enemies() -> void:
	for e in _enemies.get_children():
		e.queue_free()

# ── Story ──────────────────────────────────────────────────

# Server: everyone present reads; the day begins once they're all through
func _start_story() -> void:
	_story_day = GameState.current_day
	_story_readers.clear()
	for id: int in _scene_peers():
		_story_readers[id] = true
	GameState.set_phase(GameState.Phase.STORY)
	for id: int in _scene_peers():
		_show_story.rpc_id(id, _story_day)
	_broadcast_waiting()

## Every peer: the local reader is through (or skipped)
func finish_reading() -> void:
	if multiplayer.is_server():
		_reader_done(1)
	else:
		_story_done.rpc_id(1)

## Server: host pressed "Begin now" — don't wait for the slow readers
func force_story_end() -> void:
	if multiplayer.is_server() and GameState.phase == GameState.Phase.STORY:
		_end_story()

## Server: a late joiner sees the story in progress (not waited on)
func send_story_to(peer_id: int) -> void:
	if GameState.phase == GameState.Phase.STORY:
		_show_story.rpc_id(peer_id, _story_day)
		_set_story_waiting.rpc_id(peer_id, _story_readers.size())

@rpc("any_peer", "reliable")
func _story_done() -> void:
	if multiplayer.is_server():
		_reader_done(multiplayer.get_remote_sender_id())

func _reader_done(id: int) -> void:
	if GameState.phase != GameState.Phase.STORY or not _story_readers.erase(id):
		return
	if _story_readers.is_empty():
		_end_story()
	else:
		_broadcast_waiting()

func _end_story() -> void:
	_story_readers.clear()
	for id: int in _scene_peers():
		_hide_story.rpc_id(id)
	_begin_day()

func _broadcast_waiting() -> void:
	for id: int in _scene_peers():
		_set_story_waiting.rpc_id(id, _story_readers.size())

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
		_reader_done(id)

@rpc("authority", "call_local", "reliable")
func _show_story(day: int) -> void:
	story_started.emit(day)

@rpc("authority", "call_local", "reliable")
func _set_story_waiting(count: int) -> void:
	story_waiting_changed.emit(count)

@rpc("authority", "call_local", "reliable")
func _hide_story() -> void:
	story_ended.emit()

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
