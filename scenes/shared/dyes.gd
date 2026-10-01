class_name Dyes
extends RefCounted

# Robe dyes earned by marks (GDD §6.1 section rating): the marks were a number on a
# card and nothing more. Every mark this player has ever earned (best per section, up
# to 36) counts toward the next dye, from plain linen to Tyrian purple. Looks only — no
# stats, no loot — worn on the robe, so the slot colour on the head-band and ring stays
# the one that says who's who. Kept per player (progress.cfg via best marks); chosen in
# the gather panel / menu (Settings.dye) and shown to the crew (NetworkManager.crew_info).

# [name, robe colour, marks needed] — period dyes, kept earthy (no neon)
const LIST := [
	["Undyed linen",   Color(0.93, 0.89, 0.80), 0],
	["Madder red",     Color(0.66, 0.30, 0.22), 3],
	["Woad blue",      Color(0.36, 0.46, 0.58), 6],
	["Saffron",        Color(0.86, 0.66, 0.30), 10],
	["Olive green",    Color(0.48, 0.52, 0.30), 15],
	["Pomegranate",    Color(0.58, 0.22, 0.26), 20],
	["Indigo",         Color(0.24, 0.26, 0.44), 26],
	["Tyrian purple",  Color(0.42, 0.20, 0.38), 33],
]

## Marks this player has earned, best per section, all sections
static func earned() -> int:
	var n := 0
	for i in GameState.SECTIONS.size():
		n += GameState.mark_count(GameState.best_marks(i))
	return n

static func unlocked(i: int, marks := -1) -> bool:
	return i >= 0 and i < LIST.size() and (marks if marks >= 0 else earned()) >= LIST[i][2]

static func unlocked_count(marks := -1) -> int:
	var m := marks if marks >= 0 else earned()
	return LIST.filter(func(d): return m >= d[2]).size()

## The next dye still to earn: [name, marks needed], or [] when all are open
static func next(marks := -1) -> Array:
	var m := marks if marks >= 0 else earned()
	for d: Array in LIST:
		if m < d[2]:
			return [d[0], d[2]]
	return []

## Dress a worker look in dye `i` (0 = as it comes)
static func apply(look: Dictionary, i: int) -> Dictionary:
	if i > 0 and i < LIST.size():
		look["robe"] = LIST[i][1]
		look["trim"] = (LIST[i][1] as Color).darkened(0.2)
	return look
