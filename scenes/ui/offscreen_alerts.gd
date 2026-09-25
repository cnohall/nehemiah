class_name OffscreenAlerts
extends Control

# Edge-of-screen pointers for trouble the camera can't see: a wall section under
# attack, a teammate down. The view covers ~half the site, so without these a wall
# can crumble out of sight. Each new alert rings once (non-positional) so it's heard
# even beyond the 3D sound range. Local only — reads state every peer already has.

const HIT_WINDOW   := 2500    # ms a wall counts as "under attack" after its last hit
const REALERT_MS   := 8000    # a wall that stays under fire rings again after this
# px from each screen edge to the pointer's centre — top/bottom clear the HUD plaques
# (the phone layout sets its own)
var margin_side   := 64.0
var margin_top    := 205.0
var margin_bottom := 125.0
const ONSCREEN_PAD := 40.0    # a target this close inside the edge counts as visible
const RADIUS       := 22.0
const TIP          := 14.0    # how far the arrow tip sticks out past the disc
const FONT_SIZE    := 13

var _wall_alerted := {}   # wall instance id → msec of its last ring
var _was_downed := {}     # player instance id → bool

func _ready() -> void:
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

# Disc pinned to the screen edge, arrow pointing at the off-screen target
func _pointer(target: Vector2, color: Color, text: String, pulse: float) -> void:
	var size := get_viewport_rect().size
	var box := Rect2(margin_side, margin_top, size.x - margin_side * 2.0, size.y - margin_top - margin_bottom)
	var centre := box.get_center()
	var dir := (target - centre).normalized()
	# Push out from the box centre until we hit its edge
	var half := box.size * 0.5
	var t := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
	var pos := centre + dir * t
	var side := dir.orthogonal()
	var tip := pos + dir * (RADIUS + TIP)
	var base := pos + dir * (RADIUS - 4.0)
	var fill := Color(color, pulse)
	draw_colored_polygon(PackedVector2Array([tip, base + side * 11.0, base - side * 11.0]), fill)
	draw_circle(pos, RADIUS + 2.0, Color(UiStyle.DUSK, 0.55 * pulse))
	draw_circle(pos, RADIUS, fill)
	var font := UiStyle.CINZEL_SEMI
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	draw_string(font, pos + Vector2(-w * 0.5, FONT_SIZE * 0.35), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(UiStyle.CREAM, pulse))
