class_name WallSection
extends Node3D

signal progress_changed(percent: float)
signal completed
signal uncompleted

# ── Constants ─────────────────────────────────────────────────────────────────

const STONE_NEEDED: int  = 3
const WOOD_NEEDED: int   = 3
const MORTAR_NEEDED: int = 3
const UNIT: float = 100.0 / 9.0  # ~11.11% — one material unit of build progress
const MAX_HEIGHT: float = 2.4
const BLOCK_SIZE := Vector3(10.0, 0.8, 1.0)

# Build phase thresholds
const PHASE_WOOD:  float = 100.0 / 3.0   # ~33.3% — wood scaffolding complete
const PHASE_STONE: float = 200.0 / 3.0   # ~66.7% — stone layer complete

# Wall mesh state colours (per build phase)
const COLOR_EMPTY    := Color(0.28, 0.25, 0.22)  # charcoal rubble
const COLOR_WOOD     := Color(0.55, 0.40, 0.18)  # warm wood scaffolding
const COLOR_STONE    := Color(0.62, 0.58, 0.52)  # grey stone blocks
const COLOR_MORTAR   := Color(0.82, 0.76, 0.60)  # cream mortared finish
const COLOR_COMPLETE := Color(0.95, 0.92, 0.85)  # limestone white

# Pip colours (filled / empty)
const PIP_STONE  := Color(0.72, 0.68, 0.60)  # light grey stone
const PIP_WOOD   := Color(0.58, 0.36, 0.16)  # warm brown
const PIP_MORTAR := Color(0.50, 0.50, 0.58)  # dusty blue-grey
const PIP_EMPTY  := Color(0.18, 0.16, 0.14)  # near-black ghost

# ── Variables ─────────────────────────────────────────────────────────────────

var stone_count: int = 0
var wood_count: int = 0
var mortar_count: int = 0
var completion_percent: float = 0.0:
	set(v):
		var max_allowed = get_max_allowed_completion()
		completion_percent = clamp(v, 0.0, max_allowed)
		_update_visuals()
		progress_changed.emit(completion_percent)
		if completion_percent >= 100.0 and not _is_completed:
			_on_completed()
		elif completion_percent < 100.0 and _is_completed:
			_on_sabotaged()

var _is_completed: bool = false

## Solid ground-level footprint — always visible even at 0% completion
var _footprint: MeshInstance3D = null

# Physics blocker — enabled whenever completion > 0
var _static_body: StaticBody3D = null
var _collision_shape: CollisionShape3D = null

# ── Material indicators (ghost + fill mesh, one per material type) ───────────

var _indicator_root: Node3D = null
var _ind_fill_stone:  MeshInstance3D = null
var _ind_fill_wood:   MeshInstance3D = null
var _ind_fill_mortar: MeshInstance3D = null
var _ind_ghost_stone_mat:  StandardMaterial3D = null
var _ind_ghost_wood_mat:   StandardMaterial3D = null
var _ind_ghost_mortar_mat: StandardMaterial3D = null

var _wall_mat: StandardMaterial3D = null

@onready var _mesh: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	add_to_group("wall_sections")
	_build_footprint()
	_build_wall_material()
	_build_indicators()
	_build_static_body()
	_update_visuals()
	# Position indicators in world space after parent sets our transform
	call_deferred("_init_indicator_worldspace")

func _build_static_body() -> void:
	_static_body = StaticBody3D.new()
	_static_body.collision_layer = 2  # Wall layer
	_static_body.collision_mask = 0

	_collision_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(BLOCK_SIZE.x, MAX_HEIGHT, BLOCK_SIZE.z)
	_collision_shape.shape = box
	_collision_shape.position = Vector3(0, MAX_HEIGHT * 0.5, 0)
	_collision_shape.disabled = true  # Off until something is built
	_static_body.add_child(_collision_shape)
	add_child(_static_body)

func _build_footprint() -> void:
	_footprint = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(BLOCK_SIZE.x, 0.1, BLOCK_SIZE.z)
	_footprint.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.3, 0.3)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_footprint.material_override = mat
	_footprint.position.y = 0.05
	add_child(_footprint)

func _build_wall_material() -> void:
	_wall_mat = StandardMaterial3D.new()
	_wall_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wall_mat.albedo_color = COLOR_EMPTY
	_mesh.material_override = _wall_mat

func _build_indicators() -> void:
	_indicator_root = Node3D.new()
	add_child(_indicator_root)
	# Stone (left) = SphereMesh, Wood (centre) = BoxMesh, Mortar (right) = CylinderMesh
	_ind_fill_stone  = _create_material_indicator(Vector3(-0.8, 0, 0), "stone")
	_ind_fill_wood   = _create_material_indicator(Vector3( 0.0, 0, 0), "wood")
	_ind_fill_mortar = _create_material_indicator(Vector3( 0.8, 0, 0), "mortar")

func _create_material_indicator(offset: Vector3, type: String) -> MeshInstance3D:
	# Build the mesh shape for this material type
	var mesh: Mesh
	match type:
		"stone":
			var s := SphereMesh.new()
			s.radius = 0.22
			s.height = 0.44
			mesh = s
		"wood":
			var b := BoxMesh.new()
			b.size = Vector3(0.55, 0.15, 0.15)
			mesh = b
		"mortar":
			var c := CylinderMesh.new()
			c.top_radius    = 0.18
			c.bottom_radius = 0.14
			c.height        = 0.22
			mesh = c

	# Ghost — full-size, very dim so the player always sees the shape
	var ghost := MeshInstance3D.new()
	ghost.mesh = mesh
	var ghost_mat := StandardMaterial3D.new()
	ghost_mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.albedo_color  = Color(1.0, 1.0, 1.0, 0.12)
	ghost.material_override = ghost_mat
	ghost.position = offset
	_indicator_root.add_child(ghost)
	# Store ghost material ref for highlight updates
	match type:
		"stone":  _ind_ghost_stone_mat  = ghost_mat
		"wood":   _ind_ghost_wood_mat   = ghost_mat
		"mortar": _ind_ghost_mortar_mat = ghost_mat

	# Fill — starts invisible (scale 0), grows to scale 1 as material is delivered
	var fill := MeshInstance3D.new()
	fill.mesh = mesh
	var fill_mat := StandardMaterial3D.new()
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	match type:
		"stone":  fill_mat.albedo_color = PIP_STONE
		"wood":   fill_mat.albedo_color = PIP_WOOD
		"mortar": fill_mat.albedo_color = PIP_MORTAR
	fill.material_override = fill_mat
	fill.position = offset
	fill.scale    = Vector3.ZERO
	_indicator_root.add_child(fill)

	return fill

func _init_indicator_worldspace() -> void:
	if _indicator_root:
		_indicator_root.set_as_top_level(true)
		_indicator_root.global_position = global_position + Vector3(0, MAX_HEIGHT + 1.0, 0)

# ── Staged Construction Logic ─────────────────────────────────────────────────

func get_max_allowed_completion() -> float:
	# Building is phase-ordered: wood → stone → mortar.
	# Each unit of material adds ~11.11% to the buildable ceiling.
	# Stone/mortar phases are locked until the previous phase is fully stocked.
	if wood_count < WOOD_NEEDED:
		return float(wood_count) * UNIT
	if stone_count < STONE_NEEDED:
		return PHASE_WOOD + float(stone_count) * UNIT
	return PHASE_STONE + float(mortar_count) * UNIT

func is_ready_to_build() -> bool:
	return completion_percent < get_max_allowed_completion()

# ── Visuals ───────────────────────────────────────────────────────────────────

func _update_visuals() -> void:
	if not is_node_ready():
		return

	# Wall grows as materials are added + built
	var current_h: float = lerp(0.2, MAX_HEIGHT, completion_percent / 100.0)
	_mesh.scale.y = current_h / BLOCK_SIZE.y
	_mesh.position.y = current_h * 0.5

	# Enable physics blocker whenever anything is built
	if _collision_shape:
		_collision_shape.disabled = (completion_percent <= 0.0)

	_update_wall_color()
	_update_indicators()

func _pop_visual() -> void:
	var tween := create_tween()
	tween.tween_property(_mesh, "scale:x", 1.1, 0.1)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_mesh, "scale:z", 1.1, 0.1)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_mesh, "scale:x", 1.0, 0.1)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(_mesh, "scale:z", 1.0, 0.1)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _update_wall_color() -> void:
	if not _wall_mat:
		return
	_wall_mat.emission_enabled = false
	if _is_completed:
		_wall_mat.albedo_color = COLOR_COMPLETE
		_wall_mat.emission_enabled = true
		_wall_mat.emission = Color(0.5, 0.45, 0.30) * 0.4
	elif completion_percent >= PHASE_STONE:
		_wall_mat.albedo_color = COLOR_MORTAR   # cream finish rising
	elif completion_percent >= PHASE_WOOD:
		_wall_mat.albedo_color = COLOR_STONE    # grey stone blocks
	elif completion_percent > 0.0:
		_wall_mat.albedo_color = COLOR_WOOD     # warm wood scaffolding
	else:
		_wall_mat.albedo_color = COLOR_EMPTY    # bare charcoal rubble

func get_blocking_material() -> String:
	# Returns the material type currently preventing further building
	if wood_count < WOOD_NEEDED:
		return "wood"
	if completion_percent >= PHASE_WOOD and stone_count < STONE_NEEDED:
		return "stone"
	if completion_percent >= PHASE_STONE and mortar_count < MORTAR_NEEDED:
		return "mortar"
	return ""

func _get_blocking_material() -> String:
	return get_blocking_material()

func _set_ghost_highlight(mat: StandardMaterial3D, active: bool) -> void:
	if not mat:
		return
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.45 if active else 0.12)

func _update_indicators() -> void:
	if _indicator_root:
		_indicator_root.visible = not _is_completed
	var blocking := _get_blocking_material()
	_set_ghost_highlight(_ind_ghost_wood_mat,   blocking == "wood")
	_set_ghost_highlight(_ind_ghost_stone_mat,  blocking == "stone")
	_set_ghost_highlight(_ind_ghost_mortar_mat, blocking == "mortar")
	_set_fill_indicator(_ind_fill_stone,  stone_count,  STONE_NEEDED,  PIP_STONE)
	_set_fill_indicator(_ind_fill_wood,   wood_count,   WOOD_NEEDED,   PIP_WOOD)
	_set_fill_indicator(_ind_fill_mortar, mortar_count, MORTAR_NEEDED, PIP_MORTAR)

func _set_fill_indicator(fill: MeshInstance3D, count: int, needed: int, color: Color) -> void:
	if not fill:
		return
	var ratio: float = clampf(float(count) / float(needed), 0.0, 1.0)
	fill.scale = Vector3.ONE * ratio
	var mat := fill.material_override as StandardMaterial3D
	if not mat:
		return
	if count >= needed:
		# Full — bright albedo + emission glow
		mat.albedo_color     = color
		mat.emission_enabled = true
		mat.emission         = color * 0.5
	else:
		# Partial / empty — plain albedo, no glow
		mat.albedo_color     = color
		mat.emission_enabled = false

# ── Damage (enemy sabotage) ───────────────────────────────────────────────────

func take_damage(amount: float) -> void:
	if not multiplayer.is_server():
		return
	if _is_completed:  # 100% walls are immune
		return

	var old_pct := completion_percent
	var new_pct := maxf(old_pct - amount * 0.12, 0.0)

	# Each 11.11% threshold crossed removes one material (highest phase first).
	var units_crossed := floori(old_pct / UNIT) - floori(new_pct / UNIT)
	if units_crossed > 0:
		for _i in range(units_crossed):
			_remove_one_material()
		sync_materials.rpc(stone_count, wood_count, mortar_count)

	# Set completion AFTER material loss so the setter re-clamps to the new ceiling.
	completion_percent = new_pct
	sync_progress.rpc(completion_percent)

func _remove_one_material() -> void:
	# Strips one unit from the highest stocked phase (mortar → stone → wood)
	if mortar_count > 0:
		mortar_count -= 1
	elif stone_count > 0:
		stone_count -= 1
	elif wood_count > 0:
		wood_count -= 1

# ── Material delivery RPCs ────────────────────────────────────────────────────

@rpc("any_peer", "call_local", "reliable")
func request_add_material(sender_id: int) -> void:
	if not multiplayer.is_server():
		return
	var player = get_tree().current_scene.get_node_or_null("Players/" + str(sender_id))
	if player == null or player.get("carried_item") == null:
		return
	var item = player.carried_item
	if item == null:
		return
	if try_add_material(item):
		sync_materials.rpc(stone_count, wood_count, mortar_count)
		sync_progress.rpc(completion_percent)
		_consume_item_rpc.rpc(player.get_path(), item.get_path())

func try_add_material(carriable: Node) -> bool:
	if not carriable is MaterialItem:
		return false

	var success = false
	match carriable.material_type:
		MaterialItem.Type.STONE:
			if stone_count < STONE_NEEDED:
				stone_count += 1
				success = true
		MaterialItem.Type.WOOD:
			if wood_count < WOOD_NEEDED:
				wood_count += 1
				success = true
		MaterialItem.Type.MORTAR:
			if mortar_count < MORTAR_NEEDED:
				mortar_count += 1
				success = true

	if success:
		_pop_visual()
		_update_visuals()
		return true

	return false

@rpc("authority", "call_local", "reliable")
func _consume_item_rpc(player_path: NodePath, item_path: NodePath) -> void:
	var player = get_node_or_null(player_path)
	if player:
		player.carried_item = null
		if player.has_method("_notify_carried_changed"):
			player._notify_carried_changed()
	var item = get_node_or_null(item_path)
	if item:
		item.queue_free()

@rpc("authority", "call_local", "reliable")
func sync_materials(s: int, w: int, m: int) -> void:
	stone_count = s
	wood_count = w
	mortar_count = m
	_update_visuals()

# ── Building RPCs ─────────────────────────────────────────────────────────────

@rpc("any_peer", "call_local", "unreliable")
func request_build(amount: float) -> void:
	if not multiplayer.is_server():
		return
	if is_ready_to_build():
		completion_percent += amount
		sync_progress.rpc(completion_percent)

@rpc("authority", "call_local", "unreliable")
func sync_progress(pct: float) -> void:
	completion_percent = pct

# ── Completion callbacks ──────────────────────────────────────────────────────

func _on_completed() -> void:
	_is_completed = true
	completed.emit()
	var main = get_tree().current_scene
	if main.has_method("add_shake"):
		main.add_shake(0.2)

func _on_sabotaged() -> void:
	_is_completed = false
	uncompleted.emit()
	var main = get_tree().current_scene
	if main.has_method("add_shake"):
		main.add_shake(0.1)
