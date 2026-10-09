extends Node

# Campaign state. The server mutates it (via DayDirector) and broadcasts every change;
# clients only mirror it. Everything else reads from here and listens to the signals.

# 12 sections from the Sheep Gate in Nehemiah 3 order (counterclockwise on a north-up map)
# Each section's "twists" are the extra ingredients it plays with (GDD §6), and its
# layout: where the supply yard sits ("yard", x/z centre) and whether the opening in the
# wall is a gate ("gate": true) or just a gap to seal with stone. Every peer derives all
# of this from the section index, so nothing extra is replicated.
# Optional: "terrain" (landmarks SectionTerrain builds around the site), "pressure"
# (enemy pace multiplier, 1 = normal) and "piles" (pile name → absolute x/z, for piles
# that don't sit in the yard, e.g. water drawn from the pool at the Fountain Gate).
const DEFAULT_YARD := Vector2(0.0, 10.0)
const SECTIONS: Array = [
	{ "name": "Sheep Gate",     "ref": "Neh. 3:1",  "days": [1,2,3,4],           "twists": ["doors"],                     "yard": Vector2(0, 10),  "terrain": "sheepfold" },
	{ "name": "Fish Gate",      "ref": "Neh. 3:3",  "days": [5,6,7,8],           "twists": ["doors", "beams"],            "yard": Vector2(-9, 10), "terrain": "fish_market", "choices": ["porters", "market"] },
	{ "name": "Jeshanah Gate",  "ref": "Neh. 3:6",  "days": [9,10,11,12],        "twists": ["doors", "beams", "salvage", "ruins"], "yard": Vector2(0, 11),  "terrain": "ruins", "choices": ["dig", "shore"],
		"recipes": { "Section1": "old", "Section3": "burned" } },
	{ "name": "Broad Wall",     "ref": "Neh. 3:8",  "days": [13,14,15,16,17],    "twists": ["thick"],                     "yard": Vector2(2, 12),  "terrain": "workshops", "choices": ["rush", "pack"], "gate": false },
	{ "name": "Tower of the Ovens", "ref": "Neh. 3:11", "days": [18,19,20,21,22,23], "twists": ["mixing"],                    "yard": Vector2(9, 10),  "terrain": "ovens", "choices": ["hot", "bank"], "gate": false },
	{ "name": "Valley Gate",    "ref": "Neh. 3:13", "days": [24,25,26,27,28,29], "twists": ["doors", "mixing", "horn"],   "yard": Vector2(-6, 11), "terrain": "valley", "choices": ["terraces", "heights"], "pressure": 1.1 },
	{ "name": "Gate of the Ash Heaps",      "ref": "Neh. 3:14", "days": [30,31,32,33],       "twists": ["doors", "haul"],             "yard": Vector2(30, 9),  "terrain": "refuse", "choices": ["bundles", "road"] },
	{ "name": "Fountain Gate",  "ref": "Neh. 3:15", "days": [34,35,36],          "twists": ["doors", "mixing", "spring"], "yard": Vector2(-4, 9),  "terrain": "garden", "pressure": 0.55, "choices": ["table", "fields"],
		"piles": { "StockWater": Vector2(-11.5, 4.5) } },
	{ "name": "Water Gate",     "ref": "Neh. 3:26", "days": [37,38,39,40,41],    "twists": ["doors", "night"],            "yard": Vector2(6, 11),  "terrain": "ophel" },
	{ "name": "Horse Gate",     "ref": "Neh. 3:28", "days": [42,43,44,45,46,47], "twists": ["doors", "cramped"],          "yard": Vector2(-3, 12), "terrain": "priests", "pressure": 1.1 },
	{ "name": "East Gate",      "ref": "Neh. 3:29", "days": [48,49,50],          "twists": ["doors", "schemes"],          "yard": Vector2(4, 10),  "terrain": "kidron", "pressure": 1.2 },
	{ "name": "Miphkad Gate",   "ref": "Neh. 3:31", "days": [51,52],             "twists": ["doors", "beams", "salvage", "mixing", "horn", "schemes", "ruins"],
		"yard": Vector2(0, 10), "terrain": "market", "pressure": 1.3, "recipes": { "Section1": "burned", "Section4": "old" } },
]
# Choices before a stretch (GDD §6.5): the crew picks one of two ways to meet the work
# ahead, each a real trade — a gain and a cost, tied to what the stretch brings. Picked on
# the last card before the work (StoryPlayer), decided by DayDirector (most votes, the host's
# pick breaks a tie, no votes = the first), in play for that stretch only and written on
# the scribe's map. The card text is worked out from "mods", so it is always the truth.
#   mods (1 = unchanged):  work    — hands-on building speed       harm  — blows the wall takes
#     pressure — foes' pace and numbers     beam_solo — a beam dragged alone
#     carry — walking speed with a load
#     clear — burned timbers coming down   mix — mortar mixing time
#   posts: true — the watch posts stand from dawn, stocked
# Every stretch without its own pair offers the build / guard one: pace (the "In good
# time" mark) against defence (the "None got through" and "The wall holds" marks).
const BOONS := {
	"build": { "title": "Press the work", "ref": "Neh. 4:6", "mods": { "work": 1.2, "harm": 1.25 } },
	"guard": { "title": "Hold the line", "ref": "Neh. 4:13", "mods": { "work": 0.9, "harm": 0.75 }, "posts": true },
	"porters": { "title": "Practised porters", "ref": "Neh. 3:3", "mods": { "beam_solo": 1.9, "pressure": 1.15 } },
	"market": { "title": "Watch the market side", "ref": "Neh. 4:9", "mods": { "work": 0.9, "pressure": 0.8 }, "posts": true },
	"dig": { "title": "Dig out the rubble", "ref": "Neh. 4:2", "mods": { "clear": 2.0, "work": 1.1, "pressure": 1.2 } },
	"shore": { "title": "Shore up the old courses", "ref": "Neh. 3:6", "mods": { "harm": 0.7, "clear": 0.6 } },
	"rush": { "title": "Rush the faces", "ref": "Neh. 3:8", "mods": { "work": 1.3, "harm": 1.4 } },
	"pack": { "title": "Pack the core", "ref": "Neh. 4:6", "mods": { "harm": 0.6, "work": 0.85 } },
	"hot": { "title": "Fire the ovens high", "ref": "Neh. 3:11", "mods": { "mix": 0.5, "pressure": 1.2 } },
	"bank": { "title": "Bank the ovens", "ref": "Neh. 3:11", "mods": { "mix": 1.5, "pressure": 0.8 }, "posts": true },
	"terraces": { "title": "Work the terraces", "ref": "Neh. 3:13", "mods": { "work": 1.2, "harm": 1.3 } },
	"heights": { "title": "Lookouts on the heights", "ref": "Neh. 4:20", "mods": { "pressure": 0.75, "work": 0.9 }, "posts": true },
	"bundles": { "title": "Carry in bundles", "ref": "Neh. 3:14", "mods": { "carry": 1.25, "harm": 1.25 } },
	"road": { "title": "Hold the road", "ref": "Neh. 3:14", "mods": { "harm": 0.8, "carry": 0.85 }, "posts": true },
	"table": { "title": "Open Nehemiah's table", "ref": "Neh. 5:17", "mods": { "work": 1.2, "carry": 0.8 } },
	"fields": { "title": "Give back their fields", "ref": "Neh. 5:11", "mods": { "harm": 0.8, "work": 0.85 }, "posts": true },
}
const DEFAULT_CHOICES := ["build", "guard"]
# What a modifier means to the crew: [higher is better?, text for more, text for less]. Each
# line is "%d%% …"; the % is how far from 1 it is, in the direction of the change.
const MOD_TEXT := {
	"work": [true, "Building is %d%% quicker", "Building is %d%% slower"],
	"harm": [false, "The wall takes %d%% more harm from blows", "The wall takes %d%% less harm from blows"],
	"pressure": [false, "%d%% more foes", "%d%% fewer foes"],
	"beam_solo": [true, "A beam dragged alone goes %d%% faster", "A beam dragged alone goes %d%% slower"],
	"carry": [true, "Loaded workers walk %d%% faster", "Loaded workers walk %d%% slower"],
	"clear": [true, "Burned timbers come down %d%% faster", "Burned timbers come down %d%% slower"],
	"mix": [false, "Mortar takes %d%% more time to mix", "Mortar takes %d%% less time to mix"],
}
# The boon in play for this stretch ("" = none: the first stretch, a replay; every peer,
# set by DayDirector at its dawn)
var boon := ""
signal boon_changed

# Shown under the dawn banner the first time a section uses a twist
const TWIST_INTRO := {
	"doors": "Finish the gate: hang its doors, bolts and bars",
	"beams": "The beams are heavy. Carry them in pairs",
	"salvage": "No quarry stone here. Salvage it from the burned rubble; heaps outside the wall hold twice as much",
	"mixing": "Make the mortar: lime and water into the trough, then to the wall",
	"ruins": "Not every stretch starts bare: old courses still stand in places, and burned timbers must be pulled down before anything is built",
	"thick": "The Broad Wall: raise the outer face, then the inner, then fill between. Room for four at the work, and it takes half the blows",
	"horn": "They come up the valley in surges. {horn} sounds the horn: gather in its ring and your blows land harder",
	"haul": "A long haul from the yard: leave loads on the relay mat halfway and a porter carries them to the wall, or hand one to a friend",
	"spring": "A quiet stretch by the Pool of Shelah. The water is close at hand. Three households within the wall are hungry: carry each a portion from the baskets. Every family fed comes back to the work and builds faster; leave them hungry and the next stretch is short of hands",
	"spring_simple": "A quiet stretch by the Pool of Shelah. The water is close at hand: the mortar comes quickly",
	"night": "Night falls on the work. Keep to the torchlight; they come out of the dark",
	"cramped": "Each priest builds in front of his own house. Mind the narrow lanes",
	"schemes": "Messengers will call you down to Ono. Answer them and keep working",
}
## A twist's dawn line; the simple game's own where it leaves part of the twist out
func twist_intro(twist: String) -> String:
	var key := twist + "_simple"
	return TWIST_INTRO.get(key if simplified() and TWIST_INTRO.has(key) else twist, "")

## A verse reference in the player's language: short ("Neh. 3:1") for plaques, long
## ("Nehemiah 3:1") for cards and quotes. Takes either English form.
func short_ref(ref: String) -> String:
	return tr("Neh. %s") % _verse_of(ref)

func long_ref(ref: String) -> String:
	return tr("Nehemiah %s") % _verse_of(ref)

static func _verse_of(ref: String) -> String:
	return ref.trim_prefix("Neh. ").trim_prefix("Nehemiah ")

# Water Gate night watch (Neh. 4:22-23): the first day of the section is worked in
# daylight, the rest end in darkness
const NIGHT_FROM_DAY_IN_SECTION := 1

const TOTAL_DAYS   := 52

# Demo build (GDD §7.1 #2): export feature "demo", or `-- --demo` on the command line.
# Days 1-9, ending at the dusk of the first day brutes come (WaveManager forces one).
# Only the first DEMO_SECTIONS stretches open on the map. Wishlist link: fill in the
# store page once the Steam App ID exists; the end-card button stays hidden while empty.
const DEMO_LAST_DAY := 9
const DEMO_SECTIONS := 2
const DEMO_WISHLIST_URL := ""

static func is_demo() -> bool:
	return OS.has_feature("demo") or "--demo" in OS.get_cmdline_user_args()
# Hands-on building (GDD §5.4): delivered materials wait until workers stand at the
# wall and raise it. Debug builds: `-- --instant-build` for the old deliver-and-done
# rule, to A/B the two in playtests.
var active_build: bool = not (OS.is_debug_build() and "--instant-build" in OS.get_cmdline_user_args())
const MAX_BREACHES := 10   # enemies that may reach the inner city before the city falls

# Tower-defence layer (GDD §5.6), each on by default and each switched off from the
# command line to A/B it in playtests: `-- --no-waves`, `-- --no-sun`, `-- --no-posts`.
# The host's choice is sent to everyone who joins (send_state_to).
#   waves — the enemy comes in announced waves over a thinner trickle
#   sun   — each day has a sun clock; work left at nightfall carries over, and a section
#           not finished by the stars of its last day is lost
#   posts — watch posts behind the wall: raise one with timber, feed it sling stones,
#           and a slinger up top chips at the enemy
var waves: bool = "--no-waves" not in OS.get_cmdline_user_args()
var sun: bool = "--no-sun" not in OS.get_cmdline_user_args()
var posts: bool = "--no-posts" not in OS.get_cmdline_user_args()
# Trades (GDD §5.10): longer hands-on work, each trade quicker at its own (Trade).
# `-- --no-trades` for the old times and no perks
var trades: bool = "--no-trades" not in OS.get_cmdline_user_args()
# Saboteur (GDD §5.9): from day 6 one slips in now and then to strew the yard's piles.
# `-- --no-saboteur` to play without him
var saboteur: bool = "--no-saboteur" not in OS.get_cmdline_user_args()
# The sling pass (GDD §5.16). `-- --no-tell`: foes strike without drawing back first (no
# wind-up to read, nothing to knock aside). `-- --no-true-shot`: no glint, every throw alike
var tell: bool = "--no-tell" not in OS.get_cmdline_user_args()
var true_shot: bool = "--no-true-shot" not in OS.get_cmdline_user_args()
# `-- --no-riposte`: a sword cut in a foe's draw only knocks the strike aside, like any hit
var riposte: bool = "--no-riposte" not in OS.get_cmdline_user_args()
# Simple game (Settings.simple_game): the host's pick, as clients last heard it. Read it
# through simplified()
var simple := false
signal rules_changed

# Sun clock ("from the rising of the morning till the stars appeared", Neh. 4:21): the
# whole stretch is the goal, over its days; every day of a section has the same light,
# the section's par split over its days × slack (1 = the days add up to par; 1.2 by default). A day ends
# at the stars or when the stretch stands; it must stand by the stars of its last day.
# TODO: tune from playtests — `-- --sun-slack=1.3` to try another; the DayDirector log
# prints each day's work time against its daylight.
var sun_slack := _arg_float("--sun-slack=", 1.2)
const SUN_SOLO  := 1.25    # a lone worker gets a little longer (solo_mult: fades as bots add up)
const SUN_LOW   := 0.25    # share of daylight left when "the sun is low" warns
# Why the run was lost: "overrun" (breaches) or "stars" (a section unfinished at nightfall
# of its last day). Synced before the LOST phase.
var loss_reason := "overrun"
# Seconds of daylight today and how much is left (0 total = no clock). Server counts
# down; clients count along and are corrected now and then (sync_sun).
var sun_total := 0.0
var sun_left := 0.0
signal sun_changed

# Section rating (GDD §6.1): three marks, each earned on its own when the section's
# last unit stands. Stored per section as a bitmask; -1 = not finished this run.
enum Mark { PACE = 1, CLEAN = 2, SOUND = 4 }
const MARKS := [Mark.PACE, Mark.CLEAN, Mark.SOUND]
const MARK_NAMES := { Mark.PACE: "In good time", Mark.CLEAN: "None got through", Mark.SOUND: "The wall holds" }
# Par: seconds of work (WORK phase only) for a whole section, plus extra for the twists
# that slow the work down. A section may set its own "par". Now it only sizes the sun clock;
# the "In good time" mark counts days (pace_spare_needed). TODO: tune from playtests
# (DayDirector prints each section's time against par).
const PAR_TIME := 420.0
const PAR_TWIST := { "beams": 60.0, "salvage": 60.0, "mixing": 60.0, "haul": 120.0, "thick": 60.0 }
const SOUND_WALL := 0.8    # average wall health for "The wall holds"
# Each player's best marks per section, kept across runs (for replays)
const PROGRESS_PATH := "user://progress.cfg"

# GATHER: before day 1, waiting for the crew to join; STORY: story cards before a day
# (appended so synced ints stay stable)
enum Phase { DAWN, WORK, DUSK, WON, LOST, GATHER, STORY }

signal day_changed(day: int)
signal section_changed(section_index: int)
signal phase_changed(phase: Phase)
signal breaches_changed(count: int)
signal progress_changed(done: int, total: int)
signal crew_changed(size: int)
signal section_rated(section_index: int, mask: int)
signal game_won
signal game_lost

var current_day: int = 1
var current_section_index: int = 0
var phase: Phase = Phase.GATHER
var breaches: int = 0
var targets_done: int = 0
var targets_total: int = 0
# Players in the session, bots included (the work front, the pips)
var crew_size: int = 1
# The crew as the work and the light weigh it: a person counts whole, a bot by its skill's
# "crew" (BotBrain.SKILLS, as WaveManager sizes the enemy) — so adding a weak bot never
# costs a lone player more than it brings (cost_crew, solo_mult)
var crew_weight: float = 1.0
# peer_id → { "role": String }
var players: Dictionary = {}
var section_marks: Array = _no_marks()
# The run as the scribe's map remembers it (CircuitMap `aged`), per section: breaches,
# pieces knocked down, days worked till the stars, finished late / with days to spare.
# Every peer writes its own from what it already sees (state changes, the dusk tally).
var chronicle: Array = _no_chronicle()
# Replay: the host picked one section from the map (SectionPicker) — the run plays just
# that section and ends when it stands. -1 = the full campaign. Set by the menu before
# hosting, synced to clients; reset() leaves it alone (it outlives the game scene).
var replay_section := -1
# Menu only: reopen the section picker on this section when back from a replay
var picker_return := -1
# "Play again" from the end screen: the next run starts on this day (the first day of the
# stretch that was lost; 1 after a win). -1 = day 1 as usual. Outlives the scene reload.
var restart_day := -1
# The last section rated beat this player's saved best (end screen says so)
var rating_improved := false
# Started mid-campaign with `--day=N`: sections are only partly played, so no bests saved
var _debug_start := false
# Title screen: the menu's live backdrop — bots play the real game behind it, and
# like a `--day=N` run nothing it does is saved (no marks, met folk or achievements)
var attract := false
# "Learn the basics" from the title: a solo practice at the Sheep Gate walked through by
# Tutorial — no waves, no story, no bots but the one that falls; nothing it does is saved.
# Set by the menu, cleared when the menu opens again (outlives reset() like replay_section).
var tutorial := false
# "Explore Jerusalem" from the title: a solo sandbox, no enemy, no clock — the city as far
# as this player's wall stands (built_sections), and once it all does, the Festival of
# Booths (Neh. 8). Festival runs it. Set by the menu like `tutorial`; nothing it does is saved.
var festival := false
const FESTIVAL_SECTION := 8   # the Water Gate: "the broad place before the water gate" (Neh. 8:1)
var _met := {}             # Friends and Foes: key → true, loaded on first use

# ── Queries ────────────────────────────────────────────────

func get_section_for_day(day: int) -> Dictionary:
	return SECTIONS[_section_index_for_day(day)]

func get_current_section() -> Dictionary:
	return get_section_for_day(current_day)

## The simple game (Settings.simple_game) is in play: the host reads its own setting live,
## clients what the host sent. Never in the practice or Explore Jerusalem
func simplified() -> bool:
	if tutorial or festival:
		return false
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		return Settings.simple_game
	return simple

## Trades in play (GDD §5.10): the rule, and not the simple game (every worker plain)
func trades_on() -> bool:
	return trades and not simplified()

## The saboteur in play (GDD §5.9): the rule, and not the simple game
func saboteur_on() -> bool:
	return saboteur and not simplified()

## The marks a stretch can earn: the simple game has no "In good time"
func marks_in_play() -> Array:
	return [Mark.CLEAN, Mark.SOUND] if simplified() else MARKS

## Server: the host changed a rule mid-session (the simple game) — tell everyone
func share_rules() -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_rules.rpc(waves, sun, posts, trades, saboteur, tell, true_shot, riposte, simplified())
	rules_changed.emit()

## "In good time": days a stretch must have left over when its last unit stands — one for
## a short stretch, two from five days up (the sun clock already spreads par over the days)
func pace_spare_needed(section_index := current_section_index) -> int:
	return 2 if SECTIONS[section_index]["days"].size() >= 5 else 1

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

## Enemy pace for this section (Fountain Gate is a breather, the finale the hardest)
func pressure() -> float:
	return get_current_section().get("pressure", 1.0) * mod("pressure")

## The boon's modifier `key` for this stretch (1 = none)
func mod(key: String) -> float:
	var plain := simplified()   # no boons, no rumour: no hidden modifiers in the simple game
	var v: float = BOONS[boon]["mods"].get(key, 1.0) if BOONS.has(boon) and not plain else 1.0
	if key == "work":
		v *= 1.0 + HOUSEHOLD_WORK * households_fed
		v *= 1.0 - HUNGRY_WORK * hungry_left
		if rumour and not plain:
			v *= RUMOUR_WORK
		if Time.get_ticks_msec() < spur_until:
			v *= SPUR_WORK
	return v

## Experimental call-early (GDD §5.21): a wave called in early spurs the whole crew. Every
## peer sets its own clock from WaveManager's rpc.
const SPUR_WORK := 1.15
const SPUR_SECONDS := 40.0
var spur_until := 0

## Households fed this stretch (Neh. 5, Households): each family back at the wall adds to
## the work. Every peer counts its own; reset when the stretch changes.
const HOUSEHOLD_WORK := 0.06
var households_fed := 0

## Setbacks (GDD §5.15). Households left hungry when the Fountain Gate ends are missing from
## the next stretch's work (5:3-5); an open letter's rumour weakens everyone's hands until
## it is answered (6:5-9). Set on every peer by DayDirector / Households; cleared per stretch.
const HUNGRY_WORK := 0.06
const RUMOUR_WORK := 0.9
var hungry_left := 0
var rumour := false

## The scribe's margin notes for this stretch (what went wrong, with its verse), newest last
signal journal_changed
var journal: Array[String] = []

func add_journal(text: String) -> void:
	journal.append(text)
	if journal.size() > 2:
		journal.pop_front()
	journal_changed.emit()

## The watch posts stand from dawn (the boon says so)
func boon_posts() -> bool:
	return BOONS.has(boon) and BOONS[boon].get("posts", false)

## The two ways to meet stretch `section_index`
func choices_for(section_index: int) -> Array:
	return SECTIONS[section_index].get("choices", DEFAULT_CHOICES)

## What a boon gives and what it costs, in the player's language: { "gain": [...], "cost": [...] }
func boon_lines(key: String) -> Dictionary:
	var gain: PackedStringArray = []
	var cost: PackedStringArray = []
	var boon_def: Dictionary = BOONS[key]
	for k: String in boon_def["mods"]:
		var v: float = boon_def["mods"][k]
		var text: Array = MOD_TEXT[k]
		var more := v > 1.0
		var pct := roundi(absf(v - 1.0) * 100.0)
		var line: String = tr(text[1] if more else text[2]) % pct
		if more == text[0]:
			gain.append(line)
		else:
			cost.append(line)
	if boon_def.get("posts", false):
		gain.append(tr("The watch posts stand from dawn, stocked with stone"))
	return { "gain": gain, "cost": cost }

## Today is a night-watch day: darkness falls while the work goes on
func is_night_day() -> bool:
	return has_twist("night") and day_in_section(current_day).x >= NIGHT_FROM_DAY_IN_SECTION

## Twists this section has that the one before it didn't
func new_twists() -> Array:
	var i := current_section_index
	var before: Array = SECTIONS[i - 1].get("twists", []) if i > 0 else []
	return get_current_section().get("twists", []).filter(func(t): return t not in before)

## Seconds of daylight for each day of the current section
func day_length() -> float:
	var t := par_time() / day_in_section(current_day).y * sun_slack
	return t * solo_mult(SUN_SOLO)

## Crew size for the cost tables: whole workers only, so a lone player with a bot or two
## of less than a full worker still pays a lone builder's costs
func cost_crew() -> int:
	return maxi(1, floori(crew_weight + 0.01))

## A lone worker's edge `mult`, fading to none as helpers add up to one more worker
func solo_mult(mult: float) -> float:
	return lerpf(mult, 1.0, clampf(crew_weight - 1.0, 0.0, 1.0))

static func _arg_float(prefix: String, default: float) -> float:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix).to_float()
	return default

## The day's last light is running out
func sun_low() -> bool:
	return sun_total > 0.0 and sun_left < sun_total * SUN_LOW

## Today is the last day of its section — nightfall with work left loses the run
func last_day_of_section() -> bool:
	var pos := day_in_section(current_day)
	return pos.x == pos.y - 1

func par_time(section_index := current_section_index) -> float:
	var sec: Dictionary = SECTIONS[section_index]
	if sec.has("par"):
		return sec["par"]
	var par := PAR_TIME
	for twist: String in sec.get("twists", []):
		par += PAR_TWIST.get(twist, 0.0)
	return par

func mark_count(mask: int) -> int:
	return MARKS.filter(func(m: int): return mask >= 0 and mask & m).size()

## Marks earned this run, all sections
func total_marks() -> int:
	return section_marks.reduce(func(acc: int, m: int): return acc + mark_count(m), 0)

## Best marks this player has ever earned on a section (bitmask, -1 = never finished)
func best_marks(section_index: int) -> int:
	var cfg := ConfigFile.new()
	if cfg.load(PROGRESS_PATH) != OK:
		return -1
	return cfg.get_value("marks", str(section_index), -1)

# Friends and Foes: the section where each foe first shows (enemies by WaveManager's
# unlock days, the leaders by their story beat, the messenger by the "schemes" twist)
const MET_AT := { "scout": 0, "brute": 2, "raider": 4, "saboteur": 1, "sanballat": 2, "tobiah": 3, "geshem": 5, "messenger": 10 }

## Friends and Foes (main menu): who this player has met, kept across runs. Enemies and
## the messenger count on sight, the three leaders when their story beat plays.
## Debug builds: `-- --unlock-all` shows everyone.
func has_met(key: String) -> bool:
	_load_met()
	return _met.has(key) or (OS.is_debug_build() and "--unlock-all" in OS.get_cmdline_user_args())

## Every peer records its own; not for `--day=N` runs, like the marks
func mark_met(key: String) -> void:
	_load_met()
	if _met.has(key) or _debug_start:
		return
	_met[key] = true
	var cfg := ConfigFile.new()
	cfg.load(PROGRESS_PATH)
	cfg.set_value("met", key, true)
	cfg.save(PROGRESS_PATH)

func _load_met() -> void:
	if not _met.is_empty():
		return
	_met = { "": true }   # loaded, even when nothing has been met yet
	var cfg := ConfigFile.new()
	if cfg.load(PROGRESS_PATH) == OK and cfg.has_section("met"):
		for k: String in cfg.get_section_keys("met"):
			_met[k] = true
	# Progress from before this was tracked: a finished section means its foes were met
	for k: String in MET_AT:
		if best_marks(MET_AT[k]) >= 0:
			_met[k] = true

func is_replay() -> bool:
	return replay_section >= 0

## Early beta: every section open on the map, so testers can jump to any stretch
const ALL_SECTIONS_OPEN := true

## Picked on the map: the first section is always open; each next one once the one
## before it has been finished (any marks). Debug builds: `-- --unlock-all`.
func is_unlocked(section_index: int) -> bool:
	if is_demo() and section_index >= DEMO_SECTIONS:
		return false
	if ALL_SECTIONS_OPEN or section_index == 0 or best_marks(section_index) >= 0 or best_marks(section_index - 1) >= 0:
		return true
	return OS.is_debug_build() and "--unlock-all" in OS.get_cmdline_user_args()

## Explore Jerusalem: each stretch this player has built — finished in any run (a best
## mark), or behind the saved campaign's stretch. Debug builds: `-- --unlock-all` = all,
## `-- --built=N` = just the first N (the saved progress ignored).
func built_sections() -> Array[bool]:
	var past: int = campaign_save().get("section", 0)
	var only := -1
	if OS.is_debug_build():
		for arg in OS.get_cmdline_user_args():
			if arg == "--unlock-all":
				only = SECTIONS.size()
			elif arg.begins_with("--built="):
				only = arg.trim_prefix("--built=").to_int()
	var out: Array[bool] = []
	for i in SECTIONS.size():
		out.append(i < only if only >= 0 else (i < past or best_marks(i) >= 0))
	return out

## The whole wall stands: Explore Jerusalem keeps the Festival of Booths
func wall_finished() -> bool:
	return not built_sections().has(false)

## The first stretch of a real run (the Sheep Gate), in either game: timber and stone only.
## The frames go up in timber and the courses in stone; there's no mortar (the finish and any
## mending take stone) and no watch posts, so a new player meets two materials and the wall
## before anything else (playtest 2026-10-04)
func first_stretch() -> bool:
	return current_section_index == 0 and not attract and not free_play()

## A practice or the festival: no waves, no story, nothing saved
func free_play() -> bool:
	return tutorial or festival

func is_over() -> bool:
	return phase == Phase.WON or phase == Phase.LOST

# ── Mutations (server) ─────────────────────────────────────

func set_phase(p: Phase) -> void:
	_apply(current_day, current_section_index, p, breaches, targets_done, targets_total)

func set_progress(done: int, total: int) -> void:
	_apply(current_day, current_section_index, phase, breaches, done, total)

## Server: the run is lost for `reason` ("overrun" | "stars")
func lose(reason: String) -> void:
	if is_over():
		return
	_apply_loss(reason)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_loss.rpc(reason)
	set_phase(Phase.LOST)

@rpc("authority", "call_remote", "reliable")
func _sync_loss(reason: String) -> void:
	_apply_loss(reason)

func _apply_loss(reason: String) -> void:
	loss_reason = reason

## Server: set today's daylight (total, left); every peer then counts down during WORK
func set_sun(total: float, left: float) -> void:
	_apply_sun(total, left)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_sun.rpc(total, left)

@rpc("authority", "call_remote", "reliable")
func _sync_sun(total: float, left: float) -> void:
	_apply_sun(total, left)

func _apply_sun(total: float, left: float) -> void:
	sun_total = total
	sun_left = left
	sun_changed.emit()

# Every peer: the clock runs while the day's work does
func _process(delta: float) -> void:
	if sun_total > 0.0 and phase == Phase.WORK:
		sun_left = maxf(0.0, sun_left - delta)

func add_breach() -> void:
	if is_over():
		return
	if breaches + 1 >= MAX_BREACHES:
		_apply_loss("overrun")
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			_sync_loss.rpc("overrun")
	var b := breaches + 1
	_apply(current_day, current_section_index, Phase.LOST if b >= MAX_BREACHES else phase,
		b, targets_done, targets_total)

## Returns false when there is no next day (campaign won). `to_day` jumps ahead (a
## stretch finished early under the sun clock skips its days to spare).
func advance_day(to_day := -1) -> bool:
	if current_day >= TOTAL_DAYS:
		set_phase(Phase.WON)
		return false
	var day := current_day + 1 if to_day < 0 else to_day
	_apply(day, _section_index_for_day(day), Phase.DAWN, breaches, 0, 0)
	return true

func reset() -> void:
	current_day = 1
	current_section_index = 0
	phase = Phase.GATHER
	breaches = 0
	targets_done = 0
	targets_total = 0
	loss_reason = "overrun"
	sun_total = 0.0
	sun_left = 0.0
	players.clear()
	section_marks = _no_marks()
	chronicle = _no_chronicle()
	boon = ""
	_debug_start = attract or tutorial or festival

## Server: a replay starts on its section's first day
func apply_replay() -> void:
	if is_replay():
		var day: int = SECTIONS[replay_section]["days"][0]
		_apply(day, replay_section, phase, breaches, targets_done, targets_total)

## Server: the festival is held at the Water Gate, on its first (daylit) day
func apply_festival() -> void:
	if festival:
		var day: int = SECTIONS[FESTIVAL_SECTION]["days"][0]
		_apply(day, FESTIVAL_SECTION, phase, breaches, targets_done, targets_total)

## Festival: walked round to another stretch (its first day, so the section follows)
func festival_district(section_index: int) -> void:
	_apply(SECTIONS[section_index]["days"][0], section_index, phase, breaches, targets_done, targets_total)

## Server: a "Play again" run picks up where the last one asked (see restart_day). A run
## picked up from the campaign save (Continue, or trying a stretch again) gets back the
## marks and the scribe's map of the stretches already built.
func apply_restart() -> void:
	if restart_day > 0 and not is_replay():
		var saved := campaign_save()
		if saved.get("day", -1) == restart_day:
			# Quietly: these were judged (and their achievements given) when first earned.
			# Clients get them with the rest of the state when they ask for the roster.
			for i in mini(section_marks.size(), saved["marks"].size()):
				section_marks[i] = saved["marks"][i]
			for i in mini(chronicle.size(), saved["chronicle"].size()):
				chronicle[i] = saved["chronicle"][i]
		_apply(restart_day, _section_index_for_day(restart_day), phase, breaches, targets_done, targets_total)
	restart_day = -1

# ── Campaign save (Continue) ───────────────────────────────
# A campaign is ~1.5 hours; a crew that stops after three stretches must be able to pick
# it up again. At the dawn of each new stretch (after the first) the run is saved as it
# stood: that stretch's first day, the marks and the chronicle so far. Cleared on the win.
# Every peer keeps its own; the host's is the one that counts.

## The saved campaign: { day, section, marks, chronicle }, or {} when there is none
func campaign_save() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(PROGRESS_PATH) != OK or not cfg.has_section("campaign"):
		return {}
	var day: int = cfg.get_value("campaign", "day", -1)
	if day < 1 or day > (DEMO_LAST_DAY if is_demo() else TOTAL_DAYS):
		return {}
	return { "day": day, "section": _section_index_for_day(day),
		"marks": cfg.get_value("campaign", "marks", []), "chronicle": cfg.get_value("campaign", "chronicle", []) }

func _saveable() -> bool:
	return not (_debug_start or attract or tutorial or festival or is_replay())

## This run is a campaign the save follows (the HUD says so in the pause menu)
func saves_campaign() -> bool:
	return _saveable()

## The dawn of a stretch whose start is what the save now holds (Continue resumes here)
func dawn_saved() -> bool:
	return _saveable() and campaign_save().get("day", -1) == current_day

func _save_campaign(day: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PROGRESS_PATH)
	cfg.set_value("campaign", "day", day)
	cfg.set_value("campaign", "marks", section_marks.duplicate())
	cfg.set_value("campaign", "chronicle", chronicle.duplicate(true))
	cfg.save(PROGRESS_PATH)

func clear_campaign() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PROGRESS_PATH) == OK and cfg.has_section("campaign"):
		cfg.erase_section("campaign")
		cfg.save(PROGRESS_PATH)

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
			_debug_start = true

## Title screen: the live backdrop opens on a random stretch — any but the night one,
## whose dark would sit badly under the parchment menu
func apply_attract_start() -> void:
	var picks := range(SECTIONS.size()).filter(func(i: int): return not "night" in SECTIONS[i]["twists"])
	var section: int = picks.pick_random()
	_apply(SECTIONS[section]["days"][0], section, phase, breaches, targets_done, targets_total)

## Push full state to one peer (late join)
func send_state_to(peer_id: int) -> void:
	_sync_rules.rpc_id(peer_id, waves, sun, posts, trades, saboteur, tell, true_shot, riposte, simplified())
	_sync_replay.rpc_id(peer_id, replay_section)
	_sync.rpc_id(peer_id, current_day, current_section_index, phase, breaches, targets_done, targets_total)
	_sync_crew.rpc_id(peer_id, crew_size, crew_weight)
	_sync_boon.rpc_id(peer_id, boon)
	_sync_sun.rpc_id(peer_id, sun_total, sun_left)
	for i in section_marks.size():
		if section_marks[i] >= 0:
			_sync_marks.rpc_id(peer_id, i, section_marks[i])

## Server: the crew's pick for the stretch now dawning (DayDirector)
func set_boon(key: String) -> void:
	_apply_boon(key)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_boon.rpc(key)

@rpc("authority", "call_remote", "reliable")
func _sync_boon(key: String) -> void:
	_apply_boon(key)

func _apply_boon(key: String) -> void:
	key = key if BOONS.has(key) else ""
	if current_section_index < chronicle.size():
		chronicle[current_section_index]["boon"] = key   # the scribe notes how the stretch was met
	if key != boon:
		boon = key
		boon_changed.emit()

## Server: players joined/left, or the bots' skill changed (no weight: all whole workers)
func set_crew(size: int, weight := -1.0) -> void:
	if weight < 0.0:
		weight = size
	_apply_crew(size, weight)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_crew.rpc(size, weight)

## Server: the section's last unit stands — record its marks everywhere
func rate_section(section_index: int, mask: int) -> void:
	_apply_marks(section_index, mask)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_marks.rpc(section_index, mask)

@rpc("authority", "call_remote", "reliable")
func _sync_rules(w: bool, s: bool, p: bool, t: bool, sab: bool, tl: bool, ts: bool, rp: bool, sim: bool) -> void:
	waves = w
	sun = s
	posts = p
	trades = t
	saboteur = sab
	tell = tl
	true_shot = ts
	riposte = rp
	simple = sim
	rules_changed.emit()

@rpc("authority", "call_remote", "reliable")
func _sync_replay(section_index: int) -> void:
	replay_section = section_index

@rpc("authority", "call_remote", "reliable")
func _sync_marks(section_index: int, mask: int) -> void:
	_apply_marks(section_index, mask)

func _apply_marks(section_index: int, mask: int) -> void:
	section_marks[section_index] = mask
	# Every peer keeps its own best (more marks wins; finishing at all counts too)
	var best := best_marks(section_index)
	rating_improved = best < 0 or mark_count(mask) > mark_count(best)
	if not _debug_start and rating_improved:
		var cfg := ConfigFile.new()
		cfg.load(PROGRESS_PATH)
		cfg.set_value("marks", str(section_index), mask)
		cfg.save(PROGRESS_PATH)
	section_rated.emit(section_index, mask)

func _no_chronicle() -> Array:
	var a := []
	for i in SECTIONS.size():
		a.append({ "breaches": 0, "knocked": 0, "nightfalls": 0, "days": 0, "done": false, "late": false, "spare": 0, "boon": "", "close": false })
	return a

## Every peer, at each dusk (Main): the day goes into the chronicle
func chronicle_day(stats: Dictionary) -> void:
	var c: Dictionary = chronicle[current_section_index]
	c["days"] += 1
	if stats.get("unfinished", 0) > 0:
		c["nightfalls"] += 1
	if stats.has("marks"):
		c["done"] = true
		c["late"] = stats.get("spare", 0) < stats.get("pace_needed", 0)
		c["spare"] = stats.get("spare", 0)
		c["close"] = stats.has("close")   # stood by a hair (DayDirector._close_call)

func _no_marks() -> Array:
	var a := []
	a.resize(SECTIONS.size())
	a.fill(-1)
	return a

@rpc("authority", "call_remote", "reliable")
func _sync_crew(size: int, weight: float) -> void:
	_apply_crew(size, weight)

func _apply_crew(size: int, weight: float) -> void:
	size = maxi(1, size)
	weight = maxf(1.0, weight)
	if size != crew_size or not is_equal_approx(weight, crew_weight):
		crew_size = size
		crew_weight = weight
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
	# Into the chronicle: one got through; a standing piece knocked back down
	if section >= 0 and section < chronicle.size():
		if b > breaches and not attract:
			chronicle[section]["breaches"] += b - breaches
		if total == targets_total and done < targets_done and p == Phase.WORK:
			chronicle[section]["knocked"] += 1
	current_day = day
	current_section_index = section
	phase = p
	breaches = b
	targets_done = done
	targets_total = total
	if section_new:
		# A new stretch's dawn (not the first: a fresh run must not wipe a saved one)
		if p == Phase.DAWN and section > 0 and _saveable():
			_save_campaign(day)
		journal.clear()
		rumour = false
		journal_changed.emit()
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
			if _saveable():
				clear_campaign()
			game_won.emit()
		elif p == Phase.LOST:
			game_lost.emit()

func _section_index_for_day(day: int) -> int:
	for i in SECTIONS.size():
		if day in SECTIONS[i]["days"]:
			return i
	return 0
