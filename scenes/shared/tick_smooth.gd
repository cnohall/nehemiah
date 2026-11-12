class_name TickSmooth
extends Node
## Draws a physics-moved parent between its last two physics ticks. The body moves at
## 60 Hz but the screen (and the follow camera) run at the display's rate, so on a
## faster screen the owner's own worker stepped against a smooth world, the only figure
## that did (remote copies are already blended per frame by NetSmooth).
##
## Each render frame the parent is put at the blend of the last two tick results; just
## before the next tick it goes back to the true result, so physics, collisions and the
## rig's motion sampling never see the blended spot. Anything else that moves the parent
## between ticks (a teleport, the climb tween, an RPC) is taken as is: no blend across it.

var _prev := Vector3.ZERO
var _curr := Vector3.ZERO
var _drawn := Vector3.ZERO
var _ready_once := false

func _ready() -> void:
	process_priority = -100            # before anything this frame reads the parent (camera, tags)
	process_physics_priority = 1000    # after the parent and everyone else have moved it this tick
	get_tree().physics_frame.connect(_before_tick)
	var n := get_parent() as Node3D
	_prev = n.global_position
	_curr = _prev
	_drawn = _prev
	_ready_once = true

func _before_tick() -> void:
	var n := get_parent() as Node3D
	if n == null or not _ready_once or not is_inside_tree():
		return   # the tree's signal still reaches a node lifted out with its scene
	if n.global_position.is_equal_approx(_drawn):
		n.global_position = _curr   # undo the blend: physics runs from the true spot
	else:
		_curr = n.global_position   # moved by something else since the last draw: take it
	_prev = _curr

func _physics_process(_delta: float) -> void:
	_curr = (get_parent() as Node3D).global_position

func _process(_delta: float) -> void:
	var n := get_parent() as Node3D
	var at := n.global_position
	if not at.is_equal_approx(_curr) and not at.is_equal_approx(_drawn):
		# Moved outside physics since the tick (teleport, tween): don't blend across it
		_prev = at
		_curr = at
	n.global_position = _prev.lerp(_curr, Engine.get_physics_interpolation_fraction())
	_drawn = n.global_position
