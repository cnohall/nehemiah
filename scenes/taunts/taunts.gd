class_name Taunts
extends Node3D

# The enemy's mockery (Neh. 2:19, 4:2-3, 6:6), one line per stretch: called across the
# wall by a herald of Sanballat's (below) — the part you hear from anywhere — and daubed
# in soot on whitewash on the open ground beyond the wall. As the stretch rises the words
# fade and the herald goes; when it stands they're gone: the building is the answer.
# Only in the stretches where the text has them mocking; fresh stretches wipe the ground
# clean. Every peer, from the wall's replicated stages alone.

const INK      := Color(0.26, 0.07, 0.04)   # soot and oxblood: the enemy's colour
const ALPHA    := 0.95
const WASH     := Color(0.97, 0.94, 0.86)   # the whitewash they daubed it on, so it reads on the sand
const WASH_ALPHA := 0.8
const WASH_SIZE  := Vector2(11.5, 4.2)
# Just out beyond the footings: from the yard the camera (looking from the south-east)
# shows the ground outside only up and to the right, and not far. The words are turned
# to read straight across the screen rather than along the wall's diagonal.
# Measured (camera from the yard): (-2, -5.5) lands near (1550, 125) of 1920×1080 —
# the words hang down-screen from there, clear of the footings; the signature above
const X        := -2.0
const Z        := -5.5
const YAW      := PI / 4.0
const ACROSS   := Vector3(0.70710678, 0.0, 0.70710678)   # one line down, on screen
const WIDTH_PX := 900       # ~10 m at PIXEL
const PIXEL    := 0.011
const FADE     := 2.5       # alpha per second toward its target

# Section index → [line, who, ref]
const LINES := {
	0: ["What is this thing that you are doing? Will you rebel against the king?", "Sanballat · Tobiah · Geshem", "Neh. 2:19"],
	2: ["What are these feeble Jews doing? … Will they revive the stones out of the heaps of rubbish, since they are burned?", "Sanballat", "Neh. 4:2"],
	3: ["What they are building, if a fox climbed up it, he would break down their stone wall.", "Tobiah", "Neh. 4:3"],
	4: ["Will they fortify themselves? Will they sacrifice? Will they finish in a day?", "Sanballat", "Neh. 4:2"],
	10: ["You and the Jews intend to rebel. Because of that, you are building the wall.", "Sanballat's letter", "Neh. 6:6"],
}

# Each: { "parts": Array (wall parts of the unit), "label": Label3D, "sign": Label3D }
var _painted: Array[Dictionary] = []

func _ready() -> void:
	GameState.section_changed.connect(_paint.unbind(1))
	_paint.call_deferred()

func _paint() -> void:
	for p in _painted:
		for k in ["label", "sign", "wash"]:
			p[k].queue_free()
	_painted.clear()
	var row: Array = LINES.get(GameState.current_section_index, [])
	_row = [] if GameState.free_play() else row
	if _herald == null:
		_build_herald()
	if _row.is_empty():
		return
	# One line per stretch, out on the open ground beyond the wall: away from the footings
	# and their tags, so it reads as the enemy's scrawl and not as a job to do
	var parts: Array = []
	var wall := get_parent().get_node("Wall")
	for unit_name: String in WorkFront.UNIT_ORDER:
		var node: Node3D = wall.get_node(unit_name)
		parts.append_array(node.get_children().filter(func(c): return c.has_method("try_build")))
		if node.has_method("try_build"):
			parts.append(node)
	var at := Vector3(X, 0.115, Z)
	var wash := _wash(at + ACROSS * 1.1 + Vector3(0.0, -0.005, 0.0))
	var label := _flat(tr(row[0]), UiStyle.WORLD_FONT, 64, at, VERTICAL_ALIGNMENT_TOP)
	label.outline_size = 8   # thick, smeared strokes
	var byline := _flat("— %s, %s" % [tr(row[1]), GameState.short_ref(row[2])], UiStyle.CINZEL_BOLD, 34,
		at - ACROSS * 0.25, VERTICAL_ALIGNMENT_BOTTOM)
	_painted.append({ "parts": parts, "label": label, "sign": byline, "wash": wash })

# A rough patch of whitewash slapped on the ground, soft at the edges
func _wash(at: Vector3) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = WASH_SIZE
	quad.orientation = PlaneMesh.FACE_Y
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color.WHITE)
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.62, Color(1, 1, 1, 0.85))
	tex.gradient = g
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = Color(WASH, 0.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	mi.rotation.y = YAW
	add_child(mi)
	return mi

# Text lying flat on the ground, reading along the wall
func _flat(text: String, font: Font, size: int, at: Vector3, valign: VerticalAlignment) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = size
	l.pixel_size = PIXEL
	l.modulate = Color(INK, 0.0)
	l.outline_modulate = Color(INK, 0.0)
	l.outline_size = 0
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.width = WIDTH_PX
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = valign
	l.double_sided = false
	l.shaded = false
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.rotation = Vector3(-PI / 2.0, YAW, 0.0)
	l.position = at
	add_child(l)
	return l

func _process(delta: float) -> void:
	for p: Dictionary in _painted:
		var want := ALPHA * (1.0 - _progress(p["parts"]))
		for l: Label3D in [p["label"], p["sign"]]:
			l.modulate.a = move_toward(l.modulate.a, want, FADE * delta)
			l.outline_modulate.a = l.modulate.a
		var mat: StandardMaterial3D = p["wash"].material_override
		mat.albedo_color.a = (p["label"] as Label3D).modulate.a * WASH_ALPHA / ALPHA
	_tick_herald(delta)

# ── The herald ─────────────────────────────────────────────

# One of Sanballat's men stands out beyond the wall and calls the taunt across it (as
# Sanballat's servant came with his open letter, Neh. 6:5): at the start of the work and
# every so often after, until the stretch is half built — then he's gone. His call slides
# in from the screen edge, so it's heard from anywhere on the site.
const HERALD_AT    := Vector3(7.0, 0.1, -6.5)
const HERALD_FIRST := 1.5
const HERALD_EVERY := 40.0
const HERALD_UNTIL := 0.5    # of the stretch built
const HERALD_HOLD  := 5.5

var _herald: Node3D
var _herald_rig: CharacterRig
var _herald_shout: Shout
var _herald_t := HERALD_FIRST
var _row: Array = []

func _build_herald() -> void:
	_herald = Node3D.new()
	_herald.position = HERALD_AT
	add_child(_herald)
	_herald_rig = CharacterRig.new()
	_herald.add_child(_herald_rig)
	var look := CharacterRig.enemy_look("scout")
	look["weapon"] = ""
	look["scroll"] = Color(0.90, 0.82, 0.62)
	_herald_rig.setup(look, 0.95)
	_herald_rig.set_ring_color(Color(0, 0, 0, 0))
	_herald_rig.play("idle_down")
	_herald_shout = Shout.make_shout()
	_herald_shout.position = Vector3(0, 2.8, 0)
	_herald.add_child(_herald_shout)

func _tick_herald(delta: float) -> void:
	if _herald == null:
		return
	var on := not _row.is_empty() and not _painted.is_empty() 		and _progress(_painted[0]["parts"]) < HERALD_UNTIL and not GameState.is_over()
	_herald.visible = on
	if not on or GameState.phase != GameState.Phase.WORK:
		if GameState.phase == GameState.Phase.DAWN:
			_herald_t = HERALD_FIRST
		return
	_herald_t -= delta
	if _herald_t > 0.0:
		return
	_herald_t = HERALD_EVERY
	_herald_shout.say("“%s”  (%s, %s)" % [tr(_row[0]), tr(_row[1]), GameState.short_ref(_row[2])], HERALD_HOLD)
	_herald_rig.squash(Vector2(0.9, 1.12))
	_herald_rig.play("thrust_down")
	get_tree().create_timer(0.8).timeout.connect(func():
		if is_instance_valid(_herald_rig):
			_herald_rig.play("idle_down"))
## 0 bare footings … 1 the whole stretch stands
static func _progress(parts: Array) -> float:
	var sum := 0.0
	for part in parts:
		if part.is_complete():
			sum += 1.0
		elif "stage" in part:
			sum += part.stage / 3.0
	return sum / maxf(parts.size(), 1)
