extends StaticBody3D

signal stage_changed(new_stage: int)
signal destroyed

enum Stage { EMPTY, FRAMED, STACKED, MORTARED }

const MATERIAL_COST := {
	Stage.FRAMED:   { "wood":   3 },
	Stage.STACKED:  { "stone":  6 },
	Stage.MORTARED: { "mortar": 2 },
}
const MAX_HEALTH := 150.0

const STAGE_COLORS := [
	Color(0.62, 0.54, 0.38, 1),  # EMPTY   — bare earth
	Color(0.52, 0.32, 0.14, 1),  # FRAMED  — wood brown
	Color(0.70, 0.65, 0.55, 1),  # STACKED — stone beige
	Color(0.58, 0.54, 0.46, 1),  # MORTARED — finished wall
]

@export var stage: Stage = Stage.EMPTY

var health: float = MAX_HEALTH
# Materials deposited here, waiting for a Builder to construct
var pending: Dictionary = { "stone": 0, "wood": 0, "mortar": 0 }

@onready var mesh: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	add_to_group("wall_sections")
	_update_visuals()

# ── Deposit (any role) ─────────────────────────────────────

func deposit(kind: String, amount: int) -> void:
	if not multiplayer.is_server():
		return
	var next := (stage + 1) as Stage
	if next > Stage.MORTARED:
		return
	if MATERIAL_COST.get(next, {}).has(kind):
		pending[kind] = pending.get(kind, 0) + amount

# ── Build (Builder role only) ──────────────────────────────

func try_build() -> bool:
	if not multiplayer.is_server():
		return false
	var next := (stage + 1) as Stage
	if next > Stage.MORTARED:
		return false
	var cost: Dictionary = MATERIAL_COST.get(next, {})
	for kind in cost:
		if pending.get(kind, 0) < cost[kind]:
			return false
	for kind in cost:
		pending[kind] -= cost[kind]
	stage = next
	_update_visuals()
	stage_changed.emit(stage)
	return true

# Returns how much of the next stage's required material is pending (0.0–1.0)
func get_build_progress() -> float:
	var next := (stage + 1) as Stage
	if next > Stage.MORTARED:
		return 1.0
	var cost: Dictionary = MATERIAL_COST.get(next, {})
	if cost.is_empty():
		return 0.0
	var kind: String = cost.keys()[0]
	return minf(float(pending.get(kind, 0)) / float(cost[kind]), 1.0)

# ── Damage ─────────────────────────────────────────────────

func take_damage(amount: float) -> void:
	if stage == Stage.EMPTY:
		return
	health = clampf(health - amount, 0.0, MAX_HEALTH)
	if health == 0.0:
		_degrade()

func _degrade() -> void:
	if stage == Stage.EMPTY:
		destroyed.emit()
		return
	stage = (stage - 1) as Stage
	health = MAX_HEALTH * 0.5
	pending.clear()
	_update_visuals()
	stage_changed.emit(stage)

# ── Visuals ────────────────────────────────────────────────

func _update_visuals() -> void:
	if mesh == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = STAGE_COLORS[stage]
	mesh.set_surface_override_material(0, mat)
