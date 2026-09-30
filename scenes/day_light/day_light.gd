extends Node

# Night watch ("night" twist, Water Gate — Neh. 4:22-23): on night days darkness creeps
# in once the work starts and lifts again at the next dawn. Torches (SectionTerrain,
# group "torches") light up and every worker carries a small lamp; enemies come out of
# the dark. Runs on every peer from GameState alone — purely visual, nothing replicated.

const FALL_TIME := 16.0   # seconds for night to fall after the work starts
const LIFT_TIME := 2.5
const SUN_NIGHT       := 0.10
const SUN_NIGHT_COLOR := Color(0.55, 0.62, 0.92)
const AMBIENT_NIGHT   := 0.28
const AMBIENT_NIGHT_COLOR := Color(0.30, 0.36, 0.62)
const SKY_NIGHT       := 0.25
const TORCH_ENERGY    := 2.6
const LAMP_ENERGY     := 1.3
const LAMP_RANGE      := 4.5
const LAMP_COLOR      := Color(1.0, 0.78, 0.52)
const LAMP_POLL       := 0.5   # once night has settled, how often to hand out lamps
# Sun clock (GameState.sun): the light warms and sinks as the day's last quarter runs
# out; if the stars catch the work unfinished, night falls over the dusk
const EVENING_COLOR   := Color(1.0, 0.62, 0.38)
const EVENING_SUN     := 0.72   # sun energy at the very end of the day
const EVENING_RATE    := 0.6
# Sun clock, told by the sun itself (diegetic HUD): from the scene's mid-morning height
# the sun sinks and swings west as the daylight runs out, so the shadows lengthen and
# turn. It stands where it would over that stretch of the real wall (RingCompass): on
# the north wall it lights the city face, on the south it is behind the wall, on the
# east it moves from outside to over the city. Angles in degrees; bearings are compass
# bearings, clockwise from true north.
const SUN_HIGH     := 61.4    # elevation of the scene's sun: where each day starts
const SUN_LOW_ELEV := 22.0    # at the stars — low, long shadows, still readable
const SUN_MORNING  := 145.0   # mid-morning, south-east…
const SUN_EVENING  := 240.0   # …round by the south to west-south-west at the stars
const SUN_ARC_RATE := 0.5     # how fast it swings back up at a new dawn
# Lamps in the windows (ScatterLayer, group "window_lamps"): lit one by one as evening
# comes on (Neh. 4:21 "till the stars appeared"), all of them once night falls
const LAMPS_FROM := 0.3       # evening at which the first is lit …
const LAMPS_ALL  := 0.95      # … and the last

@onready var _sun: DirectionalLight3D = get_parent().get_node("Sun")
@onready var _env: Environment = get_parent().get_node("WorldEnvironment").environment

var darkness := 0.0
var evening := 0.0
var lamps := 0.0   # 0 … 1: share of the windows lit (read by Birds too)
var _target := 0.0
var _day := {}   # daylight values to return to
var _lamp_poll := 0.0
var _arc := 0.0   # 0 = the day's first light … 1 = the stars

func _ready() -> void:
	_day = {
		"sun": _sun.light_energy, "sun_color": _sun.light_color,
		"ambient": _env.ambient_light_energy, "ambient_color": _env.ambient_light_color,
		"sky": _env.background_energy_multiplier,
	}
	GameState.phase_changed.connect(_retarget.unbind(1))
	GameState.day_changed.connect(_retarget.unbind(1))
	GameState.sun_changed.connect(_retarget)
	GameState.section_changed.connect(_apply_arc.unbind(1))   # a new stretch, a new lie of the land
	_retarget()
	_apply()
	_apply_arc()

func _retarget() -> void:
	var dark_phase := GameState.phase == GameState.Phase.WORK or GameState.phase == GameState.Phase.DUSK
	var nightfall := GameState.sun_total > 0.0 and GameState.sun_left <= 0.0 \
		and GameState.phase in [GameState.Phase.DUSK, GameState.Phase.LOST]
	_target = 1.0 if (GameState.is_night_day() and dark_phase) or nightfall else 0.0

func _evening_target() -> float:
	if GameState.sun_total <= 0.0 or GameState.phase not in [GameState.Phase.WORK, GameState.Phase.DUSK, GameState.Phase.LOST]:
		return 0.0
	return clampf(1.0 - GameState.sun_left / (GameState.sun_total * GameState.SUN_LOW), 0.0, 1.0)

## How far through today's light (0 without a sun clock)
func _arc_target() -> float:
	if GameState.sun_total <= 0.0:
		return 0.0
	return clampf(1.0 - GameState.sun_left / GameState.sun_total, 0.0, 1.0)

func _apply_arc() -> void:
	var el := deg_to_rad(lerpf(SUN_HIGH, SUN_LOW_ELEV, _arc))
	var ground := RingCompass.bearing_on_site(GameState.current_section_index, lerpf(SUN_MORNING, SUN_EVENING, _arc))
	var to_sun := ground * cos(el) + Vector3.UP * sin(el)
	_sun.global_basis = Basis.looking_at(-to_sun, Vector3.UP)

func _process(delta: float) -> void:
	var a := _arc_target()
	if not is_equal_approx(_arc, a):
		# Counting down it follows the clock; a new dawn brings it back up gently
		_arc = a if a > _arc else move_toward(_arc, a, SUN_ARC_RATE * delta)
		_apply_arc()
	var e := _evening_target()
	if not is_equal_approx(evening, e):
		evening = move_toward(evening, e, EVENING_RATE * delta)
		_apply()
	if is_equal_approx(darkness, _target):
		_lamp_poll -= delta
		if darkness > 0.0 and _lamp_poll <= 0.0:
			_lamp_poll = LAMP_POLL
			_update_lamps()   # late joiners and respawned workers get a lamp too
		return
	var rate := 1.0 / (FALL_TIME if _target > darkness else LIFT_TIME)
	darkness = move_toward(darkness, _target, rate * delta)
	_apply()

func _apply() -> void:
	# Ease so the last light goes quickly, like a real dusk
	var k := darkness * darkness * (3.0 - 2.0 * darkness)
	var sun_day: float = _day["sun"] * lerpf(1.0, EVENING_SUN, evening)
	var sun_color := (_day["sun_color"] as Color).lerp(EVENING_COLOR, evening * 0.55)
	_sun.light_energy = lerpf(sun_day, SUN_NIGHT, k)
	_sun.light_color = sun_color.lerp(SUN_NIGHT_COLOR, k)
	_env.ambient_light_energy = lerpf(_day["ambient"], AMBIENT_NIGHT, k)
	_env.ambient_light_color = (_day["ambient_color"] as Color).lerp(AMBIENT_NIGHT_COLOR, k)
	_env.background_energy_multiplier = lerpf(_day["sky"], SKY_NIGHT, k)
	for torch: Node3D in get_tree().get_nodes_in_group("torches"):
		torch.get_node("Light").light_energy = TORCH_ENERGY * k
		torch.get_node("Flame").visible = k > 0.15
	_update_lamps()

func _update_lamps() -> void:
	var k := darkness * darkness * (3.0 - 2.0 * darkness)
	lamps = maxf(smoothstep(LAMPS_FROM, LAMPS_ALL, evening), k)
	get_tree().call_group("window_lamps", "set_lamps", lamps)
	for p: Node3D in get_tree().get_nodes_in_group("players"):
		var lamp: OmniLight3D = p.get_node_or_null("Lamp")
		if lamp == null:
			if k <= 0.0:
				continue
			lamp = OmniLight3D.new()
			lamp.name = "Lamp"
			lamp.light_color = LAMP_COLOR
			lamp.omni_range = LAMP_RANGE
			lamp.position.y = 2.2
			p.add_child(lamp)
		lamp.light_energy = LAMP_ENERGY * k
		lamp.visible = k > 0.0
