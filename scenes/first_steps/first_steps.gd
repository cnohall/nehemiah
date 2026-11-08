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
# Walking a load in delivers it (Player._auto_deliver): no button to name, a trail to follow
const DELIVER_LINE := "Carry it here"
const TRAIL_STEP := 0.85    # m between footprints
const TRAIL_FLOW := 1.4     # m/s they creep toward the wall
const TRAIL_REPATH := 0.15  # s: the near end keeps up with a walking player
const TRAIL_SKIP := 0.8     # m clear of the player's feet
const TRAIL_MAX := 120
const TRAIL_FADE := 2.5     # m over which prints grow in from either end

## A tag is up: the HUD's "next" line waits (two voices would talk over each other)
static var speaking := false

var _guide: WorldTag
var _hidden_tag: WorldTag   # a pile tag the guide is standing in for
var _ping_t := 0.0
var _idle := 0.0
var _walk_from := Vector3.INF
var _trail: MultiMeshInstance3D
var _trail_path := PackedVector3Array()
var _trail_repath := 0.0
var _trail_flow := 0.0

func _ready() -> void:
	speaking = false
	_guide = WorldTag.make(WorldTag.Kind.TOAST)
	_guide.pulse = true
	_guide.solid = true   # the crew often spawns right at the pile, between it and its tag
	_guide.visible = false
	add_child(_guide)
	_trail = _make_trail()
	add_child(_trail)

func _exit_tree() -> void:
	speaking = false

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
		return [site, DELIVER_LINE] if SiteFocus.matches_carry() else [me, "Not needed here  {drop}"]
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
		_update_trail(null, delta)
		return
	speaking = true
	_update_trail(node if goal[1] == DELIVER_LINE else null, delta)
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

# ── The trail: footprints from a first load to the wall ────────────────────

func _make_trail() -> MultiMeshInstance3D:
	var print_mesh := CylinderMesh.new()   # a flat oval stamp, stretched by its transform
	print_mesh.top_radius = 0.13
	print_mesh.bottom_radius = 0.13
	print_mesh.height = 0.012
	print_mesh.radial_segments = 14
	print_mesh.rings = 0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(UiStyle.AMBER.darkened(0.2), 0.95)   # pale amber vanishes on sand
	print_mesh.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = print_mesh
	mm.instance_count = TRAIL_MAX
	mm.visible_instance_count = 0
	var trail := MultiMeshInstance3D.new()
	trail.multimesh = mm
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trail.top_level = true
	trail.visible = false
	return trail

## Prints along the walkable way from the local player to `to` (null = no trail)
func _update_trail(to: Node3D, delta: float) -> void:
	var me := Player.local
	if to == null or me == null or not is_instance_valid(me):
		_trail.visible = false
		_trail_path = PackedVector3Array()
		return
	_trail_repath -= delta
	if _trail_path.is_empty() or _trail_repath <= 0.0:
		_trail_repath = TRAIL_REPATH
		var dest: Vector3 = to.approach_point(me.global_position, 0.0) if to.has_method("approach_point") \
			else to.global_position
		_trail_path = _walk_path(me, dest)
	_trail_flow = fmod(_trail_flow + delta * TRAIL_FLOW, TRAIL_STEP * 2.0)
	_lay_prints()
	_trail.visible = true

func _walk_path(me: Node3D, dest: Vector3) -> PackedVector3Array:
	var map := me.get_world_3d().navigation_map
	var from := me.global_position
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return PackedVector3Array([from, dest])   # not baked yet: straight there
	var path := NavigationServer3D.map_get_path(map, NavigationServer3D.map_get_closest_point(map, from),
		NavigationServer3D.map_get_closest_point(map, dest), true)
	return path if path.size() >= 2 else PackedVector3Array([from, dest])

# Counted back from the wall end, so the prints stay put in the world as the player walks
# and only the flow moves them. Left, right, left: footsteps, not dots.
func _lay_prints() -> void:
	var mm := _trail.multimesh
	var lengths := PackedFloat32Array([0.0])
	for i in range(1, _trail_path.size()):
		lengths.append(lengths[i - 1] + _flat(_trail_path[i] - _trail_path[i - 1]).length())
	var total := lengths[lengths.size() - 1]
	var n := 0
	var k := 0
	while n < TRAIL_MAX:
		# The flow wraps every two steps, so print k keeps its foot as it creeps
		var side := 1.0 if k % 2 == 0 else -1.0
		var from_end := k * TRAIL_STEP + TRAIL_STEP * 2.0 - _trail_flow
		k += 1
		var s := total - from_end
		if s < TRAIL_SKIP:
			break
		if s > total - 0.3:
			continue   # the focus ring has the very end
		var seg := lengths.bsearch(s) - 1
		seg = clampi(seg, 0, _trail_path.size() - 2)
		var a := _trail_path[seg]
		var b := _trail_path[seg + 1]
		var span := maxf(lengths[seg + 1] - lengths[seg], 0.001)
		var at := a.lerp(b, (s - lengths[seg]) / span)
		var dir := _flat(b - a).normalized()
		if dir == Vector3.ZERO:
			continue
		var size := clampf(minf(s - TRAIL_SKIP, from_end) / TRAIL_FADE, 0.25, 1.0)
		var basis := Basis.looking_at(dir, Vector3.UP).scaled_local(Vector3(0.85, 1.0, 1.5) * size)
		at += dir.cross(Vector3.UP) * side * 0.16
		mm.set_instance_transform(n, Transform3D(basis, at + Vector3(0.0, 0.05, 0.0)))
		n += 1
	mm.visible_instance_count = n

static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)

func _keys(s: String) -> String:
	return s.format({
		"interact": "[%s]" % InputMode.key("interact"), "move": "[%s]" % InputMode.key("move"),
		"drop": "[%s]" % InputMode.key("drop"), "throw": "[%s]" % InputMode.key("throw")})
