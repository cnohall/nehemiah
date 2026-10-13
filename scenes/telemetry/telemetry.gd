extends Node

# Anonymous play stats (GDD §5.24, PLAYTEST_4): where do strangers stop?
# Web builds only. A few small beacons go to the game's own Worker (POST /t), each saying
# where on the circuit this session is. Nothing that names anyone: no account, no address,
# no id kept on the device (the session id is made fresh at each page load), nothing read
# from the player. Settings → Advanced → Play stats turns it off.
#
# The last beacon before silence is where the session stopped. Closing a tab never runs
# _exit_tree, so a heartbeat every BEAT seconds (and a beacon when the tab is hidden) does
# the job sessions.log can't.

const URL := "/t"
const BEAT := 30.0
const MAX_SENT := 600   # per page load; the Worker holds its own cap

# Tests: given each JSON body instead of the browser (also makes available() true)
var transport := Callable()

var _sid := ""
var _t0 := 0
var _sent := 0
var _vis_cb: JavaScriptObject   # kept: a callback nobody holds is freed

func _ready() -> void:
	var crypto := Crypto.new()
	_sid = crypto.generate_random_bytes(6).hex_encode()
	_t0 = Time.get_ticks_msec()
	GameState.phase_changed.connect(func(_p): event("phase"))
	var beat := Timer.new()
	beat.wait_time = BEAT
	beat.timeout.connect(func(): event("beat"))
	add_child(beat)
	beat.start()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__nt=function(b){try{navigator.sendBeacon('%s',b)}catch(e){}}" % URL, true)
		_vis_cb = JavaScriptBridge.create_callback(_on_visibility)
		JavaScriptBridge.get_interface("document").addEventListener("visibilitychange", _vis_cb)
	# Deferred: Settings has loaded, and the first scene has a name by then
	event.call_deferred("open")

## Stats can leave this device at all (the web build, or a test with a transport)
func available() -> bool:
	return OS.has_feature("web") or transport.is_valid()

func _on() -> bool:
	if not Settings.share_stats or _sent >= MAX_SENT:
		return false
	if transport.is_valid():
		return true
	# Test harnesses (`--script`) aren't players
	return OS.has_feature("web") and not "--script" in OS.get_cmdline_args()

## On the title screen: the bot crew playing behind the menu (attract mode) is not a game
func _on_title() -> bool:
	var scene := get_tree().current_scene
	return GameState.attract or (scene != null and scene.name == "MainMenu")

func event(kind: String) -> void:
	# Phases flip all day behind the title; only a player's game says anything
	if kind == "phase" and _on_title():
		return
	if not _on():
		return
	_sent += 1
	var body := JSON.stringify(snapshot(kind))
	if transport.is_valid():
		transport.call(body)
	elif OS.has_feature("web"):
		JavaScriptBridge.get_interface("window").__nt(body)

## What one beacon says. Short keys: it goes out often.
func snapshot(kind: String) -> Dictionary:
	var scene := get_tree().current_scene
	var d := {
		"k": kind,
		"s": _sid,
		"t": (Time.get_ticks_msec() - _t0) / 1000,
		"sc": scene.name if scene != null else "",
		"mode": _mode(),
		"sec": 0, "day": 0, "ph": "GATHER", "done": 0, "tot": 0, "br": 0, "crew": 0,
		"simple": 1 if Settings.simple_game else 0,
		"fps": roundi(Engine.get_frames_per_second()),
		"lang": Settings.current_language(),
	}
	if not _on_title():
		d["sec"] = GameState.current_section_index
		d["day"] = GameState.current_day
		d["ph"] = GameState.Phase.keys()[GameState.phase]
		d["done"] = GameState.targets_done
		d["tot"] = GameState.targets_total
		d["br"] = GameState.breaches
		d["crew"] = GameState.crew_size
		d["simple"] = 1 if GameState.simplified() else 0
	if kind == "open":
		var size := get_viewport().get_visible_rect().size
		d["vw"] = roundi(size.x)
		d["vh"] = roundi(size.y)
	return d

func _mode() -> String:
	if GameState.tutorial:
		return "tutorial"
	if GameState.festival:
		return "explore"
	if GameState.replay_section >= 0:
		return "replay"
	return "campaign"

func _on_visibility(_args: Array) -> void:
	var state = JavaScriptBridge.get_interface("document").visibilityState
	event("hide" if str(state) == "hidden" else "show")
