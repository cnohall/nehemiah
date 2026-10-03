class_name Player
extends CharacterBody3D

# Owning peer drives movement + animation (replicated via MultiplayerSynchronizer).
# World changes — pickups, deposits, building, sling hits, health, downed state —
# go through the server.

const MAX_HEALTH      := 100.0
const RUN_SPEED       := 8.0
const CARRY_SPEED     := 5.5
const DEBRIS_SLOW     := 0.7   # charred timbers off a burned footing are awkward and heavy
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
const SLING_KNOCK_MIN  := 0.15    # m a stone shoves a scout back, light charge…
const SLING_KNOCK_MAX  := 0.55    # …and full
# True shot (GDD §5.16, Judg. 20:16 "could sling stones at a hair and not miss"): at full
# spin the stone glints once a beat — at full charge, then every TRUE_PERIOD. Let go within
# TRUE_HALF of a glint and the stone strikes ×TRUE_MULT and knocks the foe off his feet.
# A ring closes on the aim ring over TRUE_LEAD before each glint, so it can be timed
const TRUE_PERIOD      := 0.75
const TRUE_HALF        := 0.11
const TRUE_LEAD        := 0.4
const TRUE_MULT        := 1.5
const TRUE_KNOCK       := 1.4     # m a true shot throws a scout back as he goes down
const AIM_RING_TRUE    := Color(1.0, 0.86, 0.48, 1.0)    # the aim ring in the window: gold
const ARC_DOTS         := 9       # dotted flight arc from the hand to the aim ring
const SWORD_REACH     := 2.0      # a foe this close turns the sling press into a sword cut
const SWORD_ARC_DEG   := 65.0     # half-width of the cut, either side of the foe we turned to
const SWORD_DAMAGE    := 20.0     # scout 2 cuts, raider 3, brute 5
const SWORD_COOLDOWN  := 0.45
const SWORD_KNOCKBACK := 1.3      # metres a scout is shoved (brutes feel ~a third)
const SWORD_HIT_FRAME := 2        # frame of the "sword" anim where the blade lands
const POT_REACH       := 1.0      # a jar or basket this close (no foe about) takes the cut instead
# Turn the blow (GDD §5.16, `--no-riposte`): a cut that lands while a foe draws back to strike
# strikes ×RIPOSTE_MULT and knocks him off his feet, brute or not — the sword's true shot
const RIPOSTE_MULT    := 1.5
const RIPOSTE_KNOCK   := 1.4      # m a scout is thrown back as he goes down
const BLADE_COLOR     := Color(1.0, 0.98, 0.94, 0.75)   # the cut's sweep
const BLADE_TRUE      := Color(1.0, 0.76, 0.3, 0.9)      # …gold when it turns a blow
const AIM_ASSIST_DEG   := 18.0   # enemies inside this cone of the aim get homed on
const CHARGE_MOVE_MULT := 0.55    # slower while winding up
const AIM_RING_LOCKED  := Color(0.86, 0.38, 0.26, 0.9)
const AIM_RING_FREE    := Color(0.45, 0.30, 0.12, 0.85)   # dark ochre — reads on sand
const GROUND_Y         := 0.1     # top of the floor slab
const WHIRL_RADIUS     := 0.42
const HP_BAR_Y         := 2.75
const DOWNED_BAR_COLOR := Color(0.78, 0.30, 0.20)
const WHIRL_SPIN_MIN   := 9.0     # rad/s at the start of the wind-up…
const WHIRL_SPIN_MAX   := 24.0    # …and at full charge
const STAGGER_TIME    := 0.2
const DOWNED_TIME     := 8.0      # self-revive, only when nobody is left standing to help
const REVIVE_HEALTH   := 1.0
# Climbing over a standing wall ([E] against it, nothing else to do)
const CLIMB_CLEAR     := 0.9      # metres past the far face
const CLIMB_HEIGHT    := 2.6
const CLIMB_TIME      := 0.55
const RESPAWN_POS     := Vector3(0, 0.1, 8)   # y = floor top (no gravity — the world is flat)
# Walkable rectangle in x/z — inside the 100 × 80 floor, clear of its edge
const PLAY_AREA       := Rect2(-44.0, -25.0, 88.0, 49.7)   # = Terrain.FLAT_FOE … FLAT_CITY: the valley and the hill start past it
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
const BEAM_HELP_REACH := 3.2      # from the carrier: covers the dragging end, where the tag is
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
# long haul at the Gate of the Ash Heaps is a chain of these)
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
var _slot := 0                  # crew slot, set by Main (picks the dusk dance)
var trade := 0                  # Trade, set by Main with the slot: what this worker is quicker at
var _slotted := false
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
var _whirl_stone: Node3D        # the stone in the pouch (where a glint shows)
var _whirl_rev := 0             # passes round the head so far (one whoosh each)
var _glint_beat := -1           # last true-shot beat glinted
var _held := 0.0                # owner: seconds the sling has been whirling this throw
var _approach: MeshInstance3D   # owner: the ring that closes on the aim ring before a glint
var _arc_dots: Array[MeshInstance3D] = []
static var _true_told := false  # the "let go as it glints" hint, once a session
static var _riposte_told := false   # the "cut as he draws back" hint, once a session
var _hp_bar: HealthBar
var _dash_time := 0.0
var _dash_cd := 0.0
var _dash_dir := Vector3.ZERO
var _focus_ring: MeshInstance3D
var _focus_poll := 0.0
var _beam: Node3D   # carried beam, placed in world space between the two ends
var _beam_tag: WorldTag   # "Take the other end" over a lone beam's dragging end, for the others
var _buffered := {}   # action → seconds left to act on an early press
# Hands-on building: the site we're working at (owner) / registered with (server)
var _work_site: Node3D
var building_site: Node3D
var _move_dir := Vector3.ZERO   # last non-zero move input (pad aim falls back to it)
var _led_by: Node3D             # owner: the messenger we're following to Ono
var _led_time := 0.0
var _led_server := false        # server: this worker went with a messenger
var _climbing := false          # owner: mid-hop over a wall

# Replicated: the sling is being whirled (owner writes, every peer shows it)
var whirling := false:
	set(value):
		whirling = value
		_whirl_time = 0.0
		_whirl_rev = int(_whirl_angle / TAU)
		_glint_beat = -1
		if _whirl != null:
			_whirl.visible = value

# Replicated: world yaw the sling is aimed along (owner writes while winding up / throwing)
var aim_yaw := 0.0:
	set(value):
		aim_yaw = value
		if _sprite != null:
			_sprite.aim_yaw = value

@onready var _sprite: CharacterRig = $Figure

## This peer's own worker, or null before it spawns
static var local: Player

# Bots (BotBrain) are workers too: named from this range instead of a peer id and owned by
# the host, whose copy is steered by the brain in place of keys / pad. Everything that
# means "which worker" uses worker_id(), not the multiplayer authority.
const BOT_ID_BASE := 1 << 31   # past every peer id (those fit in 31 bits)
## Host only, bots only
var brain: BotBrain

static func is_bot_id(id: int) -> bool:
	return id >= BOT_ID_BASE

func worker_id() -> int:
	return name.to_int()

func is_bot() -> bool:
	return is_bot_id(worker_id())

func _ready() -> void:
	add_to_group("players")
	if is_multiplayer_authority() and not is_bot():
		local = self
	# Server-owned (host) player: don't replicate to a client still loading the
	# game scene — its copy of this node doesn't exist yet
	$MultiplayerSynchronizer.add_visibility_filter(func(id: int) -> bool:
		return not multiplayer.is_server() or id == 1 or NetworkManager.is_peer_ready(id))
	_sprite.setup(CharacterRig.worker_look(0, _DEFAULT_ROBE))
	_sprite.footstep.connect(func(): Sfx.play("step", global_position))
	_sprite.strike.connect(_on_strike)
	# The whirl follows the hand, so place it once the rig has posed this frame
	_sprite.posed.connect(func(delta: float):
		if whirling:
			_update_whirl(delta))
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
	if downed:
		# A teammate has to raise you. Only with nobody left standing (solo, or the whole
		# crew down) does the countdown run: every peer counts locally, the server decides.
		if _nobody_to_raise():
			_down_timer -= delta
			_hp_bar.show_value(_down_timer / DOWNED_TIME, DOWNED_BAR_COLOR)
			if multiplayer.is_server() and _down_timer <= 0.0:
				_set_downed.rpc(false)
		else:
			_hp_bar.show_value(1.0, DOWNED_BAR_COLOR)
		_update_raise_tag()
	else:
		_hp_bar.show_health(health / MAX_HEALTH)

func _nobody_to_raise() -> bool:
	return get_tree().get_nodes_in_group("players").all(func(p): return p == self or p.downed)

# "Help up [E]" over a downed worker, for everyone but the fallen one — nobody found the
# revive in playtest 2 without it
var _raise_tag: WorldTag

func _update_raise_tag() -> void:
	var shown := downed and Player.local != null and Player.local != self and not Player.local.downed
	if shown and _raise_tag == null:
		_raise_tag = WorldTag.make(WorldTag.Kind.SITE)
		_raise_tag.position.y = PIP_Y + 0.5
		add_child(_raise_tag)
	if _raise_tag != null:
		_raise_tag.visible = shown
		_raise_tag.pulse = shown
		if shown:
			_raise_tag.text = "Help up  [%s]" % InputMode.key("interact")

func _exit_tree() -> void:
	if local == self:
		local = null

func set_slot(slot: int, c: Color, trade_index := -1) -> void:
	var t := trade_index if trade_index >= 0 else slot % CharacterRig.TRADES.size()
	if _slotted and slot == _slot and c == slot_color and t == trade:
		return   # the crew list changed, not us — don't rebuild the rig
	_slotted = true
	_slot = slot
	slot_color = c
	trade = t
	_sprite.set_look(CharacterRig.worker_look(trade, c))
	_sprite.set_ring_color(Color(0, 0, 0, 0) if GameState.attract else c)   # the title backdrop stays unmarked
	_refresh_pip()
	_rebuild_carry_prop()   # a new rig means a new chest anchor

## "Carpenter" etc. — untranslated (callers tr() it)
func trade_name() -> String:
	return CharacterRig.TRADES[trade]

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
	_pip.visible = GameState.crew_size > 1 and not GameState.attract
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
	if brain != null:
		brain.think(delta)
	_buffer_input(delta)
	if brain == null:
		_update_focus(delta)
	if downed or GameState.is_over() or GameState.phase == GameState.Phase.STORY:
		velocity = Vector3.ZERO
		_dash_time = 0.0
		_cancel_charge()
		_update_anim()   # else the last run cycle keeps looping on the spot
		return
	if _led_by != null:
		_follow_leader(delta)
		return
	if _hold_time > 0.0:   # answering a visitor: stand and say it
		_hold_time -= delta
		velocity = Vector3.ZERO
		_update_anim()
		return
	if _work_site != null:
		if _wants_to_stop_work():
			_stop_work()
		else:
			velocity = Vector3.ZERO
			return
	if _climbing:
		velocity = Vector3.ZERO   # the hop's tween moves us, through the wall's collision
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
## Explore Jerusalem (and the campaign with Settings.turn_to_map) turns the view so north
## sits up-screen (Main.set_view_yaw); the stick turns with it. 0 everywhere else.
static var view_yaw := 0.0

static func screen_to_ground(v: Vector2) -> Vector3:
	return (SCREEN_RIGHT * v.x + SCREEN_DOWN * v.y).rotated(Vector3.UP, view_yaw)

# Remember presses for a moment, so one made during a pickup / throw animation still counts
func _buffer_input(delta: float) -> void:
	if brain == null and InputMode.gameplay_blocked():
		_buffered.clear()
		return
	for action: String in ["interact", "drop", "dash", "horn"]:
		if brain.take_press(action) if brain != null else Input.is_action_just_pressed(action):
			_buffered[action] = INPUT_BUFFER
		elif _buffered.has(action):
			_buffered[action] -= delta
			if _buffered[action] <= 0.0:
				_buffered.erase(action)

func _consume(action: String) -> bool:
	return _buffered.erase(action)

# Stick / keys, zero while a menu is up (the pad is navigating it, not walking)
func _move_input() -> Vector2:
	if brain != null:
		return brain.move
	if InputMode.gameplay_blocked():
		return Vector2.ZERO
	return Input.get_vector("move_west", "move_east", "move_north", "move_south", STICK_DEADZONE)

func _throw_just_pressed() -> bool:
	if brain != null:
		return brain.throw_pressed
	return Input.is_action_just_pressed("throw_charge") and not InputMode.gameplay_blocked()

func _handle_movement(delta: float) -> void:
	# Bots steer in the game's own view: the host's turned camera is none of theirs
	var dir := screen_to_ground(_move_input()) if brain == null 		else (SCREEN_RIGHT * brain.move.x + SCREEN_DOWN * brain.move.y)
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
		var target := dir * (CARRY_SPEED * Trade.carry_mult(trade) * GameState.mod("carry") * (DEBRIS_SLOW if carried_kind == "debris" else 1.0) if not carried_kind.is_empty() else RUN_SPEED)
		if on_beam:
			target = dir * (BEAM_PAIR_SPEED if _beam_partner() != null else minf(BEAM_SOLO_SPEED * GameState.mod("beam_solo"), BEAM_PAIR_SPEED))
		if _charging:
			target *= CHARGE_MOVE_MULT
		var rate := ACCEL if target.length_squared() > velocity.length_squared() else DECEL
		velocity = velocity.move_toward(target, rate * delta)
	move_and_slide()
	if _dash_time <= 0.0 and not on_beam:
		_nudge_apart(delta)
	_tether_to_partner()
	global_position.x = clampf(global_position.x, PLAY_AREA.position.x, PLAY_AREA.end.x)
	global_position.z = clampf(global_position.z, PLAY_AREA.position.y, PLAY_AREA.end.y)

# Workers overlapping at a work site drift apart gently (a position nudge, not a
# collision, so nobody gets blocked or shoved off their line)
const NUDGE_RADIUS := 0.8
const NUDGE_SPEED := 1.6

func _nudge_apart(delta: float) -> void:
	var push := Vector3.ZERO
	for o in get_tree().get_nodes_in_group("players"):
		if o == self or not (o is Node3D) or o.downed:
			continue
		var off: Vector3 = global_position - o.global_position
		off.y = 0.0
		var d := off.length()
		if d >= NUDGE_RADIUS:
			continue
		if d < 0.02:   # exactly stacked: split by id so the pair goes opposite ways
			off = Vector3.RIGHT * (1.0 if get_instance_id() > o.get_instance_id() else -1.0)
			d = 0.02
		push += off / d * (1.0 - d / NUDGE_RADIUS)
	if push != Vector3.ZERO:
		global_position += push.limit_length(1.0) * NUDGE_SPEED * delta

# ── Beams ──────────────────────────────────────────────────

## The worker on the other end of our beam, or null
func _beam_partner() -> Node3D:
	if helping_id != 0:
		return get_parent().get_node_or_null(str(helping_id))
	if carried_kind == "beam":
		var me := worker_id()
		for p in get_tree().get_nodes_in_group("players"):
			if p.helping_id == me:
				return p
	return null

# Owner: can't walk further from the other end than the beam allows — the pair has to
# move together (each side clamps itself, so neither can drag the other). The pull
# collides: snapping straight to the partner dragged workers through solid terrain
# (into a burned house shell, where they couldn't find the way out)
func _tether_to_partner() -> void:
	var partner := _beam_partner()
	if partner == null:
		return
	var off := global_position - partner.global_position
	off.y = 0.0
	if off.length() > BEAM_TETHER:
		var p := partner.global_position + off.normalized() * BEAM_TETHER
		move_and_collide(Vector3(p.x - global_position.x, 0.0, p.z - global_position.z))

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
	var me := worker_id()
	for p in get_tree().get_nodes_in_group("players"):
		if p.helping_id == me:
			p._set_helping.rpc(0)

# Every peer: lay the beam from our shoulder to the partner's, or drag it behind us alone
func _update_beam() -> void:
	if carried_kind != "beam":
		if _beam != null:
			_beam.queue_free()
			_beam = null
			_beam_tag = null
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
	_update_beam_tag(b, partner == null)

# Playtest: nobody knew a beam takes two. While one drags it alone, the free end asks
# every other worker (on their own screen) to take it — once they stand free to help.
func _update_beam_tag(free_end: Vector3, alone: bool) -> void:
	var me := Player.local
	var shown := alone and me != null and me != self and not me.downed and me.carried_kind.is_empty() 		and me.helping_id == 0 and GameState.phase == GameState.Phase.WORK
	if shown and _beam_tag == null:
		_beam_tag = WorldTag.make(WorldTag.Kind.SITE)
		_beam_tag.top_level = true
		_beam.add_child(_beam_tag)
	if _beam_tag == null:
		return
	_beam_tag.visible = shown
	_beam_tag.pulse = shown
	if shown:
		_beam_tag.global_position = free_end + Vector3.UP * 1.6
		_beam_tag.text = tr("Take the other end  [%s]") % InputMode.key("interact")

func _facing_vector() -> Vector3:
	match _facing:
		"up":    return -SCREEN_DOWN
		"left":  return -SCREEN_RIGHT
		"right": return SCREEN_RIGHT
	return SCREEN_DOWN

# Owner → everyone: puff of dust + stretch so a dash reads on every screen
@rpc("authority", "call_local", "unreliable")
func _dash_fx() -> void:
	if multiplayer.is_server():
		get_tree().call_group("breakable_set", "note_dash", self)   # anything run through breaks
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
enum Act { NONE, REVIVE, LET_GO, HELP, DELIVER, MESSENGER, WORK, TAKE_ITEM, TAKE_PILE, CLIMB, TALK, TIDY }

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
		var dest := _nearest_in_reach("build_sites", at, func(s): return s.needs(carried_kind))
		if dest == null:   # a hungry household of the Fountain Gate (Neh. 5)
			dest = _nearest_in_reach("households", at, func(h): return h.needs(carried_kind))
		if dest == null and carried_kind != "beam" and _wall_to_climb(at) != null:
			return [Act.CLIMB, _wall_to_climb(at)]
		return [Act.DELIVER, dest]
	var carrier := _carrier_needing_help(at)
	if carrier != null:
		return [Act.HELP, carrier]
	# Everything delivered, waiting for hands
	var site := _nearest_in_reach("build_sites", at, func(s): return s.can_build())
	var item := _nearest_in_reach("dropped_items", at, func(_i): return true)
	var pile := _nearest_in_reach("supply_piles", at, func(_p): return true)
	# A visitor talking at our elbow (GDD §6.7) takes [E] — answer him, hear him — even over
	# the wall he caught us at. Old rules (`--old-messenger`): only when nearer than anything
	# else, and the press goes with him — a careless press was the trap.
	var messenger := _nearest_in_reach("messengers", at, func(_m): return true)
	if messenger != null:
		if not Messenger.old_rules and messenger.at_elbow(self):
			return [Act.MESSENGER, messenger]
		var d := _reach_dist(messenger, at)
		if [site, item, pile].all(func(o): return o == null or _reach_dist(o, at) >= d):
			return [Act.MESSENGER, messenger]
	# Townsfolk to talk to (the festival): when nearer than any work
	var folk := _nearest_in_reach("folk", at, func(_f): return true)
	if folk != null:
		var d := _reach_dist(folk, at)
		if [site, item, pile].all(func(o): return o == null or _reach_dist(o, at) >= d):
			return [Act.TALK, folk]
	if site != null:
		return [Act.WORK, site]
	# A pile the saboteur strewed: tidy it (worked like a stage) before it gives anything
	var mess := _nearest_in_reach("scattered_piles", at, func(p): return p.can_build())
	if mess != null and (item == null or _reach_dist(mess, at) <= _reach_dist(item, at)):
		return [Act.TIDY, mess]
	# Whichever is closer: something lying on the ground, or a stockpile
	if item != null and (pile == null or _reach_dist(item, at) <= _reach_dist(pile, at)):
		return [Act.TAKE_ITEM, item]
	if pile != null:
		return [Act.TAKE_PILE, pile]
	# Last resort: over a standing wall, so nobody is shut out when the stretch closes
	var wall := _wall_to_climb(at)
	if wall != null:
		return [Act.CLIMB, wall]
	return [Act.NONE, null]

## A wall that blocks workers, within reach of `at` (null = none)
func _wall_to_climb(at: Vector3) -> Node3D:
	return _nearest_in_reach("build_sites", at,
		func(s): return s.has_method("blocks_workers") and s.blocks_workers())

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
	var lift := 0.05
	if target.is_in_group("supply_piles") or target.is_in_group("scattered_piles"):
		size = 2.6
		lift = 0.1   # over the pile's flagstone pad
	elif target.has_method("approach_point"):
		spot = target.approach_point(global_position, 0.0)
	elif target.is_in_group("dropped_items"):
		size = 1.1
	_focus_ring.global_position = Vector3(spot.x, GROUND_Y + lift, spot.z)
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
		_face_aim(_aim_point)
		_sprite.speed_scale = 1.0
		anim = "windup_" + _facing
		return
	if speed < 0.1:
		_sprite.speed_scale = 1.0
		# The day's work done (or the wall finished): standing still, the crew dances
		var dancing := GameState.phase in [GameState.Phase.DUSK, GameState.Phase.WON] \
			and carried_kind.is_empty() and helping_id == 0 and not GameState.attract
		anim = (CharAnim.DANCES[_slot % CharAnim.DANCES.size()] if dancing else "idle") + "_" + _facing
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
	# At dusk [E] is held to say you're ready (the tally's ReadyRow), not to pick things up
	if GameState.phase == GameState.Phase.DUSK and brain == null:
		_consume("interact")
		return
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
			if brain == null:
				target.bark("Thank you, friend!", true)   # a bot helped up by a person
		Act.LET_GO:
			_set_helping.rpc(0)
			_tell("Let go of the beam")
		Act.HELP:
			_set_helping.rpc(target.worker_id())
			_sfx.rpc("pickup")
			_tell("Holding the other end — {interact} to let go")
		Act.DELIVER:
			_deliver(target, at)
		Act.TALK:
			target.talk(self)
		Act.MESSENGER:
			target.answer(self)
		Act.WORK:
			if GameState.active_build:
				_start_work(target)
			elif target.try_build():
				_action.rpc("halfslash")
		Act.TIDY:
			_start_work(target)
		Act.TAKE_ITEM:
			var kind: String = target.kind
			if target.take():
				_sfx.rpc("pickup")
				_set_carried.rpc(kind)
		Act.TAKE_PILE:
			if target.request_pickup():
				_sfx.rpc("pickup")
				_set_carried.rpc(target.kind)
		Act.CLIMB:
			# The spot mirrored through the wall, stepped clear of its far face
			var here := target.to_local(at)
			var far := target.to_global(Vector3(here.x, here.y, -here.z))
			_climb_over.rpc_id(get_multiplayer_authority(), target.approach_point(far, CLIMB_CLEAR))
			_sfx.rpc("dash")

# Owner (position is owner-driven): hop over the wall to `dest`
@rpc("any_peer", "call_local", "reliable")
func _climb_over(dest: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != 1 or not is_multiplayer_authority() or _is_busy or _climbing:
		return
	_climbing = true
	_cancel_charge()
	_dash_time = 0.0
	_facing = CharAnim.dir_from_velocity(dest - global_position, _facing)
	anim = "idle_" + _facing
	_sprite.squash(Vector2(0.9, 1.12))
	var from := global_position
	dest.y = from.y
	var tw := create_tween()
	tw.tween_method(func(t: float):
		global_position = from.lerp(dest, t) + Vector3.UP * sin(t * PI) * CLIMB_HEIGHT, 0.0, 1.0, CLIMB_TIME)
	await tw.finished
	if is_instance_valid(self):
		global_position = dest
		_climbing = false
		_sprite.squash(Vector2(1.1, 0.9))

# Server: hand the carried load to `dest` (null = nothing near wants it)
func _deliver(dest: Node3D, at: Vector3) -> void:
	if dest == null or not dest.deposit(carried_kind, 1):
		var why := _why_not_needed(at)
		_tell(why[0], why[1])
		return
	get_tree().call_group("day_director", "note_load", worker_id(), dest)
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

# Server: explain a refused delivery (the carried material isn't wanted here).
# [message, material for its {need}]
func _why_not_needed(at: Vector3) -> PackedStringArray:
	if carried_kind == "debris":
		return ["Rubbish — carry it clear of the footing, then {drop}", ""]
	var wall := _nearest_in_reach("build_sites", at, func(_s): return true)
	if wall == null:
		if _nearest_in_reach("supply_piles", at, func(_p): return true) != null:
			return ["Hands full — deliver it, or {drop} to drop", ""]
		return ["Bring it to a wall", ""]
	if wall.has_method("refusal"):   # a watch post explains itself
		return [wall.refusal(carried_kind), ""]
	var need: String = wall.next_need()
	if not need.is_empty():
		return ["Needs {need} first", need]
	if wall.can_build():
		# Every load for this stage is in; it only wants working before the next material
		return ["Build this stage first — {drop} to drop, then {interact} to work", ""]
	return ["This wall is finished", ""]

@rpc("any_peer", "call_local", "reliable")
func _server_drop(at: Vector3) -> void:
	if not _from_owner():
		return
	if helping_id != 0:
		_set_helping.rpc(0)
	elif carried_kind == "debris" and _at_tip(at):
		_set_carried.rpc("")   # set down on the tip: tipped out, not passed or left lying
		_sfx.rpc("drop")
	elif not carried_kind.is_empty():
		var mate := _free_hands_near(at)
		if mate != null:
			_hand_over(mate)
		else:
			_drop_carried(at)

func _at_tip(at: Vector3) -> bool:
	for s in get_tree().get_nodes_in_group("build_sites"):
		if s.has_method("at_tip") and s.at_tip(at):
			return true
	return false

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
	# The long haul's relay mat: stacked in a free place, not left loose
	for mat: Node3D in get_tree().get_nodes_in_group("relay_mats"):
		if at.distance_to(mat.global_position) < mat.REACH:
			var slot: Vector3 = mat.free_slot()
			if slot != Vector3.INF:
				item.position = Vector3(slot.x, GROUND_Y, slot.z)
				if not RelayMat.told:
					RelayMat.told = true
					_tell("Left on the relay mat — the porter carries it to the wall")
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
	elif not kind.is_empty() and is_multiplayer_authority() and Trade.carry_mult(trade) > 1.0:
		_knack("Your trade — quicker with a load")
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
	_riposte_hint()
	if not _charging:
		# A click on HUD buttons / the Esc menu isn't a throw
		if _throw_just_pressed() and _sling_cd <= 0.0 and (brain != null or get_viewport().gui_get_hovered_control() == null):
			if brain != null:
				brain.throw_pressed = false
			# Foe at arm's length: no time to whirl — draw the sword instead (Neh. 4:18)
			var foe := _foe_in_sword_reach()
			if foe != null:
				_swing_sword(foe)
				return
			var pot := _pot_in_reach()
			if pot != null:
				_swing_sword(pot)
				return
			_charging = true
			_charge = 0.0
			_held = 0.0
			whirling = true
		return
	if brain == null and InputMode.gameplay_blocked():
		_cancel_charge()   # opened the menu mid wind-up
		return
	_charge = minf(1.0, _charge + delta / SLING_CHARGE_TIME)
	_held += delta
	if brain != null:
		_update_aim(brain.aim_point)
		if _charge >= brain.charge_goal:
			release_throw()
		return
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
	# Judged at the release press, not when the stone leaves the hand. Bots land one now
	# and then by skill (their let-go at full charge always falls on the first glint)
	var true_shot := GameState.true_shot and absf(true_offset(_held)) <= TRUE_HALF \
		and (brain == null or randf() < float(brain.skill.get("true", 0.0)))
	if true_shot:
		charge = 1.0   # a hair early still counts as full
	_cancel_charge(true)   # the stone keeps whirling through the cast until it's let go
	_sling_cd = SLING_COOLDOWN
	_face_aim(land)
	_play_action("slash")
	# Release on the swing's release frame, not at wind-up
	while is_instance_valid(self) and _sprite.animation.begins_with("slash") \
			and _sprite.frame < SLING_RELEASE_FRAME:
		await _sprite.frame_changed
	if not is_instance_valid(self):
		return
	whirling = false
	if _sprite.animation.begins_with("slash"):
		_sprite.squash(Vector2(1.08, 0.94))
		_server_sling.rpc_id(1, global_position, land, charge, InputMode.using_pad or brain != null, true_shot)
		if true_shot and brain == null:
			InputMode.rumble(0.2, 0.0, 0.06)
		if Trade.hit_mult(trade) > 1.0:
			_knack("Your trade — your blows land harder")

# ── Sword ──────────────────────────────────────────────────

func _foe_in_sword_reach() -> Node3D:
	var best: Node3D = null
	var best_d := SWORD_REACH
	for enemy: Node3D in get_tree().get_nodes_in_group("enemies"):
		var d := Vector2(enemy.global_position.x - global_position.x,
			enemy.global_position.z - global_position.z).length()
		if d < best_d:
			best_d = d
			best = enemy
	return best

# A jar or basket at arm's length — only when no foe is in sling range, so a pot at
# your feet never steals a throw
func _pot_in_reach() -> Node3D:
	for enemy: Node3D in get_tree().get_nodes_in_group("enemies"):
		if global_position.distance_to(enemy.global_position) < SLING_MAX_RANGE:
			return null
	var pots := get_tree().get_first_node_in_group("breakable_set")
	return pots.piece_in_reach(global_position, POT_REACH) if pots else null

## Owner: cut at the nearest foe (or jar); the server works out what the blade catches
func _swing_sword(foe: Node3D) -> void:
	_sling_cd = SWORD_COOLDOWN * _rally(&"rally_sword_cd")
	_face_aim(foe.global_position)
	_play_action("sword")
	_sprite.squash(Vector2(1.06, 0.95))
	while is_instance_valid(self) and _sprite.animation.begins_with("sword") \
			and _sprite.frame < SWORD_HIT_FRAME:
		await _sprite.frame_changed
	if not is_instance_valid(self) or not _sprite.animation.begins_with("sword"):
		return   # knocked out of the swing before it landed
	_server_sword.rpc_id(1, global_position, aim_yaw)
	if Trade.hit_mult(trade) > 1.0 and is_instance_valid(foe) and foe.is_in_group("enemies"):   # not a jar
		_knack("Your trade — your blows land harder")

@rpc("any_peer", "call_local", "reliable")
func _server_sword(at: Vector3, yaw: float) -> void:
	if not _from_owner() or downed:
		return
	var fwd := Vector2(sin(yaw), cos(yaw))
	var hit := false
	var turned := PackedVector3Array()   # where a blow was turned (for the look)
	for enemy: Node3D in get_tree().get_nodes_in_group("enemies"):
		var to := Vector2(enemy.global_position.x - at.x, enemy.global_position.z - at.z)
		# A little slack on reach: the foe kept walking during the wind-up
		if to.length() > SWORD_REACH + 0.4 or absf(fwd.angle_to(to)) > deg_to_rad(SWORD_ARC_DEG):
			continue
		# Asked before the damage: a hit in the draw ends it
		var turn: bool = GameState.riposte and enemy.has_method("drawing") and enemy.drawing()
		var damage := SWORD_DAMAGE * Trade.hit_mult(trade) * _rally(&"rally_damage", at)
		enemy.take_damage(damage * (RIPOSTE_MULT if turn else 1.0), worker_id())
		if turn:
			enemy.knock_down(Vector3(to.x, 0.0, to.y), RIPOSTE_KNOCK)
			turned.append(enemy.global_position)
		else:
			enemy.knock_back(Vector3(to.x, 0.0, to.y), SWORD_KNOCKBACK)
		hit = true
	var pots := get_tree().get_first_node_in_group("breakable_set")
	if pots and pots.smash_arc(at, fwd, SWORD_REACH + 0.4, SWORD_ARC_DEG):
		hit = true
	_sword_fx.rpc(hit, yaw, turned)

# Server → everyone: the swish and the sweep of the blade; a turned blow rings, flashes and
# throws dust; a jolt for whoever landed it
@rpc("any_peer", "call_local", "reliable")
func _sword_fx(hit: bool, yaw: float, turned: PackedVector3Array) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	Sfx.play("sword", global_position)
	_blade_sweep(yaw, not turned.is_empty())
	var scene := get_tree().current_scene
	for at in turned:
		var chest := at + Vector3.UP * 0.9
		Sfx.play("riposte", chest)
		SlingStone.flash(scene, chest, 1.2, 0.2)
		DustFx.puff(scene, at + Vector3.UP * 0.2, 12, 0.9)
	if not turned.is_empty():
		_sprite.hitstop(0.14)   # the blade bites: a held beat on the swing
	if not is_multiplayer_authority():
		return
	if not turned.is_empty():
		_jolt(0.32, 0.6, 0.8, 0.16)
	elif hit:
		_jolt(0.25, 0.3, 0.45, 0.1)

# Every peer: a thin crescent swept round in front of the worker, gone in a breath
func _blade_sweep(yaw: float, gold: bool) -> void:
	var half := deg_to_rad(SWORD_ARC_DEG)
	var outer := SWORD_REACH * 0.8
	var thick := 0.38 if gold else 0.26   # m deep at the blade's end of the sweep
	var steps := 12
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in steps:
		var a0 := -half + 2.0 * half * float(i) / steps
		var a1 := -half + 2.0 * half * float(i + 1) / steps
		# Thickest where the blade is now (the far end of the sweep), thin at its start
		var w0 := lerpf(0.1, 1.0, float(i) / steps)
		var w1 := lerpf(0.1, 1.0, float(i + 1) / steps)
		var p := [
			Vector3(sin(a0), 0, cos(a0)) * outer, Vector3(sin(a1), 0, cos(a1)) * outer,
			Vector3(sin(a1), 0, cos(a1)) * (outer - thick * w1), Vector3(sin(a0), 0, cos(a0)) * (outer - thick * w0)]
		for v in [p[0], p[1], p[2], p[0], p[2], p[3]]:
			st.add_vertex(v)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.albedo_color = BLADE_TRUE if gold else BLADE_COLOR
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mi)
	mi.global_position = global_position + Vector3.UP * 0.75
	mi.rotation.y = yaw
	var tw := mi.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.22 if gold else 0.14).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)

# Owner: the first time this session a foe draws back within sword reach, say what a cut does
func _riposte_hint() -> void:
	if _riposte_told or self != local or brain != null or not (GameState.riposte and GameState.tell):
		return
	for enemy: Node3D in get_tree().get_nodes_in_group("enemies"):
		if String(enemy.anim).begins_with("brace") and Vector2(enemy.global_position.x - global_position.x,
				enemy.global_position.z - global_position.z).length() < SWORD_REACH:
			_riposte_told = true
			_toast("Cut as he draws back — turn the blow")
			return

# Turn toward a ground point: exact yaw for the rig, nearest 4-way facing for the rest
func _face_aim(at: Vector3) -> void:
	var d := at - global_position
	if Vector2(d.x, d.z).length_squared() > 0.0001:
		aim_yaw = atan2(d.x, d.z)
	_facing = CharAnim.dir_from_velocity(d, _facing)

func _cancel_charge(keep_whirl := false) -> void:
	_charging = false
	if not keep_whirl:
		whirling = false
	if _aim_marker:
		_aim_marker.visible = false
	if _approach:
		_approach.visible = false
	for dot in _arc_dots:
		dot.visible = false

## Seconds from the nearest true-shot glint after `held` seconds of whirling (negative =
## before it). Glints fall at full charge and every TRUE_PERIOD after
static func true_offset(held: float) -> float:
	var s := held - SLING_CHARGE_TIME
	if s <= 0.0:
		return s
	return s - roundf(s / TRUE_PERIOD) * TRUE_PERIOD

# Clamp the cursor point to the charge's range and place the landing ring
func _update_aim(cursor: Vector3) -> void:
	var flat := Vector3(cursor.x - global_position.x, 0.0, cursor.z - global_position.z)
	var reach := _sling_range(_charge)
	var dist := clampf(flat.length(), SLING_MIN_THROW, reach)
	var dir := flat.normalized() if flat.length_squared() > 0.001 else Vector3.FORWARD
	_aim_point = Vector3(global_position.x, GROUND_Y, global_position.z) + dir * dist
	var locked := _assist_target(global_position, _aim_point, reach, _assist_cone(InputMode.using_pad or brain != null))
	if brain != null:
		return   # nobody at this screen is aiming it
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
		_aim_marker = _ground_ring(0.03)
		_approach = _ground_ring(0.022)
		_build_arc_dots()
	var c := AIM_RING_LOCKED if locked else AIM_RING_FREE
	c.a *= lerpf(0.45, 1.0, _charge)  # ring firms up as the charge builds
	var ground := Vector3(at.x, GROUND_Y + 0.04, at.z)
	# True shot: a ring closes on the aim ring over TRUE_LEAD, and the aim ring burns gold
	# for the window round each glint
	var off := true_offset(_held)
	var in_window := GameState.true_shot and absf(off) <= TRUE_HALF
	if in_window:
		c = AIM_RING_TRUE
	_aim_marker.material_override.set_shader_parameter("ring_color", c)
	_aim_marker.global_position = ground
	_aim_marker.scale = Vector3.ONE * (1.12 if in_window else 1.0)
	_aim_marker.visible = true
	var lead := -off if off < 0.0 else TRUE_PERIOD - off   # seconds to the next glint
	if GameState.true_shot and lead <= TRUE_LEAD and not in_window:
		var k := lead / TRUE_LEAD
		var ac := AIM_RING_TRUE
		ac.a = lerpf(0.95, 0.25, k)
		_approach.material_override.set_shader_parameter("ring_color", ac)
		_approach.global_position = ground
		_approach.scale = Vector3.ONE * lerpf(1.0, 2.3, k)
		_approach.visible = true
	else:
		_approach.visible = false
	_place_arc(at + Vector3.UP * 0.9 if locked else ground, c)

# A ring on the ground at the stone's real impact radius (0.9 m), owner only
func _ground_ring(width: float) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.4, 2.4)
	quad.orientation = PlaneMesh.FACE_Y
	var mat := ShaderMaterial.new()
	mat.shader = MARKER_SHADER
	mat.set_shader_parameter("shadow_color", Color(0, 0, 0, 0))
	mat.set_shader_parameter("ring_radius", 0.375)
	mat.set_shader_parameter("ring_width", width)
	var ring := MeshInstance3D.new()
	ring.mesh = quad
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.top_level = true
	add_child(ring)
	return ring

func _build_arc_dots() -> void:
	var dot := SphereMesh.new()
	dot.radius = 0.075
	dot.height = 0.15
	dot.radial_segments = 6
	dot.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dot.material = mat
	for i in ARC_DOTS:
		var mi := MeshInstance3D.new()
		mi.mesh = dot
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.top_level = true
		mi.visible = false
		add_child(mi)
		_arc_dots.append(mi)

# The stone's own flight path (SlingStone's arc) as a dotted line, firming with the charge
func _place_arc(to: Vector3, c: Color) -> void:
	var from := global_position + Vector3(0, SLING_RELEASE_Y, 0)
	var arc := from.distance_to(to) * SlingStone.ARC_HEIGHT
	var mat: StandardMaterial3D = _arc_dots[0].mesh.material
	mat.albedo_color = Color(c.r, c.g, c.b, c.a * lerpf(0.4, 0.9, _charge))
	for i in ARC_DOTS:
		var t := float(i + 1) / float(ARC_DOTS + 1)
		_arc_dots[i].global_position = from.lerp(to, t) + Vector3.UP * sin(t * PI) * arc
		_arc_dots[i].visible = true

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
func _server_sling(at: Vector3, land: Vector3, charge: float, pad: bool, true_shot := false) -> void:
	if not _from_owner() or downed:
		return
	charge = clampf(charge, 0.0, 1.0)
	true_shot = true_shot and GameState.true_shot
	var reach := _sling_range(charge)
	# Don't trust the client's landing point beyond what its charge allows
	var flat := Vector3(land.x - at.x, 0.0, land.z - at.z)
	if flat.length() > reach:
		land = Vector3(at.x, GROUND_Y, at.z) + flat.normalized() * reach
	var target := _assist_target(at, land, reach, _assist_cone(pad))
	var damage := lerpf(SLING_MIN_DAMAGE, SLING_MAX_DAMAGE, charge) * Trade.hit_mult(trade) * _rally(&"rally_damage")
	if true_shot:
		damage *= TRUE_MULT
	var knock := TRUE_KNOCK if true_shot else lerpf(SLING_KNOCK_MIN, SLING_KNOCK_MAX, charge)
	_throw_stone.rpc(target.get_path() if target else NodePath(), land, damage, knock, true_shot)

# Every peer animates the stone; only the server's copy deals damage
@rpc("any_peer", "call_local", "reliable")
func _throw_stone(target_path: NodePath, land: Vector3, damage: float, knock := 0.0, true_shot := false) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	var target: Node3D = null
	if not target_path.is_empty():
		target = get_node_or_null(target_path) as Node3D
	Sfx.play("throw", global_position)
	Sfx.play("sling_crack", global_position + Vector3(0, SLING_RELEASE_Y, 0), 0.92 if true_shot else 1.0)
	var stone := SLING_STONE.instantiate()
	get_tree().current_scene.add_child(stone)
	stone.global_position = global_position + Vector3(0, SLING_RELEASE_Y, 0)
	stone.shooter = worker_id()
	stone.init(target, land, damage, knock, true_shot)

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
	if brain == null:
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
	_update_raise_tag()
	Sfx.play("downed" if value else "revive", global_position)
	if value:
		_down_timer = DOWNED_TIME
		if is_multiplayer_authority():
			_jolt(0.6, 0.3, 0.8, 0.35)
		if multiplayer.is_server() and not _nobody_to_raise():
			bark("I've fallen — help me up!", true)
	else:
		health = MAX_HEALTH * REVIVE_HEALTH
	if is_multiplayer_authority():
		_is_busy = value
		_sprite.speed_scale = 1.0
		anim = "collapse" if value else "idle_" + _facing

# ── Bot calls ──────────────────────────────────────────────

# A bot says what it's doing when it matters to the people nearby (BotBrain._bark_for):
# a Shout over its head, so a crew of bots reads as people. Kept rare: one bot at most
# every BARK_GAP, the whole crew every BARK_CREW_GAP. Not on the title or in the tutorial.
const BARK_Y        := PIP_Y + 1.1   # over the pip and the "Help up" tag
const BARK_GAP      := 9.0
const BARK_CREW_GAP := 3.5
static var _crew_barked_at := -INF
var _barked_at := -INF
var _bark_shout: Shout

## Server: a bot says `line` (English; each peer translates). `urgent` (down, helped up)
## skips the wait and makes it breathe.
func bark(line: String, urgent := false) -> void:
	if brain == null or GameState.attract or GameState.tutorial:
		return
	var now := Time.get_ticks_msec() * 0.001
	if not urgent and (now < _barked_at + BARK_GAP or now < _crew_barked_at + BARK_CREW_GAP):
		return
	_barked_at = now
	_crew_barked_at = now
	_say.rpc(line, urgent)

@rpc("any_peer", "call_local", "reliable")
func _say(line: String, urgent: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	if _bark_shout == null:
		_bark_shout = Shout.make_shout()
		_bark_shout.position.y = BARK_Y
		add_child(_bark_shout)
	_bark_shout.say(tr(line), Shout.HOLD, urgent)

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
		if Trade.prefers(trade, site.work_material()):
			_knack("Your trade — quicker hands at this work")
	elif not downed and not _is_busy:
		anim = "idle_" + _facing

# Owner: walking off, dashing, dropping or reaching for the sling ends the work
func _wants_to_stop_work() -> bool:
	# A visitor at our elbow: the press is for him (kept, so _handle_interact sends it)
	if _buffered.has("interact") and _visitor_at_elbow():
		return true
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
	if is_multiplayer_authority() and brain == null:
		InputMode.rumble(0.15, 0.0, 0.05)

# ── Horn ("horn" twist) ────────────────────────────────────

## What standing in a horn ring does for this worker (1 anywhere else): Horn.rally_*
func _rally(what: StringName, at := Vector3.INF) -> float:
	var horn := get_tree().get_first_node_in_group("horn")
	return horn.call(what, global_position if at == Vector3.INF else at) if horn != null else 1.0

@rpc("any_peer", "call_local", "reliable")
func _server_horn(at: Vector3) -> void:
	if not _from_owner() or downed or is_led():
		return
	var horn := get_tree().get_first_node_in_group("horn")
	if horn != null and horn.request(self, at):
		_action.rpc("halfslash")
	else:
		_tell("The horn was just sounded")

@rpc("any_peer", "call_local", "reliable")
func _server_call_early() -> void:
	if not _from_owner() or downed or is_led():
		return
	var waves := get_node_or_null("../../WaveManager")
	if waves != null and waves.call_early():
		_action.rpc("halfslash")
		_tell("Wave called in early — the crew is spurred")

# ── Led off to Ono ("schemes" twist) ────────────────────────

var _led_release_toast := "Why should the work stop? Back to the wall!"
var _hold_time := 0.0   # owner: standing to answer / hear a visitor (GDD §6.7)

## Every peer: a visitor stands talking at our elbow (his [E] is ours)
func _visitor_at_elbow() -> bool:
	return not Messenger.old_rules and get_tree().get_nodes_in_group("messengers").any(
		func(m): return m.at_elbow(self))

## Server: work pace while one of Sanballat's men talks at us (BuildWork)
func pester_mult() -> float:
	for m in get_tree().get_nodes_in_group("messengers"):
		if m.pesters(self):
			return Messenger.PESTER_MULT
	return 1.0

## Server: stop `seconds` to answer or hear a visitor, saying `line`
func answer_pause(seconds: float, line: String) -> void:
	if building_site != null:
		building_site.work().remove_builder(self)
		stop_building_from_server()
	_set_hold.rpc_id(get_multiplayer_authority(), seconds, line)

@rpc("any_peer", "call_local", "reliable")
func _set_hold(seconds: float, line: String) -> void:
	if multiplayer.get_remote_sender_id() != 1 or not is_multiplayer_authority():
		return
	_hold_time = seconds
	_cancel_charge()
	_dash_time = 0.0
	_toast(line)

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
	if _led_by != null:
		_led_release_toast = _led_by.get("release_toast")
	_led_time = seconds
	_cancel_charge()
	_dash_time = 0.0
	if _led_by != null:
		_toast(_led_by.get("lead_toast"))
	elif was_led:
		_toast(_led_release_toast)
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
	if brain != null:
		return
	get_tree().call_group("camera_rig", "shake", shake)
	InputMode.rumble(weak, strong, duration)

# Server → owning player only. Sent in English; the owner shows it in their language.
func _tell(text: String, need := "") -> void:
	if is_bot():
		return
	_feedback.rpc_id(get_multiplayer_authority(), text, need)

@rpc("any_peer", "call_local", "reliable")
func _feedback(text: String, need: String) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		_toast(text, need)

# Owner: the first time this game that the trade's knack (Trade) pays off, say so once —
# never over another line still rising, or the two print on top of each other
var _knack_told := false
var _toast_until := 0   # msec: the last toast is still on screen until then

func _knack(text: String) -> void:
	if not _knack_told and brain == null and Time.get_ticks_msec() >= _toast_until:
		_knack_told = true
		_toast(text)

# Short floating line above the head (local only)
func _toast(text: String, need := "") -> void:
	if brain != null:
		return
	# "{interact}" → "[E]" or "[A]", whichever device this player is using
	var l := WorldTag.make(WorldTag.Kind.TOAST, tr(text).format({ "interact": "[%s]" % InputMode.key("interact"),
		"drop": "[%s]" % InputMode.key("drop"), "need": tr({"beam": "beams"}.get(need, need)) if not need.is_empty() else "" }))
	l.position = Vector3(0, HP_BAR_Y + 0.3, 0)
	add_child(l)
	_toast_until = Time.get_ticks_msec() + int(TOAST_TIME * 1000.0)
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
	_whirl_stone = stone_mi
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
	_sprite.whirl_phase = _whirl_angle
	# Circle in the body's side plane (a real sling's), turned halfway to the camera so it
	# never goes edge-on in the iso view; the stone comes over the top toward the target
	var fig := _sprite.global_basis.orthonormalized()
	var fwd := Vector3(fig.z.x, 0.0, fig.z.z).normalized()
	var side := Vector3(fig.x.x, 0.0, fig.x.z).normalized()
	var to_cam := cam.global_basis.z
	if side.dot(to_cam) < 0.0:
		side = -side
	var z := (side + to_cam).normalized()
	var y := (Vector3.UP - z * z.dot(Vector3.UP)).normalized()
	var x := y.cross(z)
	var spin := -1.0 if x.dot(fwd) > 0.0 else 1.0
	_whirl.global_transform = Transform3D(Basis(x, y, z) * Basis(Vector3.BACK, _whirl_angle * spin),
		_sprite.hand_position())
	# A whoosh each pass round the head, rising as it speeds up
	var rev := int(_whirl_angle / TAU)
	if rev != _whirl_rev:
		_whirl_rev = rev
		Sfx.play("sling_whirl", _whirl.global_position, lerpf(0.85, 1.25, minf(_whirl_time / SLING_CHARGE_TIME, 1.0)))
	# True shot: the stone glints on each beat at full spin (time-based, so every peer sees
	# it about when the slinger does)
	if GameState.true_shot and _whirl_time >= SLING_CHARGE_TIME:
		var beat := int((_whirl_time - SLING_CHARGE_TIME) / TRUE_PERIOD)
		if beat != _glint_beat:
			_glint_beat = beat
			_glint()

# A star of light on the pouch and the cord's ting: let go now
func _glint() -> void:
	Sfx.play("sling_glint", _whirl_stone.global_position)
	SlingStone.flash(get_tree().current_scene, _whirl_stone.global_position, 0.9, 0.2)
	if self == local and brain == null and not _true_told:
		_true_told = true
		_toast("Let go as it glints — a true shot")

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
