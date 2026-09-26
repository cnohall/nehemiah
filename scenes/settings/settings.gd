extends Node

# Player preferences — persisted to user://settings.cfg and applied at boot.
# UI edits a field, then calls apply() + save().

const PATH := "user://settings.cfg"

var fullscreen := false
var vsync := true
var volume := 0.8   # master bus, linear 0..1
var music_volume := 0.6   # Music bus (created here), linear 0..1
var sfx_volume := 0.8     # SFX bus (created here) — effects + jingles, linear 0..1
var screen_shake := true
var rumble := true
var toggle_charge := false   # sling: press to start, press again to throw (instead of hold)
# Keyboard / mouse rebinds: action → {"key": physical keycode} or {"mouse": button index}.
# Only an action's primary key / mouse event is rebindable; pad remaps go through Steam Input.
var bindings := {}

const REBINDABLE := ["move_north", "move_west", "move_south", "move_east",
	"interact", "drop", "dash", "throw_charge", "horn"]

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		fullscreen = cfg.get_value("display", "fullscreen", fullscreen)
		vsync      = cfg.get_value("display", "vsync", vsync)
		volume     = cfg.get_value("audio", "volume", volume)
		music_volume = cfg.get_value("audio", "music_volume", music_volume)
		sfx_volume = cfg.get_value("audio", "sfx_volume", sfx_volume)
		screen_shake = cfg.get_value("display", "screen_shake", screen_shake)
		rumble = cfg.get_value("controls", "rumble", rumble)
		toggle_charge = cfg.get_value("controls", "toggle_charge", toggle_charge)
		bindings = cfg.get_value("controls", "bindings", bindings)
	_apply_bindings()
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var bus := AudioServer.bus_count - 1
			AudioServer.set_bus_name(bus, bus_name)
			AudioServer.set_bus_send(bus, "Master")
	apply()

func apply() -> void:
	# Embedded/headless runs have no real window to resize
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen
			else DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync
			else DisplayServer.VSYNC_DISABLED)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(0, volume <= 0.0)
	var music := AudioServer.get_bus_index("Music")
	AudioServer.set_bus_volume_db(music, linear_to_db(maxf(music_volume, 0.0001)))
	AudioServer.set_bus_mute(music, music_volume <= 0.0)
	var sfx := AudioServer.get_bus_index("SFX")
	AudioServer.set_bus_volume_db(sfx, linear_to_db(maxf(sfx_volume, 0.0001)))
	AudioServer.set_bus_mute(sfx, sfx_volume <= 0.0)

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "vsync", vsync)
	cfg.set_value("display", "screen_shake", screen_shake)
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("controls", "rumble", rumble)
	cfg.set_value("controls", "toggle_charge", toggle_charge)
	cfg.set_value("controls", "bindings", bindings)
	cfg.save(PATH)

# ── Bindings ───────────────────────────────────────────────

## First keyboard / mouse event on an action (what the hints show and rebinding replaces)
static func primary_event(action: String) -> InputEvent:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey or e is InputEventMouseButton:
			return e
	return null

## Put `event` on `action` as its primary. If another action already uses it, that
## action gets our old primary (a swap), so no binding is ever lost.
func rebind(action: String, event: InputEvent) -> void:
	var old := primary_event(action)
	for other: String in REBINDABLE:
		if other == action:
			continue
		for e in InputMap.action_get_events(other):
			if _same(e, event):
				if old != null and e == primary_event(other):
					_set_primary(other, old)
					bindings[other] = _encode(old)
				else:
					InputMap.action_erase_event(other, e)
	_set_primary(action, event)
	bindings[action] = _encode(event)
	save()

func reset_bindings() -> void:
	bindings.clear()
	# Only the rebindable actions; a full reload would drop the pad events InputMode adds
	for action: String in REBINDABLE:
		InputMap.action_erase_events(action)
		for e: InputEvent in ProjectSettings.get_setting("input/" + action)["events"]:
			InputMap.action_add_event(action, e)
	save()

func _apply_bindings() -> void:
	for action: String in bindings:
		if action in REBINDABLE:
			var e := _decode(bindings[action])
			if e != null:
				_set_primary(action, e)

func _set_primary(action: String, event: InputEvent) -> void:
	var events := InputMap.action_get_events(action)
	var old := primary_event(action)
	InputMap.action_erase_events(action)
	var placed := false
	for e in events:
		if e == old:
			InputMap.action_add_event(action, event)
			placed = true
		else:
			InputMap.action_add_event(action, e)
	if not placed:
		InputMap.action_add_event(action, event)

static func _same(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		return a.physical_keycode == b.physical_keycode
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return a.button_index == b.button_index
	return false

static func _encode(e: InputEvent) -> Dictionary:
	if e is InputEventKey:
		return {"key": e.physical_keycode}
	return {"mouse": e.button_index}

static func _decode(d: Dictionary) -> InputEvent:
	if d.has("key"):
		var k := InputEventKey.new()
		k.physical_keycode = d["key"]
		return k
	if d.has("mouse"):
		var m := InputEventMouseButton.new()
		m.button_index = d["mouse"]
		return m
	return null
