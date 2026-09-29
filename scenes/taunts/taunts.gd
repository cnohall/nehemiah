class_name Taunts
extends Node3D

# The enemy's mockery, painted in soot on the ground outside the wall (Neh. 2:19, 4:2-3,
# 6:6) — one line before each of the first pieces of the stretch. As a piece rises the
# words under it fade, and when it stands they're gone: the building is the answer.
# Only in the stretches where the text has them mocking; fresh stretches wipe the ground
# clean. Every peer, from the wall's replicated stages alone.

const INK      := Color(0.16, 0.11, 0.08)
const ALPHA    := 0.9
const Z        := -2.1      # just outside the footing
const WIDTH_PX := 720       # wrap within a piece (8 m at PIXEL)
const PIXEL    := 0.011
const FADE     := 2.5       # alpha per second toward its target

# Section index → [line, who, ref]; spread over the stretch in build order (WorkFront)
const LINES := {
	0: [["What is this thing that you are doing?", "Sanballat · Tobiah · Geshem", "Neh. 2:19"],
		["Will you rebel against the king?", "Sanballat · Tobiah · Geshem", "Neh. 2:19"]],
	2: [["What are these feeble Jews doing?", "Sanballat", "Neh. 4:2"],
		["Will they revive the stones out of the heaps of rubbish, since they are burned?", "Sanballat", "Neh. 4:2"],
		["Will they fortify themselves?", "Sanballat", "Neh. 4:2"]],
	3: [["What they are building, if a fox climbed up it, he would break down their stone wall.", "Tobiah", "Neh. 4:3"],
		["Will they sacrifice?", "Sanballat", "Neh. 4:2"],
		["Will they finish in a day?", "Sanballat", "Neh. 4:2"]],
	4: [["Will they finish in a day?", "Sanballat", "Neh. 4:2"],
		["What are these feeble Jews doing?", "Sanballat", "Neh. 4:2"]],
	10: [["You and the Jews intend to rebel. Because of that, you are building the wall.", "Sanballat's letter", "Neh. 6:6"],
		["You would be their king.", "Sanballat's letter", "Neh. 6:6"]],
}

# Each: { "parts": Array (wall parts of the unit), "label": Label3D, "sign": Label3D }
var _painted: Array[Dictionary] = []

func _ready() -> void:
	GameState.section_changed.connect(_paint.unbind(1))
	_paint.call_deferred()

func _paint() -> void:
	for p in _painted:
		p["label"].queue_free()
		p["sign"].queue_free()
	_painted.clear()
	var lines: Array = LINES.get(GameState.current_section_index, [])
	if GameState.tutorial:
		lines = []
	var wall := get_parent().get_node("Wall")
	for i in lines.size():
		if i >= WorkFront.UNIT_ORDER.size():
			break
		var node: Node3D = wall.get_node(WorkFront.UNIT_ORDER[i])
		var parts: Array = node.get_children().filter(func(c): return c.has_method("try_build"))
		if node.has_method("try_build"):
			parts.append(node)
		var row: Array = lines[i]
		var at := Vector3(node.global_position.x, 0.115, Z)
		var label := _flat(tr(row[0]), UiStyle.SPECTRAL_ITALIC, 62, at)
		var sign := _flat("— %s, %s" % [tr(row[1]), GameState.short_ref(row[2])], UiStyle.CINZEL_SEMI, 30,
			at + Vector3(0.0, 0.0, -1.0))
		_painted.append({ "parts": parts, "label": label, "sign": sign })

# Text lying flat on the ground, reading along the wall
func _flat(text: String, font: Font, size: int, at: Vector3) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = size
	l.pixel_size = PIXEL
	l.modulate = Color(INK, 0.0)
	l.outline_size = 0
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.width = WIDTH_PX
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.double_sided = false
	l.shaded = false
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	l.position = at
	add_child(l)
	return l

func _process(delta: float) -> void:
	for p: Dictionary in _painted:
		var want := ALPHA * (1.0 - _progress(p["parts"]))
		for l: Label3D in [p["label"], p["sign"]]:
			l.modulate.a = move_toward(l.modulate.a, want, FADE * delta)

## 0 bare footing … 1 the whole piece stands
static func _progress(parts: Array) -> float:
	var sum := 0.0
	for part in parts:
		if part.is_complete():
			sum += 1.0
		elif "stage" in part:
			sum += part.stage / 3.0
	return sum / maxf(parts.size(), 1)
