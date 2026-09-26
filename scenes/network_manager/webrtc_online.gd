extends Node

# Browser-friendly online play: WebRTC peer-to-peer with room codes.
# A small signaling server (server/server.js) hands out 5-letter room codes and
# relays the WebRTC handshake; game traffic then flows directly between players
# over DTLS data channels, so RPCs/synchronizers work exactly as with ENet or Steam.
#
# Star topology like the other backends: every joiner connects to the host (id 1)
# only — WebRTCMultiplayerPeer's server mode relays between clients.
#
# Browsers have WebRTC built in; desktop builds need addons/webrtc_native.
# Loaded by NetworkManager, which owns the MultiplayerPeer once we hand it over.

signal hosted(peer: MultiplayerPeer)
signal joined(peer: MultiplayerPeer)
signal failed(reason: String)

# Bump together with server.js PROTOCOL when the handshake or netcode changes
const PROTOCOL := 1
const SETTING_URL := "nehemiah/online/signaling_url"
const LOCAL_URL := "ws://localhost:8787/ws"
const CONNECT_TIMEOUT := 10.0   # signaling socket
const JOIN_TIMEOUT := 20.0      # code accepted → data channels open

enum { IDLE, CONNECTING, WAITING, IN_ROOM }

var room_code := ""
var error := ""

var _ws: WebSocketPeer
var _state := IDLE
var _want_host := false
var _join_code := ""
var _ice: Array = []
var _rtc: WebRTCMultiplayerPeer
var _deadline := 0.0

static func available() -> bool:
	if OS.has_feature("web"):
		return true
	return GDExtensionManager.is_extension_loaded("res://addons/webrtc_native/webrtc_native.gdextension")

## Signaling server: `-- --signal=URL`, then ?signal= on the web page, then the
## project setting, then (web) the server that served the page, else localhost.
static func signaling_url() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--signal="):
			return arg.trim_prefix("--signal=")
	var from_page := WebPage.query("signal")
	if not from_page.is_empty():
		return from_page
	var setting := str(ProjectSettings.get_setting(SETTING_URL, ""))
	if not setting.is_empty():
		return setting
	if OS.has_feature("web"):
		var origin := WebPage.origin()
		if origin.begins_with("http"):
			return origin.replace("http", "ws") + "/ws"
	return LOCAL_URL

func host() -> void:
	_start(true, "")

func join(code: String) -> void:
	_start(false, code.strip_edges().to_upper())

func leave() -> void:
	if _ws:
		_ws.close()
	_ws = null
	_rtc = null
	_state = IDLE
	room_code = ""
	set_process(false)

func _ready() -> void:
	set_process(false)

func _start(as_host: bool, code: String) -> void:
	leave()
	error = ""
	_want_host = as_host
	_join_code = code
	_ws = WebSocketPeer.new()
	var url := signaling_url()
	if _ws.connect_to_url(url) != OK:
		_fail("Could not reach the online server.")
		return
	_state = CONNECTING
	_deadline = _now() + CONNECT_TIMEOUT
	set_process(true)

func _process(_delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			while _ws and _ws.get_available_packet_count() > 0:
				var msg = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
				if msg is Dictionary:
					_handle(msg)
		WebSocketPeer.STATE_CLOSED:
			# After the room is set up the signaling link is only needed for new
			# joiners — losing it mid-game doesn't touch the P2P session
			if _state == IN_ROOM:
				push_warning("WebRtcOnline: signaling closed (%d)" % _ws.get_close_code())
				_ws = null
				set_process(false)
			else:
				_fail("Lost the online server." if _state != CONNECTING else "Could not reach the online server.")
			return
	if _state != IN_ROOM and _now() > _deadline:
		_fail("The online server didn't answer.")
	elif _state == IN_ROOM and not _want_host and _deadline > 0.0 and _now() > _deadline:
		if _rtc and _rtc.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			_fail("Couldn't connect to the host — one of your networks may block direct connections.")
		_deadline = 0.0

func _handle(msg: Dictionary) -> void:
	match msg.get("type", ""):
		"hello":
			_ice = msg.get("ice", [])
			_state = WAITING
			_send(
				{ type = "host", protocol = PROTOCOL } if _want_host
				else { type = "join", code = _join_code, protocol = PROTOCOL })
		"error":
			_fail(str(msg.get("error", "Online error.")))
		"hosted":
			room_code = str(msg.code)
			print("Online: opened room %s" % room_code)
			_rtc = WebRTCMultiplayerPeer.new()
			_rtc.create_server()
			_state = IN_ROOM
			hosted.emit(_rtc)
		"joined":
			room_code = str(msg.code)
			_rtc = WebRTCMultiplayerPeer.new()
			_rtc.create_client(int(msg.id))
			_add_connection(1)
			_state = IN_ROOM
			_deadline = _now() + JOIN_TIMEOUT
			joined.emit(_rtc)   # status CONNECTING; connected_to_server fires once open
		"peer_joined":
			var conn := _add_connection(int(msg.id))
			if conn:
				conn.create_offer()
		"peer_left":
			var id := int(msg.id)
			if _rtc and _rtc.has_peer(id) and not _rtc.get_peer(id).connected:
				_rtc.remove_peer(id)   # never made it in — connected peers drop via WebRTC itself
		"closed":
			if _rtc and _rtc.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
				_fail("The host closed the room.")
		"signal":
			_on_signal(msg)

func _add_connection(id: int) -> WebRTCPeerConnection:
	var conn := WebRTCPeerConnection.new()
	if conn.initialize({ "iceServers": _ice }) != OK:
		_fail("WebRTC is not available on this device.")
		return null
	conn.session_description_created.connect(func(type: String, sdp: String):
		conn.set_local_description(type, sdp)
		_send({ type = "signal", to = id, kind = type, sdp = sdp }))
	conn.ice_candidate_created.connect(func(mid: String, index: int, cand: String):
		_send({ type = "signal", to = id, kind = "candidate", mid = mid, index = index, cand = cand }))
	_rtc.add_peer(conn, id)
	return conn

func _on_signal(msg: Dictionary) -> void:
	var from := int(msg.get("from", 0))
	if _rtc == null or not _rtc.has_peer(from):
		return
	var conn: WebRTCPeerConnection = _rtc.get_peer(from).connection
	match str(msg.get("kind", "")):
		"offer", "answer":
			# Setting a remote offer makes the connection create our answer
			conn.set_remote_description(str(msg.kind), str(msg.get("sdp", "")))
		"candidate":
			conn.add_ice_candidate(str(msg.get("mid", "")), int(msg.get("index", 0)), str(msg.get("cand", "")))

func _send(msg: Dictionary) -> void:
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(msg))

func _fail(reason: String) -> void:
	error = reason
	var rtc := _rtc
	leave()
	if rtc:
		rtc.close()
	failed.emit(reason)

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
