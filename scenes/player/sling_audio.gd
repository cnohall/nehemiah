extends Node
class_name SlingAudio
## Manages all sling sounds: stone pickup on charge start, whoosh on release.
## Connects directly to Slinger signals — no polling needed.
## Add as child of the local player via player.gd.

var _charge_player: AudioStreamPlayer3D = null
var _throw_player: AudioStreamPlayer3D = null

func init(player: CharacterBody3D, slinger: Slinger) -> void:
	_charge_player = _make_player(player, -12.0, 20.0)
	_throw_player  = _make_player(player,  -6.0, 28.0)

	var stone_sound := _load_sound("res://assets/sounds/place_stone.wav")
	var throw_sound := _load_sound("res://assets/sounds/sling_throw.wav")
	if stone_sound: _charge_player.stream = stone_sound
	if throw_sound: _throw_player.stream  = throw_sound

	slinger.charge_started.connect(_on_charge_started)
	slinger.throw_released.connect(_on_throw_released)
	slinger.charge_cancelled.connect(_on_charge_cancelled)
	slinger.reload_blocked.connect(_on_reload_blocked)

func _make_player(parent: Node, vol_db: float, max_dist: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.volume_db    = vol_db
	p.max_distance = max_dist
	parent.add_child(p)
	return p

func _load_sound(path: String) -> AudioStream:
	if FileAccess.file_exists(path):
		return load(path)
	return null

# -- Signal callbacks ----------------------------------------------------------

func _on_charge_started() -> void:
	if _charge_player and _charge_player.stream:
		_charge_player.pitch_scale = 0.55
		_charge_player.play()

func _on_throw_released(_origin: Vector3, _dir: Vector3, power: float) -> void:
	if _charge_player:
		_charge_player.stop()
	if _throw_player and _throw_player.stream:
		# Full-charge throw sounds faster/snappier
		_throw_player.pitch_scale = lerpf(0.85, 1.35, power / Slinger.MAX_POWER)
		_throw_player.play()

func _on_charge_cancelled() -> void:
	if _charge_player:
		_charge_player.stop()

func _on_reload_blocked() -> void:
	# Short high-pitched click: "not ready yet"
	if _charge_player and _charge_player.stream:
		_charge_player.pitch_scale = 3.2
		_charge_player.play()
