extends Node
class_name AimPredictor
## Draws a targeting dot at the mouse cursor's ground position while charging.
## Dot scales and shifts color with charge — amber (low) → orange-red (full).
## Add as child of the local player via player.gd.

const GROUND_Y: float = 0.18

var _dot: MeshInstance3D = null
var _player: CharacterBody3D = null
var _camera: Camera3D = null
var _slinger: Slinger = null

func init(player: CharacterBody3D, camera: Camera3D, slinger: Slinger) -> void:
	_player = player
	_camera = camera
	_slinger = slinger
	_build_dot()

func _build_dot() -> void:
	_dot = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.22
	mesh.height = 0.07
	mesh.radial_segments = 8
	mesh.rings = 4
	_dot.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.75, 0.2, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	_dot.material_override = mat
	_dot.visible = false

	# Parented to scene root so it lives in world space
	if get_tree():
		get_tree().current_scene.add_child(_dot)

func _exit_tree() -> void:
	if is_instance_valid(_dot):
		_dot.queue_free()

func _process(_delta: float) -> void:
	if not is_instance_valid(_slinger) or not is_instance_valid(_player) or not is_instance_valid(_camera):
		if is_instance_valid(_dot):
			_dot.visible = false
		return

	if not _slinger.is_charging or _slinger.is_reloading():
		_dot.visible = false
		return

	var ground_hit := _calc_ground_hit()
	if ground_hit == Vector3.INF:
		_dot.visible = false
		return

	_dot.global_position = Vector3(ground_hit.x, GROUND_Y, ground_hit.z)
	_dot.visible = true

	var ratio := _slinger.charge / Slinger.MAX_CHARGE

	# Scale: subtle pulse that speeds up with charge (2 Hz → 5 Hz)
	var pulse_hz := lerpf(2.0, 5.0, ratio)
	var pulse    := sin(Time.get_ticks_msec() * 0.001 * pulse_hz * TAU) * 0.06 * (0.5 + ratio)
	var s := lerpf(0.6, 1.1, ratio) + pulse
	_dot.scale = Vector3(s, 1.0, s)

	# Color: amber → orange-red
	var mat := _dot.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = Color(
			lerpf(0.95, 1.0,  ratio),
			lerpf(0.75, 0.28, ratio),
			lerpf(0.20, 0.08, ratio),
			0.85
		)

func _calc_ground_hit() -> Vector3:
	var mouse_pos := _player.get_viewport().get_mouse_position()
	var ray_origin := _camera.project_ray_origin(mouse_pos)
	var ray_dir    := _camera.project_ray_normal(mouse_pos)
	if absf(ray_dir.y) < 0.001:
		return Vector3.INF
	var t := (0.5 - ray_origin.y) / ray_dir.y
	return ray_origin + ray_dir * t
