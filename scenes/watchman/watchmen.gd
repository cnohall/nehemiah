class_name Watchmen
extends Node3D

# Two watchmen on timber stands at either end of the stretch — "we set a watch against
# them day and night" (Neh. 4:9). They call out the threats a plaque used to count
# (diegetic HUD): a wave coming and from which side, the wall being battered, the first
# brute or raider of the day, one of the enemy getting into the city, the sun going low.
# A call from a watchman out of view slides in from the screen edge (Shout).
# Every peer, from state it already has (like OffscreenAlerts); WaveManager tells it of
# waves through the "watchmen" group.

const STAND_X     := 21.5
const STAND_Z     := 2.6
const DECK_Y      := 2.4
const LOOK        := Color(0.55, 0.36, 0.22)
const WOOD_COLOR  := Color(0.50, 0.33, 0.18)
const POLL        := 0.4
const WALL_RECALL := 9000    # ms before the same wall is called out again
const HIT_FRESH   := 1500    # ms: a hit this recent is "being battered now"
const BRUTE_NEAR  := 3.5

# Each: { "side": -1 | 1, "rig": CharacterRig, "shout": Shout }
var _men: Array[Dictionary] = []
var _poll := 0.0
var _wall_called := {}     # wall instance id → msec
var _seen_today := {}      # enemy type → true, the first of each type called once a day
var _last_breaches := 0
var _sun_called := false

func _ready() -> void:
	add_to_group("watchmen")
	for side: int in [-1, 1]:
		_men.append(_build_stand(side))
	_last_breaches = GameState.breaches
	GameState.breaches_changed.connect(_on_breaches)
	GameState.phase_changed.connect(_on_phase)

func _on_phase(phase: GameState.Phase) -> void:
	if phase == GameState.Phase.DAWN:
		_seen_today.clear()
		_sun_called = false

func _process(delta: float) -> void:
	_poll -= delta
	if _poll > 0.0 or GameState.phase != GameState.Phase.WORK:
		return
	_poll = POLL
	_watch_walls()
	_watch_newcomers()
	if not _sun_called and GameState.sun_low():
		_sun_called = true
		_call(_nearest_man(Player.local.global_position.x if Player.local else 0.0),
			tr("The sun is low!"), true)

## WaveManager (every peer): a wave or a surge is about to come in at `at`
## A flank is named by its true quarter on the real wall (RingCompass): out across the
## wall and toward that end of the stretch
func warn_wave(at: Vector3, horn: bool) -> void:
	var where := tr("straight at the gate")
	if absf(at.x) > 6.0:
		where = RingCompass.quarter(GameState.current_section_index, Vector3(signf(at.x), 0.0, -1.0))
	var line := (tr("Up the valley — %s!") if horn else tr("They're coming — %s!")) % where
	_call(_nearest_man(at.x), line, true)

func _watch_walls() -> void:
	var now := Time.get_ticks_msec()
	for wall: Node3D in get_tree().get_nodes_in_group("wall_sections"):
		if now - wall.last_hit_msec > HIT_FRESH:
			continue
		var id := wall.get_instance_id()
		if now - _wall_called.get(id, -WALL_RECALL) < WALL_RECALL:
			continue
		_wall_called[id] = now
		var brute := false
		for e: Node3D in get_tree().get_nodes_in_group("enemies"):
			if e.get("type") == Enemy.Type.BRUTE and wall.distance_to_point(e.global_position) < BRUTE_NEAR:
				brute = true
		_call(_nearest_man(wall.global_position.x),
			tr("A brute at the wall — bring him down!") if brute else tr("They're battering the wall!"), true)
		return   # one call at a time

func _watch_newcomers() -> void:
	for e: Node3D in get_tree().get_nodes_in_group("enemies"):
		var t = e.get("type")
		if t == Enemy.Type.SCOUT or _seen_today.has(t):
			continue
		_seen_today[t] = true
		var line := tr("A brute! He'll batter the wall") if t == Enemy.Type.BRUTE \
			else tr("Raiders — quick ones, mind the gaps!")
		_call(_nearest_man(e.global_position.x), line, false)
		return

func _on_breaches(count: int) -> void:
	var more := count > _last_breaches
	_last_breaches = count
	if not more or GameState.is_over():
		return
	var left := GameState.MAX_BREACHES - count
	var line := tr("One got into the city!  %d of %d") % [count, GameState.MAX_BREACHES]
	if left <= 3:
		line = tr_n("One got in — %d more and the city falls!", "One got in — %d more and the city falls!", left) % left
	var x := Player.local.global_position.x if Player.local else 0.0
	_call(_nearest_man(x), line, true)

func _nearest_man(x: float) -> Dictionary:
	return _men[0] if x < 0.0 else _men[1]

func _call(man: Dictionary, line: String, urgent: bool) -> void:
	var shout: Shout = man["shout"]
	shout.say(line, Shout.HOLD, urgent)
	var rig: CharacterRig = man["rig"]
	rig.squash(Vector2(0.9, 1.12))
	rig.play("cheer_down")
	get_tree().create_timer(0.9).timeout.connect(func():
		if is_instance_valid(rig):
			rig.play("idle_down"))

# A lookout: four timber legs, cross braces, a plank deck, a ladder on the city side,
# and the watchman on top
func _build_stand(side: int) -> Dictionary:
	var stand := Node3D.new()
	stand.position = Vector3(STAND_X * side, 0.1, STAND_Z)
	add_child(stand)
	var parts := WatchPost._Parts.new()
	var leg := 0.55
	for sx: float in [-leg, leg]:
		for sz: float in [-leg, leg]:
			parts.add(Vector3(0.16, DECK_Y + 0.6, 0.16), Vector3(sx, (DECK_Y + 0.6) * 0.5, sz), WOOD_COLOR.darkened(0.08))
	for sz: float in [-leg, leg]:
		parts.add(Vector3(1.4, 0.09, 0.09), Vector3(0, DECK_Y * 0.45, sz), WOOD_COLOR.darkened(0.2), Vector3(0, 0, 0.9))
	parts.add(Vector3(1.45, 0.12, 1.45), Vector3(0, DECK_Y, 0), WOOD_COLOR.lightened(0.1))
	parts.add(Vector3(1.45, 0.07, 0.07), Vector3(0, DECK_Y + 0.55, -leg), WOOD_COLOR)
	for dx: float in [-0.2, 0.2]:
		parts.add(Vector3(0.06, DECK_Y + 0.2, 0.06), Vector3(dx, (DECK_Y + 0.2) * 0.5, leg + 0.3),
			WOOD_COLOR.lightened(0.05), Vector3(-0.25, 0, 0))
	for r in 6:
		var y := (r + 1) * DECK_Y / 7.0
		parts.add(Vector3(0.44, 0.05, 0.05), Vector3(0, y, leg + 0.3 + 0.25 * (0.5 - y / DECK_Y)), WOOD_COLOR.lightened(0.05))
	stand.add_child(parts.build(Chunky.wood_material(0.03)))
	var rig := CharacterRig.new()
	stand.add_child(rig)
	rig.position = Vector3(0, DECK_Y + 0.06, -0.1)
	# One of the city's own, with a spear (Neh. 4:13)
	var look := CharacterRig.worker_look(1, LOOK)
	look["tool"] = false
	look["sword"] = false
	look.erase("satchel")
	look["weapon"] = "spear"
	rig.setup(look, 0.9)
	rig.set_ring_color(Color(0, 0, 0, 0))
	rig.play("idle_down")
	var shout := Shout.make_shout()
	shout.position = Vector3(0, DECK_Y + 2.6, 0)
	stand.add_child(shout)
	return { "side": side, "rig": rig, "shout": shout }
