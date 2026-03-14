class_name WallSection
extends Node2D

signal progress_changed(percent: float)
signal completed
signal uncompleted

# ── Constants ─────────────────────────────────────────────────────────────────

const STONE_NEEDED: int  = 3
const WOOD_NEEDED: int   = 3
const MORTAR_NEEDED: int = 3
const UNIT: float = 100.0 / 9.0  # ~11.11% — one material unit of build progress

# Wall block dimensions in world units (x=width, y=depth/thickness)
const BLOCK_SIZE := Vector2(10.0, 2.0)

# Build phase thresholds
const PHASE_WOOD:  float = 100.0 / 3.0   # ~33.3% — wood scaffolding complete
const PHASE_STONE: float = 200.0 / 3.0   # ~66.7% — stone layer complete

# Wall color per build phase
const COLOR_EMPTY    := Color(0.28, 0.25, 0.22)  # charcoal rubble
const COLOR_WOOD     := Color(0.55, 0.40, 0.18)  # warm wood scaffolding
const COLOR_STONE    := Color(0.62, 0.58, 0.52)  # grey stone blocks
const COLOR_MORTAR   := Color(0.82, 0.76, 0.60)  # cream mortared finish
const COLOR_COMPLETE := Color(0.95, 0.92, 0.85)  # limestone white

# Pip colours
const PIP_STONE  := Color(0.72, 0.68, 0.60)
const PIP_WOOD   := Color(0.58, 0.36, 0.16)
const PIP_MORTAR := Color(0.50, 0.50, 0.58)
const PIP_EMPTY  := Color(0.18, 0.16, 0.14, 0.5)

# ── Variables ─────────────────────────────────────────────────────────────────

var stone_count: int = 0
var wood_count: int = 0
var mortar_count: int = 0
var completion_percent: float = 0.0:
	set(v):
		var max_allowed = get_max_allowed_completion()
		completion_percent = clampf(v, 0.0, max_allowed)
		_update_visuals()
		progress_changed.emit(completion_percent)
		if completion_percent >= 100.0 and not _is_completed:
			_on_completed()
		elif completion_percent < 100.0 and _is_completed:
			_on_sabotaged()

var _is_completed: bool = false
var _static_body: StaticBody2D = null
var _collision_shape: CollisionShape2D = null

func _ready() -> void:
	add_to_group("wall_sections")
	_build_static_body()
	_update_visuals()

func _build_static_body() -> void:
	_static_body = StaticBody2D.new()
	_static_body.collision_layer = 2  # Wall layer
	_static_body.collision_mask = 0

	_collision_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = BLOCK_SIZE
	_collision_shape.shape = rect
	_collision_shape.disabled = true  # Off until something is built
	_static_body.add_child(_collision_shape)
	add_child(_static_body)

# ── Staged Construction Logic ─────────────────────────────────────────────────

func get_max_allowed_completion() -> float:
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
	if _collision_shape:
		_collision_shape.disabled = (completion_percent <= 0.0)
	queue_redraw()

func _draw() -> void:
	var wall_color := _get_wall_color()

	# Scale wall height visually based on completion
	var height_ratio := lerpf(0.2, 1.0, completion_percent / 100.0)
	var draw_size := Vector2(BLOCK_SIZE.x, BLOCK_SIZE.y * height_ratio)
	var rect := Rect2(-draw_size * 0.5, draw_size)

	# Fill
	draw_rect(rect, wall_color)

	# Outline
	var outline_color := Color(0, 0, 0, 0.4)
	if _is_completed:
		outline_color = Color(1.0, 0.9, 0.5, 0.6)
	draw_rect(rect, outline_color, false, 1.0)

	# Footprint marker (always visible)
	if completion_percent <= 0.0:
		draw_rect(Rect2(-BLOCK_SIZE * 0.5, BLOCK_SIZE), Color(0.3, 0.3, 0.3, 0.35))
		draw_rect(Rect2(-BLOCK_SIZE * 0.5, BLOCK_SIZE), Color(0.5, 0.7, 1.0, 0.2), false, 0.8)

	# Material pips (shown when not complete)
	if not _is_completed:
		_draw_pips()

	# Glow on completion
	if _is_completed:
		draw_rect(rect.grow(0.5), Color(0.9, 0.85, 0.6, 0.15))

func _get_wall_color() -> Color:
	if _is_completed:
		return COLOR_COMPLETE
	elif completion_percent >= PHASE_STONE:
		return COLOR_MORTAR
	elif completion_percent >= PHASE_WOOD:
		return COLOR_STONE
	elif completion_percent > 0.0:
		return COLOR_WOOD
	else:
		return COLOR_EMPTY

func _draw_pips() -> void:
	# Draw material pips above the wall block
	var pip_y := -BLOCK_SIZE.y * 0.5 - 2.5
	var spacing := 2.2
	var blocking := get_blocking_material()

	# Stone pips (left third)
	for i in range(STONE_NEEDED):
		var x := -3.5 + float(i) * spacing
		var filled := i < stone_count
		var alpha := 1.0 if filled else 0.3
		var col := PIP_STONE if filled else PIP_EMPTY
		if not filled and blocking == "stone":
			col = Color(PIP_STONE.r, PIP_STONE.g, PIP_STONE.b, 0.7)
		draw_circle(Vector2(x, pip_y), 0.7, col)

	# Wood pips (center)
	for i in range(WOOD_NEEDED):
		var x := 0.0 + float(i - 1) * spacing
		var filled := i < wood_count
		var col := PIP_WOOD if filled else PIP_EMPTY
		if not filled and blocking == "wood":
			col = Color(PIP_WOOD.r, PIP_WOOD.g, PIP_WOOD.b, 0.7)
		draw_rect(Rect2(Vector2(x - 0.6, pip_y - 0.4), Vector2(1.2, 0.8)), col)

	# Mortar pips (right third)
	for i in range(MORTAR_NEEDED):
		var x := 3.5 + float(i) * spacing
		var filled := i < mortar_count
		var col := PIP_MORTAR if filled else PIP_EMPTY
		if not filled and blocking == "mortar":
			col = Color(PIP_MORTAR.r, PIP_MORTAR.g, PIP_MORTAR.b, 0.7)
		draw_circle(Vector2(x, pip_y), 0.55, col)

func _pop_visual() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale:x", 1.1, 0.1)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale:x", 1.0, 0.1)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func get_blocking_material() -> String:
	if wood_count < WOOD_NEEDED:
		return "wood"
	if completion_percent >= PHASE_WOOD and stone_count < STONE_NEEDED:
		return "stone"
	if completion_percent >= PHASE_STONE and mortar_count < MORTAR_NEEDED:
		return "mortar"
	return ""

func _get_blocking_material() -> String:
	return get_blocking_material()

# ── Damage (enemy sabotage) ───────────────────────────────────────────────────

func take_damage(amount: float) -> void:
	if not multiplayer.is_server():
		return
	if _is_completed:  # 100% walls are immune
		return

	var old_pct := completion_percent
	var new_pct := maxf(old_pct - amount * 0.12, 0.0)

	var units_crossed := floori(old_pct / UNIT) - floori(new_pct / UNIT)
	if units_crossed > 0:
		for _i in range(units_crossed):
			_remove_one_material()
		sync_materials.rpc(stone_count, wood_count, mortar_count)

	completion_percent = new_pct
	sync_progress.rpc(completion_percent)

func _remove_one_material() -> void:
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

func _on_sabotaged() -> void:
	_is_completed = false
	uncompleted.emit()
