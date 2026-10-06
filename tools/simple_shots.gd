extends SceneTree

# The Sheep Gate (the first stretch: timber and stone only, no posts) in the simple game, screenshots:
#   Godot --path . --script res://tools/simple_shots.gd -- --nostory --simple <out_dir>
# Not headless — needs the GPU. Shots:
#   simple_overview  whole stretch (fixed camera): bare footings, timber and stone piles, no posts
#   simple_yard      follow camera at the yard: what a new player sees first
#   simple_stages    one wall framed, one with courses, one finished in stone (does the finish read?)
#   simple_doors     pillars stand: the doors want timber
#   full_day2        the full game on day 2, for comparison: posts, timber and mortar out

var _out := ""
var _main: Node3D
var _t := 0.0
var _step := 0
var _frame := 0
var _walls: Array = []
var _gate: Node

const SCRIPT := [
	[0.5, "begin"],
	[7.0, "fixed"],
	[8.5, "shot", "simple_overview"],
	[8.6, "follow_yard"],
	[10.0, "shot", "simple_yard"],
	[10.1, "stages"],
	[11.8, "shot", "simple_stages"],
	[11.9, "doors"],
	[13.6, "shot", "simple_doors"],
	[13.7, "full"],
	[15.5, "fixed"],
	[17.0, "shot", "full_day2"],
	[17.1, "quit"],
]

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	root.get_node("Settings").simple_game = true
	root.get_node("Settings").fixed_camera = false
	root.size = Vector2i(1920, 1080)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	if _frame == 3:
		_main.fit_bots(0)
	_t += delta
	var me: Node3D = _main.get_node("Players").get_child(0)
	var gs: Node = root.get_node("GameState")
	var settings: Node = root.get_node("Settings")
	# Keep the shots calm: no foes, no clock running out
	_main.get_node("WaveManager").stop()
	for e in _main.get_node("Enemies").get_children():
		e.queue_free()
	if gs.sun_total > 0.0:
		gs.sun_left = gs.sun_total * 0.8
	while _step < SCRIPT.size() and _t >= SCRIPT[_step][0]:
		var s: Array = SCRIPT[_step]
		_step += 1
		match s[1]:
			"begin":
				_main.director.begin()
			"fixed":
				settings.fixed_camera = true
				_main.refresh_camera()
			"follow_yard":
				settings.fixed_camera = false
				_main.refresh_camera()
				var y: Vector2 = gs.yard_center()
				me.global_position = Vector3(y.x, 0.1, y.y - 1.5)
			"stages":
				_walls = get_nodes_in_group("build_sites").filter(func(n): return n.has_method("cost_for") and not n.decorative)
				_gate = get_nodes_in_group("build_sites").filter(func(n): return n.has_method("blocks_workers") and not n.has_method("cost_for"))[0]
				var plain := _walls.filter(func(w): return not w in _gate._pillars)
				plain.sort_custom(func(a, b): return a.global_position.x < b.global_position.x)
				# Three side by side near the middle: framed (as it starts), courses, finished
				var mid := plain.size() / 2
				if plain.size() >= 3:
					plain[mid - 1].stage = plain[mid - 1].Stage.FRAMED
					plain[mid].stage = plain[mid].Stage.STACKED
					plain[mid + 1].stage = plain[mid + 1].Stage.MORTARED
					me.global_position = plain[mid].global_position + Vector3(0, 0, 4.0)
			"doors":
				for p in _gate._pillars:
					p.stage = p.Stage.MORTARED
				me.global_position = _gate.global_position + Vector3(0, 0, 4.5)
			"full":
				settings.simple_game = false
				gs.share_rules()
				gs._apply(2, 0, gs.Phase.WORK, 0, 0, 0)
				gs.day_changed.emit(2)
			"shot":
				var img := root.get_texture().get_image()
				img.save_png("%s/%s.png" % [_out, s[2]])
				print("shot ", s[2])
			"quit":
				return true
	return false
