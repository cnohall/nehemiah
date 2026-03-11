extends Node3D
class_name WallSection

signal progress_changed(percent: float)
signal completed
signal uncompleted

# ── Material requirements ──────────────────────────────────────────────────────

const STONE_NEEDED:  int = 5
const WOOD_NEEDED:   int = 3
const MORTAR_NEEDED: int = 2

var stone_count:  int = 0
var wood_count:   int = 0
var mortar_count: int = 0

# ── Completion ────────────────────────────────────────────────────────────────

var completion_percent: float = 0.0:
	set(v):
		completion_percent = clamp(v, 0.0, 100.0)
		_update_visuals()
		progress_changed.emit(completion_percent)
		if completion_percent >= 100.0 and not _is_completed:
			_on_completed()
		elif completion_percent < 100.0 and _is_completed:
			_on_sabotaged()

var _is_completed: bool = false

const MAX_HEIGHT: float = 2.4
const BLOCK_SIZE := Vector3(10.0, 0.8, 1.0)

# ── Node refs ─────────────────────────────────────────────────────────────────

@onready var _mesh: MeshInstance3D = $MeshInstance3D

## Solid ground-level footprint — always visible even at 0% completion
var _footprint: MeshInstance3D = null

## Three sphere indicators (stone / wood / mortar)
var _indicators: Array[MeshInstance3D] = []
var _ind_mats:   Array[StandardMaterial3D] = []

## Progress label — visible only while actively building
var _pct_label: Label3D = null

# Indicator colours
const IND_MISSING: Array[Color] = [
	Color(0.55, 0.55, 0.55),   # stone  — grey
	Color(0.50, 0.30, 0.10),   # wood   — brown
	Color(0.85, 0.82, 0.78),   # mortar — cream
]
const IND_PARTIAL := Color(1.00, 0.70, 0.10)  # amber — some delivered
const IND_DONE    := Color(0.20, 0.90, 0.30)  # bright green — all delivered

# ── Ready ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	add_to_group("wall_sections")
	# Remove the placeholder label baked into the scene file
	var tscn_label := get_node_or_null("Label3D")
	if tscn_label: tscn_label.queue_free()
	_build_footprint()
	_build_indicators()
	_build_pct_label()
	_update_visuals()

## Solid coloured slab sitting on the floor — always visible, shows wall path.
func _build_footprint() -> void:
	_footprint = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(BLOCK_SIZE.x, 0.10, BLOCK_SIZE.z)
	_footprint.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.50, 0.60, 0.72)   # muted stone-blue
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_footprint.material_override = mat
	_footprint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_footprint.position.y = 0.05   # just proud of the floor surface
	add_child(_footprint)

func _build_indicators() -> void:
	# Spread three spheres evenly across the 10-unit wide section
	var x_offsets := [-2.5, 0.0, 2.5]
	for i in range(3):
		var inst := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.22
		sph.height = 0.44
		inst.mesh = sph
		var mat := StandardMaterial3D.new()
		mat.albedo_color = IND_MISSING[i]
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		inst.material_override = mat
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		inst.position = Vector3(x_offsets[i], 0.80, 0.0)
		add_child(inst)
		_indicators.append(inst)
		_ind_mats.append(mat)

func _build_pct_label() -> void:
	_pct_label = Label3D.new()
	_pct_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_pct_label.font_size  = 28
	_pct_label.outline_size = 6
	_pct_label.position = Vector3(0.0, 1.6, 0.0)
	_pct_label.modulate = Color.YELLOW
	_pct_label.visible = false
	add_child(_pct_label)

# ── Visuals ───────────────────────────────────────────────────────────────────

func _update_visuals() -> void:
	if not is_node_ready(): return

	# Wall mesh rises as completion increases (starts at a visible 0.3 stub)
	var current_h: float = lerp(0.30, MAX_HEIGHT, completion_percent / 100.0)
	_mesh.scale.y    = current_h / BLOCK_SIZE.y
	_mesh.position.y = current_h * 0.5

	var all_ready := is_ready_to_build()

	if _is_completed:
		for ind in _indicators: ind.visible = false
		if _pct_label:   _pct_label.visible = false
		if _footprint:   _footprint.visible = false
		# Golden wall tint
		if _mesh.get_surface_override_material(0) == null:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.85, 0.78, 0.55)
			_mesh.set_surface_override_material(0, mat)

	elif all_ready:
		# All materials delivered — show build progress, hide material indicators
		for ind in _indicators: ind.visible = false
		if _footprint:  _footprint.visible = true
		if _pct_label:
			_pct_label.text = "READY: %d%%" % int(completion_percent)
			_pct_label.visible = true
		_mesh.set_surface_override_material(0, null)

	else:
		# Show material delivery status
		if _footprint: _footprint.visible = true
		if _pct_label:
			var status := "NEEDS: "
			if stone_count < STONE_NEEDED: status += "Stone %d/%d " % [stone_count, STONE_NEEDED]
			if wood_count < WOOD_NEEDED: status += "Wood %d/%d " % [wood_count, WOOD_NEEDED]
			if mortar_count < MORTAR_NEEDED: status += "Mortar %d/%d " % [mortar_count, MORTAR_NEEDED]
			_pct_label.text = status
			_pct_label.visible = true
		_update_indicator_colors()
		_mesh.set_surface_override_material(0, null)

func _update_indicator_colors() -> void:
	var counts  := [stone_count,  wood_count,  mortar_count]
	var neededs := [STONE_NEEDED, WOOD_NEEDED, MORTAR_NEEDED]
	for i in range(3):
		var ind: MeshInstance3D = _indicators[i]
		var mat: StandardMaterial3D = _ind_mats[i]
		ind.visible = true
		if counts[i] == 0:
			mat.albedo_color = IND_MISSING[i]
		elif counts[i] >= neededs[i]:
			mat.albedo_color = IND_DONE
		else:
			mat.albedo_color = IND_PARTIAL

# ── Queries ───────────────────────────────────────────────────────────────────

func is_ready_to_build() -> bool:
	return stone_count >= STONE_NEEDED and wood_count >= WOOD_NEEDED and mortar_count >= MORTAR_NEEDED

# ── Damage (enemy sabotage) ───────────────────────────────────────────────────

func take_damage(amount: float) -> void:
	if not multiplayer.is_server(): return
	completion_percent -= amount * 0.5
	_sync_progress.rpc(completion_percent)

# ── Material delivery RPCs ────────────────────────────────────────────────────

@rpc("any_peer", "call_local", "reliable")
func request_add_material(sender_id: int) -> void:
	if not multiplayer.is_server(): return
	var player = get_tree().current_scene.get_node_or_null("Players/" + str(sender_id))
	if player == null or player.get("carried_item") == null: return
	var item = player.carried_item
	if item == null: return
	if try_add_material(item):
		_sync_materials.rpc(stone_count, wood_count, mortar_count)
		_consume_item_rpc.rpc(player.get_path(), item.get_path())

func try_add_material(carriable: Carriable) -> bool:
	if carriable is CutStone    and stone_count  < STONE_NEEDED:  stone_count  += 1
	elif carriable is TimberBeam  and wood_count   < WOOD_NEEDED:   wood_count   += 1
	elif carriable is MortarBucket and mortar_count < MORTAR_NEEDED: mortar_count += 1
	else: return false
	_update_visuals()
	return true

@rpc("authority", "call_local", "reliable")
func _consume_item_rpc(player_path: NodePath, item_path: NodePath) -> void:
	var player = get_node_or_null(player_path)
	if player:
		player.carried_item = null
		if player.has_method("_notify_carried_changed"):
			player._notify_carried_changed()
	var item = get_node_or_null(item_path)
	if item: item.queue_free()

@rpc("authority", "call_local", "reliable")
func _sync_materials(s: int, w: int, m: int) -> void:
	stone_count  = s
	wood_count   = w
	mortar_count = m
	_update_visuals()

# ── Building RPCs ─────────────────────────────────────────────────────────────

@rpc("any_peer", "call_local", "unreliable")
func request_build(amount: float) -> void:
	if not multiplayer.is_server(): return
	if is_ready_to_build():
		completion_percent += amount
		_sync_progress.rpc(completion_percent)

@rpc("authority", "call_local", "unreliable")
func _sync_progress(pct: float) -> void:
	completion_percent = pct

# ── Completion callbacks ──────────────────────────────────────────────────────

func _on_completed() -> void:
	_is_completed = true
	completed.emit()
	var main = get_tree().current_scene
	if main.has_method("add_shake"): main.add_shake(0.2)

func _on_sabotaged() -> void:
	_is_completed = false
	uncompleted.emit()
	var main = get_tree().current_scene
	if main.has_method("add_shake"): main.add_shake(0.1)
