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

var _player: CharacterBody2D = null
var _hud: Node = null

# ── Public API ────────────────────────────────────────────────────────────────

func init(player: CharacterBody2D, hud: Node) -> void:
	_player = player
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
	if not _player:
		return

	var power := lerpf(MIN_POWER, MAX_POWER, _charge / MAX_CHARGE)

	# In 2D top-down, aim at mouse world position
	var mouse_pos := _player.get_global_mouse_position()
	var origin := _player.global_position

	var dir := (mouse_pos - origin)
	if dir.length() < 0.01:
		return
	dir = dir.normalized()

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
