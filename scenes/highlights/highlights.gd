class_name Highlights
extends Node

# The run's highlight reel (playtest 2: "replay… while the crew chooses to play again").
# Every peer keeps its own: at the moments worth remembering — a stretch standing, a wall
# knocked back, a breach, someone falling or helped up, the day's end — it grabs a small
# still of what this player sees, with a caption. The end screen plays them back as a
# slideshow while the crew picks what's next. A still, not a re-simulation: cheap, and
# it shows exactly what happened.

const MAX_SHOTS  := 14
const SHOT_WIDTH := 640
const THROTTLE   := 6.0    # seconds between two shots of the same kind
const DELAY      := 0.35   # let the moment land on screen first
const DOWN_POLL  := 0.4

# Kinds, least to most worth keeping when the reel is full
const RANK := { "piece": 0, "down": 1, "up": 1, "knocked": 2, "breach": 2, "dusk": 3, "stands": 4, "end": 5 }

## [{ "tex": ImageTexture, "caption": String, "kind": String }], oldest first
var shots: Array = []

var _last := {}        # kind → ticks (ms) of its last shot
var _downed := {}      # worker id → downed, as last seen
var _down_poll := 0.0
var _last_done := 0
var _last_breaches := 0

func _ready() -> void:
	if GameState.attract or GameState.free_play() or DisplayServer.get_name() == "headless":
		set_process(false)
		return
	GameState.progress_changed.connect(_on_progress)
	GameState.breaches_changed.connect(_on_breaches)
	GameState.phase_changed.connect(_on_phase)
	_last_breaches = GameState.breaches

func _process(delta: float) -> void:
	_down_poll -= delta
	if _down_poll > 0.0 or GameState.phase != GameState.Phase.WORK:
		return
	_down_poll = DOWN_POLL
	for p: Player in get_tree().get_nodes_in_group("players"):
		var id := p.worker_id()
		var was: bool = _downed.get(id, false)
		var me := id == multiplayer.get_unique_id() and not p.is_bot()
		if p.downed and not was:
			take("down", tr("You went down") if me else tr("%s went down") % _who(p))
		elif was and not p.downed:
			take("up", tr("Back on your feet") if me else tr("%s is back on their feet") % _who(p))
		_downed[id] = p.downed

func _on_progress(done: int, total: int) -> void:
	if GameState.phase != GameState.Phase.WORK or total == 0:
		_last_done = done
		return
	if done > _last_done:
		take("piece", tr("Day %d · %d of %d stand") % [GameState.current_day, done, total])
	elif done < _last_done:
		take("knocked", tr("Day %d · a finished piece knocked back down") % GameState.current_day)
	_last_done = done

func _on_breaches(count: int) -> void:
	if count > _last_breaches and GameState.phase == GameState.Phase.WORK:
		take("breach", tr("Day %d · they broke through") % GameState.current_day)
	_last_breaches = count

func _on_phase(phase: GameState.Phase) -> void:
	match phase:
		GameState.Phase.DUSK:
			var stands := GameState.targets_total > 0 and GameState.targets_done >= GameState.targets_total
			var text := tr("The %s stands") % tr(GameState.get_current_section()["name"]) if stands \
				else tr("Day %d · the day's work is done") % GameState.current_day
			# A beat into the dusk: the crew is cheering by then
			await get_tree().create_timer(1.4).timeout
			take("stands" if stands else "dusk", text, true)
		GameState.Phase.WON:
			take("end", tr("The wall is finished"), true)
		GameState.Phase.LOST:
			take("end", tr("Day %d · the city fell") % GameState.current_day, true)

## Grab a still of what's on screen now (after a beat), captioned
func take(kind: String, caption: String, force := false) -> void:
	var now := Time.get_ticks_msec()
	if not force and now - int(_last.get(kind, -100000)) < THROTTLE * 1000.0:
		return
	_last[kind] = now
	await get_tree().create_timer(DELAY).timeout
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var tex := get_viewport().get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		return
	img.resize(SHOT_WIDTH, int(SHOT_WIDTH * float(img.get_height()) / img.get_width()), Image.INTERPOLATE_BILINEAR)
	shots.append({ "tex": ImageTexture.create_from_image(img), "caption": caption, "kind": kind })
	_trim()

# Full: drop the least worth keeping, oldest first among equals
func _trim() -> void:
	while shots.size() > MAX_SHOTS:
		var worst := 0
		for i in shots.size():
			if RANK[shots[i]["kind"]] < RANK[shots[worst]["kind"]]:
				worst = i
		shots.remove_at(worst)

func _who(p: Player) -> String:
	var who := NetworkManager.name_of(p.worker_id())
	return who if not who.is_empty() else tr(p.trade_name())
