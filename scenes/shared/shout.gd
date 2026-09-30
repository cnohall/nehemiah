class_name Shout
extends WorldTag

# A call from someone in the world — a watchman on his stand, the scribe at his desk
# (diegetic HUD). A parchment bubble over the speaker; while he's off-screen it slides in
# from the screen edge (WorldTag), so the call also points at where it came from.

const HOLD := 2.8

var _tween: Tween

static func make_shout() -> Shout:
	var s := Shout.new()
	s.kind = Kind.SHOUT
	s.visible = false
	return s

## Say `line` (already translated) for `hold` seconds; `urgent` makes it breathe
func say(line: String, hold := HOLD, urgent := false) -> void:
	text = line
	pulse = urgent
	visible = true
	if _tween:
		_tween.kill()
	modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.18)
	_tween.tween_interval(hold)
	_tween.tween_property(self, "modulate:a", 0.0, 0.5)
	_tween.tween_callback(hide)

func is_speaking() -> bool:
	return visible and _tween != null and _tween.is_running()
