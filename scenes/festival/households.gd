class_name Households
extends Node3D

# The trouble inside (Neh. 5), played at the Fountain Gate. The work has drawn the people
# from their fields, and three households inside the wall have nothing to eat: "We, our sons
# and our daughters, are many" (5:2), "We are mortgaging our fields" (5:3), "We have borrowed
# money for the king's tribute" (5:4). A stand of baskets in the yard gives out portions;
# carry one to each household (the Festival's portions, Folk) and [E]. Optional, never
# required: nothing ends the stretch if they go hungry. Each family fed comes back to the
# wall ("all my servants were gathered there to the work", 5:16): building +6% each for
# the stretch (GameState.households_fed). Bots don't carry to them — a job for people.
# Built on every peer from GameState alone; the server's deliveries are told to the rest.
# `-- --no-households` to play without them.

const HOUSEHOLD_TWIST := "spring"
const PILE_AT := Vector3(-4.5, 0.0, 13.0)

# Where they stand (inside the wall, far enough from the baskets to be a walk), who they
# are, and what they say hungry and fed
const FAMILIES := [
	{ "at": Vector3(-14.0, 0.1, 12.5), "kind": "woman",
	  "hungry": ["We, our sons and our daughters, are many. Let us get grain, that we may eat and live.", "Neh. 5:2"],
	  "fed": ["We will eat, and live. Our hands are yours at the wall.", ""] },
	{ "at": Vector3(4.0, 0.1, 14.0), "kind": "man",
	  "hungry": ["We are mortgaging our fields, our vineyards, and our houses. Let us get grain, because of the famine.", "Neh. 5:3"],
	  "fed": ["The grain is ours again. Show me where to lay stone.", ""] },
	{ "at": Vector3(13.0, 0.1, 12.5), "kind": "elder",
	  "hungry": ["We have borrowed money for the king’s tribute using our fields and our vineyards as collateral.", "Neh. 5:4"],
	  "fed": ["God bless you. I’ll stand a watch tonight.", ""] },
]

var enabled: bool = "--no-households" not in OS.get_cmdline_user_args()

var _families: Array[Folk] = []
var _pile: Node3D

func _init() -> void:
	name = "Households"

func _ready() -> void:
	if not enabled:
		return
	var scene := load("res://scenes/supply_pile/supply_pile.tscn") as PackedScene
	_pile = scene.instantiate()
	_pile.name = "StockPortion"
	_pile.kind = "portion"
	_pile.twist = HOUSEHOLD_TWIST   # there in this stretch only
	_pile.position = PILE_AT
	_pile.ready.connect(func(): _pile.count_label.clamp_to_screen = false)
	add_child(_pile)
	GameState.section_changed.connect(_refresh.unbind(1))
	_refresh()

func _active() -> bool:
	return GameState.has_twist(HOUSEHOLD_TWIST) and not GameState.free_play() and not GameState.attract

## The stretch changed: the households stand in the Fountain Gate and nowhere else, each
## stretch hungry again
func _refresh() -> void:
	# Those still hungry as the Fountain Gate ends are missing from the next stretch (Neh. 5:5)
	var hungry := _families.filter(func(f): return is_instance_valid(f) and f.hungry).size()
	GameState.hungry_left = 0 if _active() else hungry
	for f in _families:
		if is_instance_valid(f):
			f.remove_from_group("households")
			f.remove_from_group("folk")
			f.queue_free()
	_families.clear()
	GameState.households_fed = 0
	if not _active():
		return
	for i in FAMILIES.size():
		var row: Dictionary = FAMILIES[i]
		var f := Folk.new()
		f.hungry = true
		f.site_group = "households"
		f.tag_title = "Hungry household"
		f.hungry_line = row["hungry"]
		f.fed_line = row["fed"]
		f.look = Folk.look_for(row["kind"], Palette.UNDYED.darkened(0.2), i + 3)
		f.position = row["at"]
		f.fed.connect(_on_fed.bind(i))
		add_child(f)
		_families.append(f)

# Server: a portion went in
func _on_fed(_folk: Folk, i: int) -> void:
	if not multiplayer.is_server():
		return
	_count()
	_fed_remote.rpc(i)

@rpc("authority", "call_remote", "reliable")
func _fed_remote(i: int) -> void:
	if i >= 0 and i < _families.size() and is_instance_valid(_families[i]):
		_families[i].apply_fed()
	_count()

func _count() -> void:
	GameState.households_fed = _families.filter(func(f: Folk): return is_instance_valid(f) and not f.hungry).size()
