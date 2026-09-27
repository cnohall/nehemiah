class_name FriendsAndFoes
extends Control

# Main menu → "Friends and Foes": everyone in the game, the crew and those against the
# work, each turning slowly in a small private world (as CrewPortrait does), with who
# they are and the verse behind them. Foes stay dark silhouettes until this player has
# met them (GameState.has_met): enemies on sight, the leaders in their story beat.

signal closed

const TURN_SPEED := 0.45     # rad/s
const VIEW_PX    := Vector2i(640, 820)
# Not met yet: the figure as one flat shape of ink, no detail showing through
const SILHOUETTE := """
shader_type canvas_item;
uniform vec4 ink : source_color;
void fragment() { COLOR = vec4(ink.rgb, texture(TEXTURE, UV).a * ink.a); }
"""

# key, group, name, role (eyebrow), text, ref. Where a foe is first met: GameState.MET_AT.
# Enemy entries carry "enemy" (CharacterRig.enemy_look kind) for their stats.
const ENTRIES := [
	{ "key": "nehemiah", "group": "friends", "name": "Nehemiah",
	  "role": "Governor of Judah · Cupbearer to the king",
	  "text": "He asks King Artaxerxes to send him to rebuild the city of his forefathers, inspects the broken walls by night, and works beside the people. When his enemies call him away, he stays at the work.",
	  "ref": "Neh. 2:5" },
	{ "key": "builder", "group": "friends", "name": "Builder", "slot": 0,
	  "role": "The crew · First player",
	  "text": "Sets the stones and raises the wall course by course, a basket of stones on the back and a hammer at the belt. Every builder kept a sword at his side.",
	  "ref": "Neh. 4:18" },
	{ "key": "water_carrier", "group": "friends", "name": "Water carrier", "slot": 1,
	  "role": "The crew · Second player",
	  "text": "The burden-bearers carried their loads with one hand and held a weapon in the other: water for the mortar, stone and timber for the wall.",
	  "ref": "Neh. 4:17" },
	{ "key": "carpenter", "group": "friends", "name": "Carpenter", "slot": 2,
	  "role": "The crew · Third player",
	  "text": "Lays the beams and hangs the doors of each gate, with their bolts and bars.",
	  "ref": "Neh. 3:3" },
	{ "key": "overseer", "group": "friends", "name": "Overseer", "slot": 3,
	  "role": "The crew · Fourth player",
	  "text": "The work is great and the wall is long, and the builders are spread thin along it. Where the horn sounds, the crew gathers.",
	  "ref": "Neh. 4:19-20" },
	{ "key": "sanballat", "group": "foes", "name": "Sanballat",
	  "role": "The Horonite · Samaria",
	  "text": "Furious that anyone has come to seek the good of the people. He mocks the builders before the army of Samaria, then plots to attack the city.",
	  "ref": "Neh. 4:1-2" },
	{ "key": "tobiah", "group": "foes", "name": "Tobiah",
	  "role": "The Ammonite · Ammon",
	  "text": "Sanballat's companion, an official from Ammon. He jokes that a fox climbing on the wall would break it down, and sends letters to make Nehemiah afraid.",
	  "ref": "Neh. 4:3" },
	{ "key": "geshem", "group": "foes", "name": "Geshem",
	  "role": "The Arab · Arabia",
	  "text": "He laughs at the work from the start, joins the plot against the city, and with Sanballat invites Nehemiah down to the plain of Ono.",
	  "ref": "Neh. 6:1-2" },
	{ "key": "messenger", "group": "foes", "name": "Messenger",
	  "role": "Sent by Sanballat and Geshem",
	  "text": "He walks up to a worker with an open letter and an invitation to Ono, and waits. Go with him and you are led away from the wall. Keep working and he gives up.",
	  "ref": "Neh. 6:3-5" },
	{ "key": "scout", "group": "foes", "name": "Scout", "enemy": "scout",
	  "role": "From the first day",
	  "text": "Light and quick. Some slip through the gaps for the inner city, others turn on the wall. A few sling stones bring one down.",
	  "ref": "Neh. 4:8" },
	{ "key": "brute", "group": "foes", "name": "Brute", "enemy": "brute",
	  "role": "From day 9",
	  "text": "Helmet, shield and spear. Slow, but he hits hard, takes many stones, and always goes for the wall.",
	  "ref": "Neh. 4:11" },
	{ "key": "raider", "group": "foes", "name": "Raider", "enemy": "raider",
	  "role": "From day 21",
	  "text": "Hooded and cloaked, with a dagger, and the fastest of them all. Raiders reach a gap before you do.",
	  "ref": "Neh. 4:11" },
]
const GROUPS := { "friends": "The builders", "foes": "Those against the work" }

var _selected := -1
var _list: VBoxContainer
var _buttons: Array[Button] = []
var _view_box: SubViewportContainer
var _shadow_mat: ShaderMaterial
var _holder: Node3D
var _rig: CharacterRig
var _eyebrow: Label
var _title: Label
var _ref: Label
var _text: Label
var _stats: GridContainer
var _back_btn: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	hide()

func open() -> void:
	for i in ENTRIES.size():
		var e: Dictionary = ENTRIES[i]
		var known := _known(e)
		_buttons[i].text = e["name"] if known else "? ? ?"
		_buttons[i].auto_translate_mode = Node.AUTO_TRANSLATE_MODE_INHERIT if known \
			else Node.AUTO_TRANSLATE_MODE_DISABLED
	show()
	UiFx.fade_in(self, 0.35)
	_selected = -1
	_buttons[0].grab_focus()
	_select(0)

func close() -> void:
	hide()
	closed.emit()

static func _known(e: Dictionary) -> bool:
	return e["group"] == "friends" or GameState.has_met(e["key"])

func _process(delta: float) -> void:
	if visible and _holder:
		_holder.rotation.y += TURN_SPEED * delta

func _input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		close()

# ── Selection ──────────────────────────────────────────────

func _select(i: int) -> void:
	if i == _selected:
		return
	_selected = i
	var e: Dictionary = ENTRIES[i]
	var known := _known(e)
	_rig.set_look(_look(e))
	_rig.play("idle_down")
	_holder.rotation.y = -0.5
	_holder.scale = Vector3.ONE * (Enemy.SCALE[_enemy_type(e)] if e.has("enemy") else 1.0)
	_view_box.material = null if known else _shadow_mat
	_eyebrow.text = tr(e["role"]) if known else tr("First met at the %s") % tr(GameState.SECTIONS[GameState.MET_AT[e["key"]]]["name"])
	_title.text = tr(e["name"]) if known else tr("Not yet met")
	_ref.text = GameState.long_ref(e["ref"]) if known else ""
	_ref.visible = known
	_text.text = tr(e["text"]) if known else tr("Keep building. You will meet them on the wall.")
	for c in _stats.get_children():
		c.queue_free()
	_stats.visible = known and e.has("enemy")
	if _stats.visible:
		var t := _enemy_type(e)
		# Against the fastest, toughest, hardest-hitting of the three
		_stat_row("Speed", Enemy.SPEED[t] / Enemy.SPEED[Enemy.Type.RAIDER])
		_stat_row("Toughness", Enemy.HEALTH[t] / Enemy.HEALTH[Enemy.Type.BRUTE])
		_stat_row("Strength", Enemy.DAMAGE[t] / Enemy.DAMAGE[Enemy.Type.BRUTE])
	UiFx.fade_in(_title, 0.3)
	UiFx.fade_in(_text, 0.4, 0.05)
	Sfx.play("tally")

static func _enemy_type(e: Dictionary) -> Enemy.Type:
	return { "scout": Enemy.Type.SCOUT, "brute": Enemy.Type.BRUTE, "raider": Enemy.Type.RAIDER }[e["enemy"]]

func _stat_row(label: String, share: float) -> void:
	_stats.add_child(_label(&"Eyebrow", 13, UiStyle.INK_SOFT, false, label))
	var pips := Control.new()
	pips.custom_minimum_size = Vector2(120, 18)
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var filled := clampi(roundi(share * 5.0), 1, 5)
	pips.draw.connect(func():
		for k in 5:
			var c := Vector2(9 + k * 22, 9)
			if k < filled:
				pips.draw_circle(c, 7, UiStyle.TERRACOTTA)
			else:
				pips.draw_arc(c, 6, 0, TAU, 24, UiStyle.INK_MUTED, 1.5, true))
	_stats.add_child(pips)

## The figure: the crew in their slot colours, enemies as in the game, and the story's
## people dressed for their part (foes share the enemies' oxblood outline)
static func _look(e: Dictionary) -> Dictionary:
	if e.has("slot"):
		return CharacterRig.worker_look(e["slot"], Palette.CREW[e["slot"]])
	if e.has("enemy"):
		return CharacterRig.enemy_look(e["enemy"])
	var foe := { "outline": Color(0.36, 0.07, 0.05), "brows": true, "tool": false, "bare_arms": false }
	match e["key"]:
		"nehemiah":
			return { "skin": CharacterRig.SKIN[1], "hair": CharacterRig.HAIR_DARK, "beard": "full",
				"hat": "wrap", "hat_color": Color(0.96, 0.94, 0.89), "band": Color(0.80, 0.62, 0.26),
				"robe": Color(0.93, 0.90, 0.83), "vest": Color(0.20, 0.30, 0.52), "long_robe": true,
				"trim": Color(0.80, 0.62, 0.26), "sash": Color(0.80, 0.62, 0.26),
				"outline": CharacterRig.OUTLINE_PLAYER, "no_outline": true, "tool": false }
		"sanballat":
			foe.merge({ "skin": Color(0.64, 0.44, 0.30), "hair": Color(0.10, 0.08, 0.07), "beard": "long",
				"hat": "wrap", "hat_color": Color(0.30, 0.10, 0.09), "band": Color(0.74, 0.54, 0.26),
				"robe": Color(0.42, 0.14, 0.11), "vest": Color(0.22, 0.10, 0.09), "long_robe": true,
				"trim": Color(0.74, 0.54, 0.26), "sash": Color(0.74, 0.54, 0.26) })
		"tobiah":
			foe.merge({ "skin": Color(0.58, 0.40, 0.27), "hair": Color(0.14, 0.10, 0.08), "beard": "full",
				"hat": "band", "hat_color": Color(0.30, 0.28, 0.16),
				"robe": Color(0.36, 0.34, 0.20), "vest": Color(0.20, 0.18, 0.12), "long_robe": true,
				"trim": Color(0.20, 0.18, 0.12), "sash": Color(0.52, 0.16, 0.12),
				"scroll": Color(0.90, 0.82, 0.62) })
		"geshem":
			foe.merge({ "skin": Color(0.52, 0.35, 0.23), "hair": Color(0.08, 0.06, 0.05), "beard": "long",
				"hat": "scarf", "hat_color": Color(0.90, 0.86, 0.76), "stripe": Color(0.52, 0.14, 0.11),
				"robe": Color(0.76, 0.64, 0.46), "trim": Color(0.46, 0.34, 0.22),
				"sash": Color(0.52, 0.14, 0.11), "cape": Color(0.30, 0.20, 0.14), "long_robe": true })
		"messenger":
			foe.merge({ "skin": Color(0.66, 0.46, 0.32), "robe": Messenger.ROBE, "trim": Messenger.ROBE.darkened(0.45),
				"sash": Color(0.80, 0.62, 0.26), "hat": "wrap", "hat_color": Color(0.86, 0.78, 0.56),
				"band": Color(0.80, 0.62, 0.26), "beard": "short", "hair": Color(0.12, 0.09, 0.07),
				"outline": Color(0.20, 0.12, 0.24), "scroll": Messenger.SCROLL })
	return foe

# ── Layout ─────────────────────────────────────────────────

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UiStyle.PARCHMENT
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 140)
	margin.add_theme_constant_override("margin_top", 110)
	margin.add_theme_constant_override("margin_bottom", 64)
	add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	# Left: who's who, in two groups
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	left.custom_minimum_size.x = 340
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(left)
	left.add_child(_label(&"Eyebrow", 15, UiStyle.TERRACOTTA, false, "Friends and Foes"))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 0)
	left.add_child(_list)
	var group := ""
	for i in ENTRIES.size():
		var e: Dictionary = ENTRIES[i]
		if e["group"] != group:
			group = e["group"]
			var head := _label(&"Eyebrow", 13, UiStyle.INK_MUTED, false, GROUPS[group])
			head.custom_minimum_size.y = 44
			head.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			_list.add_child(head)
		var b := Button.new()
		b.theme_type_variation = &"GhostButton"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.focus_entered.connect(_select.bind(i))
		b.mouse_entered.connect(b.grab_focus)
		_list.add_child(b)
		_buttons.append(b)
	left.add_child(_gap(24))
	_back_btn = Button.new()
	_back_btn.theme_type_variation = &"GhostButton"
	_back_btn.text = "Back"
	_back_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_back_btn.pressed.connect(close)
	_back_btn.mouse_entered.connect(_back_btn.grab_focus)
	left.add_child(_back_btn)

	# Centre: the figure, turning
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(VIEW_PX) * 0.85
	stage.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.draw.connect(func():
		# A worn patch of ground for them to stand on
		var c := Vector2(stage.size.x * 0.5, stage.size.y * 0.86)
		stage.draw_set_transform(c, 0, Vector2(1, 0.28))
		stage.draw_circle(Vector2.ZERO, stage.size.x * 0.3, Color(UiStyle.AMBER, 0.18))
		stage.draw_circle(Vector2.ZERO, stage.size.x * 0.2, Color(UiStyle.INK, 0.08))
		stage.draw_set_transform(Vector2.ZERO))
	row.add_child(stage)
	_view_box = SubViewportContainer.new()
	_view_box.stretch = true
	_view_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(_view_box)
	var sh := Shader.new()
	sh.code = SILHOUETTE
	_shadow_mat = ShaderMaterial.new()
	_shadow_mat.shader = sh
	_shadow_mat.set_shader_parameter("ink", Color(UiStyle.INK, 0.85))
	_build_world()

	# Right: who they are
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right)
	_eyebrow = _label(&"Eyebrow", 14, UiStyle.INK_SOFT, false)
	right.add_child(_eyebrow)
	_title = _label(&"Heading", 52, UiStyle.INK, false)
	_title.add_theme_font_override("font", UiStyle.tracked(UiStyle.CINZEL_BOLD, 5))
	right.add_child(_title)
	_ref = _label(&"Eyebrow", 14, UiStyle.TERRACOTTA, false)
	right.add_child(_ref)
	var rule := ColorRect.new()
	rule.color = UiStyle.AMBER
	rule.custom_minimum_size = Vector2(72, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	right.add_child(rule)
	_text = _label(&"Body", 23, UiStyle.INK)
	_text.add_theme_constant_override("line_spacing", 6)
	right.add_child(_text)
	right.add_child(_gap(10))
	_stats = GridContainer.new()
	_stats.columns = 2
	_stats.add_theme_constant_override("h_separation", 20)
	_stats.add_theme_constant_override("v_separation", 8)
	right.add_child(_stats)

	var hint := _label(&"Eyebrow", 13, UiStyle.INK_MUTED, false, "↑ ↓   Choose          Esc   Back")
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.position += Vector2(140, -64)
	add_child(hint)

func _build_world() -> void:
	var vp := SubViewport.new()
	vp.size = VIEW_PX
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_view_box.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 0.6, 0)
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 1.5
	world.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.95, 0.85, 0.72)
	env.environment.ambient_light_energy = 0.55
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.add_child(env)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 5.0
	# A little above eye level, as the game's camera sees them
	var eye := Vector3(0, 2.6, 5.0)
	cam.transform = Transform3D.IDENTITY.looking_at(Vector3(0, 1.7, 0) - eye).translated(eye)
	world.add_child(cam)
	_holder = Node3D.new()
	world.add_child(_holder)
	_rig = CharacterRig.new()
	_holder.add_child(_rig)
	_rig.setup(_look(ENTRIES[0]))
	_rig.set_ring_color(Color(0, 0, 0, 0))

func _label(variation: StringName, font_size: int, color: Color, wrap := true, text := "") -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
