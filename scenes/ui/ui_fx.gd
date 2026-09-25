class_name UiFx
extends RefCounted

# Small shared UI motion helpers. Ease-out only — nothing bounces.

static func fade_in(node: CanvasItem, dur := 0.3, delay := 0.0) -> Tween:
	node.modulate.a = 0.0
	var tw := node.create_tween()
	tw.tween_property(node, "modulate:a", 1.0, dur).set_delay(delay) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return tw

## Fade children in one after another (title-screen entrance)
static func stagger(nodes: Array, dur := 0.5, step := 0.07, delay := 0.0) -> void:
	for i in nodes.size():
		fade_in(nodes[i], dur, delay + i * step)

## Slide a free-positioned control in from `offset` while fading
static func rise_in(node: Control, offset := Vector2(0, 14), dur := 0.45, delay := 0.0) -> Tween:
	var target := node.position
	node.position = target + offset
	node.modulate.a = 0.0
	var tw := node.create_tween().set_parallel()
	tw.tween_property(node, "position", target, dur).set_delay(delay) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "modulate:a", 1.0, dur * 0.8).set_delay(delay)
	return tw
