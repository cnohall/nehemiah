class_name FirstSteps
extends Node

# Learning the work on the job (GDD §5.26). The real first day teaches itself: a pulsing tag
# over this player's next job until they have done it once, then never again on this
# machine. Local to each peer, so a new friend gets the tags while the veteran beside them
# sees nothing. The tag says where; while it speaks the HUD's "next" line stays quiet.
#
# Dash and help-up need no lesson here: the controls card lists the one, and every downed
# worker already floats "Help up [E]". DayDirector holds the first foe and the sun for the
# first load (_holds_first_load), so the first minute is safe to read.

const LESSONS := ["walk", "carry", "deliver", "build", "sling"]
const WALK_WAIT := 3.0      # s standing still before "walk" is worth saying
const WALK_DONE := 4.0      # m walked: they know
const FOE_NEAR := 14.0      # m: a foe this close is the next job (the sling reaches 10)
const PING_EVERY := 0.4     # s between edge-arrow refreshes for an off-screen target

## A tag is up: the HUD's "next" line waits (two voices would talk over each other)
static var speaking := false

var _guide: WorldTag
var _hidden_tag: WorldTag   # a pile tag the guide is standing in for
var _ping_t := 0.0
var _idle := 0.0
var _walk_from := Vector3.INF

func _ready() -> void:
	speaking = false
	_guide = WorldTag.make(WorldTag.Kind.TOAST)
	_guide.pulse = true
	_guide.solid = true   # the crew often spawns right at the pile, between it and its tag
	_guide.visible = false
	add_child(_guide)

func _exit_tree() -> void:
	speaking = false
	TouchControls.hint = ""

func _process(delta: float) -> void:
	if GameState.phase != GameState.Phase.WORK or not Settings.hints or Settings.all_learned(LESSONS):
		_show([], delta)
		return
	var me := Player.local
	if me == null or not is_instance_valid(me) or me.downed:
		_show([], delta)
		return
	_note_learned(me)
	_show(_goal(me, delta), delta)

func _note_learned(me: Player) -> void:
	if _walk_from == Vector3.INF:
		_walk_from = me.global_position   # here, not at spawn: the crew is placed at dawn
	if me.global_position.distance_to(_walk_from) > WALK_DONE:
		Settings.learn("walk")
	if not me.carried_kind.is_empty():
		Settings.learn("carry")
	if me.loads_brought > 0:
		Settings.learn("deliver")
	if me._work_site != null:
		Settings.learn("build")
	# Up close the same button is a sword cut: either way they have found it
	if me._sling_cd > 0.0 and not me._charging:
		Settings.learn("sling")

## [Node3D, "call"] for the next job this player hasn't done yet, or []
func _goal(me: Player, delta: float) -> Array:
	if not Settings.has_learned("sling"):
		var foe := _near_foe(me)
		if foe != null:
			if me._charging:
				return [foe, "Aim and throw"]
			return [foe, "Sling it  {throw}"]
	if not Settings.has_learned("walk"):
		_idle = 0.0 if me._move_input().length() > 0.35 else _idle + delta
		if _idle >= WALK_WAIT:
			return [me, "Walk  {move}"]
	return _work_goal(me)

# Carrying → the wall (or drop it); the wall has it all → work it; otherwise → the pile it
# still needs. Each only until this player has done it themself: a bot or a friend doing
# the job doesn't teach it.
func _work_goal(me: Player) -> Array:
	if me._work_site != null:
		return []
	var site := SiteFocus.site()
	if site == null:
		return []
	if not me.carried_kind.is_empty():
		if Settings.has_learned("deliver"):
			return []
		return [site, "Deliver  {interact}"] if SiteFocus.matches_carry() else [me, "Not needed here  {drop}"]
	if GameState.active_build and site.has_method("can_build") and site.can_build():
		return [] if Settings.has_learned("build") else [site, "Build  {interact}"]
	if Settings.has_learned("carry") and Settings.has_learned("deliver"):
		return []
	var pile := _pile(me, site)
	return [pile, "Pick up  {interact}"] if pile != null else []

# Nearest open pile of what the site needs. None (a stretch's own material, the trough) means
# no tag: better silence than pointing at the wrong thing.
func _pile(me: Player, site: Node3D) -> Node3D:
	var need: String = site.next_need() if site.has_method("next_need") else ""
	if need.is_empty():
		return null
	var best: Node3D
	var best_d := INF
	for p: Node3D in get_tree().get_nodes_in_group("supply_piles"):
		if p.kind != need or not p.is_visible_in_tree():
			continue
		var d := p.global_position.distance_to(me.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best

func _near_foe(me: Player) -> Node3D:
	var best: Node3D
	var best_d := FOE_NEAR
	for e: Node3D in get_tree().get_nodes_in_group("enemies"):
		var d := e.global_position.distance_to(me.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best

# The tag over the goal, and an edge arrow while it's off-screen
func _show(goal: Array, delta: float) -> void:
	var node: Node3D = goal[0] if goal.size() >= 2 else null
	if node == null or not is_instance_valid(node):
		speaking = false
		_guide.visible = false
		_stand_in(null)
		TouchControls.hint = ""
		return
	speaking = true
	TouchControls.hint = _touch_hint(goal[1])
	var own_tag := _own_tag(node)
	var at := own_tag.global_position if own_tag != null else node.global_position + Vector3(0.0, 2.4, 0.0)
	_guide.global_position = at
	var line := _keys(tr(goal[1]))
	# A pile's tag only names it: the guide takes its place ("Stone  Pick up [E]"). A
	# site's lists what it still needs, worth keeping: the guide sits on top of it.
	if node.is_in_group("build_sites"):
		_stand_in(null)
		_guide.screen_lift = 58.0 if own_tag != null and own_tag.visible else 0.0
	else:
		_stand_in(own_tag if node.get("count_label") == own_tag else null)
		_guide.screen_lift = 0.0
		if _hidden_tag != null:
			line = _hidden_tag.text + "  " + line
	_guide.text = line
	_guide.visible = true
	_ping_t -= delta
	if _ping_t <= 0.0 and not node.is_in_group("players"):
		_ping_t = PING_EVERY
		var alerts := get_tree().get_first_node_in_group("offscreen_alerts")
		if alerts != null:
			alerts.ping(at, UiStyle.AMBER, "Here", PING_EVERY + 0.1)

# Hide this pile tag while the guide speaks for it; bring the last one back
func _stand_in(tag: WorldTag) -> void:
	if tag == _hidden_tag:
		return
	if _hidden_tag != null and is_instance_valid(_hidden_tag):
		_hidden_tag.visible = true
	_hidden_tag = tag
	if tag != null:
		tag.visible = false

# The tag a build site or pile already floats (its needs, its stock), if any
func _own_tag(node: Node3D) -> WorldTag:
	for prop in ["_label", "count_label"]:
		var tag = node.get(prop)
		if tag is WorldTag and is_instance_valid(tag) and tag.is_inside_tree():
			return tag
	return null

# Phones: the touch button the tag asks for breathes a ring (TouchControls.hint)
func _touch_hint(call: String) -> String:
	for k: String in TOUCH_HINT:
		if call.contains("{%s}" % k):
			return TOUCH_HINT[k]
	return "sling" if call == "Aim and throw" else ""

const TOUCH_HINT := { "interact": "interact", "move": "move", "drop": "drop", "throw": "sling" }

func _keys(s: String) -> String:
	return s.format({
		"interact": "[%s]" % InputMode.key("interact"), "move": "[%s]" % InputMode.key("move"),
		"drop": "[%s]" % InputMode.key("drop"), "throw": "[%s]" % InputMode.key("throw")})
