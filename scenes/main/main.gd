extends Node3D

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const HUD_SCENE    := preload("res://scenes/ui/game_hud.tscn")
const CAM_OFFSET   := Vector3(20.0, 20.0, 20.0)
const CAM_SMOOTH   := 6.0
const CAM_SIZE     := 18.0   # closer than true "strategy" framing: the crew reads as characters
# Camera leads a little into the direction of travel so you see where you're going
const LOOK_AHEAD      := 0.3    # seconds of velocity
const LOOK_AHEAD_MAX  := 2.5    # metres
const LOOK_AHEAD_EASE := 2.5
# Screen shake: trauma (0..1) decays; offset grows with trauma² so small bumps stay small
const SHAKE_MAX_OFFSET := 0.45
const SHAKE_DECAY      := 2.2
const SHAKE_FREQ       := 22.0
const HUD_INTERVAL := 0.1
# Dusk: the last stone lands in slow motion, the light turns gold, the camera leans in
const DUSK_SLOWMO      := 0.3    # time scale…
const DUSK_SLOWMO_TIME := 0.5    # …for this many real seconds
const DUSK_CAM_SIZE    := 15.5
const DUSK_SUN_COLOR   := Color(1.0, 0.74, 0.5)
const DUSK_SUN_ENERGY  := 1.45
const LIGHT_FADE       := 1.6
# Player ring / HUD colours by join order: amber, olive, terracotta, sky
const PLAYER_COLORS := Palette.CREW
# Title-screen backdrop (GameState.attract)
const ATTRACT_LEAD     := 6.0    # metres the camera sits left of the crew, so they land right of the menu
const ATTRACT_SMOOTH   := 0.35   # a slow, drifting follow — never a snap to one worker's dash

@onready var players_root: Node3D           = $Players
@onready var enemies_root: Node3D           = $Enemies
@onready var camera: Camera3D               = $Camera3D
@onready var director: Node                 = $DayDirector
@onready var sun: DirectionalLight3D        = $Sun

var hud: CanvasLayer = null
var story: StoryPlayer = null
var credits: CreditsRoll = null
var _cam_snapped := false
var _cam_base := Vector3.ZERO
var _lead := Vector3.ZERO
var _trauma := 0.0
var _shake_t := 0.0
var _hud_timer := 0.0
var _day_sun_color: Color
var _day_sun_energy: float
var _mood_tween: Tween

func _ready() -> void:
	add_to_group("camera_rig")
	if GameState.attract:
		_start_attract()
		return
	hud = HUD_SCENE.instantiate()
	add_child(hud)
	hud.begin_requested.connect(director.begin)
	hud.bots_changed.connect(fit_bots)
	director.day_tallied.connect(hud.show_tally)
	director.day_tallied.connect(SteamAchievements.on_day_tallied)
	_day_sun_color = sun.light_color
	_day_sun_energy = sun.light_energy
	GameState.phase_changed.connect(_on_phase_changed)

	story = StoryPlayer.new()
	add_child(story)
	director.story_started.connect(func(day: int): story.play(StoryData.slides_for_day(day)))
	director.story_waiting_changed.connect(story.set_waiting)
	director.story_ended.connect(story.close)
	story.finished.connect(_on_story_finished)
	story.start_now_requested.connect(director.force_story_end)
	# After the ending story: the credits, then the end screen
	credits = CreditsRoll.new()
	add_child(credits)
	credits.finished.connect(hud.show_end.bind(true))

	NetworkManager.peer_connected.connect(_on_peer_connected)
	NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
	GameState.game_lost.connect(_on_game_lost)

	camera.size = CAM_SIZE
	camera.look_at(Vector3(0, 0, 2), Vector3.UP)
	camera.make_current()

	_spawn_player(multiplayer.get_unique_id())

	if multiplayer.is_server():
		director.start()
		fit_bots()
	else:
		_request_roster.rpc_id(1)

func _process(delta: float) -> void:
	if GameState.attract:
		_frame_crew(delta)
		return
	_follow_local_player(delta)
	_hud_timer -= delta
	if _hud_timer <= 0.0:
		_hud_timer = HUD_INTERVAL
		_refresh_hud()

# ── Attract (title screen) ─────────────────────────────────

# The menu's live backdrop: a full crew of bots works the campaign from day 1 with no
# one to follow — no HUD, no story, no local player. The camera keeps the crew right
# of centre, where the menu's veil is clear.
func _start_attract() -> void:
	_day_sun_color = sun.light_color
	_day_sun_energy = sun.light_energy
	GameState.phase_changed.connect(_on_phase_changed)
	$PostFX.hide()   # the menu lays its own veil over the world
	camera.size = CAM_SIZE
	camera.look_at(Vector3(0, 0, 2), Vector3.UP)
	camera.make_current()
	director.start()
	GameState.apply_attract_start()
	fit_bots(NetworkManager.MAX_PLAYERS)
	director.begin()

func _frame_crew(delta: float) -> void:
	var crew := players_root.get_children()
	if crew.is_empty():
		return
	var mid := Vector3.ZERO
	for p: Node3D in crew:
		mid += p.global_position
	mid /= crew.size()
	var right := Vector3(camera.global_basis.x.x, 0.0, camera.global_basis.x.z).normalized()
	var p := mid - right * ATTRACT_LEAD
	var desired := Vector3(p.x + CAM_OFFSET.x, CAM_OFFSET.y, p.z + CAM_OFFSET.z)
	if not _cam_snapped:
		_cam_base = desired
		_cam_snapped = true
	else:
		_cam_base = _cam_base.lerp(desired, minf(1.0, delta * ATTRACT_SMOOTH))
	camera.global_position = _cam_base

func _follow_local_player(delta: float) -> void:
	var local_player := Player.local
	if local_player == null:
		return
	var vel: Vector3 = local_player.velocity
	var lead := Vector3(vel.x, 0.0, vel.z) * LOOK_AHEAD
	_lead = _lead.lerp(lead.limit_length(LOOK_AHEAD_MAX), minf(1.0, delta * LOOK_AHEAD_EASE))
	var p := local_player.global_position + _lead
	var desired := Vector3(p.x + CAM_OFFSET.x, CAM_OFFSET.y, p.z + CAM_OFFSET.z)
	if not _cam_snapped:
		# Snap on first frame instead of swooping in from the scene origin
		_cam_base = desired
		_cam_snapped = true
	else:
		_cam_base = _cam_base.lerp(desired, delta * CAM_SMOOTH)
	camera.global_position = _cam_base + _shake_offset(delta)

## Local screen shake — hits, crumbling walls. Amount adds up, capped at 1.
func shake(amount: float) -> void:
	if Settings.screen_shake:
		_trauma = minf(1.0, _trauma + amount)

func _shake_offset(delta: float) -> Vector3:
	if _trauma <= 0.0:
		return Vector3.ZERO
	_trauma = maxf(0.0, _trauma - SHAKE_DECAY * delta)
	_shake_t += delta * SHAKE_FREQ
	var k := _trauma * _trauma * SHAKE_MAX_OFFSET
	# Two detuned sines per axis — smooth, never repeating in a way the eye catches
	var x := sin(_shake_t) * 0.6 + sin(_shake_t * 2.3 + 1.7) * 0.4
	var y := sin(_shake_t * 1.3 + 0.4) * 0.6 + sin(_shake_t * 2.9 + 3.1) * 0.4
	return (camera.global_basis.x * x + camera.global_basis.y * y) * k

func _exit_tree() -> void:
	Engine.time_scale = 1.0

# ── Day mood ───────────────────────────────────────────────

func _on_phase_changed(phase: GameState.Phase) -> void:
	match phase:
		GameState.Phase.DUSK:
			if not GameState.attract:
				_slowmo()   # time scale is global: it would slow the menu over the world too
			_set_mood(DUSK_SUN_COLOR, DUSK_SUN_ENERGY, DUSK_CAM_SIZE)
			shake(0.25)
		GameState.Phase.DAWN, GameState.Phase.STORY, GameState.Phase.LOST:
			_set_mood(_day_sun_color, _day_sun_energy, CAM_SIZE)
		GameState.Phase.WON:
			# Every peer reads the ending at its own pace; nothing waits on it
			if story and StoryData.plays_ending():
				story.play(StoryData.ENDING)

func _on_story_finished() -> void:
	if GameState.phase == GameState.Phase.WON:
		story.close()
		credits.play()
	else:
		director.finish_reading()

# The finishing blow lands heavy: a breath of slow motion, then back to speed
func _slowmo() -> void:
	Engine.time_scale = DUSK_SLOWMO
	await get_tree().create_timer(DUSK_SLOWMO_TIME, true, false, true).timeout
	if is_inside_tree():
		Engine.time_scale = 1.0

func _set_mood(sun_color: Color, sun_energy: float, cam_size: float) -> void:
	if _mood_tween:
		_mood_tween.kill()
	_mood_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_mood_tween.tween_property(sun, "light_color", sun_color, LIGHT_FADE)
	_mood_tween.tween_property(sun, "light_energy", sun_energy, LIGHT_FADE)
	_mood_tween.tween_property(camera, "size", cam_size, LIGHT_FADE)

# ── HUD ────────────────────────────────────────────────────

func _refresh_hud() -> void:
	if hud == null:
		return
	var players := _sorted_players()
	var local_name := str(multiplayer.get_unique_id())
	for slot in 4:
		if slot < players.size():
			var pl = players[slot]
			hud.set_player_present(slot, true, pl.name == local_name, pl.is_bot())
			hud.set_player_health(slot, pl.health / pl.MAX_HEALTH)
			hud.set_player_downed(slot, pl.downed)
			hud.set_player_carry(slot, pl.carried_kind)
		else:
			hud.set_player_present(slot, false, false)

# ── Spawning ───────────────────────────────────────────────

func _on_peer_connected(id: int) -> void:
	# All peers spawn the newly arrived player
	_spawn_player(id)
	if multiplayer.is_server():
		fit_bots()   # a person takes a bot's place when the crew is full

func _on_peer_disconnected(id: int) -> void:
	_despawn(id)
	if multiplayer.is_server():
		fit_bots()

func _despawn(id: int) -> void:
	var node := players_root.get_node_or_null(str(id))
	if node:
		players_root.remove_child(node)
		node.queue_free()
	GameState.remove_player(id)
	_assign_colors()
	if multiplayer.is_server():
		GameState.set_crew(players_root.get_child_count())

# `peer_id` is a worker id: a peer's own, or a bot's (Player.BOT_ID_BASE and up, owned
# by the host — whose copy gets the brain)
func _spawn_player(peer_id: int) -> void:
	if players_root.has_node(str(peer_id)):
		return
	var bot := Player.is_bot_id(peer_id)
	var player := PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.set_multiplayer_authority(1 if bot else peer_id)
	if bot and multiplayer.is_server():
		player.brain = BotBrain.new(player, _bot_skill())
	players_root.add_child(player)
	# A small ring round the spawn point, a place per worker, so the crew doesn't start stacked
	var slot := players_root.get_child_count() - 1
	player.global_position = player.RESPAWN_POS \
		+ (Vector3.ZERO if slot == 0 else Vector3(1.3, 0, 0).rotated(Vector3.UP, slot * TAU / 4.0 - PI / 4.0))
	GameState.register_player(peer_id, "Bot" if bot else "Builder")
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

# ── Bots (server) ──────────────────────────────────────────

## Server: as many bots as Settings.bot_count asks for, in the places people leave free.
## Call again after changing the count or skill. `count` overrides the setting.
func fit_bots(count := -1) -> void:
	if not multiplayer.is_server():
		return
	var bots: Array = _sorted_players().filter(func(p): return p.is_bot())
	var people := players_root.get_child_count() - bots.size()
	var want := clampi(Settings.bot_count if count < 0 else count, 0, maxi(0, NetworkManager.MAX_PLAYERS - people))
	for p in bots:
		p.brain.set_skill(_bot_skill())
	while bots.size() > want:
		var id: int = bots.pop_back().worker_id()
		_despawn(id)
		for peer in _ready_peers():
			_remove_bot.rpc_id(peer, id)
	var next := Player.BOT_ID_BASE
	while bots.size() < want:
		while players_root.has_node(str(next)):
			next += 1
		_spawn_player(next)
		bots.append(players_root.get_node(str(next)))
		for peer in _ready_peers():
			_receive_roster_entry.rpc_id(peer, next)

# The title-screen crew shows the game played well
func _bot_skill() -> int:
	return BotBrain.SKILLS.size() - 1 if GameState.attract else Settings.bot_skill

func _ready_peers() -> Array:
	return Array(multiplayer.get_peers()).filter(NetworkManager.is_peer_ready)

@rpc("authority", "reliable")
func _remove_bot(id: int) -> void:
	_despawn(id)

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
	director.send_story_to(caller)

@rpc("authority", "reliable")
func _receive_roster_entry(peer_id: int) -> void:
	_spawn_player(peer_id)

# ── Win / Loss ─────────────────────────────────────────────

# HUD shows the end screen; stop the fight underneath it. On a win the enemy withdraws
# instead (DayDirector sends them off).
func _on_game_lost() -> void:
	get_tree().call_group("enemies", "set_physics_process", false)
