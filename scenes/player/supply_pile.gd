class_name SupplyPile
extends Node2D

@export var material_type: String = "stone" # "stone", "wood", "mortar"
@export var interact_range: float = 3.0

var _material_script: GDScript = preload("res://scenes/player/material_item.gd")

# Visual colors per type
const COLORS := {
	"stone":  Color(0.60, 0.60, 0.60),
	"wood":   Color(0.40, 0.26, 0.13),
	"mortar": Color(0.30, 0.30, 0.35),
}

func _ready() -> void:
	add_to_group("supply_piles")
	queue_redraw()

func _draw() -> void:
	var c: Color = COLORS.get(material_type, Color.WHITE)
	# Draw pile as stacked circles
	draw_circle(Vector2(-4, 3), 5.0, c * 0.85)
	draw_circle(Vector2(4, 3), 5.0, c * 0.85)
	draw_circle(Vector2(0, -2), 6.0, c)
	draw_circle(Vector2(0, -2), 6.0, Color(0, 0, 0, 0.25), false, 1.0)
	# Label drawn in world space (small text)

## Called by player pressing E near this pile.
## caller_id: the peer ID of the requesting player.
@rpc("any_peer", "call_local", "reliable")
func request_spawn_material(caller_id: int) -> void:
	if not multiplayer.is_server():
		return
	# Reject if player is already carrying something
	var player = get_tree().current_scene.get_node_or_null("Players/" + str(caller_id))
	if player and player.get("carried_item") != null and player.carried_item != null:
		return
	var uid := "%d_%d" % [Time.get_ticks_msec(), randi() % 99999]
	_sync_give_material.rpc(uid, caller_id)

## Runs on ALL peers — creates the carriable and instantly gives it to the player.
@rpc("authority", "call_local", "reliable")
func _sync_give_material(uid: String, player_id: int) -> void:
	var material_node: MaterialItem = _material_script.new()
	match material_type:
		"stone":
			material_node.material_type = MaterialItem.Type.STONE
		"wood":
			material_node.material_type = MaterialItem.Type.WOOD
		"mortar":
			material_node.material_type = MaterialItem.Type.MORTAR

	if not material_node:
		return

	material_node.name = "Carriable_" + uid
	get_tree().current_scene.add_child(material_node)
	material_node.global_position = global_position

	# Immediately give to the requesting player
	var player = get_tree().current_scene.get_node_or_null("Players/" + str(player_id))
	if player and player.get("carried_item") == null:
		material_node.pick_up(player)
		player.carried_item = material_node
		if player.has_method("_notify_carried_changed"):
			player._notify_carried_changed()
