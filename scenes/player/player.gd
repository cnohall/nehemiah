extends CharacterBody3D

const BASE_SPEED      := 8.0
const CARRY_SPEED     := 5.5   # speed while carrying anything
const INTERACT_REACH  := 2.5   # units radius

const MOVE_DIRS := {
	"move_north": Vector3(-1, 0, -1),
	"move_south": Vector3( 1, 0,  1),
	"move_east":  Vector3( 1, 0, -1),
	"move_west":  Vector3(-1, 0,  1),
}

var health: float = 100.0
var carried_kind: String = ""

@onready var mesh: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	add_to_group("players")

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	_handle_movement(delta)
	_handle_interact()

# ── Movement ───────────────────────────────────────────────

func _handle_movement(_delta: float) -> void:
	var dir := Vector3.ZERO
	for action in MOVE_DIRS:
		if Input.is_action_pressed(action):
			dir += MOVE_DIRS[action]
	if dir.length_squared() > 0:
		dir = dir.normalized()
	velocity = dir * (CARRY_SPEED if not carried_kind.is_empty() else BASE_SPEED)
	move_and_slide()

# ── Interact / Drop ────────────────────────────────────────

func _handle_interact() -> void:
	if Input.is_action_just_pressed("interact"):
		_try_interact()
	if Input.is_action_just_pressed("drop"):
		carried_kind = ""

func _try_interact() -> void:
	if not carried_kind.is_empty():
		# Carrying → deposit at nearest wall section
		for section in get_tree().get_nodes_in_group("wall_sections"):
			if _in_reach(section):
				section.deposit(carried_kind, 1)
				carried_kind = ""
				return
	else:
		# Empty-handed → try to build first, then pick up
		for section in get_tree().get_nodes_in_group("wall_sections"):
			if _in_reach(section) and section.try_build():
				return

		for pile in get_tree().get_nodes_in_group("supply_piles"):
			if _in_reach(pile):
				if pile.request_pickup():
					carried_kind = pile.kind
				return

# ── Damage ─────────────────────────────────────────────────

func take_damage(amount: float) -> void:
	health = clampf(health - amount, 0.0, 100.0)
	if health <= 0.0:
		health = 100.0  # TODO: proper respawn

# ── Helpers ────────────────────────────────────────────────

func _in_reach(node: Node3D) -> bool:
	return global_position.distance_squared_to(node.global_position) \
		< INTERACT_REACH * INTERACT_REACH
