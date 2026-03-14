extends Node2D

var text: String = "":
	set(v):
		text = v
		_update_label()
var velocity := Vector2(0, -40)
var duration := 1.5
var _timer := 0.0
var _label: Label = null

func _ready() -> void:
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 14)
	add_child(_label)
	_update_label()

func _update_label() -> void:
	if _label:
		_label.text = text
		_label.position = Vector2(-_label.size.x * 0.5, 0)

func _process(delta: float) -> void:
	_timer += delta
	position += velocity * delta
	modulate.a = lerp(1.0, 0.0, _timer / duration)
	if _timer >= duration:
		queue_free()
