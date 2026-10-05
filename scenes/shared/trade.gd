class_name Trade
extends RefCounted

# The four trades of the crew (GDD §5.10, Neh. 4): anyone can do any job, each trade
# does one thing better. Hands-on work takes WORK_MULT longer than before; a trade's own
# work runs PACE faster, which is the old pace. Water carriers walk loaded faster; the
# overseer hits harder. Off with `-- --no-trades` (GameState.trades): every worker plain,
# work at the old times.

enum { BUILDER, WATER_CARRIER, CARPENTER, OVERSEER }

const NAMES := CharacterRig.TRADES
const WORK_MULT  := 1.6    # every stage takes this much longer to work up…
const PACE       := 1.6    # …and a trade's own work runs this much faster (the old pace)
const CARRY_MULT := 1.25   # water carrier: loaded pace (5.5 → ~6.9; running is 8)
const HIT_MULT   := 1.6    # overseer: sword and sling (a full sling fells a scout)

# One line under the name wherever a trade is picked or shown
const ABOUT := [
	"Lays stone faster",
	"Walks faster with a load",
	"Works timber faster: frames, doors, watch posts",
	"Sword and sling hit harder",
]

## How fast `trade` works up a stage of `material` (1 = anyone)
static func work_pace(trade: int, material: String) -> float:
	if not GameState.trades:
		return 1.0
	match trade:
		BUILDER:
			return PACE if material == "stone" else 1.0
		CARPENTER:
			return PACE if material in ["wood", "beam"] else 1.0
	return 1.0

## Seconds of work time are stretched by this (the festival keeps its own times)
static func work_mult() -> float:
	return WORK_MULT if GameState.trades and not GameState.festival else 1.0

static func carry_mult(trade: int) -> float:
	return CARRY_MULT if GameState.trades and trade == WATER_CARRIER else 1.0

static func hit_mult(trade: int) -> float:
	return HIT_MULT if GameState.trades and trade == OVERSEER else 1.0

## The work this trade is quicker at, for bots choosing a site ("" = none)
static func prefers(trade: int, material: String) -> bool:
	return work_pace(trade, material) > 1.0

## Trade for each worker, in slot order. `chosen[i]` is a person's pick (-1 = none, the
## slot's own trade; bots are always -1). People keep theirs; bots take the trades nobody
## holds, in order, so a solo player with three bots still has the whole crew.
static func assign(chosen: Array, is_bot: Array) -> Array:
	var out := []
	var held := {}
	out.resize(chosen.size())
	out.fill(-1)
	# Explicit picks first (the server allows one per trade; a clash falls through)
	for i in chosen.size():
		if not is_bot[i] and chosen[i] >= 0 and not held.has(chosen[i]):
			out[i] = chosen[i]
			held[chosen[i]] = true
	# People without a pick: their slot's own trade, or the next free one
	for i in chosen.size():
		if is_bot[i] or out[i] >= 0:
			continue
		var t := i % NAMES.size()
		for k in NAMES.size():
			if not held.has((t + k) % NAMES.size()):
				t = (t + k) % NAMES.size()
				break
		out[i] = t
		held[t] = true
	for i in chosen.size():
		if not is_bot[i]:
			continue
		out[i] = i % NAMES.size()
		for t in NAMES.size():
			if not held.has(t):
				out[i] = t
				held[t] = true
				break
	return out
