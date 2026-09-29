class_name Taunts
extends Node3D

# The enemy's mockery (Neh. 2:19, 4:2-3, 6:6), one line per stretch: called across the
# wall by a herald of Sanballat's (below), heard from anywhere on the site. He goes once
# the stretch is half built: the building is the answer. Only in the stretches where the
# text has them mocking. Every peer, from the wall's replicated stages alone.

# Section index → [line, who, ref]
const LINES := {
	0: ["What is this thing that you are doing? Will you rebel against the king?", "Sanballat · Tobiah · Geshem", "Neh. 2:19"],
	2: ["What are these feeble Jews doing? … Will they revive the stones out of the heaps of rubbish, since they are burned?", "Sanballat", "Neh. 4:2"],
	3: ["What they are building, if a fox climbed up it, he would break down their stone wall.", "Tobiah", "Neh. 4:3"],
	4: ["Will they fortify themselves? Will they sacrifice? Will they finish in a day?", "Sanballat", "Neh. 4:2"],
	10: ["You and the Jews intend to rebel. Because of that, you are building the wall.", "Sanballat's letter", "Neh. 6:6"],
}

var _parts: Array = []   # wall parts of the current stretch, for its progress

func _ready() -> void:
	GameState.section_changed.connect(_setup.unbind(1))
	_setup.call_deferred()

func _setup() -> void:
	_row = [] if GameState.free_play() else LINES.get(GameState.current_section_index, [])
	if _herald == null:
		_build_herald()
	_parts.clear()
	if _row.is_empty():
		return
	var wall := get_parent().get_node("Wall")
	for unit_name: String in WorkFront.UNIT_ORDER:
		var node: Node3D = wall.get_node(unit_name)
		_parts.append_array(node.get_children().filter(func(c): return c.has_method("try_build")))
		if node.has_method("try_build"):
			_parts.append(node)

func _process(delta: float) -> void:
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
	var on := not _row.is_empty() and _progress(_parts) < HERALD_UNTIL and not GameState.is_over()
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
