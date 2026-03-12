extends Node
## Manages the world environment, day/night cycles, and visual transitions.

@export var sun_path: NodePath
@export var world_env_path: NodePath

@onready var _sun: DirectionalLight3D = get_node(sun_path)
@onready var _world_env: WorldEnvironment = get_node(world_env_path)

const TRANSITION_DURATION: float = 2.5
const SUN_DAY: float = 1.5
const SUN_NIGHT: float = 0.05
const BRIGHT_DAY: float = 1.0
const BRIGHT_NIGHT: float = 0.12

enum Phase { NONE, NIGHT_FALL, DAY_RISE }
var _current_phase: Phase = Phase.NONE
var _elapsed: float = 0.0

signal transition_complete(new_phase: Phase)

func _process(delta: float) -> void:
	if _current_phase == Phase.NONE: return
	
	_elapsed += delta
	var t: float = clampf(_elapsed / TRANSITION_DURATION, 0.0, 1.0)
	
	match _current_phase:
		Phase.NIGHT_FALL:
			_apply_environment(lerp(SUN_DAY, SUN_NIGHT, t), lerp(BRIGHT_DAY, BRIGHT_NIGHT, t))
		Phase.DAY_RISE:
			_apply_environment(lerp(SUN_NIGHT, SUN_DAY, t), lerp(BRIGHT_NIGHT, BRIGHT_DAY, t))
			
	if t >= 1.0:
		var finished_phase = _current_phase
		_current_phase = Phase.NONE
		transition_complete.emit(finished_phase)

func _apply_environment(sun_energy: float, brightness: float) -> void:
	if _sun: _sun.light_energy = sun_energy
	if _world_env: _world_env.environment.adjustment_brightness = brightness

@rpc("authority", "call_local", "reliable")
func sync_transition(to_night: bool) -> void:
	_elapsed = 0.0
	_current_phase = Phase.NIGHT_FALL if to_night else Phase.DAY_RISE
