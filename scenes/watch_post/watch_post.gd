class_name WatchPost
extends StaticBody3D

# Watch post behind the wall (GameState.posts, GDD §5.6) — "I set the people by their
# families with their swords, their spears, and their bows" (Neh. 4:13). A station, not
# a tower you place and forget:
#   1. bare footing: bring timber, then work it up like a wall stage → the post stands
#      and a slinger climbs up
#   2. standing: it takes sling stones (a stone load = SHOTS_PER_LOAD throws). The
#      slinger chips at the nearest enemy in range while stones last — too weak to hold
#      a flank alone, a sling hit staggers, so it slows them for whoever comes
# Stone for the post is stone not in the wall: that is the choice.
# A new stretch of wall starts with bare footings again (reset on section change).
# Implements the build-site interface players use (see wall_section.gd), with
# is_target always false so the day's focus, the "Next:" line and the bots pass it by.
# Server owns built / pending / ammo; clients mirror them via the Sync child.

const SLINGER_SCRIPT := preload("res://scenes/shared/character_rig.gd")
const SLING_STONE    := preload("res://scenes/sling_stone/sling_stone.tscn")

const WOOD_COST_BY_CREW := [1, 2, 2]   # loads for crews of 1, 2, 3+
const WORK_TIME       := 2.5
const SOLO_WORK_MULT  := 0.75
const SHOTS_PER_LOAD  := 8
const MAX_AMMO        := 24            # three loads' worth
const RANGE           := 12.0
const FIRE_CD         := 1.0
const DAMAGE          := 20.0          # a scout takes two, a brute five or six
const COVER_RANGE     := 8.0           # a fed post shields the wall within this reach
const COVER_HARM      := 0.6           # blows that wall takes, ×
const BATTER_BIAS     := 6.0           # metres a wall-batterer counts nearer when picking a target
const FOOT            := Vector3(1.5, 0.0, 1.5)
const DECK_Y          := 1.75
const LABEL_RANGE     := 6.0
const LABEL_POLL      := 0.2
const WOOD_COLOR      := Color(0.52, 0.34, 0.18)
const BASKET_COLOR    := Color(0.66, 0.52, 0.30)
const STONE_COLOR     := Color(0.72, 0.70, 0.65)
const TARGET_COLOR    := Color(0.62, 0.50, 0.34)
const LINE_COLOR      := Color(0.93, 0.90, 0.82)   # lime and cord marking out the plot
const SLINGER_COLOR   := Color(0.44, 0.55, 0.24)
const TERRACOTTA      := Color(0.76, 0.38, 0.24)
const STONE_SLOTS     := 9

signal stage_changed(new_stage: int)

var is_target := false   # never one of the day's units

var built := false:
	set(value):
		if value == built:
			return
		built = value
		if is_node_ready():
			if value:
				Sfx.play("build", global_position)
			_refresh()
			stage_changed.emit(1 if value else 0)
var pending := 0:
	set(value):
		pending = value
		if is_node_ready():
			_update_label()
var ammo := 0:
	set(value):
		ammo = value
		if is_node_ready():
			_show_ammo()
			_update_label()

var _frame: Node3D
var _footing: Node3D
var _stones: MultiMeshInstance3D
var _pennant: MultiMeshInstance3D
var _ring: MeshInstance3D
var _slinger: CharacterRig
var _label: WorldTag
var _label_poll := 0.0
var _work: BuildWork
var _cd := 0.0
var _facing := "up"

@onready var _col: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	_build_footing()
	_build_frame()
	_build_label()
	_work = BuildWork.new()
	_work.name = "Work"
	_work.position = Vector3(0, DECK_Y + 1.2, 0)
	add_child(_work)
	_prime_work()
	GameState.crew_changed.connect(_prime_work.unbind(1))
	GameState.crew_changed.connect(_update_label.unbind(1))
	InputMode.changed.connect(_update_label.unbind(1))
	GameState.section_changed.connect(_on_section_changed.unbind(1))
	GameState.rules_changed.connect(_refresh)
	NetworkManager.add_sync(self, [^".:built", ^".:pending", ^".:ammo", ^"Work:progress"])
	_refresh()

func _on_section_changed() -> void:
	if multiplayer.is_server():
		reset_slot()
	_refresh()

## Not on the first stretch (GameState.first_stretch): the wall comes first, posts from the Fish Gate
func _enabled() -> bool:
	return GameState.posts and not GameState.first_stretch()

# Shown / in the groups only while the rule is on; solid only once it stands
func _refresh() -> void:
	var on := _enabled()
	visible = on
	_col.set_deferred("disabled", not on or not built)   # bare footing: walk over it
	if on:
		add_to_group("build_sites")
		add_to_group("watch_posts")
	else:
		remove_from_group("build_sites")
		remove_from_group("watch_posts")
	_frame.visible = built
	_footing.visible = not built
	_show_ammo()
	_update_label()

func _process(delta: float) -> void:
	_label_poll -= delta
	if _label_poll <= 0.0:
		_label_poll = LABEL_POLL
		var near := Player.local != null and distance_to_point(Player.local.global_position) < LABEL_RANGE
		var working := _work.progress > 0.0
		# Out of stones while the enemy comes: say so from anywhere
		var empty := built and ammo == 0 and GameState.phase == GameState.Phase.WORK
		_label.visible = visible and not working and (near or empty)
		_label.pulse = empty
		_label.modulate.a = 1.0 if near or empty else WorldTag.DIM
		_ring.visible = visible and built and ammo > 0 and near
	if multiplayer.is_server():
		_tick_fire(delta)

# ── Slinger (server) ───────────────────────────────────────

func _tick_fire(delta: float) -> void:
	_cd -= delta
	if _cd > 0.0 or not built or ammo <= 0 or GameState.phase != GameState.Phase.WORK or not _enabled():
		return
	var target := _pick_target()
	if target == null:
		return
	_cd = FIRE_CD
	ammo -= 1
	_throw.rpc(target.get_path())

func _pick_target() -> Node3D:
	var best: Node3D = null
	var best_d := RANGE
	for e: Node3D in get_tree().get_nodes_in_group("enemies"):
		var d := Vector2(e.global_position.x - global_position.x, e.global_position.z - global_position.z).length()
		if d >= RANGE:
			continue
		# Foes at the wall first: that is what the post is there to stop
		var score: float = d - (BATTER_BIAS if e.is_battering() else 0.0)
		if score < best_d:
			best_d = score
			best = e
	return best

## Fed and standing: the wall near it takes fewer blows (WallSection.take_damage)
func covers(point: Vector3) -> bool:
	if not built or ammo <= 0 or not _enabled():
		return false
	return Vector2(point.x - global_position.x, point.z - global_position.z).length() <= COVER_RANGE

# Every peer: the slinger swings and the stone flies; the server's copy deals damage
@rpc("authority", "call_local", "reliable")
func _throw(target_path: NodePath) -> void:
	var target := get_node_or_null(target_path) as Node3D
	if target == null or _slinger == null:
		return
	_facing = CharAnim.dir_from_velocity(target.global_position - global_position, _facing)
	_slinger.play("slash_" + _facing)
	Sfx.play("throw", global_position)
	var stone := SLING_STONE.instantiate()
	get_tree().current_scene.add_child(stone)
	stone.global_position = global_position + Vector3(0, DECK_Y + 1.6, 0)
	stone.shooter = 0
	stone.init(target, target.global_position, DAMAGE)
	_slinger.animation_finished.connect(func():
		if is_instance_valid(_slinger):
			_slinger.play("idle_" + _facing), CONNECT_ONE_SHOT)

# ── Build-site interface (server mutates) ──────────────────

func _cost() -> int:
	return WOOD_COST_BY_CREW[clampi(GameState.cost_crew(), 1, WOOD_COST_BY_CREW.size()) - 1]

func needs(kind: String) -> bool:
	if not _enabled():
		return false
	if not built:
		return kind == "wood" and pending < _cost()
	return kind == "stone" and ammo <= MAX_AMMO - SHOTS_PER_LOAD

func next_need() -> String:
	if not built:
		return "wood" if pending < _cost() else ""
	return "stone" if needs("stone") else ""

func deposit(kind: String, _amount: int) -> bool:
	if not multiplayer.is_server() or not needs(kind):
		return false
	if built:
		ammo += SHOTS_PER_LOAD
		_loads += 1
	else:
		pending += 1
	return true

func can_build() -> bool:
	return _enabled() and not built and pending >= _cost()

func try_build() -> bool:
	if not multiplayer.is_server() or not can_build():
		return false
	pending = 0
	built = true
	print("WatchPost: %s raised on day %d" % [name, GameState.current_day])
	return true

func is_complete() -> bool:
	return built

## Player: why a load was refused here
func refusal(kind: String) -> String:
	if not built:
		return "The post needs timber" if kind != "wood" else "Enough timber. {interact} to raise it"
	if kind != "stone":
		return "The slinger wants stone for his sling"
	return "The slinger has stones enough"

func work() -> BuildWork:
	return _work

func work_material() -> String:
	return "wood" if can_build() else ""

var _loads := 0   # server: stone loads fed this section (for the log)

func reset_slot() -> void:
	if _loads > 0 or built:
		print("WatchPost: %s — %d stone loads fed" % [name, _loads])
	_loads = 0
	pending = 0
	ammo = 0
	built = false
	_work.reset()

## Server: "Set the watch" (GameState.BOONS) — the post stands from dawn, two loads in
func fortify() -> void:
	if not multiplayer.is_server() or not GameState.posts:
		return
	built = true
	ammo = SHOTS_PER_LOAD * 2
	_loads = 2

func repair(_fraction: float) -> void:
	pass

func _prime_work() -> void:
	if _work != null:
		_work.work_time = WORK_TIME * GameState.solo_mult(SOLO_WORK_MULT)

func distance_to_point(p: Vector3) -> float:
	var local := to_local(p)
	var half := FOOT * 0.5
	var clamped := Vector3(clampf(local.x, -half.x, half.x), 0.0, clampf(local.z, -half.z, half.z))
	return Vector2(local.x - clamped.x, local.z - clamped.z).length()

func approach_point(from: Vector3, standoff: float) -> Vector3:
	var local := to_local(from)
	var half := FOOT * 0.5
	var clamped := Vector3(clampf(local.x, -half.x, half.x), 0.0, clampf(local.z, -half.z, half.z))
	var out := Vector3(local.x - clamped.x, 0.0, local.z - clamped.z)
	if out.length_squared() < 0.0001:
		out = Vector3(0, 0, 1)
	var p := to_global(clamped + out.normalized() * standoff)
	p.y = from.y
	return p

# ── Visuals ────────────────────────────────────────────────

# Before it stands: four stakes on a marked square where the post will go
func _build_footing() -> void:
	_footing = Node3D.new()
	add_child(_footing)
	# The plot, scraped bare and lined out in lime (the floor's top is at y 0.1)
	var ground := _Parts.new()
	ground.add(Vector3(FOOT.x, 0.02, FOOT.z), Vector3(0, 0.1, 0), TARGET_COLOR)
	for s: float in [-1.0, 1.0]:
		ground.add(Vector3(FOOT.x + 0.08, 0.025, 0.08), Vector3(0, 0.11, s * FOOT.z * 0.5), LINE_COLOR)
		ground.add(Vector3(0.08, 0.025, FOOT.z), Vector3(s * FOOT.x * 0.5, 0.11, 0), LINE_COLOR)
	var flat := ground.build(Chunky.material(0.0))
	flat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_footing.add_child(flat)
	# A stake at each corner and a cord run round them, a flat footing stone under each
	var parts := _Parts.new()
	for sx: float in [-0.6, 0.6]:
		for sz: float in [-0.6, 0.6]:
			parts.add(Vector3(0.12, 0.6, 0.12), Vector3(sx, 0.4, sz), WOOD_COLOR.darkened(0.1))
			parts.add(Vector3(0.36, 0.1, 0.36), Vector3(sx, 0.13, sz), STONE_COLOR.darkened(0.08))
	for s: float in [-0.6, 0.6]:
		parts.add(Vector3(1.2, 0.03, 0.03), Vector3(0, 0.55, s), LINE_COLOR)
		parts.add(Vector3(0.03, 0.03, 1.2), Vector3(s, 0.55, 0), LINE_COLOR)
	_footing.add_child(parts.build(Chunky.wood_material(0.02)))

# Standing: four legs, braces, a plank deck, a ladder, a basket of stones, the slinger
func _build_frame() -> void:
	_frame = Node3D.new()
	add_child(_frame)
	var parts := _Parts.new()
	var leg := 0.62
	var h := DECK_Y + 0.5
	for sx: float in [-leg, leg]:
		for sz: float in [-leg, leg]:
			parts.add(Vector3(0.18, h, 0.18), Vector3(sx, h * 0.5, sz), WOOD_COLOR.darkened(0.08))
	for sz: float in [-leg, leg]:
		parts.add(Vector3(1.6, 0.1, 0.1), Vector3(0, DECK_Y * 0.5, sz), WOOD_COLOR.darkened(0.18), Vector3(0, 0, 0.8))
	parts.add(Vector3(1.6, 0.14, 1.6), Vector3(0, DECK_Y, 0), WOOD_COLOR.lightened(0.1))
	parts.add(Vector3(1.6, 0.08, 0.08), Vector3(0, DECK_Y + 0.5, -leg), WOOD_COLOR)   # rail, enemy side
	# Ladder on the city side
	for dx: float in [-0.22, 0.22]:
		parts.add(Vector3(0.07, DECK_Y + 0.3, 0.07), Vector3(dx, (DECK_Y + 0.3) * 0.5, leg + 0.3),
			WOOD_COLOR.lightened(0.05), Vector3(-0.28, 0, 0))
	for r in 5:
		var y := (r + 1) * DECK_Y / 6.0
		parts.add(Vector3(0.5, 0.05, 0.05), Vector3(0, y, leg + 0.3 + 0.28 * (0.5 - y / (DECK_Y + 0.3)) * 1.2), WOOD_COLOR.lightened(0.05))
	parts.add(Vector3(0.44, 0.26, 0.44), Vector3(0.45, DECK_Y + 0.2, 0.35), BASKET_COLOR)   # basket
	_frame.add_child(parts.build(Chunky.wood_material(0.03)))
	# Sling stones heaped in the basket — the heap follows the ammo (visible_instance_count)
	var stones := _Parts.new()
	for i in STONE_SLOTS:
		stones.add(Vector3(0.13, 0.11, 0.13),
			Vector3(0.36 + (i % 3) * 0.09, DECK_Y + 0.37 + (i / 3) * 0.07, 0.28 + (i % 2) * 0.12), STONE_COLOR)
	_stones = stones.build(Chunky.material(0.05))
	_frame.add_child(_stones)
	# A pennant on the rail while the post is fed: the wall around it is covered
	var flag := _Parts.new()
	flag.add(Vector3(0.05, 0.9, 0.05), Vector3(-leg, DECK_Y + 0.95, leg), WOOD_COLOR.darkened(0.15))
	flag.add(Vector3(0.5, 0.28, 0.03), Vector3(-leg + 0.27, DECK_Y + 1.25, leg), TERRACOTTA)
	_pennant = flag.build(Chunky.material(0.02))
	_frame.add_child(_pennant)
	# Cover reach, drawn on the ground when you come near
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = COVER_RANGE - 0.08
	torus.outer_radius = COVER_RANGE
	torus.rings = 48
	torus.ring_segments = 4
	_ring.mesh = torus
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color = Color(TERRACOTTA, 0.5)
	_ring.material_override = ring_mat
	_ring.scale = Vector3(1, 0.02, 1)
	_ring.position = Vector3(0, 0.12, 0)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)
	# The slinger: a townsman at his family's post (Neh. 4:13)
	_slinger = SLINGER_SCRIPT.new()
	_frame.add_child(_slinger)
	_slinger.position = Vector3(-0.15, DECK_Y + 0.07, -0.1)
	var look := CharacterRig.worker_look(1, SLINGER_COLOR)
	look["tool"] = false
	_slinger.setup(look, 0.9)
	_slinger.set_ring_color(Color(0, 0, 0, 0))
	_slinger.play("idle_up")

func _show_ammo() -> void:
	if _pennant != null:
		_pennant.visible = ammo > 0
	if _stones != null:
		_stones.multimesh.visible_instance_count = ceili(float(ammo) / MAX_AMMO * STONE_SLOTS)

# Chunky blocks batched into one MultiMesh (like the wall's courses)
class _Parts:
	var xf: Array[Transform3D] = []
	var colors: Array[Color] = []

	func add(size: Vector3, pos: Vector3, color: Color, rot := Vector3.ZERO) -> void:
		xf.append(Transform3D(Basis.from_euler(rot).scaled_local(size), pos))
		colors.append(color)

	func build(mat: Material) -> MultiMeshInstance3D:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = Chunky.unit_block()
		mm.instance_count = xf.size()
		for i in xf.size():
			mm.set_instance_transform(i, xf[i])
			mm.set_instance_color(i, colors[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		return mmi

# ── Label ──────────────────────────────────────────────────

func _build_label() -> void:
	_label = WorldTag.make(WorldTag.Kind.SITE)
	_label.stack_name = true
	_label.position = Vector3(0, DECK_Y + 1.9, 0)
	_label.visible = false
	add_child(_label)

# World-tag markup like the wall's ("Wood 1/2", "Build  [E]"); stones count in loads
func _update_label() -> void:
	if _label == null:
		return
	# Bare footing is flat on the ground: a short one-line sign low over it. Once the
	# tower stands the sign rides above the deck.
	_label.position.y = 0.5 if not built else DECK_Y + 1.9
	var lines: PackedStringArray = [tr("Watch post") if not built else tr("Slinger")]
	if not built:
		lines.append("Build  [%s]" % InputMode.key("interact") if can_build() 			else "Wood %d/%d" % [mini(pending, _cost()), _cost()])
	else:
		if ammo == 0:
			lines[0] = tr("Out of sling stones")
		lines.append("Stone %d/%d" % [ceili(float(ammo) / SHOTS_PER_LOAD), MAX_AMMO / SHOTS_PER_LOAD])
	# A short name stacks to fit the narrow post; a long one would tower, so it stays a line
	_label.stack_name = built and ammo > 0
	_label.text = "
".join(lines)
