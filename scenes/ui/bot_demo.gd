class_name BotDemo
extends Node

# Bots already know the twists. The first time in a section that one does something the
# section brings new (holds the far end of a beam, carries lime or water to the trough,
# digs stone out of the rubble), point at it: "Watch the carpenter — two to a beam".
# People learn by copying the crew (Overcooked's own trick); this points them at it.
# Local only: reads state every peer already has.

const HOLD  := 5.0
const LIFT  := 3.7
# twist → [what a bot is seen doing (Callable on the bot), the line]
var _shows := {
	"beams": [func(b: Player): return b.helping_id != 0, "two to a beam"],
	"mixing": [func(b: Player): return b.carried_kind in ["lime", "water"], "lime and water go to the trough"],
	"salvage": [func(b: Player): return b.carried_kind == "stone", "stone comes out of the rubble"],
	"haul": [func(b: Player): return b.carried_kind != "" and _near_relay(b), "loads stack on the relay mat"],
}
var _shown := {}   # twist → true, this section

func _ready() -> void:
	GameState.section_changed.connect(func(_i): _shown.clear())

func _process(_delta: float) -> void:
	if GameState.phase != GameState.Phase.WORK or GameState.free_play():
		return
	for twist: String in GameState.new_twists():
		if _shown.has(twist) or not _shows.has(twist):
			continue
		for p: Player in get_tree().get_nodes_in_group("players"):
			if p.is_bot() and not p.downed and _shows[twist][0].call(p):
				_shown[twist] = true
				_point_at(p, tr("Watch the %s — %s") % [tr(p.trade_name()).to_lower(), tr(_shows[twist][1])])
				break

func _point_at(bot: Player, line: String) -> void:
	var tag := WorldTag.make(WorldTag.Kind.SHOUT, line)
	tag.position.y = LIFT
	tag.pulse = true
	bot.add_child(tag)
	var tw := tag.create_tween()
	tw.tween_interval(HOLD)
	tw.tween_property(tag, "modulate:a", 0.0, 0.6)
	tw.tween_callback(tag.queue_free)
	var alerts := get_tree().get_first_node_in_group("offscreen_alerts")
	if alerts:
		alerts.ping(bot.global_position, bot.slot_color, "Watch", HOLD)

static func _near_relay(b: Player) -> bool:
	for r: Node3D in b.get_tree().get_nodes_in_group("relay_mats"):
		if r.global_position.distance_to(b.global_position) < 3.0:
			return true
	return false
