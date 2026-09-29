class_name Folk
extends Node3D

# Someone in the city at the Festival of Booths. [E] beside them and they speak — a line
# of their own, or the text itself — one line per press, round again. A few have nothing
# prepared for the feast (Neh. 8:10): while they wait they're a build site that takes a
# portion, and once fed they say so. Solo festival: the server is the only peer.

signal spoken(folk: Folk)
signal fed(folk: Folk)

const TALK_REACH := 1.4   # added to the player's reach: they stand a little apart
const HOLD       := 4.2

## Shown in the journal when met
var who := ""
## [text, ref] pairs; ref may be ""
var lines: Array = []
## Waiting for a portion (Neh. 8:10); `fed_line` is what they say after
var hungry := false
var fed_line: Array = ["", ""]
var look := {}
var size_scale := 0.9
var facing := "down"
var radius := 0.0          # a speaker on a platform is reached from its edge
var sitting := false

var is_target := false
var met := false
var _next := 0
var _rig: CharacterRig
var _shout: Shout
var _tag: WorldTag

func _ready() -> void:
	add_to_group("folk")
	if hungry:
		add_to_group("build_sites")
	_rig = CharacterRig.new()
	add_child(_rig)
	_rig.setup(look, size_scale)
	_rig.set_ring_color(Color(0, 0, 0, 0))
	_rig.play(("sway_" if sitting else "idle_") + facing)
	_shout = Shout.make_shout()
	_shout.position = Vector3(0, 2.7 * size_scale / 0.9, 0)
	_shout.clamp_to_screen = false
	add_child(_shout)
	if hungry:
		_tag = WorldTag.make(WorldTag.Kind.SITE)
		_tag.position = Vector3(0, 2.6, 0)
		_tag.clamp_to_screen = false
		_tag.text = "%s\nPortion 0/1" % tr("Nothing prepared")
		add_child(_tag)

func _process(_delta: float) -> void:
	if _tag != null:
		var near := Player.local != null and distance_to_point(Player.local.global_position) < 7.0
		_tag.visible = hungry and not _shout.is_speaking()
		_tag.modulate.a = 1.0 if near else WorldTag.DIM

## Player (server): [E] beside them
func talk(_by: Node3D) -> void:
	var line: Array
	if hungry:
		line = ["Nothing is prepared in my house for the feast.", ""]
	elif lines.is_empty():
		line = fed_line
	else:
		line = lines[_next % lines.size()]
		_next += 1
	say(line)
	if not met:
		met = true
		spoken.emit(self)

func say(line: Array) -> void:
	var text := tr(line[0])
	if line.size() > 1 and not str(line[1]).is_empty():
		# A quote carries its reference; a paraphrase says "see" (Neh. …)
		var ref := str(line[1])
		var see := ref.begins_with("see ")
		ref = ref.trim_prefix("see ")
		var shown := GameState.short_ref(ref) if ref.begins_with("Neh") else tr(ref)
		text += "  (%s)" % ((tr("see %s") % shown) if see else shown)
	_shout.say(text, HOLD)
	_rig.squash(Vector2(0.94, 1.08))

func distance_to_point(p: Vector3) -> float:
	return maxf(0.0, Vector2(p.x - global_position.x, p.z - global_position.z).length() - radius - TALK_REACH)

func approach_point(from: Vector3, _standoff: float) -> Vector3:
	return Vector3(global_position.x, from.y, global_position.z)

# ── A portion for those with nothing prepared (build-site interface) ──

func needs(kind: String) -> bool:
	return hungry and kind == "portion"

func next_need() -> String:
	return "portion" if hungry else ""

func deposit(kind: String, _amount: int) -> bool:
	if not needs(kind):
		return false
	hungry = false
	remove_from_group("build_sites")
	_rig.play("cheer_" + facing)
	get_tree().create_timer(1.4).timeout.connect(func():
		if is_instance_valid(_rig):
			_rig.play("clap_" + facing))
	say(fed_line)
	fed.emit(self)
	return true

func can_build() -> bool:
	return false

func try_build() -> bool:
	return false

func is_complete() -> bool:
	return not hungry

func blocks_workers() -> bool:
	return false

func refusal(_kind: String) -> String:
	return "They're after bread, not that" if hungry else "They have plenty now"

func work() -> BuildWork:
	return null

func work_material() -> String:
	return ""

func reset_slot() -> void:
	pass

func repair(_fraction: float) -> void:
	pass

# ── Looks ──────────────────────────────────────────────────

## A townsman, woman, child, elder or priest in festival clothes
static func look_for(kind: String, dye: Color, seed_value: int) -> Dictionary:
	var l := CharacterRig.worker_look(seed_value % 4, dye)
	l["tool"] = false
	l["sword"] = false
	for k in ["basket", "basket_stones", "strap", "planks", "apron", "satchel", "scroll", "tool_always", "sculpted_builder", "bracers"]:
		l.erase(k)
	match kind:
		"man":
			l.merge({"hat": "band", "hat_color": dye, "long_robe": false,
				"robe": Palette.UNDYED.lerp(dye, 0.25), "beard": ["short", "full"][seed_value % 2],
				"hair": [Color(0.12, 0.08, 0.06), Color(0.30, 0.18, 0.10)][seed_value % 2]}, true)
		"woman":
			l.merge({"beard": "", "hat": "wrap", "hat_color": dye.lightened(0.35), "band": dye.darkened(0.2),
				"long_robe": true, "robe": dye.lerp(Palette.UNDYED, 0.45), "vest": dye}, true)
		"child":
			l.merge({"beard": "", "hat": "band", "hat_color": dye}, true)
		"elder":
			l.merge({"beard": "long", "hair": Color(0.82, 0.80, 0.76), "hat": "wrap",
				"hat_color": Palette.UNDYED.lightened(0.1), "long_robe": true}, true)
		"priest":
			l.merge({"beard": "long", "hat": "wrap", "hat_color": Color(0.97, 0.96, 0.92), "band": Palette.INDIGO,
				"robe": Color(0.95, 0.93, 0.88), "long_robe": true, "vest": Palette.INDIGO}, true)
		"scribe":
			l.merge({"beard": "long", "hair": Color(0.7, 0.68, 0.64), "hat": "wrap", "hat_color": Color(0.97, 0.96, 0.92),
				"band": Palette.MUREX, "robe": Color(0.95, 0.93, 0.88), "long_robe": true, "vest": Palette.MUREX,
				"scroll": Color(0.90, 0.82, 0.62)}, true)
	return l
