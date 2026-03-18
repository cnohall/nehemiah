extends Node
class_name Slinger
## Self-contained sling mechanic. Call process() each physics frame.
## State is pushed back to the player via player.sling_updated signal —
## the same pattern used by health/stamina. No direct HUD dependency.

const MIN_CHARGE:  float = 0.15
const MAX_CHARGE:  float = 1.4
const MIN_POWER:   float = 8.0
const MAX_POWER:   float = 24.0
const RELOAD_TIME: float = 0.80

var _charge:       float = 0.0
var _is_charging:  bool  = false
var _reload_timer: float = 0.0

var _player: CharacterBody3D = null
var _camera: Camera3D = null

func init(player: CharacterBody3D, camera: Camera3D) -> void:
	_player = player
	_camera = camera

func process(delta: float, rmb_held: bool) -> void:
	if _reload_timer > 0.0:
		_reload_timer -= delta
		_push_state()
		return

	if rmb_held:
		_charge = minf(_charge + delta, MAX_CHARGE)
		_is_charging = true
	elif _is_charging:
		if _charge >= MIN_CHARGE:
			_do_throw()
		_is_charging = false
		_charge = 0.0

	_push_state()

func is_reloading() -> bool:
	return _reload_timer > 0.0

func charge_ratio() -> float:
	return _charge / MAX_CHARGE if _is_charging else 0.0

func _do_throw() -> void:
	if not _camera or not _player:
		return

	var power := lerpf(MIN_POWER, MAX_POWER, _charge / MAX_CHARGE)

	var mouse_pos := _player.get_viewport().get_mouse_position()
	var ray_origin := _camera.project_ray_origin(mouse_pos)
	var ray_dir    := _camera.project_ray_normal(mouse_pos)

	if absf(ray_dir.y) < 0.001:
		return

	var t   := (0.5 - ray_origin.y) / ray_dir.y
	var hit := ray_origin + ray_dir * t

	var origin    := _player.global_position + Vector3(0, 1.2, 0)
	var flat_dist := Vector2(hit.x - origin.x, hit.z - origin.z).length()
	var aim_y     := 1.2 + flat_dist * 0.07
	var dir       := (Vector3(hit.x, aim_y, hit.z) - origin).normalized()

	var main := _player.get_tree().current_scene
	if main.has_method("request_throw_stone"):
		main.request_throw_stone.rpc_id(1, origin, dir, power, _player.get_path())

	_reload_timer = RELOAD_TIME

func _push_state() -> void:
	if not is_instance_valid(_player):
		return
	if _reload_timer > 0.0:
		_player.sling_updated.emit(0.0, true, 1.0 - _reload_timer / RELOAD_TIME)
	elif _is_charging:
		_player.sling_updated.emit(_charge / MAX_CHARGE, false, 0.0)
	else:
		_player.sling_updated.emit(-1.0, false, 0.0)
