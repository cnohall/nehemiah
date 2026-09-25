extends Node

# Rearranges the shared map for the current section (GDD §6): the supply yard moves so
# each stretch plays differently (e.g. the long haul at the Dung Gate). Runs on every
# peer from GameState alone — deterministic, nothing replicated. The DayDirector
# rebakes navigation at dawn, after this has run.
# Twist-specific pieces (beam pile, rubble heaps, gate doors / infill) toggle themselves.

@onready var _supplies: Node3D = get_parent().get_node("Supplies")

var _offsets := {}   # pile → offset from the default yard centre

func _ready() -> void:
	var home := GameState.DEFAULT_YARD
	for pile: Node3D in _supplies.get_children():
		_offsets[pile] = Vector2(pile.position.x - home.x, pile.position.z - home.y)
	GameState.section_changed.connect(_apply.unbind(1))
	_apply()

func _apply() -> void:
	var yard := GameState.yard_center()
	for pile: Node3D in _offsets:
		var off: Vector2 = _offsets[pile]
		pile.position = Vector3(yard.x + off.x, pile.position.y, yard.y + off.y)
