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
const RUN_ANIM_SPEED  := 8.0      # ground speed the run cycle was drawn for
const WALK_ANIM_SPEED := 4.5

const MOVE_DIRS := {
	"move_north": Vector3(-1, 0, -1),
	"move_south": Vector3( 1, 0,  1),
	"move_east":  Vector3( 1, 0, -1),
	"move_west":  Vector3(-1, 0,  1),
}

const CARRY_COLORS := {
	"stone":  Color(0.72, 0.68, 0.60),
	"wood":   Color(0.50, 0.33, 0.17),
	"mortar": Color(0.86, 0.80, 0.66),
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
const MARKER_SHADER := preload("res://assets/shaders/ground_marker.gdshader")

# Replicated animation name — owner writes, every peer plays it
var anim := "idle_down":
	set(value):
		anim = value
		if _sprite != null and _sprite.animation != value:
			_sprite.play(value)

var health: float = MAX_HEALTH
var carried_kind: String = ""
var downed := false
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
	_sprite.play(anim)
	_carry_prop = Node3D.new()
	_carry_prop.position.y = CARRY_HEIGHT
	add_child(_carry_prop)
	_build_whirl()
	_hp_bar = HealthBar.new()
	_hp_bar.position.y = HP_BAR_Y
	add_child(_hp_bar)

func _process(delta: float) -> void:
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
	_sprite.set_sheet(_SHEETS[slot % _SHEETS.size()], _ANIMS)
	_sprite.set_ring_color(c)

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	_sling_cd = maxf(0.0, _sling_cd - delta)
	if downed or GameState.is_over():
		velocity = Vector3.ZERO
		_cancel_charge()
		return
	if _is_busy:
		_cancel_charge()  # hit or acting — wind-up is lost
	_handle_movement()
	if not _is_busy:
		_handle_interact()
		_handle_attack(delta)
	_update_anim()

# ── Movement ───────────────────────────────────────────────

func _handle_movement() -> void:
	var dir := Vector3.ZERO
	for action in MOVE_DIRS:
		if Input.is_action_pressed(action):
			dir += MOVE_DIRS[action]
	if dir.length_squared() > 0:
		dir = dir.normalized()
	velocity = dir * (CARRY_SPEED if not carried_kind.is_empty() else RUN_SPEED)
	if _charging:
		velocity *= CHARGE_MOVE_MULT
	move_and_slide()
	global_position.x = clampf(global_position.x, PLAY_AREA.position.x, PLAY_AREA.end.x)
	global_position.z = clampf(global_position.z, PLAY_AREA.position.y, PLAY_AREA.end.y)

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
		_server_drop.rpc_id(1)

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
	# Nearest valid thing wins — sections and gate pillars overlap in reach
	if not carried_kind.is_empty():
		var dest := _nearest_in_reach("wall_sections", at, func(s): return s.needs(carried_kind))
		if dest != null and dest.deposit(carried_kind, 1):
			_set_carried.rpc("")
			_action.rpc("halfslash")
			# Last load for this stage → raise it straight away (no separate Build press)
			if dest.can_build() and dest.try_build():
				_tell("Stage built!")
			return
		_tell(_why_not_needed(at))
		return
	# Fallback for sections that were already full (e.g. filled before a change of rules)
	var site := _nearest_in_reach("wall_sections", at, func(s): return s.can_build())
	if site != null and site.try_build():
		_action.rpc("halfslash")
		return
	var pile := _nearest_in_reach("supply_piles", at, func(_p): return true)
	if pile != null and pile.request_pickup():
		_set_carried.rpc(pile.kind)

# Server: explain a refused delivery (the carried material isn't wanted here)
func _why_not_needed(at: Vector3) -> String:
	var wall := _nearest_in_reach("wall_sections", at, func(_s): return true)
	if wall == null:
		if _nearest_in_reach("supply_piles", at, func(_p): return true) != null:
			return "Hands full — deliver it, or [G] to drop"
		return "Bring it to a wall"
	var need: String = wall.next_need()
	if need.is_empty():
		return "This wall is finished"
	return "Needs %s first" % need

@rpc("any_peer", "call_local", "reliable")
func _server_drop() -> void:
	if _from_owner() and not carried_kind.is_empty():
		_tell("Dropped %s" % carried_kind)
		_set_carried.rpc("")

@rpc("any_peer", "call_local", "reliable")
func _set_carried(kind: String) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	carried_kind = kind
	_rebuild_carry_prop()

# Server → everyone: the owner plays the action (its anim then replicates)
@rpc("any_peer", "call_local", "reliable")
func _action(anim_base: String) -> void:
	if multiplayer.get_remote_sender_id() == 1 and is_multiplayer_authority():
		_play_action(anim_base)

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
			_set_carried.rpc("")
		_set_downed.rpc(true)

@rpc("any_peer", "call_local", "reliable")
func _on_hurt(new_health: float) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	health = new_health
	_sprite.hit_flash()
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
	_sync_status.rpc_id(peer_id, carried_kind, downed, health)

@rpc("any_peer", "call_remote", "reliable")
func _sync_status(kind: String, is_downed: bool, hp: float) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	carried_kind = kind
	downed = is_downed
	if is_downed:
		_down_timer = DOWNED_TIME  # exact remaining time isn't sent; close enough for a late joiner
	health = hp
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
	if carried_kind.is_empty():
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = CARRY_COLORS.get(carried_kind, Color.GRAY)
	mat.roughness = 0.9
	match carried_kind:
		"wood":
			for z: float in [-0.09, 0.09]:
				var log_mesh := CylinderMesh.new()
				log_mesh.top_radius = 0.08
				log_mesh.bottom_radius = 0.08
				log_mesh.height = 0.9
				_add_prop_mesh(log_mesh, mat, Vector3(0, 0, z), Vector3(0, 0, PI / 2))
		"stone":
			var block := BoxMesh.new()
			block.size = Vector3(0.45, 0.28, 0.32)
			_add_prop_mesh(block, mat, Vector3.ZERO, Vector3(0, 0.4, 0))
		"mortar":
			var basket := CylinderMesh.new()
			basket.top_radius = 0.22
			basket.bottom_radius = 0.16
			basket.height = 0.26
			_add_prop_mesh(basket, mat, Vector3.ZERO, Vector3.ZERO)

func _add_prop_mesh(mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	_carry_prop.add_child(mi)

# ── Helpers ────────────────────────────────────────────────

func _from_owner() -> bool:
	return multiplayer.is_server() \
		and multiplayer.get_remote_sender_id() == get_multiplayer_authority()

func _nearest_in_reach(group: String, from: Vector3, accept: Callable) -> Node3D:
	var best: Node3D = null
	var best_dist := INTERACT_REACH
	for node: Node3D in get_tree().get_nodes_in_group(group):
		var d: float = node.distance_to_point(from) if node.has_method("distance_to_point") \
			else from.distance_to(node.global_position)
		if d < best_dist and accept.call(node):
			best_dist = d
			best = node
	return best
