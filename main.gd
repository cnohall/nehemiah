extends Node3D
## Main scene controller
## ─────────────────────────────────────────────────────────────────────────────
## Spawning strategy: fully manual — no MultiplayerSpawner auto-replication.
##
## Why: MultiplayerSynchronizer sends sync data on an unreliable UDP channel.
## MultiplayerSpawner sends spawn messages on a reliable channel. With auto-
## spawning, sync packets for Players/1 arrive on the client before the spawn
## packet creates the node, causing "Node not found" errors.
##
## Fix: All peers spawn all player nodes manually. `peer_connected` fires in
## the same engine frame as the connection is established — before any network
## packets from the remote peer can arrive. So by spawning in response to
## `peer_connected`, the node always exists when the first sync packet lands.
## ─────────────────────────────────────────────────────────────────────────────


const PLAYER_SCENE: PackedScene = preload("res://player.tscn")

@onready var _players: Node3D  = $Players
@onready var _camera:  Camera3D = $Camera3D

var _local_player: CharacterBody3D = null


# ══════════════════════════════════════════════════════════════════════════════
# PROCESS — camera follow
# ══════════════════════════════════════════════════════════════════════════════

func _process(_delta: float) -> void:
	if not is_instance_valid(_local_player):
		for child in _players.get_children():
			if child is CharacterBody3D and child.is_multiplayer_authority():
				_local_player = child
				break

	if is_instance_valid(_local_player):
		_camera.global_position = _local_player.global_position + Vector3(6, 10, 6)


# ══════════════════════════════════════════════════════════════════════════════
# READY
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	NetworkManager.lobby_created_success.connect(_on_lobby_created_success)
	NetworkManager.lobby_joined_success.connect(_on_lobby_joined_success)
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)


# ══════════════════════════════════════════════════════════════════════════════
# NETWORK SIGNAL HANDLERS
# ══════════════════════════════════════════════════════════════════════════════

func _on_lobby_created_success(_lobby_id: int) -> void:
	_spawn_player(1)  # host peer ID is always 1


func _on_lobby_joined_success(_lobby_id: int) -> void:
	# peer_connected(1) fires this same frame and spawns the host's player.
	# Request the full roster so we also get any other existing players and
	# our own entry once the server has processed our connection.
	_request_roster.rpc_id(1)


func _on_player_connected(peer_id: int) -> void:
	# ALL peers spawn the node immediately in response to the connection event.
	# This fires in the same engine frame as the TCP handshake, before any
	# UDP sync packets from the remote peer can arrive.
	_spawn_player(peer_id)


func _on_player_disconnected(peer_id: int) -> void:
	var node := _players.get_node_or_null(str(peer_id))
	if is_instance_valid(node):
		node.queue_free()


# ══════════════════════════════════════════════════════════════════════════════
# ROSTER RPC — ensures clients have all pre-existing players
# ══════════════════════════════════════════════════════════════════════════════

## Client → Server: "send me all current peer IDs"
@rpc("any_peer", "reliable")
func _request_roster() -> void:
	if not multiplayer.is_server():
		return
	var requester := multiplayer.get_remote_sender_id()
	var ids: Array = []
	for child in _players.get_children():
		ids.append(int(child.name))
	_receive_roster.rpc_id(requester, ids)


## Server → Client: "here are all current peer IDs"
@rpc("authority", "reliable")
func _receive_roster(ids: Array) -> void:
	for id in ids:
		_spawn_player(int(id))  # duplicate guard inside handles already-existing nodes


# ══════════════════════════════════════════════════════════════════════════════
# SPAWN HELPER
# ══════════════════════════════════════════════════════════════════════════════

func _spawn_player(peer_id: int) -> void:
	var node_name := str(peer_id)
	if _players.has_node(node_name):
		return

	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	player.name = node_name
	player.camera_path = NodePath("")
	player.position = Vector3(0, 1.5, 0)
	# Set authority BEFORE add_child so _ready() in player.gd sees it correctly.
	player.set_multiplayer_authority(peer_id)
	_players.add_child(player, true)
