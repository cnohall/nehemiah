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
const RANK := { "piece": 0, "down": 1, "up": 1, "knocked": 2, "breach": 2, "dusk": 3, "stands": 4, "close": 4, "end": 5 }

# Steam's game recording (GDD §7.1 #7): the same moments go on its timeline, so a player
# can clip a breach or a close call from the overlay. kind → [built-in icon, priority,
# clip priority (Steam's ETimelineEventClipPriority: 1 none, 2 standard, 3 featured)]
const TIMELINE := {
	"piece":   ["steam_checkmark", 10, 1],
	"down":    ["steam_death", 20, 2],
	"up":      ["steam_heart", 10, 1],
	"knocked": ["steam_explosion", 30, 2],
	"breach":  ["steam_caution", 40, 2],
	"dusk":    ["steam_flag", 20, 1],
	"stands":  ["steam_completed", 60, 2],
	"close":   ["steam_starburst", 100, 3],
	"end":     ["steam_trophy", 80, 2],
}
# Steam's ETimelineGameMode: 1 playing, 2 staging (the gathering), 3 menus
const MODE_PLAYING := 1
const MODE_STAGING := 2
const MODE_MENUS   := 3

## [{ "tex": ImageTexture, "caption": String, "kind": String }], oldest first
var shots: Array = []

var _on := true        # off on the title, in free play and headless (nothing to keep)
var _last := {}        # kind → ticks (ms) of its last shot
var _downed := {}      # worker id → downed, as last seen
var _down_poll := 0.0
var _last_done := 0
var _last_breaches := 0

func _ready() -> void:
	if GameState.attract or GameState.free_play() or DisplayServer.get_name() == "headless":
		set_process(false)
		_on = false
		_steam_mode(MODE_MENUS if GameState.attract else MODE_PLAYING)
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
		GameState.Phase.GATHER:
			_steam_mode(MODE_STAGING)
		GameState.Phase.STORY:
			_steam_mode(MODE_MENUS)
		GameState.Phase.DAWN:
			_steam_mode(MODE_PLAYING)
			var steam := NetworkManager.steam()
			if steam:
				steam.setTimelineTooltip(tr("Day %d · %s") % [GameState.current_day,
					tr(GameState.get_current_section()["name"])], 0.0)
		GameState.Phase.DUSK:
			var stands := GameState.targets_total > 0 and GameState.targets_done >= GameState.targets_total
			var text := tr("The %s stands") % tr(GameState.get_current_section()["name"]) if stands \
				else tr("Day %d · the day's work is done") % GameState.current_day
			# A beat into the dusk: the crew is cheering by then
			await get_tree().create_timer(1.4).timeout
			take("stands" if stands else "dusk", text, true)
		GameState.Phase.WON:
			take("end", tr("The wall is finished"), true)
			_steam_mode(MODE_MENUS)
		GameState.Phase.LOST:
			take("end", tr("Day %d · the city fell") % GameState.current_day, true)
			_steam_mode(MODE_MENUS)

## Grab a still of what's on screen now (after a beat), captioned. A close call passes no
## beat: the wall cam swings away from the gap as the tally comes in.
func take(kind: String, caption: String, force := false, delay := DELAY) -> void:
	if not _on:
		return
	var now := Time.get_ticks_msec()
	if not force and now - int(_last.get(kind, -100000)) < THROTTLE * 1000.0:
		return
	_last[kind] = now
	_steam_mark(kind, caption)
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
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

func _steam_mark(kind: String, caption: String) -> void:
	var steam := NetworkManager.steam()
	if steam == null or not TIMELINE.has(kind):
		return
	var t: Array = TIMELINE[kind]
	steam.addInstantaneousTimelineEvent(caption, tr(GameState.get_current_section()["name"]), t[0], t[1], 0.0, t[2])

func _steam_mode(mode: int) -> void:
	var steam := NetworkManager.steam()
	if steam:
		steam.setTimelineGameMode(mode)

func _who(p: Player) -> String:
	var who := NetworkManager.name_of(p.worker_id())
	return who if not who.is_empty() else tr(p.trade_name())
