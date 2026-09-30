class_name OffscreenAlerts
extends Control

# Edge-of-screen pointers for trouble the camera can't see: a wall section under
# attack, a teammate down. The view covers ~half the site, so without these a wall
# can crumble out of sight. Each new alert rings once (non-positional) so it's heard
# even beyond the 3D sound range. Local only — reads state every peer already has.

const HIT_WINDOW   := 2500    # ms a wall counts as "under attack" after its last hit
const REALERT_MS   := 8000    # a wall that stays under fire rings again after this
# px from each screen edge to the pointer's centre — top/bottom clear the HUD plaques
const MARGIN_SIDE   := 64.0
const MARGIN_TOP    := 205.0
const MARGIN_BOTTOM := 125.0
const ONSCREEN_PAD := 40.0    # a target this close inside the edge counts as visible
const RADIUS       := 22.0
const TIP          := 14.0    # how far the arrow tip sticks out past the disc
const FONT_SIZE    := 13

var _wall_alerted := {}   # wall instance id → msec of its last ring
var _was_downed := {}     # player instance id → bool
var _pings: Array = []    # [world pos, colour, text, msec until] — horn calls, surges

func _ready() -> void:
	add_to_group("offscreen_alerts")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or GameState.is_over():
		return
	var rect := get_viewport_rect().grow(-ONSCREEN_PAD)
	var now := Time.get_ticks_msec()
	var pulse := 0.75 + 0.25 * sin(now * 0.008)
	for wall: Node3D in get_tree().get_nodes_in_group("wall_sections"):
		if now - wall.last_hit_msec > HIT_WINDOW:
			continue
		var at := cam.unproject_position(wall.global_position)
		if rect.has_point(at):
			continue
		var id := wall.get_instance_id()
		if now - _wall_alerted.get(id, -REALERT_MS) >= REALERT_MS:
			Sfx.play("alert")
			_wall_alerted[id] = now
		_pointer(at, UiStyle.TERRACOTTA, "Wall", pulse)
	for p: Node3D in get_tree().get_nodes_in_group("players"):
		var id := p.get_instance_id()
		var was: bool = _was_downed.get(id, false)
		_was_downed[id] = p.downed
		if not p.downed or p.is_multiplayer_authority():
			continue
		var at := cam.unproject_position(p.global_position)
		if rect.has_point(at):
			continue
		if not was:
			Sfx.play("alert")
		_pointer(at, p.slot_color, "Help", pulse)
	_pings = _pings.filter(func(pg): return pg[3] > now)
	for pg: Array in _pings:
		var at := cam.unproject_position(pg[0])
		if not rect.has_point(at):
			_pointer(at, pg[1], pg[2], pulse)

## A one-off place to point at for `seconds` while it's off-screen (horn call, surge)
func ping(at: Vector3, color: Color, text: String, seconds: float) -> void:
	_pings.append([at, color, text, Time.get_ticks_msec() + int(seconds * 1000.0)])

# Disc pinned to the screen edge, arrow pointing at the off-screen target
func _pointer(target: Vector2, color: Color, text: String, pulse: float) -> void:
	var vp_size := get_viewport_rect().size
	var box := Rect2(MARGIN_SIDE, MARGIN_TOP, vp_size.x - MARGIN_SIDE * 2.0, vp_size.y - MARGIN_TOP - MARGIN_BOTTOM)
	var centre := box.get_center()
	var dir := (target - centre).normalized()
	# Push out from the box centre until we hit its edge
	var half := box.size * 0.5
	var t := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
	var pos := centre + dir * t
	# Pulse is a ring rippling outward, not a flicker of the badge itself
	var ripple := fmod(Time.get_ticks_msec() * 0.0011, 1.0)
	draw_arc(pos, RADIUS + 3.0 + ripple * 16.0, 0.0, TAU, 48,
		Color(color, 0.55 * (1.0 - ripple)), 2.5 * (1.0 - ripple) + 0.5, true)
	var shadow := pos + Vector2(0.0, 3.0)
	_pin(shadow, dir, RADIUS + 3.0, Color(UiStyle.DUSK, 0.35))
	_pin(pos, dir, RADIUS + 3.0, UiStyle.DUSK.lerp(color, 0.25))   # dark lip
	_pin(pos, dir, RADIUS + 1.5, UiStyle.PARCHMENT)                 # cream bezel
	_pin(pos, dir, RADIUS, color.darkened(0.12))
	# Soft top-lit face: a lighter disc nudged up, then a thin inner rim
	draw_circle(pos + Vector2(0.0, -2.0), RADIUS - 3.0, color.lightened(0.08 + 0.06 * pulse), true, -1.0, true)
	draw_arc(pos, RADIUS - 3.0, 0.0, TAU, 40, Color(UiStyle.CREAM, 0.35), 1.0, true)
	var font := UiStyle.CINZEL_BOLD
	text = tr(text).to_upper()
	var size := FONT_SIZE
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	while w > RADIUS * 2.0 - 10.0 and size > 8:
		size -= 1
		w = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at := pos + Vector2(-w * 0.5, size * 0.36)
	draw_string(font, at + Vector2(0.0, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(UiStyle.DUSK, 0.6))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, UiStyle.CREAM)

# Teardrop: disc of radius r whose tangents meet in a point along dir — one shape,
# so layered fills never double up where arrow and disc overlap
func _pin(pos: Vector2, dir: Vector2, r: float, color: Color) -> void:
	var tip_dist := r + TIP * (r / RADIUS)
	var a0 := dir.angle()
	var half := acos(r / tip_dist)
	var pts := PackedVector2Array([pos + dir * tip_dist])
	const STEPS := 36
	for i in STEPS + 1:
		var a := a0 + half + (TAU - half * 2.0) * i / STEPS
		pts.append(pos + Vector2.from_angle(a) * r)
	draw_colored_polygon(pts, color)
	pts.append(pts[0])
	draw_polyline(pts, color, 1.0, true)   # antialiased edge
