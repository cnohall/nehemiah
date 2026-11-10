extends Node

# Which device the local player last touched — keyboard/mouse or a gamepad. Drives the
# button hints on screen, stick vs cursor aiming, and rumble. Also gates gameplay input
# while a menu is open.

signal changed(using_pad: bool)   # device switched, pad family changed, or a rebind
signal pad_lost                   # the pad in use was unplugged / ran out of battery

const STICK_WAKE := 0.4   # stick travel that counts as "picked up the pad" (ignores drift)
# Presses that also drive the player — held over from a menu, they must not leak into play
const GAMEPLAY := ["interact", "drop", "dash", "throw_charge", "horn", "call"]

enum Pad { XBOX, SONY, NINTENDO }

# Face buttons by position (Godot's joypad layout is positional: A = bottom)
const FACE := {
	Pad.XBOX:     { JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y" },
	Pad.SONY:     { JOY_BUTTON_A: "Cross", JOY_BUTTON_B: "Circle", JOY_BUTTON_X: "Square", JOY_BUTTON_Y: "Triangle" },
	Pad.NINTENDO: { JOY_BUTTON_A: "B", JOY_BUTTON_B: "A", JOY_BUTTON_X: "Y", JOY_BUTTON_Y: "X" },
}
const SHOULDERS := {
	Pad.XBOX:     ["LB", "RB", "LT", "RT", "View", "Menu"],
	Pad.SONY:     ["L1", "R1", "L2", "R2", "Share", "Options"],
	Pad.NINTENDO: ["L", "R", "ZL", "ZR", "−", "+"],
}
const MOUSE := { MOUSE_BUTTON_LEFT: "Click", MOUSE_BUTTON_RIGHT: "Right Click",
	MOUSE_BUTTON_MIDDLE: "Middle Click", MOUSE_BUTTON_XBUTTON1: "Mouse 4", MOUSE_BUTTON_XBUTTON2: "Mouse 5" }
# Hint name → InputMap action, where they differ
const ACTION := { "throw": "throw_charge" }
# Phones: the on-screen control that does it (TouchControls labels)
const TOUCH := { "interact": "Use", "drop": "Drop", "dash": "Dash", "throw": "Sling",
	"throw_charge": "Sling", "horn": "Horn", "call": "Call", "pause": "Menu", "move": "Stick" }

var using_pad := false
var pad_kind := Pad.XBOX
var menu_open := false   # set by the HUD; see gameplay_blocked()
var _pad_device := -1
var _await_release := false

func _ready() -> void:
	# Device hints and the release guard must work in a paused (solo) game's menu
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_joy_connection)
	# Godot's built-in ui_accept / ui_cancel are keyboard-only; without these, A can't
	# press a focused button and B can't back out of a menu
	for pair in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B]]:
		var e := InputEventJoypadButton.new()
		e.button_index = pair[1]
		e.device = -1
		InputMap.action_add_event(pair[0], e)

func _input(event: InputEvent) -> void:
	var pad := using_pad
	if event is InputEventJoypadButton:
		pad = true
		_note_pad(event.device)
	elif event is InputEventJoypadMotion:
		if absf(event.axis_value) > STICK_WAKE:
			pad = true
			_note_pad(event.device)
	elif event is InputEventKey or event is InputEventMouseButton:
		pad = false
	elif event is InputEventMouseMotion and event.relative.length() > 4.0:
		pad = false
	if pad != using_pad:
		using_pad = pad
		changed.emit(pad)

func _process(_delta: float) -> void:
	if _await_release and not GAMEPLAY.any(Input.is_action_pressed):
		_await_release = false
	_update_cursor()

# ── Play cursor ────────────────────────────────────────────
# The OS arrow is lost on the busy HD-2D ground. While our own worker is out there to aim,
# the arrow becomes a big cream reticle with an ink outline; menus, story and the tally get
# the arrow back. Scaled to the window height, so it doesn't shrink to a speck at 4K.
const RETICLE_PX := 40      # at 1080p
const RETICLE_MAX := 96     # browsers drop cursors over 128 px
var _reticle_px := 0        # 0 = OS arrow

func _update_cursor() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var px := 0
	if not using_pad and not menu_open and _local_worker_out():
		var h := float(DisplayServer.window_get_size().y)
		px = clampi(roundi(RETICLE_PX * h / 1080.0), 32, RETICLE_MAX)
	if px == _reticle_px:
		return
	_reticle_px = px
	if px == 0:
		Input.set_custom_mouse_cursor(null)
	else:
		Input.set_custom_mouse_cursor(_reticle(px), Input.CURSOR_ARROW, Vector2(px, px) * 0.5)

func _local_worker_out() -> bool:
	if GameState.phase not in [GameState.Phase.DAWN, GameState.Phase.WORK, GameState.Phase.GATHER]:
		return false
	for p in get_tree().get_nodes_in_group("players"):
		if p.get("brain") == null and p.is_multiplayer_authority():
			return true
	return false

## A ring and a centre dot, cream on an ink outline (reads on sand and on stone)
static func _reticle(px: int) -> Image:
	var img := Image.create_empty(px, px, false, Image.FORMAT_RGBA8)
	var c := px * 0.5
	var ring := px * 0.30
	var band := maxf(1.5, px * 0.05)     # half-width of the cream ring
	var dot := maxf(1.5, px * 0.06)
	var line := maxf(1.5, px * 0.045)    # ink outline round both
	for y in px:
		for x in px:
			var d := Vector2(x + 0.5 - c, y + 0.5 - c).length()
			var sd := minf(absf(d - ring) - band, d - dot)   # <0 inside the cream
			var fill := clampf(0.5 - sd, 0.0, 1.0)
			var edge := clampf(0.5 - (sd - line), 0.0, 1.0)
			var col := UiStyle.INK.lerp(UiStyle.CREAM, fill)
			col.a = edge
			img.set_pixel(x, y, col)
	return img

## HUD: a menu opened / closed over play
func set_menu_open(open: bool) -> void:
	# Closing with A or a click: that same press must not throw or pick something up
	if menu_open and not open:
		_await_release = true
	menu_open = open

## True while the player shouldn't act on input: a menu is up, or a button that
## closed it is still held
func gameplay_blocked() -> bool:
	return menu_open or _await_release

## Label for an action on the device in use: "E" or "A". Built from the live bindings,
## so rebinds and non-QWERTY layouts show the key actually pressed.
func key(action: String) -> String:
	if TouchControls.enabled() and not using_pad:
		return TOUCH.get(action, action.capitalize())
	if action == "move":
		if using_pad:
			return tr("L Stick")
		return "".join(["move_north", "move_west", "move_south", "move_east"].map(
			func(m: String) -> String: return key_label(m)))
	var a: String = ACTION.get(action, action)
	var label := _pad_label(a) if using_pad else key_label(a)
	if action == "throw" and not Settings.toggle_charge:
		return tr("Hold %s") % label
	return label

## Rebinding / reset changed what the hints should say
func bindings_changed() -> void:
	changed.emit(using_pad)

## Short rumble on the pad in use (no-op on keyboard or with rumble off)
func rumble(weak: float, strong: float, duration: float) -> void:
	if not using_pad or not Settings.rumble or _pad_device < 0:
		return
	Input.start_joy_vibration(_pad_device, weak, strong, duration)

func _note_pad(device: int) -> void:
	if device == _pad_device:
		return
	_pad_device = device
	var kind := _kind_of(Input.get_joy_name(device))
	if kind != pad_kind:
		pad_kind = kind
		if using_pad:
			changed.emit(true)

func _on_joy_connection(device: int, connected: bool) -> void:
	if not connected and device == _pad_device:
		Input.stop_joy_vibration(device)
		if using_pad:
			pad_lost.emit()

static func _kind_of(joy_name: String) -> Pad:
	var n := joy_name.to_lower()
	for s in ["ps3", "ps4", "ps5", "dualshock", "dualsense", "playstation", "sony"]:
		if s in n:
			return Pad.SONY
	for s in ["nintendo", "switch", "joy-con", "pro controller"]:
		if s in n:
			return Pad.NINTENDO
	return Pad.XBOX

## Keyboard / mouse label for an InputMap action: "E", "Click", "Z" on AZERTY
func key_label(action: String) -> String:
	var e := Settings.primary_event(action)
	if e is InputEventKey:
		# The headless server (dedicated host, test harnesses) has no keyboard layout to ask
		var k := KEY_NONE if DisplayServer.get_name() == "headless" \
			else DisplayServer.keyboard_get_label_from_physical(e.physical_keycode)
		var s := OS.get_keycode_string(k if k != KEY_NONE else e.physical_keycode)
		return "Esc" if s == "Escape" else s
	if e is InputEventMouseButton:
		return tr(MOUSE[e.button_index]) if MOUSE.has(e.button_index) else tr("Mouse %d") % e.button_index
	return "—"

func _pad_label(action: String) -> String:
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton:
			return _button_name(e.button_index)
		if e is InputEventJoypadMotion and e.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
			return SHOULDERS[pad_kind][2 if e.axis == JOY_AXIS_TRIGGER_LEFT else 3]
	return "—"

func _button_name(b: int) -> String:
	if FACE[pad_kind].has(b):
		return FACE[pad_kind][b]
	match b:
		JOY_BUTTON_LEFT_SHOULDER:  return SHOULDERS[pad_kind][0]
		JOY_BUTTON_RIGHT_SHOULDER: return SHOULDERS[pad_kind][1]
		JOY_BUTTON_BACK:           return SHOULDERS[pad_kind][4]
		JOY_BUTTON_START:          return SHOULDERS[pad_kind][5]
		JOY_BUTTON_LEFT_STICK:     return "L3"
		JOY_BUTTON_RIGHT_STICK:    return "R3"
		JOY_BUTTON_DPAD_UP:        return tr("D-Pad Up")
		JOY_BUTTON_DPAD_DOWN:      return tr("D-Pad Down")
		JOY_BUTTON_DPAD_LEFT:      return tr("D-Pad Left")
		JOY_BUTTON_DPAD_RIGHT:     return tr("D-Pad Right")
	return tr("Button %d") % b
