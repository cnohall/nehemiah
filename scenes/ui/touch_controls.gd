class_name TouchControls
extends Control

# On-screen controls for phones/tablets. Everything is injected as InputEventActions,
# so the player script reads touch exactly like the keyboard — except sling aim,
# which it pulls from `aiming` / `aim_vec` instead of the mouse.
#
# Left half: floating stick (appears under the thumb). Right corner: button cluster.
# Enabled on mobile builds, or on desktop with `-- --touch` (mouse emulates one finger).
# Sizes are dp (see Mobile): every button is at least a 52dp target.

const STICK_RADIUS := 58.0
const KNOB_RADIUS  := 26.0
const STICK_ZONE   := 0.45     # left fraction of the screen that spawns the stick
const AIM_DEADZONE := 0.25     # sling drag shorter than this = auto-aim
const EDGE         := 18.0     # gap from the (safe-area) screen edge
const IDLE_ALPHA   := 0.62     # resting buttons stay out of the way of the world

## Sling held: player aims from aim_vec (screen-space, length 0..1) instead of the mouse
static var aiming := false
static var aim_vec := Vector2.ZERO

# Controls that, while visible, own the screen (pause menu, end screen …)
var blockers: Array[Control] = []
# Real GUI controls on top of the stick zone (pause, room code, Begin …): touches
# landing on them are left for the GUI instead of spawning the stick
var passthrough: Array[Control] = []

# name → { action, pos, r, label }. Laid out in _layout().
var _buttons := {}
var _touches := {}             # touch index → "stick" | button name
var _stick_center := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _move_sent := {}           # move action → last strength sent
var _safe := Rect2()

static func enabled() -> bool:
	return OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--touch")

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not OS.has_feature("mobile"):
		Input.emulate_touch_from_mouse = true
	get_viewport().size_changed.connect(_layout.call_deferred)
	_layout()

func _exit_tree() -> void:
	_release_all()

func _process(_delta: float) -> void:
	var blocked := GameState.phase == GameState.Phase.STORY
	for b in blockers:
		blocked = blocked or b.visible
	if blocked == visible:
		visible = not blocked
		if blocked:
			_release_all()
	queue_redraw()

# ── Layout ─────────────────────────────────────────────────

func _layout() -> void:
	var vp := get_viewport_rect().size
	_safe = _safe_rect(vp)
	var br := _safe.end - Vector2(EDGE, EDGE)
	# Sling is the thumb's home: biggest, in the corner. The rest fan around it on
	# an arc the thumb sweeps without re-gripping.
	_buttons = {
		sling    = { action = "throw_charge", pos = br - Vector2(50, 54),   r = 46.0, label = "Sling", icon = "sling" },
		interact = { action = "interact",     pos = br - Vector2(160, 36),  r = 36.0, label = "Carry", icon = "carry" },
		dash     = { action = "dash",         pos = br - Vector2(36, 164),  r = 30.0, label = "Dash",  icon = "dash" },
		drop     = { action = "drop",         pos = br - Vector2(138, 128), r = 26.0, label = "Drop",  icon = "drop" },
	}

# Display safe area (notch, rounded corners) mapped into viewport coordinates
func _safe_rect(vp: Vector2) -> Rect2:
	var win := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if win.x <= 0 or safe.size.x <= 0 or not OS.has_feature("mobile"):
		return Rect2(Vector2.ZERO, vp)
	var k := vp / win
	var r := Rect2(safe.position * k, safe.size * k)
	return r.intersection(Rect2(Vector2.ZERO, vp))

# ── Input ──────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_down(event.index, event.position)
		else:
			_touch_up(event.index)
	elif event is InputEventScreenDrag and _touches.has(event.index):
		_touch_move(event.index, event.position)

func _touch_down(index: int, pos: Vector2) -> void:
	for c in passthrough:
		if is_instance_valid(c) and c.is_visible_in_tree() and c.get_global_rect().grow(4.0).has_point(pos):
			return
	for name: String in _buttons:
		var b: Dictionary = _buttons[name]
		# Generous hit area — thumbs land off-centre
		if pos.distance_to(b.pos) <= b.r * 1.2:
			_touches[index] = name
			if name == "sling":
				aiming = true
				aim_vec = Vector2.ZERO
			_send(b.action, true)
			Mobile.haptic()
			get_viewport().set_input_as_handled()
			return
	if pos.x < _safe.position.x + _safe.size.x * STICK_ZONE and not _touches.values().has("stick"):
		_touches[index] = "stick"
		# Keep the whole ring on screen so the stick never starts pinned
		var lo := _safe.position + Vector2(STICK_RADIUS, STICK_RADIUS)
		var hi := _safe.end - Vector2(STICK_RADIUS, STICK_RADIUS)
		_stick_center = pos.clamp(lo, hi)
		_touch_move(index, pos)
		get_viewport().set_input_as_handled()

func _touch_move(index: int, pos: Vector2) -> void:
	match _touches.get(index, ""):
		"stick":
			_stick_vec = ((pos - _stick_center) / STICK_RADIUS).limit_length(1.0)
			_send_move(_stick_vec)
		"sling":
			var v: Vector2 = ((pos - _buttons.sling.pos) / STICK_RADIUS).limit_length(1.0)
			aim_vec = v if v.length() >= AIM_DEADZONE else Vector2.ZERO

func _touch_up(index: int) -> void:
	var role: String = _touches.get(index, "")
	_touches.erase(index)
	match role:
		"":
			return
		"stick":
			_stick_vec = Vector2.ZERO
			_send_move(Vector2.ZERO)
		_:
			_send(_buttons[role].action, false)
			if role == "sling":
				# Player reads the aim this frame on release; clear next frame
				_clear_aim.call_deferred()

func _clear_aim() -> void:
	if not _touches.values().has("sling"):
		aiming = false
		aim_vec = Vector2.ZERO

func _release_all() -> void:
	for index in _touches.keys():
		_touch_up(index)
	aiming = false
	aim_vec = Vector2.ZERO

# Stick → the four iso move actions, as analog strengths (Input.get_vector reads them)
func _send_move(v: Vector2) -> void:
	var want := {
		move_east = maxf(v.x, 0.0), move_west = maxf(-v.x, 0.0),
		move_south = maxf(v.y, 0.0), move_north = maxf(-v.y, 0.0),
	}
	for action: String in want:
		var s: float = want[action]
		if not is_equal_approx(s, _move_sent.get(action, 0.0)):
			_move_sent[action] = s
			_send(action, s > 0.0, s)

func _send(action: String, pressed: bool, strength := 1.0) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = pressed
	e.strength = strength if pressed else 0.0
	Input.parse_input_event(e)

# ── Drawing ────────────────────────────────────────────────

func _draw() -> void:
	var font := UiStyle.tracked(UiStyle.CINZEL_BOLD, 1)
	var held: Array = _touches.values()
	if held.has("stick"):
		draw_circle(_stick_center, STICK_RADIUS, Color(UiStyle.DUSK, 0.2))
		draw_arc(_stick_center, STICK_RADIUS, 0, TAU, 64, Color(UiStyle.CREAM, 0.6), 2.0, true)
		var knob := _stick_center + _stick_vec * STICK_RADIUS
		draw_circle(knob + Vector2(0, 2), KNOB_RADIUS, Color(UiStyle.DUSK, 0.18))
		draw_circle(knob, KNOB_RADIUS, Color(UiStyle.PARCHMENT, 0.92))
	# Sling drag: aim line first, so the button sits over its root
	if aiming and aim_vec != Vector2.ZERO:
		var p: Vector2 = _buttons.sling.pos
		var tip: Vector2 = p + aim_vec * STICK_RADIUS * 1.6
		draw_line(p, tip, Color(UiStyle.CREAM, 0.9), 4.0, true)
		draw_circle(tip, 6.0, UiStyle.CREAM)
	for name: String in _buttons:
		var b: Dictionary = _buttons[name]
		var down := held.has(name)
		var primary := name == "sling"
		var fill := UiStyle.TERRACOTTA if primary else UiStyle.PARCHMENT
		var ink := UiStyle.CREAM if primary else UiStyle.INK
		var a := 0.95 if down else IDLE_ALPHA
		var r: float = b.r * (0.94 if down else 1.0)   # pressed: sink a touch
		draw_circle(b.pos + Vector2(0, 2.5), r, Color(UiStyle.DUSK, 0.22 * a))
		draw_circle(b.pos, r, Color(fill, a))
		draw_arc(b.pos, r - 1.0, 0, TAU, 48, Color(UiStyle.TERRACOTTA_DEEP if primary else UiStyle.RULE, a), 1.5, true)
		# Glyph above a small caption; the smallest button is icon-only
		var labelled := r >= 30.0
		var glyph := r * (0.62 if not labelled else 0.56)
		var gpos: Vector2 = b.pos - Vector2(glyph, glyph) * 0.5 - Vector2(0, 6.0 if labelled else 0.0)
		draw_texture_rect(UiIcons.get_icon(b.icon, glyph), Rect2(gpos, Vector2(glyph, glyph)), false, Color(ink, 0.95))
		if labelled:
			var size := 11
			var w := font.get_string_size(b.label.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			draw_string(font, b.pos + Vector2(-w * 0.5, glyph * 0.5 + 8.0), b.label.to_upper(),
				HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(ink, 0.9))
