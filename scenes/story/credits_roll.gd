class_name CreditsRoll
extends CanvasLayer

# The credits: they roll up the dark left column over the finished city (CircuitMap in
# finale mode, quiet — no plaques), the gold line closing the ring behind them, and end
# on the last words of the book. Plays after the ending story, and from the main menu.
# Hold E / Enter to hurry it along; Esc skips. Phones: type at ~0.6 scale, touch and
# hold to hurry, a close button (or Android back) to skip.

signal finished

const SPEED      := 58.0     # px/s
const FAST       := 5.0      # × while held
const START_HOLD := 1.4      # seconds before the roll starts moving
const END_HOLD   := 5.0      # the closing verse stays this long once it's up
const COLUMN     := 760.0
const PHONE_SCALE := 0.6
const STUDIO_LOGO: Texture2D = preload("res://assets/brand/takiko_mark.png")

# [kind, text, detail]. Kinds: title, subtitle, role (a heading), name, small (licence
# lines), gap, logo (the studio's), verse, ref, thanks. Names and titles of works stay as written.
const ROLL := [
	["title", "Nehemiah", ""],
	["subtitle", "The Wall", ""],
	["gap", "", ""],
	["logo", "", ""],
	["small", "A Takiko Games production", ""],
	["gap", "", ""],
	["role", "Development", ""],
	["name", "Chris Nohall", ""],
	["role", "Game design", ""],
	["name", "Joakim Henriquez", ""],
	["gap", "", ""],
	["role", "Scripture", ""],
	["name", "World English Bible", ""],
	["small", "Public domain · ebible.org", ""],
	["small", "Nehemiah 4:14 adapted", ""],
	["role", "Music", ""],
	["name", "“Caryil, The Desert of Dreams”", ""],
	["small", "by insydnis · CC-BY 3.0 · opengameart.org", ""],
	["name", "“Desert theme”", ""],
	["small", "by yd · CC0 · opengameart.org", ""],
	["name", "AlkaKrab", ""],
	["small", "“Desert Fantasy Ambient” · alkakrab.itch.io", ""],
	["role", "Sound", ""],
	["name", "Kenney", ""],
	["small", "kenney.nl · CC0", ""],
	["role", "Type", ""],
	["name", "Cinzel · Spectral · Noto Serif KR", ""],
	["small", "SIL Open Font License 1.1", ""],
	["role", "Made with", ""],
	["name", "Godot Engine", ""],
	["small", "godotengine.org · MIT License", ""],
	["name", "GodotSteam", ""],
	["small", "godotsteam.com · MIT License", ""],
	["name", "Epic Online Services", ""],
	["small", "EOSG plugin by 3ddelano · MIT License", ""],
	["gap", "", ""],
	["gap", "", ""],
	["verse", "“Remember me, my God, for good.”", ""],
	["ref", "Neh. 13:31", ""],
	["gap", "", ""],
	["thanks", "Thank you for building with us.", ""],
]

var _root: Control
var _map: CircuitMap
var _clip: Control
var _column: VBoxContainer
var _hint: Label
var _playing := false
var _done := false
var _wait := 0.0
var _k := 1.0          # type and spacing scale: 1 on a monitor, PHONE_SCALE on phones
var _col_w := COLUMN

func _ready() -> void:
	layer = 22
	if Mobile.enabled():
		_k = PHONE_SCALE
		_col_w = COLUMN * 0.66
	_build()
	_root.hide()

func play() -> void:
	_playing = true
	_done = false
	_wait = START_HOLD
	_root.show()
	UiFx.fade_in(_root, 1.2)
	_map.section = CircuitDiorama.GATES.size() - 1
	_map.finale = true
	_map.play()
	Sfx.play_music("calm")
	_column.position.y = _clip.size.y   # starts just below the fold

func is_playing() -> bool:
	return _playing

func _process(delta: float) -> void:
	if not _playing or _done:
		return
	if _wait > 0.0:
		_wait -= delta
		return
	var hurry := Input.is_action_pressed("interact") or Input.is_action_pressed("ui_accept") \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	# Stops with the closing lines just above the middle of the screen
	var end_y := _clip.size.y * 0.6 - _column.size.y
	_column.position.y = maxf(end_y, _column.position.y - SPEED * _k * delta * (FAST if hurry else 1.0))
	if _column.position.y <= end_y:
		_done = true
		_hint.hide()
		await get_tree().create_timer(END_HOLD).timeout
		_finish()

# Keys and pad buttons stop here, so nothing behind the roll reacts (holding Enter to
# hurry would press the menu's focused button again); _process polls them directly
func _input(event: InputEvent) -> void:
	if not _playing:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		_finish()
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventAction:
		get_viewport().set_input_as_handled()

func _finish() -> void:
	if not _playing:
		return
	_playing = false
	_done = true
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(_root.hide)
	tw.tween_callback(finished.emit)

# ── Layout ─────────────────────────────────────────────────

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var phone := Mobile.enabled()
	var ins := Mobile.safe_insets() if phone else Vector4.ZERO
	var left := 32.0 + ins.x if phone else 140.0
	if phone:
		_root.theme = Mobile.theme   # themes don't cross the CanvasLayer
	var black := ColorRect.new()
	black.color = UiStyle.DUSK
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(black)
	_map = CircuitMap.new()
	_map.quiet = true
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_map)

	# The roll, masked so lines fade in at the foot and out at the head rather than pop:
	# the clip draws a vertical alpha ramp that only its children show through
	_clip = Control.new()
	_clip.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_clip.offset_left = left
	_clip.offset_right = left + _col_w
	_clip.offset_bottom = -(48.0 + ins.w) if phone else -90.0   # clear of the hint
	_clip.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mask := _mask_texture()
	_clip.draw.connect(func(): _clip.draw_texture_rect(mask, Rect2(Vector2.ZERO, _clip.size), false))
	_clip.resized.connect(_clip.queue_redraw)
	_root.add_child(_clip)
	_column = VBoxContainer.new()
	_column.custom_minimum_size.x = _col_w
	_column.add_theme_constant_override("separation", roundi(6 * _k))
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(_column)
	for row: Array in ROLL:
		_column.add_child(_line(row[0], row[1]))

	_hint = Label.new()
	_hint.theme_type_variation = &"Eyebrow"
	_hint.add_theme_font_size_override("font_size", 11 if phone else 13)
	_hint.add_theme_color_override("font_color", Color(UiStyle.CREAM, 0.55 if phone else 0.5))
	_hint.text = "Touch and hold to go faster" if phone else "Hold E   Faster          Esc   Skip"
	# Bottom left, on the dark side: the sand on the right is too bright for it
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.position += Vector2(left, -(20.0 + ins.w) if phone else -48.0)
	_root.add_child(_hint)
	if phone:
		# Skip: a close button top right (Android back skips too)
		var skip := UiIcons.button("close", "Skip", 48.0, &"FlatIconButton")
		for c: String in ["icon_normal_color", "icon_hover_color", "icon_focus_color"]:
			skip.add_theme_color_override(c, Color(UiStyle.CREAM, 0.8))
		skip.add_theme_color_override("icon_pressed_color", UiStyle.GOLD)
		skip.pressed.connect(_finish)
		_root.add_child(skip)
		skip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		skip.offset_left = -(48.0 + 16.0 + ins.z)
		skip.offset_right = -(16.0 + ins.z)
		skip.offset_top = 12.0 + ins.y
		skip.offset_bottom = 60.0 + ins.y

func _line(kind: String, text: String) -> Control:
	if kind == "gap":
		var g := Control.new()
		g.custom_minimum_size.y = 90 * _k
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return g
	if kind == "logo":
		var logo := TextureRect.new()
		logo.texture = STUDIO_LOGO
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		# Sized to the texture and shrunk to the left, so its edge lines up with the text
		logo.custom_minimum_size = Vector2(180.0 * STUDIO_LOGO.get_width() / STUDIO_LOGO.get_height(), 180)
		logo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return logo
	# One line each. The verse and the thanks may wrap (Korean runs long), so they get
	# the column's width up front: a wrapped label left to measure itself at zero width
	# comes out thousands of pixels tall, and the column never shrinks back from that
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if kind in ["verse", "thanks"]:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = _col_w
	var font_size := 20
	var color := UiStyle.CREAM
	match kind:
		"title":
			l.theme_type_variation = &"Heading"
			l.add_theme_font_override("font", UiStyle.tracked(UiStyle.CINZEL_BOLD, 10))
			font_size = 96
			l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		"subtitle":
			l.theme_type_variation = &"Eyebrow"
			font_size = 22
			color = UiStyle.GOLD
		"role":
			l.theme_type_variation = &"Eyebrow"
			font_size = 15
			color = UiStyle.GOLD
			l.custom_minimum_size.y = 64 * _k
			l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		"name":
			l.theme_type_variation = &"Heading"
			l.add_theme_font_override("font", UiStyle.tracked(UiStyle.CINZEL_SEMI, 3))
			font_size = 38
			l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		"small":
			l.theme_type_variation = &"Caption"
			font_size = 17
			color = Color(UiStyle.CREAM, 0.62)
		"verse":
			l.theme_type_variation = &"Verse"
			font_size = 40
			color = UiStyle.PARCHMENT
		"ref":
			l.text = GameState.long_ref(text)   # "Nehemia 13:31" and so on
			l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			l.theme_type_variation = &"Eyebrow"
			font_size = 15
			color = Color(UiStyle.GOLD, 0.85)
		"thanks":
			l.theme_type_variation = &"Body"
			font_size = 24
			color = Color(UiStyle.CREAM, 0.8)
	# Phones: smaller, but the licence lines keep a readable floor
	l.add_theme_font_size_override("font_size", maxi(roundi(font_size * _k), 12))
	l.add_theme_color_override("font_color", color)
	return l

## Clear at the head and foot of the column, solid through the middle
func _mask_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.16, 0.84, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 4
	tex.height = 256
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	return tex
