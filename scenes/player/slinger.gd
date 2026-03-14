extends Node
class_name Slinger
## Self-contained sling mechanic. Attach to player, call process() each physics frame.
## Handles charge → throw → reload state and pushes state to the HUD.

const MIN_CHARGE: float = 0.15   # seconds — below this a release is ignored
const MAX_CHARGE: float = 1.4    # seconds to reach full power
const MIN_POWER:  float = 8.0
const MAX_POWER:  float = 24.0
const RELOAD_TIME: float = 0.80  # seconds between throws

var _charge: float = 0.0
var _is_charging: bool = false
var _reload_timer: float = 0.0

var _player: CharacterBody3D = null
var _camera: Camera3D = null
var _hud: Node = null

# ── Public API ────────────────────────────────────────────────────────────────

func init(player: CharacterBody3D, camera: Camera3D, hud: Node) -> void:
	_player = player
	_camera = camera
	_hud = hud

## Call every physics frame, passing current RMB held state.
func process(delta: float, rmb_held: bool) -> void:
	if _reload_timer > 0.0:
		_reload_timer -= delta
		_push_hud()
		return

	if rmb_held:
		_charge = minf(_charge + delta, MAX_CHARGE)
		_is_charging = true
	elif _is_charging:
		# Button released — throw if charged enough
		if _charge >= MIN_CHARGE:
			_do_throw()
		_is_charging = false
		_charge = 0.0

	_push_hud()

func is_reloading() -> bool:
	return _reload_timer > 0.0

func charge_ratio() -> float:
	return _charge / MAX_CHARGE if _is_charging else 0.0

# ── Internal ──────────────────────────────────────────────────────────────────

func _do_throw() -> void:
	if not _camera or not _player:
		return

	var power := lerpf(MIN_POWER, MAX_POWER, _charge / MAX_CHARGE)

	var mouse_pos := _player.get_viewport().get_mouse_position()
	var ray_origin := _camera.project_ray_origin(mouse_pos)
	var ray_dir    := _camera.project_ray_normal(mouse_pos)

	if absf(ray_dir.y) < 0.001:
		return

	var t := (0.5 - ray_origin.y) / ray_dir.y
	var hit := ray_origin + ray_dir * t

	var origin := _player.global_position + Vector3(0, 1.2, 0)
	# Loft the throw upward proportional to distance — stone arcs back down to target
	var flat_dist := Vector2(hit.x - origin.x, hit.z - origin.z).length()
	var aim_y := 1.2 + flat_dist * 0.07
	var dir := (Vector3(hit.x, aim_y, hit.z) - origin).normalized()

	var main := _player.get_tree().current_scene
	if main.has_method("request_throw_stone"):
		main.request_throw_stone.rpc_id(1, origin, dir, power, _player.get_path())

	_reload_timer = RELOAD_TIME

func _push_hud() -> void:
	if not _hud:
		return

	if _reload_timer > 0.0:
		var reload_pct := 1.0 - (_reload_timer / RELOAD_TIME)
		_hud.update_sling(0.0, true, reload_pct)
	elif _is_charging:
		_hud.update_sling(_charge / MAX_CHARGE, false, 0.0)
	else:
		_hud.update_sling(-1.0, false, 0.0)  # -1 = hide
