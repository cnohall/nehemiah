class_name Scribe
extends Node3D

# The day's record kept in the world instead of on a plaque (diegetic HUD): a scribe at
# a low desk by the supply yard writes up the stretch — the day, which pieces stand, and
# how many of the enemy got through (red strokes; ten, and the city falls). His scroll
# floats over him only while you stand right by his desk. When a piece stands or falls
# he calls it out, and the call slides in from the screen edge, so it's heard from anywhere.
# Every peer, from GameState alone. Moves with the yard from section to section.

const OFFSET     := Vector2(-8.5, 0.8)   # from the yard centre: west of the stone pile
const ROBE       := Palette.INDIGO
const DESK_COLOR := Color(0.46, 0.32, 0.19)
const SCROLL_COLOR := Color(0.90, 0.82, 0.62)
const TAG_Y      := 3.1
# The scroll shows when the local player comes this close (m, ground plane), and goes
# again past the far one — a gap so it doesn't flicker at the edge
const NEAR_SHOW  := 3.0
const NEAR_HIDE  := 4.0

var _rig: CharacterRig
var _scroll: WorldTag
var _sheet: ScrollSheet
var _shout: Shout
var _last_done := -1
var _last_total := -1
var _day_open := false   # a phase with a record to show
var _near := false

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
	GameState.journal_changed.connect(_refresh)
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
	_sheet.notes = GameState.journal
	_sheet.update_minimum_size()
	_sheet.queue_redraw()
	_day_open = GameState.phase in [GameState.Phase.DAWN, GameState.Phase.WORK, GameState.Phase.DUSK] \
		and not GameState.free_play()
	_scroll.visible = _day_open and _near

func _process(_delta: float) -> void:
	var me := Player.local
	if me == null or not is_instance_valid(me):
		_near = false
	else:
		var d := Vector2(me.global_position.x - global_position.x, me.global_position.z - global_position.z).length()
		_near = d < (NEAR_HIDE if _near else NEAR_SHOW)
	_scroll.visible = _day_open and _near

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


# The scroll's face: the day, then two labelled rows — one block per piece of the
# stretch (inked when it stands), and a red stroke for each of the enemy that got
# through, out of the ten that lose the city
class ScrollSheet extends Control:
	const BLOCK := Vector2(20, 13)
	const GAP := 5.0
	const STROKE := 8.0
	const TITLE_SIZE := 15
	const SMALL := 12
	const COUNT := 14
	const WOOD := Color(0.50, 0.33, 0.18)
	# Aged parchment, warmer than the UI panels. The sheet fills the WorldTag's margins
	# round the content, and the tail stands in for its pointer
	const PAPER := Color(0.96, 0.91, 0.79)
	const PAPER_DARK := Color(0.78, 0.65, 0.45)
	const EDGE := Color(0.42, 0.29, 0.16)
	const MARGIN := Vector4(20, 6, 20, 7)   # left, top, right, bottom
	const TAIL := Vector2(16, 9)
	var title := ""
	var done := 0
	var total := 0
	var breaches := 0
	var notes: Array[String] = []   # margin notes: what went wrong this stretch, with its verse

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _labels() -> Array[String]:
		return [tr("Wall"), tr("City breaches")]

	func _label_w() -> float:
		var w := 0.0
		for l in _labels():
			w = maxf(w, UiStyle.SPECTRAL_ITALIC.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL).x)
		return w + 12.0

	func _strokes_w() -> float:
		return GameState.MAX_BREACHES * STROKE + 4.0

	func _get_minimum_size() -> Vector2:
		var tw := UiStyle.CINZEL_BOLD.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE).x
		var count_w := 48.0
		var row := _label_w() + maxf(maxf(total, 1) * (BLOCK.x + GAP), _strokes_w()) + count_w
		var note_w := 0.0
		for n in notes:
			note_w = maxf(note_w, UiStyle.SPECTRAL_ITALIC.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL).x)
		return Vector2(maxf(maxf(tw, row), note_w), 66 + notes.size() * 15)

	func _draw() -> void:
		_paper()
		# Ruled under the title, in faded ink
		draw_line(Vector2(0, 19.5), Vector2(size.x, 19.5), Color(EDGE, 0.22), 1.0, true)
		draw_string(UiStyle.CINZEL_BOLD, Vector2(0, 14), title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE, UiStyle.INK)
		var labels := _labels()
		var x0 := _label_w()
		var count_x := x0 + maxf(maxf(total, 1) * (BLOCK.x + GAP), _strokes_w()) + 2.0
		# The stretch: ashlar blocks, inked in as each piece stands
		var y := 24.0
		draw_string(UiStyle.SPECTRAL_ITALIC, Vector2(0, y + 11), labels[0], HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL, UiStyle.INK_SOFT)
		for i in total:
			var r := Rect2(Vector2(x0 + i * (BLOCK.x + GAP), y), BLOCK)
			if i < done:
				draw_rect(r, Palette.WALL_STONE.darkened(0.12))
				draw_rect(r, UiStyle.INK, false, 1.5)
			else:
				draw_rect(r, Color(UiStyle.RULE, 0.25))
				draw_rect(r, UiStyle.RULE, false, 1.0)
		draw_string(UiStyle.SPECTRAL_MEDIUM, Vector2(count_x, y + 12), "%d / %d" % [done, total],
			HORIZONTAL_ALIGNMENT_LEFT, -1, COUNT, UiStyle.INK if done >= total and total > 0 else UiStyle.INK_SOFT)
		# Through the wall: red strokes out of ten, tallied in fives
		y = 47.0
		draw_string(UiStyle.SPECTRAL_ITALIC, Vector2(0, y + 11), labels[1], HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL, UiStyle.INK_SOFT)
		for i in GameState.MAX_BREACHES:
			var x := x0 + 2.0 + i * STROKE + (4.0 if i >= 5 else 0.0)
			var hit := i < breaches
			draw_line(Vector2(x, y + 1), Vector2(x + 2, y + 13), UiStyle.TERRACOTTA if hit else Color(UiStyle.RULE, 0.9),
				2.4 if hit else 1.2, true)
		# Margin notes, in the scribe's red ink
		for k in notes.size():
			draw_string(UiStyle.SPECTRAL_ITALIC, Vector2(0, 76 + k * 15), notes[k], HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL, UiStyle.TERRACOTTA)
		var danger := breaches >= ceili(GameState.MAX_BREACHES * 0.7)
		draw_string(UiStyle.SPECTRAL_MEDIUM, Vector2(count_x, y + 12), "%d / %d" % [breaches, GameState.MAX_BREACHES],
			HORIZONTAL_ALIGNMENT_LEFT, -1, COUNT, UiStyle.TERRACOTTA if danger else UiStyle.INK_SOFT)

	# The sheet, drawn here rather than by the WorldTag's panel (a flat box reads as
	# clip art): soft shadow, uneven worn edges, darkening where it curls into the
	# rolls, fibres and a stain or two, then the rolls on their turned handles
	func _paper() -> void:
		var l := -MARGIN.x + 4.0
		var r := size.x + MARGIN.z - 4.0
		var t := -MARGIN.y
		var b := size.y + MARGIN.w
		var outline := _sheet_outline(l, r, t, b)
		# Shadow: the sheet again, dropped and spread, faint
		for i in 3:
			var sh := PackedVector2Array()
			for pt in outline:
				sh.append(pt + Vector2(signf(pt.x - size.x * 0.5) * i, 2.0 + i * 1.5))
			draw_colored_polygon(sh, Color(0.08, 0.05, 0.02, 0.14))
		# Paper, a shade darker toward the foot
		var cols := PackedColorArray()
		for pt in outline:
			cols.append(PAPER.lerp(PAPER_DARK, clampf((pt.y - t) / (b - t), 0.0, 1.0) * 0.18))
		draw_polygon(outline, cols)
		# Where it curls into each roll
		for side: float in [-1.0, 1.0]:
			var x_roll := l if side < 0 else r
			var x_in := x_roll - side * 22.0
			var clear := Color(PAPER_DARK, 0.0)
			var deep := Color(PAPER_DARK.darkened(0.15), 0.55)
			draw_polygon(PackedVector2Array([Vector2(x_in, t + 1.5), Vector2(x_roll, t + 1.5), Vector2(x_roll, b - 1.5), Vector2(x_in, b - 1.5)]),
				PackedColorArray([clear, deep, deep, clear]))
		# Fibres, specks, stains: seeded, so the sheet doesn't shimmer on redraw
		var rng := RandomNumberGenerator.new()
		rng.seed = 1917
		for i in 70:
			var p := Vector2(rng.randf_range(l + 8, r - 8), rng.randf_range(t + 3, b - 3))
			var d := Vector2(rng.randf_range(3.0, 9.0), rng.randf_range(-0.8, 0.8))
			draw_line(p, p + d, Color(EDGE, rng.randf_range(0.03, 0.07)), 1.0, true)
		for i in 45:
			draw_circle(Vector2(rng.randf_range(l + 6, r - 6), rng.randf_range(t + 2, b - 2)), rng.randf_range(0.4, 0.9),
				Color(EDGE, rng.randf_range(0.06, 0.14)))
		for c: Vector2 in [Vector2(size.x * 0.78, size.y * 0.35), Vector2(size.x * 0.2, size.y * 0.9)]:
			for k in 4:
				draw_circle(c, 7.0 + k * 3.5, Color(PAPER_DARK, 0.035))
		# Worn edge line, broken where the tail leaves the foot
		var mid := size.x * 0.5
		for i in outline.size() - 1:
			var a := outline[i]
			var z := outline[i + 1]
			if a.y > b - 3 and z.y > b - 3 and absf((a.x + z.x) * 0.5 - mid) < TAIL.x * 0.5 + 1.0:
				continue
			draw_line(a, z, Color(EDGE, 0.6), 1.0, true)
		draw_line(Vector2(l + 6, t + 1.5), Vector2(r - 6, t + 1.5), Color(1, 1, 1, 0.35), 1.0, true)
		# Tail toward the scribe
		var tail := PackedVector2Array([Vector2(mid - TAIL.x * 0.5, b - 1.5), Vector2(mid + TAIL.x * 0.5, b - 1.5), Vector2(mid, b + TAIL.y)])
		draw_colored_polygon(PackedVector2Array([tail[0] + Vector2(0, 2), tail[1] + Vector2(0, 2), tail[2] + Vector2(0, 2.5)]), Color(0.08, 0.05, 0.02, 0.15))
		draw_colored_polygon(tail, PAPER.lerp(PAPER_DARK, 0.18))
		draw_polyline(PackedVector2Array([tail[0] + Vector2(0, 1), tail[2], tail[1] + Vector2(0, 1)]), Color(EDGE, 0.6), 1.0, true)
		for x_roll: float in [l, r]:
			_roll(x_roll, t, b)

	# Head edge left to right, foot edge back; gently uneven, like worn papyrus
	func _sheet_outline(l: float, r: float, t: float, b: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		var x := l
		while x < r:
			pts.append(Vector2(x, t + 0.6 * sin(x * 0.11) + 0.35 * sin(x * 0.43 + 1.3)))
			x += 5.0
		pts.append(Vector2(r, t))
		x = r
		while x > l:
			pts.append(Vector2(x, b + 0.6 * sin(x * 0.13 + 2.0) + 0.35 * sin(x * 0.37)))
			x -= 5.0
		pts.append(Vector2(l, b))
		pts.append(pts[0])
		return pts

	# The sheet rolled round a wooden rod; the rod's turned handles stand out top and
	# bottom
	func _roll(cx: float, t: float, b: float) -> void:
		var rw := 7.0   # half-width of the rolled paper
		for dir: float in [-1.0, 1.0]:
			var base := t - 2.0 if dir < 0 else b + 2.0
			var tip := base + dir * 8.0
			_cylinder(Rect2(cx - 2.8, minf(base, tip), 5.6, 8.0), WOOD)
			# Collar against the roll
			_cylinder(Rect2(cx - rw + 1.5, base - 2.5 if dir < 0 else base, (rw - 1.5) * 2.0, 2.5), WOOD.darkened(0.1))
			# Turned knob
			var k := Vector2(cx, tip + dir * 1.5)
			draw_circle(k + Vector2(0, 1.0), 5.8, Color(0.08, 0.05, 0.02, 0.25))
			draw_circle(k, 5.6, WOOD.darkened(0.4))
			draw_circle(k, 4.6, WOOD)
			draw_circle(k + Vector2(-1.5, -1.5), 2.0, WOOD.lightened(0.35))
		# The rolled paper, round-shaded, the spiral's edge at each end
		_cylinder(Rect2(cx - rw, t - 2.0, rw * 2.0, b - t + 4.0), PAPER.darkened(0.04))
		for y: float in [t - 2.0, b + 2.0]:
			draw_line(Vector2(cx - rw, y), Vector2(cx + rw, y), Color(EDGE, 0.55), 1.0, true)
		for y: float in [t + 0.5, b - 0.5]:
			draw_line(Vector2(cx - rw + 1.5, y), Vector2(cx + rw - 1.5, y), Color(EDGE, 0.18), 1.0, true)
		for x: float in [cx - rw, cx + rw]:
			draw_line(Vector2(x, t - 2.0), Vector2(x, b + 2.0), Color(EDGE, 0.5), 1.0, true)

	# Shaded like a cylinder lit from the upper left: dark rim, light band, falloff
	func _cylinder(rc: Rect2, c: Color) -> void:
		var stops := [[0.0, c.darkened(0.35)], [0.28, c.lightened(0.28)], [0.55, c], [1.0, c.darkened(0.45)]]
		for i in stops.size() - 1:
			var x0: float = rc.position.x + rc.size.x * stops[i][0]
			var x1: float = rc.position.x + rc.size.x * stops[i + 1][0]
			var c0: Color = stops[i][1]
			var c1: Color = stops[i + 1][1]
			draw_polygon(PackedVector2Array([Vector2(x0, rc.position.y), Vector2(x1, rc.position.y), Vector2(x1, rc.end.y), Vector2(x0, rc.end.y)]),
				PackedColorArray([c0, c1, c1, c0]))
