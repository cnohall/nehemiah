extends Node3D
class_name SupplyPile

@export var material_type: String = "stone" # "stone", "wood", "mortar"
@export var interact_range: float = 3.0

var _cut_stone_script   = preload("res://scenes/player/cut_stone.gd")
var _timber_beam_script = preload("res://scenes/player/timber_beam.gd")
var _mortar_bucket_script = preload("res://scenes/player/mortar_bucket.gd")

func _ready() -> void:
	add_to_group("supply_piles")
	_setup_visuals()

func _setup_visuals() -> void:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2, 1, 2)
	mesh_inst.mesh = box
	var mat := StandardMaterial3D.new()
	match material_type:
		"stone":  mat.albedo_color = Color(0.60, 0.60, 0.60)
		"wood":   mat.albedo_color = Color(0.40, 0.26, 0.13)
		"mortar": mat.albedo_color = Color(0.30, 0.30, 0.35)
	mesh_inst.material_override = mat
	add_child(mesh_inst)

	var label := Label3D.new()
	label.text = material_type.to_upper()
	label.position = Vector3(0, 1.4, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 32
	label.outline_size = 8
	add_child(label)

## Called by player pressing E near this pile.
## caller_id: the peer ID of the requesting player.
@rpc("any_peer", "call_local", "reliable")
func request_spawn_material(caller_id: int) -> void:
	if not multiplayer.is_server(): return
	# Reject if player is already carrying something
	var player = get_tree().current_scene.get_node_or_null("Players/" + str(caller_id))
	if player and player.get("carried_item") != null and player.carried_item != null:
		return
	var uid := "%d_%d" % [Time.get_ticks_msec(), randi() % 99999]
	_spawn_and_give_rpc.rpc(uid, caller_id)

## Runs on ALL peers — creates the carriable and instantly gives it to the player.
@rpc("authority", "call_local", "reliable")
func _spawn_and_give_rpc(uid: String, player_id: int) -> void:
	var material_node: Carriable = null
	match material_type:
		"stone":  material_node = _cut_stone_script.new()
		"wood":   material_node = _timber_beam_script.new()
		"mortar": material_node = _mortar_bucket_script.new()
	if not material_node: return

	material_node.name = "Carriable_" + uid
	get_tree().current_scene.add_child(material_node)
	material_node.global_position = global_position + Vector3(0, 1, 0)

	# Immediately give to the requesting player
	var player = get_tree().current_scene.get_node_or_null("Players/" + str(player_id))
	if player and player.get("carried_item") == null:
		material_node.pick_up(player)
		player.carried_item = material_node
		# Update the HUD carried label
		if player.has_method("_notify_carried_changed"):
			player._notify_carried_changed()
