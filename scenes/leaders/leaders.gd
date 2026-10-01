class_name Leaders
extends Node3D

# Sanballat, Tobiah and Geshem in the world, not just on the story cards. At the arc's
# peaks they come and stand on the rise beyond the wall to watch the work — and call
# across it — and when the stretch stands (or the wall is finished) they turn and go:
# "they lost heart" (Neh. 6:16). No fighting: they're the pressure behind the attackers.
#
# When: a SectionBeats beat that names a leader (SectionBeats.beat_fired, "leader": one
# key, "all", or a comma list). Without SectionBeats, on the first work of the sections
# in FALLBACK. Every peer, from state it already has; nothing replicated.

const RISE_Z   := -10.5
const SPACING  := 2.6
const LEAVE_T  := 3.2
const CALL_HOLD := 5.0
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
		i += 1

func _leave() -> void:
	for key: String in _here:
		var n: Node3D = _here[key]["node"]
		var rig: CharacterRig = _here[key]["rig"]
		rig.play("walk_up")
		var tw := n.create_tween()
		tw.tween_property(n, "position:z", RISE_Z - 14.0, LEAVE_T).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_callback(n.queue_free)
	_here.clear()

func _clear() -> void:
	for key: String in _here:
		_here[key]["node"].queue_free()
	_here.clear()
