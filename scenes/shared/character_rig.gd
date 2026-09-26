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
const ROUNDING     := 3.5      # corner radius as a multiple of each part's authored bevel
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
		"outline": OUTLINE_PLAYER, "no_outline": true, "tool": true, "hat": "band", "hat_color": dye,
	}
	match slot % 4:
		0:
			look.merge({"skin": SKIN[0], "hair": HAIR_DARK, "beard": "full", "hair_style": "short",
				"strap": true, "basket": true, "basket_stones": true, "trim": dye.darkened(0.1)}, true)
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
	# Workers go without: clean shapes read softer; enemies keep the oxblood rim as a threat cue
	_outline_mat = null if look.get("no_outline", false) else _outlines[oc]

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
		_part(leg, _bbox(Vector3(0.19, 0.08, 0.28), 0.03), SANDAL, Vector3(0, -0.3, 0.04))
		_part(leg, _bbox(Vector3(0.165, 0.05, 0.08), 0.015), LEATHER, Vector3(0, -0.22, 0.06))

	_torso = _pivot(_body, Vector3(0, HIP_Y, 0))
	# Tunic: boxy chest over a flared skirt, hem band, belt
	var long_robe: bool = look.get("long_robe", false)
	_part(_torso, _bbox(Vector3(0.54, 0.5, 0.38), 0.08), robe, Vector3(0, 0.35, 0))
	if long_robe:
		_part(_torso, _bbox(Vector3(0.62, 0.5, 0.44), 0.08), robe, Vector3(0, -0.06, 0))
		_part(_torso, _bbox(Vector3(0.625, 0.07, 0.445), 0.06), trim, Vector3(0, -0.28, 0))
	else:
		_part(_torso, _bbox(Vector3(0.62, 0.34, 0.44), 0.07), robe, Vector3(0, 0.02, 0))
		_part(_torso, _bbox(Vector3(0.625, 0.08, 0.445), 0.06), trim, Vector3(0, -0.12, 0))
	_part(_torso, _bbox(Vector3(0.59, 0.11, 0.42), 0.03), look["sash"], Vector3(0, 0.17, 0))
	# Sash ends hanging at the hip
	if look.get("sash_tails", false):
		_part(_torso, _bbox(Vector3(0.09, 0.3, 0.04), 0.015), look["sash"], Vector3(-0.16, 0.02, 0.22), Vector3(0, 0, 0.12))
	# Buckle / knot at the front of the belt
	_part(_torso, _bbox(Vector3(0.12, 0.1, 0.05), 0.02), look["sash"].darkened(0.25), Vector3(0.1, 0.17, 0.21))
	if look.has("vest"):
		# Open vest: coloured over the chest with the linen showing down the front
		var v: Color = look["vest"]
		_part(_torso, _bbox(Vector3(0.58, 0.44, 0.41), 0.07), v, Vector3(0, 0.36, 0))
		_part(_torso, _bbox(Vector3(0.16, 0.44, 0.02), 0.01), robe, Vector3(0, 0.36, 0.205))
		_part(_torso, _bbox(Vector3(0.6, 0.05, 0.43), 0.015), v.darkened(0.3), Vector3(0, 0.14, 0))
	if look.has("apron"):
		var a: Color = look["apron"]
		_part(_torso, _bbox(Vector3(0.44, 0.56, 0.04), 0.015), a, Vector3(0, 0.12, 0.225))
		_part(_torso, _bbox(Vector3(0.2, 0.12, 0.03), 0.01), a.darkened(0.2), Vector3(0.08, 0.02, 0.25))
		# Tool handles poking out of the pocket
		_part(_torso, _bbox(Vector3(0.04, 0.16, 0.04), 0.01), WOOD_LIGHT, Vector3(0.04, 0.1, 0.26), Vector3(0, 0, 0.2))
		_part(_torso, _bbox(Vector3(0.04, 0.14, 0.04), 0.01), Color(0.55, 0.55, 0.55), Vector3(0.13, 0.1, 0.26), Vector3(0, 0, -0.2))
	if look.get("strap", false):
		_part(_torso, _bbox(Vector3(0.08, 0.62, 0.4), 0.02), LEATHER, Vector3(0, 0.4, 0), Vector3(0, 0, 0.62))
	if look.has("satchel"):
		# Bag on the hip, strap across the other way
		var sc: Color = look["satchel"]
		_part(_torso, _bbox(Vector3(0.08, 0.62, 0.4), 0.02), sc.darkened(0.1), Vector3(0, 0.4, 0), Vector3(0, 0, -0.62))
		_part(_torso, _bbox(Vector3(0.14, 0.24, 0.24), 0.05), sc, Vector3(-0.35, 0.06, 0.04))
		_part(_torso, _bbox(Vector3(0.15, 0.1, 0.25), 0.03), sc.darkened(0.2), Vector3(-0.355, 0.15, 0.04))
	if look.has("scroll"):
		var sc2 := _pivot(_torso, Vector3(0.33, 0.15, 0.08))
		sc2.rotation = Vector3(0.2, 0, 0.35)
		_part(sc2, _cyl(0.06, 0.06, 0.36), look["scroll"], Vector3.ZERO)
		_part(sc2, _cyl(0.065, 0.065, 0.05), BAND, Vector3.ZERO)
	if look.has("armour"):
		_part(_torso, _bbox(Vector3(0.54, 0.4, 0.4), 0.06), look["armour"], Vector3(0, 0.38, 0))
	if look.has("cape"):
		_cape = _pivot(_torso, Vector3(0, SHOULDER_Y - HIP_Y + 0.02, -0.17))
		_part(_cape, _bbox(Vector3(0.52, 0.78, 0.06), 0.02), look["cape"], Vector3(0, -0.38, -0.04))
	# Basket on the back: wicker bands, a darker rim, straps over the shoulders
	if look.get("basket", false):
		var wicker := Color(0.74, 0.54, 0.28)
		_part(_torso, _bbox(Vector3(0.46, 0.46, 0.28), 0.07), wicker, Vector3(0, 0.4, -0.31))
		for y: float in [0.28, 0.4, 0.52]:
			_part(_torso, _bbox(Vector3(0.475, 0.035, 0.29), 0.01), wicker.darkened(0.14), Vector3(0, y, -0.31))
		_part(_torso, _bbox(Vector3(0.5, 0.07, 0.32), 0.025), wicker.darkened(0.3), Vector3(0, 0.64, -0.31))
		if look.get("basket_stones", false):
			for st: Array in [[Vector3(-0.1, 0.69, -0.3), 0.3], [Vector3(0.1, 0.7, -0.34), -0.4], [Vector3(0.0, 0.73, -0.26), 0.9]]:
				_part(_torso, _bbox(Vector3(0.17, 0.14, 0.15), 0.04), Palette.WALL_STONE.darkened(0.12), st[0], Vector3(0.2, st[1], 0.1))
		for sx: float in [-1.0, 1.0]:
			_part(_torso, _bbox(Vector3(0.07, 0.07, 0.42), 0.02), LEATHER, Vector3(0.14 * sx, 0.6, -0.03))
	# Planks bundled on the back, tied with a rope
	if look.get("planks", false):
		for pk: Array in [[-0.12, 0.08, 0.0], [0.02, -0.05, 0.03], [0.14, 0.12, -0.02]]:
			_part(_torso, _bbox(Vector3(0.13, 0.95, 0.05), 0.015), WOOD_LIGHT.darkened(0.06 + pk[2]),
				Vector3(pk[0], 0.48 + pk[1] * 0.3, -0.24 - absf(pk[2])), Vector3(0.12, 0, pk[1]))
		_part(_torso, _bbox(Vector3(0.44, 0.05, 0.1), 0.015), BAND.lightened(0.2), Vector3(0.01, 0.45, -0.24))
		for sx: float in [-1.0, 1.0]:
			_part(_torso, _bbox(Vector3(0.06, 0.06, 0.42), 0.02), LEATHER, Vector3(0.13 * sx, 0.6, -0.03))

	# Arms: short sleeve, bare forearm, blocky hand; pivot at the shoulder
	_arm_l = _pivot(_torso, Vector3(ARM_X + 0.03, SHOULDER_Y - HIP_Y, 0))
	_arm_r = _pivot(_torso, Vector3(-ARM_X - 0.03, SHOULDER_Y - HIP_Y, 0))
	var hands: Array[Node3D] = []
	var sleeve: Color = look.get("vest", robe) if look.has("vest") and not long_robe else robe
	var forearm: Color = skin if look.get("bare_arms", true) else robe
	for arm in [_arm_l, _arm_r]:
		_part(arm, _bbox(Vector3(0.19, 0.2, 0.19), 0.05), sleeve, Vector3(0, -0.06, 0))
		_part(arm, _bbox(Vector3(0.14, 0.26, 0.14), 0.04), forearm, Vector3(0, -0.24, 0))
		if look.get("bracers", false):
			_part(arm, _bbox(Vector3(0.155, 0.09, 0.155), 0.02), LEATHER, Vector3(0, -0.3, 0))
		var hand := _pivot(arm, Vector3(0, -0.4, 0))
		_part(hand, _bbox(Vector3(0.16, 0.15, 0.16), 0.05), skin, Vector3.ZERO)
		hands.append(hand)

	# Head: a big rounded block — the camera's main read
	_head = _pivot(_torso, Vector3(0, NECK_Y - HIP_Y, 0))
	var hc := Vector3(0, HEAD_R * 0.78, 0.01)
	var hw := 0.66   # head width / height / depth — a soft, nearly round block
	var hh := 0.58
	var hd := 0.58
	var front := hc.z + hd * 0.5
	_part(_head, _bbox(Vector3(hw, hh, hd), 0.12), skin, hc)
	# Ears
	for sx: float in [-1.0, 1.0]:
		_part(_head, _bbox(Vector3(0.06, 0.12, 0.1), 0.02), skin.darkened(0.06), hc + Vector3((hw * 0.5 + 0.01) * sx, 0.0, 0.02))
	var hat: String = look.get("hat", "band")
	_hair(look.get("hair_style", "short"), hair, hc, hw, hh, hd, hat)
	# Face: eyes with a catch-light, brows, nose
	for sx: float in [-1.0, 1.0]:
		# White of the eye, a big dark iris looking slightly inward, a catch-light
		_part(_head, _bbox(Vector3(0.115, 0.13, 0.04), 0.02), Color(0.97, 0.94, 0.88), hc + Vector3(0.13 * sx, 0.03, front + 0.0))
		_part(_head, _bbox(Vector3(0.078, 0.105, 0.04), 0.018), Color(0.12, 0.07, 0.04), hc + Vector3(0.13 * sx - 0.012 * sx, 0.025, front + 0.018))
		_part(_head, _bbox(Vector3(0.03, 0.03, 0.02), 0.006), Color(1, 0.97, 0.9), hc + Vector3(0.13 * sx + 0.005, 0.05, front + 0.04))
		var brow := _part(_head, _bbox(Vector3(0.17, 0.06, 0.06), 0.02), look.get("brow", hair),
			hc + Vector3(0.13 * sx, 0.125, front + 0.02))
		# Inner ends low: determined on the crew, scowling on enemies
		brow.rotation.z = (0.42 if look.get("brows", false) else 0.14) * sx
	_part(_head, _bbox(Vector3(0.12, 0.13, 0.1), 0.045), skin.darkened(0.06), hc + Vector3(0, -0.05, front + 0.025))
	# Beard: a block round the jaw, sideburns up to the hair, moustache over the lip
	var bl: String = look.get("beard", "")
	var bc: Color = look.get("beard_color", hair)
	if not bl.is_empty():
		var bh: float = {"full": 0.22, "long": 0.3, "short": 0.15}.get(bl, 0.2)
		var bw: float = hw + (0.05 if bl != "short" else 0.02)
		_part(_head, _bbox(Vector3(bw, bh + 0.06, 0.3), 0.1), bc, hc + Vector3(0, -0.1 - bh * 0.5, front - 0.1))
		# Cheeks: the beard climbs the jaw in two soft lobes
		for sx: float in [-1.0, 1.0]:
			_part(_head, _bbox(Vector3(0.2, 0.22, 0.22), 0.09), bc, hc + Vector3(0.22 * sx, -0.1, front - 0.1))
		if bl == "long":
			# Tapering to a point below the chin
			_part(_head, _bbox(Vector3(bw * 0.6, 0.16, 0.2), 0.06), bc, hc + Vector3(0, -0.09 - bh - 0.04, front - 0.1))
		elif bl == "full":
			_part(_head, _bbox(Vector3(bw * 0.8, 0.1, 0.2), 0.04), bc.darkened(0.05), hc + Vector3(0, -0.09 - bh + 0.01, front - 0.05))
		for sx: float in [-1.0, 1.0]:
			_part(_head, _bbox(Vector3(0.08, 0.26, 0.26), 0.03), bc, hc + Vector3((hw * 0.5 + 0.005) * sx, -0.06, 0.1))
		# Moustache in two curled halves
		for sx: float in [-1.0, 1.0]:
			var m := _part(_head, _bbox(Vector3(0.17, 0.075, 0.08), 0.035), bc.darkened(0.08), hc + Vector3(0.075 * sx, -0.125, front + 0.01))
			m.rotation.z = -0.25 * sx
		# Mouth: a dark slit between moustache and beard
		_part(_head, _bbox(Vector3(0.1, 0.03, 0.02), 0.008), Color(0.35, 0.12, 0.08), hc + Vector3(0, -0.175, front + 0.012))

	var hat_c: Color = look.get("hat_color", LINEN)
	match hat:
		"band", "scarf":
			# Cloth band tied round the head; a scarf is wider, striped, with long tails
			var scarf := hat == "scarf"
			var bh2 := 0.17 if scarf else 0.13
			# Round the brow line, under the hair dome (a band on the crown reads as a lid)
			var by := hh * 0.5 - (0.1 if scarf else 0.08)
			_part(_head, _bbox(Vector3(hw + 0.1, bh2, hd + 0.1), 0.05), hat_c, hc + Vector3(0, by, 0))
			if scarf:
				for dy: float in [-0.045, 0.045]:
					_part(_head, _bbox(Vector3(hw + 0.08, 0.03, hd + 0.08), 0.01), look["stripe"], hc + Vector3(0, by + dy, 0))
			_part(_head, _bbox(Vector3(0.13, 0.13, 0.09), 0.035), hat_c.darkened(0.1), hc + Vector3(0.1, by, -hd * 0.5 - 0.06))
			if look.get("tails", true):
				var tl := 0.36 if scarf else 0.25
				for t: Array in [[0.1, 0.35], [-0.01, -0.22]]:
					var tail := _part(_head, _bbox(Vector3(0.11, tl, 0.04), 0.012), hat_c.darkened(0.05),
						hc + Vector3(0.1 + t[0], by - tl * 0.5 - 0.03, -hd * 0.5 - 0.1), Vector3(0.5, 0, t[1]))
					if scarf:
						_part(tail, _bbox(Vector3(0.115, 0.03, 0.045), 0.008), look["stripe"], Vector3(0, -tl * 0.25, 0))
		"wrap":
			# Head-cloth over the crown, coloured band, cloth falling behind to the shoulders
			_part(_head, _sphere(0.5), hat_c, hc + Vector3(0, hh * 0.5 - 0.06, -0.02), Vector3.ZERO, Vector3(hw + 0.16, 0.46, hd + 0.14))
			_part(_head, _bbox(Vector3(hw + 0.12, 0.08, hd + 0.12), 0.025), look["band"], hc + Vector3(0, hh * 0.5 - 0.12, -0.01))
			_part(_head, _bbox(Vector3(hw + 0.08, 0.56, 0.12), 0.04), hat_c.darkened(0.04), hc + Vector3(0, -0.12, -hd * 0.5 - 0.03), Vector3(0.12, 0, 0))
			for sx: float in [-1.0, 1.0]:
				_part(_head, _bbox(Vector3(0.08, 0.42, hd * 0.7), 0.03), hat_c.darkened(0.02), hc + Vector3((hw * 0.5 + 0.05) * sx, -0.06, -0.08))
		"hood":
			_part(_head, _bbox(Vector3(hw + 0.12, hh * 0.55, hd + 0.1), 0.1), hat_c, hc + Vector3(0, hh * 0.3, -0.04))
			for sx: float in [-1.0, 1.0]:
				_part(_head, _bbox(Vector3(0.08, hh * 0.8, hd * 0.9), 0.03), hat_c, hc + Vector3((hw * 0.5 + 0.05) * sx, -0.05, -0.05))
			_part(_head, _bbox(Vector3(hw + 0.1, 0.55, 0.12), 0.04), hat_c, hc + Vector3(0, -0.2, -hd * 0.5 - 0.02), Vector3(0.12, 0, 0))
		"helmet":
			_part(_head, _cyl(0.0, hw * 0.62, 0.42), hat_c, hc + Vector3(0, hh * 0.5 + 0.18, -0.02))
			_part(_head, _bbox(Vector3(hw + 0.1, 0.09, hd + 0.1), 0.03), hat_c.darkened(0.25), hc + Vector3(0, hh * 0.5 - 0.04, -0.01))

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

# Hair by style. The crown is the part the iso camera sees most, so it gets volume.
func _hair(style: String, hair: Color, hc: Vector3, hw: float, hh: float, hd: float, hat: String) -> void:
	if hat == "wrap" or hat == "hood" or hat == "helmet":
		# Only the back shows under the cloth
		_part(_head, _bbox(Vector3(hw + 0.02, hh * 0.5, 0.14), 0.05), hair, hc + Vector3(0, -0.02, -hd * 0.5 + 0.05))
		return
	# A domed mass over the crown and down the back, not a lid
	_part(_head, _sphere(0.5), hair, hc + Vector3(0, hh * 0.5, -0.02), Vector3.ZERO, Vector3(hw + 0.12, 0.38, hd + 0.1))
	_part(_head, _bbox(Vector3(hw + 0.05, hh * 0.8, 0.24), 0.1), hair, hc + Vector3(0, 0.03, -hd * 0.5 + 0.06))
	var crown := hc + Vector3(0, hh * 0.5 + 0.05, 0)
	match style:
		"curly":
			# Tight curls: a cap of small blocks, spilling over the band and behind
			var i := 0
			for x: float in [-0.22, -0.07, 0.08, 0.22]:
				for z: float in [-0.2, -0.04, 0.12]:
					var j := hash(i) % 7 / 7.0
					_part(_head, _bbox(Vector3(0.16, 0.13, 0.16), 0.05), hair.lightened(j * 0.1),
						crown + Vector3(x, 0.02 + j * 0.04, z), Vector3(j, j * 2.0, 0))
					i += 1
			for x: float in [-0.24, -0.08, 0.08, 0.24]:
				_part(_head, _bbox(Vector3(0.15, 0.16, 0.14), 0.05), hair, crown + Vector3(x, -0.3, -hd * 0.5 - 0.02))
		"bushy":
			# Thick mane, lighter on top, falling to the neck at the back and sides
			for t: Array in [[Vector3(-0.14, 0.08, 0.1), 0.3], [Vector3(0.12, 0.09, 0.02), -0.25], [Vector3(-0.02, 0.12, -0.14), 0.6], [Vector3(0.18, 0.06, -0.16), -0.5]]:
				_part(_head, _bbox(Vector3(0.28, 0.12, 0.26), 0.05), hair.lightened(0.1), crown + t[0] - Vector3(0, 0.03, 0), Vector3(0.12, t[1], 0.1))
			_part(_head, _bbox(Vector3(hw + 0.1, 0.34, 0.18), 0.06), hair, crown + Vector3(0, -0.42, -hd * 0.5 + 0.02))
			for sx: float in [-1.0, 1.0]:
				_part(_head, _bbox(Vector3(0.1, 0.34, 0.3), 0.04), hair, crown + Vector3((hw * 0.5 + 0.03) * sx, -0.3, -0.1))
		_:
			# Tousled tufts on the crown so it doesn't read as a lid
			for t: Array in [[Vector3(-0.12, 0.04, 0.08), 0.3], [Vector3(0.1, 0.05, -0.04), -0.25], [Vector3(-0.02, 0.06, -0.14), 0.6]]:
				var tuft := _part(_head, _bbox(Vector3(0.26, 0.1, 0.24), 0.045), hair.lightened(0.05),
					crown + t[0], Vector3(0.12, t[1], 0.1))
				tuft.rotation.z = -t[1] * 0.3

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

# Soft rounded block: the authored bevel sets the corner radius, pushed rounder so
# figures read as toys rather than voxels
static func _bbox(size: Vector3, bevel: float) -> Mesh:
	return _cached("bb%s%.3f" % [size, bevel], func():
		var m := minf(size.x, minf(size.y, size.z))
		var r := Vector3.ONE * bevel * ROUNDING
		return Chunky.round_box(size, r.min(size * 0.48), 2 if m < 0.08 else 3))

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
