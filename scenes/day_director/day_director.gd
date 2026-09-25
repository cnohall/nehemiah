extends Node

# Server-side day loop (GDD "sprint model"):
#   GATHER — before day 1: players join and walk around, nothing spawns
#   DAWN  — today's wall units are marked, short breather, no spawns
#   WORK  — enemies stream in; day ends when every target unit is fully built
#   DUSK  — enemies withdraw, then the next day begins
# Moving into a new circuit section (Nehemiah 3) resets the wall to bare foundations.

const DAWN_TIME        := 5.0
const DUSK_TIME        := 6.0
const NAV_REBAKE_DELAY := 0.4
const REPAIR_ON_DAWN   := 0.5   # fraction of lost health restored overnight

# Build order within a section: the named gate first, then outward to the towers
const UNIT_ORDER := ["SheepGate", "Section1", "Section3", "TowerLeft", "Section4", "TowerRight"]

@onready var _wall: Node3D                = get_parent().get_node("Wall")
@onready var _waves: Node                 = get_parent().get_node("WaveManager")
@onready var _enemies: Node3D             = get_parent().get_node("Enemies")
@onready var _nav: NavigationRegion3D     = get_parent().get_node("NavRegion")

var _units: Array = []     # each unit = Array of wall sections (gate = both pillars)
var _targets: Array = []   # units that must be finished today
var _timer := 0.0
var _nav_rebake_in := -1.0

func _ready() -> void:
	for unit_name: String in UNIT_ORDER:
		var node := _wall.get_node(unit_name)
		var parts: Array = [node] if node.has_method("try_build") \
			else node.get_children().filter(func(c): return c.has_method("try_build"))
		_units.append(parts)
		for part in parts:
			part.stage_changed.connect(_on_stage_changed.unbind(1))
	# Parse the tagged scene roots (floor, wall, supplies, houses) rather than the
	# region's own (empty) children. Set here: the .tscn key doesn't round-trip.
	_nav.navigation_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	_nav.navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	GameState.game_lost.connect(_on_game_over)
	GameState.game_won.connect(_on_game_over)
	set_process(multiplayer.is_server())

## Server: open the session — the crew gathers until the host calls begin()
func start() -> void:
	GameState.reset()

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
	var pos := GameState.day_in_section(GameState.current_day)
	var fresh_section := pos.x == 0
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
