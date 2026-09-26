class_name CharacterRig
extends Node3D

# Low-poly chibi figure built from primitive meshes, animated in code.
# Stands in for the old AnimatedSprite3D: same API (play / animation / frame /
# speed_scale / frame_changed / animation_finished / hit_flash / hitstop / squash),
# so Player and Enemy drive it exactly like the old sprite sheets. Animation names keep the
# "<anim>_<dir>" form; the rig keeps a virtual frame clock (CharAnim.ANIM_CFG timing)
# so gameplay beats — sling release, build strike, footsteps — land on the same frames.
#
# Proportions: big head (~40% of height), stubby robe body, short legs — reads at
# gameplay zoom. The player colour is the robe; the head-wrap is what the iso camera
# sees most, so it stays light and bright.

const PART_SHADER    := preload("res://assets/shaders/toon_part.gdshader")
const OUTLINE_SHADER := preload("res://assets/shaders/toon_outline.gdshader")
const MARKER_SHADER  := preload("res://assets/shaders/ground_marker.gdshader")
const FLASH_TIME   := 0.16
const SQUASH_TIME  := 0.28
const STEP_FRAMES  := [1, 5]   # footfalls in the 8-frame walk / run cycles
const STRIKE_FRAME := 4        # downstroke of the build loop
const TURN_RATE    := 16.0     # rad/s-ish smoothing toward the facing direction
const BASE_SCALE   := 1.3
# Building: turn a three-quarter view toward the camera so the mallet arm isn't
# hidden behind the body when the wall is "up" screen (the usual case)
const BUILD_TURN   := -0.65

# Rig dimensions (metres, before scale). Feet at y = 0.
const HIP_Y      := 0.34
const SHOULDER_Y := 0.92
const NECK_Y     := 1.0
const HEAD_R     := 0.34
const ARM_X      := 0.25

# Screen directions of the "<anim>_<dir>" suffixes (iso camera looks down -x -z)
const DIR_VEC := {
	"down":  Vector3(0.70710678, 0, 0.70710678),
	"up":    Vector3(-0.70710678, 0, -0.70710678),
	"right": Vector3(0.70710678, 0, -0.70710678),
	"left":  Vector3(-0.70710678, 0, 0.70710678),
}

const OUTLINE_PLAYER := Color(0.17, 0.11, 0.07)
const SKIN := [Color(0.86, 0.58, 0.38), Color(0.90, 0.66, 0.46), Color(0.72, 0.48, 0.31), Color(0.64, 0.42, 0.27)]
const HAIR_DARK := Color(0.30, 0.18, 0.11)
const HAIR_GREY := Color(0.72, 0.70, 0.66)
const LINEN     := Color(0.89, 0.83, 0.70)
const LEATHER   := Color(0.46, 0.30, 0.18)
const BAND      := Color(0.24, 0.16, 0.11)

signal footstep
signal strike            # tool meets stone in the "build" loop
signal frame_changed
signal animation_finished

var animation := ""
var frame := 0
var speed_scale := 1.0
## What the hands hold: "" (free), "overhead" (a load on the head), "beam" (arms forward)
var hold := ""

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

static var _meshes: Dictionary = {}
static var _part_mat: ShaderMaterial
static var _outlines: Dictionary = {}

# ── Looks ──────────────────────────────────────────────────

## A worker: undyed linen tunic, head-band and belt dyed in the player's colour, basket
## on the back; face varies per slot so the crew reads as four people, not one figure
## in four colours.
static func worker_look(slot: int, color: Color) -> Dictionary:
	var faces := [
		{"beard": "full",  "hair": HAIR_DARK},
		{"beard": "short", "hair": HAIR_DARK},
		{"beard": "long",  "hair": HAIR_DARK},
		{"beard": "full",  "hair": HAIR_GREY},
	]
	var f: Dictionary = faces[slot % faces.size()]
	# Dye, not paint: pull the UI colour a little toward undyed wool
	var dye := color.lerp(Color(0.55, 0.44, 0.33), 0.12)
	return {
		"skin": SKIN[slot % SKIN.size()], "robe": LINEN, "trim": dye.darkened(0.15),
		"sash": dye.darkened(0.2), "hat": "band", "hat_color": dye, "band": BAND,
		"beard": f["beard"], "hair": f["hair"], "outline": OUTLINE_PLAYER,
		"strap": true, "basket": true, "tool": true,
	}

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
	_update_facing(delta)
	_apply_pose()

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
		if _has_last:
			var step := pos - _last_pos
			step.y = 0.0
			if step.length() > 0.02 * delta * 60.0 and step.normalized().dot(target) > 0.3:
				target = step.normalized()
		_last_pos = pos
		_has_last = true
	var want := atan2(target.x, target.z)
	if _base == "build":
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
	var head_rx := 0.0
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
			var w := sin(_t * 10.0)
			ar = Vector3(-0.3, 0, -2.5 + w * 0.12)
			al = Vector3(-1.2, 0, 0.2)
			lean = -0.1
		"slash", "halfslash":
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
	if _spear != null and _base in ["idle", "walk"]:
		ar = Vector3(-0.45, 0, -0.3)   # hand on the shaft
	_body.position.y = body_y
	_body.rotation.x = body_rx
	_body.scale = Vector3(_squash.x, _squash.y, _squash.x)
	_torso.rotation.x = lean
	_head.rotation.x = head_rx
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
	_outline_mat = _outlines[oc]

	var skin: Color = look["skin"]
	var robe: Color = look["robe"]
	var trim: Color = look["trim"]
	var hair: Color = look["hair"]

	_body = _pivot(self, Vector3.ZERO)
	# Legs: bare shins, chunky sandals with a strap
	_leg_l = _pivot(_body, Vector3(0.12, HIP_Y, 0))
	_leg_r = _pivot(_body, Vector3(-0.12, HIP_Y, 0))
	for leg in [_leg_l, _leg_r]:
		_part(leg, _bbox(Vector3(0.15, 0.32, 0.15), 0.04), skin, Vector3(0, -0.15, 0))
		_part(leg, _bbox(Vector3(0.18, 0.08, 0.27), 0.03), LEATHER.darkened(0.15), Vector3(0, -0.3, 0.04))
		_part(leg, _bbox(Vector3(0.165, 0.05, 0.08), 0.015), LEATHER, Vector3(0, -0.22, 0.06))

	_torso = _pivot(_body, Vector3(0, HIP_Y, 0))
	# Tunic: boxy chest over a flared skirt, hem band, belt; leather strap across the chest
	_part(_torso, _bbox(Vector3(0.54, 0.5, 0.38), 0.08), robe, Vector3(0, 0.35, 0))
	_part(_torso, _bbox(Vector3(0.62, 0.34, 0.44), 0.07), robe, Vector3(0, 0.02, 0))
	_part(_torso, _bbox(Vector3(0.64, 0.07, 0.46), 0.025), trim, Vector3(0, -0.13, 0))
	_part(_torso, _bbox(Vector3(0.59, 0.11, 0.42), 0.03), look["sash"], Vector3(0, 0.17, 0))
	if look.get("strap", false):
		_part(_torso, _bbox(Vector3(0.08, 0.62, 0.4), 0.02), LEATHER, Vector3(0, 0.4, 0), Vector3(0, 0, 0.62))
	if look.has("armour"):
		_part(_torso, _bbox(Vector3(0.54, 0.4, 0.4), 0.06), look["armour"], Vector3(0, 0.38, 0))
	if look.has("cape"):
		_cape = _pivot(_torso, Vector3(0, SHOULDER_Y - HIP_Y + 0.02, -0.17))
		_part(_cape, _bbox(Vector3(0.52, 0.78, 0.06), 0.02), look["cape"], Vector3(0, -0.38, -0.04))
	# Basket on the back: wicker, a darker rim, straps over the shoulders
	if look.get("basket", false):
		var wicker := Color(0.72, 0.52, 0.28)
		_part(_torso, _bbox(Vector3(0.44, 0.44, 0.26), 0.06), wicker, Vector3(0, 0.4, -0.3))
		_part(_torso, _bbox(Vector3(0.48, 0.07, 0.3), 0.025), wicker.darkened(0.25), Vector3(0, 0.63, -0.3))
		_part(_torso, _bbox(Vector3(0.46, 0.04, 0.28), 0.01), wicker.darkened(0.12), Vector3(0, 0.44, -0.3))
		for sx: float in [-1.0, 1.0]:
			_part(_torso, _bbox(Vector3(0.07, 0.07, 0.42), 0.02), LEATHER, Vector3(0.14 * sx, 0.6, -0.03))

	# Arms: short sleeve, bare forearm, blocky hand; pivot at the shoulder
	_arm_l = _pivot(_torso, Vector3(ARM_X + 0.03, SHOULDER_Y - HIP_Y, 0))
	_arm_r = _pivot(_torso, Vector3(-ARM_X - 0.03, SHOULDER_Y - HIP_Y, 0))
	var hands: Array[Node3D] = []
	var forearm: Color = skin if look.get("bare_arms", true) else robe
	for arm in [_arm_l, _arm_r]:
		_part(arm, _bbox(Vector3(0.19, 0.2, 0.19), 0.05), robe, Vector3(0, -0.06, 0))
		_part(arm, _bbox(Vector3(0.14, 0.26, 0.14), 0.04), forearm, Vector3(0, -0.24, 0))
		var hand := _pivot(arm, Vector3(0, -0.4, 0))
		_part(hand, _bbox(Vector3(0.16, 0.15, 0.16), 0.05), skin, Vector3.ZERO)
		hands.append(hand)

	# Head: a big rounded block — the camera's main read
	_head = _pivot(_torso, Vector3(0, NECK_Y - HIP_Y, 0))
	var hc := Vector3(0, HEAD_R * 0.85, 0.01)
	var hw := 0.62   # head width / height / depth
	var hh := 0.58
	var hd := 0.56
	var front := hc.z + hd * 0.5
	_part(_head, _bbox(Vector3(hw, hh, hd), 0.13), skin, hc)
	# Hair: crown and back of the head
	_part(_head, _bbox(Vector3(hw + 0.03, 0.12, hd + 0.02), 0.05), hair, hc + Vector3(0, hh * 0.5 - 0.01, -0.02))
	# Tousled tufts on the crown so it doesn't read as a lid
	if look.get("hat", "band") == "band":
		for t: Array in [[Vector3(-0.12, 0.07, 0.08), 0.3], [Vector3(0.1, 0.08, -0.04), -0.25], [Vector3(-0.02, 0.1, -0.14), 0.6]]:
			var tuft := _part(_head, _bbox(Vector3(0.26, 0.12, 0.24), 0.05), hair.lightened(0.05),
				hc + Vector3(0, hh * 0.5, 0) + t[0], Vector3(0.12, t[1], 0.1))
			tuft.rotation.z = -t[1] * 0.3
	_part(_head, _bbox(Vector3(hw + 0.04, hh * 0.72, 0.16), 0.05), hair, hc + Vector3(0, 0.06, -hd * 0.5 + 0.05))
	# Face: eyes, brows, nose
	for sx: float in [-1.0, 1.0]:
		_part(_head, _bbox(Vector3(0.065, 0.085, 0.04), 0.012), Color(0.10, 0.07, 0.05), hc + Vector3(0.12 * sx, 0.03, front))
		var brow := _part(_head, _bbox(Vector3(0.15, 0.05, 0.05), 0.015), hair, hc + Vector3(0.12 * sx, 0.105, front + 0.005))
		brow.rotation.z = (-0.35 if look.get("brows", false) else -0.08) * sx
	_part(_head, _bbox(Vector3(0.09, 0.09, 0.07), 0.03), skin.darkened(0.08), hc + Vector3(0, -0.04, front + 0.015))
	# Beard: a block round the jaw, sideburns up to the hair, moustache over the lip
	var bl: String = look.get("beard", "")
	if not bl.is_empty():
		var bh: float = {"full": 0.26, "long": 0.36, "short": 0.18}.get(bl, 0.22)
		var bw: float = hw + (0.05 if bl != "short" else 0.02)
		_part(_head, _bbox(Vector3(bw, bh, 0.24), 0.07), hair, hc + Vector3(0, -0.09 - bh * 0.5, front - 0.07))
		for sx: float in [-1.0, 1.0]:
			_part(_head, _bbox(Vector3(0.08, 0.26, 0.26), 0.03), hair, hc + Vector3((hw * 0.5 + 0.005) * sx, -0.06, 0.1))
		_part(_head, _bbox(Vector3(0.3, 0.07, 0.06), 0.02), hair, hc + Vector3(0, -0.11, front + 0.01))

	var hat: Color = look.get("hat_color", LINEN)
	match look.get("hat", "band"):
		"band":
			# Cloth band tied round the head, two tails flying behind the knot
			_part(_head, _bbox(Vector3(hw + 0.07, 0.13, hd + 0.07), 0.035), hat, hc + Vector3(0, hh * 0.5 - 0.09, 0))
			_part(_head, _bbox(Vector3(0.12, 0.12, 0.08), 0.03), hat.darkened(0.1), hc + Vector3(0.08, hh * 0.5 - 0.09, -hd * 0.5 - 0.06))
			for t: Array in [[0.09, 0.35], [-0.02, -0.25]]:
				_part(_head, _bbox(Vector3(0.1, 0.25, 0.04), 0.012), hat.darkened(0.06),
					hc + Vector3(0.08 + t[0], hh * 0.5 - 0.24, -hd * 0.5 - 0.1), Vector3(0.45, 0, t[1]))
		"wrap":
			# Head-cloth over the crown, cord band, cloth falling behind
			_part(_head, _bbox(Vector3(hw + 0.08, 0.24, hd + 0.08), 0.08), hat, hc + Vector3(0, hh * 0.5 - 0.02, -0.01))
			_part(_head, _bbox(Vector3(hw + 0.1, 0.07, hd + 0.1), 0.02), look["band"], hc + Vector3(0, hh * 0.5 - 0.12, -0.01))
			_part(_head, _bbox(Vector3(hw + 0.06, 0.5, 0.1), 0.03), hat, hc + Vector3(0, -0.12, -hd * 0.5 - 0.02), Vector3(0.12, 0, 0))
		"hood":
			_part(_head, _bbox(Vector3(hw + 0.12, hh * 0.55, hd + 0.1), 0.1), hat, hc + Vector3(0, hh * 0.3, -0.04))
			for sx: float in [-1.0, 1.0]:
				_part(_head, _bbox(Vector3(0.08, hh * 0.8, hd * 0.9), 0.03), hat, hc + Vector3((hw * 0.5 + 0.05) * sx, -0.05, -0.05))
			_part(_head, _bbox(Vector3(hw + 0.1, 0.55, 0.12), 0.04), hat, hc + Vector3(0, -0.2, -hd * 0.5 - 0.02), Vector3(0.12, 0, 0))
		"helmet":
			_part(_head, _cyl(0.0, hw * 0.62, 0.42), hat, hc + Vector3(0, hh * 0.5 + 0.18, -0.02))
			_part(_head, _bbox(Vector3(hw + 0.1, 0.09, hd + 0.1), 0.03), hat.darkened(0.25), hc + Vector3(0, hh * 0.5 - 0.04, -0.01))

	# Weapons
	match look.get("weapon", ""):
		"spear":
			_spear = _pivot(_torso, Vector3(-ARM_X - 0.12, 0.28, 0.12))
			_part(_spear, _bbox(Vector3(0.06, 2.2, 0.06), 0.015), Color(0.42, 0.28, 0.16), Vector3(0, 0.55, 0))
			_part(_spear, _cyl(0.0, 0.07, 0.26), Color(0.62, 0.60, 0.56), Vector3(0, 1.78, 0))
		"dagger":
			var d := _pivot(hands[1], Vector3(0, -0.05, 0.05))
			_part(d, _bbox(Vector3(0.06, 0.34, 0.03), 0.01), Color(0.72, 0.70, 0.66), Vector3(0, -0.2, 0))
			_part(d, _bbox(Vector3(0.17, 0.05, 0.06), 0.015), Color(0.55, 0.42, 0.22), Vector3(0, -0.02, 0))
	if look.has("shield"):
		var sh := _pivot(_torso, Vector3(ARM_X + 0.14, 0.42, 0.2))
		sh.rotation.y = 0.35
		_part(sh, _bbox(Vector3(0.54, 0.74, 0.08), 0.03), look["shield"], Vector3.ZERO)
		_part(sh, _bbox(Vector3(0.15, 0.15, 0.1), 0.03), Color(0.74, 0.54, 0.26), Vector3(0, 0, 0.04))
	# Worker's mallet — shown only while building
	if look.get("tool", false):
		_tool = _pivot(hands[1], Vector3(0, -0.04, 0.02))
		_part(_tool, _bbox(Vector3(0.06, 0.58, 0.06), 0.015), Color(0.50, 0.34, 0.20), Vector3(0, -0.24, 0))
		_part(_tool, _bbox(Vector3(0.4, 0.24, 0.24), 0.05), Color(0.60, 0.58, 0.55), Vector3(0, -0.54, 0))
		_tool_visible()

func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n

func _part(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _part_mat
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

static func _bbox(size: Vector3, bevel: float) -> Mesh:
	return _cached("bb%s%.3f" % [size, bevel], func(): return Chunky.bevel_box(size, bevel))

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
