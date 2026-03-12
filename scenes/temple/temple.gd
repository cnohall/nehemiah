extends StaticBody3D

signal destroyed

@export var health: float = 200.0
@onready var _mesh: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	add_to_group("temple")

func take_damage(amount: float) -> void:
	if not multiplayer.is_server(): return
	sync_damage.rpc(amount)

@rpc("authority", "call_local", "reliable")
func sync_damage(amount: float) -> void:
	health -= amount
	# Visual feedback: flash red
	if _mesh:
		var tween = create_tween()
		tween.tween_property(_mesh, "surface_material_override/0:albedo_color", Color.RED, 0.1)
		tween.tween_property(_mesh, "surface_material_override/0:albedo_color", Color(0.4, 0.35, 0.3), 0.1)
	
	if health <= 0:
		destroyed.emit()
		queue_free()
