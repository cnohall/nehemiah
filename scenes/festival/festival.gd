class_name Festival
extends CanvasLayer

# "Walk the City": the Festival of Booths after the wall was finished (Neh. 8) — a
# sandbox with no clock and no enemy, for walking Jerusalem. Held at the Water Gate,
# where "all the people gathered themselves together as one man" (8:1). The whole wall
# stands; the yard's work piles are gone. What there is to do, all from the chapter:
#   - hear Ezra read the Law from his wooden platform (8:3-8)
#   - go out to the mount for branches and build booths — in the broad place, the
#     courtyards, the courts of God's house (8:15-16)
#   - send portions to those for whom nothing is prepared (8:10)
#   - meet the people of the city, and go up to the house of God
# A small journal ticks them off; nothing is timed and nothing is saved. Solo, offline
# (like the Tutorial): the game scene is its own server.

const BOOTHS := [
	[Vector3(-7.0, 0.1, 9.5), "in the broad place of the Water Gate"],
	[Vector3(-17.0, 0.1, 9.0), "in a courtyard"],
	[Vector3(14.0, 0.1, 6.0), "in a courtyard"],
	[Vector3(7.0, 0.1, 24.0), "by the well"],
	[Vector3(40.6, 0.1, 11.3), "in the courts of God's house"],
]
# Cut boughs waiting on the slopes outside the wall (8:15 "go out to the mountain")
const BRANCH_PILES := [Vector3(-9.0, 0.1, -10.5), Vector3(3.0, 0.1, -10.0), Vector3(15.0, 0.1, -12.0)]
const PORTION_TABLE := Vector3(8.0, 0.1, 8.5)
const PLATFORM := Vector3(1.0, 0.1, 5.2)
const PLATFORM_SIZE := Vector3(3.2, 1.1, 2.0)
const VISIT_POLL := 0.3

var _main: Node
var _booths: Array[Booth] = []
var _hungry: Array[Folk] = []
var _named: Array[Folk] = []
var _heard := false
var _visited := false
var _done_shown := false
var _poll := 0.0
var _saved := {}

var _panel: PanelContainer
var _rows := {}   # task → [Tick, Label]
var _leave: Button

func _init(main: Node) -> void:
	_main = main
	layer = 12

func _ready() -> void:
	_saved = { "sun": GameState.sun, "posts": GameState.posts }
	GameState.sun = false
	GameState.posts = false
	# One frame in: the day director is set up, the player spawned
	await get_tree().process_frame
	_main.director.begin()
	_raise_the_wall()
	_clear_the_yard()
	_build_world()
	_build_journal()
	_refresh()

func _exit_tree() -> void:
	GameState.sun = _saved.get("sun", true)
	GameState.posts = _saved.get("posts", true)

func _process(delta: float) -> void:
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = VISIT_POLL
	var me := Player.local
	if not _visited and me != null and is_instance_valid(me) and Temple.in_court(me.global_position):
		_visited = true
		Sfx.play("tally_land")
		_main.hud._show_banner(tr("The house of God"),
			tr("“We will not forsake the house of our God.”  (%s)") % GameState.short_ref("Neh. 10:39"), 3.6)
		_refresh()

# ── Setting the scene ──────────────────────────────────────

# "So the wall was finished" (6:15): every piece of this stretch stands, doors hung
func _raise_the_wall() -> void:
	for unit: Array in _main.director._units:
		for part in unit:
			if "stage" in part:
				part.stage = 3
			elif "finished" in part:
				part.finished = true

# The builders' yard is packed away: its piles, heaps and trough
func _clear_the_yard() -> void:
	for parent in ["Supplies", "Rubble"]:
		for n: Node in _main.get_node(parent).get_children():
			n.process_mode = Node.PROCESS_MODE_DISABLED
			n.visible = false
			for g in ["supply_piles", "build_sites", "restockable"]:
				n.remove_from_group(g)
			var col := n.get_node_or_null("CollisionShape3D") as CollisionShape3D
			if col != null:
				col.set_deferred("disabled", true)

func _build_world() -> void:
	var root := Node3D.new()
	root.name = "Festival"
	_main.add_child(root)
	root.add_child(Temple.new())
	_build_platform(root)
	for i in BOOTHS.size():
		var b := Booth.new()
		b.name = "Booth%d" % i
		b.place = BOOTHS[i][1]
		b.position = BOOTHS[i][0]
		b.raised.connect(_on_booth)
		root.add_child(b)
		_booths.append(b)
	var pile_scene := load("res://scenes/supply_pile/supply_pile.tscn") as PackedScene
	for at: Vector3 in BRANCH_PILES:
		root.add_child(_pile(pile_scene, "branch", at))
	root.add_child(_pile(pile_scene, "portion", PORTION_TABLE))
	_add_people(root)

func _pile(scene: PackedScene, kind: String, at: Vector3) -> Node3D:
	var p := scene.instantiate()
	p.kind = kind
	p.position = at
	p.ready.connect(func(): p.count_label.clamp_to_screen = false)
	return p

# Ezra's platform of wood (8:4), facing the broad place
func _build_platform(root: Node3D) -> void:
	var body := StaticBody3D.new()
	body.position = PLATFORM
	root.add_child(body)
	var parts := WatchPost._Parts.new()
	var s := PLATFORM_SIZE
	parts.add(Vector3(s.x, 0.14, s.z), Vector3(0, s.y, 0), Color(0.60, 0.44, 0.26))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			parts.add(Vector3(0.18, s.y, 0.18), Vector3(sx * (s.x * 0.5 - 0.15), s.y * 0.5, sz * (s.z * 0.5 - 0.15)), Color(0.46, 0.32, 0.18))
	parts.add(Vector3(s.x, 0.5, 0.08), Vector3(0, s.y + 0.3, s.z * 0.5 - 0.05), Color(0.55, 0.40, 0.24))   # front rail
	parts.add(Vector3(0.6, 0.9, 0.5), Vector3(0, s.y + 0.5, s.z * 0.5 - 0.35), Color(0.52, 0.38, 0.22))    # the lectern
	body.add_child(parts.build(Chunky.wood_material(0.03)))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(s.x, s.y + 0.4, s.z)
	shape.shape = box
	shape.position = Vector3(0, (s.y + 0.4) * 0.5, 0)
	body.add_child(shape)

# ── The people ─────────────────────────────────────────────

func _add_people(root: Node3D) -> void:
	var top := PLATFORM + Vector3(0, PLATFORM_SIZE.y + 0.07, 0)
	var ezra := _folk(root, "Ezra the scribe", "scribe", Palette.MUREX, top + Vector3(0, 0, 0.2), [
		["You shall take on the first day the fruit of majestic trees, branches of palm trees, and boughs of thick trees, and willows of the brook; and you shall rejoice before Yahweh your God seven days.", "Lev. 23:40"],
		["You shall dwell in temporary shelters for seven days.", "Lev. 23:42"],
		["Go out to the mountain, and get olive branches, branches of wild olive, myrtle branches, palm branches, and branches of thick trees, to make temporary shelters, as it is written.", "Neh. 8:15"],
	])
	ezra.radius = 1.4
	ezra.spoken.connect(func(_f): _heard = true; _refresh())
	for sx: float in [-1.0, 1.0]:
		_folk(root, "", "priest", Palette.INDIGO, top + Vector3(sx * 1.1, 0, -0.35), []).radius = 1.4
	_folk(root, "Nehemiah the governor", "elder", Palette.SAFFRON, PLATFORM + Vector3(3.2, 0, 1.4), [
		["Today is holy to Yahweh your God. Don’t mourn, nor weep.", "Neh. 8:9"],
		["Go your way. Eat the fat, drink the sweet, and send portions to him for whom nothing is prepared.", "Neh. 8:10"],
		["Don’t be grieved, for the joy of Yahweh is your strength.", "Neh. 8:10"],
	])
	_folk(root, "A Levite", "priest", Palette.WELD, Vector3(-3.0, 0.1, 11.2), [
		["We read in the book distinctly, and give the sense, so that everyone understands.", "see Neh. 8:8"],
		["Hold your peace, for the day is holy. Don’t be grieved.", "Neh. 8:11"],
	])
	_folk(root, "Shallum's daughters", "woman", Palette.MADDER, Vector3(-19.8, 0.1, 10.8), [
		["Our father Shallum ruled half the district of Jerusalem — and we built the wall with him.", "see Neh. 3:12"],
		["Branches are out on the slopes past the gate. Bring two, and we'll put up a booth here.", ""],
	])
	_folk(root, "", "woman", Palette.SAFFRON, Vector3(-20.8, 0.1, 9.6), [
		["Mind the lattice — the roof should let the stars show through.", ""],
	])
	_folk(root, "Meremoth the priest", "priest", Palette.MUREX, Vector3(31.5, 0.1, 15.2), [
		["I repaired the wall from the door of Eliashib's house to its end.", "see Neh. 3:21"],
		["Go up into the court. They are building shelters there too.", "see Neh. 8:16"],
	])
	_folk(root, "A priest at the altar", "priest", Palette.INDIGO, Vector3(35.0, 0.1, 10.6), [
		["We will not forsake the house of our God.", "Neh. 10:39"],
		["Fire shall be kept burning on the altar continually; it shall not go out.", "Lev. 6:13"],
	])
	_folk(root, "The gatekeeper", "man", Palette.INDIGO, Vector3(-6.4, 0.1, 2.2), [
		["Out through the gate for branches — olive, myrtle, palm. Go to the mount.", "see Neh. 8:15"],
		["The gates stay open today. Nobody is coming to fight.", ""],
	])
	for i in 2:
		_folk(root, "", "child", Palette.DYES[i + 1], Vector3(-2.5 + i * 1.3, 0.1, 3.4 + i * 0.4), [
			["We're going out for palm branches!", ""],
		]).size_scale = 0.62
	# The crowd in the broad place, listening
	var rng := RandomNumberGenerator.new()
	rng.seed = 818
	for i in 14:
		var row := i / 5
		var at := PLATFORM + Vector3(-4.0 + (i % 5) * 2.0 + rng.randf_range(-0.4, 0.4), 0.0, 3.6 + row * 1.6 + rng.randf_range(-0.3, 0.3))
		var kind: String = ["man", "woman", "elder", "man", "woman", "child"][rng.randi() % 6]
		var f := _folk(root, "", kind, Palette.DYES[rng.randi() % Palette.DYES.size()], at,
			[["Amen, Amen!", "Neh. 8:6"]] if i % 2 == 0 else [["We've listened since early morning.", "see Neh. 8:3"]])
		f.facing = "up"
		if kind == "child":
			f.size_scale = 0.62
	# Those for whom nothing is prepared (8:10), along the streets
	var hungry := [
		[Vector3(-9.5, 0.1, 22.6), "elder", "A widow's house"],
		[Vector3(9.5, 0.1, 22.6), "elder", "An old man"],
		[Vector3(18.0, 0.1, 25.2), "woman", "A mother with nothing prepared"],
		[Vector3(-2.0, 0.1, 30.5), "man", "A stranger in the city"],
	]
	for h: Array in hungry:
		var f := Folk.new()
		f.who = ""
		f.hungry = true
		f.fed_line = ["Blessings on you — the joy of Yahweh is our strength today.", "see Neh. 8:10"]
		f.look = Folk.look_for(h[1], Palette.UNDYED.darkened(0.2), _named.size() + _hungry.size())
		f.position = h[0]
		f.fed.connect(func(_f): _refresh())
		root.add_child(f)
		_hungry.append(f)

func _folk(root: Node3D, who: String, kind: String, dye: Color, at: Vector3, lines: Array) -> Folk:
	var f := Folk.new()
	f.who = who
	f.lines = lines
	f.look = Folk.look_for(kind, dye, root.get_child_count())
	f.position = at
	root.add_child(f)
	if not who.is_empty():
		_named.append(f)
		f.spoken.connect(func(_f): _refresh())
	return f

func _on_booth() -> void:
	_refresh()

# ── Journal ────────────────────────────────────────────────

func _build_journal() -> void:
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiStyle.plaque(Vector2(20, 14), 0.93))
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 18)
	UiStyle.ornament(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	_panel.add_child(vb)
	var eyebrow := Label.new()
	eyebrow.theme_type_variation = &"Eyebrow"
	eyebrow.text = tr("Neh. 8  ·  The seventh month")
	eyebrow.add_theme_color_override("font_color", UiStyle.TERRACOTTA)
	vb.add_child(eyebrow)
	var title := Label.new()
	title.theme_type_variation = &"Heading"
	title.text = "The Festival of Booths"
	title.add_theme_color_override("font_color", UiStyle.INK)
	vb.add_child(title)
	var sub := Label.new()
	sub.theme_type_variation = &"Caption"
	sub.text = "The wall is finished. No clock, no enemy — walk the city."
	sub.add_theme_color_override("font_color", UiStyle.INK_SOFT)
	vb.add_child(sub)
	vb.add_child(HSeparator.new())
	for task: String in ["hear", "booths", "portions", "people", "temple"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var tick := Tick.new()
		tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tick)
		var l := Label.new()
		l.theme_type_variation = &"Body"
		l.add_theme_font_size_override("font_size", 16)
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # set translated
		row.add_child(l)
		vb.add_child(row)
		_rows[task] = [tick, l]
	var hint := Label.new()
	hint.theme_type_variation = &"Caption"
	hint.add_theme_color_override("font_color", UiStyle.INK_MUTED)
	hint.text = "Walk up to people and press %s to talk" % InputMode.key("interact")
	hint.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	vb.add_child(hint)
	_leave = Button.new()
	_leave.theme_type_variation = &"GhostButton"
	_leave.text = "Back to the title"
	_leave.focus_mode = Control.FOCUS_NONE
	_leave.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_leave.pressed.connect(func(): _main.hud._leave())
	vb.add_child(_leave)
	UiFx.fade_in(_panel, 0.4)

func _refresh() -> void:
	if _rows.is_empty():
		return
	var booths := _booths.filter(func(b): return b.built).size()
	var fed := _hungry.filter(func(f): return not f.hungry).size()
	var met := _named.filter(func(f): return f.met).size()
	_set_row("hear", _heard, tr("Hear Ezra read the Law at the Water Gate"))
	_set_row("booths", booths >= _booths.size(),
		tr("Build booths with branches from the mount — %d of %d") % [booths, _booths.size()])
	_set_row("portions", fed >= _hungry.size(),
		tr("Send portions to those with nothing prepared — %d of %d") % [fed, _hungry.size()])
	_set_row("people", met >= _named.size(), tr("Meet the people of the city — %d of %d") % [met, _named.size()])
	_set_row("temple", _visited, tr("Go up to the house of God"))
	var all := _heard and _visited and booths >= _booths.size() and fed >= _hungry.size() and met >= _named.size()
	if all and not _done_shown:
		_done_shown = true
		Sfx.play_jingle("won")
		_main.hud._show_banner(tr("There was very great gladness"),
			tr("%s  ·  Stay as long as you like") % GameState.short_ref("Neh. 8:17"), 5.0)

func _set_row(task: String, done: bool, text: String) -> void:
	var row: Array = _rows[task]
	var tick: Tick = row[0]
	if done and not tick.done:
		Sfx.play("tally_land")
	tick.done = done
	tick.queue_redraw()
	var l: Label = row[1]
	l.text = text
	l.add_theme_color_override("font_color", UiStyle.INK_MUTED if done else UiStyle.INK)


# A small box, ticked in olive when the task is done
class Tick extends Control:
	var done := false

	func _init() -> void:
		custom_minimum_size = Vector2(18, 18)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2(1, 1), size - Vector2(2, 2))
		draw_rect(r, UiStyle.PARCHMENT_DEEP)
		draw_rect(r, UiStyle.RULE, false, 1.5)
		if done:
			draw_polyline(PackedVector2Array([Vector2(4, 9), Vector2(8, 13), Vector2(15, 4)]), UiStyle.OLIVE, 3.0, true)
