extends Node

const MAX_PLAYERS := 4
const DEFAULT_PORT  := 7350
const MENU_SCENE    := "res://scenes/ui/main_menu.tscn"

signal lobby_created
signal lobby_joined(success: bool)
signal peer_connected(id: int)
signal peer_disconnected(id: int)

# Peers whose game scene has loaded. Server-owned synchronizers filter on this so
# nothing replicates to a client still sitting in the menu (its nodes don't exist yet).
var _ready_peers: Dictionary = {}

# Connect once — reconnecting per host()/join() call errors on the second attempt
func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host(port: int = DEFAULT_PORT) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err  := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("NetworkManager: create_server failed (err %d)" % err)
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

func disconnect_session() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	_ready_peers.clear()

# ── Scene readiness (server) ───────────────────────────────

func mark_peer_ready(id: int) -> void:
	_ready_peers[id] = true

func is_peer_ready(id: int) -> bool:
	return _ready_peers.has(id)

# Gate a server-owned synchronizer on peer readiness. Call before the node enters
# the tree so a MultiplayerSpawner never spawns it on a peer that isn't ready.
func gate_sync(sync: MultiplayerSynchronizer) -> void:
	sync.add_visibility_filter(is_peer_ready)

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
