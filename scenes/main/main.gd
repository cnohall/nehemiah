extends Node3D

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const HUD_SCENE    := preload("res://scenes/ui/game_hud.tscn")

@onready var players_root: Node3D          = $Players
@onready var enemies_root: Node3D          = $Enemies
@onready var camera: Camera3D             = $Camera3D
@onready var wave_manager: Node           = $WaveManager
@onready var nav_region: NavigationRegion3D = $NavRegion

var hud: CanvasLayer = null

func _ready() -> void:
	hud = HUD_SCENE.instantiate()
	add_child(hud)

	NetworkManager.peer_connected.connect(_on_peer_connected)
	NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
	GameState.game_won.connect(_on_game_won)
	GameState.game_lost.connect(_on_game_lost)

	wave_manager.enemy_died.connect(_on_enemy_count_changed)
	wave_manager.wave_cleared.connect(_on_wave_cleared)

	# Bake nav mesh after CSG/physics finishes initialising
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.make_current()
	call_deferred("_bake_nav")

	_spawn_player(multiplayer.get_unique_id())

	if multiplayer.is_server():
		wave_manager.start_wave(GameState.current_day)
	else:
		_request_roster.rpc_id(1)

# ── Spawning ───────────────────────────────────────────────

func _on_peer_connected(id: int) -> void:
	# All peers spawn the newly arrived player
	_spawn_player(id)

func _on_peer_disconnected(id: int) -> void:
	var node := players_root.get_node_or_null(str(id))
	if node:
		node.queue_free()
	GameState.remove_player(id)

func _spawn_player(peer_id: int) -> void:
	if players_root.has_node(str(peer_id)):
		return
	var player := PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)
	players_root.add_child(player)
	player.global_position = Vector3(0, 0.5, 0)
	GameState.register_player(peer_id, "Builder")

# ── Late-join roster sync (server → client) ────────────────

@rpc("any_peer", "reliable")
func _request_roster() -> void:
	if not multiplayer.is_server():
		return
	var caller := multiplayer.get_remote_sender_id()
	# Send every currently connected peer ID to the caller
	for peer_id in players_root.get_children().map(func(n): return int(n.name)):
		_receive_roster_entry.rpc_id(caller, peer_id)

@rpc("authority", "reliable")
func _receive_roster_entry(peer_id: int) -> void:
	_spawn_player(peer_id)

# ── Navigation ─────────────────────────────────────────────

func _bake_nav() -> void:
	nav_region.bake_navigation_mesh()

# ── Wave ───────────────────────────────────────────────────

func _on_enemy_count_changed() -> void:
	if hud:
		hud.set_enemy_count(wave_manager.get_alive_count())

func _on_wave_cleared() -> void:
	if multiplayer.is_server():
		GameState.advance_day()

# ── Win / Loss ─────────────────────────────────────────────

func _on_game_won() -> void:
	# TODO: show win screen
	pass

func _on_game_lost() -> void:
	# TODO: show loss screen
	pass
