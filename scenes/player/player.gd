class_name Player
extends CharacterBody3D

# Owning peer drives movement + animation (replicated via MultiplayerSynchronizer).
# World changes — pickups, deposits, building, sling hits, health, downed state —
# go through the server.

const MAX_HEALTH      := 100.0
const RUN_SPEED       := 8.0
const CARRY_SPEED     := 5.5
const INTERACT_REACH  := 2.5
const REVIVE_REACH    := 1.8
# Sling: hold to charge, release to throw at the cursor. Charge scales range + damage.
const SLING_MIN_RANGE  := 4.0
const SLING_MAX_RANGE  := 10.0
const SLING_MIN_DAMAGE := 12.0
const SLING_MAX_DAMAGE := 25.0
const SLING_CHARGE_TIME := 0.9    # seconds to full charge
const SLING_COOLDOWN   := 0.6
const SLING_MIN_THROW  := 1.5     # never land closer than this
const AIM_ASSIST_DEG   := 18.0    # enemies inside this cone of the aim get homed on
const CHARGE_MOVE_MULT := 0.55    # slower while winding up
const AIM_RING_LOCKED  := Color(0.86, 0.38, 0.26, 0.9)
const AIM_RING_FREE    := Color(0.45, 0.30, 0.12, 0.85)   # dark ochre — reads on sand
const GROUND_Y         := 0.1     # top of the floor slab
const WHIRL_HAND_Y     := 1.7     # throwing hand, raised beside the head
const WHIRL_SIDE       := 0.32    # hand offset to the side of the body (screen space)
const WHIRL_RADIUS     := 0.42
const HP_BAR_Y         := 2.75
const DOWNED_BAR_COLOR := Color(0.78, 0.30, 0.20)
const WHIRL_SPIN_MIN   := 9.0     # rad/s at the start of the wind-up…
const WHIRL_SPIN_MAX   := 24.0    # …and at full charge
const STAGGER_TIME    := 0.2
const DOWNED_TIME     := 8.0      # self-revive if no teammate helps
const REVIVE_HEALTH   := 0.5
const RESPAWN_POS     := Vector3(0, 0.1, 8)   # y = floor top (no gravity — the world is flat)
# Walkable rectangle in x/z — inside the 100 × 80 floor, clear of its edge
const PLAY_AREA       := Rect2(-44.0, -30.0, 88.0, 64.0)
const CARRY_FRONT_SCALE := 0.8   # a load hugged at the chest reads a little smaller than overhead
const CARRY_HEIGHT    := 2.4      # just above the head of the ~2.2 m chibi figure
const CARRY_SCALE     := 1.35     # loads read bigger overhead than on the ground (Overcooked)
const PIP_Y           := 3.2      # player-colour marker above the head (multiplayer)
const SLING_RELEASE_Y := 1.9      # overhead hand height
const SLING_RELEASE_FRAME := 3    # frame of the "slash" swing where the stone leaves the hand
const TOAST_TIME      := 1.2
# Dash (Overcooked 2 style): short burst in the move direction, works while carrying
const DASH_SPEED      := 20.0
const DASH_TIME       := 0.14
const DASH_COOLDOWN   := 0.7
# Short ramp so starts and stops have a little weight without going floaty
const ACCEL           := 140.0    # ~0.06 s to full run
const DECEL           := 160.0    # ~0.05 s to a stop
# Beams ("beams" twist): one worker can drag a beam alone, slowly; a second worker takes
# the other end and the pair move at carrying pace, tethered to each other
const BEAM_SOLO_SPEED := 2.4
const BEAM_PAIR_SPEED := 4.8
const BEAM_TETHER     := 2.4      # max distance between the two ends' carriers
const BEAM_HELP_REACH := 2.0
const BEAM_HOLD_Y     := 1.25     # shoulder height
const FOCUS_COLOR     := Color(0.99, 0.93, 0.74, 0.95)   # cream ring under what [E] will use
const FOCUS_POLL      := 0.1
const RUN_ANIM_SPEED  := 8.0      # ground speed the run cycle was drawn for
const WALK_ANIM_SPEED := 4.5
const STICK_DEADZONE  := 0.2
# A press that lands while an action is still playing is kept this long, not dropped
const INPUT_BUFFER    := 0.15
# Gamepad sling: no cursor, so the aim cone is wider and an idle stick throws where we face
const PAD_ASSIST_DEG  := 35.0

# Screen directions on the ground plane (isometric camera looks down -x -z)
const SCREEN_RIGHT := Vector3(1, 0, -1) * 0.70710678
const SCREEN_DOWN  := Vector3(1, 0, 1) * 0.70710678

const _DEFAULT_ROBE := Palette.CREW[0]   # until Main assigns a slot
const SLING_STONE := preload("res://scenes/sling_stone/sling_stone.tscn")
const DROPPED_ITEM := preload("res://scenes/dropped_item/dropped_item.tscn")
const MAX_DROPPED  := 40      # oldest ground item vanishes past this
const DROP_JITTER  := 0.25    # so repeated drops don't stack on one spot
# Dropping a load beside an empty-handed teammate puts it in their hands instead (the
# long haul at the Dung Gate is a chain of these)
const HANDOFF_REACH := 2.2
# Led off by an Ono messenger ("schemes" twist): walk behind him, no control
const LED_FOLLOW    := 1.3
const LED_SPEED     := 3.4
const MARKER_SHADER := preload("res://assets/shaders/ground_marker.gdshader")

# Replicated animation name — owner writes, every peer plays it
var anim := "idle_down":
	set(value):
		anim = value
		if _sprite != null and _sprite.animation != value:
			_sprite.play(value)

var health: float = MAX_HEALTH
var carried_kind: String = ""
# Peer id of the worker whose beam we're holding the other end of (0 = none). Server-set.
var helping_id := 0
var downed := false
var slot_color := Color.WHITE   # ring / HUD colour, set by Main
var _facing := "down"
var _is_busy := false
var _sling_cd := 0.0
var _down_timer := 0.0
var _carry_prop: Node3D
var _carry_front: Node3D   # the load at the chest, parented to the rig's carry anchor
var _charging := false
var _charge := 0.0
var _aim_point := Vector3.ZERO
var _aim_marker: MeshInstance3D
var _whirl: Node3D
var _whirl_time := 0.0
var _whirl_angle := 0.0
var _hp_bar: HealthBar
var _dash_time := 0.0
var _dash_cd := 0.0
var _dash_dir := Vector3.ZERO
var _focus_ring: MeshInstance3D
var _focus_poll := 0.0
var _beam: Node3D   # carried beam, placed in world space between the two ends
var _buffered := {}   # action → seconds left to act on an early press
# Hands-on building: the site we're working at (owner) / registered with (server)
var _work_site: Node3D
var building_site: Node3D
var _move_dir := Vector3.ZERO   # last non-zero move input (pad aim falls back to it)
var _led_by: Node3D             # owner: the messenger we're following to Ono
var _led_time := 0.0
var _led_server := false        # server: this worker went with a messenger

# Replicated: the sling is being whirled (owner writes, every peer shows it)
var whirling := false:
	set(value):
		whirling = value
		_whirl_time = 0.0
		if _whirl != null:
			_whirl.visible = value

@onready var _sprite: CharacterRig = $Figure

## This peer's own worker, or null before it spawns
static var local: Player

func _ready() -> void:
	add_to_group("players")
	if is_multiplayer_authority():
		local = self
	# Server-owned (host) player: don't replicate to a client still loading the
	# game scene — its copy of this node doesn't exist yet
	$MultiplayerSynchronizer.add_visibility_filter(func(id: int) -> bool:
		return not multiplayer.is_server() or id == 1 or NetworkManager.is_peer_ready(id))
	_sprite.setup(CharacterRig.worker_look(0, _DEFAULT_ROBE))
	_sprite.footstep.connect(func(): Sfx.play("step", global_position))
	_sprite.strike.connect(_on_strike)
	_sprite.play(anim)
	_carry_prop = Node3D.new()
	_carry_prop.position.y = CARRY_HEIGHT
	add_child(_carry_prop)
	_build_whirl()
	_hp_bar = HealthBar.new()
	_hp_bar.position.y = HP_BAR_Y
	add_child(_hp_bar)
	_build_pip()
	GameState.crew_changed.connect(func(_n): _refresh_pip())
	GameState.phase_changed.connect(_on_phase_changed)

func _process(delta: float) -> void:
	_update_beam()
	if carried_kind == "beam" or helping_id != 0:
		_sprite.hold = "beam"
	else:
		_sprite.hold = "" if carried_kind.is_empty() else "front"
	if whirling:
		_update_whirl(delta)
	if downed:
		# Every peer counts down locally; the server's copy decides the self-revive
		_down_timer -= delta
		_hp_bar.show_value(_down_timer / DOWNED_TIME, DOWNED_BAR_COLOR)
		if multiplayer.is_server() and _down_timer <= 0.0:
			_set_downed.rpc(false)
	else:
		_hp_bar.show_health(health / MAX_HEALTH)

func _exit_tree() -> void:
	if local == self:
		local = null

func set_slot(slot: int, c: Color) -> void:
	slot_color = c
	_sprite.set_look(CharacterRig.worker_look(slot, c))
	_sprite.set_ring_color(c)
	_refresh_pip()
	_rebuild_carry_prop()   # a new rig means a new chest anchor

# Small diamond in the player's colour over the head — who's who in a busy crew.
# Only with company; pulses while downed so teammates see who needs help.
var _pip: MeshInstance3D
var _pip_tween: Tween

func _build_pip() -> void:
	var gem := SphereMesh.new()   # 4 segments × 2 rings = a diamond
	gem.radius = 0.16
	gem.height = 0.42
	gem.radial_segments = 4
	gem.rings = 1
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.render_priority = 1
	_pip = MeshInstance3D.new()
	_pip.mesh = gem
	_pip.material_override = mat
	_pip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pip.position.y = PIP_Y
	_pip.rotation.y = PI / 4   # a face toward the iso camera
	add_child(_pip)
	_refresh_pip()

func _refresh_pip() -> void:
	if _pip == null:
		return
	_pip.visible = GameState.crew_size > 1
	(_pip.material_override as StandardMaterial3D).albedo_color = slot_color
	if _pip_tween:
		_pip_tween.kill()
		_pip.scale = Vector3.ONE
	if downed:
		_pip_tween = _pip.create_tween().set_loops()
		_pip_tween.tween_property(_pip, "scale", Vector3.ONE * 1.6, 0.35).set_trans(Tween.TRANS_SINE)
		_pip_tween.tween_property(_pip, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_SINE)

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	_sling_cd = maxf(0.0, _sling_cd - delta)
	_dash_cd = maxf(0.0, _dash_cd - delta)
	_buffer_input(delta)
	_update_focus(delta)
	if downed or GameState.is_over() or GameState.phase == GameState.Phase.STORY:
		velocity = Vector3.ZERO
		_dash_time = 0.0
		_cancel_charge()
		return
	if _led_by != null:
		_follow_leader(delta)
		return
	if _work_site != null:
		if _wants_to_stop_work():
			_stop_work()
		else:
			velocity = Vector3.ZERO
			return
	if _is_busy:
		_cancel_charge()  # hit or acting — wind-up is lost
	_handle_movement(delta)
	if not _is_busy:
		_handle_interact()
		_handle_attack(delta)
		if _consume("horn") and GameState.has_twist("horn"):
			_server_horn.rpc_id(1, global_position)
	_update_anim()

# ── Movement ───────────────────────────────────────────────

## Screen-space stick / keys → ground direction. Keys give length 1; a stick can be
## pushed part-way for a slower walk.
static func screen_to_ground(v: Vector2) -> Vector3:
	return SCREEN_RIGHT * v.x + SCREEN_DOWN * v.y

# Remember presses for a moment, so one made during a pickup / throw animation still counts
func _buffer_input(delta: float) -> void:
	if InputMode.gameplay_blocked():
		_buffered.clear()
		return
	for action: String in ["interact", "drop", "dash", "horn"]:
		if Input.is_action_just_pressed(action):
			_buffered[action] = INPUT_BUFFER
		elif _buffered.has(action):
			_buffered[action] -= delta
			if _buffered[action] <= 0.0:
				_buffered.erase(action)

func _consume(action: String) -> bool:
	return _buffered.erase(action)

# Stick / keys, zero while a menu is up (the pad is navigating it, not walking)
func _move_input() -> Vector2:
	if InputMode.gameplay_blocked():
		return Vector2.ZERO
	return Input.get_vector("move_west", "move_east", "move_north", "move_south", STICK_DEADZONE)

func _throw_just_pressed() -> bool:
	return Input.is_action_just_pressed("throw_charge") and not InputMode.gameplay_blocked()

func _handle_movement(delta: float) -> void:
	var dir := screen_to_ground(_move_input())
	if dir != Vector3.ZERO:
		_move_dir = dir.normalized()
	var on_beam := carried_kind == "beam" or helping_id != 0
	if _buffered.has("dash") and _dash_cd <= 0.0 and not _is_busy and not _charging and not on_beam:
		_consume("dash")
		# Standing still: dash the way we're facing
		_dash_dir = dir.normalized() if dir != Vector3.ZERO else _facing_vector()
		_dash_time = DASH_TIME
		_dash_cd = DASH_COOLDOWN
		_dash_fx.rpc()
	if _dash_time > 0.0:
		_dash_time -= delta
		velocity = _dash_dir * DASH_SPEED
	else:
		var target := dir * (CARRY_SPEED if not carried_kind.is_empty() else RUN_SPEED)
		if on_beam:
			target = dir * (BEAM_PAIR_SPEED if _beam_partner() != null else BEAM_SOLO_SPEED)
		if _charging:
			target *= CHARGE_MOVE_MULT
		var rate := ACCEL if target.length_squared() > velocity.length_squared() else DECEL
		velocity = velocity.move_toward(target, rate * delta)
	move_and_slide()
	_tether_to_partner()
	global_position.x = clampf(global_position.x, PLAY_AREA.position.x, PLAY_AREA.end.x)
	global_position.z = clampf(global_position.z, PLAY_AREA.position.y, PLAY_AREA.end.y)

# ── Beams ──────────────────────────────────────────────────

## The worker on the other end of our beam, or null
func _beam_partner() -> Node3D:
	if helping_id != 0:
		return get_parent().get_node_or_null(str(helping_id))
	if carried_kind == "beam":
		var me := get_multiplayer_authority()
		for p in get_tree().get_nodes_in_group("players"):
			if p.helping_id == me:
				return p
	return null

# Owner: can't walk further from the other end than the beam allows — the pair has to
# move together (each side clamps itself, so neither can drag the other)
func _tether_to_partner() -> void:
	var partner := _beam_partner()
	if partner == null:
		return
	var off := global_position - partner.global_position
	off.y = 0.0
	if off.length() > BEAM_TETHER:
		var p := partner.global_position + off.normalized() * BEAM_TETHER
		global_position = Vector3(p.x, global_position.y, p.z)

## A lone beam carrier within reach who could use a hand
func _carrier_needing_help(at: Vector3) -> Node3D:
	for p in get_tree().get_nodes_in_group("players"):
		if p != self and p.carried_kind == "beam" and not p.downed and p._beam_partner() == null \
				and at.distance_to(p.global_position) < BEAM_HELP_REACH:
			return p
	return null

@rpc("any_peer", "call_local", "reliable")
func _set_helping(carrier_id: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	helping_id = carrier_id
	_sprite.squash(Vector2(1.08, 0.92) if carrier_id != 0 else Vector2(0.95, 1.05))

# Server: let go of whoever holds the other end of our beam
func _release_helper() -> void:
	var me := get_multiplayer_authority()
	for p in get_tree().get_nodes_in_group("players"):
		if p.helping_id == me:
			p._set_helping.rpc(0)

# Every peer: lay the beam from our shoulder to the partner's, or drag it behind us alone
func _update_beam() -> void:
	if carried_kind != "beam":
		if _beam != null:
			_beam.queue_free()
			_beam = null
		return
	if _beam == null:
		_beam = Node3D.new()
		_beam.top_level = true
		_beam.add_child(DroppedItem.build_prop("beam"))
		add_child(_beam)
	var a := global_position + Vector3.UP * BEAM_HOLD_Y
	var partner := _beam_partner()
	var b: Vector3
	if partner != null:
		b = partner.global_position + Vector3.UP * BEAM_HOLD_Y
	else:
		# Alone: one end on the shoulder, the other dragging in the sand behind
		var back := -_facing_vector()
		b = global_position + back * 2.2 + Vector3.UP * 0.15
	var along := b - a
	if along.length_squared() < 0.01:
		return
	var x := along.normalized()
	var z := x.cross(Vector3.UP).normalized()
	if z.length_squared() < 0.01:
		z = Vector3.FORWARD
	_beam.global_transform = Transform3D(Basis(x, z.cross(x), z), (a + b) * 0.5)

func _facing_vector() -> Vector3:
	match _facing:
		"up":    return -SCREEN_DOWN
		"left":  return -SCREEN_RIGHT
		"right": return SCREEN_RIGHT
	return SCREEN_DOWN

# Owner → everyone: puff of dust + stretch so a dash reads on every screen
@rpc("authority", "call_local", "unreliable")
func _dash_fx() -> void:
	_sprite.squash(Vector2(0.92, 1.08))
	Sfx.play("dash", global_position)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 10
	p.lifetime = 0.5
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, -1.0, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 0.9
	p.scale_amount_curve = DustFx.grow_curve()
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.92, 0.84, 0.66, 0.7))
	ramp.set_color(1, Color(0.92, 0.84, 0.66, 0.0))
	p.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	quad.material = DustFx.material()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.mesh = quad
	p.top_level = true  # stays where the dash started
	add_child(p)
	p.global_position = global_position + Vector3(0, 0.15, 0)
	p.emitting = true
	p.finished.connect(p.queue_free)

# ── Interaction focus (owner, local only) ──────────────────

## What [E] acts on from `at`, in priority order: [Act, target]. The one rule for both
## the focus ring (owner, from replicated state — Overcooked's counter highlight) and
## _server_interact, so the ring always shows exactly what the press will do.
enum Act { NONE, REVIVE, LET_GO, HELP, DELIVER, MESSENGER, WORK, TAKE_ITEM, TAKE_PILE }

func _interact_choice(at: Vector3) -> Array:
	# Helping a fallen teammate comes first
	for p in get_tree().get_nodes_in_group("players"):
		if p != self and p.downed and at.distance_to(p.global_position) < REVIVE_REACH:
			return [Act.REVIVE, p]
	if helping_id != 0:
		return [Act.LET_GO, null]
	# Nearest valid thing wins — sections and gate pillars overlap in reach.
	# Null target = nothing here wants the load.
	if not carried_kind.is_empty():
		return [Act.DELIVER, _nearest_in_reach("build_sites", at, func(s): return s.needs(carried_kind))]
	var carrier := _carrier_needing_help(at)
	if carrier != null:
		return [Act.HELP, carrier]
	# Everything delivered, waiting for hands
	var site := _nearest_in_reach("build_sites", at, func(s): return s.can_build())
	var item := _nearest_in_reach("dropped_items", at, func(_i): return true)
	var pile := _nearest_in_reach("supply_piles", at, func(_p): return true)
	# An Ono messenger standing closer than anything else goes first. He waits right
	# beside you, so a careless press goes with him — that's the trap.
	var messenger := _nearest_in_reach("messengers", at, func(_m): return true)
	if messenger != null:
		var d := _reach_dist(messenger, at)
		if [site, item, pile].all(func(o): return o == null or _reach_dist(o, at) >= d):
			return [Act.MESSENGER, messenger]
	if site != null:
		return [Act.WORK, site]
	# Whichever is closer: something lying on the ground, or a stockpile
	if item != null and (pile == null or _reach_dist(item, at) <= _reach_dist(pile, at)):
		return [Act.TAKE_ITEM, item]
	if pile != null:
		return [Act.TAKE_PILE, pile]
	return [Act.NONE, null]

func _update_focus(delta: float) -> void:
	_focus_poll -= delta
	if _focus_poll > 0.0:
		return
	_focus_poll = FOCUS_POLL
	if _focus_ring == null:
		_build_focus_ring()
	var target: Node3D = null
	if not downed and not GameState.is_over():
		target = _interact_choice(global_position)[1]
	_focus_ring.visible = target != null
	if target == null:
		return
	# Walls are long — ring the spot on the wall nearest us, not its centre
	var spot := target.global_position
	var size := 1.5
	if target.has_method("approach_point"):
		spot = target.approach_point(global_position, 0.0)
	elif target.is_in_group("supply_piles"):
		size = 2.6
	elif target.is_in_group("dropped_items"):
		size = 1.1
	_focus_ring.global_position = Vector3(spot.x, GROUND_Y + 0.05, spot.z)
	_focus_ring.mesh.size = Vector2(size, size)

func _build_focus_ring() -> void:
	var quad := QuadMesh.new()
	quad.orientation = PlaneMesh.FACE_Y
	var mat := ShaderMaterial.new()
	mat.shader = MARKER_SHADER
	mat.set_shader_parameter("shadow_color", Color(0, 0, 0, 0))
	mat.set_shader_parameter("ring_color", FOCUS_COLOR)
	mat.set_shader_parameter("ring_radius", 0.42)
	mat.set_shader_parameter("ring_width", 0.05)
	_focus_ring = MeshInstance3D.new()
	_focus_ring.mesh = quad
	_focus_ring.material_override = mat
	_focus_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_focus_ring.top_level = true
	_focus_ring.visible = false
	add_child(_focus_ring)
	# Gentle breathing pulse
	var tw := _focus_ring.create_tween().set_loops()
	tw.tween_property(_focus_ring, "scale", Vector3.ONE * 1.08, 0.45).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_focus_ring, "scale", Vector3.ONE * 0.94, 0.45).set_trans(Tween.TRANS_SINE)

# ── Animation ──────────────────────────────────────────────

func _update_anim() -> void:
	# Working: the build loop owns the pose (work can start mid-tick, from interact)
	if _is_busy or _work_site != null:
		return
	var speed := velocity.length()
	if _charging:
		# Face the aim, not the walking direction, while winding up
		_facing = CharAnim.dir_from_velocity(_aim_point - global_position, _facing)
		_sprite.speed_scale = 1.0
		anim = "windup_" + _facing
		return
	if speed < 0.1:
		_sprite.speed_scale = 1.0
		anim = "idle_" + _facing
		return
	if not _charging:
		_facing = CharAnim.dir_from_velocity(velocity, _facing)
	# Laden workers trudge; free hands run. Stride rate follows ground speed.
	var laden := not carried_kind.is_empty()
	_sprite.speed_scale = speed / (WALK_ANIM_SPEED if laden else RUN_ANIM_SPEED)
	anim = ("walk_" if laden else "run_") + _facing

# One-shot action animation that blocks input until it finishes (owner only)
func _play_action(anim_base: String) -> void:
	_is_busy = true
	_sprite.speed_scale = 1.0
	anim = anim_base + "_" + _facing
	await _sprite.animation_finished
	if is_instance_valid(self) and not downed:
		_is_busy = false
		if _work_site == null:
			anim = "idle_" + _facing

# ── Interact / Drop ────────────────────────────────────────

func _handle_interact() -> void:
	if _consume("interact"):
		_server_interact.rpc_id(1, global_position)
	if _consume("drop"):
		_server_drop.rpc_id(1, global_position)

# Owner sends its position with the request: the reliable RPC can overtake the
# unreliable position sync, so the server's copy may still be a frame behind.
@rpc("any_peer", "call_local", "reliable")
func _server_interact(at: Vector3) -> void:
	if not _from_owner() or downed:
		return
	var choice := _interact_choice(at)
	var target: Node3D = choice[1]
	match choice[0]:
		Act.REVIVE:
			target._set_downed.rpc(false)
			_action.rpc("halfslash")
		Act.LET_GO:
			_set_helping.rpc(0)
			_tell("Let go of the beam")
		Act.HELP:
			_set_helping.rpc(target.get_multiplayer_authority())
			_sfx.rpc("pickup")
			_tell("Holding the other end — {interact} to let go")
		Act.DELIVER:
			_deliver(target, at)
		Act.MESSENGER:
			target.accept(self)
		Act.WORK:
			if GameState.active_build:
				_start_work(target)
			elif target.try_build():
				_action.rpc("halfslash")
		Act.TAKE_ITEM:
			var kind: String = target.kind
			if target.take():
				_sfx.rpc("pickup")
				_set_carried.rpc(kind)
		Act.TAKE_PILE:
			if target.request_pickup():
				_sfx.rpc("pickup")
				_set_carried.rpc(target.kind)

# Server: hand the carried load to `dest` (null = nothing near wants it)
func _deliver(dest: Node3D, at: Vector3) -> void:
	if dest == null or not dest.deposit(carried_kind, 1):
		_tell(_why_not_needed(at))
		return
	get_tree().call_group("day_director", "note_load", get_multiplayer_authority())
	_sfx.rpc("deposit_" + carried_kind)
	_set_carried.rpc("")
	if dest.can_build():
		# Last load for this stage: the one who brought it sets straight to work
		# (hands-on building), or it goes up at once (old rule)
		if GameState.active_build:
			_start_work(dest)
		elif dest.try_build():
			_action.rpc("halfslash")
			_tell("Stage built!")
		return
	_action.rpc("halfslash")

# Server: explain a refused delivery (the carried material isn't wanted here)
func _why_not_needed(at: Vector3) -> String:
	var wall := _nearest_in_reach("build_sites", at, func(_s): return true)
	if wall == null:
		if _nearest_in_reach("supply_piles", at, func(_p): return true) != null:
			return "Hands full — deliver it, or {drop} to drop"
		return "Bring it to a wall"
	var need: String = wall.next_need()
	if need.is_empty():
		return "This wall is finished"
	return "Needs %s first" % need

@rpc("any_peer", "call_local", "reliable")
func _server_drop(at: Vector3) -> void:
	if not _from_owner():
		return
	if helping_id != 0:
		_set_helping.rpc(0)
	elif not carried_kind.is_empty():
		var mate := _free_hands_near(at)
		if mate != null:
			_hand_over(mate)
		else:
			_drop_carried(at)

# Server: the nearest teammate who could take our load straight from our hands
func _free_hands_near(at: Vector3) -> Node3D:
	if carried_kind == "beam":
		return null   # beams are shared by taking the other end, not passed
	var best: Node3D = null
	var best_d := HANDOFF_REACH
	for p in get_tree().get_nodes_in_group("players"):
		if p == self or p.downed or not p.carried_kind.is_empty() or p.helping_id != 0 				or p.building_site != null or p.is_led():
			continue
		var d := at.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best

func _hand_over(mate: Node3D) -> void:
	var kind := carried_kind
	_set_carried.rpc("")
	mate._set_carried.rpc(kind)
	_sfx.rpc("pickup")
	_action.rpc("halfslash")
	mate._tell("Caught it")

# Server: put the load on the ground where it stays until someone picks it up
func _drop_carried(at: Vector3) -> void:
	var items: Node3D = get_node("../../Items")
	if items.get_child_count() >= MAX_DROPPED:
		items.get_child(0).queue_free()
	var item: DroppedItem = DROPPED_ITEM.instantiate()
	item.kind = carried_kind
	item.position = Vector3(at.x + randf_range(-DROP_JITTER, DROP_JITTER), GROUND_Y,
		at.z + randf_range(-DROP_JITTER, DROP_JITTER))
	# Filter must be in place before add_child — the spawner snapshots visibility on enter
	NetworkManager.gate_sync(item.get_node("MultiplayerSynchronizer"))
	items.add_child(item, true)
	_sfx.rpc("drop")
	_set_carried.rpc("")

@rpc("any_peer", "call_local", "reliable")
func _set_carried(kind: String) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	carried_kind = kind
	_rebuild_carry_prop()
	if multiplayer.is_server() and kind != "beam":
		_release_helper()
	if kind == "beam" and is_multiplayer_authority() and GameState.crew_size > 1:
		_toast("Heavy — a partner can take the other end {interact}")
	# Pick up → squashed under the load; put down → spring back up
	_sprite.squash(Vector2(1.08, 0.92) if not kind.is_empty() else Vector2(0.95, 1.05))

# Server → everyone: the owner plays the action (its anim then replicates)
@rpc("any_peer", "call_local", "reliable")
func _action(anim_base: String) -> void:
	if multiplayer.get_remote_sender_id() == 1 and is_multiplayer_authority():
		_play_action(anim_base)

# Server → everyone: a sound at this worker's feet
@rpc("any_peer", "call_local", "unreliable")
func _sfx(event: String) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		Sfx.play(event, global_position)

# ── Attack ─────────────────────────────────────────────────

func _handle_attack(delta: float) -> void:
	if not _charging:
		# A click on HUD buttons / the Esc menu isn't a throw
		if _throw_just_pressed() and _sling_cd <= 0.0 and get_viewport().gui_get_hovered_control() == null:
			_charging = true
			_charge = 0.0
			whirling = true
		return
	if InputMode.gameplay_blocked():
		_cancel_charge()   # opened the menu mid wind-up
		return
	_charge = minf(1.0, _charge + delta / SLING_CHARGE_TIME)
	_update_aim(_pad_aim_point() if InputMode.using_pad else _cursor_on_ground())
	# Toggle mode (accessibility): a second press throws; otherwise letting go does
	if (_throw_just_pressed() if Settings.toggle_charge else not Input.is_action_pressed("throw_charge")):
		release_throw()

# Right stick picks the direction; left alone, the throw goes the way we're walking /
# facing. Always thrown at the full range the charge allows — the assist finds the enemy.
func _pad_aim_point() -> Vector3:
	var stick := Input.get_vector("aim_west", "aim_east", "aim_north", "aim_south", STICK_DEADZONE)
	var dir := screen_to_ground(stick).normalized() if stick != Vector2.ZERO else _move_dir
	if dir == Vector3.ZERO:
		dir = _facing_vector()
	return global_position + dir * _sling_range(_charge)

## Owner: finish the wind-up and throw at the current aim point
func release_throw() -> void:
	if not _charging:
		return
	var land := _aim_point
	var charge := _charge
	_cancel_charge()
	_sling_cd = SLING_COOLDOWN
	_facing = CharAnim.dir_from_velocity(land - global_position, _facing)
	_play_action("slash")
	# Release on the swing's release frame, not at wind-up
	while is_instance_valid(self) and _sprite.animation.begins_with("slash") \
			and _sprite.frame < SLING_RELEASE_FRAME:
		await _sprite.frame_changed
	if is_instance_valid(self) and _sprite.animation.begins_with("slash"):
		_server_sling.rpc_id(1, global_position, land, charge, InputMode.using_pad)

func _cancel_charge() -> void:
	_charging = false
	whirling = false
	if _aim_marker:
		_aim_marker.visible = false

# Clamp the cursor point to the charge's range and place the landing ring
func _update_aim(cursor: Vector3) -> void:
	var flat := Vector3(cursor.x - global_position.x, 0.0, cursor.z - global_position.z)
	var reach := _sling_range(_charge)
	var dist := clampf(flat.length(), SLING_MIN_THROW, reach)
	var dir := flat.normalized() if flat.length_squared() > 0.001 else Vector3.FORWARD
	_aim_point = Vector3(global_position.x, GROUND_Y, global_position.z) + dir * dist
	var locked := _assist_target(global_position, _aim_point, reach, _assist_cone(InputMode.using_pad))
	_show_aim_marker(locked.global_position if locked else _aim_point, locked != null)

func _cursor_on_ground() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return global_position
	var mp := get_viewport().get_mouse_position()
	var origin := cam.project_ray_origin(mp)
	var normal := cam.project_ray_normal(mp)
	if absf(normal.y) < 0.001:
		return global_position
	return origin + normal * (-origin.y / normal.y)

func _show_aim_marker(at: Vector3, locked: bool) -> void:
	if _aim_marker == null:
		var quad := QuadMesh.new()
		# Ring drawn at the stone's real impact radius (0.9 m)
		quad.size = Vector2(2.4, 2.4)
		quad.orientation = PlaneMesh.FACE_Y
		var mat := ShaderMaterial.new()
		mat.shader = MARKER_SHADER
		mat.set_shader_parameter("shadow_color", Color(0, 0, 0, 0))
		mat.set_shader_parameter("ring_radius", 0.375)
		mat.set_shader_parameter("ring_width", 0.03)
		_aim_marker = MeshInstance3D.new()
		_aim_marker.mesh = quad
		_aim_marker.material_override = mat
		_aim_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_aim_marker.top_level = true
		add_child(_aim_marker)
	var c := AIM_RING_LOCKED if locked else AIM_RING_FREE
	c.a *= lerpf(0.45, 1.0, _charge)  # ring firms up as the charge builds
	_aim_marker.material_override.set_shader_parameter("ring_color", c)
	_aim_marker.global_position = Vector3(at.x, GROUND_Y + 0.04, at.z)
	_aim_marker.visible = true

static func _assist_cone(pad: bool) -> float:
	return PAD_ASSIST_DEG if pad else AIM_ASSIST_DEG

static func _sling_range(charge: float) -> float:
	return lerpf(SLING_MIN_RANGE, SLING_MAX_RANGE, charge)

# Enemy nearest the aim line inside the assist cone and within reach, or null
func _assist_target(from: Vector3, land: Vector3, reach: float, cone_deg: float) -> Node3D:
	var aim := Vector2(land.x - from.x, land.z - from.z)
	if aim.length_squared() < 0.001:
		return null
	var best: Node3D = null
	var best_angle := deg_to_rad(cone_deg)
	for enemy: Node3D in get_tree().get_nodes_in_group("enemies"):
		var to := Vector2(enemy.global_position.x - from.x, enemy.global_position.z - from.z)
		if to.length() > reach + 0.5:
			continue
		var angle := absf(aim.angle_to(to))
		if angle < best_angle:
			best_angle = angle
			best = enemy
	return best

@rpc("any_peer", "call_local", "reliable")
func _server_sling(at: Vector3, land: Vector3, charge: float, pad: bool) -> void:
	if not _from_owner() or downed:
		return
	charge = clampf(charge, 0.0, 1.0)
	var reach := _sling_range(charge)
	# Don't trust the client's landing point beyond what its charge allows
	var flat := Vector3(land.x - at.x, 0.0, land.z - at.z)
	if flat.length() > reach:
		land = Vector3(at.x, GROUND_Y, at.z) + flat.normalized() * reach
	var target := _assist_target(at, land, reach, _assist_cone(pad))
	var damage := lerpf(SLING_MIN_DAMAGE, SLING_MAX_DAMAGE, charge)
	_throw_stone.rpc(target.get_path() if target else NodePath(), land, damage)

# Every peer animates the stone; only the server's copy deals damage
@rpc("any_peer", "call_local", "reliable")
func _throw_stone(target_path: NodePath, land: Vector3, damage: float) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	var target: Node3D = null
	if not target_path.is_empty():
		target = get_node_or_null(target_path) as Node3D
	Sfx.play("throw", global_position)
	var stone := SLING_STONE.instantiate()
	get_tree().current_scene.add_child(stone)
	stone.global_position = global_position + Vector3(0, SLING_RELEASE_Y, 0)
	stone.shooter = get_multiplayer_authority()
	stone.init(target, land, damage)

# Owner: the day's work is done — throw both arms up. A beat late, so the server's
# revive / down-tools messages (sent alongside the phase) land first.
func _on_phase_changed(phase: GameState.Phase) -> void:
	if phase != GameState.Phase.DUSK or not is_multiplayer_authority():
		return
	await get_tree().create_timer(0.25).timeout
	if not is_instance_valid(self) or downed or GameState.phase != GameState.Phase.DUSK:
		return
	_cancel_charge()
	if _work_site != null:
		_stop_work()
	_facing = "down"   # toward the camera
	_play_action("cheer")
	_sprite.squash(Vector2(0.9, 1.12))
	InputMode.rumble(0.3, 0.2, 0.12)

# ── Damage / Downed (server) ───────────────────────────────

func take_damage(amount: float) -> void:
	if not multiplayer.is_server() or downed:
		return
	# A blow knocks you off the work (Neh. 4:17 — someone has to guard the builders)
	if building_site != null:
		building_site.work().remove_builder(self)
		stop_building_from_server()
	var new_health := clampf(health - amount, 0.0, MAX_HEALTH)
	_on_hurt.rpc(new_health)
	if new_health <= 0.0:
		if not carried_kind.is_empty():
			_drop_carried(global_position)
		if helping_id != 0:
			_set_helping.rpc(0)
		_set_downed.rpc(true)

@rpc("any_peer", "call_local", "reliable")
func _on_hurt(new_health: float) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	health = new_health
	_sprite.hit_flash()
	if new_health > 0.0:
		Sfx.play("hurt", global_position)
	if is_multiplayer_authority():
		_jolt(0.35, 0.4, 0.2, 0.15)
	if is_multiplayer_authority() and not _is_busy and new_health > 0.0:
		# Short stagger — "collapse" is kept for downed
		_is_busy = true
		await get_tree().create_timer(STAGGER_TIME).timeout
		if is_instance_valid(self) and not downed:
			_is_busy = false

@rpc("any_peer", "call_local", "reliable")
func _set_downed(value: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	downed = value
	_refresh_pip()
	Sfx.play("downed" if value else "revive", global_position)
	if value:
		_down_timer = DOWNED_TIME
		if is_multiplayer_authority():
			_jolt(0.6, 0.3, 0.8, 0.35)
	else:
		health = MAX_HEALTH * REVIVE_HEALTH
	if is_multiplayer_authority():
		_is_busy = value
		_sprite.speed_scale = 1.0
		anim = "collapse" if value else "idle_" + _facing

# ── Working at the wall ────────────────────────────────────

# Server: join the work at a site whose materials are all in
func _start_work(site: Node3D) -> void:
	if building_site != null and building_site != site:
		building_site.work().remove_builder(self)
	if not site.work().add_builder(self):
		building_site = null
		_tell("Enough hands here")
		return
	building_site = site
	_set_working.rpc_id(get_multiplayer_authority(), site.get_path())

## Server: the work is done or we were pulled off it
func stop_building_from_server() -> void:
	building_site = null
	_set_working.rpc_id(get_multiplayer_authority(), NodePath())

@rpc("any_peer", "call_local", "reliable")
func _server_stop_work() -> void:
	if not _from_owner() or building_site == null:
		return
	building_site.work().remove_builder(self)
	building_site = null

# Server → owner: start / stop the working loop
@rpc("any_peer", "call_local", "reliable")
func _set_working(site_path: NodePath) -> void:
	if multiplayer.get_remote_sender_id() != 1 or not is_multiplayer_authority():
		return
	var site: Node3D = get_node_or_null(site_path) if not site_path.is_empty() else null
	if site == _work_site:
		return
	_work_site = site
	_sprite.speed_scale = 1.0
	if site != null:
		_cancel_charge()
		_dash_time = 0.0
		_facing = CharAnim.dir_from_velocity(site.approach_point(global_position, 0.0) - global_position, _facing)
		anim = "build_" + _facing
		_sprite.squash(Vector2(1.06, 0.94))
	elif not downed and not _is_busy:
		anim = "idle_" + _facing

# Owner: walking off, dashing, dropping or reaching for the sling ends the work
func _wants_to_stop_work() -> bool:
	_consume("interact")   # already working — a repeat press does nothing
	return _move_input().length() > 0.35 or _buffered.has("dash") or _buffered.has("drop") \
		or _throw_just_pressed() or _is_busy

func _stop_work() -> void:
	_work_site = null
	_server_stop_work.rpc_id(1)
	if not _is_busy:
		anim = "idle_" + _facing

# Every peer: one strike of the tool — a knock and a little dust off the wall
func _on_strike() -> void:
	var site := _nearest_in_reach("build_sites", global_position, func(s): return not s.work_material().is_empty())
	var mat: String = site.work_material() if site != null else "stone"
	Sfx.play("work_" + mat, global_position)
	var at: Vector3 = site.approach_point(global_position, 0.0) if site != null else global_position
	DustFx.puff(self, Vector3(at.x, 0.9, at.z), 5, 0.35)
	if is_multiplayer_authority():
		InputMode.rumble(0.15, 0.0, 0.05)

# ── Horn ("horn" twist) ────────────────────────────────────

@rpc("any_peer", "call_local", "reliable")
func _server_horn(at: Vector3) -> void:
	if not _from_owner() or downed or is_led():
		return
	var horn := get_tree().get_first_node_in_group("horn")
	if horn != null and horn.request(self, at):
		_action.rpc("halfslash")
	else:
		_tell("The horn was just sounded")

# ── Led off to Ono ("schemes" twist) ────────────────────────

func is_led() -> bool:
	return _led_server

## Server: a messenger leads this worker away for `seconds`
func lead_away(messenger: Node3D, seconds: float) -> void:
	_led_server = true
	if building_site != null:
		building_site.work().remove_builder(self)
		stop_building_from_server()
	_set_led.rpc_id(get_multiplayer_authority(), messenger.get_path(), seconds)

## Server: the messenger let go (time up, or the day ended)
func release_from_lead() -> void:
	if not _led_server:
		return
	_led_server = false
	_set_led.rpc_id(get_multiplayer_authority(), NodePath(), 0.0)

@rpc("any_peer", "call_local", "reliable")
func _set_led(path: NodePath, seconds: float) -> void:
	if multiplayer.get_remote_sender_id() != 1 or not is_multiplayer_authority():
		return
	var was_led := _led_by != null
	_led_by = get_node_or_null(path) as Node3D if not path.is_empty() else null
	_led_time = seconds
	_cancel_charge()
	_dash_time = 0.0
	if _led_by != null:
		_toast("Going down to Ono…")
	elif was_led:
		_toast("Why should the work stop? Back to the wall!")
		anim = "idle_" + _facing

# Owner: walk behind the messenger; no input until he lets go
func _follow_leader(delta: float) -> void:
	_led_time -= delta
	if not is_instance_valid(_led_by) or _led_time <= -1.0:
		_led_by = null   # the server's release is on its way; don't wait on it
		return
	var to := _led_by.global_position - global_position
	to.y = 0.0
	var target := Vector3.ZERO
	if to.length() > LED_FOLLOW:
		target = to.normalized() * LED_SPEED
	velocity = velocity.move_toward(target, ACCEL * delta)
	move_and_slide()
	global_position.x = clampf(global_position.x, PLAY_AREA.position.x, PLAY_AREA.end.x)
	global_position.z = clampf(global_position.z, PLAY_AREA.position.y, PLAY_AREA.end.y)
	_update_anim()

# ── Late join (server → one peer) ──────────────────────────

func send_status_to(peer_id: int) -> void:
	_sync_status.rpc_id(peer_id, carried_kind, downed, health, helping_id)

@rpc("any_peer", "call_remote", "reliable")
func _sync_status(kind: String, is_downed: bool, hp: float, helping: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	carried_kind = kind
	downed = is_downed
	if is_downed:
		_down_timer = DOWNED_TIME  # exact remaining time isn't sent; close enough for a late joiner
	health = hp
	helping_id = helping
	_rebuild_carry_prop()

# ── Feedback ───────────────────────────────────────────────

# Local player only: shake our camera and rumble our pad
func _jolt(shake: float, weak: float, strong: float, duration: float) -> void:
	get_tree().call_group("camera_rig", "shake", shake)
	InputMode.rumble(weak, strong, duration)

# Server → owning player only
func _tell(text: String) -> void:
	_feedback.rpc_id(get_multiplayer_authority(), text)

@rpc("any_peer", "call_local", "reliable")
func _feedback(text: String) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		_toast(text)

# Short floating line above the head (local only)
func _toast(text: String) -> void:
	# "{interact}" → "[E]" or "[A]", whichever device this player is using
	var l := WorldTag.make(WorldTag.Kind.TOAST,
		text.format({ "interact": "[%s]" % InputMode.key("interact"), "drop": "[%s]" % InputMode.key("drop") }))
	l.position = Vector3(0, HP_BAR_Y + 0.3, 0)
	add_child(l)
	var tw := l.create_tween()
	tw.set_parallel()
	tw.tween_property(l, "position:y", l.position.y + 0.5, TOAST_TIME)
	tw.tween_property(l, "modulate:a", 0.0, TOAST_TIME * 0.4).set_delay(TOAST_TIME * 0.6)
	tw.chain().tween_callback(l.queue_free)

# ── Sling whirl ────────────────────────────────────────────

# Cord + stone swung in a vertical circle from the throwing hand, beside the body.
# The circle faces the camera so it reads from the isometric view.
func _build_whirl() -> void:
	_whirl = Node3D.new()
	_whirl.top_level = true  # placed in world space every frame
	_whirl.visible = false
	add_child(_whirl)
	var cord_mat := StandardMaterial3D.new()
	cord_mat.albedo_color = Color(0.36, 0.26, 0.16)
	cord_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var cord := CylinderMesh.new()
	cord.top_radius = 0.02
	cord.bottom_radius = 0.02
	cord.height = WHIRL_RADIUS
	cord.radial_segments = 4
	var cord_mi := MeshInstance3D.new()
	cord_mi.mesh = cord
	cord_mi.material_override = cord_mat
	cord_mi.rotation.z = PI / 2          # lie along local +X
	cord_mi.position.x = WHIRL_RADIUS * 0.5
	cord_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_whirl.add_child(cord_mi)
	var stone := SphereMesh.new()
	stone.radius = 0.09
	stone.height = 0.15
	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.55, 0.50, 0.44)
	var stone_mi := MeshInstance3D.new()
	stone_mi.mesh = stone
	stone_mi.material_override = stone_mat
	stone_mi.position.x = WHIRL_RADIUS
	_whirl.add_child(stone_mi)
	# Faint motion-blur ring along the stone's path, so the spin reads at a glance
	var blur := QuadMesh.new()
	blur.size = Vector2(WHIRL_RADIUS * 2.5, WHIRL_RADIUS * 2.5)  # local XY plane
	var blur_mat := ShaderMaterial.new()
	blur_mat.shader = MARKER_SHADER
	blur_mat.set_shader_parameter("shadow_color", Color(0, 0, 0, 0))
	blur_mat.set_shader_parameter("ring_color", Color(0.95, 0.90, 0.78, 0.45))
	blur_mat.set_shader_parameter("ring_radius", 0.4)   # = WHIRL_RADIUS on this quad
	blur_mat.set_shader_parameter("ring_width", 0.06)
	var blur_mi := MeshInstance3D.new()
	blur_mi.mesh = blur
	blur_mi.material_override = blur_mat
	blur_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_whirl.add_child(blur_mi)

func _update_whirl(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# Spin speeds up as the charge builds (time-based so every peer agrees)
	_whirl_time += delta
	_whirl_angle += lerpf(WHIRL_SPIN_MIN, WHIRL_SPIN_MAX, minf(_whirl_time / SLING_CHARGE_TIME, 1.0)) * delta
	var right := cam.global_basis.x
	# Throwing (right) hand: screen-left when facing the camera or right, screen-right otherwise.
	# Facing comes from the replicated anim ("windup_left") so remote peers agree.
	var facing := anim.get_slice("_", 1)
	var side := -1.0 if facing == "down" or facing == "right" else 1.0
	var hand := global_position + Vector3.UP * WHIRL_HAND_Y + right * side * WHIRL_SIDE
	_whirl.global_transform = Transform3D(cam.global_basis * Basis(Vector3.BACK, _whirl_angle), hand)

# ── Carried prop ───────────────────────────────────────────

func _rebuild_carry_prop() -> void:
	for c in _carry_prop.get_children():
		c.queue_free()
	if is_instance_valid(_carry_front):
		_carry_front.queue_free()
	_carry_front = null
	if not carried_kind.is_empty() and carried_kind != "beam":
		var prop := DroppedItem.build_prop(carried_kind)
		# Hugged at the chest (the rig's anchor turns and bobs with the body); the rig is
		# scaled, so undo that to keep the load its usual size
		var anchor := _sprite.carry_anchor()
		if anchor != null:
			prop.scale = Vector3.ONE * CARRY_SCALE * CARRY_FRONT_SCALE / _sprite.scale.x
			prop.position = Vector3(0, -0.04, 0)
			anchor.add_child(prop)
			_carry_front = prop
		else:
			prop.scale = Vector3.ONE * CARRY_SCALE
			_carry_prop.add_child(prop)

# ── Helpers ────────────────────────────────────────────────

func _from_owner() -> bool:
	return multiplayer.is_server() \
		and multiplayer.get_remote_sender_id() == get_multiplayer_authority()

func _nearest_in_reach(group: String, from: Vector3, accept: Callable) -> Node3D:
	var best: Node3D = null
	var best_dist := INTERACT_REACH
	for node: Node3D in get_tree().get_nodes_in_group(group):
		var d := _reach_dist(node, from)
		if d < best_dist and accept.call(node):
			best_dist = d
			best = node
	return best

func _reach_dist(node: Node3D, from: Vector3) -> float:
	return node.distance_to_point(from) if node.has_method("distance_to_point") \
		else from.distance_to(node.global_position)
