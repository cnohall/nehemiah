extends "res://scenes/player/carriable.gd"
class_name CutStone

func _init() -> void:
	material_name = "Cut Stone"
	speed_penalty = 0.4 # 40% slower
	color = Color(0.6, 0.6, 0.6) # Gray
