extends SceneTree

# Anonymous play stats (Telemetry), without a browser:
#   Godot --headless --path . --script res://tools/telemetry_test.gd
# A transport stands in for the web build's sendBeacon. Checks: nothing leaves a desktop
# build; a phase change and a heartbeat each send one small beacon that says where the game
# is and nothing else; the off switch silences it; modes read right; the per-page cap holds.
# Exit code 0 = every check passed.

# The only keys a beacon may carry (the Worker's allow-list in worker/src/stats.js matches)
const ALLOWED := ["k", "s", "t", "sc", "mode", "sec", "day", "ph", "done", "tot", "br", "crew",
	"simple", "fps", "lang", "vw", "vh"]

var _fails := 0
var _got: Array[Dictionary] = []

func _process(_delta: float) -> bool:
	var tel = root.get_node("Telemetry")
	var gs = root.get_node("GameState")
	var settings = root.get_node("Settings")
	gs.reset()
	settings.share_stats = true

	_check(not tel.available(), "no transport, not the web: nothing can leave")
	tel.event("beat")
	_check(_got.is_empty(), "…and nothing did")

	tel.transport = func(body: String): _got.append(JSON.parse_string(body))
	_check(tel.available(), "a transport makes it available")

	gs._set_state(5, 1, gs.Phase.WORK, 0, 2, 6)
	_check(_got.size() == 1 and _got[0]["k"] == "phase", "a phase change sends one beacon")
	var b: Dictionary = _got[0]
	_check(b["sec"] == 1 and b["day"] == 5 and b["ph"] == "WORK", "…saying section 1, day 5, WORK")
	_check(b["done"] == 2 and b["tot"] == 6 and b["br"] == 0, "…and 2 of 6 pieces, no breaches")
	_check(b["mode"] == "campaign" and b["simple"] == 0, "…a campaign in the full game")
	_check(str(b["s"]).length() == 12, "…with a 12-character session id")

	_got.clear()
	gs._set_state(5, 1, gs.Phase.WORK, 1, 3, 6)
	_check(_got.is_empty(), "progress and a breach alone send nothing (only phases and the heartbeat do)")

	tel.event("beat")
	_check(_got.size() == 1 and _got[0]["k"] == "beat" and _got[0]["br"] == 1 and _got[0]["done"] == 3,
		"the heartbeat carries the latest state")

	tel.event("open")
	var open: Dictionary = _got[-1]
	_check(open.has("vw") and open.has("vh"), "the first beacon also gives the window size")
	_check(not _got[-2].has("vw"), "…and later ones don't")

	for beacon in _got:
		for key: String in beacon:
			_check(key in ALLOWED, "beacon key '%s' is on the allow-list" % key)
		_check(JSON.stringify(beacon).length() < 300, "a beacon stays small (%d bytes)" % JSON.stringify(beacon).length())

	# Modes
	gs.tutorial = true
	_got.clear()
	tel.event("beat")
	_check(_got[0]["mode"] == "tutorial", "the practice reads as tutorial")
	gs.tutorial = false
	gs.festival = true
	_got.clear()
	tel.event("beat")
	_check(_got[0]["mode"] == "explore", "Explore Jerusalem reads as explore")
	gs.festival = false
	gs.replay_section = 3
	_got.clear()
	tel.event("beat")
	_check(_got[0]["mode"] == "replay", "a section replay reads as replay")
	gs.replay_section = -1

	# The simple game
	settings.simple_game = true
	_got.clear()
	tel.event("beat")
	_check(_got[0]["simple"] == 1, "the simple game is flagged")
	settings.simple_game = false

	# The off switch
	settings.share_stats = false
	_got.clear()
	tel.event("beat")
	gs._set_state(6, 1, gs.Phase.DUSK, 1, 6, 6)
	_check(_got.is_empty(), "Play stats off: nothing is sent, phases included")
	settings.share_stats = true

	# The per-page cap
	tel._sent = tel.MAX_SENT - 1
	_got.clear()
	tel.event("beat")
	tel.event("beat")
	_check(_got.size() == 1, "the per-page cap stops the flood (%d sent)" % _got.size())

	# Behind the title the bot crew plays on (attract mode): no phase beacons, no game state
	tel._sent = 0
	gs.attract = true
	gs._set_state(24, 5, gs.Phase.DAWN, 3, 4, 6)
	_got.clear()
	gs._set_state(24, 5, gs.Phase.WORK, 3, 4, 6)
	_check(_got.is_empty(), "attract mode: a phase flip sends nothing")
	tel.event("beat")
	_check(_got.size() == 1 and _got[0]["sec"] == 0 and _got[0]["day"] == 0 and _got[0]["ph"] == "GATHER"
		and _got[0]["br"] == 0 and _got[0]["crew"] == 0, "attract mode: a heartbeat says nothing about the game")
	gs.attract = false

	# The Privacy row on the Advanced page: built only when stats can leave, flips the setting.
	# (The panel saves settings.cfg on a toggle: keep the player's own.)
	var cfg_path: String = settings.PATH
	var had := FileAccess.file_exists(cfg_path)
	var backup := FileAccess.get_file_as_bytes(cfg_path) if had else PackedByteArray()
	var panel: Control = load("res://scenes/ui/settings_panel.tscn").instantiate()
	root.add_child(panel)
	panel.open()
	_check(panel._stats_on != null and panel._stats_off != null, "the Play stats row is built")
	_check(panel._stats_on.button_pressed and not panel._stats_off.button_pressed, "…showing On")
	panel._stats_off.pressed.emit()
	_check(not settings.share_stats, "Off turns the setting off")
	panel.open()
	_check(panel._stats_off.button_pressed, "…and reopening shows Off")
	panel._stats_on.pressed.emit()
	_check(settings.share_stats, "On turns it back on")
	panel.queue_free()
	if had:
		var f := FileAccess.open(cfg_path, FileAccess.WRITE)
		f.store_buffer(backup)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg_path))
	settings.share_stats = true

	print("RESULT: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)
	return true

func _check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok:
		_fails += 1
