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
		var max_allowed = get_max_allowed_completion()
		completion_percent = clamp(v, 0.0, max_allowed)
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

## Three indicators (stone / wood / mortar)
var _indicators: Array[MeshInstance3D] = []
var _ind_mats:   Array[StandardMaterial3D] = []

## UI Label for material counts and progress
var _info_label: Label3D = null

# Indicator colours
const IND_COLORS: Array[Color] = [
	Color(0.6, 0.6, 0.6),   # stone  — grey
	Color(0.4, 0.26, 0.13), # wood   — brown
	Color(0.3, 0.3, 0.35),  # mortar — dark blueish
]

# ── Ready ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	add_to_group("wall_sections")
	_build_footprint()
	_build_indicators()
	_build_info_label()
	_update_visuals()

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

func _build_indicators() -> void:
	var x_offsets := [-2.0, 0.0, 2.0]
	for i in range(3):
		var inst := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.4, 0.4, 0.4)
		inst.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = IND_COLORS[i]
		inst.material_override = mat
		inst.position = Vector3(x_offsets[i], 1.2, 0.0)
		add_child(inst)
		_indicators.append(inst)
		_ind_mats.append(mat)

func _build_info_label() -> void:
	_info_label = Label3D.new()
	_info_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_info_label.font_size = 32
	_info_label.outline_size = 10
	_info_label.position = Vector3(0.0, 2.0, 0.0)
	add_child(_info_label)

# ── Staged Construction Logic ─────────────────────────────────────────────────

func get_max_allowed_completion() -> float:
	if wood_count == 0: return 0.0
	if wood_count < WOOD_NEEDED: return 20.0   # Scaffolding/Framework
	if stone_count < STONE_NEEDED: return 50.0 # Main Structure
	if mortar_count < MORTAR_NEEDED: return 80.0 # Binding
	return 100.0

func is_ready_to_build() -> bool:
	return completion_percent < get_max_allowed_completion()

# ── Visuals ───────────────────────────────────────────────────────────────────

func _update_visuals() -> void:
	if not is_node_ready(): return

	var current_h: float = lerp(0.2, MAX_HEIGHT, completion_percent / 100.0)
	_mesh.scale.y = current_h / BLOCK_SIZE.y
	_mesh.position.y = current_h * 0.5

	var counts = [stone_count, wood_count, mortar_count]
	var needed = [STONE_NEEDED, WOOD_NEEDED, MORTAR_NEEDED]
	var names = ["Stone", "Wood", "Mortar"]
	
	var status_text = ""
	var max_comp = get_max_allowed_completion()
	
	if _is_completed:
		status_text = "[ COMPLETE ]"
		_info_label.modulate = Color.GREEN
		for ind in _indicators: ind.visible = false
	else:
		for i in range(3):
			var ind_mat: StandardMaterial3D = _ind_mats[i]
			ind_mat.emission_enabled = (counts[i] >= needed[i])
			if ind_mat.emission_enabled:
				ind_mat.albedo_color = IND_COLORS[i]
				ind_mat.emission = IND_COLORS[i]
			else:
				ind_mat.albedo_color = IND_COLORS[i] * 0.3
				status_text += "%s: %d/%d  " % [names[i], counts[i], needed[i]]
		
		if completion_percent < max_comp:
			status_text += "\nBUILDING: %d%%" % int(completion_percent)
			_info_label.modulate = Color.YELLOW
		elif max_comp < 100.0:
			status_text += "\nNEED MORE MATERIALS TO BUILD HIGHER"
			_info_label.modulate = Color.ORANGE
		else:
			status_text += "\nREADY TO FINISH: %d%%" % int(completion_percent)
			_info_label.modulate = Color.CYAN

	_info_label.text = status_text

# ── Damage (enemy sabotage) ───────────────────────────────────────────────────

func take_damage(amount: float) -> void:
	if not multiplayer.is_server(): return
	
	var final_dmg = amount
	var main = get_tree().current_scene
	if main and main.get("upgrades_purchased") and main.upgrades_purchased.get("fortify", false):
		final_dmg *= 0.5 # 50% damage reduction
		
	completion_percent -= final_dmg * 0.5
	sync_progress.rpc(completion_percent)

# ── Material delivery RPCs ────────────────────────────────────────────────────

@rpc("any_peer", "call_local", "reliable")
func request_add_material(sender_id: int) -> void:
	if not multiplayer.is_server(): return
	var player = get_tree().current_scene.get_node_or_null("Players/" + str(sender_id))
	if player == null or player.get("carried_item") == null: return
	var item = player.carried_item
	if item == null: return
	if try_add_material(item):
		sync_materials.rpc(stone_count, wood_count, mortar_count)
		_consume_item_rpc.rpc(player.get_path(), item.get_path())

func try_add_material(carriable: Carriable) -> bool:
	if carriable is CutStone and stone_count < STONE_NEEDED: stone_count += 1
	elif carriable is TimberBeam and wood_count < WOOD_NEEDED: wood_count += 1
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
func sync_materials(s: int, w: int, m: int) -> void:
	stone_count = s
	wood_count = w
	mortar_count = m
	_update_visuals()

# ── Building RPCs ─────────────────────────────────────────────────────────────

@rpc("any_peer", "call_local", "unreliable")
func request_build(amount: float) -> void:
	if not multiplayer.is_server(): return
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
	if main.has_method("add_shake"): main.add_shake(0.2)

func _on_sabotaged() -> void:
	_is_completed = false
	uncompleted.emit()
	var main = get_tree().current_scene
	if main.has_method("add_shake"): main.add_shake(0.1)
