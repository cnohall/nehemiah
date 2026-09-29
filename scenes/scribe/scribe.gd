class_name Scribe
extends Node3D

# The day's record kept in the world instead of on a plaque (diegetic HUD): a scribe at
# a low desk by the supply yard writes up the stretch — the day, which pieces stand, and
# how many of the enemy got through (red strokes; ten, and the city falls). His scroll
# floats over him while he's on screen. When a piece stands or falls he calls it out, and
# the call slides in from the screen edge, so it's heard from anywhere.
# Every peer, from GameState alone. Moves with the yard from section to section.

const OFFSET     := Vector2(-8.5, 0.8)   # from the yard centre: west of the stone pile
const ROBE       := Palette.INDIGO
const DESK_COLOR := Color(0.46, 0.32, 0.19)
const SCROLL_COLOR := Color(0.90, 0.82, 0.62)
const TAG_Y      := 3.1

var _rig: CharacterRig
var _scroll: WorldTag
var _sheet: ScrollSheet
var _shout: Shout
var _last_done := -1
var _last_total := -1

func _ready() -> void:
	_build_desk()
	_rig = CharacterRig.new()
	add_child(_rig)
	var look := CharacterRig.worker_look(3, ROBE)
	look["tool"] = false
	look["sword"] = false
	_rig.setup(look, 0.95)
	_rig.set_ring_color(Color(0, 0, 0, 0))
	_rig.position = Vector3(-0.2, 0.0, -0.6)   # behind the desk, facing the camera
	_rig.play("idle_down")
	_sheet = ScrollSheet.new()
	_scroll = WorldTag.make(WorldTag.Kind.SCROLL)
	_scroll.custom = _sheet
	_scroll.clamp_to_screen = false
	_scroll.position = Vector3(0, TAG_Y, 0)
	add_child(_scroll)
	_shout = Shout.make_shout()
	_shout.position = Vector3(0, TAG_Y, 0)
	_shout.screen_lift = 96.0   # above the scroll when both show
	add_child(_shout)
	GameState.section_changed.connect(_place.unbind(1))
	GameState.day_changed.connect(_refresh.unbind(1))
	GameState.progress_changed.connect(_on_progress)
	GameState.breaches_changed.connect(_refresh.unbind(1))
	GameState.phase_changed.connect(_refresh.unbind(1))
	_place()
	_refresh()

func _place() -> void:
	var at := GameState.yard_center() + OFFSET
	position = Vector3(at.x, 0.1, at.y)

func _refresh() -> void:
	var sec := GameState.get_current_section()
	_sheet.title = tr("Day %d  ·  %s") % [GameState.current_day, tr(sec["name"])]
	_sheet.done = GameState.targets_done
	_sheet.total = GameState.targets_total
	_sheet.breaches = GameState.breaches
	_sheet.update_minimum_size()
	_sheet.queue_redraw()
	_scroll.visible = GameState.phase in [GameState.Phase.DAWN, GameState.Phase.WORK, GameState.Phase.DUSK] \
		and not GameState.free_play()

# A piece stood (or fell): write it up, look up, say it
func _on_progress(done: int, total: int) -> void:
	var working := GameState.phase == GameState.Phase.WORK
	if working and total == _last_total and done != _last_done:
		var line := ""
		if done < _last_done:
			line = tr("A piece has fallen — raise it again!")
		elif done >= total:
			line = tr("The stretch stands!")
		elif total - done == 1:
			line = tr("One piece left!")
		else:
			line = tr("%d of %d stand") % [done, total]
		_shout.say(line, Shout.HOLD, done < _last_done)
		_rig.squash(Vector2(0.92, 1.1))
		_rig.play("cheer_down" if done > _last_done else "idle_down")
		get_tree().create_timer(1.2).timeout.connect(func():
			if is_instance_valid(_rig):
				_rig.play("idle_down"))
	_last_done = done
	_last_total = total
	_refresh()

# A low writing desk (the scribe sits on his heels behind it), a scroll half unrolled
# on it, an ink pot
func _build_desk() -> void:
	var parts := WatchPost._Parts.new()
	parts.add(Vector3(1.3, 0.08, 0.6), Vector3(0, 0.46, 0), DESK_COLOR.lightened(0.08))
	for sx: float in [-0.55, 0.55]:
		for sz: float in [-0.22, 0.22]:
			parts.add(Vector3(0.08, 0.44, 0.08), Vector3(sx, 0.22, sz), DESK_COLOR.darkened(0.1))
	add_child(parts.build(Chunky.wood_material(0.02)))
	var paper := WatchPost._Parts.new()
	paper.add(Vector3(0.8, 0.012, 0.36), Vector3(0.05, 0.51, 0), SCROLL_COLOR)
	for sx: float in [-0.37, 0.47]:
		paper.add(Vector3(0.1, 0.1, 0.42), Vector3(sx, 0.55, 0), SCROLL_COLOR.darkened(0.12))
	paper.add(Vector3(0.1, 0.12, 0.1), Vector3(0.52, 0.56, -0.2), Color(0.18, 0.14, 0.12))   # ink pot
	add_child(paper.build(Chunky.material(0.02)))


# The scroll's face: the day, one block per piece of the stretch (inked when it stands),
# and a red stroke for each of the enemy that got through, out of the ten that lose it
class ScrollSheet extends Control:
	const BLOCK := Vector2(20, 13)
	const GAP := 5.0
	const TITLE_SIZE := 15
	const SMALL := 12
	var title := ""
	var done := 0
	var total := 0
	var breaches := 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _get_minimum_size() -> Vector2:
		var tw := UiStyle.CINZEL_BOLD.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE).x
		var bw := maxf(total, 1) * (BLOCK.x + GAP) + 44.0
		var sw := 70.0 + GameState.MAX_BREACHES * 8.0
		return Vector2(maxf(tw, maxf(bw, sw)), 66)

	func _draw() -> void:
		# Rolled ends, just outside the sheet
		for x: float in [-14.0, size.x + 6.0]:
			draw_rect(Rect2(x, -8, 8, size.y + 16), Color(0.55, 0.42, 0.26))
			draw_rect(Rect2(x + 1, -8, 3, size.y + 16), Color(0.68, 0.54, 0.34))
		draw_string(UiStyle.CINZEL_BOLD, Vector2(0, 14), title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE, UiStyle.INK)
		# The stretch: ashlar blocks, inked in as each piece stands
		var y := 24.0
		for i in total:
			var r := Rect2(Vector2(i * (BLOCK.x + GAP), y), BLOCK)
			if i < done:
				draw_rect(r, Palette.WALL_STONE.darkened(0.12))
				draw_rect(r, UiStyle.INK, false, 1.5)
			else:
				draw_rect(r, Color(UiStyle.RULE, 0.8), false, 1.0)
		if total > 0:
			draw_string(UiStyle.SPECTRAL_MEDIUM, Vector2(total * (BLOCK.x + GAP) + 4, y + 12),
				"%d / %d" % [done, total], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiStyle.INK_SOFT)
		# Through the wall: red strokes out of ten
		y = 52.0
		var label := tr("Got through")
		draw_string(UiStyle.SPECTRAL_ITALIC, Vector2(0, y + 10), label, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL, UiStyle.INK_SOFT)
		var x0 := UiStyle.SPECTRAL_ITALIC.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL).x + 8.0
		for i in GameState.MAX_BREACHES:
			var x := x0 + i * 8.0 + (4.0 if i >= 5 else 0.0)
			var hit := i < breaches
			draw_line(Vector2(x, y), Vector2(x + 2, y + 12), UiStyle.TERRACOTTA if hit else Color(UiStyle.RULE, 0.55),
				2.2 if hit else 1.0, true)
