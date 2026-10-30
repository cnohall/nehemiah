class_name Festival
extends CanvasLayer

# "Explore Jerusalem": the Festival of Booths after the wall was finished (Neh. 8) — a
# sandbox with no clock and no enemy, for walking Jerusalem. It opens at the Water Gate,
# where "all the people gathered themselves together as one man" (8:1), and the whole
# circuit is open: walk off either end of a stretch, along the wall, and you come to the
# next one round the ring (Neh. 3's order, back round to the Sheep Gate). Each stretch
# keeps its own ground (SectionTerrain) and the builders Neh. 3 names there; three hold
# the feast in full:
#   Water Gate — Ezra reads the Law from his wooden platform (8:3-8)
#   Sheep Gate — the house of God beside it (3:1), its court and altar
#   Fountain Gate — the pool of Shelah and the King's Garden (3:15)
# What there is to do, all from the chapter: hear the Law; go out for branches and build
# booths (8:15-16); send portions to those for whom nothing is prepared (8:10); meet the
# people; go up to the house of God. A journal ticks them off; progress holds from
# stretch to stretch. Nothing is timed and nothing is saved. Solo, offline (like the
# Tutorial): the game scene is its own server.
# Until this player has built the whole wall (GameState.built_sections) there is no feast:
# the stretches built stand with their builders, the rest lie broken (Neh. 2:17), and the
# walk opens at the first stretch still to build. The journal counts what stands.

const START := 8   # the Water Gate
const PLATFORM := Vector3(1.0, 0.1, 9.0)   # well in from the wall: the crowd gathers on its camera side
const PLATFORM_SIZE := Vector3(3.2, 1.1, 2.0)
const VISIT_POLL := 0.2
# Walking off the end of a stretch: past EDGE_X you go on to the next; you arrive ARRIVE_X in
const EDGE_X   := 41.5
const ARRIVE_X := 38.5
const SIGN_X   := 40.0
## Which way round the wall a step toward +x takes you: -1, so the next gate of Neh. 3
## lies toward -x. With the outside of the wall at -z, that makes each stretch a true
## turn of the map, not its mirror — north-up, the wall lies on screen as on the map.
const FLOW := -1
const FADE     := 0.3
# The feast is kept when these are done ("There was very great gladness", 8:17)
const BOOTH_GOAL  := 5
const PEOPLE_GOAL := 8

# The builders Neh. 3 names at each stretch: [who, look, words, ref] — quoted, WEB
const BUILDERS := {
	0: [["Eliashib the high priest", "priest", "Then Eliashib the high priest rose up with his brothers the priests, and they built the sheep gate.", "Neh. 3:1"]],
	1: [["The sons of Hassenaah", "man", "The sons of Hassenaah built the fish gate. They laid its beams, and set up its doors, its bolts, and its bars.", "Neh. 3:3"]],
	2: [["Joiada and Meshullam", "man", "Joiada the son of Paseah and Meshullam the son of Besodeiah repaired the old gate.", "Neh. 3:6"]],
	3: [["Uzziel the goldsmith", "man", "Next to him, Uzziel the son of Harhaiah, goldsmiths, made repairs.", "Neh. 3:8"],
		["Hananiah the perfumer", "man", "Next to him, Hananiah, one of the perfumers, made repairs, and they fortified Jerusalem even to the wide wall.", "Neh. 3:8"]],
	4: [["Malchijah and Hasshub", "man", "Malchijah the son of Harim and Hasshub the son of Pahathmoab repaired another portion and the tower of the furnaces.", "Neh. 3:11"],
		["Shallum's daughters", "woman", "Next to him, Shallum the son of Hallohesh, the ruler of half the district of Jerusalem, he and his daughters made repairs.", "Neh. 3:12"]],
	5: [["Hanun of Zanoah", "man", "Hanun and the inhabitants of Zanoah repaired the valley gate.", "Neh. 3:13"]],
	6: [["Malchijah son of Rechab", "elder", "Malchijah the son of Rechab, the ruler of the district of Beth Haccherem, repaired the dung gate.", "Neh. 3:14"]],
	7: [["Shallun son of Colhozeh", "elder", "Shallun the son of Colhozeh, the ruler of the district of Mizpah, repaired the spring gate.", "Neh. 3:15"],
		["Nehemiah son of Azbuk", "man", "Nehemiah the son of Azbuk, the ruler of half the district of Beth Zur, made repairs to the place opposite the tombs of David, and to the pool that was made.", "Neh. 3:16"]],
	8: [["The temple servants of Ophel", "man", "Now the temple servants lived in Ophel, to the place opposite the water gate toward the east, and the tower that stands out.", "Neh. 3:26"]],
	9: [["A priest of the Horse Gate", "priest", "Above the horse gate, the priests made repairs, everyone across from his own house.", "Neh. 3:28"]],
	10: [["Shemaiah, keeper of the east gate", "man", "After him, Shemaiah the son of Shecaniah, the keeper of the east gate, made repairs.", "Neh. 3:29"]],
	11: [["Malchijah the goldsmith", "man", "Malchijah, one of the goldsmiths to the house of the temple servants, and of the merchants, made repairs opposite the gate of Hammiphkad and to the ascent of the corner.", "Neh. 3:31"]],
}
const BUILDER_AT := [Vector3(-2.2, 0.1, 3.0), Vector3(-5.8, 0.1, 3.0)]   # by the gate each built

# The three feast districts. booths: [at, place]; hungry: [at, look]
const FEASTS := {
	8: {
		"platform": true,
		"booths": [[Vector3(-7.0, 0.1, 9.5), "in the broad place of the Water Gate"], [Vector3(-17.0, 0.1, 9.0), "in a courtyard"],
			[Vector3(14.0, 0.1, 6.0), "in a courtyard"], [Vector3(7.0, 0.1, 24.0), "by the well"]],
		"branches": [Vector3(-9.0, 0.1, -10.5), Vector3(3.0, 0.1, -10.0), Vector3(15.0, 0.1, -12.0)],
		"portion": Vector3(-6.0, 0.1, 13.5),
		"hungry": [[Vector3(-9.5, 0.1, 22.6), "elder"], [Vector3(18.0, 0.1, 25.2), "woman"]],
	},
	0: {
		"temple": true,
		"booths": [[Vector3(41.1, 0.1, 9.3), "in the courts of God's house"], [Vector3(-8.0, 0.1, 9.5), "in the broad place of the Sheep Gate"]],
		"branches": [Vector3(-4.0, 0.1, -11.0), Vector3(8.0, 0.1, -10.0)],
		"portion": Vector3(6.0, 0.1, 9.0),
		"hungry": [[Vector3(9.5, 0.1, 22.6), "elder"]],
	},
	7: {
		"booths": [[Vector3(-9.0, 0.1, 10.8), "by the pool of Shelah"], [Vector3(3.0, 0.1, 7.0), "in a courtyard"]],
		"branches": [Vector3(15.0, 0.1, 12.6)],   # boughs of thick trees, from the King's Garden
		"portion": Vector3(-3.0, 0.1, 9.5),
		"hungry": [[Vector3(-2.0, 0.1, 30.5), "man"]],
	},
}
# Everywhere else: people about, and a booth of their own if someone brings branches
const OTHER_BOOTH := [Vector3(-12.5, 0.1, 11.0), "in a courtyard"]   # clear of every stretch's ground
const OTHER_BRANCHES := Vector3(-8.0, 0.1, -10.0)
const TOWNSFOLK := [
	["The wall is finished in fifty-two days!", "see Neh. 6:15"],
	["Have you been out to the mount for branches?", "see Neh. 8:15"],
	["Every one of us on his own roof, in a shelter of boughs.", "see Neh. 8:16"],
	["Not since the days of Joshua has it been kept like this.", "see Neh. 8:17"],
	["Walk the whole wall round: every gate stands.", ""],
]
# Before the wall is finished: on a stretch that stands, and on one still in ruins
const BUILT_TALK := [
	["The God of heaven will prosper us.", "Neh. 2:20"],
	["The people had a mind to work.", "see Neh. 4:6"],
	["Half of us worked, and half held the spears.", "see Neh. 4:16"],
	["This stretch stands. Now the gaps further round.", ""],
]
const RUIN_TALK := [
	["The wall of Jerusalem is broken down, and its gates are burned with fire.", "see Neh. 1:3"],
	["Come, let's build up the wall of Jerusalem, that we won't be disgraced.", "Neh. 2:17"],
	["There is so much rubble. How can we build the wall?", "see Neh. 4:10"],
]

var _main: Node
var _root: Node3D
var _district := -1
var _traveling := false
var _cooldown := 0.0
var _poll := 0.0
var _saved := {}
var _built: Array[bool] = []   # stretch → standing (this player's campaign)
var _feast := false            # the whole wall stands: the Festival of Booths
# Progress kept across districts
var _heard := false
var _visited := false
var _done_shown := false
var _booths_raised := {}   # "district:index" → true
var _fed := {}             # "district:index" → true
var _met := {}             # who → true
var _seen := {}            # district → true
var _fade: ColorRect
var _compass: RingCompass
var _dedication: Dedication

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
	get_tree().call_group("watch_posts", "_refresh")   # GameState.posts is off: no posts, no footings
	_built = GameState.built_sections()
	_feast = not _built.has(false)
	_clear_the_yard()
	_build_fade()
	_dedication = Dedication.new(self)
	add_child(_dedication)
	_dedication.finished.connect(_refresh)
	_build_journal()
	_enter(START if _feast else maxi(_built.find(false), 0))

func _exit_tree() -> void:
	Player.view_yaw = 0.0   # a static: the game's own view again
	GameState.sun = _saved.get("sun", true)
	GameState.posts = _saved.get("posts", true)

func _process(delta: float) -> void:
	_cooldown -= delta
	_poll -= delta
	if _poll > 0.0 or _traveling:
		return
	_poll = VISIT_POLL
	var me := Player.local
	if me == null or not is_instance_valid(me):
		return
	var at := me.global_position
	if _feast and not _visited and FEASTS.get(_district, {}).get("temple", false) and Temple.in_court(at):
		_visited = true
		Sfx.play("tally_land")
		_main.hud._show_banner(tr("The house of God"),
			tr("“We will not forsake the house of our God.”  (%s)") % GameState.short_ref("Neh. 10:39"), 3.6)
		_refresh()
	# Off the end of the stretch: on round the wall
	if _cooldown <= 0.0 and absf(at.x) > EDGE_X:
		_travel(1 if at.x > 0.0 else -1, at.z)

# ── Round the wall ─────────────────────────────────────────

## The stretch off the end of this one on the +x (dir 1) or -x (dir -1) side
func _neighbour(dir: int) -> int:
	return posmod(_district + dir * FLOW, GameState.SECTIONS.size())

func _travel(dir: int, z: float) -> void:
	_traveling = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, FADE)
	await tw.finished
	_enter(_neighbour(dir))
	var me := Player.local
	if me != null and is_instance_valid(me):
		me.global_position = Vector3(-dir * ARRIVE_X, me.global_position.y, _arrival_z(dir, z))
	_main._cam_snapped = false   # no swoop across the whole site
	_cooldown = 1.0
	tw = create_tween()
	tw.tween_property(_fade, "color:a", 0.0, FADE)
	_traveling = false

# Turn the view so true north is straight up-screen, as on a map of the city
func _north_up_yaw(district: int) -> float:
	return RingCompass.north_up_yaw(district)

## Along the wall at the same depth — but at the Sheep Gate's east end the temple court
## fills the ground up to the wall, so in along the street before its gate
func _arrival_z(dir: int, z: float) -> float:
	if _district == 0 and dir < 0:
		return Temple.COURT.end.y + 1.6
	return clampf(z, 2.5, 12.0)

func _enter(district: int) -> void:
	_district = district
	_clear_district()   # before the new ground is laid, which keeps clear of what's standing
	GameState.festival_district(district)
	_clear_the_yard()   # a new stretch sets its piles out again
	if _built[district]:
		_raise_the_wall()   # this stretch's gate (or infill) standing
	else:
		_ruin_the_wall()
	_build_district()
	if _feast:
		_dedication.district_ready(district, _root)
	var sec: Dictionary = GameState.SECTIONS[district]
	var first := not _seen.has(district)
	_seen[district] = true
	if _compass != null:
		_compass.district = district
	_main.set_view_yaw(_north_up_yaw(district))
	_refresh()
	var sub := GameState.short_ref(sec["ref"])
	if not _built[district]:
		sub = tr("%s  ·  not yet built") % sub
	if first:
		sub = tr("%s  ·  walk off either end of the wall to go on round") % sub
	_main.hud._show_banner(tr(sec["name"]), sub, 2.6 if first else 1.6)

## A banner for the dedication's walk (Dedication)
func announce(title: String, sub: String, hold := 3.0) -> void:
	_main.hud._show_banner(title, sub, hold)

func refresh_journal() -> void:
	_refresh()

func _build_fade() -> void:
	_fade = ColorRect.new()
	_fade.color = Color(UiStyle.DUSK, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)

# ── Setting the scene ──────────────────────────────────────

# "So the wall was finished" (6:15): every piece of this stretch stands, doors hung
func _raise_the_wall() -> void:
	for unit: Array in _main.director._units:
		for part in unit:
			if "stage" in part:
				part.stage = 3
			elif "finished" in part:
				part.finished = true

# Not yet built: the stretch as the campaign finds it — bare footings, old courses, burned
# heaps (WallSection.reset_slot)
func _ruin_the_wall() -> void:
	for unit: Array in _main.director._units:
		for part in unit:
			part.reset_slot()
			part.is_target = false

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

func _clear_district() -> void:
	if _root != null:
		_main.remove_child(_root)
		_root.queue_free()
		_root = null

func _build_district() -> void:
	_root = Node3D.new()
	_root.name = "Festival"
	_main.add_child(_root)
	var d := _district
	var feast: Dictionary = FEASTS.get(d, {})
	if feast.get("temple", false):
		_root.add_child(Temple.new())   # rebuilt in Zerubbabel's day: it stands either way
		if _feast:
			_add_temple_people(_root)
	if not _feast:
		_build_walk(_root, d)
		_add_signs(_root)
		return
	if feast.get("platform", false):
		_build_platform(_root)
		_add_water_gate_people(_root)
	var booths: Array = feast.get("booths", [OTHER_BOOTH])
	for i in booths.size():
		var b := Booth.new()
		b.name = "Booth%d" % i
		b.place = booths[i][1]
		b.position = booths[i][0]
		var key := "%d:%d" % [d, i]
		b.raised.connect(func():
			_booths_raised[key] = true
			_refresh())
		_root.add_child(b)
		if _booths_raised.has(key):
			b.stand()
	var pile_scene := load("res://scenes/supply_pile/supply_pile.tscn") as PackedScene
	for at: Vector3 in feast.get("branches", [OTHER_BRANCHES]):
		_root.add_child(_pile(pile_scene, "branch", at))
	if feast.has("portion"):
		_root.add_child(_pile(pile_scene, "portion", feast["portion"]))
	var hungry: Array = feast.get("hungry", [])
	for i in hungry.size():
		_add_hungry(_root, "%d:%d" % [d, i], hungry[i][0], hungry[i][1])
	var builders: Array = BUILDERS.get(d, [])
	for i in builders.size():
		var row: Array = builders[i]
		_folk(_root, row[0], row[1], Palette.DYES[(d + i) % Palette.DYES.size()], BUILDER_AT[i % BUILDER_AT.size()],
			[[row[2], row[3]]]).wander = 1.2
	if not feast.get("platform", false):
		_add_townsfolk(_root, d, TOWNSFOLK, 6)
	_add_signs(_root)

# Before the feast: the builders by a stretch that stands; people about either way, talking
# of the work done or still to do
func _build_walk(root: Node3D, d: int) -> void:
	if _built[d]:
		var builders: Array = BUILDERS.get(d, [])
		for i in builders.size():
			var row: Array = builders[i]
			_folk(root, row[0], row[1], Palette.DYES[(d + i) % Palette.DYES.size()], BUILDER_AT[i % BUILDER_AT.size()],
				[[row[2], row[3]]]).wander = 1.2
	_add_townsfolk(root, d, BUILT_TALK if _built[d] else RUIN_TALK, 4)

func _pile(scene: PackedScene, kind: String, at: Vector3) -> Node3D:
	var p := scene.instantiate()
	p.kind = kind
	p.position = at
	p.ready.connect(func(): p.count_label.clamp_to_screen = false)
	return p

# At each end of the stretch: a post saying which gate lies on round the wall that way
func _add_signs(root: Node3D) -> void:
	for dir: int in [-1, 1]:
		var next := _neighbour(dir)
		var post := Node3D.new()
		post.position = Vector3(dir * SIGN_X, 0.1, 4.0)
		root.add_child(post)
		var parts := WatchPost._Parts.new()
		parts.add(Vector3(0.16, 2.0, 0.16), Vector3(0, 1.0, 0), Color(0.46, 0.32, 0.18))
		parts.add(Vector3(1.3, 0.34, 0.08), Vector3(dir * 0.45, 1.75, 0), Color(0.60, 0.44, 0.26))
		post.add_child(parts.build(Chunky.wood_material(0.02)))
		var tag := WorldTag.make(WorldTag.Kind.NOTE)
		tag.clamp_to_screen = false
		tag.position = Vector3(0, 2.6, 0)
		var gate: String = tr(GameState.SECTIONS[next]["name"])
		tag.text = ("%s  →" % gate) if dir > 0 else ("←  %s" % gate)
		post.add_child(tag)

# Which way the people gather from Ezra's platform: toward the camera, so the readers
# face it over the crowd's heads ("in the sight of all the people", 8:5) — but never out
# across the wall
func _crowd_dir() -> Vector3:
	var d := -RingCompass.SCREEN_UP.rotated(Vector3.UP, _north_up_yaw(_district))
	d.z = maxf(d.z, -0.6)
	return d.normalized()

# Ezra's platform of wood (8:4), its rail and lectern toward the people
func _build_platform(root: Node3D) -> void:
	var body := StaticBody3D.new()
	body.position = PLATFORM
	var d := _crowd_dir()
	body.rotation.y = atan2(d.x, d.z)
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

func _add_water_gate_people(root: Node3D) -> void:
	var d := _crowd_dir()
	var turn := Basis(Vector3.UP, atan2(d.x, d.z))   # the platform's own frame
	var ahead := PLATFORM + d * 20.0                 # what the readers look out over
	var top := PLATFORM + Vector3(0, PLATFORM_SIZE.y + 0.07, 0)
	var ezra := _folk(root, "Ezra the scribe", "scribe", Palette.MUREX, top + turn * Vector3(0, 0, 0.2), [
		["You shall take on the first day the fruit of majestic trees, branches of palm trees, and boughs of thick trees, and willows of the brook; and you shall rejoice before Yahweh your God seven days.", "Lev. 23:40"],
		["You shall dwell in temporary shelters for seven days.", "Lev. 23:42"],
		["Go out to the mountain, and get olive branches, branches of wild olive, myrtle branches, palm branches, and branches of thick trees, to make temporary shelters, as it is written.", "Neh. 8:15"],
	])
	ezra.radius = 1.4
	ezra.face(ahead)
	ezra.spoken.connect(func(_f):
		_heard = true
		_refresh())
	for sx: float in [-1.0, 1.0]:
		var priest := _folk(root, "", "priest", Palette.INDIGO, top + turn * Vector3(sx * 1.1, 0, -0.35), [])
		priest.radius = 1.4
		priest.face(ahead)
	# Nehemiah before the platform, on the city side, with the Levites (8:9)
	var nehemiah := _folk(root, "Nehemiah the governor", "governor", Palette.SAFFRON, PLATFORM + turn * Vector3(-2.2, 0, 1.3), [
		["Today is holy to Yahweh your God. Don’t mourn, nor weep.", "Neh. 8:9"],
		["Go your way. Eat the fat, drink the sweet, and send portions to him for whom nothing is prepared.", "Neh. 8:10"],
		["Don’t be grieved, for the joy of Yahweh is your strength.", "Neh. 8:10"],
	])
	nehemiah.face(ahead)
	var levite := _folk(root, "A Levite", "priest", Palette.WELD, Vector3(-3.0, 0.1, 11.2), [
		["We read in the book distinctly, and give the sense, so that everyone understands.", "see Neh. 8:8"],
		["Hold your peace, for the day is holy. Don’t be grieved.", "Neh. 8:11"],
	])
	levite.wander = 1.5
	var meremoth := _folk(root, "Meremoth the priest", "priest", Palette.MUREX, Vector3(-19.0, 0.1, 11.0), [
		["I repaired the wall from the door of Eliashib's house to its end.", "see Neh. 3:21"],
		["They're building shelters in the courts of God's house too, round the wall at the Sheep Gate.", "see Neh. 8:16"],
	])
	meremoth.wander = 2.0
	_folk(root, "The gatekeeper", "man", Palette.INDIGO, Vector3(-9.0, 0.1, 2.6), [
		["Out through the gate for branches: olive, myrtle, palm. Go to the mount.", "see Neh. 8:15"],
		["The gates stay open today. Nobody is coming to fight.", ""],
	])
	for i in 2:
		var kid := _folk(root, "", "child", Palette.DYES[i + 1], Vector3(-1.5 + i * 1.3, 0.1, 14.0 + i * 0.4), [
			["We're going out for palm branches!", ""],
		])
		kid.size_scale = 0.62
		kid.wander = 2.5
	# The crowd in the broad place, turned to the platform
	var rng := RandomNumberGenerator.new()
	rng.seed = 818
	for i in 14:
		var row := i / 5
		var across := -3.0 + (i % 5) * 1.5 + rng.randf_range(-0.3, 0.3)
		var at := PLATFORM + turn * Vector3(across, 0.0, 3.0 + row * 1.5 + rng.randf_range(-0.25, 0.25))
		var kind: String = ["man", "woman", "elder", "man", "woman", "child"][rng.randi() % 6]
		var f := _folk(root, "", kind, Palette.DYES[rng.randi() % Palette.DYES.size()], at,
			[["Amen, Amen!", "Neh. 8:6"]] if i % 2 == 0 else [["We've listened since early morning.", "see Neh. 8:3"]])
		f.face(PLATFORM)
		if kind == "child":
			f.size_scale = 0.62

func _add_temple_people(root: Node3D) -> void:
	var keeper := _folk(root, "A priest at the altar", "priest", Palette.INDIGO, Vector3(34.6, 0.1, 9.6), [
		["We will not forsake the house of our God.", "Neh. 10:39"],
		["Fire shall be kept burning on the altar continually; it shall not go out.", "Lev. 6:13"],
	])
	keeper.wander = 1.0
	_folk(root, "", "priest", Palette.WELD, Vector3(33.6, 0.1, 13.8), [
		["Go up into the court. There's a shelter to put up by the altar.", "see Neh. 8:16"],
	]).wander = 2.0

# A few people about the stretch, glad of the day
func _add_townsfolk(root: Node3D, d: int, talk: Array, count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7700 + d
	for i in count:
		var at := Vector3(rng.randf_range(-16.0, 16.0), 0.1, rng.randf_range(9.0, 13.0))
		var kind: String = ["man", "woman", "elder", "child", "woman", "man"][i]
		var f := _folk(root, "", kind, Palette.DYES[rng.randi() % Palette.DYES.size()], at,
			[talk[(d + i) % talk.size()]])
		f.facing = ["down", "left", "right", "up"][rng.randi() % 4]
		f.wander = 3.0
		if kind == "child":
			f.size_scale = 0.62

func _add_hungry(root: Node3D, key: String, at: Vector3, kind: String) -> void:
	var f := Folk.new()
	f.who = ""
	f.hungry = not _fed.has(key)
	f.fed_line = ["Blessings on you. The joy of Yahweh is our strength today.", "see Neh. 8:10"]
	f.look = Folk.look_for(kind, Palette.UNDYED.darkened(0.2), absi(key.hash()))
	f.position = at
	f.fed.connect(func(_f):
		_fed[key] = true
		_refresh())
	root.add_child(f)

func _folk(root: Node3D, who: String, kind: String, dye: Color, at: Vector3, lines: Array) -> Folk:
	var f := Folk.new()
	f.who = who
	f.lines = lines
	f.look = Folk.look_for(kind, dye, root.get_child_count())
	f.position = at
	f.met = _met.has(who)
	root.add_child(f)
	if not who.is_empty():
		f.spoken.connect(func(_f):
			_met[who] = true
			_refresh())
	return f

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
	eyebrow.text = tr("Neh. 8  ·  The seventh month") if _feast else GameState.short_ref("Neh. 2:17")
	eyebrow.add_theme_color_override("font_color", UiStyle.TERRACOTTA)
	vb.add_child(eyebrow)
	var title := Label.new()
	title.theme_type_variation = &"Heading"
	title.text = "The Festival of Booths" if _feast else "Jerusalem"
	title.add_theme_color_override("font_color", UiStyle.INK)
	vb.add_child(title)
	var sub := Label.new()
	sub.theme_type_variation = &"Caption"
	sub.text = "The wall is finished. No clock, no enemy. Walk the city." if _feast 		else "The wall is not yet finished. The Festival of Booths waits for the last stone."
	if not _feast:
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.custom_minimum_size.x = 330
	sub.add_theme_color_override("font_color", UiStyle.INK_SOFT)
	vb.add_child(sub)
	vb.add_child(HSeparator.new())
	var tasks := ["hear", "booths", "portions", "people", "temple", "dedication", "circuit"] if _feast else ["built", "circuit"]
	for task: String in tasks:
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
	hint.text = tr("Walk up to people and press %s to talk") % InputMode.key("interact")
	hint.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	vb.add_child(hint)
	# Where on the wall you are, and which way north lies
	_compass = RingCompass.new()
	_compass.district = START
	vb.add_child(_compass)
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
	var booths := _booths_raised.size()
	var fed := _fed.size()
	var hungry := 0
	for f: Dictionary in FEASTS.values():
		hungry += f.get("hungry", []).size()
	var met := _met.size()
	var gates := GameState.SECTIONS.size()
	_set_row("circuit", _seen.size() >= gates, tr("Walk the wall round: %d of %d gates") % [_seen.size(), gates])
	if not _feast:
		var standing := _built.count(true)
		_set_row("built", false, tr("Stretches of wall standing: %d of %d") % [standing, gates])
		return
	_set_row("hear", _heard, tr("Hear Ezra read the Law at the Water Gate"))
	_set_row("booths", booths >= BOOTH_GOAL,
		tr("Build booths with branches from the mount: %d of %d") % [mini(booths, BOOTH_GOAL), BOOTH_GOAL])
	_set_row("portions", fed >= hungry,
		tr("Send portions to those with nothing prepared: %d of %d") % [fed, hungry])
	_set_row("people", met >= PEOPLE_GOAL, tr("Meet the people who built the wall: %d of %d") % [mini(met, PEOPLE_GOAL), PEOPLE_GOAL])
	_set_row("temple", _visited, tr("Go up to the house of God, by the Sheep Gate"))
	var walked := _dedication != null and _dedication.done
	_set_row("dedication", walked, tr("Walk the wall with a choir, from the Valley Gate to the temple") if _dedication == null or not _dedication.active
		else tr("Follow the company round the wall to the house of God"))
	var all := _heard and _visited and booths >= BOOTH_GOAL and fed >= hungry and met >= PEOPLE_GOAL
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
