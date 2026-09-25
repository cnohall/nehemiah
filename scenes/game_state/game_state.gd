extends Node

# Campaign state. The server mutates it (via DayDirector) and broadcasts every change;
# clients only mirror it. Everything else reads from here and listens to the signals.

# 12 sections clockwise from Sheep Gate (Nehemiah 3)
# Each section's "twists" are the extra ingredients it plays with (GDD §6), and its
# layout: where the supply yard sits ("yard", x/z centre) and whether the opening in the
# wall is a gate ("gate": true) or just a gap to seal with stone. Every peer derives all
# of this from the section index, so nothing extra is replicated.
const DEFAULT_YARD := Vector2(0.0, 10.0)
const SECTIONS: Array = [
	{ "name": "Sheep Gate",     "ref": "Neh. 3:1",  "days": [1,2,3,4],           "twists": ["doors"],                     "yard": Vector2(0, 10) },
	{ "name": "Fish Gate",      "ref": "Neh. 3:3",  "days": [5,6,7,8],           "twists": ["doors", "beams"],            "yard": Vector2(-9, 10) },
	{ "name": "Jeshanah Gate",  "ref": "Neh. 3:6",  "days": [9,10,11,12],        "twists": ["doors", "beams", "salvage"], "yard": Vector2(0, 11) },
	{ "name": "Broad Wall",     "ref": "Neh. 3:8",  "days": [13,14,15,16,17],    "twists": [],                            "yard": Vector2(2, 12), "gate": false },
	{ "name": "Tower of Ovens", "ref": "Neh. 3:11", "days": [18,19,20,21,22,23], "twists": ["mixing"],                            "yard": Vector2(9, 10), "gate": false },
	{ "name": "Valley Gate",    "ref": "Neh. 3:13", "days": [24,25,26,27,28,29], "twists": ["doors", "mixing"],                  "yard": Vector2(-6, 11) },
	{ "name": "Dung Gate",      "ref": "Neh. 3:14", "days": [30,31,32,33],       "twists": ["doors"],                     "yard": Vector2(30, 9) },
	{ "name": "Fountain Gate",  "ref": "Neh. 3:15", "days": [34,35,36],          "twists": ["doors"],                     "yard": Vector2(-4, 8) },
	{ "name": "Water Gate",     "ref": "Neh. 3:26", "days": [37,38,39,40,41],    "twists": ["doors"],                     "yard": Vector2(6, 11) },
	{ "name": "Horse Gate",     "ref": "Neh. 3:28", "days": [42,43,44,45,46,47], "twists": ["doors"],                     "yard": Vector2(-3, 12) },
	{ "name": "East Gate",      "ref": "Neh. 3:29", "days": [48,49,50],          "twists": ["doors"],                     "yard": Vector2(4, 10) },
	{ "name": "Miphkad Gate",   "ref": "Neh. 3:31", "days": [51,52],             "twists": ["doors"],                     "yard": Vector2(0, 10) },
]
# Shown under the dawn banner the first time a section uses a twist
const TWIST_INTRO := {
	"doors": "Finish the gate: hang its doors, bolts and bars",
	"beams": "The beams are heavy — carry them in pairs",
	"salvage": "No quarry stone here — salvage it from the burned rubble",
	"mixing": "Make the mortar: lime and water into the trough, then to the wall",
}

const TOTAL_DAYS   := 52
const MAX_BREACHES := 10   # enemies that may reach the inner city before the city falls

# GATHER: before day 1, waiting for the crew to join; STORY: story cards before a day
# (appended so synced ints stay stable)
enum Phase { DAWN, WORK, DUSK, WON, LOST, GATHER, STORY }

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

func yard_center() -> Vector2:
	return get_current_section().get("yard", DEFAULT_YARD)

## False where the wall has no gate in this stretch — the opening is sealed with stone
func has_gate() -> bool:
	return get_current_section().get("gate", true)

func has_twist(twist: String) -> bool:
	return twist in get_current_section().get("twists", [])

## Twists this section has that the one before it didn't
func new_twists() -> Array:
	var i := current_section_index
	var before: Array = SECTIONS[i - 1].get("twists", []) if i > 0 else []
	return get_current_section().get("twists", []).filter(func(t): return t not in before)

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

## Debug builds: `-- --day=N` on the command line starts the campaign at day N
## (e.g. 8 for brutes, 20 for raiders). Server only, before day 1 begins.
func apply_debug_start_day() -> void:
	if not OS.is_debug_build():
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--day="):
			var day := clampi(arg.trim_prefix("--day=").to_int(), 1, TOTAL_DAYS)
			_apply(day, _section_index_for_day(day), phase, breaches, targets_done, targets_total)
			print("GameState: debug start at day %d" % day)

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
