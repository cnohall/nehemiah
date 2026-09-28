class_name Tutorial
extends CanvasLayer

# "Learn the basics" (playtest 2: more tutorials). A short solo practice at the Sheep
# Gate, the stretch the priests built beside the temple (Neh. 3:1), walked through one
# step at a time: move, dash, carry, deliver, build, the sling, and helping a fallen
# crewmate up. Each step waits until the player has done it. No waves (WaveManager
# stands down while GameState.tutorial), no story, nothing saved.

const STEP_PAUSE := 0.8   # breath between one step done and the next shown

var _main: Node
var _steps: Array = []    # [{ "title", "text", "done": Callable, "start": Callable }]
var _i := -1
var _between := 0.0
var _start_pos := Vector3.ZERO
var _scout: Node3D
var _fallen: Node3D
var _fell := false   # the crewmate has gone down (a beat after joining)
var _saved_sun := true

var _panel: PanelContainer
var _count: Label
var _title: Label
var _text: Label
var _leave: Button

func _init(main: Node) -> void:
	_main = main
	layer = 12

func _ready() -> void:
	_saved_sun = GameState.sun
	GameState.sun = false   # no clock to lose to while learning
	_build()
	_steps = [
		{ "title": "The Sheep Gate",
		  "text": "Eliashib the high priest and his brothers built here, beside the temple (Neh. 3:1). Learn the work with them.\n{interact} to begin",
		  "done": func(): return Input.is_action_just_pressed("interact") or _elapsed() > 8.0 },
		{ "title": "Walk", "text": "Walk with {move}",
		  "start": func(): _start_pos = _me().global_position,
		  "done": func(): return _me().global_position.distance_to(_start_pos) > 4.0 },
		{ "title": "Dash", "text": "A quick burst: {dash}. It works while carrying too",
		  "done": func(): return _me()._dash_cd > 0.0 },
		{ "title": "Carry", "text": "Walk up to a stockpile and pick up a load with {interact}. The wall's tag says what it needs",
		  "done": func(): return not _me().carried_kind.is_empty() },
		{ "title": "Deliver", "text": "Take it to the wall on the amber footing and press {interact}. Not needed there? {drop} drops it",
		  "done": func(): return int(_main.director._stats.get("loads", 0)) > 0 },
		{ "title": "Build", "text": "Bring what the wall still asks for. Once it has it all, stand at the wall and work it up with {interact}",
		  "done": func(): return _any_built() },
		{ "title": "Guard the builders", "text": "An enemy! Hold {throw} to whirl the sling, aim, and let go. Close in, the same button is a sword cut",
		  "start": _send_scout,
		  "done": func(): return _scout == null or not is_instance_valid(_scout) or _scout.get("health") <= 0.0 },
		{ "title": "Nobody gets up alone", "text": "Your crewmate is down. Go to them and press {interact} to help them up",
		  "start": _fell_crewmate,
		  "done": func(): return _fell and is_instance_valid(_fallen) and not _fallen.downed },
		{ "title": "That's the work", "text": "Carry, build, guard, and lift each other up.\n“Let us rise up and build.” (Neh. 2:18)",
		  "start": _finale,
		  "done": func(): return false },
	]
	# One frame in: the day director is set up, the crew spawned
	await get_tree().process_frame
	_main.director.begin()
	_next()

func _exit_tree() -> void:
	GameState.sun = _saved_sun

var _step_t := 0.0

func _elapsed() -> float:
	return _step_t

func _process(delta: float) -> void:
	if _i < 0 or _i >= _steps.size() or _me() == null:
		return
	if _between > 0.0:
		_between -= delta
		if _between <= 0.0:
			_next()
		return
	_step_t += delta
	_refresh_text()   # keys follow the device in use
	if _steps[_i]["done"].call():
		Sfx.play("tally_land")
		_panel.modulate = Color(0.8, 1.0, 0.8)   # a green wash: done
		_between = STEP_PAUSE

func _next() -> void:
	_i += 1
	_step_t = 0.0
	_panel.modulate = Color.WHITE
	if _i >= _steps.size():
		return
	var step: Dictionary = _steps[_i]
	if step.has("start"):
		step["start"].call()
	_count.text = tr("Step %d of %d") % [_i + 1, _steps.size()]
	_title.text = tr(step["title"])
	_refresh_text()
	UiFx.fade_in(_panel, 0.25)

func _refresh_text() -> void:
	_text.text = tr(_steps[_i]["text"]).format({
		"interact": "[%s]" % InputMode.key("interact"), "move": "[%s]" % InputMode.key("move"),
		"dash": "[%s]" % InputMode.key("dash"), "drop": "[%s]" % InputMode.key("drop"),
		"throw": "[%s]" % InputMode.key("throw")})

func _me() -> Player:
	return Player.local if Player.local != null and is_instance_valid(Player.local) else null

func _any_built() -> bool:
	for w in get_tree().get_nodes_in_group("wall_sections"):
		if w.stage > 0:
			return true
	return false

func _finale() -> void:
	_leave.text = "Back to the title"
	_leave.theme_type_variation = &"PrimaryButton"
	_leave.focus_mode = Control.FOCUS_ALL
	_leave.grab_focus()

# One scout, a little way out beyond the wall from wherever the player is
func _send_scout() -> void:
	_scout = load("res://scenes/enemy/enemy.tscn").instantiate()
	_scout.type = 0
	var at := _me().global_position
	_scout.position = Vector3(clampf(at.x, -12.0, 12.0), 0.1, -9.0)
	_main.enemies_root.add_child(_scout, true)

# A crewmate joins beside the player, then falls
func _fell_crewmate() -> void:
	_main.fit_bots(1)
	for p: Player in _main.players_root.get_children():
		if p.is_bot():
			_fallen = p
	if _fallen == null:
		return
	_fallen.global_position = _me().global_position + Vector3(3.0, 0.0, 1.5)
	await get_tree().create_timer(0.3).timeout
	if is_instance_valid(_fallen):
		_fallen.take_damage(1000.0)
		_fell = true

func _build() -> void:
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiStyle.plaque(Vector2(26, 16), 0.95))
	_panel.custom_minimum_size.x = 620
	add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 16)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	UiStyle.ornament(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	_panel.add_child(vb)
	_count = Label.new()
	_count.theme_type_variation = &"Eyebrow"
	_count.add_theme_color_override("font_color", UiStyle.TERRACOTTA)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_count)
	_title = Label.new()
	_title.theme_type_variation = &"Heading"
	_title.add_theme_color_override("font_color", UiStyle.INK)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_title)
	_text = Label.new()
	_text.theme_type_variation = &"Body"
	_text.add_theme_color_override("font_color", UiStyle.INK_SOFT)
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = 580
	vb.add_child(_text)
	for l: Label in [_count, _title, _text]:
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # set translated
	_leave = Button.new()
	_leave.theme_type_variation = &"GhostButton"
	_leave.text = "Leave the practice"
	_leave.focus_mode = Control.FOCUS_NONE
	_leave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_leave.pressed.connect(func(): _main.hud._leave())
	vb.add_child(_leave)
