extends Node

# Campaign state. The server mutates it (via DayDirector) and broadcasts every change;
# clients only mirror it. Everything else reads from here and listens to the signals.

# 12 sections clockwise from Sheep Gate (Nehemiah 3)
const SECTIONS: Array = [
	{ "name": "Sheep Gate",     "ref": "Neh. 3:1",  "days": [1,2,3,4]          },
	{ "name": "Fish Gate",      "ref": "Neh. 3:3",  "days": [5,6,7,8]          },
	{ "name": "Jeshanah Gate",  "ref": "Neh. 3:6",  "days": [9,10,11,12]       },
	{ "name": "Broad Wall",     "ref": "Neh. 3:8",  "days": [13,14,15,16,17]   },
	{ "name": "Tower of Ovens", "ref": "Neh. 3:11", "days": [18,19,20,21,22,23]},
	{ "name": "Valley Gate",    "ref": "Neh. 3:13", "days": [24,25,26,27,28,29]},
	{ "name": "Dung Gate",      "ref": "Neh. 3:14", "days": [30,31,32,33]      },
	{ "name": "Fountain Gate",  "ref": "Neh. 3:15", "days": [34,35,36]         },
	{ "name": "Water Gate",     "ref": "Neh. 3:26", "days": [37,38,39,40,41]   },
	{ "name": "Horse Gate",     "ref": "Neh. 3:28", "days": [42,43,44,45,46,47]},
	{ "name": "East Gate",      "ref": "Neh. 3:29", "days": [48,49,50]         },
	{ "name": "Miphkad Gate",   "ref": "Neh. 3:31", "days": [51,52]            },
]

const TOTAL_DAYS   := 52
const MAX_BREACHES := 10   # enemies that may reach the inner city before the city falls

# GATHER: before day 1, waiting for the crew to join (appended so synced ints stay stable)
enum Phase { DAWN, WORK, DUSK, WON, LOST, GATHER }

signal day_changed(day: int)
signal section_changed(section_index: int)
signal phase_changed(phase: Phase)
signal breaches_changed(count: int)
signal progress_changed(done: int, total: int)
signal crew_changed(size: int)
signal game_won
signal game_lost

var current_day: int = 1
var current_section_index: int = 0
var phase: Phase = Phase.GATHER
var breaches: int = 0
var targets_done: int = 0
var targets_total: int = 0
# Players in the session — building costs scale with it (see WallSection.cost_for)
var crew_size: int = 1
# peer_id → { "role": String }
var players: Dictionary = {}

# ── Queries ────────────────────────────────────────────────

func get_section_for_day(day: int) -> Dictionary:
	return SECTIONS[_section_index_for_day(day)]

func get_current_section() -> Dictionary:
	return get_section_for_day(current_day)

## 0-based index of `day` within its section, and that section's day count
func day_in_section(day: int) -> Vector2i:
	var days: Array = get_section_for_day(day)["days"]
	return Vector2i(days.find(day), days.size())

func is_over() -> bool:
	return phase == Phase.WON or phase == Phase.LOST

# ── Mutations (server) ─────────────────────────────────────

func set_phase(p: Phase) -> void:
	_apply(current_day, current_section_index, p, breaches, targets_done, targets_total)

func set_progress(done: int, total: int) -> void:
	_apply(current_day, current_section_index, phase, breaches, done, total)

func add_breach() -> void:
	if is_over():
		return
	var b := breaches + 1
	_apply(current_day, current_section_index, Phase.LOST if b >= MAX_BREACHES else phase,
		b, targets_done, targets_total)

## Returns false when there is no next day (campaign won)
func advance_day() -> bool:
	if current_day >= TOTAL_DAYS:
		set_phase(Phase.WON)
		return false
	var day := current_day + 1
	_apply(day, _section_index_for_day(day), Phase.DAWN, breaches, 0, 0)
	return true

func reset() -> void:
	current_day = 1
	current_section_index = 0
	phase = Phase.GATHER
	breaches = 0
	targets_done = 0
	targets_total = 0
	players.clear()

## Push full state to one peer (late join)
func send_state_to(peer_id: int) -> void:
	_sync.rpc_id(peer_id, current_day, current_section_index, phase, breaches, targets_done, targets_total)
	_sync_crew.rpc_id(peer_id, crew_size)

## Server: players joined/left
func set_crew(size: int) -> void:
	_apply_crew(size)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_crew.rpc(size)

@rpc("authority", "call_remote", "reliable")
func _sync_crew(size: int) -> void:
	_apply_crew(size)

func _apply_crew(size: int) -> void:
	size = maxi(1, size)
	if size != crew_size:
		crew_size = size
		crew_changed.emit(size)

# ── Players ────────────────────────────────────────────────

func register_player(peer_id: int, role: String) -> void:
	players[peer_id] = { "role": role }

func remove_player(peer_id: int) -> void:
	players.erase(peer_id)

# ── Internal ───────────────────────────────────────────────

func _apply(day: int, section: int, p: Phase, b: int, done: int, total: int) -> void:
	_set_state(day, section, p, b, done, total)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync.rpc(day, section, p, b, done, total)

@rpc("authority", "call_remote", "reliable")
func _sync(day: int, section: int, p: int, b: int, done: int, total: int) -> void:
	_set_state(day, section, p as Phase, b, done, total)

# Assign, then emit only what changed — every peer runs this
func _set_state(day: int, section: int, p: Phase, b: int, done: int, total: int) -> void:
	var day_new := day != current_day
	var section_new := section != current_section_index
	var phase_new := p != phase
	var breach_new := b != breaches
	var progress_new := done != targets_done or total != targets_total
	current_day = day
	current_section_index = section
	phase = p
	breaches = b
	targets_done = done
	targets_total = total
	if section_new:
		section_changed.emit(section)
	if day_new:
		day_changed.emit(day)
	if breach_new:
		breaches_changed.emit(b)
	if progress_new:
		progress_changed.emit(done, total)
	if phase_new:
		phase_changed.emit(p)
		if p == Phase.WON:
			game_won.emit()
		elif p == Phase.LOST:
			game_lost.emit()

func _section_index_for_day(day: int) -> int:
	for i in SECTIONS.size():
		if day in SECTIONS[i]["days"]:
			return i
	return 0
