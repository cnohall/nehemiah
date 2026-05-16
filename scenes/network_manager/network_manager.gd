extends Node

const MAX_PLAYERS := 4
const DEFAULT_PORT  := 7350

signal lobby_created
signal lobby_joined(success: bool)
signal peer_connected(id: int)
signal peer_disconnected(id: int)

func host(port: int = DEFAULT_PORT) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err  := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("NetworkManager: create_server failed (err %d)" % err)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	emit_signal("lobby_created")

func join(address: String, port: int = DEFAULT_PORT) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err  := peer.create_client(address, port)
	if err != OK:
		emit_signal("lobby_joined", false)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)

func disconnect_session() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null

func _on_peer_connected(id: int) -> void:
	emit_signal("peer_connected", id)

func _on_peer_disconnected(id: int) -> void:
	emit_signal("peer_disconnected", id)

func _on_connected_to_server() -> void:
	emit_signal("lobby_joined", true)

func _on_connection_failed() -> void:
	emit_signal("lobby_joined", false)
