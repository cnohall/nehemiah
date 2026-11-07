class_name Calls
extends Node3D

# The call (GDD §5.25): one button, read from where it points. "Cover me!" while you work a
# wall, "Foes here!" at a foe, "Stone here!" at a site that wants stone, "Build here!" at one
# with all its loads in, "Here!" anywhere else. Everyone sees a small standard with the words
# (and an off-screen pointer); the nearest free bot takes it as an order (BotBrain.give_order)
# and drops what it was doing. Alone, the bots become a crew that answers (Neh. 4:13, the
# people set by their families); in company it is the shout that online play lacks.
# Server reads the spot and picks the bot; every peer shows the call. `-- --no-calls` (host)
# turns it off.

const CALL_TIME    := 8.0     # the standard stands this long (a "hold" order lasts as long)
const ORDER_TIME   := 20.0    # a bot keeps to any other order at most this long
const COOLDOWN     := 1.2     # per caller (s)
const FOE_RANGE    := 6.0     # a foe this near the spot → "Foes here!"
const SITE_RANGE   := 4.0     # a site this near the spot → bring its load / build it
const BUSY_PENALTY := 8.0     # a bot at work counts as this much further (m)…
const LOADED_BONUS := 10.0    # …one already carrying the wanted load this much nearer
const RING_SIZE    := 3.2
const MARKER_SHADER := preload("res://assets/shaders/ground_marker.gdshader")
const POLE := Color(0.40, 0.29, 0.18)
const CLOTH := Color(0.93, 0.88, 0.74)
const BRING := { "stone": "Stone here!", "wood": "Timber here!", "mortar": "Mortar here!",
	"beam": "A beam here!", "lime": "Lime here!", "water": "Water here!" }

var on: bool = "--no-calls" not in OS.get_cmdline_user_args()
var _ready_at := {}       # worker id → msec it may call again
var _last_root: Node3D    # the standard _show just raised (a "hold" order walks to it)

func _ready() -> void:
	add_to_group("calls")

## Server: `worker` called at `at`. Reads the spot, raises the standard on every peer and hands
## the order to the nearest free bot.
func request(worker: Player, at: Vector3) -> void:
	if not multiplayer.is_server() or not on or GameState.phase != GameState.Phase.WORK \
			or GameState.attract or GameState.festival:
		return
	var now := Time.get_ticks_msec()
	if now < _ready_at.get(worker.worker_id(), 0):
		return
	_ready_at[worker.worker_id()] = now + int(COOLDOWN * 1000.0)
	at = Vector3(at.x, 0.0, at.z)
	var order := _read(worker, at)
	_show.rpc(at, worker.slot_color, order["line"])
	if order["kind"] == "hold":
		order["target"] = _last_root   # freed with the standard, which ends the order
	var bot := _answerer(order, at)
	if bot != null:
		order["until"] = now + int(ORDER_TIME * 1000.0)
		bot.brain.give_order(order)
	elif get_tree().get_nodes_in_group("players").any(func(p): return p.brain != null):
		worker._tell("Nobody free to answer")

# What the spot asks for, in order: cover the caller at work, a foe, a site's load, its work
func _read(worker: Player, at: Vector3) -> Dictionary:
	if worker.building_site != null:
		return { "kind": "cover", "line": "Cover me!", "target": worker }
	for e: Node3D in get_tree().get_nodes_in_group("enemies"):
		if Vector2(e.global_position.x - at.x, e.global_position.z - at.z).length() < FOE_RANGE:
			return { "kind": "hold", "line": "Foes here!", "arrive": 5.0 }
	var site := _site_near(at)
	if site != null:
		var need: String = site.next_need()
		if not need.is_empty():
			return { "kind": "bring", "line": BRING.get(need, "Bring it here!"), "target": site, "material": need }
		if site.can_build():
			return { "kind": "work", "line": "Build here!", "target": site }
	return { "kind": "hold", "line": "Here!", "arrive": 1.8 }

# Walls, gates, watch posts and the mortar trough: the nearest within SITE_RANGE
func _site_near(at: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := SITE_RANGE
	for group in ["build_sites", "supply_piles"]:
		for s: Node3D in get_tree().get_nodes_in_group(group):
			if not s.has_method("next_need") or not s.is_visible_in_tree():
				continue
			var d: float = s.distance_to_point(at) if s.has_method("distance_to_point") else s.global_position.distance_to(at)
			if d < best_d:
				best_d = d
				best = s
	return best

# The nearest bot free to answer: not down, led off, reviving or on a beam
func _answerer(order: Dictionary, at: Vector3) -> Player:
	var from: Vector3 = order["target"].global_position if order["kind"] == "cover" else at
	var best: Player = null
	var best_d := INF
	for p: Player in get_tree().get_nodes_in_group("players"):
		if p.brain == null or p == order.get("target") or p.downed or p.is_led() \
				or p.helping_id != 0 or p.carried_kind == "beam" or p.brain.reviving():
			continue
		var d := Vector2(p.global_position.x - from.x, p.global_position.z - from.z).length()
		if p._work_site != null:
			d += BUSY_PENALTY
		if order["kind"] == "bring" and p.carried_kind == order["material"]:
			d -= LOADED_BONUS
		if d < best_d:
			best_d = d
			best = p
	return best

@rpc("authority", "call_local", "reliable")
func _show(at: Vector3, color: Color, line: String) -> void:
	Sfx.play("alert")
	get_tree().call_group("offscreen_alerts", "ping", at, color, line.trim_suffix("!"), CALL_TIME)
	_raise_standard(at, color, line)

# A short pole with a pennant in the caller's colour, a ring on the ground and the words over it
func _raise_standard(at: Vector3, color: Color, line: String) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = at
	_last_root = root
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.04
	cyl.bottom_radius = 0.06
	cyl.height = 2.2
	pole.mesh = cyl
	pole.material_override = Horn._mat(POLE)
	pole.position = Vector3(0, 1.1, 0)
	root.add_child(pole)
	var flag := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.7, 0.42, 0.04)
	flag.mesh = box
	flag.material_override = Horn._mat(color.lerp(CLOTH, 0.15))
	flag.position = Vector3(0.37, 1.95, 0)
	root.add_child(flag)
	var ring := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.orientation = PlaneMesh.FACE_Y
	quad.size = Vector2(RING_SIZE, RING_SIZE)
	ring.mesh = quad
	var rm := ShaderMaterial.new()
	rm.shader = MARKER_SHADER
	rm.set_shader_parameter("shadow_color", Color(0, 0, 0, 0))
	rm.set_shader_parameter("ring_color", Color(color, 0.85))
	rm.set_shader_parameter("ring_radius", 0.42)
	rm.set_shader_parameter("ring_width", 0.05)
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position.y = 0.14
	root.add_child(ring)
	var tag := Label3D.new()
	tag.text = tr(line)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.pixel_size = 0.005
	tag.font_size = 40
	tag.outline_size = 14
	tag.modulate = Color(0.98, 0.93, 0.78)
	tag.outline_modulate = Color(0.16, 0.11, 0.08)
	tag.position = Vector3(0, 2.55, 0)
	root.add_child(tag)
	# Pop up, then fold away (as the horn's standard does, quicker)
	root.scale = Vector3(1, 0.01, 1)
	var tw := root.create_tween()
	tw.tween_property(root, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(CALL_TIME)
	tw.tween_property(root, "scale", Vector3(1, 0.01, 1), 0.25)
	tw.tween_callback(root.queue_free)
