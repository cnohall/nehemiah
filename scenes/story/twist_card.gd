class_name TwistCard
extends Control

# What a new twist asks of the crew, in three drawn panels (Overcooked's recipe card):
# plain woodcut pictograms on parchment, one caption under each. Shown as a story slide
# ("twist" key, StoryData) on the first day of a section that brings it, so the whole
# crew has seen it before the work starts — the dawn banner alone was read by nobody.

const PANEL      := Vector2(440, 330)
const GAP        := 36.0
const TOP        := 0.09    # of height: the row's top edge
const CAPTION_SZ := 24
const INK        := UiStyle.INK
const ROBE       := [Color(0.62, 0.30, 0.16), Color(0.25, 0.42, 0.52), Color(0.46, 0.52, 0.24), Color(0.55, 0.40, 0.58)]
const FOE        := Color(0.20, 0.15, 0.12)
const FOE_RIM    := Color(0.50, 0.12, 0.10)
const STONE      := Color(0.72, 0.68, 0.60)
const TIMBER     := Color(0.55, 0.36, 0.20)
const MORTAR     := Color(0.60, 0.60, 0.58)
const LIME       := Color(0.95, 0.94, 0.90)
const WATER      := Color(0.33, 0.52, 0.66)
const WALL_C     := Color(0.86, 0.80, 0.68)

var twist := "":
	set(v):
		twist = v
		_shots = _load_shots(v)
		queue_redraw()
var _shots: Array[Texture2D] = []   # in-game pictures (tools/twist_pics.gd); a null falls back to the drawn pictogram

func _ready() -> void:
	resized.connect(queue_redraw)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## The three captions for a twist (English; translated when drawn)
static func captions(t: String) -> Array:
	match t:
		"doors": return ["Raise both pillars of the gate", "Then bring timber to the gap", "Hang the doors — the crew walks through, the foe can't"]
		"beams": return ["A beam dragged alone goes slowly", "A friend takes the other end [%s]" % "interact", "Carry it together to the wall"]
		"salvage": return ["No stone pile here", "Dig the stone out of the rubble heaps", "Heaps outside the wall hold twice as much — if you dare"]
		"mixing": return ["Lime and water into the trough", "It mixes by itself — wait a moment", "Carry the mortar to the wall"]
		"thick": return ["The Broad Wall is built in two faces", "Outer face first, then the inner — four hands at the work", "Filled and mortared, it takes half the blows"]
		"ruins": return ["Some stretches still stand: only the mortar is wanted", "Some are burned: pull the charred timbers down [%s]" % "interact", "Then build as usual"]
		"horn": return ["They come up the valley in surges", "Sound the horn [%s] where help is needed" % "horn", "Everyone gathers to the horn"]
		"haul": return ["The yard is far from the wall", "Stack loads on the relay mat halfway", "Or hand a load to a friend [%s]" % "drop"]
		"spring": return ["The pool is by the wall", "Water close at hand — mortar comes quickly", "A quiet stretch: catch your breath"]
		"night": return ["Night falls on the work", "Torches light the way — each worker has a lamp", "The foe comes out of the dark"]
		"cramped": return ["Priests' houses between yard and wall", "Narrow lanes — one at a time", "Pass loads over rather than queue"]
		"schemes": return ["A messenger calls you down to Ono", "Go with him and you're led away from the work", "Ignore him — he gives up and leaves"]
	return []

func _draw() -> void:
	var caps := captions(twist)
	if caps.is_empty():
		return
	var n := caps.size()
	var scale_k := minf(1.0, (size.x - 80.0) / (PANEL.x * n + GAP * (n - 1)))
	var panel := PANEL * scale_k
	var row_w := panel.x * n + GAP * scale_k * (n - 1)
	var x0 := (size.x - row_w) * 0.5
	var y0 := size.y * TOP
	var font: Font = UiStyle.SPECTRAL_MEDIUM
	for i in n:
		var r := Rect2(Vector2(x0 + i * (panel.x + GAP * scale_k), y0), panel)
		# Parchment plate with a thin gold rule and a number
		draw_rect(r.grow(3.0), Color(UiStyle.GOLD, 0.7))
		draw_rect(r, UiStyle.PARCHMENT)
		draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.72)), Color(UiStyle.PARCHMENT_DEEP, 0.55))
		draw_string(UiStyle.CINZEL_BOLD, r.position + Vector2(12, 28) * scale_k, ["I", "II", "III", "IV"][i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(20 * scale_k), Color(UiStyle.TERRACOTTA, 0.8))
		var pic := Rect2(r.position + Vector2(0, 8) * scale_k, Vector2(r.size.x, r.size.y * 0.66))
		var shot: Texture2D = _shots[i] if i < _shots.size() else null
		if shot != null:
			var frame := Rect2(r.position, Vector2(r.size.x, r.size.y * 0.72))   # the picture fills the plate above the caption
			draw_texture_rect(shot, frame, false)
			draw_rect(frame, Color(INK, 0.5), false, 2.0)
		else:
			_panel(i, pic, scale_k)
		# Caption under the picture, inside the plate
		var cap := _fill_keys(tr(caps[i]))
		draw_multiline_string(font, Vector2(r.position.x + 14 * scale_k, r.position.y + r.size.y * 0.78 + 4),
			cap, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 28 * scale_k, int(CAPTION_SZ * scale_k), 2, INK)
		if i < n - 1:
			var a := Vector2(r.end.x + 6 * scale_k, r.position.y + r.size.y * 0.4)
			_arrow(a, a + Vector2(GAP * scale_k - 12 * scale_k, 0), UiStyle.GOLD, 3.0 * scale_k)

static func _load_shots(t: String) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for i in 3:
		var path := "res://art/twist/%s_%d.png" % [t, i]
		out.append(load(path) if ResourceLoader.exists(path) else null)
	return out

## "[interact]" → the key or button in use
func _fill_keys(s: String) -> String:
	for action: String in ["interact", "drop", "horn", "dash", "throw"]:
		s = s.replace("[%s]" % action, "[%s]" % InputMode.key(action))
	return s

# ── Pictures ───────────────────────────────────────────────

func _panel(i: int, r: Rect2, k: float) -> void:
	k *= PANEL.x / 300.0   # the pictures were laid out on a 300 px plate
	var g := r.position.y + r.size.y * 0.86     # ground line
	var cx := r.get_center().x
	var u := 42.0 * k                           # one figure's height unit
	draw_rect(Rect2(r.position.x, g, r.size.x, r.end.y - g + 8.0 * k), Color(UiStyle.TERRACOTTA, 0.10))
	draw_line(Vector2(r.position.x + 12 * k, g), Vector2(r.end.x - 12 * k, g), Color(INK, 0.35), 2.0 * k)
	match twist + str(i):
		"doors0":
			_pillar(Vector2(cx - 50 * k, g), u, 1.0); _pillar(Vector2(cx + 50 * k, g), u, 1.0)
			_worker(Vector2(cx, g), u, 0, "stone")
		"doors1":
			_pillar(Vector2(cx - 50 * k, g), u, 1.0); _pillar(Vector2(cx + 50 * k, g), u, 1.0)
			_worker(Vector2(cx - 95 * k, g), u, 1, "wood")
			_arrow(Vector2(cx - 70 * k, g - u * 1.4), Vector2(cx - 10 * k, g - u * 1.4), UiStyle.TERRACOTTA, 3 * k)
		"doors2":
			_pillar(Vector2(cx - 50 * k, g), u, 1.0); _pillar(Vector2(cx + 50 * k, g), u, 1.0)
			draw_rect(Rect2(cx - 36 * k, g - u * 2.1, 72 * k, u * 2.1), TIMBER)
			draw_line(Vector2(cx, g - u * 2.1), Vector2(cx, g), Color(INK, 0.6), 2 * k)
			_worker(Vector2(cx - 12 * k, g), u * 0.8, 2, "")
			_foe(Vector2(cx + 100 * k, g), u)
			_cross(Vector2(cx + 100 * k, g - u * 2.6), 10 * k)
		"beams0":
			var ub := 54.0 * k
			_worker(Vector2(cx - 70 * k, g), ub, 0, "")
			_beam_tilted(Vector2(cx - 62 * k, g - ub * 1.05), Vector2(cx + 90 * k, g - 5 * k), k)
			_hand(Vector2(cx - 60 * k, g - ub * 1.0), ub)
			_dust(Vector2(cx + 90 * k, g), k)
		"beams1":
			var ub := 54.0 * k
			_worker(Vector2(cx - 80 * k, g), ub, 0, "")
			_worker(Vector2(cx + 80 * k, g), ub, 1, "")
			_ring(Vector2(cx + 80 * k, g), 30 * k)
			_beam_level(Vector2(cx - 120 * k, g - ub * 1.05), Vector2(cx + 120 * k, g - ub * 1.05), k)
			_hand(Vector2(cx - 80 * k, g - ub * 1.0), ub)
			_hand(Vector2(cx + 80 * k, g - ub * 1.0), ub)
		"beams2":
			var ub := 54.0 * k
			_wall(Rect2(cx + 75 * k, g - ub * 1.3, 60 * k, ub * 1.3), 3)
			_worker(Vector2(cx - 95 * k, g), ub, 0, "")
			_worker(Vector2(cx + 15 * k, g), ub, 1, "")
			_beam_level(Vector2(cx - 130 * k, g - ub * 1.05), Vector2(cx + 50 * k, g - ub * 1.05), k)
			_hand(Vector2(cx - 95 * k, g - ub * 1.0), ub)
			_hand(Vector2(cx + 15 * k, g - ub * 1.0), ub)
		"salvage0":
			_heap(Vector2(cx - 50 * k, g), 34 * k, false)
			_stack(Vector2(cx + 40 * k, g), k, STONE)
			_cross(Vector2(cx + 40 * k, g - 30 * k), 22 * k)
		"salvage1":
			_heap(Vector2(cx - 30 * k, g), 44 * k, true)
			_worker(Vector2(cx + 40 * k, g), u, 0, "stone")
		"salvage2":
			_wall(Rect2(cx - 16 * k, g - u * 1.6, 32 * k, u * 1.6), 3)
			_heap(Vector2(cx - 80 * k, g), 26 * k, true)
			_heap(Vector2(cx + 80 * k, g), 44 * k, true)
			_heap(Vector2(cx + 95 * k, g), 30 * k, true)
			_foe(Vector2(cx + 125 * k, g), u * 0.8)
		"mixing0":
			_bin(Vector2(cx - 90 * k, g), k, LIME)
			_jar(Vector2(cx - 50 * k, g), k)
			_trough(Vector2(cx + 50 * k, g), k, 0.0)
			_arrow(Vector2(cx - 30 * k, g - 30 * k), Vector2(cx + 20 * k, g - 30 * k), UiStyle.TERRACOTTA, 3 * k)
		"mixing1":
			_trough(Vector2(cx, g), k, 0.6)
			_sand_glass(Vector2(cx, g - 90 * k), k)
		"mixing2":
			_trough(Vector2(cx - 80 * k, g), k, 1.0)
			_worker(Vector2(cx, g), u, 2, "mortar")
			_wall(Rect2(cx + 60 * k, g - u * 1.5, 50 * k, u * 1.5), 3)
		"thick0":
			_wall(Rect2(cx - 40 * k, g - u * 1.8, 80 * k, u * 1.8), 3)
			_wall(Rect2(cx - 100 * k, g - u * 1.8, 30 * k, u * 1.8), 3)
		"thick1":
			_wall(Rect2(cx - 40 * k, g - u * 1.2, 80 * k, u * 1.2), 2)
			for j in 4:
				_worker(Vector2(cx - 90 * k + j * 60 * k, g), u * 0.8, j, "stone" if j % 2 == 0 else "")
		"thick2":
			_wall(Rect2(cx - 50 * k, g - u * 1.8, 80 * k, u * 1.8), 3)
			_foe(Vector2(cx + 70 * k, g), u * 1.15, true)
			_shield(Vector2(cx - 10 * k, g - u * 2.3), 16 * k)
		"ruins0":
			_wall(Rect2(cx - 40 * k, g - u * 1.7, 80 * k, u * 1.7), 2)
			_worker(Vector2(cx + 80 * k, g), u, 0, "mortar")
		"ruins1":
			_wall(Rect2(cx - 100 * k, g - u * 0.5, 70 * k, u * 0.5), 1)
			for j in 4:
				draw_line(Vector2(cx - 30 * k + j * 22 * k, g), Vector2(cx - 10 * k + j * 22 * k, g - u * (1.1 + 0.2 * (j % 2))), Color(INK, 0.85), 5 * k)
			_worker(Vector2(cx - 120 * k, g), u, 0, "")
			_hand(Vector2(cx - 100 * k, g - u * 0.9), u)
		"ruins2":
			_wall(Rect2(cx - 60 * k, g - u * 1.6, 100 * k, u * 1.6), 3)
			_worker(Vector2(cx + 80 * k, g), u, 1, "stone")
		"horn0":
			for j in 3:
				_foe(Vector2(cx - 40 * k + j * 40 * k, g - j * 6 * k), u * 0.8)
			_arrow(Vector2(cx + 100 * k, g - u * 2.2), Vector2(cx - 90 * k, g - u * 2.2), FOE_RIM, 3 * k)
		"horn1":
			_worker(Vector2(cx, g), u, 0, "")
			_horn(Vector2(cx + 14 * k, g - u * 1.5), k)
			for j in 3:
				draw_arc(Vector2(cx + 30 * k, g - u * 1.6), (18 + j * 14) * k, -0.8, 0.8, 12, Color(UiStyle.AMBER, 0.8 - j * 0.2), 2.5 * k)
		"horn2":
			_ring(Vector2(cx, g), 30 * k)
			_standard(Vector2(cx, g), u, 0)
			for j in [-1, 1]:
				_worker(Vector2(cx + j * 90 * k, g), u, 1 if j < 0 else 2, "")
				_arrow(Vector2(cx + j * 70 * k, g - u), Vector2(cx + j * 30 * k, g - u), UiStyle.TERRACOTTA, 3 * k)
		"haul0":
			_stack(Vector2(cx - 110 * k, g), k, STONE)
			_wall(Rect2(cx + 90 * k, g - u * 1.4, 36 * k, u * 1.4), 2)
			for j in 5:
				draw_circle(Vector2(cx - 70 * k + j * 30 * k, g - 6 * k), 3 * k, Color(INK, 0.4))
		"haul1":
			_mat(Vector2(cx, g), k)
			_worker(Vector2(cx - 80 * k, g), u, 0, "stone")
			_worker(Vector2(cx + 80 * k, g), u, 1, "")
			_arrow(Vector2(cx - 60 * k, g - u * 1.2), Vector2(cx - 20 * k, g - u * 0.6), UiStyle.TERRACOTTA, 3 * k)
		"haul2":
			_worker(Vector2(cx - 40 * k, g), u, 0, "stone")
			_worker(Vector2(cx + 40 * k, g), u, 1, "")
			_arrow(Vector2(cx - 22 * k, g - u * 2.1), Vector2(cx + 22 * k, g - u * 2.1), UiStyle.TERRACOTTA, 3 * k)
		"spring0":
			draw_colored_polygon(_ellipse(Vector2(cx - 40 * k, g - 4 * k), Vector2(70 * k, 12 * k)), WATER)
			_wall(Rect2(cx + 60 * k, g - u * 1.3, 40 * k, u * 1.3), 2)
		"spring1":
			_jar(Vector2(cx - 50 * k, g), k)
			_trough(Vector2(cx + 40 * k, g), k, 1.0)
		"spring2":
			_worker(Vector2(cx - 30 * k, g), u, 0, "")
			_worker(Vector2(cx + 30 * k, g), u, 1, "")
			draw_circle(Vector2(cx, g - u * 2.8), 14 * k, Color(UiStyle.GOLD, 0.8))
		"night0":
			draw_rect(Rect2(r.position, Vector2(r.size.x, g - r.position.y)), Color(0.10, 0.12, 0.20, 0.7))
			draw_circle(Vector2(cx + 80 * k, r.position.y + 30 * k), 12 * k, Color(0.93, 0.91, 0.84))
			_wall(Rect2(cx - 60 * k, g - u * 1.4, 100 * k, u * 1.4), 2)
		"night1":
			draw_rect(Rect2(r.position, Vector2(r.size.x, g - r.position.y)), Color(0.10, 0.12, 0.20, 0.7))
			draw_circle(Vector2(cx - 50 * k, g - u * 1.2), 44 * k, Color(UiStyle.AMBER, 0.28))
			_torch(Vector2(cx - 50 * k, g), u)
			_worker(Vector2(cx + 30 * k, g), u, 0, "")
			draw_circle(Vector2(cx + 48 * k, g - u * 1.1), 20 * k, Color(UiStyle.AMBER, 0.3))
		"night2":
			draw_rect(Rect2(r.position, Vector2(r.size.x, g - r.position.y)), Color(0.10, 0.12, 0.20, 0.8))
			_foe(Vector2(cx + 70 * k, g), u)
			draw_circle(Vector2(cx - 50 * k, g - u * 1.2), 44 * k, Color(UiStyle.AMBER, 0.28))
			_worker(Vector2(cx - 50 * k, g), u, 0, "")
		"cramped0":
			for j in 3:
				_house(Rect2(cx - 120 * k + j * 84 * k, g - u * 1.6, 60 * k, u * 1.6))
		"cramped1":
			_house(Rect2(cx - 120 * k, g - u * 1.6, 70 * k, u * 1.6))
			_house(Rect2(cx + 50 * k, g - u * 1.6, 70 * k, u * 1.6))
			_worker(Vector2(cx, g), u, 0, "stone")
		"cramped2":
			_house(Rect2(cx - 20 * k, g - u * 1.6, 40 * k, u * 1.6))
			_worker(Vector2(cx - 70 * k, g), u, 0, "stone")
			_worker(Vector2(cx + 70 * k, g), u, 1, "")
			_arrow(Vector2(cx - 50 * k, g - u * 2.2), Vector2(cx + 50 * k, g - u * 2.2), UiStyle.TERRACOTTA, 3 * k)
		"schemes0":
			_worker(Vector2(cx - 40 * k, g), u, 0, "")
			_messenger(Vector2(cx + 40 * k, g), u)
			draw_rect(Rect2(cx + 44 * k, g - u * 1.5, 20 * k, 14 * k), LIME)
		"schemes1":
			_messenger(Vector2(cx + 40 * k, g), u)
			_worker(Vector2(cx - 10 * k, g), u, 0, "")
			_arrow(Vector2(cx + 60 * k, g - u * 0.6), Vector2(cx + 130 * k, g - u * 0.6), Color(INK, 0.5), 3 * k)
			_wall(Rect2(cx - 130 * k, g - u * 1.0, 40 * k, u * 1.0), 1)
		"schemes2":
			_worker(Vector2(cx - 40 * k, g), u, 0, "stone")
			_wall(Rect2(cx - 110 * k, g - u * 1.5, 40 * k, u * 1.5), 3)
			_messenger(Vector2(cx + 80 * k, g), u * 0.8)
			_arrow(Vector2(cx + 100 * k, g - u), Vector2(cx + 140 * k, g - u), Color(INK, 0.5), 3 * k)

# ── Shapes ─────────────────────────────────────────────────

func _worker(at: Vector2, u: float, slot: int, load: String) -> void:
	var robe: Color = ROBE[slot % ROBE.size()]
	draw_colored_polygon(_ellipse(at + Vector2(0, u * 0.03), Vector2(u * 0.55, u * 0.09)), Color(INK, 0.18))
	var body := PackedVector2Array([at + Vector2(-u * 0.42, 0), at + Vector2(u * 0.42, 0),
		at + Vector2(u * 0.26, -u * 1.2), at + Vector2(-u * 0.26, -u * 1.2)])
	draw_colored_polygon(body, robe)
	draw_polyline(body + PackedVector2Array([body[0]]), INK, maxf(1.5, u * 0.05))
	var head := at + Vector2(0, -u * 1.48)
	draw_circle(head, u * 0.3, Color(0.78, 0.60, 0.44))
	draw_arc(head, u * 0.3, 0, TAU, 20, INK, maxf(1.5, u * 0.05))
	draw_colored_polygon(PackedVector2Array([head + Vector2(-u * 0.34, -u * 0.05), head + Vector2(u * 0.34, -u * 0.05),
		head + Vector2(u * 0.2, -u * 0.36), head + Vector2(-u * 0.2, -u * 0.36)]), UiStyle.CREAM)
	if load.is_empty():
		return
	var top := head + Vector2(0, -u * 0.62)
	match load:
		"stone":
			draw_rect(Rect2(top - Vector2(u * 0.3, u * 0.22), Vector2(u * 0.6, u * 0.4)), STONE)
			draw_rect(Rect2(top - Vector2(u * 0.3, u * 0.22), Vector2(u * 0.6, u * 0.4)), INK, false, 1.5)
		"wood":
			draw_rect(Rect2(top - Vector2(u * 0.5, u * 0.14), Vector2(u * 1.0, u * 0.26)), TIMBER)
			draw_rect(Rect2(top - Vector2(u * 0.5, u * 0.14), Vector2(u * 1.0, u * 0.26)), INK, false, 1.5)
		"mortar":
			draw_colored_polygon(PackedVector2Array([top + Vector2(-u * 0.36, -u * 0.18), top + Vector2(u * 0.36, -u * 0.18),
				top + Vector2(u * 0.26, u * 0.2), top + Vector2(-u * 0.26, u * 0.2)]), Color(0.66, 0.52, 0.32))
			draw_rect(Rect2(top + Vector2(-u * 0.3, -u * 0.22), Vector2(u * 0.6, u * 0.1)), MORTAR)

func _foe(at: Vector2, u: float, brute := false) -> void:
	var w := u * (0.55 if brute else 0.4)
	var body := PackedVector2Array([at + Vector2(-w, 0), at + Vector2(w, 0), at + Vector2(w * 0.6, -u * 1.25), at + Vector2(-w * 0.6, -u * 1.25)])
	draw_colored_polygon(body, FOE)
	draw_polyline(body + PackedVector2Array([body[0]]), FOE_RIM, maxf(1.5, u * 0.06))
	var head := at + Vector2(0, -u * 1.5)
	draw_circle(head, u * 0.28, FOE)
	draw_arc(head, u * 0.28, 0, TAU, 20, FOE_RIM, maxf(1.5, u * 0.06))
	# Spear
	draw_line(at + Vector2(w + 4, 0), at + Vector2(w + 4, -u * 2.1), Color(0.35, 0.25, 0.16), maxf(2.0, u * 0.07))
	draw_colored_polygon(PackedVector2Array([at + Vector2(w + 4, -u * 2.35), at + Vector2(w - 2, -u * 2.08), at + Vector2(w + 10, -u * 2.08)]), Color(0.60, 0.48, 0.30))

func _messenger(at: Vector2, u: float) -> void:
	var body := PackedVector2Array([at + Vector2(-u * 0.4, 0), at + Vector2(u * 0.4, 0), at + Vector2(u * 0.24, -u * 1.25), at + Vector2(-u * 0.24, -u * 1.25)])
	draw_colored_polygon(body, Color(0.42, 0.30, 0.44))
	draw_polyline(body + PackedVector2Array([body[0]]), INK, 1.5)
	draw_circle(at + Vector2(0, -u * 1.5), u * 0.28, Color(0.78, 0.60, 0.44))
	draw_arc(at + Vector2(0, -u * 1.5), u * 0.28, 0, TAU, 20, INK, 1.5)

func _pillar(at: Vector2, u: float, built: float) -> void:
	_wall(Rect2(at.x - u * 0.45, at.y - u * 2.6 * built, u * 0.9, u * 2.6 * built), 4)

## A block wall: `rows` courses of offset stones
func _wall(r: Rect2, rows: int) -> void:
	draw_rect(r, WALL_C)
	var h := r.size.y / maxi(1, rows)
	for j in rows:
		var y := r.end.y - (j + 1) * h
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(INK, 0.35), 1.5)
		var off := 0.0 if j % 2 == 0 else h * 0.9
		var x := r.position.x + off + h * 1.8
		while x < r.end.x - 2.0:
			draw_line(Vector2(x, y), Vector2(x, y + h), Color(INK, 0.3), 1.5)
			x += h * 1.8
	draw_rect(r, INK, false, 2.0)

func _beam_level(a: Vector2, b: Vector2, k: float) -> void:
	draw_line(a, b, TIMBER, 18 * k)
	draw_line(a + Vector2(0, -9 * k), b + Vector2(0, -9 * k), INK, 1.5)
	draw_line(a + Vector2(0, 9 * k), b + Vector2(0, 9 * k), INK, 1.5)

func _beam_tilted(a: Vector2, b: Vector2, k: float) -> void:
	draw_line(a, b, TIMBER, 18 * k)
	var n := (b - a).orthogonal().normalized() * 9 * k
	draw_line(a + n, b + n, INK, 1.5)
	draw_line(a - n, b - n, INK, 1.5)

func _hand(at: Vector2, u: float) -> void:
	draw_circle(at, u * 0.1, Color(0.78, 0.60, 0.44))
	draw_arc(at, u * 0.1, 0, TAU, 12, INK, 1.5)

func _dust(at: Vector2, k: float) -> void:
	for j in 4:
		draw_circle(at + Vector2(j * 10 * k - 6 * k, -4 * k - (j % 2) * 5 * k), (5 + j) * k, Color(UiStyle.RULE, 0.5))

func _heap(at: Vector2, rad: float, stones: bool) -> void:
	draw_colored_polygon(_half_ellipse(at, Vector2(rad * 1.4, rad * 0.8)), Color(0.36, 0.30, 0.26))
	if stones:
		for j in 4:
			var p := at + Vector2((j - 1.5) * rad * 0.5, -rad * (0.3 + 0.15 * (j % 2)))
			draw_rect(Rect2(p - Vector2(rad * 0.18, rad * 0.14), Vector2(rad * 0.36, rad * 0.26)), STONE)

func _stack(at: Vector2, k: float, col: Color) -> void:
	for j in 3:
		for m in 3 - j:
			var p := at + Vector2((m - (2 - j) * 0.5) * 22 * k - 11 * k, -(j + 1) * 16 * k)
			draw_rect(Rect2(p, Vector2(20 * k, 14 * k)), col)
			draw_rect(Rect2(p, Vector2(20 * k, 14 * k)), INK, false, 1.2)

func _bin(at: Vector2, k: float, col: Color) -> void:
	var r := Rect2(at + Vector2(-20 * k, -34 * k), Vector2(40 * k, 34 * k))
	draw_rect(r, TIMBER)
	draw_rect(Rect2(r.position + Vector2(4 * k, 4 * k), Vector2(32 * k, 10 * k)), col)
	draw_rect(r, INK, false, 1.5)

func _jar(at: Vector2, k: float) -> void:
	draw_colored_polygon(_ellipse(at + Vector2(0, -20 * k), Vector2(16 * k, 20 * k)), Color(0.72, 0.46, 0.30))
	draw_rect(Rect2(at + Vector2(-7 * k, -46 * k), Vector2(14 * k, 8 * k)), Color(0.72, 0.46, 0.30))
	draw_colored_polygon(_ellipse(at + Vector2(0, -44 * k), Vector2(6 * k, 2 * k)), WATER)

func _trough(at: Vector2, k: float, full: float) -> void:
	var r := Rect2(at + Vector2(-44 * k, -26 * k), Vector2(88 * k, 26 * k))
	draw_rect(r, Color(0.62, 0.58, 0.52))
	if full > 0.0:
		draw_rect(Rect2(r.position + Vector2(5 * k, 4 * k), Vector2(78 * k, 8 * k)), MORTAR.lerp(LIME, 1.0 - full))
	draw_rect(r, INK, false, 1.5)
	if full > 0.0 and full < 1.0:
		draw_line(at + Vector2(10 * k, -20 * k), at + Vector2(30 * k, -60 * k), TIMBER, 4 * k)

func _sand_glass(at: Vector2, k: float) -> void:
	var s := 16 * k
	draw_colored_polygon(PackedVector2Array([at + Vector2(-s, -s), at + Vector2(s, -s), at]), Color(UiStyle.AMBER, 0.8))
	draw_colored_polygon(PackedVector2Array([at, at + Vector2(s, s), at + Vector2(-s, s)]), Color(UiStyle.AMBER, 0.4))
	draw_polyline(PackedVector2Array([at + Vector2(-s, -s), at + Vector2(s, -s), at + Vector2(-s, s), at + Vector2(s, s), at + Vector2(-s, -s)]), INK, 1.5)

func _mat(at: Vector2, k: float) -> void:
	draw_colored_polygon(_half_ellipse(at, Vector2(50 * k, 8 * k)), Color(0.70, 0.58, 0.36))
	_stack(at + Vector2(0, -4 * k), k * 0.7, STONE)

func _house(r: Rect2) -> void:
	draw_rect(r, Color(0.93, 0.90, 0.84))
	draw_rect(Rect2(r.get_center() + Vector2(-r.size.x * 0.12, r.size.y * 0.1), Vector2(r.size.x * 0.24, r.size.y * 0.4)), Color(0.25, 0.42, 0.52))
	draw_rect(r, INK, false, 1.5)

func _torch(at: Vector2, u: float) -> void:
	draw_line(at, at + Vector2(0, -u * 1.8), TIMBER, 4)
	draw_circle(at + Vector2(0, -u * 1.95), u * 0.18, UiStyle.AMBER)
	draw_circle(at + Vector2(0, -u * 2.0), u * 0.09, UiStyle.CREAM)

func _horn(at: Vector2, k: float) -> void:
	draw_polyline(PackedVector2Array([at, at + Vector2(12 * k, -6 * k), at + Vector2(24 * k, -4 * k), at + Vector2(30 * k, 6 * k)]), Color(0.85, 0.76, 0.58), 6 * k)

func _standard(at: Vector2, u: float, slot: int) -> void:
	draw_line(at, at + Vector2(0, -u * 2.4), TIMBER, 3)
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, -u * 2.4), at + Vector2(u * 0.8, -u * 2.2), at + Vector2(0, -u * 1.9)]), ROBE[slot])

func _shield(at: Vector2, s: float) -> void:
	draw_colored_polygon(PackedVector2Array([at + Vector2(-s, -s), at + Vector2(s, -s), at + Vector2(s, 0), at + Vector2(0, s * 1.2), at + Vector2(-s, 0)]), UiStyle.OLIVE)
	draw_polyline(PackedVector2Array([at + Vector2(-s, -s), at + Vector2(s, -s), at + Vector2(s, 0), at + Vector2(0, s * 1.2), at + Vector2(-s, 0), at + Vector2(-s, -s)]), INK, 1.5)

func _ring(at: Vector2, rad: float) -> void:
	draw_colored_polygon(_ellipse(at, Vector2(rad, rad * 0.3)), Color(UiStyle.CREAM, 0.6))
	draw_polyline(_ellipse(at, Vector2(rad, rad * 0.3)) + PackedVector2Array([at + Vector2(rad, 0)]), UiStyle.AMBER, 2.0)

func _cross(at: Vector2, s: float) -> void:
	draw_line(at + Vector2(-s, -s), at + Vector2(s, s), UiStyle.TERRACOTTA, 4)
	draw_line(at + Vector2(s, -s), at + Vector2(-s, s), UiStyle.TERRACOTTA, 4)

func _arrow(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	draw_line(a, b, col, w)
	var d := (b - a).normalized()
	var n := d.orthogonal()
	draw_colored_polygon(PackedVector2Array([b + d * w * 2.0, b - d * w * 1.5 + n * w * 2.2, b - d * w * 1.5 - n * w * 2.2]), col)

func _ellipse(c: Vector2, r: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for j in 24:
		var a := TAU * j / 24.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	return pts

func _half_ellipse(c: Vector2, r: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for j in 13:
		var a := PI + PI * j / 12.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	return pts
