class_name Palette
extends RefCounted

# World colour palette (sRGB, vertex/albedo colours). One set of period dyes and
# building materials shared by set dressing, terrain twists and the crew, so the
# world reads as one place rather than a box of crayons. Kept a notch below the
# UI accents in chroma — WorldEnvironment lifts saturation ~10% on top.
# UI tokens live in UiStyle; TERRACOTTA there is MADDER here, lifted for text.

# ── Dyes (rugs, awnings, cloth) ────────────────────────────
const MADDER  := Color(0.62, 0.28, 0.17)   # madder root red
const SAFFRON := Color(0.80, 0.60, 0.27)   # saffron / pomegranate-rind yellow
const INDIGO  := Color(0.25, 0.31, 0.46)   # woad / indigo blue
const WELD    := Color(0.47, 0.49, 0.26)   # weld + woad olive green
const MUREX   := Color(0.47, 0.22, 0.27)   # Tyrian purple-red, the costly one
const UNDYED  := Color(0.83, 0.77, 0.65)   # natural wool / linen

const DYES := [MADDER, SAFFRON, INDIGO, WELD, MUREX]

# ── Building ───────────────────────────────────────────────
# Lime plaster over mudbrick and bare limestone — lighter than the ground, not white
const PLASTER := [Color(0.86, 0.80, 0.69), Color(0.82, 0.74, 0.61), Color(0.78, 0.69, 0.55),
	Color(0.85, 0.79, 0.70)]
# Doors: weathered blue-green (the Levant favourite), faded indigo, bare cedar
const DOORS := [Color(0.24, 0.38, 0.38), Color(0.26, 0.29, 0.40), Color(0.40, 0.28, 0.17),
	Color(0.33, 0.37, 0.26)]
const PAVING    := Color(0.80, 0.76, 0.68)
const LIMESTONE := Color(0.78, 0.75, 0.68)
# Dressed wall stone: the palest, coolest thing in the scene, so the wall leads
const WALL_STONE := Color(0.84, 0.82, 0.77)
# Foliage: olive and fig kept a touch fresher than dry scrub so trees read as life
const LEAF := Color(0.40, 0.56, 0.24)

# ── Crew (player slots) — strong enough to pick out at a glance, still dyes ──
# One per trade (CharacterRig.worker_look): builder indigo, water carrier madder,
# carpenter weld green, supervisor saffron
const CREW := [Color(0.24, 0.42, 0.80), Color(0.80, 0.28, 0.20), Color(0.46, 0.62, 0.26),
	Color(0.90, 0.66, 0.22)]
