class_name SectionBeats
extends Node

# The stretch's own story, told while it goes up (GDD §6.4). Sections run 2 to 6 days and
# the sun clock gives every section about the same work whatever its day count, so beats
# are keyed to how far the stretch stands, not to the day: "half" when half its units
# stand, "last" when one is left. A beat is a watchman's call (a verse, where the text
# has one) and, usually, a warned pack that comes at a chosen place — the enemy answers
# the work (Neh. 4:7, "they heard that the repairing… went forward… they were very
# angry"). Each fires once per stretch, never twice at once.
# Server decides and spawns (through WaveManager); every peer hears the call and sees the
# pointer, and gets beat_fired (Leaders shows the named foes on it).
# `-- --no-beats` to play without them.

signal beat_fired(section_index: int, key: String, beat: Dictionary)

const POLL      := 0.5
const WARN      := 5.0      # like a wave: time to stock a post or take up a sling
const GAP       := 0.35     # seconds between members of the pack
const SPREAD    := 2.5
const FLANK_X   := 14.0
const GATE_X    := 3.0
const PER_CREW  := 2        # one more in the pack for every two workers past the first
const COLOR     := Color(0.72, 0.22, 0.18)
const VERSE_HOLD := 6.5

# Section index → { "half" | "last": beat }. A beat:
#   call   — the watchman's words (always)
#   verse  — [WEB text, ref], said after the call
#   pack   — [[Enemy.Type, count], …] (none = just the call)
#   at     — "gate" | "flank" (one end) | "both" (both ends) | "east" (the end that faces
#            east on the real ring) | "yard" (the end nearest the supply yard)
#   leader — for Leaders: "sanballat" | "tobiah" | "geshem" | "all" | ""
# Only foes already unlocked on those days (brutes from day 9, raiders from 21).
const S := Enemy.Type.SCOUT
const B := Enemy.Type.BRUTE
const R := Enemy.Type.RAIDER
const SAB := Enemy.Type.SABOTEUR
const BEATS := {
	0: {   # Sheep Gate — quiet start
		"half": { "call": "The priests' stretch is rising!",
			"verse": ["The God of heaven will prosper us. Therefore we, his servants, will arise and build", "Neh. 2:20"] },
		"last": { "call": "They'll try the gate before its doors hang!", "pack": [[S, 3]], "at": "gate" },
	},
	1: {   # Fish Gate
		"half": { "call": "Both ends at once — split up!", "pack": [[S, 2]], "at": "both" },
		"last": { "call": "A rush at the gate!", "pack": [[S, 4]], "at": "gate" },
	},
	2: {   # Jeshanah Gate — brutes arrive
		"half": { "call": "Brutes, for the new stones!", "pack": [[B, 2], [S, 1]], "at": "flank" },
		"last": { "call": "They're at the gate — hold it!", "pack": [[B, 1], [S, 3]], "at": "gate" },
	},
	3: {   # Broad Wall — the wall at half height, and their anger (Neh. 4:6-7)
		"half": { "call": "Half its height! And they've heard of it…",
			"verse": ["So we built the wall; and all the wall was joined together to half its height, for the people had a mind to work.", "Neh. 4:6"],
			"pack": [[S, 2], [B, 1]], "at": "both", "leader": "sanballat" },
		"last": { "call": "They want the last gap!", "pack": [[B, 2], [S, 2]], "at": "gate" },
	},
	4: {   # Tower of the Ovens — the conspiracy, and the plan to stop the work (4:8, 4:11)
		"half": { "call": "They've all come together!",
			"verse": ["and they all conspired together to come and fight against Jerusalem, and to cause confusion among us.", "Neh. 4:8"],
			"pack": [[S, 4], [B, 2]], "at": "flank", "leader": "tobiah" },
		"last": { "call": "Quiet ones — after the yard!",
			"verse": ["They will not know or see, until we come in among them and kill them, and cause the work to cease.", "Neh. 4:11"],
			"pack": [[SAB, 1], [S, 3]], "at": "flank" },
	},
	5: {   # Valley Gate — peak one
		"half": { "call": "Raiders up both sides of the valley!", "pack": [[R, 2], [S, 1]], "at": "both" },
		"last": { "call": "Everything they have — to the gate!",
			"verse": ["Wherever you hear the sound of the trumpet, rally there to us. Our God will fight for us.", "Neh. 4:20"],
			"pack": [[B, 2], [R, 2], [S, 3]], "at": "gate", "leader": "sanballat" },
	},
	6: {   # Gate of the Ash Heaps — the long haul
		"half": { "call": "Raiders on the haul road!", "pack": [[R, 3]], "at": "yard" },
		"last": { "call": "Brutes for the gate!", "pack": [[B, 3]], "at": "gate" },
	},
	7: {   # Fountain Gate — the breather, and the trouble inside (Neh. 5): no packs
		"half": { "call": "The families are back on their land.",
			"verse": ["We will restore them, and will require nothing of them. We will do so, even as you say.", "Neh. 5:12"] },
		"last": { "call": "Quiet in the valley today.",
			"verse": ["They said, “Let’s rise up and build.” So they strengthened their hands for the good work.", "Neh. 2:18"] },
	},
	8: {   # Water Gate — out of the dark
		"half": { "call": "Out of the dark — both ends!", "pack": [[R, 2], [S, 2]], "at": "both" },
		"last": { "call": "At the gate! Torches!", "pack": [[B, 2], [S, 2]], "at": "gate" },
	},
	9: {   # Horse Gate — the lanes
		"half": { "call": "Brutes for the priests' houses!", "pack": [[B, 3]], "at": "gate" },
		"last": { "call": "Both ends — mind the lanes!", "pack": [[R, 2], [B, 1]], "at": "both" },
	},
	10: {   # East Gate — Geshem's men from the east; the answer to Ono (6:3, 6:9)
		"half": { "call": "Geshem's raiders, from the east!",
			"verse": ["I am doing a great work, so that I can’t come down.", "Neh. 6:3"],
			"pack": [[R, 4]], "at": "east", "leader": "geshem" },
		"last": { "call": "The last of it — hold on!",
			"verse": ["But now, strengthen my hands.", "Neh. 6:9"],
			"pack": [[B, 2], [R, 2], [S, 2]], "at": "both" },
	},
	11: {   # Miphkad Gate — the finale
		"half": { "call": "They're all coming!", "pack": [[B, 2], [R, 2], [S, 2]], "at": "both" },
		"last": { "call": "The last stone — all of them at once!",
			"verse": ["So we did the work. Half of the people held the spears from the rising of the morning until the stars appeared.", "Neh. 4:21"],
			"pack": [[B, 3], [R, 3], [S, 3]], "at": "both", "leader": "all" },
	},
}

var enabled: bool = "--no-beats" not in OS.get_cmdline_user_args()

var _fired := {}     # key → true, this stretch
var _poll := 0.0
var _queue: Array = []   # server: [type, position] still to come in the warned pack
var _warn := 0.0
var _gap := 0.0

@onready var _waves: Node = get_parent().get_node("WaveManager")

func _ready() -> void:
	add_to_group("section_beats")
	GameState.section_changed.connect(_reset.unbind(1))

func _reset() -> void:
	_fired.clear()
	_queue.clear()

## The beats a section has, "half" / "last" → beat
static func beats_for(section_index: int) -> Dictionary:
	return BEATS.get(section_index, {})

func _process(delta: float) -> void:
	if not multiplayer.is_server() or not enabled or GameState.free_play():
		return
	if GameState.phase != GameState.Phase.WORK:
		_queue.clear()   # the day ended before the pack came: it doesn't come
		return
	if not _queue.is_empty():
		_tick_pack(delta)
		return
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = POLL
	var key := _due()
	if not key.is_empty():
		_fire(key)

## The beat now due, or "" — "half" before "last", each once a stretch
func _due() -> String:
	var total := GameState.targets_total
	var done := GameState.targets_done
	if total < 2 or done >= total:
		return ""
	var beats := beats_for(GameState.current_section_index)
	if beats.has("half") and not _fired.has("half") and done * 2 >= total:
		return "half"
	if beats.has("last") and not _fired.has("last") and done == total - 1:
		return "last"
	return ""

func _fire(key: String) -> void:
	_fired[key] = true
	var i := GameState.current_section_index
	var beat: Dictionary = beats_for(i)[key]
	var spots := _spots(beat.get("at", "gate"), i)
	_queue = _pack(beat.get("pack", []), spots)
	_warn = WARN
	_gap = 0.0
	print("SectionBeats: %s \"%s\" — %d foes" % [GameState.SECTIONS[i]["name"], key, _queue.size()])
	_announce.rpc(i, key, spots if not _queue.is_empty() else [])

func _tick_pack(delta: float) -> void:
	if _warn > 0.0:
		_warn -= delta
		return
	_gap -= delta
	if _gap > 0.0:
		return
	_gap = GAP
	var next: Array = _queue.pop_front()
	if _waves.enemies_root.get_child_count() < _waves.MAX_ALIVE_CAP:
		_waves._do_spawn(next[0], next[1])

## Where the pack comes in (outside the wall, at the enemy line)
func _spots(at: String, section_index: int) -> Array:
	var z: float = _waves.SPAWN_Z
	match at:
		"both":
			return [Vector3(-FLANK_X, 0.1, z), Vector3(FLANK_X, 0.1, z)]
		"flank":
			return [Vector3(FLANK_X * (1.0 if randf() < 0.5 else -1.0), 0.1, z)]
		"east":
			var e := RingCompass.bearing_on_site(section_index, 90.0)
			return [Vector3(FLANK_X * (1.0 if e.x >= 0.0 else -1.0), 0.1, z)]
		"yard":
			return [Vector3(FLANK_X * (1.0 if GameState.yard_center().x >= 0.0 else -1.0), 0.1, z)]
	return [Vector3(randf_range(-GATE_X, GATE_X), 0.1, z)]

## The pack, members dealt round the spots in turn. Grows with the crew (a bot counts by
## its skill, like the waves) and the host's difficulty; a saboteur only when he's on.
func _pack(pack: Array, spots: Array) -> Array:
	var out := []
	var extra := floori((_waves._crew() - 1.0) / PER_CREW)
	var pace: float = Settings.diff()["pace"]
	for entry: Array in pack:
		var type: Enemy.Type = entry[0]
		if type == Enemy.Type.SABOTEUR and not GameState.saboteur:
			continue
		var n: int = entry[1]
		if type != Enemy.Type.SABOTEUR:
			n = maxi(1, roundi((n + extra) * pace))
			extra = 0   # the crew's extra goes on the first kind only
		for k in n:
			out.append(type)
	var i := 0
	var placed := []
	for type in out:
		var at: Vector3 = spots[i % spots.size()]
		placed.append([type, at + Vector3(randf_range(-SPREAD, SPREAD), 0.0, randf_range(-1.0, 1.0))])
		i += 1
	return placed

# Every peer: the watchman nearest the danger calls it (and the verse), the bell rings,
# a pointer shows each spot; Leaders and the like hear beat_fired
@rpc("authority", "call_local", "reliable")
func _announce(section_index: int, key: String, spots: Array) -> void:
	var beat: Dictionary = beats_for(section_index).get(key, {})
	if beat.is_empty():
		return
	var line := tr(beat["call"])
	if beat.has("verse"):
		line += "\n“%s” (%s)" % [tr(beat["verse"][0]), GameState.short_ref(beat["verse"][1])]
	var x: float = spots[0].x if not spots.is_empty() else 0.0
	for w in get_tree().get_nodes_in_group("watchmen"):
		var man: Dictionary = w._nearest_man(x)
		w._call(man, line, not spots.is_empty())
		if beat.has("verse"):   # a verse needs longer on screen than a call
			man["shout"].say(line, VERSE_HOLD, not spots.is_empty())
	if not spots.is_empty():
		Sfx.play("alert")
		for at: Vector3 in spots:
			get_tree().call_group("offscreen_alerts", "ping", at, COLOR, tr("Onslaught"), WARN + 3.0)
	beat_fired.emit(section_index, key, beat)
