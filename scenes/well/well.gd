class_name Well
extends Node3D

# The city well (GDD §5.22): a hurt worker walks to it, sets the load down and holds [E] to drink
# until mended (Player.Act.DRINK; the healing is Player's). This node is the place and the
# telling: a tag over the frame that appears only for a worker who is hurt — a plain "Well" to
# find it from afar (it slides in from the screen edge), then "Drink [E]" once in reach, pulsing
# when badly hurt. Healthy workers never see it. The stonework is ScatterLayer's (_well).

const SHOW_BELOW   := 0.8    # health fraction under which the tag appears for the local worker
const URGENT_BELOW := 0.5    # …and under which it breathes
const TAG_Y        := 2.5    # over the crossbeam (1.9)
const RIM          := 0.95   # centre to the stone lip, m: reach is measured from the lip

var _tag: WorldTag

func _init() -> void:
	name = "Well"   # the same path on every peer: Player sends it to the owner when drinking starts

func _ready() -> void:
	add_to_group("wells")
	position = ScatterLayer.WELL_POS
	_tag = WorldTag.make(WorldTag.Kind.STATION)
	_tag.position = Vector3(0, TAG_Y, 0)
	_tag.visible = false
	add_child(_tag)

func _process(_delta: float) -> void:
	var me := Player.local
	if me == null or me.downed or me.is_drinking() or not Player.can_drink_now():
		_tag.visible = false
		return
	var hp := me.health / Player.MAX_HEALTH
	_tag.visible = hp < SHOW_BELOW
	_tag.pulse = hp < URGENT_BELOW
	if not _tag.visible:
		return
	if distance_to_point(me.global_position) > Player.INTERACT_REACH:
		_tag.text = "Well"
	elif me.carried_kind.is_empty():
		_tag.text = "Drink  [%s]" % InputMode.key("interact")
	else:
		_tag.text = "Set the load down first"

## Metres from `p` to the lip (negative inside it), on the ground — Player's reach test
func distance_to_point(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length() - RIM

## Where to stand: on the lip toward `from`
func approach_point(from: Vector3, _standoff: float) -> Vector3:
	var d := Vector2(from.x - global_position.x, from.z - global_position.z)
	d = d.normalized() if d.length() > 0.01 else Vector2(0, 1)
	return Vector3(global_position.x + d.x * (RIM + 0.4), from.y, global_position.z + d.y * (RIM + 0.4))
