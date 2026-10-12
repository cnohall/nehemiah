class_name CharacterRig
extends Node3D

# Sculpted chibi figure built from shared procedural meshes, animated in code.
# Stands in for the old AnimatedSprite3D: same API (play / animation / frame /
# speed_scale / frame_changed / animation_finished / hit_flash / hitstop / squash),
# so Player and Enemy drive it exactly like the old sprite sheets. Animation names keep the
# "<anim>_<dir>" form; the rig keeps a virtual frame clock (CharAnim.ANIM_CFG timing)
# so gameplay beats — sling release, build strike, footsteps — land on the same frames.
#
# Proportions: built chibi (head ~40% of height), short and stubby, reads at gameplay zoom.
# Settings → Advanced → Figures can take it taller (`build`: the head shrunk and the legs,
# torso and arms stretched to a grown man of about five and a half heads). The player colour
# is the head-band; the head is what the iso camera sees most, so it stays light and bright.

const BUILDER_BODY := preload("res://scenes/shared/builder_body.gd")
const BUILDER_HEAD := preload("res://scenes/shared/builder_head.gd")

const PART_SHADER    := preload("res://assets/shaders/toon_part.gdshader")
const OUTLINE_SHADER := preload("res://assets/shaders/toon_outline.gdshader")
const MARKER_SHADER  := preload("res://assets/shaders/ground_marker.gdshader")
const FLASH_TIME   := 0.16
const SQUASH_TIME  := 0.28
const SQUASH_DAMP  := 0.35     # share of a requested squash actually shown: weight, not rubber
const STEP_FRAMES  := [1, 5]   # footfalls in the 8-frame walk / run cycles
const STRIKE_FRAME := 4        # downstroke of the build loop
const TURN_RATE    := 16.0     # rad/s-ish smoothing toward the facing direction
const BASE_SCALE   := 1.3
const BEVEL_SCALE  := 1.3      # chamfer as a multiple of each part's authored bevel
# Building: turn a three-quarter view toward the camera so the mallet arm isn't
# hidden behind the body when the wall is "up" screen (the usual case)
const BUILD_TURN   := -0.65
const BLEND_TIME   := 0.09     # cross-fade from the old pose when the animation changes
const HOLD_TIME    := 0.1      # this long without motion and the figure counts as stopped
const WINDUP_FULL  := 0.9      # wind-up reaches full tension (= Player.SLING_CHARGE_TIME)

# Rig dimensions (metres, before scale). Feet at y = 0.
const HIP_Y      := 0.36
const SHOULDER_Y := 0.86
const NECK_Y     := 0.98
const HEAD_R     := 0.34
const ARM_X      := 0.4
# The figure's build (Settings.tall_figures): 0 short and stubby, 1 tall. Taller shrinks the
# head and stretches the legs (the legs' pivots too, and the torso lifted to match, so the
# figure keeps roughly its height); the feet are pressed back to their own height
# (_flatten_feet). Read when a figure is built; Settings rebuilds every figure on a change.
static var build := 0.0
const TALL_HEAD    := 0.56
const TALL_LEG     := 1.82
const TALL_TORSO   := 1.1
const TALL_ARM     := 1.14   # hands to mid-thigh, not the belt

# Screen directions of the "<anim>_<dir>" suffixes (iso camera looks down -x -z)
const DIR_VEC := {
	"down":  Vector3(0.70710678, 0, 0.70710678),
	"up":    Vector3(-0.70710678, 0, -0.70710678),
	"right": Vector3(0.70710678, 0, -0.70710678),
	"left":  Vector3(-0.70710678, 0, 0.70710678),
}

const OUTLINE_PLAYER := Color(0.17, 0.11, 0.07)
const OUTLINE_MIN_PART := 0.12   # only the big forms: an outlined brow or beard lock is a cartoon's
# Sun-browned, not orange: olive and umber undertones of men who work outdoors
const SKIN := [Color(0.76, 0.55, 0.40), Color(0.81, 0.62, 0.47), Color(0.63, 0.44, 0.31), Color(0.54, 0.38, 0.27)]
const HAIR_DARK := Color(0.30, 0.18, 0.11)
const HAIR_BROWN := Color(0.20, 0.105, 0.06)   # dark brown: the builder and Nehemiah
const HAIR_GREY := Color(0.72, 0.70, 0.66)
const LINEN     := Color(0.89, 0.83, 0.70)
const LEATHER   := Color(0.46, 0.30, 0.18)
const SANDAL    := Color(0.40, 0.25, 0.15)
const WOOD_LIGHT := Color(0.66, 0.46, 0.27)
const HAIR_BLACK := Color(0.16, 0.11, 0.08)
const HAIR_GINGER := Color(0.66, 0.40, 0.18)
const BAND      := Color(0.24, 0.16, 0.11)

signal footstep
signal strike            # tool meets stone in the "build" loop
signal frame_changed
signal animation_finished
signal posed(delta: float)   # after each frame's pose, so props can follow the hands
signal rebuilt               # set_look built the figure anew (a new look, or a new build)

var animation := ""
var frame := 0
var speed_scale := 1.0
## What the hands hold: "" (free), "front" (a load hugged to the chest), "overhead"
## (a load on the head), "beam" (arms forward)
var hold := ""
## Sling: world yaw faced while winding up / throwing (free aim, not the 4-way facing)
var aim_yaw := 0.0
## Stand facing this world yaw instead of the animation's four ways (NAN: off) — people
## at the festival turned toward whoever they're listening to
var hold_yaw := NAN
## Sling: angle of the whirling stone, so the hand circles in step with it
var whirl_phase := 0.0

var _base := ""          # animation without the direction suffix
var _dir := "down"
var _t := 0.0            # seconds into the current animation (scaled)
var _cfg: Dictionary = {}
var _playing := false
var _finished := false
var _size := 1.0
var _yaw := 0.0
var _last_pos := Vector3.ZERO
var _has_last := false
var _squash := Vector2.ONE
var _flash_tween: Tween
var _squash_tween: Tween
var _parts: Array[GeometryInstance3D] = []
var _outline_mat: ShaderMaterial
var _marker_mat: ShaderMaterial
var _look: Dictionary = {}
var _move_speed := 0.0   # ground speed of the parent, measured from its motion
var _vel := Vector3.ZERO  # its ground velocity, sampled and held (_update_facing)
var _acc_d := Vector3.ZERO
var _acc_t := 0.0
var _path_yaw := NAN      # the heading last travelled, kept on stopping
var _stride := 0.0       # leg phase for stepping while in a non-locomotion pose
var _blend_from: Dictionary = {}
var _blend := 1.0        # 0..1 progress of the cross-fade from _blend_from
var _recoil := 0.0       # a blow rocking the figure back (radians of lean), springing out
var _recoil_tween: Tween

# Pivots
var _body: Node3D        # feet pivot — squash, bob, collapse
var _torso: Node3D       # hip pivot — lean
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _tool: Node3D        # mallet, only while building
var _spear: Node3D
var _cape: Node3D
var _carry_anchor: Node3D   # chest-front point where a carried load rides
var _belt_tool: Node3D      # the builder's hammer hung at the hip between strokes
var _hand_r: Node3D         # throwing hand
var _hands: Array[Node3D] = []
var _sword: Node3D          # worker's sword, in hand only for the cut…
var _belt_sword: Node3D     # …and girded at the side otherwise (Neh. 4:18)
# Joints hung by BuilderBody: [left, right]
var _knees: Array[Node3D] = []
var _ankles: Array[Node3D] = []
var _elbows: Array[Node3D] = []
# Secondary motion: what hangs off the figure follows it on springs (Vector2: angle, speed)
var _tails: Array[Node3D] = []    # head-band / scarf ends (BuilderHead)
var _veil: Node3D                 # a head-cloth's fall down the back (BuilderHead)
var _skirt: Node3D                # the tunic below the belt (BuilderBody)
var _sec_tail := Vector2.ZERO
var _sec_tail_roll := Vector2.ZERO
var _sec_cape := Vector2.ZERO
var _sec_veil := Vector2.ZERO
var _sec_skirt := Vector2.ZERO
var _prev_body_y := 0.0
var _body_vy := 0.0
var _accel := 0.0           # ground acceleration (m/s²), smoothed: leaning into starts and stops
var _turn_rate := 0.0       # rad/s the figure is turning: banking into turns
var _seed := 0.0            # each figure's idle drifts on its own clock
var _last_pose: Dictionary = {}
var _dip := 0.0             # knees giving under a load picked up, a landing, a blow (squash)
var _dip_tween: Tween
# This figure's build, fixed when it was built (`build`)
var _grown := 0.0
var _head_scale := 1.0
var _leg_stretch := 1.0
var _torso_stretch := 1.0
var _arm_stretch := 1.0
var _hand_items: Array[Node3D] = []   # things put in the right hand from outside (attach_to_hand)

static var _meshes: Dictionary = {}
static var _part_mat: ShaderMaterial
static var _outlines: Dictionary = {}

# ── Looks ──────────────────────────────────────────────────

const TRADES := ["Builder", "Water carrier", "Carpenter", "Overseer"]

## A worker, one trade per player slot (the crew of Neh. 4 — builders, burden-bearers,
## craftsmen, and one giving directions). The slot colour is the dye each trade wears:
##   0 builder     — linen tunic, head-band, basket of stones on the back
##   1 water carrier — striped scarf, curls, sash and a satchel
##   2 carpenter   — dyed tunic, leather apron, planks bundled on the back
##   3 supervisor  — long robe, open vest, head-cloth, a scroll at the belt
static func worker_look(slot: int, color: Color) -> Dictionary:
	# Dye, not paint: pull the UI colour toward undyed wool, as cloth worn in the sun
	var dye := color.lerp(Color(0.55, 0.44, 0.33), 0.2)
	var look := {
		"robe": LINEN, "trim": LINEN.darkened(0.12), "sash": LEATHER, "band": BAND,
		"outline": OUTLINE_PLAYER, "no_outline": true, "tool": true, "sword": true, "hat": "band", "hat_color": dye,
	}
	match slot % 4:
		0:
			look.merge({"skin": SKIN[0], "hair": HAIR_BROWN, "beard": "full", "hair_style": "short",
				"strap": true, "basket": true, "basket_stones": true, "trim": LINEN.darkened(0.1),
				"sculpted_builder": true, "sculpted_body": true}, true)
		1:
			look.merge({"skin": SKIN[2], "hair": HAIR_BLACK, "beard": "short", "hair_style": "curly",
				"hat": "scarf", "hat_color": Color(0.95, 0.92, 0.85), "stripe": dye,
				"sash": dye, "sash_tails": true, "trim": dye.darkened(0.1), "satchel": LEATHER.lightened(0.05),
				"belt_color": dye.darkened(0.1), "sculpted_builder": true, "sculpted_body": true}, true)
		2:
			look.merge({"skin": SKIN[1], "hair": HAIR_GINGER, "beard": "full", "hair_style": "bushy",
				"tails": false, "robe": dye.lerp(Color(0.55, 0.50, 0.36), 0.35), "trim": dye.darkened(0.3),
				"hat_color": dye.darkened(0.15), "apron": Color(0.62, 0.44, 0.28), "planks": true,
				"bracers": true, "brow": HAIR_GINGER.darkened(0.2),
				"sculpted_builder": true, "sculpted_body": true}, true)
		3:
			look.merge({"skin": SKIN[0], "hair": HAIR_GREY, "beard": "long", "hat": "wrap",
				"hat_color": Color(0.96, 0.94, 0.89), "band": dye, "robe": Color(0.93, 0.90, 0.83),
				"vest": dye, "long_robe": true, "scroll": Color(0.90, 0.82, 0.62),
				"trim": dye.darkened(0.2), "brow": Color(0.62, 0.60, 0.56),
				"sculpted_builder": true, "sculpted_body": true}, true)
	return look

## Enemies: dark goat-hair cloth, oxblood rim, a silhouette per type
static func enemy_look(kind: String) -> Dictionary:
	var base := {
		"skin": Color(0.60, 0.40, 0.27), "trim": Color(0.12, 0.09, 0.08), "hair": Color(0.10, 0.08, 0.07),
		"band": Color(0.10, 0.08, 0.07), "brows": true, "outline": Color(0.36, 0.07, 0.05),
		"bare_arms": false,
	}
	match kind:
		"brute":
			base.merge({"robe": Color(0.34, 0.22, 0.16), "armour": Color(0.50, 0.33, 0.19),
				"sash": Color(0.22, 0.14, 0.10), "hat": "helmet", "hat_color": Color(0.60, 0.45, 0.25),
				"beard": "full", "weapon": "spear", "shield": Color(0.56, 0.18, 0.12)})
		"saboteur":
			# Slim, dark hood, an empty sack on his back, no weapon: he's not here to fight
			base.merge({"robe": Color(0.16, 0.14, 0.13), "sash": Color(0.30, 0.22, 0.14),
				"hat": "hood", "hat_color": Color(0.10, 0.09, 0.09), "beard": "short",
				"sack": Color(0.58, 0.48, 0.32)})
		"raider":
			base.merge({"robe": Color(0.20, 0.17, 0.18), "sash": Color(0.60, 0.16, 0.12),
				"hat": "hood", "hat_color": Color(0.46, 0.12, 0.10), "beard": "short",
				"weapon": "dagger", "cape": Color(0.52, 0.13, 0.11)})
		_:
			base.merge({"robe": Color(0.36, 0.28, 0.22), "sash": Color(0.62, 0.20, 0.14),
				"hat": "hood", "hat_color": Color(0.17, 0.14, 0.13), "beard": "short", "weapon": "spear"})
	base.merge({"belt_color": base["sash"], "sculpted_builder": true, "sculpted_body": true})
	return base

# ── Setup ──────────────────────────────────────────────────

func setup(look: Dictionary, size_scale := 1.0) -> void:
	_size = size_scale * BASE_SCALE
	scale = Vector3.ONE * _size
	_seed = randf() * 100.0
	add_to_group(&"character_rigs")
	_build(look)
	_build_marker()

## Rebuild with another look (e.g. a player's slot colour), keeping the pose. What others
## hung on the figure (a load at the chest, a letter in the hand) moves to the new one.
func set_look(look: Dictionary) -> void:
	var at_chest: Array[Node] = []
	if _carry_anchor != null:
		for c in _carry_anchor.get_children():
			_carry_anchor.remove_child(c)
			at_chest.append(c)
	for n in _hand_items:
		if is_instance_valid(n) and n.get_parent() != null:
			n.get_parent().remove_child(n)
	for c in get_children():
		c.free()
	_parts.clear()
	_tool = null
	_spear = null
	_cape = null
	_carry_anchor = null
	_belt_tool = null
	_sword = null
	_belt_sword = null
	_veil = null
	_skirt = null
	_hands.clear()
	_knees.clear()
	_ankles.clear()
	_elbows.clear()
	_tails.clear()
	_build(look)
	_apply_pose()
	for c in at_chest:
		_carry_anchor.add_child(c)
	var held := _hand_items.filter(func(n): return is_instance_valid(n))
	_hand_items.clear()
	for n: Node3D in held:
		attach_to_hand(n)
	rebuilt.emit()

## Built anew at the current `build` (Settings.tall_figures changed)
func refresh_build() -> void:
	if not _look.is_empty():
		set_look(_look)

## Put `n` in the right fist (kept there through a rebuild)
func attach_to_hand(n: Node3D) -> void:
	if _hand_r == null:
		return
	_hand_r.add_child(n)
	_hand_items.append(n)

func set_ring_color(c: Color) -> void:
	_marker_mat.set_shader_parameter("ring_color", c)

# ── Sprite-compatible playback ─────────────────────────────

func play(anim_name: String = "") -> void:
	if anim_name.is_empty() or anim_name == animation:
		_playing = true
		return
	var parts := anim_name.rsplit("_", true, 1)
	var base := anim_name
	var dir := _dir
	if parts.size() == 2 and DIR_VEC.has(parts[1]):
		base = parts[0]
		dir = parts[1]
	var same_loop: bool = base == _base and _cfg.get("loop", false)
	animation = anim_name
	_dir = dir
	_playing = true
	if not same_loop:
		if base != _base and _body != null:
			_blend_from = _pose_snapshot()
			_blend = 0.0
		_base = base
		_cfg = CharAnim.ANIM_CFG.get(base, CharAnim.ANIM_CFG["idle"])
		_t = 0.0
		_finished = false
		_set_frame(0)
	_tool_visible()

func pause() -> void:
	_playing = false

func is_playing() -> bool:
	return _playing

func hit_flash() -> void:
	if _flash_tween:
		_flash_tween.kill()
	_set_flash(1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_method(_set_flash, 1.0, 0.0, FLASH_TIME)

## Freeze the pose for a beat so a hit lands with weight (visual only)
func hitstop(duration: float) -> void:
	if not _playing:
		return
	pause()
	await get_tree().create_timer(duration).timeout
	if is_instance_valid(self) and not _playing:
		play()

## A blow rocks the upper body back by `amount` radians and it springs upright again,
## on top of whatever the animation is doing (visual only)
func recoil(amount: float) -> void:
	if _recoil_tween:
		_recoil_tween.kill()
	_recoil = amount
	_recoil_tween = create_tween()
	_recoil_tween.tween_property(self, "_recoil", 0.0, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Squash & stretch (x, y factors), springing back. Feet stay planted.
func squash(amount: Vector2) -> void:
	if _squash_tween:
		_squash_tween.kill()
	# A squash is weight going down through the legs: the knees dip with it and come back
	if amount.y < 1.0:
		_dip = clampf((1.0 - amount.y) * 3.5, 0.0, 0.5)
		if _dip_tween:
			_dip_tween.kill()
		_dip_tween = create_tween()
		_dip_tween.tween_property(self, "_dip", 0.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	amount = Vector2.ONE.lerp(amount, SQUASH_DAMP)
	_squash = amount
	_squash_tween = create_tween()
	_squash_tween.tween_method(func(t: float): _squash = Vector2.ONE.lerp(amount, t), 1.0, 0.0, SQUASH_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _process(delta: float) -> void:
	if _cfg.is_empty():
		return
	if _playing and not _finished:
		_t += delta * speed_scale
		var n: int = _cfg["cycle"].size()
		var f := int(_t * _cfg["fps"])
		if not _cfg["loop"] and f >= n:
			_finished = true
			_playing = false
			_set_frame(n - 1)
			animation_finished.emit()
		else:
			_set_frame(f % n)
	_blend = minf(1.0, _blend + delta / BLEND_TIME)
	_update_facing(delta)
	_apply_pose()
	_secondary(delta)
	posed.emit(delta)

func _set_frame(f: int) -> void:
	if f == frame:
		return
	frame = f
	frame_changed.emit()
	if frame in STEP_FRAMES and (_base == "run" or _base == "walk"):
		footstep.emit()
		if _base == "run" and _move_speed > 4.0:
			_foot_dust(0 if frame == STEP_FRAMES[0] else 1)
	elif frame == STRIKE_FRAME and _base == "build":
		strike.emit()

## A little dust kicked up where a running foot comes down
func _foot_dust(side: int) -> void:
	if side >= _ankles.size() or not is_inside_tree() or get_parent() == null:
		return
	var at := _ankles[side].global_position
	at.y = get_parent().global_position.y + 0.08
	# Ground-coloured and low: on the pale ochre a light puff reads as smoke, not dust
	DustFx.puff(get_parent(), at, 2, 0.2 * _size, Color(0.58, 0.46, 0.32, 0.3))

# Motion is measured on the physics clock the body moves on. Sampled per rendered frame,
# a frame between two physics ticks saw no motion, so the heading flickered between the path
# and the nearest of the four directions, and the speed (and the lean on it) between run
# and stand. A tick that saw none (a remote player's position arrives in network steps) is
# merged into the next that did; only HOLD_TIME without motion counts as stopping.
func _physics_process(delta: float) -> void:
	var p := get_parent() as Node3D
	if p == null or delta <= 0.0:
		return
	var pos := p.global_position
	if _has_last:
		var step := pos - _last_pos
		step.y = 0.0
		_acc_d += step
		_acc_t += delta
		if step.length_squared() > 1e-10 or _acc_t >= HOLD_TIME:
			var was := _move_speed
			_vel = _vel.lerp(_acc_d / _acc_t, clampf(_acc_t * 14.0, 0.0, 1.0))
			_move_speed = _vel.length()
			_accel = lerpf(_accel, (_move_speed - was) / _acc_t, clampf(_acc_t * 8.0, 0.0, 1.0))
			_acc_d = Vector3.ZERO
			_acc_t = 0.0
	_last_pos = pos
	_has_last = true

# Face the animation's direction; while moving, face the way actually travelled, so turns
# are smooth rather than four-way snaps, and keep that heading on stopping.
func _update_facing(delta: float) -> void:
	var target: Vector3 = DIR_VEC[_dir]
	var want := atan2(target.x, target.z)
	_stride += _move_speed * delta * 2.4
	var locomotion := _base == "run" or _base == "walk" or _base == "idle"
	if _move_speed > 0.6:
		var heading := Vector3(_vel.x, 0.0, _vel.z).normalized()
		# Running: always the way he goes. Other poses (a blow knocking him back, a windup
		# walked backwards) only when it's roughly the way the pose faces
		if locomotion or heading.dot(target) > 0.3:
			want = atan2(heading.x, heading.z)
			_path_yaw = want
	elif locomotion and not is_nan(_path_yaw) and absf(angle_difference(_path_yaw, want)) < 0.9:
		# Stopped: keep the heading he ran in, not the nearest of the four ways (unless the
		# game turned him deliberately, e.g. to face a wall)
		want = _path_yaw
	else:
		_path_yaw = NAN
	if not is_nan(hold_yaw):
		want = hold_yaw
	if _base == "windup" or _base == "slash" or _base == "sword":
		want = aim_yaw   # the sling faces its target, any angle
	elif _base == "build":
		want += BUILD_TURN
	var was_yaw := _yaw
	_yaw = lerp_angle(_yaw, want, clampf(delta * TURN_RATE, 0.0, 1.0))
	if delta > 0.0:
		_turn_rate = lerpf(_turn_rate, angle_difference(was_yaw, _yaw) / delta, clampf(delta * 6.0, 0.0, 1.0))
	rotation.y = _yaw

# ── Posing ─────────────────────────────────────────────────

func _apply_pose() -> void:
	if _body == null:
		return
	var fps: float = _cfg.get("fps", 4.0)
	var n: float = _cfg.get("cycle", [0]).size()
	var k := clampf(_t * fps / n, 0.0, 1.0)           # one-shot progress 0..1
	var ph := _t * fps / n * TAU                        # loop phase
	# Rest pose: knees and elbows a touch soft, never locked straight
	var body_y := 0.0
	var body_rx := 0.0
	var roll := 0.0                                     # hips rocking side to side
	var lean := 0.0
	var twist := 0.0                                    # torso yaw; negative pulls the right shoulder back
	var head_rx := 0.0
	var head_ry := 0.0
	var al := Vector3(-0.08, 0, 0.14)                   # left arm (rx, ry, rz)
	var ar := Vector3(-0.08, 0, -0.14)
	var ll := 0.0
	var lr := 0.0
	var kl := 0.06                                      # knee bend (the shin back)
	var kr := 0.06
	var el := 0.2                                       # elbow bend (the forearm forward)
	var er := 0.2
	var plant := true                                   # body height follows the legs, a foot on the ground
	var lift := 0.0                                     # off the planted foot: a run's flight, a hop
	var spear_rx := 0.0
	var spear_z := 0.0
	var tool_rx := -1.35                                # the wrist: hammer head led forward off the hand
	var moving := smoothstep(0.3, 1.5, _move_speed)
	match _base:
		"idle":
			# At ease: the weight drifts from foot to foot every few seconds, the chest rises
			# and falls, now and then the head turns to look about
			var tt := _t + _seed
			var shift := sin(tt * 0.55) * 0.8 + sin(tt * 1.3) * 0.2
			var breath := sin(tt * 2.2)
			roll = shift * 0.03
			kl = 0.05 + maxf(0.0, -shift) * 0.16
			kr = 0.05 + maxf(0.0, shift) * 0.16
			ll = -maxf(0.0, -shift) * 0.08
			lr = -maxf(0.0, shift) * 0.08
			twist = shift * 0.04
			lean = 0.02 + breath * 0.012
			head_rx = -breath * 0.025
			var glance := smoothstep(0.55, 0.95, absf(sin(tt * 0.23)))
			head_ry = sin(tt * 0.41) * 0.42 * glance - twist * 0.6
			al = Vector3(-0.04 + breath * 0.02, 0, 0.13 + breath * 0.02 + maxf(0.0, shift) * 0.03)
			ar = Vector3(-0.04 + breath * 0.02, 0, -0.13 - breath * 0.02 - maxf(0.0, -shift) * 0.03)
			el = 0.18 + breath * 0.03
			er = 0.2 - breath * 0.03
		"run", "walk":
			var run := _base == "run"
			var s := sin(ph)
			var c := cos(ph)
			var stride := 0.62 if run else 0.42
			ll = -s * stride
			lr = s * stride
			kl = _gait_knee(ph, run)
			kr = _gait_knee(ph + PI, run)
			# Arms against the legs, elbows bent: pumped hard at a run, swung easy at a walk,
			# folding more as each comes forward
			var swing := 0.78 if run else 0.4
			al.x = s * swing
			ar.x = -s * swing
			al.z = 0.16 if run else 0.13
			ar.z = -al.z
			el = (1.15 if run else 0.25) + maxf(0.0, -al.x) * (0.45 if run else 0.55)
			er = (1.15 if run else 0.25) + maxf(0.0, -ar.x) * (0.45 if run else 0.55)
			# Shoulders turn against the hips, the hips rock over the standing leg, the head
			# holds steady on the line of travel
			twist = s * (0.17 if run else 0.08)
			roll = -c * (0.025 if run else 0.04)
			head_ry = -twist * 0.85
			head_rx = -0.05 if run else 0.0
			lean = 0.2 if run else 0.05
			if run:
				lift = 0.06 * (1.0 - absf(c))   # both feet off the ground between strides
		"windup":
			# Sling whirl: throwing hand raised and circling in step with the stone, off hand
			# pointing at the target, shoulders coiling back as the tension builds
			var c := ease(minf(_t / WINDUP_FULL, 1.0), 0.6)
			var wc := cos(whirl_phase)
			var ws := sin(whirl_phase)
			ar = Vector3(-0.6 + wc * 0.22, 0, -2.3 + ws * 0.18)
			er = 0.3 + wc * 0.12                            # the wrist and elbow work the cord
			al = Vector3(-1.3 + ws * 0.04, 0, 0.32)
			el = 0.12
			twist = -0.2 - 0.25 * c
			head_ry = -twist * 0.85                         # eyes stay on the target
			lean = -0.05 - 0.08 * c
			# Braced stance, lead (left) foot forward, knees giving; stepping when walking
			var go := minf(_move_speed / 2.0, 1.0)
			var s := sin(_stride) * go
			ll = lerpf(-0.3, -s * 0.5, go)
			lr = lerpf(0.22, s * 0.5, go)
			kl = lerpf(0.16 + 0.08 * c, _gait_knee(_stride, false), go)
			kr = lerpf(0.22 + 0.18 * c, _gait_knee(_stride + PI, false), go)
		"slash":
			# Sling cast: cock back, whip overhand (the stone leaves on frame 3, k = 0.5),
			# follow through across the body and settle
			var ax: float
			var az: float
			if k < 0.3:
				var e := ease(k / 0.3, 0.5)
				ax = lerpf(-2.2, -3.4, e)
				az = lerpf(-1.3, -0.45, e)
				er = lerpf(0.5, 1.2, e)                     # elbow folds as the arm cocks
				twist = lerpf(-0.45, -0.65, e)
				lean = lerpf(-0.13, -0.2, e)
				ll = lerpf(-0.3, -0.12, e)                  # weight rocks onto the back foot
				lr = lerpf(0.22, 0.3, e)
				kl = 0.2
				kr = lerpf(0.38, 0.48, e)
			elif k < 0.55:
				var u := (k - 0.3) / 0.25
				var e := ease(u, 2.2)                       # accelerating whip
				ax = lerpf(-3.4, -0.9, e)
				az = lerpf(-0.45, -0.1, e)
				er = lerpf(1.2, 0.05, ease(u, 1.6))         # snaps straight at the release
				twist = lerpf(-0.65, 0.5, e)
				lean = lerpf(-0.2, 0.34, e)
				ll = lerpf(-0.12, -0.5, e)                  # step into the throw
				lr = lerpf(0.3, 0.38, e)
				kl = lerpf(0.2, 0.36, e)
				kr = lerpf(0.48, 0.16, e)
			else:
				var e := ease((k - 0.55) / 0.45, 0.45)      # settle out of the follow-through
				ax = lerpf(-0.9, -0.35, e)
				az = lerpf(-0.1, 0.3, e)
				er = lerpf(0.05, 0.35, e)
				twist = lerpf(0.5, 0.12, e)
				lean = lerpf(0.34, 0.08, e)
				ll = lerpf(-0.5, -0.2, e)
				lr = lerpf(0.38, 0.12, e)
				kl = lerpf(0.36, 0.1, e)
				kr = lerpf(0.16, 0.08, e)
			ar = Vector3(ax, 0, az)
			al = Vector3(lerpf(-1.3, 0.35, ease(k, 0.7)), 0, lerpf(0.32, 0.4, k))   # off hand pulls back
			el = lerpf(0.12, 1.0, smoothstep(0.3, 0.6, k))
			head_ry = -twist * 0.7
			head_rx = 0.08
		"sword":
			# Flat cut: draw back across the body, sweep through the foe (k ≈ 0.4), recover
			var ax: float
			var az: float
			if k < 0.25:
				var e := ease(k / 0.25, 0.5)
				ax = lerpf(-0.6, -1.7, e)
				az = lerpf(-0.2, 0.9, e)                    # blade cocked over the off shoulder
				er = lerpf(0.4, 1.35, e)
				twist = lerpf(0.0, 0.6, e)
				lean = lerpf(0.0, -0.1, e)
				kr = lerpf(0.08, 0.3, e)
			elif k < 0.5:
				var e := ease((k - 0.25) / 0.25, 2.0)       # accelerating sweep
				ax = lerpf(-1.7, -1.4, e)
				az = lerpf(0.9, -1.0, e)
				er = lerpf(1.35, 0.1, e)
				twist = lerpf(0.6, -0.55, e)
				lean = lerpf(-0.1, 0.28, e)
				ll = lerpf(0.0, -0.45, e)                   # step into the cut
				lr = lerpf(0.0, 0.22, e)
				kl = lerpf(0.08, 0.4, e)
				kr = lerpf(0.3, 0.2, e)
			else:
				var e := ease((k - 0.5) / 0.5, 0.45)
				ax = lerpf(-1.4, -0.3, e)
				az = lerpf(-1.0, -0.2, e)
				er = lerpf(0.1, 0.35, e)
				twist = lerpf(-0.55, 0.0, e)
				lean = lerpf(0.28, 0.05, e)
				ll = lerpf(-0.45, -0.1, e)
				lr = lerpf(0.22, 0.05, e)
				kl = lerpf(0.4, 0.1, e)
				kr = lerpf(0.2, 0.08, e)
			ar = Vector3(ax, 0, az)
			al = Vector3(-0.5, 0, 0.35)
			el = 0.9
			head_ry = -twist * 0.6
		"halfslash":
			var e := ease(k, 0.6)
			ar = Vector3(lerpf(-3.0, -0.5, e), 0, -0.15)
			er = lerpf(1.2, 0.15, e)
			al = Vector3(lerpf(-0.9, 0.4, e), 0, 0.2)
			el = lerpf(0.9, 0.3, e)
			lean = lerpf(-0.15, 0.3, e)
			kl = lerpf(0.1, 0.3, e)
		"build":
			# Mallet overhand: raised behind the head over frames 0-3 with the wrist cocked so
			# the head rides up over the shoulder, driven down on 4 as the wrist snaps through
			# and the knees give into the blow, recovered 5-7; the off hand steadies the stone
			var keys := [-1.4, -2.3, -2.9, -3.15, -0.55, -0.75, -1.0, -1.2]
			var bends := [0.85, 1.05, 1.15, 1.2, 0.1, 0.25, 0.45, 0.7]
			var wrists := [-0.85, -0.6, -0.45, -0.4, -1.5, -1.45, -1.3, -1.05]
			var dips := [0.1, 0.06, 0.04, 0.04, 0.42, 0.36, 0.24, 0.16]
			var fi := _t * fps
			var i0 := int(fi) % 8
			var i1 := (i0 + 1) % 8
			var fr := fi - floorf(fi)
			var w := fr * fr if i0 == 3 else fr               # the downstroke accelerates
			ar = Vector3(lerpf(keys[i0], keys[i1], w), 0, -0.1)
			er = lerpf(bends[i0], bends[i1], w)
			tool_rx = lerpf(wrists[i0], wrists[i1], w)
			var dip: float = lerpf(dips[i0], dips[i1], w)
			al = Vector3(lerpf(-0.85, -1.1, dip * 2.0), 0, 0.12)
			el = lerpf(0.4, 0.25, dip * 2.0)
			lean = lerpf(-0.08, 0.36, dip / 0.42)
			ll = -0.28
			lr = 0.18
			kl = dip
			kr = dip * 0.8 + 0.08
			head_rx = 0.12 + dip * 0.2
			twist = lerpf(-0.18, 0.12, dip / 0.42)
		"thrust":
			var j := sin(k * PI)
			ar = Vector3(lerpf(-0.6, -1.5, j), 0, -0.1)
			er = lerpf(1.0, 0.1, j)
			al = Vector3(-0.5, 0, 0.3)
			el = 0.8
			lean = j * 0.3
			ll = -0.3 * j
			kl = 0.1 + 0.3 * j
			kr = 0.1 + 0.15 * j
			spear_rx = PI * 0.5 * minf(1.0, k * 4.0) * (1.0 if k < 0.85 else (1.0 - k) / 0.15)
			spear_z = j * 0.45
		"brace":
			# The tell: spear levelled and drawn back past the hip, sunk into a lunge on the
			# back leg, shoulders coiled — then held, trembling, until the blow
			var e := ease(k, 0.45)
			ar = Vector3(lerpf(-0.6, -0.95, e), 0, lerpf(-0.1, -0.35, e))
			er = lerpf(0.6, 1.1, e)
			al = Vector3(lerpf(-0.5, -1.1, e), 0, 0.35)
			el = lerpf(0.5, 0.7, e)
			lean = -0.12 * e
			twist = -0.4 * e
			head_ry = 0.3 * e
			ll = -0.42 * e
			lr = 0.32 * e
			kl = 0.1 + 0.35 * e
			kr = 0.1 + 0.5 * e
			spear_rx = PI * 0.5 * e
			spear_z = -0.3 * e
			if k >= 1.0:
				var shake := sin(Time.get_ticks_msec() * 0.06) * 0.02
				lean += shake
				twist += shake
		"reel":
			# Knocked aside: thrown back a step, spear jerked up, arms out for balance
			var j := sin(k * PI)
			lean = -0.38 * j
			ar = Vector3(-0.6 - 1.7 * j, 0, -0.2 - 0.3 * j)
			al = Vector3(-0.5 - 1.1 * j, 0, 0.35 + 0.4 * j)
			er = 0.3 + 0.5 * j
			el = 0.3 + 0.6 * j
			head_rx = -0.3 * j
			ll = 0.35 * j
			lr = -0.25 * j
			kl = 0.1 + 0.25 * j
			kr = 0.1 + 0.45 * j
			spear_rx = -0.5 * j
		"knocked":
			# Off his feet (a true shot): down on his back, a beat on the ground, up again
			var c: float
			if k < 0.22:
				c = ease(k / 0.22, 2.4)
			elif k < 0.62:
				c = 1.0
			else:
				c = 1.0 - ease((k - 0.62) / 0.38, 0.6)
			plant = false
			body_rx = -1.3 * c
			body_y = 0.13 * c
			al = Vector3(-0.3 - 1.2 * c, 0, 0.14 + c * 0.9)
			ar = Vector3(-0.3 - 1.2 * c, 0, -0.14 - c * 0.9)
			el = 0.2 + 0.6 * c
			er = 0.2 + 0.4 * c
			ll = -0.6 * c
			lr = -0.25 * c
			kl = 0.06 + 0.9 * c
			kr = 0.06 + 0.4 * c
			# Getting up: a knee drawn under on the way
			if k > 0.62:
				kr += sin((k - 0.62) / 0.38 * PI) * 0.8
			head_rx = -0.25 * c + (0.15 if k > 0.22 and k < 0.3 else 0.0)   # head knocks the ground
		"cheer":
			# Two hops; arms fly up on the first and wave overhead. The knees sink before each
			# jump and take the landing
			var hop := absf(sin(k * TAU))
			var up := minf(1.0, k * 6.0)
			lift = hop * 0.24
			var wave := sin(_t * 16.0) * 0.18 * up
			al = Vector3(lerpf(-0.08, -2.7, up) + wave, 0, lerpf(0.14, 0.45, up))
			ar = Vector3(lerpf(-0.08, -2.7, up) - wave, 0, lerpf(-0.14, -0.45, up))
			el = 0.25 + 0.2 * (1.0 - up)
			er = el
			ll = -hop * 0.3
			lr = -hop * 0.3
			kl = 0.08 + (1.0 - hop) * 0.38 * up + hop * 0.35
			kr = kl
			lean = -0.12 * up + (1.0 - hop) * 0.1 * up
			head_rx = -0.2 * up
		"dabke":
			# Levantine line dance: arms up and out as if linked at the shoulders, a side
			# shuffle, then a kick and a stomp on the last beat
			var beat := fmod(_t * fps, n) / n
			twist = sin(ph) * 0.15
			al = Vector3(-1.25, 0, 0.95)
			ar = Vector3(-1.25, 0, -0.95)
			el = 0.35
			er = 0.35
			ll = sin(ph) * 0.2
			lr = -sin(ph) * 0.2
			kl = _gait_knee(ph, false) * 0.6
			kr = _gait_knee(ph + PI, false) * 0.6
			if beat >= 0.5 and beat < 0.8:
				var kick := sin((beat - 0.5) / 0.3 * PI)
				ll = -0.75 * kick                           # the kick: knee up, then the foot shot out
				kl = 0.15 + 0.6 * (1.0 - smoothstep(0.3, 0.8, (beat - 0.5) / 0.3)) * kick
				kr = 0.18
			elif beat >= 0.8:
				var stomp := sin((beat - 0.8) / 0.2 * PI)
				kl = 0.1 + 0.25 * stomp                     # the stomp: weight dropped through both knees
				kr = 0.1 + 0.25 * stomp
				lean = 0.08 * stomp
			lift = absf(sin(ph * 2.0)) * 0.03
			head_rx = 0.06
		"clap":
			# Side step and clap in front of the chest, twice a cycle
			var c := absf(sin(ph * 2.0))
			al = Vector3(-0.75, 0, lerpf(0.55, 0.05, c))
			ar = Vector3(-0.75, 0, lerpf(-0.55, -0.05, c))
			el = 1.25
			er = 1.25
			ll = sin(ph) * 0.35
			lr = -sin(ph) * 0.35
			kl = _gait_knee(ph, false)
			kr = _gait_knee(ph + PI, false)
			lift = absf(sin(ph)) * 0.05
			head_ry = sin(ph) * 0.22
			lean = 0.05
		"sway":
			# Both arms up in a V, waving, the body swaying side to side over soft knees
			var s := sin(ph)
			al = Vector3(-2.45 + s * 0.22, 0, 0.6)
			ar = Vector3(-2.45 - s * 0.22, 0, -0.6)
			el = 0.3
			er = 0.3
			twist = s * 0.45
			roll = s * 0.05
			ll = -maxf(0.0, s) * 0.3
			lr = -maxf(0.0, -s) * 0.3
			kl = 0.08 + maxf(0.0, s) * 0.35
			kr = 0.08 + maxf(0.0, -s) * 0.35
			head_rx = -0.15
		"collapse":
			# The knees go first, then he topples back
			var buckle := ease(minf(1.0, k * 2.5), 0.6)
			var fall := ease(clampf((k - 0.25) / 0.75, 0.0, 1.0), 2.2)
			plant = fall < 0.05
			kl = 0.06 + 0.9 * buckle * (1.0 - fall * 0.6)
			kr = 0.06 + 0.7 * buckle * (1.0 - fall * 0.6)
			ll = -0.4 * buckle * (1.0 - fall * 0.5)
			lr = -0.25 * buckle * (1.0 - fall * 0.5)
			body_y = (-0.18 * buckle * (1.0 - fall) + 0.14 * fall) if not plant else 0.0   # lying on his back, not in the ground
			body_rx = -1.45 * fall
			lean = 0.25 * buckle * (1.0 - fall)
			al = Vector3(-0.3, 0, 0.14 + fall * 1.2)
			ar = Vector3(-0.3, 0, -0.14 - fall * 1.2)
			el = 0.3 + 0.4 * buckle
			er = 0.3 + 0.3 * buckle
			head_rx = -0.3 * fall + 0.2 * buckle * (1.0 - fall)
	# A dash: one long bound, the back leg trailing, arms flung back
	if _base == "run":
		var d := smoothstep(10.0, 14.0, _move_speed)
		if d > 0.0:
			ll = lerpf(ll, -0.8, d)
			lr = lerpf(lr, 0.65, d)
			kl = lerpf(kl, 0.4, d)
			kr = lerpf(kr, 1.0, d)
			al = al.lerp(Vector3(0.85, 0, 0.35), d)
			ar = ar.lerp(Vector3(0.85, 0, -0.35), d)
			el = lerpf(el, 0.35, d)
			er = lerpf(er, 0.35, d)
			lean += 0.22 * d
			lift += 0.07 * d
			twist *= 1.0 - d
	# Loads override the arms
	if _base in ["idle", "walk", "run"]:
		match hold:
			"overhead":
				var sway := sin(ph) * 0.06 if _base != "idle" else 0.0
				al = Vector3(-2.75 + sway, 0, 0.32)
				ar = Vector3(-2.75 - sway, 0, -0.32)
				el = 0.75
				er = 0.75
				twist *= 0.3
			"beam":
				al = Vector3(-1.05, 0, 0.1)
				ar = Vector3(-1.05, 0, -0.1)
				el = 0.55
				er = 0.55
				twist *= 0.3
			"front":
				# Hugging the load to the chest, elbows out and bent round it
				var bob := sin(ph) * 0.05 if _base != "idle" else 0.0
				al = Vector3(-0.7 + bob, 0, -0.32)
				ar = Vector3(-0.7 - bob, 0, 0.32)
				el = 1.3
				er = 1.3
				twist *= 0.3
				lean -= 0.04   # leaning back against the weight
	if _spear != null and _base in ["idle", "walk"]:
		ar = Vector3(-0.35, 0, -0.3)   # hand on the shaft
		er = 0.75
	# Moving: lean into a start, sit back into a stop, bank into a turn; a blow buckles the
	# knees a little
	if _base in ["idle", "walk", "run", "windup"] and plant:
		var surge := clampf(_accel * 0.022, -0.2, 0.2)
		lean += surge
		if surge < 0.0:
			kl -= surge * 0.6
			kr -= surge * 0.6
		roll += clampf(-_turn_rate * _move_speed * 0.012, -0.22, 0.22)
	if _recoil > 0.0:
		kl += _recoil * 0.6
		kr += _recoil * 0.8
	if _dip > 0.0 and plant:
		kl += _dip
		kr += _dip
		ll -= _dip * 0.35
		lr -= _dip * 0.35
		lean += _dip * 0.3
	# In the swing the hammer head leads forward off the hand
	_tool_visible()
	if _tool != null:
		_tool.rotation.x = tool_rx
	if _sword != null:
		_sword.rotation.x = -1.45   # blade out ahead of the fist
	# Ease out of the previous animation's pose instead of snapping to the new one
	if _blend < 1.0 and not _blend_from.is_empty():
		var w := smoothstep(0.0, 1.0, _blend)
		var f := _blend_from
		body_y = lerpf(f.body_y, body_y, w)
		lean = lerpf(f.lean, lean, w)
		twist = lerp_angle(f.twist, twist, w)
		roll = lerpf(f.roll, roll, w)
		head_rx = lerpf(f.head.x, head_rx, w)
		head_ry = lerp_angle(f.head.y, head_ry, w)
		al = f.al.lerp(al, w)
		ar = f.ar.lerp(ar, w)
		ll = lerpf(f.ll, ll, w)
		lr = lerpf(f.lr, lr, w)
		kl = lerpf(f.kl, kl, w)
		kr = lerpf(f.kr, kr, w)
		el = lerpf(f.el, el, w)
		er = lerpf(f.er, er, w)
	# Feet on the ground: the body sits as high as its longer leg reaches, and the foot
	# that bears the weight lies flat while the other's toes trail
	var reach_l := _leg_reach(ll, kl)
	var reach_r := _leg_reach(lr, kr)
	var reach := maxf(reach_l, reach_r)
	if plant and not _knees.is_empty():
		body_y += reach - _leg_rest() + lift
	elif plant:
		body_y += lift
	_body.position.y = body_y
	_body.rotation.x = body_rx
	_body.rotation.z = roll
	_body.scale = Vector3(_squash.x, _squash.y, _squash.x)
	_torso.rotation.x = lean - _recoil
	head_rx -= _recoil * 0.7
	_torso.rotation.y = twist
	_torso.rotation.z = -roll * 0.6                     # the shoulders keep level over the hips
	_head.rotation.x = head_rx
	_head.rotation.y = head_ry
	_head.rotation.z = -roll * 0.4
	_arm_l.rotation = al
	_arm_r.rotation = ar
	_leg_l.rotation.x = ll
	_leg_r.rotation.x = lr
	if not _knees.is_empty():
		_knees[0].rotation.x = kl
		_knees[1].rotation.x = kr
		var w_l := 1.0 - smoothstep(0.0, 0.04, reach - reach_l) if plant else 0.3
		var w_r := 1.0 - smoothstep(0.0, 0.04, reach - reach_r) if plant else 0.3
		_ankles[0].rotation.x = -(ll + kl) * lerpf(0.55, 1.0, w_l) + (1.0 - w_l) * 0.25
		_ankles[1].rotation.x = -(lr + kr) * lerpf(0.55, 1.0, w_r) + (1.0 - w_r) * 0.25
	if not _elbows.is_empty():
		_elbows[0].rotation.x = -el
		_elbows[1].rotation.x = -er
	if _spear != null:
		_spear.rotation.x = spear_rx
		_spear.position.z = 0.12 + spear_z
		_grip_spear()
	_last_pose = { "lean": lean, "body_y": body_y, "moving": moving, "ph": ph, "ll": ll, "lr": lr }

## The spear's shaft through the right fist, a third of the way up it, at the angle the
## pose gave it (it hangs on the torso, so the hand alone can't carry its angle)
func _grip_spear() -> void:
	if _hand_r == null or not _hand_r.is_inside_tree() or not _torso.is_inside_tree():
		return
	const GRIP := 0.2
	var fist := _torso.to_local(_hand_r.global_position + _hand_r.global_basis.y * -0.02)
	_spear.position = fist - _spear.basis * Vector3(0, GRIP, 0)

## Knee bend through a stride at leg phase `p` (thigh forward at p = π/2): folded high
## through the swing, soft under the weight
static func _gait_knee(p: float, run: bool) -> float:
	var swing := maxf(0.0, cos(p - 0.3))
	var stance := maxf(0.0, -cos(p))
	if run:
		return 0.12 + 1.35 * pow(swing, 1.4) + 0.22 * stance
	return 0.05 + 0.65 * pow(swing, 1.6) + 0.08 * stance

## How far below the hip a leg reaches with the thigh at `thigh` and the knee at `knee`
## (rig units, before the rig's scale)
func _leg_reach(thigh: float, knee: float) -> float:
	var upper := -BUILDER_BODY.KNEE_Y * _leg_stretch
	var lower := _leg_rest() - upper
	return upper * cos(thigh) + lower * cos(thigh + knee)

func _leg_rest() -> float:
	return HIP_Y * _leg_stretch

## What hangs off the figure follows it: head-band ends stream back with speed and swing
## out on a turn, a head-cloth and a cloak lift behind a run, the tunic's skirt lags a step
## and flares round the striding legs
func _secondary(delta: float) -> void:
	if delta <= 0.0 or _body == null:
		return
	var by := _body.position.y
	_body_vy = lerpf(_body_vy, (by - _prev_body_y) / delta, clampf(delta * 20.0, 0.0, 1.0))
	_prev_body_y = by
	var lean: float = _last_pose.get("lean", 0.0)
	var moving: float = _last_pose.get("moving", 0.0)
	var ph: float = _last_pose.get("ph", 0.0)
	if not _tails.is_empty():
		var lift := clampf(minf(_move_speed, 9.0) * 0.09 - _body_vy * 0.9 + _accel * 0.012 + maxf(lean, 0.0) * 0.5, -0.25, 1.0)
		_sec_tail = _spring(_sec_tail, lift + moving * sin(ph * 2.0) * 0.06, 90.0, 6.0, delta)
		_sec_tail_roll = _spring(_sec_tail_roll, clampf(_turn_rate * 0.08, -0.5, 0.5), 80.0, 5.0, delta)
		for i in _tails.size():
			var tl := _tails[i]
			var lag := 1.0 - i * 0.18                   # the second end trails the first
			tl.rotation.x = tl.get_meta("rx", 0.0) + _sec_tail.x * lag
			tl.rotation.z = tl.get_meta("rz", 0.0) + _sec_tail_roll.x * lag
	if _veil != null:
		var target := clampf(minf(_move_speed, 9.0) * 0.035 - _body_vy * 0.35 + _accel * 0.005 + maxf(lean, 0.0) * 0.4, -0.08, 0.5)
		_sec_veil = _spring(_sec_veil, target, 70.0, 6.0, delta)
		_veil.rotation.x = _sec_veil.x
	if _cape != null:
		var target := 0.06 + maxf(lean, 0.0) * 0.6 + minf(_move_speed, 9.0) * 0.04 - _body_vy * 0.3 + _accel * 0.006
		_sec_cape = _spring(_sec_cape, clampf(target, -0.1, 0.9), 55.0, 5.5, delta)
		_cape.rotation.x = _sec_cape.x
	if _skirt != null:
		var target := clampf(_accel * 0.006 + moving * 0.03 - lean * 0.35 - _body_vy * 0.25, -0.2, 0.2)
		_sec_skirt = _spring(_sec_skirt, target, 120.0, 9.0, delta)
		_skirt.rotation.x = _sec_skirt.x
		# Room for the knees: the hem flares fore and aft as the legs open
		var open := absf(float(_last_pose.get("ll", 0.0)) - float(_last_pose.get("lr", 0.0)))
		_skirt.scale = Vector3(1.0, 1.0, 1.0 + clampf(open * 0.22, 0.0, 0.3))

static func _spring(s: Vector2, target: float, stiff: float, damp: float, delta: float) -> Vector2:
	var v := s.y + (-stiff * (s.x - target) - damp * s.y) * delta
	return Vector2(s.x + v * delta, v)

func _tool_visible() -> void:
	if _tool != null:
		_tool.visible = _base == "build"
	if _belt_tool != null:
		_belt_tool.visible = _base != "build" and not _look.get("sculpted_body", false)
	if _sword != null:
		_sword.visible = _base == "sword"
	if _belt_sword != null:
		_belt_sword.visible = _base != "sword" and not _look.get("sculpted_body", false)

## Chest-front point a carried load hangs from (follows the body's turn and bob)
func carry_anchor() -> Node3D:
	return _carry_anchor

## World position of the throwing (right) hand, where the sling cord is held
func hand_position() -> Vector3:
	return _hand_r.global_position if _hand_r != null else global_position + Vector3.UP * 1.7

func _pose_snapshot() -> Dictionary:
	return {
		# Height above the planted legs, not the planted height itself (that follows the knees)
		"body_y": 0.0 if _base not in ["collapse", "knocked"] else _body.position.y,
		"lean": _torso.rotation.x, "twist": _torso.rotation.y,
		"roll": _body.rotation.z,
		"head": _head.rotation, "al": _arm_l.rotation, "ar": _arm_r.rotation,
		"ll": _leg_l.rotation.x, "lr": _leg_r.rotation.x,
		"kl": _knees[0].rotation.x if not _knees.is_empty() else 0.06,
		"kr": _knees[1].rotation.x if not _knees.is_empty() else 0.06,
		"el": -_elbows[0].rotation.x if not _elbows.is_empty() else 0.2,
		"er": -_elbows[1].rotation.x if not _elbows.is_empty() else 0.2,
	}

func _set_flash(v: float) -> void:
	for p in _parts:
		p.set_instance_shader_parameter("flash", v)

# ── Building the figure ────────────────────────────────────

func _build(look: Dictionary) -> void:
	_look = look
	_grown = clampf(build, 0.0, 1.0)
	_head_scale = lerpf(1.0, TALL_HEAD, _grown)
	_leg_stretch = lerpf(1.0, TALL_LEG, _grown)
	_torso_stretch = lerpf(1.0, TALL_TORSO, _grown)
	_arm_stretch = lerpf(1.0, TALL_ARM, _grown)
	if _part_mat == null:
		_part_mat = ShaderMaterial.new()
		_part_mat.shader = PART_SHADER
	var oc: Color = look.get("outline", OUTLINE_PLAYER)
	if not _outlines.has(oc):
		var om := ShaderMaterial.new()
		om.shader = OUTLINE_SHADER
		om.set_shader_parameter("outline_color", oc)
		_outlines[oc] = om
	# Workers go without: clean shapes read softer; enemies keep the oxblood rim as a threat cue
	_outline_mat = null if look.get("no_outline", false) else _outlines[oc]

	var skin: Color = look["skin"]
	var robe: Color = look["robe"]
	var hair: Color = look["hair"]

	_body = _pivot(self, Vector3.ZERO)
	var hands: Array[Node3D] = []
	var sculpted_body: bool = look.get("sculpted_body", false)
	if sculpted_body:
		hands = BUILDER_BODY.new().build(self, look)
	else:
		var sandal: Color = look.get("sandal", SANDAL)
		var long_robe: bool = look.get("long_robe", false)
		var belt: Color = look["sash"]

		# ── Legs: bare shins, chunky sandals — sole, foot, a row of toes, two straps
		_leg_l = _pivot(_body, Vector3(0.13, HIP_Y, 0))
		_leg_r = _pivot(_body, Vector3(-0.13, HIP_Y, 0))
		for leg in [_leg_l, _leg_r]:
			_part(leg, _ellipsoid(Vector3(0.18, 0.34, 0.18)), skin, Vector3(0, -0.16, 0))
			_part(leg, _soft(Vector3(0.2, 0.05, 0.31), 0.016), sandal.darkened(0.15), Vector3(0, -HIP_Y + 0.025, 0.045))
			_part(leg, _soft(Vector3(0.16, 0.07, 0.22), 0.028), skin, Vector3(0, -HIP_Y + 0.085, 0.035))
			for tx: float in [-0.052, 0.0, 0.052]:
				_part(leg, _soft(Vector3(0.046, 0.046, 0.05), 0.012), skin.darkened(0.04), Vector3(tx, -HIP_Y + 0.072, 0.168))
			_part(leg, _soft(Vector3(0.172, 0.04, 0.07), 0.012), sandal, Vector3(0, -HIP_Y + 0.11, 0.085))
			_part(leg, _soft(Vector3(0.165, 0.045, 0.165), 0.012), sandal, Vector3(0, -HIP_Y + 0.16, 0))

		# ── Tunic: broad chest, skirt to the knee (the ankle on a long robe), a hem band
		_torso = _pivot(_body, Vector3(0, HIP_Y, 0))
		_part(_torso, _soft(Vector3(0.6, 0.38, 0.42), 0.07), robe, Vector3(0, 0.39, 0))
		if long_robe:
			_part(_torso, _cloth_skirt(0.48), robe, Vector3(0, -0.02, 0))
		else:
			_part(_torso, _cloth_skirt(0.34), robe, Vector3(0, 0.07, 0))
		# Wide belt, a knot of leather and a brass buckle at the front
		_part(_torso, _oval_band(Vector3(0.69, 0.13, 0.52)), belt, Vector3(0, 0.23, 0))
		_part(_torso, _soft(Vector3(0.14, 0.13, 0.05), 0.02), belt.darkened(0.28), Vector3(0.02, 0.23, 0.245))
		_part(_torso, _soft(Vector3(0.07, 0.06, 0.02), 0.008), Color(0.76, 0.62, 0.36), Vector3(0.02, 0.23, 0.272))
		if look.get("sash_tails", false):
			_part(_torso, _soft(Vector3(0.1, 0.3, 0.04), 0.015), belt, Vector3(-0.17, 0.06, 0.245), Vector3(0, 0, 0.12))
			_part(_torso, _soft(Vector3(0.09, 0.24, 0.04), 0.015), belt.darkened(0.1), Vector3(-0.07, 0.08, 0.25), Vector3(0, 0, -0.1))
		# ── Arms: short sleeve, bare forearm, rounded hand; pivot at the shoulder
		_arm_l = _pivot(_torso, Vector3(ARM_X, SHOULDER_Y - HIP_Y, 0))
		_arm_r = _pivot(_torso, Vector3(-ARM_X, SHOULDER_Y - HIP_Y, 0))
		var sleeve: Color = look.get("vest", robe) if look.has("vest") and not long_robe else robe
		var forearm: Color = skin if look.get("bare_arms", true) else robe
		for arm in [_arm_l, _arm_r]:
			_part(arm, _ellipsoid(Vector3(0.29, 0.30, 0.29)), sleeve, Vector3(0, -0.07, 0))
			_part(arm, _oval_band(Vector3(0.23, 0.055, 0.23)), sleeve.darkened(0.1), Vector3(0, -0.19, 0))
			_part(arm, _ellipsoid(Vector3(0.19, 0.26, 0.19)), forearm, Vector3(0, -0.28, 0))
			if look.get("bracers", false):
				_part(arm, _oval_band(Vector3(0.20, 0.1, 0.20)), LEATHER, Vector3(0, -0.31, 0))
			var hand := _pivot(arm, Vector3(0, -0.43, 0))
			_part(hand, _soft(Vector3(0.18, 0.17, 0.18), 0.05), skin, Vector3.ZERO)
			_part(hand, _soft(Vector3(0.06, 0.08, 0.07), 0.02), skin.darkened(0.05), Vector3(0, 0.02, 0.1))
			hands.append(hand)

	if look.has("vest") and not sculpted_body:
		# Open vest: coloured over the chest with the tunic showing down the front
		var v: Color = look["vest"]
		for sx: float in [-1.0, 1.0]:
			_part(_torso, _soft(Vector3(0.22, 0.46, 0.44), 0.05), v, Vector3(0.2 * sx, 0.4, 0))
		_part(_torso, _soft(Vector3(0.6, 0.44, 0.1), 0.04), v, Vector3(0, 0.4, -0.18))
		for sx: float in [-1.0, 1.0]:
			_part(_torso, _soft(Vector3(0.03, 0.46, 0.02), 0.008), v.darkened(0.3), Vector3(0.09 * sx, 0.4, 0.225))
			# Split vest skirts continue below the belt, framing the linen robe.
			_part(_torso, _soft(Vector3(0.14, 0.39, 0.055), 0.02), v,
				Vector3(0.24 * sx, -0.015, 0.185), Vector3(0, sx * 0.30, sx * 0.10))
	if look.has("apron"):
		var a: Color = look["apron"]
		_part(_torso, _soft(Vector3(0.44, 0.58, 0.04), 0.015), a, Vector3(0, 0.14, 0.245))
		_part(_torso, _soft(Vector3(0.2, 0.13, 0.03), 0.01), a.darkened(0.2), Vector3(0.09, 0.04, 0.27))
		_part(_torso, _soft(Vector3(0.04, 0.16, 0.04), 0.01), WOOD_LIGHT, Vector3(0.05, 0.12, 0.28), Vector3(0, 0, 0.2))
		_part(_torso, _soft(Vector3(0.04, 0.14, 0.04), 0.01), Color(0.6, 0.6, 0.62), Vector3(0.14, 0.12, 0.28), Vector3(0, 0, -0.2))
		# A small toothed saw hangs at the hip, clear of the moving forearms.
		var saw := _pivot(_torso, Vector3(-0.32, 0.13, -0.05))
		saw.rotation.z = -0.20
		_part(saw, _soft(Vector3(0.14, 0.16, 0.06), 0.025), LEATHER, Vector3.ZERO)
		_part(saw, _bbox(Vector3(0.12, 0.31, 0.025), 0.008), Color(0.58, 0.62, 0.65), Vector3(0, -0.21, 0))
		for tooth in 6:
			_part(saw, _box(Vector3(0.038, 0.038, 0.028)), Color(0.58, 0.62, 0.65),
				Vector3(-0.065, -0.085 - tooth * 0.047, 0), Vector3(0, 0, PI * 0.25))
	if look.get("strap", false) and not sculpted_body:
		_part(_torso, _soft(Vector3(0.09, 0.66, 0.44), 0.02), LEATHER, Vector3(0, 0.42, 0), Vector3(0, 0, 0.62))
	if look.has("satchel"):
		var sc: Color = look["satchel"]
		_part(_torso, _soft(Vector3(0.09, 0.66, 0.44), 0.02), sc.darkened(0.1), Vector3(0, 0.42, 0), Vector3(0, 0, -0.62))
		_part(_torso, _soft(Vector3(0.15, 0.26, 0.26), 0.05), sc, Vector3(-0.38, 0.08, 0.05))
		_part(_torso, _soft(Vector3(0.16, 0.11, 0.27), 0.03), sc.darkened(0.2), Vector3(-0.385, 0.18, 0.05))
		_part(_torso, _soft(Vector3(0.03, 0.05, 0.04), 0.008), Color(0.76, 0.62, 0.36), Vector3(-0.465, 0.14, 0.05))
	if look.has("scroll"):
		var sc2 := _pivot(_torso, Vector3(0.36, 0.17, 0.1))
		sc2.rotation = Vector3(0.2, 0, 0.35)
		_part(sc2, _cyl(0.065, 0.065, 0.4), look["scroll"], Vector3.ZERO)
		_part(sc2, _cyl(0.07, 0.07, 0.05), BAND, Vector3.ZERO)
		for sy: float in [-1.0, 1.0]:
			_part(sc2, _torus(0.035, 0.064), look["scroll"].darkened(0.18), Vector3(0, sy * 0.205, 0))
	if look.has("armour") and not sculpted_body:
		_part(_torso, _soft(Vector3(0.63, 0.4, 0.45), 0.06), look["armour"], Vector3(0, 0.4, 0))
		_part(_torso, _soft(Vector3(0.645, 0.05, 0.465), 0.015), look["armour"].darkened(0.25), Vector3(0, 0.3, 0))
	if look.has("cape") and not sculpted_body:
		_cape = _pivot(_torso, Vector3(0, SHOULDER_Y - HIP_Y + 0.02, -0.2))
		_part(_cape, _soft(Vector3(0.58, 0.8, 0.06), 0.02), look["cape"], Vector3(0, -0.39, -0.04))
	# Basket on the back, riding above the shoulders: wicker bands, a rim, stones heaped in it
	if look.get("basket", false) and not sculpted_body:
		var wicker := Color(0.78, 0.58, 0.3)
		# Square on the back, riding high so the rim and stones show over both shoulders
		var bk := _pivot(_torso, Vector3(0.0, 0.66, -0.37))
		bk.rotation = Vector3(-0.14, 0, 0)
		_part(bk, _soft(Vector3(0.7, 0.5, 0.32), 0.06), wicker, Vector3.ZERO)
		for y: float in [-0.14, 0.0, 0.14]:
			_part(bk, _soft(Vector3(0.715, 0.04, 0.335), 0.012), wicker.darkened(0.16), Vector3(0, y, 0))
		for x: float in [-0.24, 0.0, 0.24]:
			_part(bk, _soft(Vector3(0.035, 0.46, 0.335), 0.01), wicker.darkened(0.08), Vector3(x, 0, 0))
		_part(bk, _soft(Vector3(0.75, 0.08, 0.37), 0.025), wicker.darkened(0.3), Vector3(0, 0.26, 0))
		if look.get("basket_stones", false):
			for st: Array in [[Vector3(-0.24, 0.31, 0.02), 0.3, 0.19], [Vector3(0.0, 0.34, -0.04), -0.4, 0.21],
					[Vector3(0.24, 0.31, 0.04), 0.9, 0.18], [Vector3(-0.1, 0.38, 0.07), 0.2, 0.15], [Vector3(0.14, 0.38, -0.05), 0.5, 0.15]]:
				_part(bk, _bbox(Vector3(st[2], st[2] * 0.85, st[2]), 0.035), Palette.WALL_STONE.darkened(0.08 + st[1] * 0.04),
					st[0], Vector3(0.25, st[1], 0.15))
		for sx: float in [-1.0, 1.0]:
			_part(_torso, _soft(Vector3(0.09, 0.08, 0.5), 0.02), LEATHER, Vector3(0.17 * sx, SHOULDER_Y - HIP_Y + 0.02, -0.05))
	if look.get("planks", false):
		var pb := _pivot(_torso, Vector3(0, 0.5, -0.3))
		pb.rotation = Vector3(0.12, 0, 1.38)
		for pk: Array in [[-0.1, 0.0, 0.0], [0.03, 0.06, 0.04], [0.15, -0.04, -0.03]]:
			_part(pb, _bbox(Vector3(0.16, 1.20, 0.09), 0.015), WOOD_LIGHT.darkened(0.04 + pk[2]),
				Vector3(pk[0], pk[1], -absf(pk[2]) * 2.0))
		_part(pb, _soft(Vector3(0.44, 0.06, 0.12), 0.015), BAND.lightened(0.2), Vector3(0.02, -0.05, -0.02))
		for sx: float in [-1.0, 1.0]:
			_part(_torso, _soft(Vector3(0.07, 0.07, 0.46), 0.02), LEATHER, Vector3(0.15 * sx, SHOULDER_Y - HIP_Y + 0.02, -0.04))
	# Where a load rides when carried in front, at the chest
	if not sculpted_body:
		_carry_anchor = _pivot(_torso, Vector3(0, 0.4, 0.42))
	_hand_r = hands[1]
	_hands = hands

	# ── Head: a rounded jaw with layered cheeks, ears and expressive brows
	_head = _pivot(_torso, Vector3(0, NECK_Y - HIP_Y, 0))
	if look.get("sculpted_builder", false):
		BUILDER_HEAD.new().build(self, _head, look)
	else:
		var hw := 0.64
		var hh := 0.6
		var hd := 0.58
		var hc := Vector3(0, hh * 0.5 - 0.02, 0.02)
		var front := hc.z + hd * 0.5
		_part(_head, _soft(Vector3(hw, hh, hd), 0.20), skin, hc)
		for sx: float in [-1.0, 1.0]:
			_part(_head, _ellipsoid(Vector3(0.115, 0.17, 0.13)), skin.darkened(0.07), hc + Vector3((hw * 0.5 + 0.02) * sx, -0.02, 0.02))
			_part(_head, _ellipsoid(Vector3(0.04, 0.085, 0.075)), skin.darkened(0.22), hc + Vector3((hw * 0.5 + 0.053) * sx, -0.02, 0.055))
			# Cheeks soften the jaw and support the eyes above the beard line.
			_part(_head, _ellipsoid(Vector3(0.21, 0.14, 0.085)), skin, hc + Vector3(0.19 * sx, -0.09, front - 0.05))
		var hat: String = look.get("hat", "band")
		_hair(look.get("hair_style", "short"), hair, hc, hw, hh, hd, hat)
		# Face: dark eyes with a catch-light, heavy brows, a big wedge of a nose
		for sx: float in [-1.0, 1.0]:
			_part(_head, _ellipsoid(Vector3(0.085, 0.115, 0.045)), Color(0.1, 0.06, 0.04), hc + Vector3(0.125 * sx, 0.0, front + 0.005))
			_part(_head, _soft(Vector3(0.028, 0.028, 0.02), 0.006), Color(1, 0.97, 0.9), hc + Vector3(0.125 * sx + 0.02, 0.03, front + 0.02))
			var brow := _part(_head, _soft(Vector3(0.2, 0.075, 0.07), 0.02), look.get("brow", hair),
				hc + Vector3(0.13 * sx, 0.1, front + 0.01))
			# Inner ends low: determined on the crew, scowling on enemies
			brow.rotation.z = (0.42 if look.get("brows", false) else 0.22) * sx
		_part(_head, _ellipsoid(Vector3(0.15, 0.17, 0.16)), skin.darkened(0.05), hc + Vector3(0, -0.07, front + 0.045))
		# Beard: a rounded mass around the jaw down onto the chest, cheek lobes up to the ears,
		# sideburns into the hair, clumps along the jaw, the moustache as a bar under the nose
		var bl: String = look.get("beard", "")
		var bc: Color = look.get("beard_color", hair)
		if not bl.is_empty():
			var bh: float = {"full": 0.36, "long": 0.46, "short": 0.25}.get(bl, 0.3)
			_part(_head, _ellipsoid(Vector3(hw + 0.03, bh * 1.15, 0.32)), bc, hc + Vector3(0, -0.1 - bh * 0.5, front - 0.11))
			# Overlapping tapered locks, with a scalloped lower silhouette.
			for lock_index in 7:
				var u := (lock_index - 3) / 3.0
				var lock_height := bh * (0.76 - absf(u) * 0.22)
				_part(_head, _ellipsoid(Vector3(0.13, lock_height, 0.13)), bc.lightened(0.025 * (lock_index % 3)),
					hc + Vector3(u * 0.25, -0.14 - bh * 0.48 + absf(u) * 0.06, front + 0.015 - absf(u) * 0.055), Vector3(0.08, 0, -u * 0.22))
			for sx: float in [-1.0, 1.0]:
				_part(_head, _ellipsoid(Vector3(0.15, 0.30, hd * 0.72)), bc, hc + Vector3((hw * 0.5 - 0.03) * sx, -0.13, 0.03))
				_part(_head, _ellipsoid(Vector3(0.12, 0.26, 0.2)), bc, hc + Vector3((hw * 0.5 + 0.005) * sx, 0.03, 0.02))
				_part(_head, _ellipsoid(Vector3(0.18, 0.19, 0.22)), bc.darkened(0.06), hc + Vector3(0.17 * sx, -0.1 - bh + 0.04, front - 0.1), Vector3(0, 0, 0.3 * sx))
			if bl != "short":
				_part(_head, _ellipsoid(Vector3(hw * (0.45 if bl == "long" else 0.55), 0.19, 0.25)), bc.darkened(0.04),
					hc + Vector3(0, -0.1 - bh - 0.03, front - 0.1))
			for sx: float in [-1.0, 1.0]:
				_part(_head, _ellipsoid(Vector3(0.22, 0.095, 0.12)), bc.darkened(0.1), hc + Vector3(sx * 0.09, -0.15, front + 0.05), Vector3(0, 0, sx * 0.22))
			_part(_head, _soft(Vector3(0.1, 0.03, 0.02), 0.008), Color(0.35, 0.12, 0.08), hc + Vector3(0, -0.225, front + 0.035))
		else:
			_part(_head, _soft(Vector3(0.12, 0.035, 0.02), 0.008), Color(0.35, 0.12, 0.08), hc + Vector3(0, -0.19, front + 0.005))

		var hat_c: Color = look.get("hat_color", LINEN)
		match hat:
			"band", "scarf":
				# Cloth band tied round the brow, hair showing above; a scarf is deeper,
				# striped, with long tails
				var scarf := hat == "scarf"
				var bh2 := 0.17 if scarf else 0.12
				var by := hh * 0.5 - (0.11 if scarf else 0.1)
				_part(_head, _oval_band(Vector3(hw + 0.08, bh2, hd + 0.08)), hat_c, hc + Vector3(0, by, 0))
				if scarf:
					for dy: float in [-0.045, 0.045]:
						_part(_head, _oval_band(Vector3(hw + 0.09, 0.03, hd + 0.09)), look["stripe"], hc + Vector3(0, by + dy, 0))
				_part(_head, _soft(Vector3(0.14, 0.14, 0.1), 0.035), hat_c.darkened(0.1), hc + Vector3(0.12, by, -hd * 0.5 - 0.05))
				if look.get("tails", true):
					var tl := 0.36 if scarf else 0.26
					for t: Array in [[0.1, 0.4], [-0.02, -0.25]]:
						var tail := _part(_head, _soft(Vector3(0.11, tl, 0.04), 0.012), hat_c.darkened(0.05),
							hc + Vector3(0.12 + t[0], by - tl * 0.5 - 0.03, -hd * 0.5 - 0.1), Vector3(0.5, 0, t[1]))
						if scarf:
							_part(tail, _soft(Vector3(0.115, 0.03, 0.045), 0.008), look["stripe"], Vector3(0, -tl * 0.25, 0))
			"wrap":
				# Head-cloth over the crown, coloured band, cloth falling behind to the shoulders
				_part(_head, _ellipsoid(Vector3(hw + 0.14, 0.35, hd + 0.14)), hat_c, hc + Vector3(0, hh * 0.5 + 0.02, -0.01))
				# Folds of the wound cloth: raised bands slanting round the crown
				for k in 3:
					var f := _part(_head, _ellipsoid(Vector3(hw + 0.12, 0.19, hd + 0.12)), hat_c.darkened(0.07 + k * 0.02),
						hc + Vector3(0, hh * 0.5 + 0.06 + k * 0.07, -0.01 - k * 0.02))
					f.rotation.z = 0.12 - k * 0.1
					f.scale = Vector3.ONE * (1.0 - k * 0.1)
				_part(_head, _oval_band(Vector3(hw + 0.12, 0.1, hd + 0.12)), look["band"], hc + Vector3(0, hh * 0.5 - 0.1, -0.01))
				_part(_head, _soft(Vector3(hw + 0.08, 0.6, 0.12), 0.04), hat_c.darkened(0.04), hc + Vector3(0, -0.12, -hd * 0.5 - 0.04), Vector3(0.12, 0, 0))
				for sx: float in [-1.0, 1.0]:
					_part(_head, _ellipsoid(Vector3(0.13, 0.53, hd * 0.7)), hat_c.darkened(0.02), hc + Vector3((hw * 0.5 + 0.05) * sx, -0.06, -0.08), Vector3(-0.12, 0, sx * 0.10))
			"hood":
				_part(_head, _soft(Vector3(hw + 0.12, hh * 0.55, hd + 0.1), 0.1), hat_c, hc + Vector3(0, hh * 0.3, -0.04))
				for sx: float in [-1.0, 1.0]:
					_part(_head, _soft(Vector3(0.08, hh * 0.8, hd * 0.9), 0.03), hat_c, hc + Vector3((hw * 0.5 + 0.05) * sx, -0.05, -0.05))
				_part(_head, _soft(Vector3(hw + 0.1, 0.55, 0.12), 0.04), hat_c, hc + Vector3(0, -0.2, -hd * 0.5 - 0.02), Vector3(0.12, 0, 0))
			"helmet":
				_part(_head, _cyl(0.0, hw * 0.62, 0.42), hat_c, hc + Vector3(0, hh * 0.5 + 0.18, -0.02))
				_part(_head, _soft(Vector3(hw + 0.1, 0.09, hd + 0.1), 0.03), hat_c.darkened(0.25), hc + Vector3(0, hh * 0.5 - 0.04, -0.01))

	# Weapons
	match look.get("weapon", ""):
		"spear":
			_spear = _pivot(_torso, Vector3(-ARM_X - 0.08, 0.28, 0.12))
			_part(_spear, _soft(Vector3(0.07, 2.2, 0.07), 0.015), Color(0.42, 0.28, 0.16), Vector3(0, 0.55, 0))
			_part(_spear, _cyl(0.0, 0.08, 0.28), Color(0.62, 0.60, 0.56), Vector3(0, 1.78, 0))
		"dagger":
			var d := _pivot(hands[1], Vector3(0, -0.05, 0.05))
			_part(d, _soft(Vector3(0.06, 0.34, 0.03), 0.01), Color(0.72, 0.70, 0.66), Vector3(0, -0.2, 0))
			_part(d, _soft(Vector3(0.17, 0.05, 0.06), 0.015), Color(0.55, 0.42, 0.22), Vector3(0, -0.02, 0))
	if look.has("sack"):
		var sack := _pivot(_torso, Vector3(0, 0.38, -0.3))
		sack.rotation.x = 0.25
		_part(sack, _soft(Vector3(0.46, 0.5, 0.26), 0.12), look["sack"], Vector3.ZERO)
		_part(sack, _soft(Vector3(0.14, 0.12, 0.14), 0.04), Color(look["sack"]).darkened(0.3), Vector3(0, 0.3, 0))
	if look.has("shield"):
		# A round shield of hide on a wicker frame: a dished face, a rawhide rim laced on, a
		# bronze boss and a ring of rivets, a pale band painted round it
		var face: Color = look["shield"]
		var bronze := Color(0.62, 0.46, 0.24)
		var sh := _pivot(_torso, Vector3(ARM_X + 0.06, 0.34, 0.18))
		sh.rotation = Vector3(0.08, 0.55, 0.0)
		_part(sh, _ellipsoid(Vector3(0.74, 0.74, 0.12)), face, Vector3.ZERO)
		_part(sh, _ellipsoid(Vector3(0.6, 0.6, 0.1)), face.lightened(0.06), Vector3(0, 0, 0.016))
		_part(sh, _torus(0.33, 0.39), Color(0.52, 0.38, 0.24), Vector3(0, 0, 0.01), Vector3(PI * 0.5, 0, 0))
		_part(sh, _torus(0.20, 0.215), face.lightened(0.32), Vector3(0, 0, 0.045), Vector3(PI * 0.5, 0, 0))
		_part(sh, _ellipsoid(Vector3(0.17, 0.17, 0.12)), bronze, Vector3(0, 0, 0.06))
		_part(sh, _ellipsoid(Vector3(0.05, 0.05, 0.04)), bronze.lightened(0.3), Vector3(0.02, 0.02, 0.115))
		for i in 10:
			var a := TAU * i / 10.0
			_part(sh, _ellipsoid(Vector3(0.035, 0.035, 0.025)), bronze.lightened(0.1), Vector3(cos(a) * 0.29, sin(a) * 0.29, 0.045))
	# Worker's hammer: a squared stone head on a stout handle
	if look.get("tool", false):
		_tool = _pivot(hands[1], Vector3(0, -0.02, 0.02))
		_part(_tool, _soft(Vector3(0.07, 0.56, 0.07), 0.018), Color(0.50, 0.34, 0.20), Vector3(0, -0.24, 0))
		_part(_tool, _soft(Vector3(0.09, 0.08, 0.09), 0.02), LEATHER, Vector3(0, -0.06, 0))
		_part(_tool, _bbox(Vector3(0.36, 0.22, 0.22), 0.05), Color(0.58, 0.57, 0.58), Vector3(0, -0.54, 0))
		if look.get("tool_always", false) and not look.get("sculpted_body", false):
			# Between strokes it hangs from the belt at the hip, head up
			_belt_tool = _pivot(_torso, Vector3(-0.36, 0.2, 0.08))
			_belt_tool.rotation = Vector3(0.15, 0, -0.12)
			_part(_belt_tool, _soft(Vector3(0.06, 0.42, 0.06), 0.015), Color(0.50, 0.34, 0.20), Vector3(0, -0.08, 0))
			_part(_belt_tool, _soft(Vector3(0.28, 0.17, 0.17), 0.04), Color(0.58, 0.57, 0.58), Vector3(0, 0.15, 0))
		_tool_visible()
	# Worker's sword: short bronze-hued blade, leather grip; sheathed at the left hip
	if look.get("sword", false):
		var blade := Color(0.84, 0.82, 0.76)
		var brass := Color(0.78, 0.58, 0.26)
		_sword = _pivot(hands[1], Vector3(0, -0.02, 0.02))
		_part(_sword, _soft(Vector3(0.08, 0.2, 0.08), 0.02), LEATHER, Vector3(0, -0.02, 0))
		_part(_sword, _soft(Vector3(0.3, 0.07, 0.1), 0.02), brass, Vector3(0, -0.14, 0))
		_part(_sword, _soft(Vector3(0.15, 0.72, 0.04), 0.015), blade, Vector3(0, -0.52, 0))
		# Sheathed: short, slung back along the hip so it doesn't read as a staff
		_belt_sword = _pivot(_torso, Vector3(0.42, 0.07, -0.15) if look.get("sculpted_body", false) else Vector3(ARM_X - 0.02, 0.1, 0.06))
		_belt_sword.rotation = Vector3(0.95, 0, 0.1)
		_part(_belt_sword, _soft(Vector3(0.13, 0.5, 0.08), 0.03), LEATHER.darkened(0.2), Vector3(0, -0.22, 0))
		_part(_belt_sword, _soft(Vector3(0.08, 0.15, 0.08), 0.02), LEATHER, Vector3(0, 0.13, 0))
		_part(_belt_sword, _soft(Vector3(0.24, 0.06, 0.1), 0.02), brass, Vector3(0, 0.04, 0))
		_tool_visible()
	_proportions()

func _proportions() -> void:
	if _head != null:
		# Under the stretched torso: divide it back out so the head stays round
		_head.scale = Vector3(_head_scale, _head_scale / _torso_stretch, _head_scale)
	for leg: Node3D in [_leg_l, _leg_r]:
		if leg != null:
			leg.scale.y = _leg_stretch
			leg.position.y *= _leg_stretch
			_flatten_feet(leg)
	if _torso != null:
		_torso.position.y *= _leg_stretch
		_torso.scale.y = _torso_stretch
	# Longer upper and forearm; the hands (and what they hold) keep their size
	for arm: Node3D in [_arm_l, _arm_r]:
		if arm != null:
			arm.scale.y = _arm_stretch
	for hand in _hands:
		hand.scale.y = 1.0 / _arm_stretch

## The leg stretch is for shins, not feet: press everything below the ankle back to its
## authored height, sole still on the ground (y' = -HIP + (y + HIP) / stretch)
func _flatten_feet(leg: Node3D) -> void:
	var i := [_leg_l, _leg_r].find(leg)
	if i >= 0 and i < _ankles.size():
		# Jointed legs: the foot hangs from its ankle pivot, so press the pivot itself
		var knee := _knees[i]
		var ankle_pivot := _ankles[i]
		var ya := knee.position.y + ankle_pivot.position.y
		ankle_pivot.position.y = ya / _leg_stretch - HIP_Y + HIP_Y / _leg_stretch - knee.position.y
		ankle_pivot.scale.y = 1.0 / _leg_stretch
		return
	var ankle := -HIP_Y + 0.16
	for c: Node in leg.get_children():
		var n := c as Node3D
		if n == null:
			continue
		var top := n.position.y
		if n is MeshInstance3D:
			var box: AABB = (n as MeshInstance3D).mesh.get_aabb()
			top = n.position.y + (box.position.y + box.size.y) * n.scale.y
		if top > ankle:
			continue
		n.scale.y /= _leg_stretch
		n.position.y = n.position.y / _leg_stretch - HIP_Y + HIP_Y / _leg_stretch

# Hair by style: a cap over the crown and down the back, chunky locks on top
func _hair(style: String, hair: Color, hc: Vector3, hw: float, hh: float, hd: float, hat: String) -> void:
	if hat == "wrap" or hat == "hood" or hat == "helmet":
		# Only the back shows under the cloth
		_part(_head, _soft(Vector3(hw + 0.02, hh * 0.5, 0.14), 0.05), hair, hc + Vector3(0, -0.02, -hd * 0.5 + 0.05))
		return
	_part(_head, _ellipsoid(Vector3(hw + 0.08, 0.30, hd + 0.08)), hair, hc + Vector3(0, hh * 0.5 + 0.01, -0.01))
	_part(_head, _ellipsoid(Vector3(hw + 0.04, hh * 0.85, 0.23)), hair, hc + Vector3(0, 0.04, -hd * 0.5 + 0.03))
	var crown := hc + Vector3(0, hh * 0.5 + 0.09, 0)
	match style:
		"curly":
			# Tight curls: a cap of overlapping curls, spilling over the band and down the back
			var i := 0
			for x: float in [-0.24, -0.08, 0.08, 0.24]:
				for z: float in [-0.22, -0.06, 0.1, 0.24]:
					var j := hash(i) % 7 / 7.0
					_part(_head, _ellipsoid(Vector3(0.18, 0.16, 0.18)), hair.lightened(j * 0.12),
						crown + Vector3(x, j * 0.05 + 0.04 - (absf(x) + absf(z)) * 0.22, z), Vector3(j, j * 2.0, 0))
					i += 1
			for x: float in [-0.25, -0.08, 0.08, 0.25]:
				for y: float in [-0.25, -0.42]:
					_part(_head, _ellipsoid(Vector3(0.18, 0.18, 0.16)), hair.lightened(0.04 if y < -0.3 else 0.0), crown + Vector3(x, y, -hd * 0.5 - 0.04))
		"bushy":
			# Thick mane: big uneven locks, lighter on top, falling to the shoulders
			_locks(hair, crown, 0.23, 0.2)
			_part(_head, _soft(Vector3(hw + 0.12, 0.4, 0.2), 0.06), hair, crown + Vector3(0, -0.48, -hd * 0.5))
			for sx: float in [-1.0, 1.0]:
				for lock_index in 3:
					_part(_head, _ellipsoid(Vector3(0.16, 0.27, 0.15)), hair.lightened(lock_index * 0.025),
						crown + Vector3((hw * 0.5 + 0.015) * sx, -0.36 - lock_index * 0.035, -0.02 - lock_index * 0.10), Vector3(-0.25, 0, sx * 0.15))
		_:
			# Short and thick: a crop of uneven locks, a layered fringe above the band
			_locks(hair, crown, 0.2, 0.19)
			for x: float in [-0.2, 0.0, 0.2]:
				_part(_head, _soft(Vector3(0.2, 0.1, 0.1), 0.03), hair.lightened(0.03), hc + Vector3(x, hh * 0.5 + 0.02, hd * 0.5 - 0.02), Vector3(0.3, 0, x))

# A 3×3 crop of chunky locks over the crown: each tipped and raised a little differently,
# so from the iso camera it reads as hair rather than a lid of tiles
func _locks(hair: Color, crown: Vector3, size: float, step: float) -> void:
	var i := 0
	for x: float in [-step, 0.0, step]:
		for z: float in [-step, 0.0, step]:
			var j := float(hash(i * 7 + 3) % 11) / 11.0
			var k := float(hash(i * 13 + 5) % 7) / 7.0
			_part(_head, _ellipsoid(Vector3(size * 1.42, size * 0.72, size * 0.88)), hair.lightened(0.02 + j * 0.1).darkened(k * 0.06),
				crown + Vector3(x + (k - 0.5) * 0.04, j * 0.06 + 0.045 - (absf(x) + absf(z)) * 0.26, z), Vector3((j - 0.5) * 0.7, j * 1.6, (k - 0.5) * 0.7))
			i += 1

func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n

func _part(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _part_mat
	# Outline shells on tiny parts (eyes, mouth, buckles) read as dirt specks
	var ab := mesh.get_aabb().size
	if _outline_mat != null and minf(ab.x, minf(ab.y, ab.z)) >= OUTLINE_MIN_PART:
		mi.material_overlay = _outline_mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	mi.set_instance_shader_parameter("part_color", color)
	_parts.append(mi)
	return mi

# Shared meshes, keyed by size — every rig in the game reuses the same few
static func _cached(key: String, make: Callable) -> Mesh:
	if not _meshes.has(key):
		_meshes[key] = make.call()
	return _meshes[key]

static func _sphere(r: float) -> Mesh:
	return _cached("s%.3f" % r, func():
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = 14
		m.rings = 7
		return m)

static func _capsule(r: float, h: float) -> Mesh:
	return _cached("c%.3f,%.3f" % [r, h], func():
		var m := CapsuleMesh.new()
		m.radius = r
		m.height = h
		m.radial_segments = 10
		m.rings = 3
		return m)

static func _cyl(top: float, bottom: float, h: float) -> Mesh:
	return _cached("y%.3f,%.3f,%.3f" % [top, bottom, h], func():
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = h
		m.radial_segments = 14
		m.rings = 1
		return m)

static func _box(size: Vector3) -> Mesh:
	return _cached("b%s" % size, func():
		var m := BoxMesh.new()
		m.size = size
		return m)

# Rounded sculpted surfaces for skin, cloth and leather. Project a subdivided
# box onto its rounded inner core; analytic normals keep the bevels continuous.
# Cached once per shape, just like the hard-surface meshes.
static func _soft(size: Vector3, bevel: float) -> Mesh:
	return _cached("soft%s%.3f" % [size, bevel], func():
		var radius := minf(maxf(bevel * 1.8, size[size.min_axis_index()] * 0.35), size[size.min_axis_index()] * 0.49)
		var core := size * 0.5 - Vector3.ONE * radius
		var source := BoxMesh.new()
		source.size = size
		source.subdivide_width = 5
		source.subdivide_height = 5
		source.subdivide_depth = 5
		var arrays := source.get_mesh_arrays()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in vertices.size():
			var inner := vertices[i].clamp(-core, core)
			var normal := (vertices[i] - inner).normalized()
			vertices[i] = inner + normal * radius
			normals[i] = normal
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TANGENT] = null
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh)

static func _oval_band(size: Vector3) -> Mesh:
	return _cached("band%s" % size, func():
		var source := CylinderMesh.new()
		source.top_radius = 0.5
		source.bottom_radius = 0.5
		source.height = 1.0
		source.radial_segments = 32
		var arrays := source.get_mesh_arrays()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in vertices.size():
			vertices[i] *= size
			normals[i] = (normals[i] / size).normalized()
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TANGENT] = null
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh)

# A flared hem with shallow radial folds, instead of a rectangular skirt.
static func _cloth_skirt(height: float) -> Mesh:
	return _cached("cloth%.3f" % height, func():
		var source := CylinderMesh.new()
		source.top_radius = 0.29
		source.bottom_radius = 0.35
		source.height = height
		source.radial_segments = 48
		source.rings = 4
		var arrays := source.get_mesh_arrays()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in vertices.size():
			var v := vertices[i]
			var angle := atan2(v.z, v.x)
			var fall := clampf(0.5 - v.y / height, 0.0, 1.0)
			var fold := 1.0 + sin(angle * 9.0 + 0.4) * 0.045 * fall
			vertices[i] = Vector3(v.x * fold, v.y, v.z * fold * 0.72)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_TANGENT] = null
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var surface := SurfaceTool.new()
		surface.create_from(mesh, 0)
		surface.generate_normals()
		return surface.commit())

## Small ovals (eyes, ears, fingers, curls) get fewer facets than big ones: a figure is
## ~90 of them, and at iso distance the difference is invisible.
static func _ellipsoid(size: Vector3, lod := false) -> Mesh:
	var big := size[size.max_axis_index()]
	var radial := 16 if not lod or big >= 0.3 else (12 if big >= 0.1 else 8)
	return _cached("oval%s_%d" % [size, radial], func():
		var source := SphereMesh.new()
		source.radius = 0.5
		source.height = 1.0
		source.radial_segments = radial
		source.rings = radial / 2
		var arrays := source.get_mesh_arrays()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in vertices.size():
			vertices[i] *= size
			normals[i] = (normals[i] / size).normalized()
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TANGENT] = null
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh)

# Chamfered block, flat-shaded: the chunky low-poly look (Chunky)
static func _bbox(size: Vector3, bevel: float) -> Mesh:
	return _cached("bb%s%.3f" % [size, bevel], func():
		var m := minf(size.x, minf(size.y, size.z))
		return Chunky.bevel_box(size, minf(bevel * BEVEL_SCALE, m * 0.3)))

static func _torus(inner: float, outer: float) -> Mesh:
	return _cached("t%.3f,%.3f" % [inner, outer], func():
		var m := TorusMesh.new()
		m.inner_radius = inner
		m.outer_radius = outer
		m.rings = 16
		m.ring_segments = 6
		return m)

# Contact shadow + optional player-colour ring, flat on the ground (sibling, not
# rotated with the body)
func _build_marker() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.9, 1.9)
	quad.orientation = PlaneMesh.FACE_Y
	_marker_mat = ShaderMaterial.new()
	_marker_mat.shader = MARKER_SHADER
	_marker_mat.set_shader_parameter("ring_radius", 0.34)
	_marker_mat.set_shader_parameter("ring_width", 0.07)
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = _marker_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, 0.03, 0)
	get_parent().add_child.call_deferred(mi)
