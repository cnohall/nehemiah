extends Node

# Steam achievements. Every peer judges its own from what it already receives — section
# ratings, the dusk tally, the win — so nothing extra goes over the network.
# Unlocks and running totals are kept in progress.cfg as well: pushed to Steam again on
# the next start when Steam was away (or the build had no app ID yet), and there for an
# in-game list later. Off Steam (web, mobile) they're only kept locally.
# API names must match Steamworks → Stats & Achievements: see tools/steam_achievements.md.
# Not for `--day=N` runs, like the marks.

signal unlocked(id: String)

# Per-day and lifetime thresholds. TODO: tune from playtest tallies
const LOADS_IN_A_DAY := 20
const FOES_IN_A_DAY  := 15
const LOADS_TOTAL    := 1000
const FOES_TOTAL     := 500

# id → [name, description]. The section ones (SECTION_01…12) are added from GameState.
# Hidden in Steamworks: GREAT_WORK.
const FIXED := {
	"FIRST_DAY":    ["Let us rise up and build", "Finish the first day's work (Neh. 2:18)"],
	"WALL_DONE":    ["Elul 25", "Finish the wall on day 52 (Neh. 6:15)"],
	"NONE_THROUGH": ["Not one slipped through", "Finish the wall without a single enemy reaching the city"],
	"THREE_MARKS":  ["Well built", "Earn all three marks on a section"],
	"ALL_MARKS":    ["Every stone in its place", "Hold all three marks on every section"],
	"SOLO_MARKS":   ["Over against his own house", "Earn all three marks on a section working alone (Neh. 3:28)"],
	"CREW_2":       ["Two are better than one", "Finish a section with a crew of two or more"],
	"CREW_4":       ["Every hand at the wall", "Finish a section with a crew of four"],
	"LOADS_DAY":    ["Burden bearer", "Deliver %d loads in a single day" % LOADS_IN_A_DAY],
	"FOES_DAY":     ["On guard", "Drive off %d enemies in a single day" % FOES_IN_A_DAY],
	"LOADS_ALL":    ["The strength of the bearers", "Deliver %d loads in all (Neh. 4:10)" % LOADS_TOTAL],
	"FOES_ALL":     ["A watch day and night", "Drive off %d enemies in all (Neh. 4:9)" % FOES_TOTAL],
	"GREAT_WORK":   ["I am doing a great work", "Finish a section the messengers came to without anyone going down to Ono (Neh. 6:3)"],
}

const CFG_UNLOCKED := "achievements"
const CFG_STATS    := "stats"

var _unlocked := {}   # id → true
var _stats := {}      # "loads" / "foes" → lifetime total
# Test harnesses (`--script`) play real days: they mustn't unlock the player's achievements
# or add to their lifetime totals in progress.cfg
var _harness := "--script" in OS.get_cmdline_args()

func _ready() -> void:
	_load()
	GameState.section_rated.connect(_on_section_rated)
	GameState.game_won.connect(_on_game_won)
	_push_all()

## Every achievement: id → [name, description], in Steamworks order
func all() -> Dictionary:
	var out := {}
	for i in GameState.SECTIONS.size():
		var sec: Dictionary = GameState.SECTIONS[i]
		out[section_id(i)] = ["The %s stands" % sec["name"], "Finish the %s (%s)" % [sec["name"], sec["ref"]]]
	out.merge(FIXED)
	return out

static func section_id(section_index: int) -> String:
	return "SECTION_%02d" % (section_index + 1)

func is_unlocked(id: String) -> bool:
	return _unlocked.has(id)

func unlock(id: String) -> void:
	if _unlocked.has(id) or GameState._debug_start or _harness:
		return
	_unlocked[id] = true
	var cfg := ConfigFile.new()
	cfg.load(GameState.PROGRESS_PATH)
	cfg.set_value(CFG_UNLOCKED, id, true)
	cfg.save(GameState.PROGRESS_PATH)
	print("Achievements: unlocked %s" % id)
	var steam := _steam()
	if steam:
		steam.setAchievement(id)
		steam.storeStats()
	unlocked.emit(id)

# ── Judging ────────────────────────────────────────────────

func _on_section_rated(section_index: int, mask: int) -> void:
	unlock(section_id(section_index))
	var full := GameState.mark_count(mask) == GameState.MARKS.size()
	if full:
		unlock("THREE_MARKS")
		if GameState.crew_size == 1:
			unlock("SOLO_MARKS")
	# Company means people: bots fill places, but these are for playing together
	var people := GameState.players.values().filter(func(p): return p["role"] != "Bot").size()
	if people >= 2:
		unlock("CREW_2")
	if people >= 4:
		unlock("CREW_4")
	# Best marks are saved before section_rated fires, so this run counts
	var all_full := range(GameState.SECTIONS.size()).all(func(i: int):
		return GameState.mark_count(GameState.best_marks(i)) == GameState.MARKS.size())
	if all_full:
		unlock("ALL_MARKS")

## Every peer: the dusk tally (DayDirector.day_tallied) — this worker's share of the day
func on_day_tallied(stats: Dictionary) -> void:
	if GameState._debug_start:
		return
	if GameState.current_day == 1:
		unlock("FIRST_DAY")
	if stats.has("marks") and GameState.has_twist("schemes") and stats.get("section_ono", 0) == 0:
		unlock("GREAT_WORK")
	var me := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	for row: Array in stats.get("crew", []):
		if row[0] != me:
			continue
		var loads: int = row[1]
		var foes: int = row[2]
		if loads >= LOADS_IN_A_DAY:
			unlock("LOADS_DAY")
		if foes >= FOES_IN_A_DAY:
			unlock("FOES_DAY")
		if _add_stat("loads", loads) >= LOADS_TOTAL:
			unlock("LOADS_ALL")
		if _add_stat("foes", foes) >= FOES_TOTAL:
			unlock("FOES_ALL")

func _on_game_won() -> void:
	if GameState.is_replay() or GameState.is_demo():
		return
	unlock("WALL_DONE")
	if GameState.breaches == 0:
		unlock("NONE_THROUGH")

# ── Storage / Steam ────────────────────────────────────────

func _add_stat(key: String, amount: int) -> int:
	_stats[key] = _stats.get(key, 0) + amount
	if amount > 0 and not _harness:
		var cfg := ConfigFile.new()
		cfg.load(GameState.PROGRESS_PATH)
		cfg.set_value(CFG_STATS, key, _stats[key])
		cfg.save(GameState.PROGRESS_PATH)
	return _stats[key]

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(GameState.PROGRESS_PATH) != OK:
		return
	if cfg.has_section(CFG_UNLOCKED):
		for id: String in cfg.get_section_keys(CFG_UNLOCKED):
			_unlocked[id] = true
	if cfg.has_section(CFG_STATS):
		for key: String in cfg.get_section_keys(CFG_STATS):
			_stats[key] = cfg.get_value(CFG_STATS, key, 0)

# Catch Steam up on anything earned while it was away
func _push_all() -> void:
	var steam := _steam()
	if not steam or _unlocked.is_empty():
		return
	for id: String in _unlocked:
		steam.setAchievement(id)
	steam.storeStats()

# Steam, when running under our own app ID — Spacewar (480) has its own achievements
func _steam() -> Object:
	if NetworkManager.STEAM_APP_ID == 480:
		return null
	return NetworkManager.steam()
