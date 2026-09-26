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

@onready var _sun: DirectionalLight3D = get_parent().get_node("Sun")
@onready var _env: Environment = get_parent().get_node("WorldEnvironment").environment

var darkness := 0.0
var _target := 0.0
var _day := {}   # daylight values to return to

func _ready() -> void:
	_day = {
		"sun": _sun.light_energy, "sun_color": _sun.light_color,
		"ambient": _env.ambient_light_energy, "ambient_color": _env.ambient_light_color,
		"sky": _env.background_energy_multiplier,
	}
	GameState.phase_changed.connect(_retarget.unbind(1))
	GameState.day_changed.connect(_retarget.unbind(1))
	_retarget()
	_apply()

func _retarget() -> void:
	var dark_phase := GameState.phase == GameState.Phase.WORK or GameState.phase == GameState.Phase.DUSK
	_target = 1.0 if GameState.is_night_day() and dark_phase else 0.0

func _process(delta: float) -> void:
	if is_equal_approx(darkness, _target):
		if darkness > 0.0:
			_update_lamps()   # late joiners and respawned workers get a lamp too
		return
	var rate := 1.0 / (FALL_TIME if _target > darkness else LIFT_TIME)
	darkness = move_toward(darkness, _target, rate * delta)
	_apply()

func _apply() -> void:
	# Ease so the last light goes quickly, like a real dusk
	var k := darkness * darkness * (3.0 - 2.0 * darkness)
	_sun.light_energy = lerpf(_day["sun"], SUN_NIGHT, k)
	_sun.light_color = (_day["sun_color"] as Color).lerp(SUN_NIGHT_COLOR, k)
	_env.ambient_light_energy = lerpf(_day["ambient"], AMBIENT_NIGHT, k)
	_env.ambient_light_color = (_day["ambient_color"] as Color).lerp(AMBIENT_NIGHT_COLOR, k)
	_env.background_energy_multiplier = lerpf(_day["sky"], SKY_NIGHT, k)
	for torch: Node3D in get_tree().get_nodes_in_group("torches"):
		torch.get_node("Light").light_energy = TORCH_ENERGY * k
		torch.get_node("Flame").visible = k > 0.15
	_update_lamps()

func _update_lamps() -> void:
	var k := darkness * darkness * (3.0 - 2.0 * darkness)
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
