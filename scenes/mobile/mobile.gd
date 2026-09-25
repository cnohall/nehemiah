extends Node

# Phone/tablet presentation layer (autoload `Mobile`). Inert on desktop unless run
# with `-- --touch`, which previews the phone layout at a Pixel-sized dp height.
#
# - UI units = Android dp: the root content scale is set from screen density, so a
#   48-unit button is a 48dp touch target on any phone (Material's minimum).
# - Immersive fullscreen (system bars hidden; swipe from the edge to peek).
# - Android back gesture = Esc: closes the top sheet / opens the game menu, and
#   quits only from the title screen.
# - Safe area (camera cutout, rounded corners) in UI units for edge-hugging HUD.

signal layout_changed

const MIN_DP_H     := 360.0   # smaller phones get slightly denser UI rather than clipping
const MAX_DP_H     := 520.0   # tablets: cap so the HUD doesn't shrink to a speck
const PREVIEW_DP_H := 411.0   # desktop --touch preview ≈ Pixel 9a landscape
const WORLD_TEXT   := 1.5     # world labels (Label3D) read at arm's length
const CAMERA_SIZE  := 18.0    # ortho size; desktop uses 24 — phones zoom in a step

## Window pixels per UI unit (≈ screen density on a phone)
var ui_scale := 1.0
## Phone theme. Set on the root window; CanvasLayer UIs (HUD, story) don't inherit
## through the layer, so they assign it to their own root control.
var theme: Theme

static func enabled() -> bool:
	return OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--touch")

func _ready() -> void:
	if not enabled():
		return
	get_tree().quit_on_go_back = false
	get_tree().root.size_changed.connect(_rescale)
	_rescale()
	# Phone-sized theme on the root window overrides the project (desktop) theme
	theme = UiStyle.build_theme(true)
	get_tree().root.theme = theme

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and enabled():
		# Same path as the Esc key: `ui_cancel` closes sheets, `pause` toggles the game menu
		for pressed in [true, false]:
			var e := InputEventKey.new()
			e.keycode = KEY_ESCAPE
			e.physical_keycode = KEY_ESCAPE
			e.pressed = pressed
			Input.parse_input_event(e)

func _rescale() -> void:
	var root := get_tree().root
	var win := Vector2(root.size)
	if win.y <= 0.0:
		return
	var dp_h := PREVIEW_DP_H
	if OS.has_feature("mobile"):
		var dpi := DisplayServer.screen_get_dpi()
		var density := dpi / 160.0 if dpi > 0 else DisplayServer.screen_get_scale()
		dp_h = win.y / maxf(density, 1.0)
	var h := clampf(dp_h, MIN_DP_H, MAX_DP_H)
	var want := Vector2i(roundi(win.x * h / win.y), roundi(h))
	if want == root.content_scale_size:
		return
	ui_scale = win.y / h
	root.content_scale_size = want
	layout_changed.emit()

## Cutout / rounded-corner insets in UI units: (left, top, right, bottom)
func safe_insets() -> Vector4:
	if not OS.has_feature("mobile"):
		return Vector4.ZERO
	var win := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if win.x <= 0.0 or safe.size.x <= 0.0:
		return Vector4.ZERO
	var k := 1.0 / ui_scale
	return Vector4(safe.position.x * k, safe.position.y * k,
		maxf(win.x - safe.end.x, 0.0) * k, maxf(win.y - safe.end.y, 0.0) * k)

## Inset a full-rect control by the safe area plus `pad` on every side
func fit_safe(c: Control, pad := 0.0) -> void:
	var s := safe_insets()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = s.x + pad
	c.offset_top = s.y + pad
	c.offset_right = -(s.z + pad)
	c.offset_bottom = -(s.w + pad)

## Enlarge a world-space label for the phone camera (no-op on desktop)
func world_text(l: Label3D) -> void:
	if enabled():
		l.pixel_size *= WORLD_TEXT

## Light tick for on-screen buttons (needs the VIBRATE permission on Android)
func haptic(ms := 12) -> void:
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(ms, 0.35)
