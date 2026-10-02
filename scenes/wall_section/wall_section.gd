extends StaticBody3D

# Buildable wall slot, also used by gate pillars and watchtowers.
# Server owns stage / health / pending; clients mirror stage + pending via the Sync child.
# Footprint comes from the CollisionShape3D box; visuals are generated per stage.

signal stage_changed(new_stage: int)
signal destroyed

enum Stage { EMPTY, FRAMED, STACKED, MORTARED }

# Cost of reaching each stage, by crew size (1, 2, 3+). A solo builder needs fewer
# trips; a full crew does the full job.
const MATERIAL_COST_BY_CREW := [
	{ Stage.FRAMED: { "wood": 2 }, Stage.STACKED: { "stone": 4 }, Stage.MORTARED: { "mortar": 1 } },
	{ Stage.FRAMED: { "wood": 3 }, Stage.STACKED: { "stone": 5 }, Stage.MORTARED: { "mortar": 2 } },
	{ Stage.FRAMED: { "wood": 3 }, Stage.STACKED: { "stone": 6 }, Stage.MORTARED: { "mortar": 2 } },
]
# With hands-on building the labour moves from hauling to working the wall: one load
# less per stage (never below one), paid back in work time
const ACTIVE_BUILD_DISCOUNT := 1
# Seconds of work for one worker to raise each stage (BuildWork); a solo builder is quicker
const WORK_TIME := { Stage.FRAMED: 2.0, Stage.STACKED: 3.0, Stage.MORTARED: 2.0 }
const SOLO_WORK_MULT := 0.75
# "beams" twist (Neh. 3:3 "they laid its beams"): framing takes long beams, carried in
# pairs, instead of loose timber
const BEAM_COST_BY_CREW    := [1, 2, 2]
# "thick" twist (Broad Wall, Neh. 3:8): plain stretches built double-thick — two faces
# with a rubble core between them. The stone stage is two jobs: the outer face, facing
# the foe, then the inner face; the core is filled and mortared last. More stone and
# mortar, room for one more pair of hands, and it takes half the blows.
const THICK_DEPTH          := 2.2
const THICK_FACE_DEPTH     := 0.7    # how deep each face of courses is; the core fills between
const THICK_FACES          := ["Outer face", "Inner face"]
const THICK_EXTRA          := { Stage.STACKED: { "stone": 2 }, Stage.MORTARED: { "mortar": 1 } }
const THICK_WORK_MULT      := 1.3
const THICK_FACE_WORK      := 0.6    # one face's share of the stone stage's work time
const CORE_COLOR           := Color(0.50, 0.44, 0.36)   # rubble between the faces
const THICK_HARM           := 0.5    # a double-thick piece takes half of every blow
const THIN_MAX_DEPTH       := 1.0    # only plain walls thicken, not towers or pillars
# Per-unit recipes (GDD §6.4, the "ruins" twist): not every unit starts from bare footing.
# A section's "recipes" map a unit's node name to RECIPE_OLD (old courses still stand — the
# stone stage is done, only mortar is wanted) or RECIPE_BURNED (charred framing to pull
# down first: a job of work alone, no materials, before the usual stages). Pulling it down
# only brings the timbers to the ground — each charred length is then a load to carry off the
# footing (DEBRIS_*), and the stages wait until the pad is bare.
const RECIPE_OLD           := "old"
const RECIPE_BURNED        := "burned"
const CLEAR_WORK_TIME      := 5.0
const DEBRIS_BASE          := 2      # charred loads left by the pulling down: this + crew size (max 3)
const DEBRIS_ON_PAD        := 2.4    # a load closer than this to the footing still fouls it
const DEBRIS_DUMP_GAP      := 5.0    # the tip, this far past the inner face
const DEBRIS_DUMP_RADIUS   := 1.8    # a worker this close to the tip, load in hand, tips it out by himself
const DEBRIS_ITEM := preload("res://scenes/dropped_item/dropped_item.tscn")
const CHAR_COLOR           := Color(0.17, 0.14, 0.12)
const MAX_HEALTH           := 150.0
const DEGRADE_HEALTH_RATIO := 0.5
# Mending (GDD §5.17): a finished wall battered below REPAIR_BELOW of its health takes one
# load of mortar and a short spell of work to win REPAIR_GAIN of it back — before it falls
const REPAIR_BELOW         := 0.7
const REPAIR_GAIN          := 0.35
const REPAIR_WORK_TIME     := 2.0
const REPAIR_ALERT_BELOW   := 0.4    # the label shows from afar once a wall is this far gone
const LABEL_RANGE          := 6.0
const LABEL_POLL           := 0.2

const COURSE_H     := 0.5    # stone course height
const MERLON_W     := 0.7
const MERLON_H     := 0.45
const GAP_ROUGH    := 0.06    # joint width before mortar
const GAP_MORTARED := 0.012

const STONE_COLOR  := Palette.WALL_STONE   # Jerusalem limestone — pale and cool against the ochre ground so the wall leads
const MORTAR_COLOR := Color(0.62, 0.60, 0.60)
const EARTH_COLOR  := Color(0.55, 0.45, 0.30)
const TARGET_COLOR := Color(0.86, 0.58, 0.22)   # today's work — amber footing
const WOOD_COLOR   := Color(0.52, 0.34, 0.18)
const TIMBER_WIDTH := 3.4   # squared scaffold timber, as a multiple of the old pole radius


@export var stage: Stage = Stage.EMPTY:
	set(value):
		if value == stage:
			return
		if is_node_ready() and not decorative:
			Sfx.play("build" if value > stage else "wall_crumble", global_position)
			# Felt by whoever is close: a thud when a course goes up, a jolt when one falls
			if GameState.phase == GameState.Phase.WORK and _local_player_near():
				get_tree().call_group("camera_rig", "shake", 0.15 if value > stage else 0.45)
		stage = value
		if is_node_ready():
			_update_visuals()
			_dust_puff()
			_bounce()
			stage_changed.emit(stage)

# Thick walls: faces of the stone stage already standing (0 outer next, 1 inner next, 2 both).
# Replicated by the Sync; the preview and the standing wall both show them.
var face := 0:
	set(value):
		if value == face:
			return
		face = value
		if is_node_ready() and not decorative:
			_prime_work()
			_update_visuals()

# Burned recipe: false until the charred framing is pulled down. Replicated by the Sync.
var cleared := true:
	set(value):
		if value == cleared:
			return
		cleared = value
		if is_node_ready() and not decorative:
			_prime_work()
			_update_visuals()

# Burned recipe, second half: the framing is down and its timbers lie on the footing until
# they are carried clear. Replicated by the Sync.
var pulled := false:
	set(value):
		if value == pulled:
			return
		pulled = value
		if is_node_ready() and not decorative:
			_label_poll = 0.0
			_update_visuals()

# Outer stretches repaired by other families (Neh. 3) — not networked, not buildable.
# They rise with the campaign (rubble on day 1, finished by day 52 — "the whole wall
# was joined together to half its height", Neh. 4:6) and always block movement.
@export var decorative := false

# Server marks the units that must be finished today (DayDirector)
var is_target := false:
	set(value):
		is_target = value
		if is_node_ready():
			_foundation_mat.albedo_color = TARGET_COLOR if value and not GameState.attract else EARTH_COLOR
			_update_label()

# Replicated; a drop shakes the stones on every peer so an attack reads at a glance
var health: float = MAX_HEALTH:
	set(value):
		if value < health and is_node_ready():
			_shake()
			Sfx.play("wall_hit", global_position)
			last_hit_msec = Time.get_ticks_msec()
		health = value
		if is_node_ready():
			_prime_work()   # the mending job opens and closes with the damage
# Local clock of the last hit seen on this peer — drives the HUD's off-screen alert
var last_hit_msec := -100000
# Materials deposited here, waiting to be built
var pending: Dictionary = _empty_pending():
	set(value):
		pending = value
		if is_node_ready():
			_update_label()

var _size: Vector3
var _center: Vector3
var _visual: Node3D
var _label: WorldTag
var _foundation_mat: StandardMaterial3D
var _label_poll := 0.0
var _juice_tween: Tween
var _work: BuildWork
# The next stage going up while workers are at it, revealed block by block
var _preview: Node3D
var _preview_skip := 0
var _previewing := false   # _build_stage is drawing the next stage's preview, not the standing wall

@onready var _col: CollisionShape3D = $CollisionShape3D

func _enter_tree() -> void:
	# Before ready, so the starting stage doesn't play a dust puff
	if decorative and not is_node_ready():
		_follow_campaign(GameState.current_day)

func _ready() -> void:
	_size = (_col.shape as BoxShape3D).size
	_center = _col.position
	_visual = Node3D.new()
	add_child(_visual)
	_build_label()
	if decorative:
		set_process(false)
		GameState.day_changed.connect(_follow_campaign)
	else:
		add_to_group("wall_sections")   # what enemies batter
		add_to_group("build_sites")     # what workers deliver to (walls + gate doors)
		GameState.section_changed.connect(_update_label.unbind(1))
		_work = BuildWork.new()
		_work.name = "Work"
		_work.position = Vector3(_center.x, _size.y + 0.9, _center.z)
		add_child(_work)
		_work.progress_changed.connect(_on_work_progress)
		InputMode.changed.connect(_update_label.unbind(1))
		_build_sync()
		GameState.crew_changed.connect(_update_label.unbind(1))
		GameState.crew_changed.connect(_prime_work.unbind(1))
		_prime_work()
		if _size.z < THIN_MAX_DEPTH:
			_col.shape = _col.shape.duplicate()   # the depth changes per section, per wall
			_base_depth = _size.z
			GameState.section_changed.connect(_apply_thickness.unbind(1))
			_apply_thickness(false)
	_update_visuals()

var _base_depth := 0.0

## Plain stretch: double-thick where the section calls for it
func _apply_thickness(redraw := true) -> void:
	var depth := THICK_DEPTH if GameState.has_twist("thick") else _base_depth
	if is_equal_approx(depth, _size.z):
		return
	_size.z = depth
	(_col.shape as BoxShape3D).size.z = depth
	_prime_work()
	if redraw:
		_update_visuals()

func is_thick() -> bool:
	return _base_depth > 0.0 and GameState.has_twist("thick")

## This unit's recipe in the current section ("" = bare footing, like every other)
func recipe() -> String:
	return "" if decorative else GameState.get_current_section().get("recipes", {}).get(str(name), "")

## Burned recipe, charred framing still up (hands-on building only: the instant rule skips it)
func _clearing() -> bool:
	return not cleared and GameState.active_build and stage == Stage.EMPTY

## Burned recipe, framing down but its timbers still lie on the footing
func _hauling() -> bool:
	return _clearing() and pulled

## Where the debris goes: a tip on the city side of the footing (the outer face is -z)
func dump_point() -> Vector3:
	return to_global(Vector3(_center.x, 0.0, _center.z + _size.z * 0.5 + DEBRIS_DUMP_GAP))

## Charred loads still lying on the footing
func dump_marker() -> Node3D:
	var m := get_node_or_null("DebrisDump") as Node3D
	if m == null:
		m = Node3D.new()
		m.name = "DebrisDump"
		add_child(m)
		m.global_position = dump_point()
		# A scorched patch so the tip can be seen, only while there is rubbish to carry to it
		var disc := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = DEBRIS_DUMP_RADIUS
		mesh.bottom_radius = DEBRIS_DUMP_RADIUS
		mesh.height = 0.03
		disc.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.17, 0.14, 0.12, 0.55)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 1.0
		disc.material_override = mat
		disc.position.y = 0.04
		disc.visible = false
		m.add_child(disc)
	(m.get_child(0) as Node3D).visible = _hauling()
	return m

## Server: a load of charred timber carried onto the tip is tipped out — no drop to aim
func _tip_debris() -> void:
	var at := dump_point()
	for p: Node3D in get_tree().get_nodes_in_group("players"):
		if p.carried_kind == "debris" and Vector2(p.global_position.x - at.x, p.global_position.z - at.z).length() < DEBRIS_DUMP_RADIUS:
			p._set_carried.rpc("")

## A timber lifted off the pad but not yet set down elsewhere still counts as rubbish
func _debris_in_hand() -> bool:
	for p in get_tree().get_nodes_in_group("players"):
		if p.carried_kind == "debris":
			return true
	return false

func debris_on_pad() -> Array:
	return get_tree().get_nodes_in_group("dropped_items").filter(func(it: Node3D):
		return it.kind == "debris" and distance_to_point(it.global_position) < DEBRIS_ON_PAD)

func _process(delta: float) -> void:
	_label_poll -= delta
	if _label_poll > 0.0:
		return
	_label_poll = LABEL_POLL
	if multiplayer.is_server() and _hauling():
		_tip_debris()
		if debris_on_pad().is_empty() and not _debris_in_hand():
			cleared = true   # the pad is bare; the usual stages follow
			_dust_puff()
			_prime_work()
	if _hauling():
		dump_marker()   # shows the tip on every peer once the framing is down
		_update_label()   # the count of timbers left ticks down as they are carried clear
	elif has_node("DebrisDump"):
		(get_node("DebrisDump").get_child(0) as Node3D).visible = false
	var damaged := is_built() and health < MAX_HEALTH
	var working := _work != null and _work.progress > 0.0   # the bar and rising stones say it all
	var near := _local_player_near()
	var failing := repairing() and health < MAX_HEALTH * REPAIR_ALERT_BELOW   # about to fall — seen from afar
	_label.visible = not working and (failing or (is_target and not is_complete()) 		or ((stage != Stage.MORTARED or damaged) and near))
	# One site at a time says "here next"; the others step back
	var focus := SiteFocus.site() == self
	_label.pulse = focus
	_label.modulate.a = 1.0 if focus or near else WorldTag.DIM
	if damaged:
		_update_label()

static func _empty_pending() -> Dictionary:
	return { "stone": 0, "wood": 0, "mortar": 0, "beam": 0 }

# ── Deposit / Build (server) ───────────────────────────────

func deposit(kind: String, amount: int) -> bool:
	if not multiplayer.is_server() or not needs(kind):
		return false
	pending[kind] = pending.get(kind, 0) + amount
	_update_label()
	return true

func needs(kind: String) -> bool:
	if _clearing():
		return false
	if repairing():
		return kind == "mortar" and pending.get("mortar", 0) < 1
	var next := stage + 1
	if next > Stage.MORTARED:
		return false
	var cost: Dictionary = cost_for(next)
	return cost.has(kind) and pending.get(kind, 0) < cost[kind]

## A finished wall battered low enough to want mending (one load of mortar, then work)
func repairing() -> bool:
	return is_complete() and not decorative and health < MAX_HEALTH * REPAIR_BELOW

func cost_for(target_stage: int) -> Dictionary:
	var tier := clampi(GameState.crew_size, 1, MATERIAL_COST_BY_CREW.size()) - 1
	if target_stage == Stage.FRAMED and GameState.has_twist("beams"):
		return { "beam": BEAM_COST_BY_CREW[tier] }
	var cost: Dictionary = MATERIAL_COST_BY_CREW[tier][target_stage].duplicate()
	if GameState.active_build:
		for kind: String in cost:
			cost[kind] = maxi(1, cost[kind] - ACTIVE_BUILD_DISCOUNT)
	if is_thick():
		for kind: String in THICK_EXTRA.get(target_stage, {}):
			cost[kind] += THICK_EXTRA[target_stage][kind]
		if target_stage == Stage.STACKED:
			cost["stone"] = ceili(cost["stone"] / 2.0)   # each face is paid for on its own
	return cost

## BuildWork: the site that holds this progress
func work() -> BuildWork:
	return _work

## Material being worked into the next stage ("" when finished) — picks the strike sound
func work_material() -> String:
	if _clearing():
		return "wood"   # charred timbers — the carpenters' work
	if repairing():
		return "mortar"
	var next := stage + 1
	return "" if next > Stage.MORTARED else cost_for(next).keys()[0]

## Material still missing for the next stage ("" when finished)
func next_need() -> String:
	if _clearing():
		return ""
	if repairing():
		return "mortar" if needs("mortar") else ""
	var next := stage + 1
	if next > Stage.MORTARED:
		return ""
	var cost: Dictionary = cost_for(next)
	for kind: String in cost:
		if pending.get(kind, 0) < cost[kind]:
			return kind
	return ""

func can_build() -> bool:
	if _clearing():
		return not pulled   # pulling down is work; hauling is not
	if repairing():
		return pending.get("mortar", 0) >= 1
	var next := stage + 1
	if next > Stage.MORTARED:
		return false
	var cost: Dictionary = cost_for(next)
	for kind in cost:
		if pending.get(kind, 0) < cost[kind]:
			return false
	return true

func try_build() -> bool:
	if not multiplayer.is_server() or not can_build():
		return false
	if _clearing():
		pulled = true   # the framing is down; its timbers now lie on the footing
		_strew_debris()
		_dust_puff()
		return true
	if repairing():
		pending["mortar"] -= 1
		health = minf(MAX_HEALTH, health + MAX_HEALTH * REPAIR_GAIN)
		_dust_puff()
		return true
	var next := stage + 1
	var cost: Dictionary = cost_for(next)
	for kind in cost:
		pending[kind] -= cost[kind]
	if next == Stage.STACKED and is_thick():
		face += 1
		if face < THICK_FACES.size():
			_prime_work()   # the outer face stands; the inner one still wants its stone
			return true
	stage = next as Stage
	_prime_work()
	return true

## Server: the pulled-down timbers drop in a ring over the footing, each a load to carry off
func _strew_debris() -> void:
	var items := get_tree().current_scene.get_node_or_null("Items")
	if items == null:
		return
	var n := DEBRIS_BASE + mini(GameState.crew_size, 3)
	for i in n:
		var item: DroppedItem = DEBRIS_ITEM.instantiate()
		item.kind = "debris"
		var x := _center.x + (float(i) / n - 0.5) * _size.x * 0.8
		var z := _center.z + (0.35 if i % 2 == 0 else -0.35) * minf(_size.z, 1.6)
		var at := to_global(Vector3(x, 0.0, z))
		item.position = Vector3(at.x, Player.GROUND_Y, at.z)
		NetworkManager.gate_sync(item.get_node("MultiplayerSynchronizer"))
		items.add_child(item, true)

## Thick wall, stone stage: which face is being raised ("Outer face" / "Inner face"), else ""
func face_name() -> String:
	if is_thick() and stage + 1 == Stage.STACKED and face < THICK_FACES.size():
		return THICK_FACES[face]
	return ""

func _prime_work() -> void:
	if _work == null:
		return
	if _clearing():
		_work.work_time = CLEAR_WORK_TIME * (SOLO_WORK_MULT if GameState.crew_size == 1 else 1.0) / GameState.mod("clear")
		return
	if repairing():
		_work.work_time = REPAIR_WORK_TIME * (SOLO_WORK_MULT if GameState.crew_size == 1 else 1.0)
		return
	var next := stage + 1
	if next <= Stage.MORTARED:
		var thick_mult := 1.0
		if is_thick():
			thick_mult = THICK_WORK_MULT * (THICK_FACE_WORK if next == Stage.STACKED else 1.0)
		_work.work_time = WORK_TIME[next] * (SOLO_WORK_MULT if GameState.crew_size == 1 else 1.0) * thick_mult

# Returns how much of the next stage's required material is pending (0.0–1.0)
func get_build_progress() -> float:
	if _clearing():
		return 0.0
	var next := stage + 1
	if next > Stage.MORTARED:
		return 1.0
	var cost: Dictionary = cost_for(next)
	var kind: String = cost.keys()[0]
	return minf(float(pending.get(kind, 0)) / float(cost[kind]), 1.0)

## Decorative only: stage from how far the campaign has got. Each stretch is offset a
## few days so they don't all rise together. Pure function of the day, so every peer agrees.
func _follow_campaign(day: int) -> void:
	if GameState.festival:
		day = GameState.TOTAL_DAYS   # the festival comes after the wall is finished
	var t := (day - 1 + (hash(global_position.x) % 7) - 3) / float(GameState.TOTAL_DAYS - 1)
	var s := Stage.EMPTY
	if day >= GameState.TOTAL_DAYS or t >= 0.9:
		s = Stage.MORTARED
	elif t >= 0.5:
		s = Stage.STACKED
	elif t >= 0.2:
		s = Stage.FRAMED
	stage = s

func is_built() -> bool:
	return stage != Stage.EMPTY

func is_complete() -> bool:
	return stage == Stage.MORTARED

## Workers may climb over it (Player: CLIMB). Finished walls only, so a press at a
## half-built wall never hops you to the wrong side
func blocks_workers() -> bool:
	return is_complete()

# ── Day transitions (server) ───────────────────────────────

## New circuit section: back to bare foundations
func reset_slot() -> void:
	pending = _empty_pending()
	health = MAX_HEALTH
	var r := recipe()
	cleared = r != RECIPE_BURNED
	pulled = false
	face = 2 if r == RECIPE_OLD and is_thick() else 0
	stage = Stage.STACKED if r == RECIPE_OLD else Stage.EMPTY
	_work.reset()
	_prime_work()

## Overnight repair of part of the damage
func repair(fraction: float) -> void:
	health = minf(MAX_HEALTH, health + (MAX_HEALTH - health) * fraction)

# Distance from a world point to this section's footprint (not its centre —
# an enemy at the end of an 8 m wall is still touching it)
func distance_to_point(p: Vector3) -> float:
	var local := to_local(p) - _center
	var half := _size * 0.5
	var clamped := local.clamp(-half, half)
	return Vector2(local.x - clamped.x, local.z - clamped.z).length()

# Spot just outside the footprint on the side facing `from` — where an attacker stands
func approach_point(from: Vector3, standoff: float) -> Vector3:
	var local := to_local(from) - _center
	var half := _size * 0.5
	var clamped := local.clamp(-half, half)
	var out := Vector3(local.x - clamped.x, 0.0, local.z - clamped.z)
	if out.length_squared() < 0.0001:
		out = Vector3(0.0, 0.0, signf(local.z) if local.z != 0.0 else -1.0)
	var p := to_global(_center + clamped + out.normalized() * standoff)
	p.y = from.y
	return p

# ── Damage (server) ────────────────────────────────────────

func take_damage(amount: float) -> void:
	if stage == Stage.EMPTY:
		return
	if is_thick():
		amount *= THICK_HARM
	amount *= GameState.mod("harm")
	var at := to_global(_center)
	for post: WatchPost in get_tree().get_nodes_in_group("watch_posts"):
		if post.covers(at):
			amount *= WatchPost.COVER_HARM
			break
	health = clampf(health - amount, 0.0, MAX_HEALTH)
	if health == 0.0:
		_degrade()

func _degrade() -> void:
	pending = _empty_pending()
	health = MAX_HEALTH * DEGRADE_HEALTH_RATIO
	# A blow takes the stone stage back to the timber; a thick wall loses both faces
	# with it, and one knocked back from the mortar keeps its two
	if stage <= Stage.STACKED:
		face = 0
	stage = (stage - 1) as Stage
	_work.reset()
	_prime_work()
	# Knocked back to bare foundation — slot stays so it can be rebuilt
	if stage == Stage.EMPTY:
		destroyed.emit()

# ── Networking ─────────────────────────────────────────────

func _build_sync() -> void:
	NetworkManager.add_sync(self, [^".:stage", ^".:face", ^".:cleared", ^".:pulled", ^".:pending", ^".:health", ^".:is_target", ^"Work:progress"])

# ── Visuals ────────────────────────────────────────────────

func _update_visuals() -> void:
	for c in _visual.get_children():
		c.queue_free()
	_clear_preview()
	_col.set_deferred("disabled", stage == Stage.EMPTY and not decorative)
	_add_foundation()
	_build_stage(stage, _visual_rng())
	_update_label()

# Same seed every time, so a stage's preview lays exactly the blocks it will end up with
func _visual_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(global_position.snapped(Vector3.ONE * 0.1))
	return rng

# Every peer: workers' progress → the next stage rises in the order it's built
func _on_work_progress(value: float) -> void:
	var next := stage + 1
	if value <= 0.0 or next > Stage.MORTARED or _clearing():
		_clear_preview()
		return
	if _preview == null:
		_preview = Node3D.new()
		add_child(_preview)
		var real := _visual
		_visual = _preview
		_previewing = true
		_build_stage(next as Stage, _visual_rng())
		_previewing = false
		_visual = real
		# Pieces already standing in this stage are shown from the start
		match next:
			Stage.STACKED:
				# A thick wall's preview is just the face going up, all of it new
				_preview_skip = 0 if is_thick() else _first_multimesh_count(_visual)
			Stage.MORTARED:
				_preview_skip = 1 + _first_multimesh_count(_preview)   # mortar core + courses
			_:
				_preview_skip = 0
	BuildWork.reveal(_preview, value, _preview_skip)

func _clear_preview() -> void:
	if _preview != null:
		_preview.queue_free()
		_preview = null

static func _first_multimesh_count(root: Node) -> int:
	for c in root.get_children():
		if c is MultiMeshInstance3D:
			return c.multimesh.instance_count
	return 0

func _build_stage(s: Stage, rng: RandomNumberGenerator) -> void:
	var thick := is_thick()
	match s:
		Stage.EMPTY:
			_add_ruin(rng)  # broken footing, walkable
			if _clearing() and not pulled:
				_add_charred(rng)
		Stage.FRAMED:
			_add_box(Vector3(_size.x - 0.1, minf(COURSE_H, _size.y) - 0.04, _size.z - 0.14),
				Vector3(_center.x, 0.12 + minf(COURSE_H, _size.y) * 0.5, _center.z), Palette.STONE_JOINT)
			_add_courses(rng, minf(COURSE_H, _size.y), GAP_ROUGH)
			_add_scaffold(rng)
			if thick and face > 0:
				_add_faces(rng, _size.y, GAP_ROUGH, 1)   # the outer face is up, the inner one still open
		Stage.STACKED:
			if thick and _previewing:
				_add_faces(rng, _size.y, GAP_ROUGH, 1, face)   # the face going up now
				return
			_add_box(Vector3(_size.x - 0.1, _size.y - 0.04, _size.z - 0.14),
				_center, CORE_COLOR if thick else Palette.STONE_JOINT)
			if thick:
				_add_faces(rng, _size.y, GAP_ROUGH)
			else:
				_add_courses(rng, _size.y, GAP_ROUGH)
		Stage.MORTARED:
			_add_box(Vector3(_size.x - 0.12, _size.y - 0.05, _size.z - 0.12),
				_center, MORTAR_COLOR)
			if thick:
				_add_faces(rng, _size.y, GAP_MORTARED)
			else:
				_add_courses(rng, _size.y, GAP_MORTARED)
			_add_merlons()

func _add_foundation() -> void:
	var s := Vector3(_size.x + 0.35, 0.12, _size.z + 0.35)
	_foundation_mat = _add_box(s, Vector3(_center.x, 0.06, _center.z),
		TARGET_COLOR if is_target and not GameState.attract else EARTH_COLOR)  # the title backdrop stays unmarked

# Staggered courses of rough-cut blocks, one MultiMesh for the whole section
func _add_courses(rng: RandomNumberGenerator, height: float, gap: float, bands: Array = []) -> void:
	if bands.is_empty():
		bands = [[_center.z, _size.z]]
	var rows := maxi(1, roundi(height / COURSE_H))
	var row_h := height / rows
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var x0 := _center.x - _size.x * 0.5
	var y0 := 0.12
	for r in rows:
		for band: Array in bands:
			var x := x0
			var first := true
			while x < x0 + _size.x - 0.05:
				var blen := rng.randf_range(0.7, 1.25)
				if first and r % 2 == 1:
					blen *= 0.5  # stagger joints
				first = false
				blen = minf(blen, x0 + _size.x - x)
				var depth: float = band[1] + rng.randf_range(-0.06, 0.08)
				var s := Vector3(blen - gap, row_h - gap, depth)
				var pos := Vector3(x + blen * 0.5, y0 + row_h * (r + 0.5), band[0])
				transforms.append(Transform3D(Basis.from_scale(s), pos))
				# Value jitter + a warm/cool drift per block; the odd weathered stone reused from rubble
				var v := rng.randf_range(-0.11, 0.06)
				if rng.randf() < 0.12:
					v -= 0.12
				var w := rng.randf_range(-0.025, 0.03)
				colors.append(Color(STONE_COLOR.r + v + w, STONE_COLOR.g + v, STONE_COLOR.b + v - w * 0.5))
				x += blen
	_add_multimesh(transforms, colors)

# Thick wall: a face of courses on each side of the rubble core, outer (-z, toward the foe)
# first. `count` faces from `first`; the default is both.
func _add_faces(rng: RandomNumberGenerator, height: float, gap: float, count := 2, first := 0) -> void:
	var bands: Array = []
	for i in range(first, first + count):
		var side := -1.0 if i == 0 else 1.0
		bands.append([_center.z + side * (_size.z - THICK_FACE_DEPTH) * 0.5, THICK_FACE_DEPTH])
	_add_courses(rng, height, gap, bands)

# What's left of the old wall (Neh. 2:13 "broken down"): the bottom course, stones
# cracked, sunk and tilted, a few gone, the odd one still standing a course higher
func _add_ruin(rng: RandomNumberGenerator) -> void:
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var x0 := _center.x - _size.x * 0.5
	var x := x0
	while x < x0 + _size.x - 0.1:
		var blen := minf(rng.randf_range(0.6, 1.1), x0 + _size.x - x)
		if rng.randf() > 0.12:
			var h := rng.randf_range(0.16, 0.34)
			var depth := _size.z * rng.randf_range(0.75, 1.0)
			var s := Vector3(blen - 0.08, h, depth)
			var b := Basis.from_euler(Vector3(rng.randf_range(-0.08, 0.08), rng.randf_range(-0.1, 0.1), rng.randf_range(-0.1, 0.1)))
			var pos := Vector3(x + blen * 0.5, 0.12 + h * 0.5 - 0.03, _center.z + rng.randf_range(-0.08, 0.08))
			transforms.append(Transform3D(b.scaled_local(s), pos))
			var v := rng.randf_range(-0.12, 0.0)
			colors.append(Color(STONE_COLOR.r + v, STONE_COLOR.g + v, STONE_COLOR.b + v * 1.1))
			# A stone from the next course still in place
			if rng.randf() < 0.18:
				var s2 := Vector3(blen * rng.randf_range(0.5, 0.8), 0.3, depth * 0.8)
				transforms.append(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.12, 0.12)).scaled_local(s2),
					pos + Vector3(rng.randf_range(-0.1, 0.1), h * 0.5 + 0.15, 0)))
				colors.append(Color(STONE_COLOR.r - 0.06, STONE_COLOR.g - 0.06, STONE_COLOR.b - 0.07))
		x += blen
	_add_multimesh(transforms, colors)

# Burned recipe: blackened framing, fallen across the footing
func _add_charred(rng: RandomNumberGenerator) -> void:
	var poles: Array[Transform3D] = []
	var colors: Array[Color] = []
	var n := maxi(3, roundi(_size.x / 1.2))
	for i in n:
		var x := _center.x - _size.x * 0.5 + _size.x / n * (i + 0.5) + rng.randf_range(-0.2, 0.2)
		var z := _center.z + rng.randf_range(-0.25, 0.25)
		var lean := Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(0.6, 1.3), rng.randf_range(-0.3, 0.3))
		poles.append(_pole_transform(Vector3(x, 0.1, z), Vector3(x, 0.1, z) + lean, 0.06))
		colors.append(CHAR_COLOR.lightened(rng.randf_range(0.0, 0.1)))
	_add_multimesh(poles, colors, Chunky.unit_block(), Chunky.wood_material(0.03))

func _add_merlons() -> void:
	var top := 0.12 + _size.y
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var deep := _size.z > 1.5  # towers: ring of merlons; walls: single row
	var md := 0.4 if deep else _size.z
	var nx := maxi(1, floori(_size.x / (MERLON_W * 2.0)))
	var zs: Array = [_center.z - _size.z * 0.5 + md * 0.5, _center.z + _size.z * 0.5 - md * 0.5] if deep else [_center.z]
	for z: float in zs:
		for i in nx:
			var x := _center.x - _size.x * 0.5 + _size.x / nx * (i + 0.5)
			transforms.append(Transform3D(Basis.from_scale(Vector3(MERLON_W, MERLON_H, md)),
				Vector3(x, top + MERLON_H * 0.5, z)))
			colors.append(STONE_COLOR)
	if deep:
		var nz := maxi(1, floori(_size.z / (MERLON_W * 2.0)))
		for x: float in [_center.x - _size.x * 0.5 + md * 0.5, _center.x + _size.x * 0.5 - md * 0.5]:
			for i in range(1, nz - 1):  # skip ends, covered by the x rows
				var z := _center.z - _size.z * 0.5 + _size.z / nz * (i + 0.5)
				transforms.append(Transform3D(Basis.from_scale(Vector3(md, MERLON_H, MERLON_W)),
					Vector3(x, top + MERLON_H * 0.5, z)))
				colors.append(STONE_COLOR)
	_add_multimesh(transforms, colors)

# Timber scaffold marking the wall's full height: rough poles, X-braces, putlogs
# with short plank runs, and a ladder on the city side (Neh. 4:17 builders at work).
# Batched: one MultiMesh for the poles, one for the planks.
func _add_scaffold(rng: RandomNumberGenerator) -> void:
	var poles: Array[Transform3D] = []
	var pole_colors: Array[Color] = []
	var pole := func(a: Vector3, b: Vector3, radius: float, color: Color) -> void:
		poles.append(_pole_transform(a, b, radius))
		pole_colors.append(color)
	var h := _size.y + 0.35
	var bays := maxi(1, roundi(_size.x / 1.5))
	var x0 := _center.x - _size.x * 0.5
	var bay := _size.x / bays
	var off := _size.z * 0.5 + 0.28
	var tops: Array[Vector3] = []
	for side: float in [-1.0, 1.0]:
		var z := _center.z + side * off
		var feet: Array[Vector3] = []
		var heads: Array[Vector3] = []
		for i in bays + 1:
			var x := x0 + bay * i
			var foot := Vector3(x + rng.randf_range(-0.05, 0.05), 0.0, z)
			var head := Vector3(x + rng.randf_range(-0.08, 0.08), h + rng.randf_range(-0.1, 0.15), z + side * 0.04)
			pole.call(foot, head, 0.055, WOOD_COLOR.darkened(rng.randf_range(0.0, 0.15)))
			feet.append(foot)
			heads.append(head)
		# Ledger lashed along the top, X-brace in alternate bays
		var ly := h - 0.12
		pole.call(Vector3(x0 - 0.15, ly, z), Vector3(x0 + _size.x + 0.15, ly, z), 0.035, WOOD_COLOR.darkened(0.1))
		for i in bays:
			if (i + int(side > 0.0)) % 2 == 0:
				var a := feet[i] + Vector3(0, 0.15, 0)
				var b := Vector3(heads[i + 1].x, ly, z)
				pole.call(a, b, 0.03, WOOD_COLOR.darkened(0.18))
		if side > 0.0:
			tops = heads
	# Putlogs across the wall with short, slightly skewed plank runs on top
	for i in bays + 1:
		var x := tops[i].x
		pole.call(Vector3(x, h - 0.08, _center.z - off - 0.1), Vector3(x, h - 0.08, _center.z + off + 0.1),
			0.03, WOOD_COLOR.darkened(0.1))
	var planks: Array[Transform3D] = []
	var plank_colors: Array[Color] = []
	for i in bays:
		if rng.randf() < 0.75:
			var s := Vector3(bay * rng.randf_range(0.7, 0.95), 0.07, 0.34)
			var pos := Vector3(x0 + bay * (i + 0.5), h - 0.03, _center.z + rng.randf_range(-0.2, 0.2))
			plank_colors.append(WOOD_COLOR.lightened(rng.randf_range(0.06, 0.16)))
			planks.append(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.06, 0.06)).scaled_local(s), pos))
	# Ladder leaning on the city side
	var lx := x0 + bay * (rng.randi_range(0, bays - 1) + 0.5)
	var base_z := _center.z + off + 0.75
	var top_z := _center.z + off + 0.05
	for dx: float in [-0.2, 0.2]:
		pole.call(Vector3(lx + dx, 0.0, base_z), Vector3(lx + dx, h + 0.1, top_z), 0.03, WOOD_COLOR.lightened(0.05))
	var rungs := int(h / 0.32)
	for r in range(1, rungs + 1):
		var t := float(r) / (rungs + 1)
		var y := (h + 0.1) * t
		var z := lerpf(base_z, top_z, t)
		pole.call(Vector3(lx - 0.2, y, z), Vector3(lx + 0.2, y, z), 0.02, WOOD_COLOR.lightened(0.05))
	_add_multimesh(poles, pole_colors, Chunky.unit_block(), Chunky.wood_material(0.03))
	_add_multimesh(planks, plank_colors, Chunky.unit_block(), Chunky.wood_material(0.015))

# Squared timber between two points: the unit block stretched to length, chunky section
static func _pole_transform(a: Vector3, b: Vector3, radius: float) -> Transform3D:
	var dir := (b - a).normalized()
	var rot := Basis(Quaternion(Vector3.UP, dir)) if absf(dir.dot(Vector3.UP)) < 0.999 else Basis()
	var w := radius * TIMBER_WIDTH
	return Transform3D(rot.scaled_local(Vector3(w, a.distance_to(b), w)), (a + b) * 0.5)

func _add_box(size: Vector3, pos: Vector3, color: Color) -> StandardMaterial3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	mi.material_override = mat
	_visual.add_child(mi)
	return mat

func _add_multimesh(transforms: Array[Transform3D], colors: Array[Color],
		mesh: Mesh = null, mat: Material = null) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh if mesh != null else Chunky.unit_block()
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat if mat != null else Chunky.material(0.07)
	_visual.add_child(mmi)

## Every peer, at dusk: today's finished wall takes a bow
func celebrate() -> void:
	if stage == Stage.EMPTY:
		return
	_bounce()
	_dust_puff()
	Sfx.play("build", global_position + _center)

# Stage raised: pop up from slightly squashed, cartoon-style
func _bounce() -> void:
	if _juice_tween:
		_juice_tween.kill()
	_visual.position = Vector3.ZERO
	_visual.scale = Vector3(1.02, 0.9, 1.02)
	_juice_tween = create_tween()
	_juice_tween.tween_property(_visual, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _shake() -> void:
	if _juice_tween and _juice_tween.is_running():
		return
	_juice_tween = create_tween()
	for x: float in [0.07, -0.06, 0.04, -0.02, 0.0]:
		_juice_tween.tween_property(_visual, "position:x", x, 0.04)

func _dust_puff() -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.85
	p.amount = 28
	p.lifetime = 1.4
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(_size.x * 0.5, 0.2, _size.z * 0.5 + 0.3)
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.8
	p.gravity = Vector3(0, -0.6, 0)
	p.damping_min = 0.8
	p.damping_max = 1.4
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	p.scale_amount_curve = DustFx.grow_curve()
	p.angle_min = 0.0
	p.angle_max = 360.0
	# Earthier than the limestone so the puff reads against a fresh wall
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.78, 0.68, 0.52, 0.5))
	ramp.set_color(1, Color(0.78, 0.68, 0.52, 0.0))
	p.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.material = DustFx.material()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.mesh = quad
	p.position = Vector3(_center.x, 0.3, _center.z)
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)

# ── Label ──────────────────────────────────────────────────

func _build_label() -> void:
	_label = WorldTag.make(WorldTag.Kind.SITE)
	_label.position = Vector3(_center.x, _size.y + 1.0, _center.z)
	_label.visible = false
	add_child(_label)

func _update_label() -> void:
	var lines: PackedStringArray = []
	var next := stage + 1
	if _hauling():
		lines.append("Carry the timbers to the dark patch  %d left" % debris_on_pad().size())
	elif _clearing():
		lines.append("Pull down the charred timbers  [%s]" % InputMode.key("interact"))
	var face_label := face_name()
	if not face_label.is_empty():
		lines.append(face_label)
	if _clearing():
		pass   # the line above says it all
	elif GameState.active_build and can_build():
		# Everything's here — it needs hands, not loads
		lines.append("Build  [%s]" % InputMode.key("interact"))
	elif next <= Stage.MORTARED:
		var cost: Dictionary = cost_for(next)
		var parts: PackedStringArray = []
		for kind: String in cost:
			var have: int = mini(pending.get(kind, 0), cost[kind])
			parts.append("%s %d/%d" % [kind.capitalize(), have, cost[kind]])
		lines.append("  ".join(parts))
	elif repairing():
		lines.append("Mend  [%s]" % InputMode.key("interact") if can_build() else "Mortar to mend  %d/1" % mini(pending.get("mortar", 0), 1))
	if is_built() and health < MAX_HEALTH:
		lines.append("Wall %d%%" % roundi(health / MAX_HEALTH * 100.0))
	_label.text = "\n".join(lines)

func _local_player_near() -> bool:
	return Player.local != null and distance_to_point(Player.local.global_position) < LABEL_RANGE
