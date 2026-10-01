class_name FriendsAndFoes
extends Control

# Main menu → "Friends and Foes": the whole cast of the rebuilding. The crew and those
# against the work stand in a lineup of portrait medallions along the foot of the page;
# the one picked stands large in an arched plate — before the finished wall at dawn if
# a friend, outside the broken wall at dusk if a foe — with a verse in their own words.
# Foes stay ink silhouettes against the night until this player has met them
# (GameState.has_met): enemies on sight, the leaders in their story beat.

signal closed

# key, group, name, role (eyebrow), quote (World English Bible, verbatim), ref, text.
# Optional: "slot" (crew trade, CharacterRig.worker_look), "enemy" (enemy_look kind),
# "move" (a signature animation played when picked).
# Three groups: the crew; the named men behind the opposition (and their envoy), set
# apart so they don't read as bosses; then the attackers at the wall. Within each, in
# the order they turn up (GameState.MET_AT), so the lineup fills in left to right.
const ENTRIES := [
	{ "key": "nehemiah", "group": "friends", "name": "Nehemiah",
	  "role": "Governor of Judah · Cupbearer to the king",
	  "quote": "“I am doing a great work, so that I can’t come down.”", "ref": "Neh. 6:3",
	  "text": "He asks King Artaxerxes to send him to rebuild the city of his forefathers, inspects the broken walls by night, and works beside the people. When his enemies call him away, he stays at the work." },
	{ "key": "builder", "group": "friends", "name": "Builder", "slot": 0, "move": "build",
	  "role": "The crew · A trade to choose",
	  "quote": "“Among the builders, everyone wore his sword at his side, and so built.”", "ref": "Neh. 4:18",
	  "text": "Sets the stones and raises the wall course by course, a basket of stones on the back and a hammer at the belt." },
	{ "key": "water_carrier", "group": "friends", "name": "Water carrier", "slot": 1, "move": "cheer",
	  "role": "The crew · A trade to choose",
	  "quote": "“Everyone with one of his hands did the work, and with the other held his weapon.”", "ref": "Neh. 4:17",
	  "text": "Water for the mortar, stone and timber for the wall: the burden-bearers keep the builders supplied." },
	{ "key": "carpenter", "group": "friends", "name": "Carpenter", "slot": 2, "move": "build",
	  "role": "The crew · A trade to choose",
	  "quote": "“They laid its beams, and set up its doors, its bolts, and its bars.”", "ref": "Neh. 3:3",
	  "text": "Lays the beams and hangs the doors of each gate. The long timbers take two to carry." },
	{ "key": "overseer", "group": "friends", "name": "Overseer", "slot": 3, "move": "cheer",
	  "role": "The crew · A trade to choose",
	  "quote": "“Wherever you hear the sound of the trumpet, rally there to us.”", "ref": "Neh. 4:20",
	  "text": "The work is great and the wall is long, and the builders are spread thin along it. The overseer stands behind them with sword and sling, and where the horn sounds, the crew gathers." },
	{ "key": "sanballat", "group": "leaders", "name": "Sanballat",
	  "role": "The Horonite · Samaria",
	  "quote": "“Will they revive the stones out of the heaps of rubbish, since they are burned?”", "ref": "Neh. 4:2",
	  "text": "Furious that anyone has come to seek the good of the people. He mocks the builders before the army of Samaria, then plots to attack the city." },
	{ "key": "tobiah", "group": "leaders", "name": "Tobiah",
	  "role": "The Ammonite · Ammon",
	  "quote": "“What they are building, if a fox climbed up it, he would break down their stone wall.”", "ref": "Neh. 4:3",
	  "text": "Sanballat’s companion, an official from Ammon. When jokes fail, he sends letters to make Nehemiah afraid." },
	{ "key": "geshem", "group": "leaders", "name": "Geshem",
	  "role": "The Arab · Arabia",
	  "quote": "“What is this thing that you are doing? Will you rebel against the king?”", "ref": "Neh. 2:19",
	  "text": "He laughs at the work from the start, joins the plot against the city, and with Sanballat invites Nehemiah down to the plain of Ono." },
	{ "key": "messenger", "group": "leaders", "name": "Messenger",
	  "role": "Sent by Sanballat and Geshem",
	  "quote": "“Come! Let’s meet together in the villages in the plain of Ono.”", "ref": "Neh. 6:2",
	  "text": "He walks up to a worker with an open letter and waits. Go with him and you are led away from the wall. Keep working and he gives up." },
	{ "key": "scout", "group": "foes", "name": "Scout", "enemy": "scout", "move": "thrust",
	  "role": "From the first day",
	  "quote": "“They will not know or see, until we come in among them.”", "ref": "Neh. 4:11",
	  "text": "Light and quick. Some slip through the gaps for the inner city, others turn on the wall. A few sling stones bring one down." },
	{ "key": "brute", "group": "foes", "name": "Brute", "enemy": "brute", "move": "thrust",
	  "role": "From day 9",
	  "quote": "“They all conspired together to come and fight against Jerusalem.”", "ref": "Neh. 4:8",
	  "text": "Helmet, shield and spear. Slow, but he hits hard, takes many stones, and always goes for the wall." },
	{ "key": "saboteur", "group": "foes", "name": "Saboteur", "enemy": "saboteur", "move": "thrust",
	  "role": "From day 6",
	  "quote": "“They will not know or see, until we come in the middle of them… and cause the work to cease.”", "ref": "Neh. 4:11",
	  "text": "Hooded, an empty sack on his back, no weapon. He slips over the wall for the yard and strews the pile the work needs. Two cuts bring him down; a strewn pile must be tidied before it gives anything." },
	{ "key": "raider", "group": "foes", "name": "Raider", "enemy": "raider", "move": "slash",
	  "role": "From day 21",
	  "quote": "“…and cause the work to cease.”", "ref": "Neh. 4:11",
	  "text": "Hooded and cloaked, with a dagger, and the fastest of them all. Raiders reach a gap before you do." },
]
const GROUPS := { "friends": "The builders", "leaders": "Those against the work", "foes": "The attackers" }

const OXBLOOD    := Color(0.42, 0.12, 0.09)
const SWAY       := 0.22      # rad either side of the 3/4 view
const SWAY_SPEED := 0.55
const DRAG_TURN  := 0.012     # rad per pixel dragged
const MOVE_HOLD  := 1.3       # seconds a looping signature move plays
const MEDAL      := 92.0
const SUN_X      := 0.84      # of the plate's width: off to the side, clear of the head
# The backdrop runs this far past each side of the plate, so its wall reads chunkier
const BACKDROP_BLEED := 0.125
const TEXT_W     := 860.0     # measure of the text column, so lines stay readable
# Not met yet: the figure as one flat shape of ink, no detail showing through — but
# edged in moonlight on the plate, so it still reads against the night
const SILHOUETTE := """
shader_type canvas_item;
uniform vec4 ink : source_color;
uniform vec4 rim : source_color = vec4(0.0);
uniform float rim_px = 2.5;
// A material here opts out of the parent's clip_children, so the medals mask their own disc
uniform bool disc = false;
void fragment() {
	float a = texture(TEXTURE, UV).a;
	if (disc) {
		a *= 1.0 - smoothstep(0.5 - fwidth(UV.x), 0.5, distance(UV, vec2(0.5)));
	}
	vec2 d = TEXTURE_PIXEL_SIZE * rim_px;
	float inner = min(min(texture(TEXTURE, UV + vec2(d.x, 0.0)).a, texture(TEXTURE, UV - vec2(d.x, 0.0)).a),
		min(texture(TEXTURE, UV + vec2(0.0, d.y)).a, texture(TEXTURE, UV - vec2(0.0, d.y)).a));
	float edge = clamp(a - inner, 0.0, 1.0) * rim.a;
	COLOR = vec4(mix(ink.rgb, rim.rgb, edge), a * ink.a);
}
"""

var _selected := -1
var _time := 0.0
var _drag := 0.0
var _dragging := false
var _silhouette: ShaderMaterial
var _silhouette_rim: ShaderMaterial

var _plate: Control
var _scene: Control          # backdrop + figure, clipped to the arch
var _backdrop: StoryBackdrop
var _floor: Control
var _view_box: SubViewportContainer
var _holder: Node3D
var _rig: CharacterRig
var _medals: Array[Control] = []
var _medal_vps: Array[SubViewport] = []
var _count: Label
var _count_bar: Control
var _eyebrow: Label
var _title: Label
var _tag: Label
var _ref: Label
var _quote: Label
var _text: Label
var _extra: VBoxContainer
var _back_btn: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sh := Shader.new()
	sh.code = SILHOUETTE
	_silhouette = ShaderMaterial.new()
	_silhouette.shader = sh
	_silhouette.set_shader_parameter("ink", Color(0.06, 0.04, 0.03, 0.92))
	_silhouette_rim = _silhouette.duplicate()
	_silhouette.set_shader_parameter("disc", true)
	_silhouette_rim.set_shader_parameter("ink", Color(0.03, 0.03, 0.05, 1.0))
	_silhouette_rim.set_shader_parameter("rim", Color(0.80, 0.82, 0.90, 0.75))
	_build()
	hide()

func open() -> void:
	var met := 0
	for i in ENTRIES.size():
		var known := _known(ENTRIES[i])
		met += int(known)
		var m := _medals[i]
		(m.get_meta("box") as Control).material = null if known else _silhouette
		(m.get_meta("name") as Label).text = tr(ENTRIES[i]["name"]) if known else "?"
		_medal_vps[i].render_target_update_mode = SubViewport.UPDATE_ONCE
	_count.text = tr("Met %d of %d") % [met, ENTRIES.size()]
	_count_bar.set_meta("share", float(met) / ENTRIES.size())
	_count_bar.queue_redraw()
	show()
	UiFx.fade_in(self, 0.35)
	UiFx.stagger(_medals, 0.4, 0.035, 0.15)
	_selected = -1
	_medals[0].grab_focus()

func close() -> void:
	hide()
	closed.emit()

static func _known(e: Dictionary) -> bool:
	return e["group"] == "friends" or GameState.has_met(e["key"])

# ── Input ──────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed and _plate.get_global_rect().has_point(event.position)
	elif event is InputEventMouseMotion and _dragging:
		_drag += event.relative.x * DRAG_TURN

func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	# Three-quarter view toward the text, breathing a little either side; a drag turns
	# it, and it eases back when let go
	if not _dragging:
		_drag = lerpf(_drag, 0.0, minf(1.0, delta * 1.2))
	_holder.rotation.y = -0.35 + SWAY * sin(_time * SWAY_SPEED) + _drag

# ── Selection ──────────────────────────────────────────────

func _select(i: int) -> void:
	if i == _selected:
		return
	var first := _selected < 0
	_selected = i
	for m in _medals:
		m.queue_redraw()
	var e: Dictionary = ENTRIES[i]
	var known := _known(e)
	var foe: bool = e["group"] != "friends"

	# The plate: dawn before the finished wall, dusk outside a broken one, night unmet
	_backdrop.sky = "night" if not known else ("dusk" if foe else "dawn")
	_backdrop.built = 1.0 if not foe else (0.3 if known else 0.0)
	_backdrop.pattern = hash(e["key"])
	# The sun clear of the figure's head; an unmet one stands under the moon
	_backdrop.sun_at = ((SUN_X if known else 0.5) + BACKDROP_BLEED) / (1.0 + 2.0 * BACKDROP_BLEED)
	_rig.set_look(_look(e))
	_holder.scale = Vector3.ONE * (Enemy.SCALE[_enemy_type(e)] if e.has("enemy") else 1.0)
	_view_box.material = null if known else _silhouette_rim
	_floor.queue_redraw()
	_rig.play("idle_down")
	_rig.squash(Vector2(0.92, 1.08))
	if known and e.has("move"):
		_signature(e["move"], i)
	if not first:
		UiFx.fade_in(_scene, 0.35)

	var where: String = tr("First met at the %s") % tr(GameState.SECTIONS[GameState.MET_AT[e["key"]]]["name"]) \
		if GameState.MET_AT.has(e["key"]) else ""
	_eyebrow.text = tr(e["role"]) if known else where
	_title.text = tr(e["name"]) if known else tr("Not yet met")
	_tag.text = tr({ "friends": "Friend", "leaders": "Adversary", "foes": "Foe" }[e["group"]])
	_tag.add_theme_stylebox_override("normal", UiStyle.box(OXBLOOD if foe else UiStyle.OLIVE, Vector2(10, 3), 3))
	_tag.visible = known
	_ref.text = GameState.long_ref(e["ref"])
	_ref.visible = known
	_quote.text = tr(e["quote"]) if known else ""
	_quote.get_parent().visible = known
	_text.text = tr(e["text"]) if known else tr("Keep building. You will meet them on the wall.")
	_fill_extra(e, known, where)
	UiFx.stagger([_eyebrow, _title, _quote.get_parent(), _text, _extra], 0.35, 0.05)
	if not first:
		Sfx.play("tally")

# A one-off move when picked: the crew at work or cheering, the enemy striking
func _signature(move: String, i: int) -> void:
	await get_tree().create_timer(0.25).timeout
	if _selected != i or not visible:
		return
	_rig.play(move + "_down")
	if CharAnim.ANIM_CFG[move].get("loop", false):
		await get_tree().create_timer(MOVE_HOLD).timeout
	else:
		await _rig.animation_finished
	if _selected == i:
		_rig.play("idle_down")

# Under the text: the dye a trade wears, a foe's measure, and where each foe shows
func _fill_extra(e: Dictionary, known: bool, where: String) -> void:
	for c in _extra.get_children():
		c.queue_free()
	if not known:
		return
	# A trade's knack (Trade): what it does faster than the rest of the crew
	if e.has("slot") and GameState.trades:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var knack := _label(&"Eyebrow", 13, UiStyle.CREAM, false, "Knack")
		knack.add_theme_stylebox_override("normal", UiStyle.box(UiStyle.OLIVE, Vector2(10, 3), 3))
		knack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(knack)
		row.add_child(_label(&"Body", 17, UiStyle.INK, false, Trade.ABOUT[e["slot"]]))
		_extra.add_child(row)
		_extra.add_child(_label(&"Eyebrow", 13, UiStyle.INK_MUTED, false,
			"Anyone can do any job — pick your trade when the crew gathers"))
	if e.has("enemy"):
		var t := _enemy_type(e)
		# Against the fastest, toughest, hardest-hitting of the three
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 24)
		grid.add_theme_constant_override("v_separation", 10)
		grid.add_child(_label(&"Eyebrow", 13, UiStyle.INK_SOFT, false, "Speed"))
		grid.add_child(_meter(Enemy.SPEED[t] / Enemy.SPEED[Enemy.Type.RAIDER]))
		grid.add_child(_label(&"Eyebrow", 13, UiStyle.INK_SOFT, false, "Toughness"))
		grid.add_child(_meter(Enemy.HEALTH[t] / Enemy.HEALTH[Enemy.Type.BRUTE]))
		grid.add_child(_label(&"Eyebrow", 13, UiStyle.INK_SOFT, false, "Strength"))
		grid.add_child(_meter(Enemy.DAMAGE[t] / Enemy.DAMAGE[Enemy.Type.BRUTE]))
		_extra.add_child(grid)
	if not where.is_empty():
		var l := _label(&"Eyebrow", 13, UiStyle.INK_MUTED, false, where)
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # already translated
		_extra.add_child(l)

func _meter(share: float) -> Control:
	var m := Control.new()
	m.custom_minimum_size = Vector2(5 * 34, 12)
	m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var filled := clampi(roundi(share * 5.0), 1, 5)
	m.draw.connect(func():
		for k in 5:
			var sb := UiStyle.box(OXBLOOD if k < filled else Color(UiStyle.INK, 0.1), Vector2.ZERO, 3)
			m.draw_style_box(sb, Rect2(k * 34, 1, 28, 10)))
	return m

static func _enemy_type(e: Dictionary) -> Enemy.Type:
	return { "scout": Enemy.Type.SCOUT, "brute": Enemy.Type.BRUTE, "raider": Enemy.Type.RAIDER, "saboteur": Enemy.Type.SABOTEUR }[e["enemy"]]

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
	margin.add_theme_constant_override("margin_top", 56)
	margin.add_theme_constant_override("margin_bottom", 36)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 22)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(page)

	page.add_child(_build_header())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 80)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(body)
	body.add_child(_build_plate())
	body.add_child(_build_info())
	page.add_child(_build_lineup())
	_wire_focus()

	var hint := _label(&"Eyebrow", 12, UiStyle.INK_MUTED, false, "← →   Choose          Drag   Turn          Esc   Back")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(hint)

func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := _label(&"Heading", 34, UiStyle.INK, false, "Friends and Foes")
	head.add_theme_font_override("font", UiStyle.tracked(UiStyle.CINZEL_BOLD, 4))
	row.add_child(head)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	var tally := VBoxContainer.new()
	tally.add_theme_constant_override("separation", 6)
	tally.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tally.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tally)
	_count = _label(&"Eyebrow", 13, UiStyle.INK_SOFT, false)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # set translated
	tally.add_child(_count)
	_count_bar = Control.new()
	_count_bar.custom_minimum_size = Vector2(180, 4)
	_count_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count_bar.draw.connect(func():
		var w := _count_bar.size.x
		_count_bar.draw_rect(Rect2(0, 0, w, 4), UiStyle.PARCHMENT_DEEP)
		_count_bar.draw_rect(Rect2(0, 0, w * float(_count_bar.get_meta("share", 0.0)), 4), UiStyle.AMBER))
	tally.add_child(_count_bar)
	_back_btn = Button.new()
	_back_btn.theme_type_variation = &"GhostButton"
	_back_btn.text = "Back"
	_back_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_back_btn.pressed.connect(close)
	_back_btn.mouse_entered.connect(_back_btn.grab_focus)
	row.add_child(_back_btn)
	return row

## Arched window: sky, hills and the wall behind, the figure in front. The arch is
## drawn once as the clip mask and again on top as the frame.
func _build_plate() -> Control:
	_plate = Control.new()
	_plate.custom_minimum_size = Vector2(540, 0)
	_plate.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_plate.mouse_filter = Control.MOUSE_FILTER_PASS
	_plate.mouse_default_cursor_shape = Control.CURSOR_DRAG

	_scene = Control.new()
	_scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_scene.draw.connect(func(): _scene.draw_colored_polygon(_arch(_scene.size, 0.0), UiStyle.DUSK))
	_plate.add_child(_scene)
	_backdrop = StoryBackdrop.new()
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene.add_child(_backdrop)
	_scene.resized.connect(func():
		var bleed := _scene.size.x * BACKDROP_BLEED
		_backdrop.position = Vector2(-bleed, 0)
		_backdrop.size = _scene.size + Vector2(2.0 * bleed, 0))
	# The ground in front of the wall, lit from the sky, and a soft pool of light where
	# the figure stands — warm by day, cold under the moon
	var pool_tex := GradientTexture2D.new()
	pool_tex.fill = GradientTexture2D.FILL_RADIAL
	pool_tex.fill_from = Vector2(0.5, 0.5)
	pool_tex.fill_to = Vector2(1.0, 0.5)
	pool_tex.gradient = Gradient.new()
	pool_tex.gradient.set_color(0, Color(1, 1, 1, 0.42))
	pool_tex.gradient.set_color(1, Color(1, 1, 1, 0))
	pool_tex.gradient.add_point(0.55, Color(1, 1, 1, 0.16))
	_floor = Control.new()
	_floor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_floor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_floor.draw.connect(func():
		var s := _floor.size
		var night := _backdrop.sky == "night"
		var glow: Color = StoryBackdrop.SKIES[_backdrop.sky][1]
		var y := s.y * StoryBackdrop.WALL_BASE + 1.0
		var near := glow.lerp(Color.BLACK, 0.66)
		var far := glow.lerp(Color.BLACK, 0.9)
		_floor.draw_polygon(PackedVector2Array([Vector2(0, y), Vector2(s.x, y), Vector2(s.x, s.y), Vector2(0, s.y)]),
			PackedColorArray([near, near, far, far]))
		_floor.draw_line(Vector2(0, y), Vector2(s.x, y), Color(glow, 0.25), 1.5)
		var r := s.x * 0.46
		_floor.draw_set_transform(Vector2(s.x * 0.5, s.y * 0.9), 0, Vector2(1, 0.24))
		_floor.draw_texture_rect(pool_tex, Rect2(-r, -r, 2 * r, 2 * r), false,
			Color(0.72, 0.80, 1.0) if night else Color(1.0, 0.80, 0.52))
		_floor.draw_set_transform(Vector2.ZERO))
	_scene.add_child(_floor)
	_view_box = SubViewportContainer.new()
	_view_box.stretch = true
	_view_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scene.add_child(_view_box)
	_build_world()

	var frame := Control.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.draw.connect(func():
		var outer := _arch(frame.size, 1.5)
		outer.append(outer[0])
		frame.draw_polyline(outer, UiStyle.INK, 3.0, true)
		var inner := _arch(frame.size, 10.0)
		inner.append(inner[0])
		frame.draw_polyline(inner, Color(UiStyle.GOLD, 0.85), 1.5, true))
	_plate.add_child(frame)
	for n: Control in [_scene, frame, _floor]:
		_plate.resized.connect(n.queue_redraw)
	return _plate

## Round-topped arch filling `s`, inset by `inset` pixels
static func _arch(s: Vector2, inset: float) -> PackedVector2Array:
	var r := s.x * 0.5 - inset
	var c := Vector2(s.x * 0.5, r + inset)
	var pts := PackedVector2Array([Vector2(inset, s.y - inset), Vector2(inset, c.y)])
	for k in range(1, 48):
		var a := PI + PI * k / 48.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	pts.append(Vector2(s.x - inset, c.y))
	pts.append(Vector2(s.x - inset, s.y - inset))
	return pts

func _build_world() -> void:
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_view_box.add_child(vp)
	var world := _stage_world(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 5.1
	# A touch above eye level; the figure stands low in the arch, feet in the light
	var eye := Vector3(0, 2.4, 6.0)
	cam.transform = Transform3D.IDENTITY.looking_at(Vector3(0, 1.75, 0) - eye).translated(eye)
	world.add_child(cam)
	_holder = Node3D.new()
	world.add_child(_holder)
	_rig = CharacterRig.new()
	_holder.add_child(_rig)
	_rig.setup(_look(ENTRIES[0]))
	_rig.set_ring_color(Color(0, 0, 0, 0))

## Sun, warm fill and filmic tone, as the portraits in the HUD
static func _stage_world(vp: SubViewport) -> Node3D:
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
	return world

func _build_info() -> Control:
	# Hung from a fixed line level with the shoulder of the arch, so the name stays put
	# from one entry to the next however long the text runs
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 12)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_BEGIN
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(_gap(120))
	_eyebrow = _label(&"Eyebrow", 14, UiStyle.TERRACOTTA, false)
	_eyebrow.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # set translated
	info.add_child(_eyebrow)
	_title = _label(&"Heading", 68, UiStyle.INK, false)
	_title.add_theme_font_override("font", UiStyle.tracked(UiStyle.CINZEL_BOLD, 6))
	info.add_child(_title)
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 14)
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(meta)
	_tag = _label(&"Eyebrow", 12, UiStyle.CREAM, false)
	_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meta.add_child(_tag)
	_ref = _label(&"Eyebrow", 14, UiStyle.INK_SOFT, false)
	_ref.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meta.add_child(_ref)
	info.add_child(_gap(8))
	# The verse, in their own words: set large, hung on a gold rule
	var quote_row := HBoxContainer.new()
	quote_row.add_theme_constant_override("separation", 22)
	quote_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(quote_row)
	var rule := ColorRect.new()
	rule.color = UiStyle.GOLD
	rule.custom_minimum_size = Vector2(3, 0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quote_row.add_child(rule)
	_quote = _label(&"Verse", 32, UiStyle.INK)
	_quote.add_theme_constant_override("line_spacing", 4)
	_quote.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quote_row.add_child(_quote)
	info.add_child(_gap(8))
	_text = _label(&"Body", 22, UiStyle.INK_SOFT)
	_text.add_theme_constant_override("line_spacing", 5)
	_text.custom_minimum_size.x = TEXT_W
	_text.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	info.add_child(_text)
	info.add_child(_gap(6))
	_extra = VBoxContainer.new()
	_extra.add_theme_constant_override("separation", 12)
	_extra.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(_extra)
	return info

## The cast along the foot of the page: a portrait medallion each, crew then foes
func _build_lineup() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var group := ""
	var box: HBoxContainer = null
	for i in ENTRIES.size():
		var e: Dictionary = ENTRIES[i]
		if e["group"] != group:
			group = e["group"]
			if box != null:
				var div := ColorRect.new()
				div.color = UiStyle.RULE
				div.custom_minimum_size = Vector2(1, MEDAL)
				div.size_flags_vertical = Control.SIZE_SHRINK_END
				div.mouse_filter = Control.MOUSE_FILTER_IGNORE
				row.add_child(_gap_x(28))
				row.add_child(div)
				row.add_child(_gap_x(28))
			var col := VBoxContainer.new()
			col.add_theme_constant_override("separation", 18)   # room for the picked one to rise
			col.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(col)
			# Group title with a hairline run out across the group
			var head := HBoxContainer.new()
			head.add_theme_constant_override("separation", 14)
			head.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.add_child(head)
			head.add_child(_label(&"Eyebrow", 13, UiStyle.INK_SOFT, false, GROUPS[group]))
			var hair := ColorRect.new()
			hair.color = UiStyle.RULE
			hair.custom_minimum_size = Vector2(0, 1)
			hair.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hair.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			hair.mouse_filter = Control.MOUSE_FILTER_IGNORE
			head.add_child(hair)
			box = HBoxContainer.new()
			box.add_theme_constant_override("separation", 16)   # room for longer names (Wasserträger)
			box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.add_child(box)
		box.add_child(_medal(i))
	return row

# Walk the lineup with left/right (wrapping); up goes to Back. Paths need the tree.
func _wire_focus() -> void:
	var n := _medals.size()
	for i in n:
		_medals[i].focus_neighbor_left = _medals[i].get_path_to(_medals[(i - 1 + n) % n])
		_medals[i].focus_neighbor_right = _medals[i].get_path_to(_medals[(i + 1) % n])
		_medals[i].focus_neighbor_top = _medals[i].get_path_to(_back_btn)
	_back_btn.focus_neighbor_bottom = _back_btn.get_path_to(_medals[0])

## A head-and-shoulders portrait in a tinted disc: olive for the crew, oxblood for foes
func _medal(i: int) -> Control:
	var e: Dictionary = ENTRIES[i]
	var foe: bool = e["group"] != "friends"
	var m := VBoxContainer.new()
	m.add_theme_constant_override("separation", 6)
	m.focus_mode = Control.FOCUS_ALL
	m.mouse_filter = Control.MOUSE_FILTER_STOP
	m.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	m.focus_entered.connect(_select.bind(i))
	m.mouse_entered.connect(m.grab_focus)
	var disc := Control.new()
	disc.custom_minimum_size = Vector2(MEDAL, MEDAL)
	disc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.pivot_offset = Vector2(MEDAL * 0.5, MEDAL)   # grows upward, clear of its name
	disc.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	disc.draw.connect(func():
		var c := disc.size * 0.5
		var tint: Color = OXBLOOD if foe else UiStyle.OLIVE
		disc.draw_circle(c, MEDAL * 0.5, tint.lerp(UiStyle.PARCHMENT, 0.72))
		# Kept inside the disc: whatever the disc draws is also its clip mask
		disc.draw_circle(c + Vector2(0, MEDAL * 0.16), MEDAL * 0.34, tint.lerp(UiStyle.PARCHMENT, 0.58)))
	m.add_child(disc)
	var box := SubViewportContainer.new()
	box.stretch = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	disc.add_child(box)
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	# Still portraits: rendered when the page opens, not every frame
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	box.add_child(vp)
	var world := _stage_world(vp)
	var s: float = Enemy.SCALE[_enemy_type(e)] if e.has("enemy") else 1.0
	var head := Vector3(0, 1.62 * s, 0)
	var eye := head + Vector3(2.3, 1.2, 2.0)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.7 * s
	cam.transform = Transform3D.IDENTITY.looking_at(head - eye).translated(eye)
	world.add_child(cam)
	var holder := Node3D.new()
	holder.scale = Vector3.ONE * s
	world.add_child(holder)
	var rig := CharacterRig.new()
	holder.add_child(rig)
	rig.setup(_look(e))
	rig.set_ring_color(Color(0, 0, 0, 0))
	rig.play("idle_down")
	# Rim over the portrait: gold on the one picked
	var ring := Control.new()
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.draw.connect(func():
		var here := i == _selected
		ring.draw_arc(ring.size * 0.5, MEDAL * 0.5 - (2.5 if here else 1.0), 0, TAU, 64,
			UiStyle.GOLD if here else Color(UiStyle.INK, 0.3), 5.0 if here else 1.5, true))
	disc.add_child(ring)
	var name_l := _label(&"Eyebrow", 12, UiStyle.INK_SOFT, false)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.custom_minimum_size.x = MEDAL + 4
	name_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # set translated
	m.add_child(name_l)
	m.set_meta("box", box)
	m.set_meta("name", name_l)
	# The one picked stands a little forward: larger, gold rim, its name in terracotta
	m.draw.connect(func():
		var here := i == _selected
		var known := name_l.text != "?"
		name_l.add_theme_color_override("font_color",
			UiStyle.TERRACOTTA if here else (UiStyle.INK_SOFT if known else UiStyle.INK_MUTED))
		disc.scale = Vector2.ONE * (1.1 if here else 1.0)
		ring.queue_redraw())
	_medals.append(m)
	_medal_vps.append(vp)
	return m

func _label(variation: StringName, font_size: int, color: Color, wrapped := true, text := "") -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if wrapped:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func _gap_x(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.x = w
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
