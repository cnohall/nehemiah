extends Node

const MAX_PLAYERS := 4
const DEFAULT_PORT  := 7350
const MENU_SCENE    := "res://scenes/ui/main_menu.tscn"

# 480 = Valve's public "Spacewar" test app. Swap for the real app ID once
# Steamworks is set up — nothing else changes.
const STEAM_APP_ID := 480
# Lobby metadata key so our lobbies never mix with other Spacewar games
const LOBBY_TAG_KEY := "nehemiah"
const LOBBY_TAG_VAL := "1"
# Steam enum values (read from the extension; hardcoded so this script parses
# even when GodotSteam is absent)
const LOBBY_TYPE_FRIENDS_ONLY := 1
const STEAM_RESULT_OK         := 1
const LOBBY_ENTER_SUCCESS     := 1
const FRIEND_FLAG_IMMEDIATE   := 4
const PERSONA_OFFLINE         := 0
# Online room codes: 5 letters, no I/O so they read cleanly off a screen
const ROOM_CODE_LEN   := 5
const ROOM_CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ"
const ONLINE_SCRIPT   := "res://scenes/network_manager/webrtc_online.gd"
# Invite links: <page>?room=CODE joins straight from the menu (web build)
const ROOM_QUERY      := "room"

signal lobby_created
signal lobby_joined(success: bool)
signal host_failed(reason: String)
signal peer_connected(id: int)
signal peer_disconnected(id: int)

# Peers whose game scene has loaded. Server-owned synchronizers filter on this so
# nothing replicates to a client still sitting in the menu (its nodes don't exist yet).
var _ready_peers: Dictionary = {}

# GodotSteam singleton, or null when the extension is missing / Steam isn't running.
# Accessed dynamically so the project still runs without the addon.
var _steam: Object = null
# Why Steam init failed, shown in the menu so remote testers can report it
var _steam_error := ""
var _lobby_id := 0
var _hosting_lobby := false
# WebRTC room-code helper (webrtc_online.gd), or null where WebRTC is unavailable
var _online: Node = null
var _online_joining := false
# Why the last online host/join failed, for the menu
var last_error := ""

# Connect once — reconnecting per host()/join() call errors on the second attempt
func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_init_steam()
	_init_online()

# ── ENet (LAN / direct IP, headless tests) ─────────────────

func host(port: int = DEFAULT_PORT) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err  := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("NetworkManager: create_server failed (err %d)" % err)
		host_failed.emit("Could not open port %d." % port)
		return
	multiplayer.multiplayer_peer = peer
	lobby_created.emit()

func join(address: String, port: int = DEFAULT_PORT) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err  := peer.create_client(address, port)
	if err != OK:
		lobby_joined.emit(false)
		return
	multiplayer.multiplayer_peer = peer

# ── Steam (lobbies + relayed P2P, no port forwarding) ──────

func steam_available() -> bool:
	return _steam != null

func steam_error() -> String:
	return _steam_error

func steam_name() -> String:
	return _steam.getPersonaName() if _steam else ""

func in_steam_lobby() -> bool:
	return _lobby_id != 0

# Lobby id doubles as a join code for when the overlay isn't available
# (e.g. running from the editor)
func lobby_code() -> String:
	return str(_lobby_id) if _lobby_id else ""

func host_steam() -> void:
	if not _steam:
		host_failed.emit("Steam is not running.")
		return
	_hosting_lobby = true
	_steam.createLobby(LOBBY_TYPE_FRIENDS_ONLY, MAX_PLAYERS)

func join_steam(lobby_id: int) -> void:
	if not _steam:
		lobby_joined.emit(false)
		return
	_hosting_lobby = false
	_steam.joinLobby(lobby_id)

# Online Steam friends, those already in the game first. Used by the in-game
# invite list — the overlay invite dialog only works when Steam launched the exe.
func online_friends() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _steam:
		return out
	for i in _steam.getFriendCount(FRIEND_FLAG_IMMEDIATE):
		var id: int = _steam.getFriendByIndex(i, FRIEND_FLAG_IMMEDIATE)
		if _steam.getFriendPersonaState(id) == PERSONA_OFFLINE:
			continue
		var game: Dictionary = _steam.getFriendGamePlayed(id)
		out.append({ id = id, name = _steam.getFriendPersonaName(id),
			in_game = game.get("id", 0) == STEAM_APP_ID })
	out.sort_custom(func(a, b):
		if a.in_game != b.in_game:
			return a.in_game
		return a.name.naturalnocasecmp_to(b.name) < 0)
	return out

## Friends currently in a lobby of this game — one click to join from the menu
func friend_lobbies() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _steam:
		return out
	for i in _steam.getFriendCount(FRIEND_FLAG_IMMEDIATE):
		var id: int = _steam.getFriendByIndex(i, FRIEND_FLAG_IMMEDIATE)
		var game: Dictionary = _steam.getFriendGamePlayed(id)
		var lobby: int = game.get("lobby", 0)
		if game.get("id", 0) == STEAM_APP_ID and lobby != 0:
			out.append({ name = _steam.getFriendPersonaName(id), lobby = lobby })
	return out

## Steam's own invite dialog (works with a gamepad). False when the overlay is off.
func open_invite_overlay() -> bool:
	if not (_steam and _lobby_id) or not _steam.isOverlayEnabled():
		return false
	_steam.activateGameOverlayInviteDialog(_lobby_id)
	return true

# Sends a lobby invite via Steam chat; accepting it fires join_requested
func invite_friend(steam_id: int) -> bool:
	if not (_steam and _lobby_id):
		return false
	return _steam.inviteUserToLobby(_lobby_id, steam_id)

# ── Online rooms (WebRTC + room codes — browsers and desktop) ─

func online_available() -> bool:
	return _online != null

func in_online_room() -> bool:
	return _online != null and not _online.room_code.is_empty()

func room_code() -> String:
	return _online.room_code if _online else ""

## Page link that joins this room on open ("" outside the web build)
func invite_link() -> String:
	return WebPage.url_with(ROOM_QUERY, room_code()) if in_online_room() and WebPage.active() else ""

## Room code from an invite link the page was opened with, once ("" if none)
func take_invite_code() -> String:
	var code := WebPage.query(ROOM_QUERY).to_upper()
	if code.is_empty():
		return ""
	WebPage.clear_query(ROOM_QUERY)
	return code if is_room_code(code) else ""

static func is_room_code(text: String) -> bool:
	if text.length() != ROOM_CODE_LEN:
		return false
	for c in text.to_upper():
		if not ROOM_CODE_CHARS.contains(c):
			return false
	return true

func host_online() -> void:
	last_error = ""
	_online_joining = false
	_online.host()

func join_online(code: String) -> void:
	last_error = ""
	_online_joining = true
	_online.join(code)

func _init_online() -> void:
	if not preload(ONLINE_SCRIPT).available():
		return
	_online = preload(ONLINE_SCRIPT).new()
	_online.name = "Online"
	add_child(_online)
	_online.hosted.connect(func(peer: MultiplayerPeer):
		multiplayer.multiplayer_peer = peer
		lobby_created.emit())
	# lobby_joined(true) fires from connected_to_server once the data channels open
	_online.joined.connect(func(peer: MultiplayerPeer):
		multiplayer.multiplayer_peer = peer)
	_online.failed.connect(func(reason: String):
		last_error = reason
		disconnect_session()
		if _online_joining:
			lobby_joined.emit(false)
		else:
			host_failed.emit(reason))

# ── Session teardown ───────────────────────────────────────

func disconnect_session() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	# Offline peer, not null: a solo game started next still counts as the server
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_ready_peers.clear()
	if _online:
		_online.leave()
	if _steam and _lobby_id:
		_steam.leaveLobby(_lobby_id)
		_steam.clearRichPresence()
	_lobby_id = 0
	_hosting_lobby = false

# ── Scene readiness (server) ───────────────────────────────

func mark_peer_ready(id: int) -> void:
	_ready_peers[id] = true

func is_peer_ready(id: int) -> bool:
	return _ready_peers.has(id)

# Gate a server-owned synchronizer on peer readiness. Call before the node enters
# the tree so a MultiplayerSpawner never spawns it on a peer that isn't ready.
func gate_sync(sync: MultiplayerSynchronizer) -> void:
	sync.add_visibility_filter(is_peer_ready)

## Server → clients replication of `props` on `owner`, as a gated "Sync" child
func add_sync(owner: Node, props: Array[NodePath],
		mode := SceneReplicationConfig.REPLICATION_MODE_ALWAYS, interval := 0.1) -> MultiplayerSynchronizer:
	var cfg := SceneReplicationConfig.new()
	for prop in props:
		cfg.add_property(prop)
		cfg.property_set_replication_mode(prop, mode)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.replication_interval = interval
	sync.replication_config = cfg
	gate_sync(sync)
	owner.add_child(sync)
	return sync

# ── Signals ────────────────────────────────────────────────

func _on_peer_connected(id: int) -> void:
	peer_connected.emit(id)

func _on_peer_disconnected(id: int) -> void:
	_ready_peers.erase(id)
	peer_disconnected.emit(id)

func _on_connected_to_server() -> void:
	lobby_joined.emit(true)

func _on_connection_failed() -> void:
	disconnect_session()
	lobby_joined.emit(false)

# Host left — drop back to the menu instead of running against a dead peer
func _on_server_disconnected() -> void:
	disconnect_session()
	get_tree().change_scene_to_file(MENU_SCENE)

# ── Steam internals ────────────────────────────────────────

func _init_steam() -> void:
	if not Engine.has_singleton("Steam"):
		# Extension didn't load: DLLs missing next to the exe, or blocked by AV
		_steam_error = "Steam plugin failed to load"
		return
	var steam := Engine.get_singleton("Steam")
	# embed_callbacks = true: GodotSteam pumps run_callbacks() itself each frame
	var res: Dictionary = steam.steamInitEx(STEAM_APP_ID, true)
	if res.get("status", -1) != 0:
		_steam_error = "%s (code %d)" % [res.get("verbal", "?"), res.get("status", -1)]
		print("NetworkManager: Steam unavailable (%s) — LAN only" % _steam_error)
		return
	_steam = steam
	if _steam.has_method("initRelayNetworkAccess"):
		# Warm up the relay network now so the first connection isn't slow
		_steam.initRelayNetworkAccess()
	_steam.connect("lobby_created", _on_steam_lobby_created)
	_steam.connect("lobby_joined", _on_steam_lobby_joined)
	_steam.connect("join_requested", _on_steam_join_requested)
	# Launched by accepting an invite while the game was closed: "+connect_lobby <id>"
	var args := OS.get_cmdline_args()
	var i := args.find("+connect_lobby")
	if i != -1 and i + 1 < args.size() and args[i + 1].is_valid_int():
		join_steam.call_deferred(args[i + 1].to_int())

func _on_steam_lobby_created(result: int, lobby_id: int) -> void:
	if result != STEAM_RESULT_OK:
		_hosting_lobby = false
		host_failed.emit("Steam could not create a lobby (result %d)." % result)
		return
	_lobby_id = lobby_id
	_steam.setLobbyData(lobby_id, LOBBY_TAG_KEY, LOBBY_TAG_VAL)
	_steam.setLobbyData(lobby_id, "host_name", steam_name())
	_steam.setLobbyJoinable(lobby_id, true)
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	var err: int = peer.create_host(0)
	if err != OK:
		disconnect_session()
		host_failed.emit("Steam host socket failed (err %d)." % err)
		return
	multiplayer.multiplayer_peer = peer
	_set_presence()
	lobby_created.emit()

func _on_steam_lobby_joined(lobby_id: int, _perms: int, _locked: bool, response: int) -> void:
	# Fires for the creator too — the host path is finished in _on_steam_lobby_created
	if _hosting_lobby:
		return
	if response != LOBBY_ENTER_SUCCESS:
		lobby_joined.emit(false)
		return
	_lobby_id = lobby_id
	if _steam.getLobbyData(lobby_id, LOBBY_TAG_KEY) != LOBBY_TAG_VAL:
		disconnect_session()
		lobby_joined.emit(false)
		return
	var owner: int = _steam.getLobbyOwner(lobby_id)
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	var err: int = peer.create_client(owner, 0)
	if err != OK:
		disconnect_session()
		lobby_joined.emit(false)
		return
	multiplayer.multiplayer_peer = peer
	_set_presence()
	# lobby_joined(true) fires from connected_to_server once the socket is up

# Friend clicked "Join Game" in the overlay / friends list, or accepted an invite
func _on_steam_join_requested(lobby_id: int, _friend_id: int) -> void:
	if lobby_id == _lobby_id:
		return
	# Mid-game: leave the current session first. The menu picks up lobby_joined
	# and moves into Main, same as a normal join.
	var scene := get_tree().current_scene
	if scene and scene.scene_file_path != MENU_SCENE:
		disconnect_session()
		get_tree().change_scene_to_file(MENU_SCENE)
	join_steam(lobby_id)

# Rich presence "connect" makes "Join Game" appear on us in friends' lists
func _set_presence() -> void:
	_steam.setRichPresence("connect", "+connect_lobby %d" % _lobby_id)
	_steam.setRichPresence("status", "Building the wall")
