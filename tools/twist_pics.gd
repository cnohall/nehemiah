extends SceneTree

# Stages a twist in the real game and saves the pictures TwistCard shows, one per panel:
#   Godot --path . --script res://tools/twist_pics.gd -- --nostory --day=<a day of the twist> <twist>
# Day per twist: doors 1, beams 5, salvage 9, thick 13, mixing 18, horn 24, haul 30,
# spring 34, night 37, cramped 42, schemes 48 (tools/twist_pics.ps1 runs them all).
# Writes res://art/twist/<twist>_<n>.png, cropped to the plate's picture (440:238). Then
# `Godot --path . --headless --import`, so the card picks the new files up.

const OUT := "res://art/twist"
const SETTLE := 45
const CROP := Vector2i(1160, 627)   # px of the 1920x1080 frame
const PARK := Vector3(90, 0.1, 90)  # where workers not in the picture wait
const RIGHT := Vector3(1, 0, -1)    # the screen's horizontal, along the ground
const DOWN := Vector3(1, 0, 1)      # toward the camera

var _twist := "beams"
var _main: Node3D
var _boot := 0
var _frame := 0   # frames into the current panel
var _step := -1
var _spec := {}
var _foes: Array = []
var _messenger: Node3D

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_twist = a
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1920, 1080)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(_delta: float) -> bool:
	_boot += 1
	if _boot == 3:
		_main.fit_bots(3)
		_main.director.begin()
	if _boot < 3:
		return false
	_frame += 1
	var gs = root.get_node("GameState")
	if _step < 0:
		if gs.phase != gs.Phase.WORK or _main.get_node("Players").get_child_count() < 4:
			return false
		_main.set_process(false)
		_main.set_physics_process(false)
		for c in root.find_children("*", "CanvasLayer", true, false):
			c.visible = false   # HUD, tutorial bubbles, everything flat
		_step = 0
		_frame = 0
	if _frame == 0:
		return false
	if _frame == 1:
		_begin_panel()
	_hold()
	if _frame == SETTLE:
		var img := root.get_texture().get_image()
		var r := Rect2i((img.get_size() - CROP) / 2, CROP)
		img.get_region(r).save_png("%s/%s_%d.png" % [OUT, _twist, _step])
		print("saved %s_%d" % [_twist, _step])
		_step += 1
		_frame = 0
		if _step >= 3:
			return true
	return false

# ── Per-panel state ────────────────────────────────────────

func _players() -> Array:
	var out: Array = _main.get_node("Players").get_children()
	out.sort_custom(func(a, b): return a.worker_id() < b.worker_id())
	return out

func _begin_panel() -> void:
	# Clean slate: no foes, no visitor, nothing lying about
	for f in _foes:
		if is_instance_valid(f):
			f.queue_free()
	_foes.clear()
	if _messenger != null and is_instance_valid(_messenger):
		_messenger.queue_free()
		_messenger = null
	for it in _main.get_node("Items").get_children():
		it.queue_free()
	_spec = _stage(_twist, _step)
	for f in _spec.get("foes", []):
		_foes.append(_spawn_foe(f[0], f[1]))
	for l in _spec.get("loads", []):
		_drop(l[0], l[1])
	if _spec.has("messenger"):
		var m = load("res://scenes/messenger/messenger.tscn").instantiate()
		m.position = _spec["messenger"][0]
		root.get_node("NetworkManager").gate_sync(m.get_node("MultiplayerSynchronizer"))
		_main.get_node("Visitors").add_child(m, true)
		m.set_physics_process(false)
		m.set_process(false)
		m.state = _spec["messenger"][1]   # Messenger.State: 1 waiting, 2 leading, 3 leaving
		m._facing = _spec["messenger"][2]
		m.anim = "idle_" + _spec["messenger"][2]
		_messenger = m
	if _spec.has("setup"):
		_spec["setup"].call()

func _hold() -> void:
	# Enemies other than ours (the wave manager may still spawn) go
	for e in _main.get_node("Enemies").get_children():
		if not _foes.has(e):
			e.queue_free()
	for i in _foes.size():
		if _foes[i] != null and is_instance_valid(_foes[i]):
			_foes[i].global_position = _spec["foes"][i][1]
			_foes[i].velocity = Vector3.ZERO
	if _messenger != null and is_instance_valid(_messenger):
		_messenger.global_position = _spec["messenger"][0]
	var crew: Array = _spec.get("crew", [])
	var players := _players()
	for i in players.size():
		var p: Node3D = players[i]
		p.helping_id = 0
		if i < crew.size():
			_put(p, crew[i][0], crew[i][1], crew[i][2])
		else:
			_put(p, PARK + Vector3(i * 2, 0, 0), "down", "")
	for pair in _spec.get("help", []):   # [helper, carrier]: holds the other end of a beam
		players[pair[0]].helping_id = players[pair[1]].worker_id()
	if _spec.has("hold"):
		_spec["hold"].call()
	# Yard signs out; workers' own prompts stay
	for t in _main.find_children("*", "WorldTag", true, false):
		t.visible = _main.get_node("Players").is_ancestor_of(t)
	if _spec.get("night", false):
		var dl = _main.get_node("DayLight")
		dl._target = 1.0
		dl.darkness = 1.0
		dl._apply()
	var cam: Camera3D = _main.camera
	cam.size = _spec.get("size", 9.0)
	var look: Vector3 = _spec["look"]
	cam.global_position = look + Vector3(20, 20, 20)
	cam.look_at(look, Vector3.UP)

func _put(p: Node3D, at: Vector3, facing: String, carry: String) -> void:
	p.global_position = at
	p.velocity = Vector3.ZERO
	p._facing = facing
	if carry != p.carried_kind:
		p.carried_kind = carry
		if carry != "beam":
			p._rebuild_carry_prop()

func _spawn_foe(type: int, at: Vector3) -> Node3D:
	var enemies := _main.get_node("Enemies")
	var before := enemies.get_children()
	_main.get_node("WaveManager")._do_spawn(type, at)
	for e in enemies.get_children():
		if not before.has(e):
			e.set_physics_process(false)
			return e
	return null

func _drop(kind: String, at: Vector3) -> void:
	var item = load("res://scenes/dropped_item/dropped_item.tscn").instantiate()
	item.kind = kind
	item.position = Vector3(at.x, 0.1, at.z)
	root.get_node("NetworkManager").gate_sync(item.get_node("MultiplayerSynchronizer"))
	_main.get_node("Items").add_child(item, true)

# ── The pictures ───────────────────────────────────────────

## A spot `x` metres right of `at` on screen and `y` toward the camera
func _o(at: Vector3, x: float, y: float) -> Vector3:
	return at + RIGHT.normalized() * x + DOWN.normalized() * y

func _gate() -> Node3D:
	for c in _main.get_node("Wall").get_children():
		if c.get_script() != null and c.get_script().resource_path.ends_with("gate.gd"):
			return c
	return null

func _mat() -> Node3D:
	for c in _main.get_children():
		if c.get_script() != null and c.get_script().resource_path.ends_with("relay_mat.gd"):
			return c
	return null

func _sup(n: String) -> Node3D:
	return _main.get_node("Supplies/" + n)

func _rub(n: String) -> Node3D:
	return _main.get_node("Rubble/" + n)

func _section(n: String) -> Node3D:
	return _main.get_node("Wall/" + n)

func _stage(twist: String, i: int) -> Dictionary:
	var E := { "SCOUT": 0, "BRUTE": 1, "RAIDER": 2, "SABOTEUR": 3 }   # Enemy.Type (not referenced: it needs the autoloads)
	match twist + str(i):
		# Sheep Gate: pillars, then timber, then the hung doors with the foe shut out
		"doors0":
			var g := _gate()
			var p2: Vector3 = g._pillars[1].global_position
			return { "look": g.global_position + Vector3(0, 0.8, 0.3), "size": 13.0,
				"crew": [[_o(p2, -0.3, 2.6), "down", "stone"]],
				"setup": func():
					_pillars(g, 0, false)
					g._pillars[0].stage = 3
					g._pillars[1].stage = 1 }
		"doors1":
			var g := _gate()
			return { "look": g.global_position + Vector3(0, 0.8, 0.3), "size": 13.0,
				"crew": [[_o(g.global_position, -2.2, 3.0), "right", "wood"]],
				"setup": func(): _pillars(g, 3, false) }
		"doors2":
			var g := _gate()
			var gp: Vector3 = g.global_position
			return { "look": gp + Vector3(0, 0.8, -0.3), "size": 13.0,
				"crew": [[gp + Vector3(0, 0, 1.0), "down", ""]],
				"foes": [[E.SCOUT, gp + Vector3(0, 0.1, -2.6)]],
				"setup": func(): _pillars(g, 3, true) }
		# Fish Gate: a beam dragged alone, a friend takes the other end, both carry it
		"beams0":
			return { "look": _bm(-0.6), "size": 8.5,
				"crew": [[_bm(0.0), "right", "beam"]] }
		"beams1":
			return { "look": _bm(-1.2), "size": 8.5,
				"crew": [[_bm(0.5), "right", "beam"], [_bm(-3.0), "right", ""]] }
		"beams2":
			return { "look": _bm(0.0), "size": 8.5,
				"crew": [[_bm(2.0), "right", "beam"], [_bm(-2.0), "right", ""]],
				"help": [[1, 0]] }
		# Jeshanah Gate: no quarry pile, dig the rubble, the far heaps pay double
		"salvage0":
			var pile := _sup("StockStone")
			return { "look": _o(pile.global_position, 0.5, 0.5), "size": 12.0,
				"crew": [[_o(pile.global_position, 1.6, 1.8), "down", ""]],
				"setup": func(): pile.visible = false }
		"salvage1":
			var h := _rub("HeapEast")
			return { "look": h.global_position, "size": 10.0,
				"crew": [[_o(h.global_position, -0.6, 2.0), "down", "stone"]] }
		"salvage2":
			var h := _rub("HeapOutsideWest")
			return { "look": _o(h.global_position, 0, 1.0), "size": 10.0,
				"crew": [[_o(h.global_position, -2.0, 2.0), "right", "stone"]],
				"foes": [[E.SCOUT, _o(h.global_position, 4.5, -2.0)]] }
		# Broad Wall: double thick, four hands, it stands up to the brutes
		"thick0":
			var s := _section("Section3")
			return { "look": s.global_position + Vector3(0, 0.5, 0.6), "size": 11.0,
				"crew": [[_o(s.global_position, -1.0, 3.0), "down", ""]],
				"setup": func(): _wall(s, 3, 2) }
		"thick1":
			var s := _section("Section3")
			var at: Vector3 = s.global_position
			return { "look": at + Vector3(0, 0.5, 1.0), "size": 10.0,
				"crew": [[_o(at, -2.6, 2.2), "up", "stone"], [_o(at, -0.9, 2.2), "up", ""],
					[_o(at, 0.9, 2.2), "up", "stone"], [_o(at, 2.6, 2.2), "up", ""]],
				"setup": func(): _wall(s, 1, 0) }
		"thick2":
			var s := _section("Section3")
			var at: Vector3 = s.global_position
			return { "look": at + Vector3(0, 0.5, -0.5), "size": 11.0,
				"crew": [[_o(at, -2.5, 3.2), "down", ""]],
				"foes": [[E.BRUTE, _o(at, 0.5, -3.0)], [E.BRUTE, _o(at, 3.2, -3.4)]],
				"setup": func(): _wall(s, 3, 2) }
		# Tower of Ovens: lime and water to the trough, it mixes, the mortar goes to the wall
		"mixing0":
			var t := _sup("Trough")
			return { "look": _o(t.global_position, 0, 1.5), "size": 10.0,
				"crew": [[_o(t.global_position, -3.0, 2.0), "right", "lime"],
					[_o(t.global_position, 1.0, 3.6), "up", "water"]],
				"setup": func(): _trough(t, false, false, false) }
		"mixing1":
			var t := _sup("Trough")
			return { "look": _o(t.global_position, 0, 1.0), "size": 9.0,
				"crew": [[_o(t.global_position, -2.2, 1.6), "right", ""]],
				"setup": func(): _trough(t, true, true, false),
				"hold": func(): t.mix_left = 3.0 }
		"mixing2":
			var t := _sup("Trough")
			return { "look": _o(t.global_position, -1.5, 1.0), "size": 9.0,
				"crew": [[_o(t.global_position, -3.0, 1.8), "down", "mortar"]],
				"setup": func(): _trough(t, false, false, true) }
		# Valley Gate: surges, the horn, the gathering
		"horn0":
			return { "look": Vector3(1, 0, -3), "size": 15.0,
				"crew": [[Vector3(-5, 0.1, 3.5), "up", ""]],
				"foes": [[E.SCOUT, Vector3(-6, 0.1, -6.5)], [E.SCOUT, Vector3(-2, 0.1, -8)],
					[E.SCOUT, Vector3(3, 0.1, -6.8)], [E.SCOUT, Vector3(8, 0.1, -8.5)],
					[E.BRUTE, Vector3(1, 0.1, -10)]] }
		"horn1":
			return { "look": Vector3(0, 0, 4), "size": 9.0,
				"crew": [[Vector3(0, 0.1, 4), "down", ""]],
				"setup": func(): _horn(Vector3(0, 0, 4)) }
		"horn2":
			return { "look": Vector3(0, 0, 4), "size": 10.0,
				"crew": [[Vector3(0, 0.1, 4), "down", ""], [Vector3(-2.6, 0.1, 5.4), "right", ""],
					[Vector3(3.0, 0.1, 5.6), "left", ""], [Vector3(1.8, 0.1, 2.0), "down", ""]],
				"setup": func(): _horn(Vector3(0, 0, 4)) }
		# Dung Gate: a long haul — the relay mat halfway, or a load handed to a friend
		"haul0":
			var st := _sup("StockStone")
			return { "look": Vector3(21, 0, 5), "size": 24.0,
				"crew": [[_o(st.global_position, 0.5, 2.0), "left", "stone"]] }
		"haul1":
			var mat := _mat()
			var sl: Array = mat.slots()
			return { "look": mat.global_position, "size": 8.5,
				"crew": [[_o(mat.global_position, -2.8, 1.4), "right", "stone"],
					[_o(mat.global_position, 2.8, 1.6), "left", ""]],
				"loads": [["stone", sl[0]], ["stone", sl[1]], ["wood", sl[2]]] }
		"haul2":
			var at := Vector3(22, 0.1, 6)
			return { "look": at, "size": 8.5,
				"crew": [[_o(at, -1.3, 0.0), "right", "stone"], [_o(at, 1.3, 0.0), "left", ""]] }
		# Fountain Gate: the pool by the wall, water at hand, a breather
		"spring0":
			var pool := _sup("StockWater")
			return { "look": _o(pool.global_position, 0.5, 0.5), "size": 11.0,
				"crew": [[_o(pool.global_position, 2.2, 2.4), "left", ""]] }
		"spring1":
			var t := _sup("Trough")
			return { "look": _o(t.global_position, -1.8, 0.4), "size": 9.0,
				"crew": [[_o(t.global_position, -3.4, 1.4), "right", "water"]] }
		"spring2":
			var pool := _sup("StockWater")
			var at: Vector3 = pool.global_position
			return { "look": _o(at, 3.2, 1.8), "size": 10.0,
				"crew": [[_o(at, 1.4, 2.6), "down", ""], [_o(at, 3.4, 2.6), "down", ""], [_o(at, 5.4, 2.6), "down", ""]] }
		# Water Gate: night falls, each worker carries a lamp, the foe comes out of the dark
		"night0":
			return { "look": Vector3(2, 0, 3), "size": 17.0, "night": true,
				"crew": [[Vector3(0, 0.1, 5), "right", ""], [Vector3(6, 0.1, 7), "left", ""]] }
		"night1":
			return { "look": Vector3(0, 0.6, 4), "size": 7.5, "night": true,
				"crew": [[Vector3(0, 0.1, 4), "down", ""]] }
		"night2":
			return { "look": Vector3(0, 0.6, 1), "size": 11.0, "night": true,
				"crew": [[Vector3(-1, 0.1, 3.6), "up", ""]],
				"foes": [[E.SCOUT, Vector3(2.5, 0.1, -3.4)]] }
		# Horse Gate: priests' houses between the yard and the wall, narrow lanes, hand loads over
		"cramped0":
			return { "look": Vector3(8, 0, 5), "size": 18.0,
				"crew": [[Vector3(6.5, 0.1, 10.5), "up", "stone"]] }
		"cramped1":
			return { "look": Vector3(6.5, 0, 8.0), "size": 9.0,
				"crew": [[Vector3(6.5, 0.1, 8.0), "up", "stone"], [Vector3(6.5, 0.1, 10.6), "up", "wood"]] }
		"cramped2":
			return { "look": Vector3(6.5, 0, 8.6), "size": 8.5,
				"crew": [[Vector3(6.5, 0.1, 10.0), "up", "stone"], [Vector3(6.5, 0.1, 7.9), "down", ""]] }
		# East Gate: a messenger from the enemy, led away, or ignored
		"schemes0":
			var at := Vector3(4, 0.1, 7)
			return { "look": _o(at, 0.8, 0), "size": 8.5,
				"crew": [[at, "right", ""]],
				"messenger": [_o(at, 1.7, 0.3), 1, "left"] }
		"schemes1":
			var at := Vector3(14, 0.1, 9)
			return { "look": _o(at, 0, 0), "size": 11.0,
				"crew": [[_o(at, -1.8, 0), "right", ""]],
				"messenger": [_o(at, 0.4, 0), 2, "right"] }
		"schemes2":
			var s := _section("Section3")
			var at: Vector3 = s.global_position
			return { "look": _o(at, 1.0, 1.4), "size": 10.0,
				"crew": [[_o(at, -1.0, 2.6), "up", "stone"]],
				"messenger": [_o(at, 5.2, 2.6), 3, "right"] }
	return { "look": Vector3(0, 0, 4) }

## A spot on the Fish Gate yard along the screen's horizontal
func _bm(x: float) -> Vector3:
	return _o(Vector3(-3.0, 0.1, 5.0), x, 0.0)

# ── State helpers ──────────────────────────────────────────

## Both pillars of a gate to `stage` (0 bare … 3 mortared), doors hung or not
func _pillars(g: Node3D, stage: int, doors: bool) -> void:
	for p in g._pillars:
		p.stage = stage
	g.finished = doors
	g.pending = 0

func _wall(s: Node3D, stage: int, face: int) -> void:
	s.stage = stage
	s.face = face

func _trough(t: Node3D, lime: bool, water: bool, ready: bool) -> void:
	t.has_lime = lime
	t.has_water = water
	t.mortar_ready = ready
	t.mix_left = 0.0

func _horn(at: Vector3) -> void:
	_main.get_node("Horn")._sound(at, Color(0.86, 0.58, 0.22))
