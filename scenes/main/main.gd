extends Node3D

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const HUD_SCENE    := preload("res://scenes/ui/game_hud.tscn")
const CAM_OFFSET   := Vector3(20.0, 20.0, 20.0)
const CAM_SMOOTH   := 6.0
const HUD_INTERVAL := 0.1
# Player ring / HUD colours by join order: amber, olive, terracotta, sky
const PLAYER_COLORS := [Color(0.93, 0.66, 0.22), Color(0.52, 0.70, 0.28), Color(0.86, 0.38, 0.26), Color(0.38, 0.62, 0.86)]

@onready var players_root: Node3D           = $Players
@onready var enemies_root: Node3D           = $Enemies
@onready var camera: Camera3D               = $Camera3D
@onready var director: Node                 = $DayDirector

var hud: CanvasLayer = null
var _cam_snapped := false
var _hud_timer := 0.0

func _ready() -> void:
	hud = HUD_SCENE.instantiate()
	add_child(hud)

	NetworkManager.peer_connected.connect(_on_peer_connected)
	NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
	GameState.game_won.connect(_on_game_won)
	GameState.game_lost.connect(_on_game_lost)

	camera.size = 24.0
	camera.look_at(Vector3(0, 0, 2), Vector3.UP)
	camera.make_current()

	_spawn_player(multiplayer.get_unique_id())

	if multiplayer.is_server():
		director.start()
	else:
		_request_roster.rpc_id(1)

func _process(delta: float) -> void:
	_follow_local_player(delta)
	_hud_timer -= delta
	if _hud_timer <= 0.0:
		_hud_timer = HUD_INTERVAL
		_refresh_hud()

func _follow_local_player(delta: float) -> void:
	var local_player: Node3D = players_root.get_node_or_null(str(multiplayer.get_unique_id()))
	if local_player == null:
		return
	var p := local_player.global_position
	var desired := Vector3(p.x + CAM_OFFSET.x, CAM_OFFSET.y, p.z + CAM_OFFSET.z)
	if not _cam_snapped:
		# Snap on first frame instead of swooping in from the scene origin
		camera.global_position = desired
		_cam_snapped = true
	else:
		camera.global_position = camera.global_position.lerp(desired, delta * CAM_SMOOTH)

# ── HUD ────────────────────────────────────────────────────

func _refresh_hud() -> void:
	if hud == null:
		return
	# Enemies replicate to every peer, so the child count is valid on clients too
	var alive := 0
	for e in enemies_root.get_children():
		if not e.is_queued_for_deletion():
			alive += 1
	hud.set_enemy_count(alive)

	var players := _sorted_players()
	var local_name := str(multiplayer.get_unique_id())
	for slot in 4:
		if slot < players.size():
			var pl = players[slot]
			hud.set_player_present(slot, true, pl.name == local_name)
			hud.set_player_health(slot, pl.health / pl.MAX_HEALTH)
			hud.set_player_carry(slot, "Downed" if pl.downed else pl.carried_kind.capitalize())
		else:
			hud.set_player_present(slot, false, false)

# ── Spawning ───────────────────────────────────────────────

func _on_peer_connected(id: int) -> void:
	# All peers spawn the newly arrived player
	_spawn_player(id)

func _on_peer_disconnected(id: int) -> void:
	var node := players_root.get_node_or_null(str(id))
	if node:
		players_root.remove_child(node)
		node.queue_free()
	GameState.remove_player(id)
	_assign_colors()
	if multiplayer.is_server():
		GameState.set_crew(players_root.get_child_count())

func _spawn_player(peer_id: int) -> void:
	if players_root.has_node(str(peer_id)):
		return
	var player := PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)
	players_root.add_child(player)
	player.global_position = player.RESPAWN_POS
	GameState.register_player(peer_id, "Builder")
	_assign_colors()
	if multiplayer.is_server():
		GameState.set_crew(players_root.get_child_count())

# Sorted by peer id so every peer agrees on slot → colour
func _sorted_players() -> Array:
	var players := players_root.get_children()
	players.sort_custom(func(a, b): return int(a.name) < int(b.name))
	return players

func _assign_colors() -> void:
	var players := _sorted_players()
	for slot in players.size():
		var c: Color = PLAYER_COLORS[slot % PLAYER_COLORS.size()]
		players[slot].set_slot(slot, c)
		if hud:
			hud.set_player_color(slot, c)

# ── Late-join roster sync (server → client) ────────────────

# Sent by a client once its Main scene exists — also the signal that it's safe
# to start replicating server-owned nodes (enemies, wall state) to that peer.
@rpc("any_peer", "reliable")
func _request_roster() -> void:
	if not multiplayer.is_server():
		return
	var caller := multiplayer.get_remote_sender_id()
	for peer_id in players_root.get_children().map(func(n): return int(n.name)):
		_receive_roster_entry.rpc_id(caller, peer_id)
	# Players now exist on the caller (reliable RPCs arrive in order), so it may see them
	NetworkManager.mark_peer_ready(caller)
	# Per-player state the roster doesn't carry (what they hold, downed, health)
	for p in players_root.get_children():
		p.send_status_to(caller)
	GameState.send_state_to(caller)

@rpc("authority", "reliable")
func _receive_roster_entry(peer_id: int) -> void:
	_spawn_player(peer_id)

# ── Win / Loss ─────────────────────────────────────────────

# HUD shows the end screen; stop the fight underneath it
func _on_game_won() -> void:
	get_tree().call_group("enemies", "set_physics_process", false)

func _on_game_lost() -> void:
	get_tree().call_group("enemies", "set_physics_process", false)
