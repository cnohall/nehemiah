extends CanvasLayer

# The painting over everything while the game is busy: a lobby being made or joined, or
# a scene loading (the game, or back to the menu). Before, a click on Host froze the
# menu with no word of what was happening.
#
#   wait(title, note, on_cancel)  network waits: the menu keeps running underneath;
#                                 Cancel / Esc / B calls on_cancel and lifts the cover
#   go(path, title, section)      scene changes: covers, lets the cover reach the screen,
#                                 changes scene, lifts once the new scene has settled
#
# What's on it fits the time it's up. A load into a stretch (1.5 to 3 s, thread frozen)
# shows one still: the circuit map with that stretch lit (pre-rendered by
# tools/load_maps.gd; the live map can't draw through the stall) and its line of Neh 3.
# A network wait can run long with the menu still animating, so it turns over tips.
#   lift()                        done waiting (failed, or nothing to load after all)
#
# A scene's _ready runs on the main thread, so the stones hold still while it builds:
# the cover's job is to be on screen first, not to animate through the stall.

const BG := preload("res://assets/ui/menu_bg.jpg")
const FADE_IN  := 0.16
const FADE_OUT := 0.45
const SETTLE   := 0.2     # s after the new scene's first frames: shaders, nav bake, dust
const STONES   := 5
const STONE_PERIOD := 2.2 # s for the course to be laid and cleared
const MAP := "res://assets/load/map_%d.jpg"
const TIP_EVERY := 5.0    # s per tip
const TIP_FADE  := 0.25
# Only what holds from day 1, so no tip gets ahead of what a stretch brings in
const TIPS := [
	"Carry the load to the wall, then work it up with your own hands.",
	"Foes come while you build. Drive them off, then go back to the work.",
	"If ten foes reach the inner city, the city falls.",
	"Each stretch has three marks to earn: In good time, None got through, The wall holds.",
	"The campaign is kept at the start of each stretch. Continue picks it up from there.",
	"Every stretch you have built can be played again from the map.",
	"Playing alone: bots fill the crew, and come to the work or the fight when you call.",
]

var _root: Control
var _bg: TextureRect
var _veil: ColorRect
var _center: CenterContainer
var _eyebrow: Label
var _title: Label
var _verse: Label
var _note: Label
var _tip: Label
var _tip_t0 := -1.0       # s; tips turn over while >= 0
var _tip_from := 0
var _tip_shown := -1
var _cancel_btn: Button
var _stones: Control
var _tw: Tween
var _on_cancel := Callable()
var _gen := 0             # each wait/go bumps it; a stale go never lifts a newer cover
var _focus_before: Control
var _holding := false     # go() paused the tree; whoever supersedes it lets go

func _ready() -> void:
	layer = 120             # over the HUD, story cards, pause menu
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.hide()

func is_up() -> bool:
	return _root.visible

## Network wait over the menu. `on_cancel` empty: no way out but the result.
## Resolves once the cover is on screen, so a stall started next (the first host hashes
## every script, NetFingerprint) happens behind it; false if cancelled or replaced by then.
func wait(title: String, note := "", on_cancel := Callable()) -> bool:
	_gen += 1
	var g := _gen
	_release()
	_set_scene(-1)
	_set_text(title, note)
	_start_tips()
	_on_cancel = on_cancel
	_cancel_btn.visible = on_cancel.is_valid()
	await _show()
	await RenderingServer.frame_post_draw
	return g == _gen

## Cover, change scene, lift once the new scene stands. The old scene holds still under
## the cover (tree paused) so nothing in it runs on after its session was torn down.
## `section` >= 0: the load lands on that stretch, so the cover is its map and verse.
func go(path: String, title := "Gathering the builders", section := -1) -> void:
	_gen += 1
	var g := _gen
	get_tree().paused = true
	_holding = true
	_stop_tips()
	if _set_scene(section):
		_set_text(GameState.SECTIONS[section]["name"], GameState.short_ref(StoryData.VERSES[section][1]))
	else:
		_set_text(title, "")
	_on_cancel = Callable()
	_cancel_btn.hide()
	_focus_before = null    # its scene is going away
	await _show()
	# The frame with the cover in it must be drawn before the load stalls the thread
	await RenderingServer.frame_post_draw
	if g != _gen:
		return
	_release()
	if get_tree().change_scene_to_file(path) != OK:
		push_error("LoadCover: could not load %s" % path)
		lift()
		return
	await get_tree().scene_changed
	for i in 3:
		await get_tree().process_frame
	await get_tree().create_timer(SETTLE, true, false, true).timeout
	if g == _gen:
		lift()

func lift() -> void:
	_gen += 1
	_release()
	_stop_tips()
	_on_cancel = Callable()
	if not _root.visible:
		return
	_fade(0.0, FADE_OUT).tween_callback(_root.hide)
	if is_instance_valid(_focus_before) and _focus_before.is_visible_in_tree():
		_focus_before.grab_focus()
	_focus_before = null

# ── Internals ──────────────────────────────────────────────

func _release() -> void:
	if _holding:
		_holding = false
		get_tree().paused = false

func _show() -> Signal:
	if not _root.visible:
		var owner_ := get_viewport().gui_get_focus_owner()
		_focus_before = owner_ if owner_ and not _root.is_ancestor_of(owner_) else null
		_root.modulate.a = 0.0
		_root.show()
	# Keys and pad go to the cover, never to a menu entry still lit underneath
	if _cancel_btn.visible:
		_cancel_btn.grab_focus()
	else:
		get_viewport().gui_release_focus()
	return _fade(1.0, FADE_IN * (1.0 - _root.modulate.a)).finished

func _fade(to: float, time: float) -> Tween:
	if _tw:
		_tw.kill()
	_tw = create_tween().set_ignore_time_scale()
	_tw.tween_property(_root, "modulate:a", to, maxf(time, 0.01)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return _tw

# The painting, or the map of `section` with its verse. True when it's a stretch.
func _set_scene(section: int) -> bool:
	var here := section >= 0 and section < StoryData.VERSES.size()
	var map: Texture2D = null
	if here and ResourceLoader.exists(MAP % section):
		map = load(MAP % section)
	_bg.texture = map if map else BG
	# The map carries its own dark wash on the left: the tablet sits there, the lit
	# stretch stays clear on the right
	_veil.color.a = 0.12 if map else 0.38
	_center.anchor_right = 0.44 if map else 1.0
	_eyebrow.visible = here
	_verse.visible = here
	if here:
		_eyebrow.text = tr("Day %d of %d") % [GameState.SECTIONS[section]["days"][0], GameState.TOTAL_DAYS]
		_verse.text = tr(StoryData.VERSES[section][0])
	return here

func _start_tips() -> void:
	if _tip_t0 < 0.0:
		_tip_from = randi() % TIPS.size()
		_tip_t0 = Time.get_ticks_msec() / 1000.0
		_tip_shown = -1
		_turn_tips()
	_tip.show()

func _stop_tips() -> void:
	_tip_t0 = -1.0
	_tip.hide()

# Clock-driven like the stones: after a stall it shows the tip it should, not the next
func _turn_tips() -> void:
	var t := Time.get_ticks_msec() / 1000.0 - _tip_t0
	var i := (_tip_from + int(t / TIP_EVERY)) % TIPS.size()
	if i != _tip_shown:
		_tip_shown = i
		_tip.text = tr(TIPS[i])
	# The first tip is there at once; later ones fade through
	var into := fmod(t, TIP_EVERY)
	var fade_in := 1.0 if t < TIP_EVERY else clampf(into / TIP_FADE, 0.0, 1.0)
	_tip.modulate.a = minf(fade_in, clampf((TIP_EVERY - into) / TIP_FADE, 0.0, 1.0))

func _set_text(title: String, note: String) -> void:
	_title.text = title     # auto-translated; callers tr() their own format strings
	_note.text = note
	_note.visible = not note.is_empty()

func _input(event: InputEvent) -> void:
	if not _root.visible:
		return
	if event.is_action_pressed("ui_cancel") and _on_cancel.is_valid():
		get_viewport().set_input_as_handled()
		_cancel()
		return
	# Mouse: the cover's own rect stops it. Keys and pad: only Cancel, when it has focus,
	# may take them; nothing reaches the menu or game underneath.
	if event is InputEventMouse or (_cancel_btn.visible and _cancel_btn.has_focus()):
		return
	get_viewport().set_input_as_handled()

func _cancel() -> void:
	var cb := _on_cancel
	lift()
	cb.call()

func _process(_delta: float) -> void:
	if _root.visible:
		_stones.queue_redraw()
		if _tip_t0 >= 0.0:
			_turn_tips()

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_bg = TextureRect.new()
	_bg.texture = BG
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bg)
	# Evening over the painting so the tablet reads as the one thing to look at
	_veil = ColorRect.new()
	_veil.color = Color(UiStyle.DUSK, 0.38)
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_veil)

	_center = CenterContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_center)
	var tablet := PanelContainer.new()
	tablet.add_theme_stylebox_override("panel", UiStyle.plaque(Vector2(44, 28), 0.96))
	tablet.custom_minimum_size.x = 460
	UiStyle.ornament(tablet)
	_center.add_child(tablet)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	tablet.add_child(col)

	_eyebrow = Label.new()
	_eyebrow.theme_type_variation = &"Eyebrow"
	_eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_eyebrow.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_eyebrow.hide()
	col.add_child(_eyebrow)

	_title = Label.new()
	_title.theme_type_variation = &"Heading"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)

	_stones = Control.new()
	_stones.custom_minimum_size = Vector2(0, 26)
	_stones.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stones.draw.connect(_draw_stones)
	col.add_child(_stones)

	_verse = Label.new()
	_verse.theme_type_variation = &"Verse"
	_verse.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_verse.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_verse.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_verse.hide()
	col.add_child(_verse)

	_note = Label.new()
	_note.theme_type_variation = &"Caption"
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # callers pass it tr()'d
	col.add_child(_note)

	_tip = Label.new()
	_tip.theme_type_variation = &"Body"
	_tip.add_theme_font_size_override("font_size", 15)
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_tip.custom_minimum_size.y = 44   # two lines held, so the tablet doesn't jump per tip
	_tip.hide()
	col.add_child(_tip)

	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.theme_type_variation = &"GhostButton"
	_cancel_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_cancel_btn.pressed.connect(_cancel)
	col.add_child(_cancel_btn)

# A course of cut stones laid one by one, then lifted together: the wall going up.
# Clock-driven, so after a stall it jumps to where it should be instead of lagging.
func _draw_stones() -> void:
	var w := 26.0
	var h := 16.0
	var gap := 6.0
	var total := STONES * w + (STONES - 1) * gap
	var x0 := (_stones.size.x - total) * 0.5
	var base_y := _stones.size.y - 2.0
	var t := fmod(Time.get_ticks_msec() / 1000.0, STONE_PERIOD) / STONE_PERIOD
	var clear := smoothstep(0.86, 1.0, t)   # the whole course fades before the next
	for i in STONES:
		var r := Rect2(x0 + i * (w + gap), base_y - h, w, h)
		# Bed: where the stone will sit
		_stones.draw_rect(r, Color(UiStyle.RULE, 0.35), false, 1.0)
		var start := 0.08 + i * 0.13
		var k := clampf((t - start) / 0.12, 0.0, 1.0)
		if k <= 0.0:
			continue
		var ease_ := 1.0 - pow(1.0 - k, 3.0)
		var drop := (1.0 - ease_) * -10.0
		var a := ease_ * (1.0 - clear)
		var s := Rect2(r.position + Vector2(0, drop), r.size)
		_stones.draw_rect(s, Color(UiStyle.AMBER.lerp(UiStyle.PARCHMENT_DEEP, 0.35), a))
		# Carved lip along the bottom, like the tablets
		_stones.draw_rect(Rect2(s.position.x, s.end.y - 3.0, s.size.x, 3.0), Color(UiStyle.TERRACOTTA_DEEP, a * 0.55))
