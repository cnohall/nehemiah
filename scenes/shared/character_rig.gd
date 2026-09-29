class_name CharacterRig
extends Node3D

# Sculpted chibi figure built from shared procedural meshes, animated in code.
# Stands in for the old AnimatedSprite3D: same API (play / animation / frame /
# speed_scale / frame_changed / animation_finished / hit_flash / hitstop / squash),
# so Player and Enemy drive it exactly like the old sprite sheets. Animation names keep the
# "<anim>_<dir>" form; the rig keeps a virtual frame clock (CharAnim.ANIM_CFG timing)
# so gameplay beats — sling release, build strike, footsteps — land on the same frames.
#
# Proportions: big head (~40% of height), stubby robe body, short legs — reads at
# gameplay zoom. The player colour is the robe; the head-wrap is what the iso camera
# sees most, so it stays light and bright.

const BUILDER_HEAD := preload("res://scenes/shared/builder_head.gd")

const PART_SHADER    := preload("res://assets/shaders/toon_part.gdshader")
const OUTLINE_SHADER := preload("res://assets/shaders/toon_outline.gdshader")
const MARKER_SHADER  := preload("res://assets/shaders/ground_marker.gdshader")
const FLASH_TIME   := 0.16
const SQUASH_TIME  := 0.28
const STEP_FRAMES  := [1, 5]   # footfalls in the 8-frame walk / run cycles
const STRIKE_FRAME := 4        # downstroke of the build loop
const TURN_RATE    := 16.0     # rad/s-ish smoothing toward the facing direction
const BASE_SCALE   := 1.3
const BEVEL_SCALE  := 1.3      # chamfer as a multiple of each part's authored bevel
# Building: turn a three-quarter view toward the camera so the mallet arm isn't
# hidden behind the body when the wall is "up" screen (the usual case)
const BUILD_TURN   := -0.65
const BLEND_TIME   := 0.09     # cross-fade from the old pose when the animation changes
const WINDUP_FULL  := 0.9      # wind-up reaches full tension (= Player.SLING_CHARGE_TIME)

# Rig dimensions (metres, before scale). Feet at y = 0.
const HIP_Y      := 0.36
const SHOULDER_Y := 0.86
const NECK_Y     := 0.98
const HEAD_R     := 0.34
const ARM_X      := 0.4

# Screen directions of the "<anim>_<dir>" suffixes (iso camera looks down -x -z)
const DIR_VEC := {
	"down":  Vector3(0.70710678, 0, 0.70710678),
	"up":    Vector3(-0.70710678, 0, -0.70710678),
	"right": Vector3(0.70710678, 0, -0.70710678),
	"left":  Vector3(-0.70710678, 0, 0.70710678),
}

const OUTLINE_PLAYER := Color(0.17, 0.11, 0.07)
const OUTLINE_MIN_PART := 0.07
const SKIN := [Color(0.86, 0.58, 0.38), Color(0.90, 0.66, 0.46), Color(0.72, 0.48, 0.31), Color(0.64, 0.42, 0.27)]
const HAIR_DARK := Color(0.30, 0.18, 0.11)
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
var _stride := 0.0       # leg phase for stepping while in a non-locomotion pose
var _blend_from: Dictionary = {}
var _blend := 1.0        # 0..1 progress of the cross-fade from _blend_from

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
var _sword: Node3D          # worker's sword, in hand only for the cut…
var _belt_sword: Node3D     # …and girded at the side otherwise (Neh. 4:18)

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
	# Dye, not paint: pull the UI colour a little toward undyed wool
	var dye := color.lerp(Color(0.55, 0.44, 0.33), 0.1)
	var look := {
		"robe": LINEN, "trim": LINEN.darkened(0.12), "sash": LEATHER, "band": BAND,
		"outline": OUTLINE_PLAYER, "no_outline": true, "tool": true, "sword": true, "hat": "band", "hat_color": dye,
	}
	match slot % 4:
		0:
			look.merge({"skin": SKIN[0], "hair": HAIR_DARK, "beard": "full", "hair_style": "short",
				"strap": true, "basket": true, "basket_stones": true, "trim": LINEN.darkened(0.1),
				"tool_always": true, "sculpted_builder": true}, true)
		1:
			look.merge({"skin": SKIN[2], "hair": HAIR_BLACK, "beard": "short", "hair_style": "curly",
				"hat": "scarf", "hat_color": Color(0.95, 0.92, 0.85), "stripe": dye,
				"sash": dye, "sash_tails": true, "trim": dye.darkened(0.1), "satchel": LEATHER.lightened(0.05)}, true)
		2:
			look.merge({"skin": SKIN[1], "hair": HAIR_GINGER, "beard": "full", "hair_style": "bushy",
				"tails": false, "robe": dye.lerp(Color(0.55, 0.50, 0.36), 0.35), "trim": dye.darkened(0.3),
				"hat_color": dye.darkened(0.15), "apron": Color(0.62, 0.44, 0.28), "planks": true,
				"bracers": true, "brow": HAIR_GINGER.darkened(0.2)}, true)
		3:
			look.merge({"skin": SKIN[0], "hair": HAIR_GREY, "beard": "long", "hat": "wrap",
				"hat_color": Color(0.96, 0.94, 0.89), "band": dye, "robe": Color(0.93, 0.90, 0.83),
				"vest": dye, "long_robe": true, "scroll": Color(0.90, 0.82, 0.62),
				"trim": dye.darkened(0.2), "brow": Color(0.62, 0.60, 0.56)}, true)
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
				"sash": Color(0.22, 0.14, 0.10), "hat": "helmet", "hat_color": Color(0.74, 0.54, 0.26),
				"beard": "full", "weapon": "spear", "shield": Color(0.56, 0.18, 0.12)})
		"raider":
			base.merge({"robe": Color(0.20, 0.17, 0.18), "sash": Color(0.60, 0.16, 0.12),
				"hat": "hood", "hat_color": Color(0.46, 0.12, 0.10), "beard": "short",
				"weapon": "dagger", "cape": Color(0.52, 0.13, 0.11)})
		_:
			base.merge({"robe": Color(0.36, 0.28, 0.22), "sash": Color(0.62, 0.20, 0.14),
				"hat": "hood", "hat_color": Color(0.17, 0.14, 0.13), "beard": "short", "weapon": "spear"})
	return base

# ── Setup ──────────────────────────────────────────────────

func setup(look: Dictionary, size_scale := 1.0) -> void:
	_size = size_scale * BASE_SCALE
	scale = Vector3.ONE * _size
	_build(look)
	_build_marker()

## Rebuild with another look (e.g. a player's slot colour), keeping the pose
func set_look(look: Dictionary) -> void:
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
	_build(look)
	_apply_pose()

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

## Cartoon squash & stretch (x, y factors), springing back. Feet stay planted.
func squash(amount: Vector2) -> void:
	if _squash_tween:
		_squash_tween.kill()
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
	posed.emit(delta)

func _set_frame(f: int) -> void:
	if f == frame:
		return
	frame = f
	frame_changed.emit()
	if frame in STEP_FRAMES and (_base == "run" or _base == "walk"):
		footstep.emit()
	elif frame == STRIKE_FRAME and _base == "build":
		strike.emit()

# Face the animation's direction; while moving roughly that way, follow the actual
# path instead so turns are smooth rather than four-way snaps.
func _update_facing(delta: float) -> void:
	var target: Vector3 = DIR_VEC[_dir]
	var p := get_parent() as Node3D
	if p != null:
		var pos := p.global_position
		if _has_last and delta > 0.0:
			var step := pos - _last_pos
			step.y = 0.0
			_move_speed = lerpf(_move_speed, step.length() / delta, clampf(delta * 12.0, 0.0, 1.0))
			_stride += _move_speed * delta * 2.4
			if step.length() > 0.02 * delta * 60.0 and step.normalized().dot(target) > 0.3:
				target = step.normalized()
		_last_pos = pos
		_has_last = true
	var want := atan2(target.x, target.z)
	if not is_nan(hold_yaw):
		want = hold_yaw
	if _base == "windup" or _base == "slash" or _base == "sword":
		want = aim_yaw   # the sling faces its target, any angle
	elif _base == "build":
		want += BUILD_TURN
	_yaw = lerp_angle(_yaw, want, clampf(delta * TURN_RATE, 0.0, 1.0))
	rotation.y = _yaw

# ── Posing ─────────────────────────────────────────────────

func _apply_pose() -> void:
	if _body == null:
		return
	var fps: float = _cfg.get("fps", 4.0)
	var n: float = _cfg.get("cycle", [0]).size()
	var k := clampf(_t * fps / n, 0.0, 1.0)           # one-shot progress 0..1
	var ph := _t * fps / n * TAU                        # loop phase
	# Rest pose
	var body_y := 0.0
	var body_rx := 0.0
	var lean := 0.0
	var twist := 0.0                                    # torso yaw; negative pulls the right shoulder back
	var head_rx := 0.0
	var head_ry := 0.0
	var al := Vector3(-0.08, 0, 0.14)                   # left arm (rx, ry, rz)
	var ar := Vector3(-0.08, 0, -0.14)
	var ll := 0.0
	var lr := 0.0
	var spear_rx := 0.0
	var spear_z := 0.0
	match _base:
		"idle":
			var b := sin(_t * 2.4)
			body_y = b * 0.012
			head_rx = b * 0.03
			al.z += b * 0.03
			ar.z -= b * 0.03
		"run", "walk":
			var s := sin(ph)
			var stride := 0.85 if _base == "run" else 0.55
			ll = -s * stride
			lr = s * stride
			al.x = s * 0.9
			ar.x = -s * 0.9
			body_y = absf(cos(ph)) * (0.07 if _base == "run" else 0.04)
			lean = 0.2 if _base == "run" else 0.05
		"windup":
			# Sling whirl: throwing hand raised and circling in step with the stone, off hand
			# pointing at the target, shoulders coiling back as the tension builds
			var c := ease(minf(_t / WINDUP_FULL, 1.0), 0.6)
			var wc := cos(whirl_phase)
			var ws := sin(whirl_phase)
			ar = Vector3(-0.6 + wc * 0.22, 0, -2.3 + ws * 0.18)
			al = Vector3(-1.3 + ws * 0.04, 0, 0.32)
			twist = -0.2 - 0.25 * c
			head_ry = -twist * 0.85                         # eyes stay on the target
			lean = -0.05 - 0.08 * c
			body_y = -0.025 * c + ws * 0.008
			# Braced stance, lead (left) foot forward; stepping when walking while winding up
			var go := minf(_move_speed / 2.0, 1.0)
			var s := sin(_stride) * go
			ll = lerpf(-0.3, -s * 0.5, go)
			lr = lerpf(0.22, s * 0.5, go)
			body_y += absf(cos(_stride)) * 0.03 * go
		"slash":
			# Sling cast: cock back, whip overhand (the stone leaves on frame 3, k = 0.5),
			# follow through across the body and settle
			var ax: float
			var az: float
			if k < 0.3:
				var e := ease(k / 0.3, 0.5)
				ax = lerpf(-2.2, -3.4, e)
				az = lerpf(-1.3, -0.45, e)
				twist = lerpf(-0.45, -0.65, e)
				lean = lerpf(-0.13, -0.2, e)
				ll = lerpf(-0.3, -0.12, e)                  # weight rocks onto the back foot
				lr = lerpf(0.22, 0.3, e)
			elif k < 0.55:
				var e := ease((k - 0.3) / 0.25, 2.2)        # accelerating whip
				ax = lerpf(-3.4, -0.9, e)
				az = lerpf(-0.45, -0.1, e)
				twist = lerpf(-0.65, 0.5, e)
				lean = lerpf(-0.2, 0.34, e)
				ll = lerpf(-0.12, -0.5, e)                  # step into the throw
				lr = lerpf(0.3, 0.38, e)
				body_y = -0.04 * e
			else:
				var e := ease((k - 0.55) / 0.45, 0.45)      # settle out of the follow-through
				ax = lerpf(-0.9, -0.35, e)
				az = lerpf(-0.1, 0.3, e)
				twist = lerpf(0.5, 0.12, e)
				lean = lerpf(0.34, 0.08, e)
				ll = lerpf(-0.5, -0.2, e)
				lr = lerpf(0.38, 0.12, e)
				body_y = lerpf(-0.04, 0.0, e)
			ar = Vector3(ax, 0, az)
			al = Vector3(lerpf(-1.3, 0.35, ease(k, 0.7)), 0, lerpf(0.32, 0.4, k))   # off hand pulls back
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
				twist = lerpf(0.0, 0.6, e)
				lean = lerpf(0.0, -0.1, e)
			elif k < 0.5:
				var e := ease((k - 0.25) / 0.25, 2.0)       # accelerating sweep
				ax = lerpf(-1.7, -1.4, e)
				az = lerpf(0.9, -1.0, e)
				twist = lerpf(0.6, -0.55, e)
				lean = lerpf(-0.1, 0.28, e)
				ll = lerpf(0.0, -0.45, e)                   # step into the cut
				body_y = -0.04 * e
			else:
				var e := ease((k - 0.5) / 0.5, 0.45)
				ax = lerpf(-1.4, -0.3, e)
				az = lerpf(-1.0, -0.2, e)
				twist = lerpf(-0.55, 0.0, e)
				lean = lerpf(0.28, 0.05, e)
				ll = lerpf(-0.45, -0.1, e)
				body_y = lerpf(-0.04, 0.0, e)
			ar = Vector3(ax, 0, az)
			al = Vector3(-0.5, 0, 0.35)
			head_ry = -twist * 0.6
		"halfslash":
			var e := ease(k, 0.6)
			ar = Vector3(lerpf(-3.0, -0.5, e), 0, -0.15)
			al = Vector3(lerpf(-0.9, 0.4, e), 0, 0.2)
			lean = lerpf(-0.15, 0.3, e)
		"build":
			# Raise over frames 0-3, slam on 4, recover 5-7
			var keys := [-1.4, -2.3, -2.9, -3.2, -0.5, -0.75, -1.0, -1.2]
			var fi := _t * fps
			var i0 := int(fi) % 8
			var i1 := (i0 + 1) % 8
			var fr := fi - floorf(fi)
			var a: float = lerpf(keys[i0], keys[i1], fr * fr if i0 == 3 else fr)
			ar = Vector3(a, 0, -0.1)
			al = Vector3(-0.8, 0, 0.25)
			lean = 0.34 if i0 >= 4 and i0 <= 5 else (-0.08 if i0 == 3 else 0.12)
			body_y = -0.03 if i0 == 4 else 0.0
			head_rx = 0.15
		"thrust":
			var j := sin(k * PI)
			ar = Vector3(lerpf(-0.6, -1.5, j), 0, -0.1)
			al = Vector3(-0.5, 0, 0.3)
			lean = j * 0.3
			spear_rx = PI * 0.5 * minf(1.0, k * 4.0) * (1.0 if k < 0.85 else (1.0 - k) / 0.15)
			spear_z = j * 0.45
		"cheer":
			# Two hops; arms fly up on the first and wave overhead
			var hop := absf(sin(k * TAU))
			body_y = hop * 0.28
			var up := minf(1.0, k * 6.0)
			var wave := sin(_t * 16.0) * 0.18 * up
			al = Vector3(lerpf(-0.08, -2.7, up) + wave, 0, lerpf(0.14, 0.45, up))
			ar = Vector3(lerpf(-0.08, -2.7, up) - wave, 0, lerpf(-0.14, -0.45, up))
			ll = -hop * 0.35
			lr = -hop * 0.35
			lean = -0.12 * up
			head_rx = -0.2 * up
		"dabke":
			# Levantine line dance: arms up and out as if linked at the shoulders, a side
			# shuffle, then a kick and a stomp on the last beat
			var beat := fmod(_t * fps, n) / n
			twist = sin(ph) * 0.15
			al = Vector3(-1.25, 0, 0.95)
			ar = Vector3(-1.25, 0, -0.95)
			ll = sin(ph) * 0.2
			lr = -sin(ph) * 0.2
			if beat >= 0.5 and beat < 0.8:
				ll = -0.75 * sin((beat - 0.5) / 0.3 * PI)   # the kick
			elif beat >= 0.8:
				body_y = -0.05 * sin((beat - 0.8) / 0.2 * PI)   # the stomp
			body_y += absf(sin(ph * 2.0)) * 0.04
			head_rx = 0.06
		"clap":
			# Side step and clap in front of the chest, twice a cycle
			var c := absf(sin(ph * 2.0))
			al = Vector3(-1.45, 0, lerpf(0.65, -0.12, c))
			ar = Vector3(-1.45, 0, lerpf(-0.65, 0.12, c))
			ll = sin(ph) * 0.35
			lr = -sin(ph) * 0.35
			body_y = absf(sin(ph)) * 0.08
			head_ry = sin(ph) * 0.22
			lean = 0.05
		"sway":
			# Both arms up in a V, waving, the body swaying side to side
			var s := sin(ph)
			al = Vector3(-2.45 + s * 0.22, 0, 0.6)
			ar = Vector3(-2.45 - s * 0.22, 0, -0.6)
			twist = s * 0.45
			body_y = absf(sin(ph * 2.0)) * 0.05
			ll = -maxf(0.0, s) * 0.3
			lr = -maxf(0.0, -s) * 0.3
			head_rx = -0.15
		"collapse":
			var c := ease(k, 2.2)
			body_rx = -1.45 * c
			body_y = 0.0
			al = Vector3(-0.3, 0, 0.14 + c * 1.2)
			ar = Vector3(-0.3, 0, -0.14 - c * 1.2)
			head_rx = -0.3 * c
	# Loads override the arms
	if _base in ["idle", "walk", "run"]:
		match hold:
			"overhead":
				var sway := sin(ph) * 0.06 if _base != "idle" else 0.0
				al = Vector3(-2.95 + sway, 0, 0.3)
				ar = Vector3(-2.95 - sway, 0, -0.3)
			"beam":
				al = Vector3(-1.35, 0, 0.1)
				ar = Vector3(-1.35, 0, -0.1)
			"front":
				# Hugging the load to the chest, elbows out
				var bob := sin(ph) * 0.05 if _base != "idle" else 0.0
				al = Vector3(-0.95 + bob, 0, -0.45)
				ar = Vector3(-0.95 - bob, 0, 0.45)
	if _spear != null and _base in ["idle", "walk"]:
		ar = Vector3(-0.45, 0, -0.3)   # hand on the shaft
	# In the swing the hammer head leads forward off the hand
	_tool_visible()
	if _tool != null:
		_tool.rotation.x = -1.35
	if _sword != null:
		_sword.rotation.x = -1.45   # blade out ahead of the fist
	# Ease out of the previous animation's pose instead of snapping to the new one
	if _blend < 1.0 and not _blend_from.is_empty():
		var w := smoothstep(0.0, 1.0, _blend)
		var f := _blend_from
		body_y = lerpf(f.body_y, body_y, w)
		lean = lerpf(f.lean, lean, w)
		twist = lerp_angle(f.twist, twist, w)
		head_rx = lerpf(f.head.x, head_rx, w)
		head_ry = lerp_angle(f.head.y, head_ry, w)
		al = f.al.lerp(al, w)
		ar = f.ar.lerp(ar, w)
		ll = lerpf(f.ll, ll, w)
		lr = lerpf(f.lr, lr, w)
	_body.position.y = body_y
	_body.rotation.x = body_rx
	_body.scale = Vector3(_squash.x, _squash.y, _squash.x)
	_torso.rotation.x = lean
	_torso.rotation.y = twist
	_head.rotation.x = head_rx
	_head.rotation.y = head_ry
	_arm_l.rotation = al
	_arm_r.rotation = ar
	_leg_l.rotation.x = ll
	_leg_r.rotation.x = lr
	if _spear != null:
		_spear.rotation.x = spear_rx
		_spear.position.z = 0.12 + spear_z
	if _cape != null:
		_cape.rotation.x = -0.1 - lean * 0.5 - absf(sin(ph)) * (0.25 if _base == "walk" or _base == "run" else 0.0)

func _tool_visible() -> void:
	if _tool != null:
		_tool.visible = _base == "build"
	if _belt_tool != null:
		_belt_tool.visible = _base != "build"
	if _sword != null:
		_sword.visible = _base == "sword"
	if _belt_sword != null:
		_belt_sword.visible = _base != "sword"

## Chest-front point a carried load hangs from (follows the body's turn and bob)
func carry_anchor() -> Node3D:
	return _carry_anchor

## World position of the throwing (right) hand, where the sling cord is held
func hand_position() -> Vector3:
	return _hand_r.global_position if _hand_r != null else global_position + Vector3.UP * 1.7

func _pose_snapshot() -> Dictionary:
	return {
		"body_y": _body.position.y, "lean": _torso.rotation.x, "twist": _torso.rotation.y,
		"head": _head.rotation, "al": _arm_l.rotation, "ar": _arm_r.rotation,
		"ll": _leg_l.rotation.x, "lr": _leg_r.rotation.x,
	}

func _set_flash(v: float) -> void:
	for p in _parts:
		p.set_instance_shader_parameter("flash", v)

# ── Building the figure ────────────────────────────────────

func _build(look: Dictionary) -> void:
	_look = look
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
	if look.has("vest"):
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
	if look.get("strap", false):
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
	if look.has("armour"):
		_part(_torso, _soft(Vector3(0.63, 0.4, 0.45), 0.06), look["armour"], Vector3(0, 0.4, 0))
		_part(_torso, _soft(Vector3(0.645, 0.05, 0.465), 0.015), look["armour"].darkened(0.25), Vector3(0, 0.3, 0))
	if look.has("cape"):
		_cape = _pivot(_torso, Vector3(0, SHOULDER_Y - HIP_Y + 0.02, -0.2))
		_part(_cape, _soft(Vector3(0.58, 0.8, 0.06), 0.02), look["cape"], Vector3(0, -0.39, -0.04))
	# Basket on the back, riding above the shoulders: wicker bands, a rim, stones heaped in it
	if look.get("basket", false):
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
	_carry_anchor = _pivot(_torso, Vector3(0, 0.4, 0.42))

	# ── Arms: short sleeve, bare forearm, rounded hand; pivot at the shoulder
	_arm_l = _pivot(_torso, Vector3(ARM_X, SHOULDER_Y - HIP_Y, 0))
	_arm_r = _pivot(_torso, Vector3(-ARM_X, SHOULDER_Y - HIP_Y, 0))
	var hands: Array[Node3D] = []
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
	_hand_r = hands[1]

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
	if look.has("shield"):
		var sh := _pivot(_torso, Vector3(ARM_X + 0.1, 0.42, 0.2))
		sh.rotation.y = 0.35
		_part(sh, _soft(Vector3(0.56, 0.76, 0.08), 0.03), look["shield"], Vector3.ZERO)
		_part(sh, _soft(Vector3(0.15, 0.15, 0.1), 0.03), Color(0.74, 0.54, 0.26), Vector3(0, 0, 0.04))
	# Worker's hammer: a squared stone head on a stout handle
	if look.get("tool", false):
		_tool = _pivot(hands[1], Vector3(0, -0.02, 0.02))
		_part(_tool, _soft(Vector3(0.07, 0.56, 0.07), 0.018), Color(0.50, 0.34, 0.20), Vector3(0, -0.24, 0))
		_part(_tool, _soft(Vector3(0.09, 0.08, 0.09), 0.02), LEATHER, Vector3(0, -0.06, 0))
		_part(_tool, _bbox(Vector3(0.36, 0.22, 0.22), 0.05), Color(0.58, 0.57, 0.58), Vector3(0, -0.54, 0))
		if look.get("tool_always", false):
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
		_belt_sword = _pivot(_torso, Vector3(ARM_X - 0.02, 0.1, 0.06))
		_belt_sword.rotation = Vector3(0.95, 0, 0.1)
		_part(_belt_sword, _soft(Vector3(0.13, 0.5, 0.08), 0.03), LEATHER.darkened(0.2), Vector3(0, -0.22, 0))
		_part(_belt_sword, _soft(Vector3(0.08, 0.15, 0.08), 0.02), LEATHER, Vector3(0, 0.13, 0))
		_part(_belt_sword, _soft(Vector3(0.24, 0.06, 0.1), 0.02), brass, Vector3(0, 0.04, 0))
		_tool_visible()

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

static func _ellipsoid(size: Vector3) -> Mesh:
	return _cached("oval%s" % size, func():
		var source := SphereMesh.new()
		source.radius = 0.5
		source.height = 1.0
		source.radial_segments = 16
		source.rings = 8
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
