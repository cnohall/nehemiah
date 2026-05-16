extends Node

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

const TOTAL_DAYS := 52

signal day_changed(day: int)
signal section_changed(section_index: int)
signal game_won
signal game_lost

var current_day: int = 1
var current_section_index: int = 0
# peer_id → { "role": String, "health": float }
var players: Dictionary = {}

# ── Queries ────────────────────────────────────────────────

func get_section_for_day(day: int) -> Dictionary:
	return SECTIONS[_section_index_for_day(day)]

func get_current_section() -> Dictionary:
	return get_section_for_day(current_day)

# ── Progression ────────────────────────────────────────────

func advance_day() -> void:
	if current_day >= TOTAL_DAYS:
		game_won.emit()
		return
	current_day += 1
	var new_idx := _section_index_for_day(current_day)
	if new_idx != current_section_index:
		current_section_index = new_idx
		section_changed.emit(current_section_index)
	day_changed.emit(current_day)

func trigger_loss() -> void:
	game_lost.emit()

# ── Players ────────────────────────────────────────────────

func register_player(peer_id: int, role: String) -> void:
	players[peer_id] = { "role": role, "health": 100.0 }

func remove_player(peer_id: int) -> void:
	players.erase(peer_id)

func reset() -> void:
	current_day = 1
	current_section_index = 0
	players.clear()

# ── Internal ───────────────────────────────────────────────

func _section_index_for_day(day: int) -> int:
	for i in SECTIONS.size():
		if day in SECTIONS[i]["days"]:
			return i
	return 0
