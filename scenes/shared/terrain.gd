class_name Terrain
extends RefCounted

# The lie of the land (GDD §6.5). Jerusalem sat on a ridge between two valleys: outside the
# wall the ground falls away into the Kidron / Hinnom and climbs again on the far side;
# inside, the city steps up the hill in terraces. The strip people walk on (Player.PLAY_AREA,
# the enemy approach) stays dead flat — heights only start past it, so nothing that walks
# or fights needs to know. Props sample `height()` to sit on the slope; GroundMesh builds
# the ground from it. One profile per section (the stretch's own view); deterministic,
# every peer computes the same.

## Flat from here to there. North (-z) is the foe's side, south (+z) the city
const FLAT_FOE := -26.0
## The lower city's cross street is walkable (Enemy.BREACH_Z, 21, is well inside); the city
## stops at the foot of the first terrace, its step the kerb you can't climb
const FLAT_CITY := 24.7
## Terrace risers climbing the city side: z where each rises, over RISER_W. They sit
## between the street rows of ScatterLayer's city so every house stands level: the cross
## street and well on the flat, the south row on the first terrace, the back lane second
const RISERS := [25.6, 31.0, 37.4, 43.2, 49.0, 54.8, 60.6]
const RISER_W := 0.8
const WADI_DRAG := 0.72
const SIDE_FLAT := 56.0   # the outer wall stretches end at |x| = 52

## Per section (GameState.SECTIONS order): city climb, drop outside, far slope above that.
## Valley Gate / Dung Gate / East Gate look into real ravines; the north gates face a
## gentle fall under the temple mount; the Ophel gates sit above the Kidron.
const PROFILES := [
	{ "climb": 8.8, "fall": 3.0,  "far": 6.0 },    # Sheep Gate — temple mount rising behind
	{ "climb": 6.9, "fall": 3.5,  "far": 5.0 },    # Fish Gate — Tyropoeon
	{ "climb": 6.9, "fall": 3.5,  "far": 5.0 },    # Jeshanah Gate
	{ "climb": 8.1, "fall": 4.5,  "far": 6.0 },    # Broad Wall — the Mishneh
	{ "climb": 8.1, "fall": 5.5,  "far": 6.5 },    # Tower of Ovens
	{ "climb": 10.0, "fall": 10.0, "far": 9.0, "wadi": true },    # Valley Gate — Hinnom below, Mount Zion above
	{ "climb": 6.2, "fall": 9.0,  "far": 7.0 },    # Dung Gate — the refuse valley
	{ "climb": 5.0, "fall": 5.5,  "far": 6.0 },    # Fountain Gate — Siloam, low
	{ "climb": 6.9, "fall": 7.5,  "far": 8.0 },    # Water Gate — Gihon
	{ "climb": 6.9, "fall": 8.5,  "far": 9.0 },    # Horse Gate — Ophel over the Kidron
	{ "climb": 5.6, "fall": 11.0, "far": 12.0, "wadi": true },   # East Gate — Kidron, Mount of Olives opposite
	{ "climb": 6.9, "fall": 6.5,  "far": 8.0 },    # Miphkad — north-east
]

static var _index := -1
static var _p: Dictionary = PROFILES[0]

## Make `i` the section height() answers for (cheap, safe to call every rebuild)
static func use_section(i: int) -> void:
	if i == _index:
		return
	_index = i
	_p = PROFILES[clampi(i, 0, PROFILES.size() - 1)]

## Ground height above the flat floor at (x, z) in the current section
static func height(x: float, z: float) -> float:
	var h := 0.0
	var ax := absf(x)
	# Foe side: fall into the valley, then the far slope up the other side
	if z < FLAT_FOE:
		var d := smoothstep(FLAT_FOE, FLAT_FOE - 15.0, z)
		h -= _p["fall"] * d
		h += (_p["fall"] + _p["far"]) * smoothstep(-46.0, -84.0, z)
		# Low rolling so the valley isn't a ramp (zero where it's flat)
		h += (sin(x * 0.11 + z * 0.07) + sin(x * 0.05 - z * 0.13)) * 0.6 * smoothstep(FLAT_FOE, FLAT_FOE - 8.0, z)
	# City side: terraces up the hill
	if z > RISERS[0] - 0.1:
		var n := RISERS.size()
		var step: float = _p["climb"] / n
		for k in n:
			h += step * smoothstep(RISERS[k], RISERS[k] + RISER_W, z)
		h += _p["climb"] * 0.6 * smoothstep(RISERS[n - 1] + 2.0, RISERS[n - 1] + 30.0, z)
	# Sides close in: the hills round the city
	h += 6.0 * smoothstep(SIDE_FLAT, SIDE_FLAT + 30.0, ax)
	return h

## Centre line (z) of the dry wadi across the enemy's approach (Valley Gate, East Gate) —
## keep in step with ground.gdshader `feature == 1`
static func wadi_z(x: float) -> float:
	return -8.5 + 2.4 * sin(x * 0.11 + 0.7) + 1.1 * sin(x * 0.31)

## Share of its pace a walker keeps at (x, z): loose wadi gravel drags at the feet
static func ground_drag(x: float, z: float) -> float:
	if _p.get("wadi", false) and absf(z - wadi_z(x)) < 1.9:
		return WADI_DRAG
	return 1.0
