extends SceneTree

# Frame-time probe on the real game: Main as a solo host with bots, a day under way.
#   Godot --path . --script res://tools/perf_scene.gd -- --nostory [--day=N] [--warm=8] [--secs=20] [--tally]
#       [--off=<script.gd>] [--quality=0..2] [--scale=0.5..1] [--art=0..2] [--window=WxH] [--hide=<node>|@<group>]
# Prints the frame split (node _process / _physics_process time, physics step, render CPU,
# GPU), draws/objects/triangles and, with --tally, the processing nodes by script.
# --off stops that script's callbacks for the measured window (to price one script).
# Vsync is forced off (Settings would put the saved choice back). Not headless: needs the GPU.

class Stamp extends Node:
	var us := 0
	var physics := false
	func _process(_d: float) -> void:
		if not physics:
			us = Time.get_ticks_usec()
	func _physics_process(_d: float) -> void:
		if physics:
			us = Time.get_ticks_usec()

var _main: Node3D
var _frame := 0
var _t := 0.0
var _warm := 8.0
var _secs := 20.0
var _tally := false
var _off := ""
var _quality := -1
var _scale := -1.0
var _art := -1
var _window := Vector2i.ZERO
var _hide: Array[String] = []
var _scatter := false   # --scatter: list the scatter batches by triangles drawn
var _offed := false
var _last_us := 0
var _rows := {}   # name -> PackedFloat64Array
var _p0: Stamp
var _p1: Stamp
var _f0: Stamp
var _f1: Stamp
var _phys_nodes := 0.0   # node _physics_process time summed over this frame's ticks
var _pre_us := 0
var _post_us := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--warm="):
			_warm = a.trim_prefix("--warm=").to_float()
		elif a.begins_with("--secs="):
			_secs = a.trim_prefix("--secs=").to_float()
		elif a.begins_with("--off="):
			_off = a.trim_prefix("--off=")
		elif a.begins_with("--quality="):
			_quality = a.trim_prefix("--quality=").to_int()
		elif a.begins_with("--scale="):
			_scale = a.trim_prefix("--scale=").to_float()
		elif a.begins_with("--art="):
			_art = a.trim_prefix("--art=").to_int()
		elif a.begins_with("--window="):
			var wh := a.trim_prefix("--window=").split("x")
			_window = Vector2i(wh[0].to_int(), wh[1].to_int())
		elif a.begins_with("--hide="):
			_hide.append(a.trim_prefix("--hide="))
		elif a == "--scatter":
			_scatter = true
		elif a == "--tally":
			_tally = true
	root.size = Vector2i(1920, 1080)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	node_added.connect(func(n: Node):
		if n is SubViewport:
			RenderingServer.viewport_set_measure_render_time(n.get_viewport_rid(), true))
	RenderingServer.frame_pre_draw.connect(func(): _pre_us = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func(): _post_us = Time.get_ticks_usec())
	_p0 = _stamp(-1000000, false)
	_p1 = _stamp(1000000, false)
	_f0 = _stamp(-1000000, true)
	_f1 = _stamp(1000000, true)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _stamp(prio: int, physics: bool) -> Stamp:
	var s := Stamp.new()
	s.physics = physics
	if physics:
		s.process_physics_priority = prio
		s.set_process(false)
	else:
		s.process_priority = prio
		s.set_physics_process(false)
	root.add_child.call_deferred(s)
	if physics and prio > 0:
		s.tree_entered.connect(func(): physics_frame.connect(_on_physics_end))
	return s

# physics_frame fires before the tick's nodes run: read the previous tick's span
func _on_physics_end() -> void:
	if _f1.us > _f0.us and _f0.us > 0:
		_phys_nodes += (_f1.us - _f0.us) / 1000.0

func _sample(key: String, v: float) -> void:
	if not _rows.has(key):
		_rows[key] = PackedFloat64Array()
	_rows[key].append(v)

func _process(delta: float) -> bool:
	_frame += 1
	var now := Time.get_ticks_usec()
	var dt_ms := (now - _last_us) / 1000.0
	# The last frame end to end: tree before the nodes, nodes, tree after (deferred calls,
	# transform flush, timers, tweens), RenderingServer.draw, then physics ticks + the rest
	var split := [(_p0.us - _last_us) / 1000.0, (_p1.us - _p0.us) / 1000.0, (_pre_us - _p1.us) / 1000.0,
		(_post_us - _pre_us) / 1000.0, (now - _post_us) / 1000.0]
	_last_us = now
	if _frame == 3:
		var settings := root.get_node("Settings")
		settings.auto_scale = false
		if _quality >= 0:
			settings.quality = _quality
		if _scale > 0.0:
			settings.render_scale = _scale
		if _art >= 0:
			settings.art_style = _art
		settings._apply_graphics()
		if _window != Vector2i.ZERO:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(_window)
		for h in _hide:
			if h.begins_with("@"):
				for n in get_nodes_in_group(h.substr(1)):
					n.set("visible", false)
			else:
				_main.get_node(h).set("visible", false)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_main.director.begin()
		if _scatter:
			_tally_scatter()
	if _frame < 3:
		return false
	_t += delta
	if _t < _warm:
		_phys_nodes = 0.0
		return false
	if not _off.is_empty() and not _offed:
		_offed = true
		_stop(root)
	var vp := root.get_viewport_rid()
	_sample("frame", dt_ms)
	_sample("tree_pre", split[0])
	_sample("nodes_proc", split[1])
	_sample("tree_post", split[2])
	_sample("rs_draw", split[3])
	_sample("ticks_etc", split[4])
	_sample("nodes_phys", _phys_nodes)
	_phys_nodes = 0.0
	_sample("physics", Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_sample("render_cpu", RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu())
	_sample("gpu", RenderingServer.viewport_get_measured_render_time_gpu(vp))
	_sample("draws", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_sample("objects", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	_sample("tris_k", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0)
	_sample("enemies", _main.enemies_root.get_child_count())
	if _t >= _warm + _secs:
		_report()
		return true
	return false

func _stop(n: Node) -> void:
	var s: Script = n.get_script()
	if s and s.resource_path.get_file() == _off:
		n.set_process(false)
		n.set_physics_process(false)
	for c in n.get_children():
		_stop(c)

func _report() -> void:
	var settings := root.get_node("Settings")
	print("--- perf_scene: %d frames, day %d, quality %d, scale %.2f, %s, %s %s---" % [_rows["frame"].size(),
		root.get_node("GameState").current_day, settings.quality, settings.render_scale, root.size,
		["windowed", "min", "max", "full", "excl"][DisplayServer.window_get_mode()], ("off=" + _off + " ") if _off else ""])
	for key in _rows:
		var a: PackedFloat64Array = _rows[key].duplicate()
		a.sort()
		var sum := 0.0
		for v in a:
			sum += v
		print("%-11s avg %8.2f  p50 %8.2f  p95 %8.2f  max %8.2f" % [key, sum / a.size(),
			a[a.size() / 2], a[int(a.size() * 0.95)], a[a.size() - 1]])
	var f: PackedFloat64Array = _rows["frame"]
	print("hitches >33ms %d  >50ms %d  >100ms %d" % [Array(f).filter(func(v): return v > 33.3).size(),
		Array(f).filter(func(v): return v > 50.0).size(), Array(f).filter(func(v): return v > 100.0).size()])
	print("nodes %d  objects %d" % [Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_COUNT)])
	if _tally:
		var rigs := {}
		var parts := 0
		for r in get_nodes_in_group("character_rigs"):
			var o: Node = r.get_parent()
			var s: Script = o.get_script() if o else null
			var k: String = s.resource_path.get_file() if s else str(o.get_path()).get_slice("/", 3)
			var cam := r.get_viewport().get_camera_3d()
			k += " on" if cam and cam.is_position_in_frustum(r.global_position) else " off"
			rigs[k] = rigs.get(k, 0) + 1
			parts += r._parts.size()
		print("rigs ", rigs, " parts ", parts)
		for vp in root.find_children("*", "SubViewport", true, false):
			print("subviewport %s size %s mode %d msaa %d gpu %.2f" % [vp.get_path(), vp.size, vp.render_target_update_mode,
				vp.msaa_3d, RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid())])
		var mm_tris := {}
		for mmi: MultiMeshInstance3D in _main.find_children("*", "MultiMeshInstance3D", true, false):
			var mm := mmi.multimesh
			if mm == null or mm.mesh == null or not mmi.is_visible_in_tree():
				continue
			var tris := 0
			for si in mm.mesh.get_surface_count():
				var arr := mm.mesh.surface_get_arrays(si)
				tris += (arr[Mesh.ARRAY_INDEX].size() if arr[Mesh.ARRAY_INDEX] != null else arr[Mesh.ARRAY_VERTEX].size()) / 3
			var owner_name := str(_main.get_path_to(mmi)).get_slice("/", 0)
			var k := "%s %s" % [owner_name, "shadow" if mmi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF else "noshadow"]
			var row: Array = mm_tris.get(k, [0, 0, 0, AABB()])
			row[0] += 1
			row[1] += mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			row[2] += tris * (mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count)
			var ab := mmi.global_transform * mm.get_aabb()
			row[3] = ab if row[3].size == Vector3.ZERO else row[3].merge(ab)
			mm_tris[k] = row
		for k in mm_tris:
			print("multimesh %-28s mmis %4d  instances %6d  tris %8d  aabb %s" % [k, mm_tris[k][0], mm_tris[k][1], mm_tris[k][2], mm_tris[k][3]])
		var by := {}
		_walk(root, by)
		var keys := by.keys()
		keys.sort_custom(func(x, y): return by[x] > by[y])
		for k in keys.slice(0, 30):
			print("%6d  %s" % [by[k], k])

func _walk(n: Node, by: Dictionary) -> void:
	if n.is_processing() or n.is_physics_processing():
		var s: Script = n.get_script()
		var k: String = (s.resource_path.get_file() if s else n.get_class()) + (" P" if n.is_processing() else "") + (" F" if n.is_physics_processing() else "")
		by[k] = by.get(k, 0) + 1
	for c in n.get_children():
		_walk(c, by)

## Every scatter kind (its tiles summed): instances, triangles per instance, triangles in all,
## tiles, shadow on/off
func _tally_scatter() -> void:
	var kinds := {}
	for mmi: MultiMeshInstance3D in _main.get_node("ScatterLayer").find_children("*", "MultiMeshInstance3D", false, false):
		var mm := mmi.multimesh
		var mesh := mm.mesh
		var tris := 0
		for s in mesh.get_surface_count():
			var a := mesh.surface_get_arrays(s)
			tris += (a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX] != null else a[Mesh.ARRAY_VERTEX].size()) / 3
		var kind := String(mmi.name).get_slice("~", 0)
		if not kinds.has(kind):
			kinds[kind] = [kind, 0, tris, 0, 0, mmi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF]
		kinds[kind][1] += mm.instance_count
		kinds[kind][3] += mm.instance_count * tris
		kinds[kind][4] += 1
	var rows := kinds.values()
	rows.sort_custom(func(a, b): return a[3] > b[3])
	var total := 0
	var nodes := 0
	for r in rows:
		total += r[3]
		nodes += r[4]
	print("scatter: %d kinds in %d batches, %d triangles" % [rows.size(), nodes, total])
	for r in rows.slice(0, 30):
		print("  %-16s n=%6d  tris/inst=%5d  tris=%8d  tiles=%3d  shadow=%s" % r)
