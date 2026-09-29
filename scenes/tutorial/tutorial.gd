class_name Tutorial
extends CanvasLayer

# "Learn the basics" (playtest 2: more tutorials). A short solo practice at the Sheep
# Gate, the stretch the priests built beside the temple (Neh. 3:1), walked through one
# step at a time: move, dash, carry, deliver, build, the sling, and helping a fallen
# crewmate up. Each step waits until the player has done it. No waves (WaveManager
# stands down while GameState.tutorial), no story, nothing saved.
#
# The screen says what to do; the world says where. Each step's short call ("Pick up
# [E]") floats as a pulsing tag over the thing to go to — the pile, the wall, the scout,
# the fallen crewmate, or the worker themself — with an edge arrow while it's out of
# view. On phones the plaque shrinks to one row (step and name) so it never hides the
# way, and the touch button the step needs pulses.

const STEP_PAUSE := 0.8   # breath between one step done and the next shown
const PING_EVERY := 0.4   # s between edge-arrow refreshes for an off-screen target

var _main: Node
# [{ "title", "text", "done": Callable, "start": Callable, "goal": Callable, "button" }]
# goal() → [Node3D, "call"] or [] — where to point and what the tag says there
var _steps: Array = []
var _i := -1
var _between := 0.0
var _start_pos := Vector3.ZERO
var _scout: Node3D
var _fallen: Node3D
var _fell := false   # the crewmate has gone down (a beat after joining)
var _saved_sun := true
var _ping_t := 0.0

var _panel: PanelContainer
var _count: Label
var _title: Label
var _text: Label
var _leave: Button
var _guide: WorldTag
var _hidden_tag: WorldTag   # a pile tag the guide is standing in for
var _phone := false

func _init(main: Node) -> void:
	_main = main
	layer = 12

func _ready() -> void:
	_saved_sun = GameState.sun
	GameState.sun = false   # no clock to lose to while learning
	_phone = Mobile.enabled()
	_build()
	_steps = [
		{ "title": "The Sheep Gate",
		  "text": "Eliashib the high priest and his brothers built here, beside the temple (Neh. 3:1). Learn the work with them.\n{interact} to begin",
		  "button": "interact",
		  "done": func(): return Input.is_action_just_pressed("interact") or _elapsed() > 8.0 },
		{ "title": "Walk", "text": "Walk with {move}",
		  "button": "move",
		  "start": func(): _start_pos = _me().global_position,
		  "goal": func(): return [_me(), "Drag on the left to walk" if _touch() else "Walk  {move}"],
		  "done": func(): return _me().global_position.distance_to(_start_pos) > 4.0 },
		{ "title": "Dash", "text": "A quick burst: {dash}. It works while carrying too",
		  "button": "dash",
		  "goal": func(): return [_me(), "Dash  {dash}"],
		  "done": func(): return _me()._dash_cd > 0.0 },
		{ "title": "Carry", "text": "Walk up to a stockpile and pick up a load with {interact}. The wall's tag says what it needs",
		  "button": "interact",
		  "goal": func(): return [_pile(), "Pick up  {interact}"],
		  "done": func(): return not _me().carried_kind.is_empty() },
		{ "title": "Deliver", "text": "Take it to the wall on the amber footing and press {interact}. Not needed there? {drop} drops it",
		  "button": "interact",
		  "goal": _work_goal,
		  "done": func(): return int(_main.director._stats.get("loads", 0)) > 0 },
		{ "title": "Build", "text": "Bring what the wall still asks for. Once it has it all, stand at the wall and work it up with {interact}",
		  "button": "interact",
		  "goal": _work_goal,
		  "done": func(): return _any_built() },
		{ "title": "Guard the builders", "text": "An enemy! Hold {throw} to whirl the sling, aim, and let go. Close in, the same button is a sword cut",
		  "button": "sling",
		  "start": _send_scout,
		  "goal": func(): return [_scout, "Sling it  {throw}"] if _scout_alive() else [],
		  "done": func(): return not _scout_alive() },
		{ "title": "Nobody gets up alone", "text": "Your crewmate is down. Go to them and press {interact} to help them up",
		  "button": "interact",
		  "start": _fell_crewmate,
		  "goal": func(): return [_fallen, "Help up  {interact}"] if _fell and is_instance_valid(_fallen) else [],
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
	TouchControls.hint = ""
	_stand_in(null)
	if _guide != null and is_instance_valid(_guide):
		_guide.queue_free()

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
	_point(delta)
	if _steps[_i]["done"].call():
		Sfx.play("tally_land")
		_panel.modulate = Color(0.8, 1.0, 0.8)   # a green wash: done
		_between = STEP_PAUSE
		_guide.visible = false
		TouchControls.hint = ""
		_stand_in(null)

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
	if _phone:
		_count.text = "%d/%d" % [_i + 1, _steps.size()]
	_title.text = tr(step["title"])
	# Phones: a step with somewhere to go says it there, not in a plaque over the view
	_text.visible = not (_phone and step.has("goal"))
	TouchControls.hint = step.get("button", "")
	_refresh_text()
	_fit.call_deferred()
	UiFx.fade_in(_panel, 0.25)

func _refresh_text() -> void:
	_text.text = _keys(tr(_steps[_i]["text"]))

func _keys(s: String) -> String:
	return s.format({
		"interact": "[%s]" % InputMode.key("interact"), "move": "[%s]" % InputMode.key("move"),
		"dash": "[%s]" % InputMode.key("dash"), "drop": "[%s]" % InputMode.key("drop"),
		"throw": "[%s]" % InputMode.key("throw")})

# The guide tag over this step's goal, and an edge arrow while it's off-screen
func _point(delta: float) -> void:
	var step: Dictionary = _steps[_i]
	var goal: Array = step["goal"].call() if step.has("goal") else []
	var node: Node3D = goal[0] if goal.size() >= 2 else null
	if node == null or not is_instance_valid(node) or not _guide.is_inside_tree():
		_guide.visible = false
		_stand_in(null)
		return
	TouchControls.hint = goal[2] if goal.size() > 2 else step.get("button", "")
	var own_tag := _own_tag(node)
	var at := own_tag.global_position if own_tag != null else node.global_position + Vector3(0.0, 2.4, 0.0)
	_guide.global_position = at
	var call := _keys(tr(goal[1]))
	# A pile's tag only names it: the guide takes its place ("Stone  Pick up [E]"). A
	# site's lists what it still needs, worth keeping: the guide sits on top of it.
	if node.is_in_group("build_sites"):
		_stand_in(null)
		_guide.screen_lift = 58.0 if own_tag != null and own_tag.visible else 0.0
	else:
		_stand_in(own_tag if node.get("count_label") == own_tag else null)
		_guide.screen_lift = 0.0
		if _hidden_tag != null:
			call = _hidden_tag.text + "  " + call
	_guide.text = call
	_guide.visible = true
	# Off-screen: an edge arrow (a downed player already gets OffscreenAlerts' own)
	_ping_t -= delta
	if _ping_t <= 0.0 and not node.is_in_group("players"):
		_ping_t = PING_EVERY
		var alerts := get_tree().get_first_node_in_group("offscreen_alerts")
		if alerts != null:
			alerts.ping(at, UiStyle.AMBER, "Here", PING_EVERY + 0.1)

# Hide this pile tag while the guide speaks for it; bring the last one back
func _stand_in(tag: WorldTag) -> void:
	if tag == _hidden_tag:
		return
	if _hidden_tag != null and is_instance_valid(_hidden_tag):
		_hidden_tag.visible = true
	_hidden_tag = tag
	if tag != null:
		tag.visible = false

# The tag a build site or pile already floats (its needs, its stock), if any
func _own_tag(node: Node3D) -> WorldTag:
	for prop in ["_label", "count_label"]:
		var tag = node.get(prop)
		if tag is WorldTag and is_instance_valid(tag) and tag.is_inside_tree():
			return tag
	return null

# Deliver / build: carrying → the wall; the wall has it all → the wall, to work it;
# otherwise → the pile it still needs
func _work_goal() -> Array:
	var site := SiteFocus.site()
	if site == null:
		return []
	if not _me().carried_kind.is_empty():
		if SiteFocus.matches_carry():
			return [site, "Deliver  {interact}"]
		return [_me(), "Not needed here  {drop}", "drop"]
	if site.has_method("can_build") and site.can_build():
		return [site, "Build  {interact}"]
	return [_pile(), "Pick up  {interact}"]

# Nearest pile of what the focus site still needs (any pile if it can't say)
func _pile() -> Node3D:
	var site := SiteFocus.site()
	var need: String = site.next_need() if site != null and site.has_method("next_need") else ""
	var best: Node3D
	var best_d := INF
	for p: Node3D in get_tree().get_nodes_in_group("supply_piles"):
		if not need.is_empty() and p.kind != need:
			continue
		var d := p.global_position.distance_to(_me().global_position)
		if d < best_d:
			best_d = d
			best = p
	if best == null and not need.is_empty():
		var any := get_tree().get_nodes_in_group("supply_piles")
		return any[0] if not any.is_empty() else null
	return best

func _scout_alive() -> bool:
	return _scout != null and is_instance_valid(_scout) and _scout.get("health") > 0.0

func _touch() -> bool:
	return TouchControls.enabled() and not InputMode.using_pad

func _me() -> Player:
	return Player.local if Player.local != null and is_instance_valid(Player.local) else null

func _any_built() -> bool:
	for w in get_tree().get_nodes_in_group("wall_sections"):
		if w.stage > 0:
			return true
	return false

func _finale() -> void:
	_text.visible = true
	_leave.visible = true
	_leave.text = "Back to the title"
	_leave.theme_type_variation = &"PrimaryButton"
	_leave.focus_mode = Control.FOCUS_ALL
	_leave.grab_focus()
	_fit.call_deferred()

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
	_guide = WorldTag.make(WorldTag.Kind.TOAST)
	_guide.pulse = true
	_guide.visible = false
	_main.add_child.call_deferred(_guide)
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
	if _phone:
		_compact_for_phone(vb)

# Phones: the dp-sized theme (CanvasLayers don't inherit the root's) and one slim row —
# "3/9  Carry" — under the one-row day plaque. The body only shows for the intro and
# the close; every other step says its piece in the world. Leaving mid-way is in the
# game menu.
func _compact_for_phone(vb: VBoxContainer) -> void:
	_panel.theme = Mobile.theme
	_panel.add_theme_stylebox_override("panel", UiStyle.plaque(Vector2(14, 5), 0.9))
	_panel.custom_minimum_size.x = 0
	_text.custom_minimum_size.x = 400
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	vb.move_child(row, 0)
	for l: Label in [_count, _title]:
		vb.remove_child(l)
		row.add_child(l)
	_title.add_theme_font_size_override("font_size", 17)
	_text.add_theme_font_size_override("font_size", 14)
	_count.add_theme_font_size_override("font_size", 12)
	_leave.visible = false
	# Bottom-centre, between the stick and the buttons (the HUD's "Next:" pill spot,
	# which stands down in the practice): the wall and piles are up-screen
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_fit()

# Shrink-wrap the plaque to what it shows now (a hidden body leaves its height behind)
func _fit() -> void:
	if not _phone:
		return
	var bottom := -(Mobile.safe_insets().w + 14.0)
	_panel.offset_left = 0.0
	_panel.offset_right = 0.0
	_panel.offset_top = bottom
	_panel.offset_bottom = bottom
