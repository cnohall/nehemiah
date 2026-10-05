class_name Leaders
extends Node3D

# Sanballat, Tobiah and Geshem in the world, not just on the story cards. At the arc's
# peaks they come to the rise beyond the wall and call across it, then turn and go a few
# seconds later (or at once when the stretch stands / the wall is finished: "they lost
# heart", Neh. 6:16). They don't linger in the enemy lane — unhittable humanoids there
# confused new players. No fighting: they're the pressure behind the attackers.
#
# When: a SectionBeats beat that names a leader (SectionBeats.beat_fired, "leader": one
# key, "all", or a comma list). Without SectionBeats, on the first work of the sections
# in FALLBACK. Every peer, from state it already has; nothing replicated.

const RISE_Z   := -10.5
const SPACING  := 2.6
const LEAVE_T  := 3.2
const CALL_HOLD := 5.0
const GHOST_ALPHA := 0.45   # toon_part "ghost": 0 solid, 1 gone
const LINGER  := 3.0   # after the call, before they turn and go
# Their own words (WEB), called across the wall when they arrive
const LINES := {
	"sanballat": ["What are these feeble Jews doing?", "Neh. 4:2"],
	"tobiah": ["If a fox climbed up it, he would break down their stone wall.", "Neh. 4:3"],
	"geshem": ["Come! Let's meet together in the plain of Ono.", "Neh. 6:2"],
}
const ALL := ["sanballat", "tobiah", "geshem"]
# Section index → who watches when there's no SectionBeats to say so
const FALLBACK := { 3: ["sanballat", "tobiah"], 5: ["sanballat", "tobiah", "geshem"], 10: ["geshem"], 11: ["sanballat", "tobiah", "geshem"] }

var _here := {}   # key → { "node": Node3D, "rig": CharacterRig, "shout": Shout }
var _beats := false

func _ready() -> void:
	GameState.phase_changed.connect(_on_phase)
	GameState.section_changed.connect(func(_i): _clear())
	_hook_beats.call_deferred()

func _hook_beats() -> void:
	var beats := get_parent().get_node_or_null("SectionBeats")
	if beats != null and beats.has_signal("beat_fired"):
		_beats = true
		beats.beat_fired.connect(_on_beat)

func _on_beat(_section: int, _key: String, beat: Dictionary) -> void:
	var who: String = beat.get("leader", "")
	if who.is_empty():
		return
	_arrive(ALL if who == "all" else Array(who.split(",")).map(func(k): return k.strip_edges()))

func _on_phase(phase: GameState.Phase) -> void:
	if GameState.free_play() or GameState.attract:
		return
	match phase:
		GameState.Phase.WORK:
			if not _beats and GameState.day_in_section(GameState.current_day).x == 0:
				_arrive(FALLBACK.get(GameState.current_section_index, []))
		GameState.Phase.DUSK, GameState.Phase.WON:
			# Worked till the stars they'd stay; a stretch that stands sends them off
			if GameState.targets_done >= GameState.targets_total or phase == GameState.Phase.WON:
				_leave()

func _arrive(keys: Array) -> void:
	if GameState.intro_day():
		return   # day 1 teaches one thing; a ghost by the wall reads as a bug
	var i := 0
	for key: String in keys:
		if not LINES.has(key) or _here.has(key):
			continue
		var n := Node3D.new()
		var x := (i - (keys.size() - 1) * 0.5) * SPACING
		n.position = Vector3(x, 0.1, RISE_Z - 6.0)
		add_child(n)
		var rig := CharacterRig.new()
		n.add_child(rig)
		rig.setup(FriendsAndFoes._look({ "key": key }), 1.1)
		rig.set_ring_color(Color(0, 0, 0, 0))
		_ghost.call_deferred(n, rig)
		rig.play("walk_down")
		var shout := Shout.make_shout()
		shout.position = Vector3(0, 3.0, 0)
		n.add_child(shout)
		_here[key] = { "node": n, "rig": rig, "shout": shout }
		GameState.mark_met(key)
		# Up onto the rise, then the call — one after another
		var tw := n.create_tween()
		tw.tween_property(n, "position:z", RISE_Z, 2.4).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(rig.play.bind("idle_down"))
		tw.tween_interval(0.4 + i * 2.2)
		tw.tween_callback(func():
			shout.say("%s — %s" % [tr(LINES[key][0]), tr(key.capitalize())], CALL_HOLD, true))
		# Call, then go: standing in the lane all fight reads as a target nobody can hit
		tw.tween_interval(CALL_HOLD + LINGER)
		tw.tween_callback(_dismiss.bind(key))
		_here[key]["tween"] = tw
		i += 1

# See-through, no shadow, no ground marker: reads as "watching", not as a unit to hit.
# Deferred — the rig builds its parts and its ground marker (a sibling) a frame late.
func _ghost(n: Node3D, rig: CharacterRig) -> void:
	if not is_instance_valid(n):
		return
	for c in n.get_children():
		if c is MeshInstance3D:
			c.visible = false   # contact shadow
	for c in rig.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		mi.set_instance_shader_parameter("ghost", GHOST_ALPHA)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _leave() -> void:
	for key: String in _here.keys():
		_dismiss(key)

func _dismiss(key: String) -> void:
	if not _here.has(key):
		return
	var n: Node3D = _here[key]["node"]
	var rig: CharacterRig = _here[key]["rig"]
	var old: Tween = _here[key]["tween"]
	_here.erase(key)
	if old.is_valid():
		old.kill()
	rig.play("walk_up")
	var tw := n.create_tween()
	tw.tween_property(n, "position:z", RISE_Z - 14.0, LEAVE_T).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(n.queue_free)

func _clear() -> void:
	for key: String in _here:
		_here[key]["node"].queue_free()
	_here.clear()
