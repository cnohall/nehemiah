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
# Fixed camera (Settings.fixed_camera): the whole stretch in one view, Overcooked-style.
# Frames FIXED_FRAME (x/z: the wall, the enemy line at WaveManager.SPAWN_Z, the near
# side) grown to take in every stockpile, and leans a little toward you.
const FIXED_FRAME  := Rect2(-20.0, -13.0, 40.0, 21.0)
const FIXED_MARGIN := 3.0    # metres kept round each stockpile / heap
const FIXED_DRIFT  := 3.0    # metres the view leans toward the local player
const FIXED_SMOOTH := 3.0
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
const ROSTER_RETRY     := 1.5    # seconds between a client's asks for the roster
# Wall cam: when a stretch stands, the camera runs along it end to end and each piece
# shows the name of the one who carried most to it, cut into the stone (the tally waits)
const WALL_CAM_TIME  := 3.2
const WALL_CAM_SIZE  := 11.0
const WALL_CAM_FROM  := -21.0
const WALL_CAM_TO    := 21.0
const WALL_CAM_Z     := 1.5
const CARVE_COLOR    := Color(0.33, 0.31, 0.35)
const CARVE_LIGHT    := Color(0.93, 0.92, 0.95)

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
var _zoom := 1.0             # the mood's camera size over CAM_SIZE (dusk leans in)
var _was_fixed := false
var _trauma := 0.0
var _shake_t := 0.0
var _hud_timer := 0.0
var _day_sun_color: Color
var _day_sun_energy: float
var _mood_tween: Tween
var _wall_cam: Tween
var _carvings: Array[Label3D] = []   # names on their tablets

func _ready() -> void:
	add_to_group("camera_rig")
	# The stretch's own arc: the enemy answers the work at half and at the last unit
	var beats := SectionBeats.new()
	beats.name = "SectionBeats"
	add_child(beats)
	# The day's record and its threats, kept in the world (diegetic HUD)
	add_child(Scribe.new())
	add_child(Watchmen.new())
	add_child(Taunts.new())
	var relay := RelayMat.new()   # the long haul's halfway stack + porter (Dung Gate)
	relay.name = "RelayMat"       # same node path on every peer, for its trip RPC
	add_child(relay)
	add_child(Households.new())   # the hungry families of Neh. 5 (Fountain Gate)
	add_child(Leaders.new())    # Sanballat, Tobiah, Geshem watching from the rise at the peaks
	if GameState.attract:
		_start_attract()
		return
	hud = HUD_SCENE.instantiate()
	add_child(hud)
	var reel := Highlights.new()
	reel.name = "Highlights"
	add_child(reel)
	hud.highlights = reel
	hud.vote_cast.connect(director.cast_vote)
	director.votes_changed.connect(hud.set_votes)
	hud.begin_requested.connect(director.begin)
	hud.bots_changed.connect(fit_bots)
	director.day_tallied.connect(hud.show_tally)
	director.day_tallied.connect(_on_day_tallied)
	GameState.section_changed.connect(_clear_carvings.unbind(1))
	director.day_tallied.connect(SteamAchievements.on_day_tallied)
	_day_sun_color = sun.light_color
	_day_sun_energy = sun.light_energy
	GameState.phase_changed.connect(_on_phase_changed)
	Mobile.lighten_world($WorldEnvironment.environment, $PostFX/Vignette)

	story = StoryPlayer.new()
	add_child(story)
	director.story_started.connect(func(day: int): story.play(StoryData.slides_for_day(day)))
	director.ready_changed.connect(story.set_ready_state)
	director.ready_changed.connect(hud.set_ready_state)
	hud.ready_pressed.connect(director.mark_ready)
	hud.begin_now_requested.connect(director.force_ready)
	director.story_ended.connect(story.close)
	story.finished.connect(_on_story_finished)
	story.choice_made.connect(director.cast_choice)
	story.start_now_requested.connect(director.force_ready)
	# After the ending story: the credits, then the end screen
	credits = CreditsRoll.new()
	add_child(credits)
	credits.finished.connect(hud.show_end.bind(true))

	NetworkManager.peer_connected.connect(_on_peer_connected)
	NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
	NetworkManager.crew_info_changed.connect(_assign_colors)   # someone picked a trade
	GameState.game_lost.connect(_on_game_lost)

	camera.size = CAM_SIZE
	camera.look_at(Vector3(0, 0, 2), Vector3.UP)
	camera.make_current()

	_spawn_player(multiplayer.get_unique_id())

	if multiplayer.is_server():
		NetworkManager.open_crew()
		# After a "Play again" reload the crew is still connected: nobody joins anew
		for id in multiplayer.get_peers():
			_spawn_player(id)
		director.start()
		if GameState.tutorial:
			fit_bots(0)
			add_child(Tutorial.new(self))
		elif GameState.festival:
			fit_bots(0)
			add_child(Festival.new(self))
		else:
			fit_bots()
	else:
		_ask_for_roster()

# Client: after a "Play again" everyone reloads at once, and the host's new Main may not
# be up when our first ask lands — ask again until the roster arrives
var _roster_in := false

func _ask_for_roster() -> void:
	while is_inside_tree() and not _roster_in and multiplayer.has_multiplayer_peer():
		_request_roster.rpc_id(1)
		await get_tree().create_timer(ROSTER_RETRY).timeout

func _process(delta: float) -> void:
	if GameState.attract:
		_frame_crew(delta)
		return
	_turn_to_map()
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
	var desired := p + _cam_offset()
	desired.y = CAM_OFFSET.y
	if not _cam_snapped:
		_cam_base = desired
		_cam_snapped = true
	else:
		_cam_base = _cam_base.lerp(desired, minf(1.0, delta * ATTRACT_SMOOTH))
	camera.global_position = _cam_base

func _follow_local_player(delta: float) -> void:
	var local_player := Player.local
	if local_player == null or (_wall_cam != null and _wall_cam.is_running()):
		return
	var fixed := _fixed_cam()
	if fixed != _was_fixed:
		_was_fixed = fixed
		if not fixed:   # back to the close follow framing
			create_tween().tween_property(camera, "size", CAM_SIZE * _zoom, 0.6).set_trans(Tween.TRANS_SINE)
	var p: Vector3
	var smooth := CAM_SMOOTH
	if fixed:
		var frame := _fixed_frame()
		var mid := Vector3(frame.get_center().x, 0.0, frame.get_center().y)
		var toward := local_player.global_position - mid
		p = mid + Vector3(toward.x, 0.0, toward.z).limit_length(FIXED_DRIFT)
		smooth = FIXED_SMOOTH
		var size := _fit_size(frame, mid) * _zoom
		camera.size = size if not _cam_snapped else lerpf(camera.size, size, minf(1.0, delta * FIXED_SMOOTH))
	else:
		var vel: Vector3 = local_player.velocity
		var lead := Vector3(vel.x, 0.0, vel.z) * LOOK_AHEAD
		_lead = _lead.lerp(lead.limit_length(LOOK_AHEAD_MAX), minf(1.0, delta * LOOK_AHEAD_EASE))
		p = local_player.global_position + _lead
	var desired := p + _cam_offset()
	desired.y = CAM_OFFSET.y
	if not _cam_snapped:
		# Snap on first frame instead of swooping in from the scene origin
		_cam_base = desired
		_cam_snapped = true
	else:
		_cam_base = _cam_base.lerp(desired, minf(1.0, delta * smooth))
	camera.global_position = _cam_base + _shake_offset(delta)

# Explore Jerusalem wanders the whole city: it always follows
func _fixed_cam() -> bool:
	return Settings.fixed_camera and not GameState.festival and not GameState.attract

## The ground (x/z) the fixed camera keeps in view: FIXED_FRAME plus every stockpile
## and heap standing this section (the yard moves — the Dung Gate's sits far east)
func _fixed_frame() -> Rect2:
	var frame := FIXED_FRAME
	for group: Node in [$Supplies, $Rubble]:
		for pile: Node3D in group.get_children():
			if pile.is_visible_in_tree():
				var at := Vector2(pile.global_position.x, pile.global_position.z)
				frame = frame.expand(at - Vector2.ONE * FIXED_MARGIN).expand(at + Vector2.ONE * FIXED_MARGIN)
	return frame

## Orthographic size that fits the frame's four ground corners, seen from `mid`
func _fit_size(frame: Rect2, mid: Vector3) -> float:
	var right := camera.global_basis.x
	var up := camera.global_basis.y
	var half := Vector2.ZERO
	for c: Vector2 in [frame.position, frame.end, Vector2(frame.position.x, frame.end.y), Vector2(frame.end.x, frame.position.y)]:
		var v := Vector3(c.x, 0.0, c.y) - mid
		half.x = maxf(half.x, absf(v.dot(right)))
		half.y = maxf(half.y, absf(v.dot(up)))
	var view := get_viewport().get_visible_rect().size
	var aspect := view.x / view.y if view.y > 0.0 else 16.0 / 9.0
	# size is the view's height (keep height); the drift can shift it by up to FIXED_DRIFT
	return maxf(half.y * 2.0, half.x * 2.0 / aspect) + FIXED_DRIFT

## Explore Jerusalem: turn the view about the vertical (radians), so north can sit up-screen
## as it does on a map. Movement turns with it (Player.view_yaw). 0 = the game's view.
var view_yaw := 0.0

func set_view_yaw(yaw: float) -> void:
	view_yaw = yaw
	Player.view_yaw = yaw
	var target := Vector3.ZERO
	if Player.local != null and is_instance_valid(Player.local):
		target = Player.local.global_position
	target.y = 0.0
	camera.global_position = target + _cam_offset()
	camera.look_at(target, Vector3.UP)
	_cam_snapped = false

## Campaign, Settings.turn_to_map: each stretch seen north-up as in Explore Jerusalem
## (which turns its own view). Checked every frame: a new section, or the setting
## changed from the pause menu, turns it at once.
func _turn_to_map() -> void:
	if GameState.festival:
		return
	var yaw := RingCompass.north_up_yaw(GameState.current_section_index) if Settings.turn_to_map else 0.0
	if not is_equal_approx(yaw, view_yaw):
		set_view_yaw(yaw)

func _cam_offset() -> Vector3:
	return CAM_OFFSET.rotated(Vector3.UP, view_yaw)

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
	Player.view_yaw = 0.0   # a static: the next scene starts in the game's own view

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
		director.mark_ready()

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
	_mood_tween.tween_property(self, "_zoom", cam_size / CAM_SIZE, LIGHT_FADE)
	if not _fixed_cam():   # the fixed camera sizes itself each frame, _zoom included
		_mood_tween.tween_property(camera, "size", cam_size, LIGHT_FADE)

# ── Wall cam ───────────────────────────────────────────────

func _on_day_tallied(stats: Dictionary) -> void:
	GameState.chronicle_day(stats)
	if stats.has("names") and not GameState.attract:
		_play_wall_cam(stats["names"])

# End to end along the finished stretch, low and close; each name is cut into its piece
# as the camera comes to it. Then the follow camera eases back from where it ended.
func _play_wall_cam(names: Array) -> void:
	_clear_carvings()
	var units := WorkFront.UNIT_ORDER
	var crew := _sorted_players()
	for i in mini(names.size(), units.size()):
		var who := _carved_name(int(names[i]), crew)
		if who.is_empty():
			continue
		var unit: Node3D = $Wall.get_node(units[i])
		var label := _carve(who, unit)
		# Cut as the camera passes: the dolly's progress at this piece's x
		var at := inverse_lerp(WALL_CAM_FROM, WALL_CAM_TO, unit.global_position.x)
		var tw := label.create_tween().set_ignore_time_scale(true)
		tw.tween_interval(0.25 + at * WALL_CAM_TIME * 0.85)
		tw.tween_property(label.get_parent(), "scale:y", 1.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(label, "modulate:a", 1.0, 0.35)
		tw.tween_callback(Sfx.play.bind("build", label.global_position))
	if _wall_cam:
		_wall_cam.kill()
	var start := Vector3(WALL_CAM_FROM, 0.0, WALL_CAM_Z) + _cam_offset()
	var end := Vector3(WALL_CAM_TO, 0.0, WALL_CAM_Z) + _cam_offset()
	_wall_cam = create_tween().set_ignore_time_scale(true)
	_wall_cam.tween_property(camera, "global_position", start, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_wall_cam.parallel().tween_property(camera, "size", WALL_CAM_SIZE, 0.35)
	_wall_cam.tween_property(camera, "global_position", end, WALL_CAM_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_wall_cam.tween_callback(func():
		_cam_base = camera.global_position
		if _fixed_cam():
			return   # the fixed camera eases back to its own framing
		_mood_tween = create_tween()
		_mood_tween.tween_property(camera, "size", DUSK_CAM_SIZE, 0.8).set_trans(Tween.TRANS_SINE))

## A worker's name for the stone: their Steam name, else their trade (bots, LAN)
func _carved_name(id: int, crew: Array) -> String:
	if id == 0:
		return ""
	var steam := NetworkManager.name_of(id)
	if not steam.is_empty() and not Player.is_bot_id(id):
		return steam
	for p in crew:
		if int(p.name) == id:
			return tr(p.trade_name())
	return ""

# A dedication tablet set into the city face of the piece, chest high, the name cut in.
# Stands proud of the rough courses so no stone hides it; it rises into place when cut.
func _carve(text: String, unit: Node3D) -> Label3D:
	var face := 0.5
	var col := unit.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null and col.shape is BoxShape3D:
		face = col.position.z + (col.shape as BoxShape3D).size.z * 0.5
	var tablet := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(maxf(1.4, text.length() * 0.3 + 0.5), 0.62, 0.1)
	tablet.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = CARVE_LIGHT.darkened(0.08)
	mat.roughness = 0.95
	tablet.material_override = mat
	tablet.position = Vector3(unit.global_position.x, 1.45, face + 0.28)
	tablet.scale = Vector3(1.0, 0.001, 1.0)
	add_child(tablet)
	var l := Label3D.new()
	l.text = text
	l.font = UiStyle.CINZEL_BOLD
	l.font_size = 56
	l.pixel_size = 0.0085
	l.modulate = Color(CARVE_COLOR, 0.0)
	l.outline_size = 0
	l.shaded = false
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.position = Vector3(0.0, 0.0, 0.06)
	tablet.add_child(l)
	_carvings.append(l)
	return l

func _clear_carvings() -> void:
	for l in _carvings:
		if is_instance_valid(l):
			l.get_parent().queue_free()   # the tablet, name and all
	_carvings.clear()

# ── HUD ────────────────────────────────────────────────────

func _refresh_hud() -> void:
	if hud == null:
		return
	var players := _sorted_players()
	var local_name := str(multiplayer.get_unique_id())
	for slot in 4:
		if slot < players.size():
			var pl = players[slot]
			hud.set_player_present(slot, true, pl.name == local_name, pl.is_bot(),
				NetworkManager.name_of(pl.worker_id()), NetworkManager.is_loading(pl.worker_id()), pl.trade)
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
	var trades := Trade.assign(players.map(func(p): return NetworkManager.trade_of(p.worker_id())),
		players.map(func(p): return p.is_bot()))
	for slot in players.size():
		var c: Color = PLAYER_COLORS[slot % PLAYER_COLORS.size()]
		players[slot].set_slot(slot, c, trades[slot])
		if hud:
			hud.set_player_color(slot, c, trades[slot])

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
	$Breakables.send_state_to(caller)   # after GameState, so the caller has laid out the same section
	director.send_story_to(caller)

@rpc("authority", "reliable")
func _receive_roster_entry(peer_id: int) -> void:
	_roster_in = true
	_spawn_player(peer_id)

# ── Win / Loss ─────────────────────────────────────────────

# HUD shows the end screen; stop the fight underneath it. On a win the enemy withdraws
# instead (DayDirector sends them off).
func _on_game_lost() -> void:
	get_tree().call_group("enemies", "set_physics_process", false)
