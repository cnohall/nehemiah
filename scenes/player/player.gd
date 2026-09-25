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
const WHIRL_HAND_Y     := 1.3     # throwing hand, about shoulder height
const WHIRL_SIDE       := 0.32    # hand offset to the side of the body (screen space)
const WHIRL_RADIUS     := 0.42
const HP_BAR_Y         := 2.3
const DOWNED_BAR_COLOR := Color(0.78, 0.30, 0.20)
const WHIRL_SPIN_MIN   := 9.0     # rad/s at the start of the wind-up…
const WHIRL_SPIN_MAX   := 24.0    # …and at full charge
const STAGGER_TIME    := 0.2
const DOWNED_TIME     := 8.0      # self-revive if no teammate helps
const REVIVE_HEALTH   := 0.5
const RESPAWN_POS     := Vector3(0, 0.1, 8)   # y = floor top (no gravity — the world is flat)
# Walkable rectangle in x/z — inside the 100 × 80 floor, clear of its edge
const PLAY_AREA       := Rect2(-44.0, -30.0, 88.0, 64.0)
const CARRY_HEIGHT    := 1.95     # just above the head of a ~1.7 m figure
const SLING_RELEASE_Y := 1.5      # overhead hand height
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
const BEAM_HOLD_Y     := 1.45     # shoulder height
const FOCUS_COLOR     := Color(0.99, 0.93, 0.74, 0.95)   # cream ring under what [E] will use
const FOCUS_POLL      := 0.1
const RUN_ANIM_SPEED  := 8.0      # ground speed the run cycle was drawn for
const WALK_ANIM_SPEED := 4.5

const MOVE_DIRS := {
	"move_north": Vector3(-1, 0, -1),
	"move_south": Vector3( 1, 0,  1),
	"move_east":  Vector3( 1, 0, -1),
	"move_west":  Vector3(-1, 0,  1),
}

# Worker sheets (tunic colour per player slot) — composed from LPC layers, see assets/sprites/CREDITS.md
const _FONT       := preload("res://assets/fonts/Spectral/Spectral-SemiBold.ttf")
const _SHEETS     := [
	preload("res://assets/sprites/player_1.png"),
	preload("res://assets/sprites/player_2.png"),
	preload("res://assets/sprites/player_3.png"),
	preload("res://assets/sprites/player_4.png"),
]
const _ANIMS      := ["idle", "walk", "run", "windup", "slash", "halfslash", "collapse"]
const SLING_STONE := preload("res://scenes/sling_stone/sling_stone.tscn")
const DROPPED_ITEM := preload("res://scenes/dropped_item/dropped_item.tscn")
const MAX_DROPPED  := 40      # oldest ground item vanishes past this
const DROP_JITTER  := 0.25    # so repeated drops don't stack on one spot
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

# Replicated: the sling is being whirled (owner writes, every peer shows it)
var whirling := false:
	set(value):
		whirling = value
		_whirl_time = 0.0
		if _whirl != null:
			_whirl.visible = value

@onready var _sprite: CharacterSprite = $Sprite3D

func _ready() -> void:
	add_to_group("players")
	# Server-owned (host) player: don't replicate to a client still loading the
	# game scene — its copy of this node doesn't exist yet
	$MultiplayerSynchronizer.add_visibility_filter(func(id: int) -> bool:
		return not multiplayer.is_server() or id == 1 or NetworkManager.is_peer_ready(id))
	_sprite.setup(_SHEETS[0], _ANIMS)
	_sprite.footstep.connect(func(): Sfx.play("step", global_position))
	_sprite.play(anim)
	_carry_prop = Node3D.new()
	_carry_prop.position.y = CARRY_HEIGHT
	add_child(_carry_prop)
	_build_whirl()
	_hp_bar = HealthBar.new()
	_hp_bar.position.y = HP_BAR_Y
	add_child(_hp_bar)

func _process(delta: float) -> void:
	_update_beam()
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

func set_slot(slot: int, c: Color) -> void:
	slot_color = c
	_sprite.set_sheet(_SHEETS[slot % _SHEETS.size()], _ANIMS)
	_sprite.set_ring_color(c)

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	_sling_cd = maxf(0.0, _sling_cd - delta)
	_dash_cd = maxf(0.0, _dash_cd - delta)
	_update_focus(delta)
	if downed or GameState.is_over() or GameState.phase == GameState.Phase.STORY:
		velocity = Vector3.ZERO
		_dash_time = 0.0
		_cancel_charge()
		return
	if _is_busy:
		_cancel_charge()  # hit or acting — wind-up is lost
	_handle_movement(delta)
	if not _is_busy:
		_handle_interact()
		_handle_attack(delta)
	_update_anim()

# ── Movement ───────────────────────────────────────────────

func _handle_movement(delta: float) -> void:
	var dir := Vector3.ZERO
	for action in MOVE_DIRS:
		if Input.is_action_pressed(action):
			dir += MOVE_DIRS[action]
	if dir.length_squared() > 0:
		dir = dir.normalized()
	var on_beam := carried_kind == "beam" or helping_id != 0
	if Input.is_action_just_pressed("dash") and _dash_cd <= 0.0 and not _is_busy and not _charging and not on_beam:
		# Standing still: dash the way we're facing
		_dash_dir = dir if dir != Vector3.ZERO else _facing_vector()
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
		"up":    return MOVE_DIRS["move_north"].normalized()
		"left":  return MOVE_DIRS["move_west"].normalized()
		"right": return MOVE_DIRS["move_east"].normalized()
	return MOVE_DIRS["move_south"].normalized()

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

# Mirrors _server_interact's priorities from replicated state, so the ring shows
# exactly what [E] will act on — Overcooked's counter highlight.
func _focus_target(at: Vector3) -> Node3D:
	for p in get_tree().get_nodes_in_group("players"):
		if p != self and p.downed and at.distance_to(p.global_position) < REVIVE_REACH:
			return p
	if helping_id != 0:
		return null
	if not carried_kind.is_empty():
		return _nearest_in_reach("build_sites", at, func(s): return s.needs(carried_kind))
	var carrier := _carrier_needing_help(at)
	if carrier != null:
		return carrier
	var site := _nearest_in_reach("build_sites", at, func(s): return s.can_build())
	if site != null:
		return site
	var item := _nearest_in_reach("dropped_items", at, func(_i): return true)
	var pile := _nearest_in_reach("supply_piles", at, func(_p): return true)
	if item != null and (pile == null or _reach_dist(item, at) <= _reach_dist(pile, at)):
		return item
	return pile

func _update_focus(delta: float) -> void:
	_focus_poll -= delta
	if _focus_poll > 0.0:
		return
	_focus_poll = FOCUS_POLL
	if _focus_ring == null:
		_build_focus_ring()
	var target: Node3D = null
	if not downed and not GameState.is_over():
		target = _focus_target(global_position)
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
	if _is_busy:
		return
	var speed := velocity.length()
	if _charging:
		# Face the aim, not the walking direction, while winding up
		_facing = LPCFrames.dir_from_velocity(_aim_point - global_position, _facing)
		_sprite.speed_scale = 1.0
		anim = "windup_" + _facing
		return
	if speed < 0.1:
		_sprite.speed_scale = 1.0
		anim = "idle_" + _facing
		return
	if not _charging:
		_facing = LPCFrames.dir_from_velocity(velocity, _facing)
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
		anim = "idle_" + _facing

# ── Interact / Drop ────────────────────────────────────────

func _handle_interact() -> void:
	if Input.is_action_just_pressed("interact"):
		_server_interact.rpc_id(1, global_position)
	if Input.is_action_just_pressed("drop"):
		_server_drop.rpc_id(1, global_position)

# Owner sends its position with the request: the reliable RPC can overtake the
# unreliable position sync, so the server's copy may still be a frame behind.
@rpc("any_peer", "call_local", "reliable")
func _server_interact(at: Vector3) -> void:
	if not _from_owner() or downed:
		return
	# Helping a fallen teammate comes first
	for p in get_tree().get_nodes_in_group("players"):
		if p != self and p.downed and at.distance_to(p.global_position) < REVIVE_REACH:
			p._set_downed.rpc(false)
			_action.rpc("halfslash")
			return
	if helping_id != 0:
		_set_helping.rpc(0)
		_tell("Let go of the beam")
		return
	if carried_kind.is_empty():
		var carrier := _carrier_needing_help(at)
		if carrier != null:
			_set_helping.rpc(carrier.get_multiplayer_authority())
			_sfx.rpc("pickup")
			_tell("Holding the other end — [E] to let go")
			return
	# Nearest valid thing wins — sections and gate pillars overlap in reach
	if not carried_kind.is_empty():
		var dest := _nearest_in_reach("build_sites", at, func(s): return s.needs(carried_kind))
		if dest != null and dest.deposit(carried_kind, 1):
			_sfx.rpc("deposit_" + carried_kind)
			_set_carried.rpc("")
			_action.rpc("halfslash")
			# Last load for this stage → raise it straight away (no separate Build press)
			if dest.can_build() and dest.try_build():
				_tell("Stage built!")
			return
		_tell(_why_not_needed(at))
		return
	# Fallback for sections that were already full (e.g. filled before a change of rules)
	var site := _nearest_in_reach("build_sites", at, func(s): return s.can_build())
	if site != null and site.try_build():
		_action.rpc("halfslash")
		return
	# Whichever is closer: something lying on the ground, or a stockpile
	var item := _nearest_in_reach("dropped_items", at, func(_i): return true)
	var pile := _nearest_in_reach("supply_piles", at, func(_p): return true)
	if item != null and (pile == null or _reach_dist(item, at) <= _reach_dist(pile, at)):
		var kind: String = item.kind
		if item.take():
			_sfx.rpc("pickup")
			_set_carried.rpc(kind)
		return
	if pile != null and pile.request_pickup():
		_sfx.rpc("pickup")
		_set_carried.rpc(pile.kind)

# Server: explain a refused delivery (the carried material isn't wanted here)
func _why_not_needed(at: Vector3) -> String:
	var wall := _nearest_in_reach("build_sites", at, func(_s): return true)
	if wall == null:
		if _nearest_in_reach("supply_piles", at, func(_p): return true) != null:
			return "Hands full — deliver it, or [G] to drop"
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
		_drop_carried(at)

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
		_toast("Heavy — a partner can take the other end [E]")
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
		if Input.is_action_just_pressed("throw_charge") and _sling_cd <= 0.0 and get_viewport().gui_get_hovered_control() == null:
			_charging = true
			_charge = 0.0
			whirling = true
		return
	_charge = minf(1.0, _charge + delta / SLING_CHARGE_TIME)
	_update_aim(_cursor_on_ground())
	if not Input.is_action_pressed("throw_charge"):
		release_throw()

## Owner: finish the wind-up and throw at the current aim point
func release_throw() -> void:
	if not _charging:
		return
	var land := _aim_point
	var charge := _charge
	_cancel_charge()
	_sling_cd = SLING_COOLDOWN
	_facing = LPCFrames.dir_from_velocity(land - global_position, _facing)
	_play_action("slash")
	# Release on the swing's release frame, not at wind-up
	while is_instance_valid(self) and _sprite.animation.begins_with("slash") \
			and _sprite.frame < SLING_RELEASE_FRAME:
		await _sprite.frame_changed
	if is_instance_valid(self) and _sprite.animation.begins_with("slash"):
		_server_sling.rpc_id(1, global_position, land, charge)

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
	var locked := _assist_target(global_position, _aim_point, reach)
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

static func _sling_range(charge: float) -> float:
	return lerpf(SLING_MIN_RANGE, SLING_MAX_RANGE, charge)

# Enemy nearest the aim line inside the assist cone and within reach, or null
func _assist_target(from: Vector3, land: Vector3, reach: float) -> Node3D:
	var aim := Vector2(land.x - from.x, land.z - from.z)
	if aim.length_squared() < 0.001:
		return null
	var best: Node3D = null
	var best_angle := deg_to_rad(AIM_ASSIST_DEG)
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
func _server_sling(at: Vector3, land: Vector3, charge: float) -> void:
	if not _from_owner() or downed:
		return
	charge = clampf(charge, 0.0, 1.0)
	var reach := _sling_range(charge)
	# Don't trust the client's landing point beyond what its charge allows
	var flat := Vector3(land.x - at.x, 0.0, land.z - at.z)
	if flat.length() > reach:
		land = Vector3(at.x, GROUND_Y, at.z) + flat.normalized() * reach
	var target := _assist_target(at, land, reach)
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
	stone.init(target, land, damage)

# ── Damage / Downed (server) ───────────────────────────────

func take_damage(amount: float) -> void:
	if not multiplayer.is_server() or downed:
		return
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
	if is_multiplayer_authority() and not _is_busy and new_health > 0.0:
		# Short stagger — the sheet's "hurt" row is a full collapse, kept for downed
		_is_busy = true
		await get_tree().create_timer(STAGGER_TIME).timeout
		if is_instance_valid(self) and not downed:
			_is_busy = false

@rpc("any_peer", "call_local", "reliable")
func _set_downed(value: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	downed = value
	Sfx.play("downed" if value else "revive", global_position)
	if value:
		_down_timer = DOWNED_TIME
	else:
		health = MAX_HEALTH * REVIVE_HEALTH
	if is_multiplayer_authority():
		_is_busy = value
		_sprite.speed_scale = 1.0
		anim = "collapse" if value else "idle_" + _facing

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

# Server → owning player only
func _tell(text: String) -> void:
	_feedback.rpc_id(get_multiplayer_authority(), text)

@rpc("any_peer", "call_local", "reliable")
func _feedback(text: String) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		_toast(text)

# Short floating line above the head (local only)
func _toast(text: String) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = _FONT
	l.font_size = 34
	l.pixel_size = 0.01
	l.outline_size = 10
	l.modulate = Color(0.98, 0.95, 0.88)
	l.outline_modulate = Color(0.20, 0.14, 0.08)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
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
	if not carried_kind.is_empty() and carried_kind != "beam":
		_carry_prop.add_child(DroppedItem.build_prop(carried_kind))

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
