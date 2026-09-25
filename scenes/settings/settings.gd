extends Node

# Player preferences — persisted to user://settings.cfg and applied at boot.
# UI edits a field, then calls apply() + save().

const PATH := "user://settings.cfg"

var fullscreen := false
var vsync := true
var volume := 0.8   # master bus, linear 0..1

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		fullscreen = cfg.get_value("display", "fullscreen", fullscreen)
		vsync      = cfg.get_value("display", "vsync", vsync)
		volume     = cfg.get_value("audio", "volume", volume)
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

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "vsync", vsync)
	cfg.set_value("audio", "volume", volume)
	cfg.save(PATH)
