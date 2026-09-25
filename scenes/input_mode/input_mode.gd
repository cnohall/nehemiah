extends Node

# Which device the local player last touched — keyboard/mouse or a gamepad. Drives the
# button hints on screen, stick vs cursor aiming, and rumble.

signal changed(using_pad: bool)

const STICK_WAKE := 0.4   # stick travel that counts as "picked up the pad" (ignores drift)

# Button / key label per action, for hints ("[E] to let go" → "[A] to let go")
const KEYS := {
	"move": "WASD", "interact": "E", "drop": "G", "dash": "Space",
	"throw": "Hold Click", "pause": "Esc",
}
const PAD := {
	"move": "L Stick", "interact": "A", "drop": "Y", "dash": "B",
	"throw": "Hold RT", "pause": "Start",
}

var using_pad := false

func _input(event: InputEvent) -> void:
	var pad := using_pad
	if event is InputEventJoypadButton:
		pad = true
	elif event is InputEventJoypadMotion:
		if absf(event.axis_value) > STICK_WAKE:
			pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		pad = false
	elif event is InputEventMouseMotion and event.relative.length() > 4.0:
		pad = false
	if pad != using_pad:
		using_pad = pad
		changed.emit(pad)

## Label for an action on the device in use: "E" or "A"
func key(action: String) -> String:
	return (PAD if using_pad else KEYS).get(action, action)

## Short rumble on the pad in use (no-op on keyboard)
func rumble(weak: float, strong: float, duration: float) -> void:
	if not using_pad:
		return
	for id in Input.get_connected_joypads():
		Input.start_joy_vibration(id, weak, strong, duration)
