extends SceneTree

# Checks the tower-defence layer (GDD §5.6) offline:
#   Godot --path . --script res://tools/td_test.gd -- --nostory --day=5 <out_dir>   (the Sheep Gate has no posts)
# - posts: timber raises a watch post, stone feeds it, the slinger throws at an enemy
#   in range and the ammo runs down
# - waves: a warned wave comes in as a pack
# - sun: a day has a sun clock and the whole stretch is the goal; nightfall with work
#   left ends the day, the next day has the same light and the same goal. On a section's last day (run with --day=4) nightfall
#   loses the run with reason "stars"
# Shots of the post saved to out_dir. Exit code 0 = every check passed.

var _out := ""
var _main: Node3D
var _frame := 0
var _t := 0.0
var _state := "wait_work"
var _mark := 0.0
var _fails := 0
var _post: Node3D
var _enemy: Node3D
var _tally := {}
var _hits := 0
var _day1_sun := 0.0
var _gs: Node

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	root.size = Vector2i(1920, 1080)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_gs = root.get_node("GameState")
		_main.director.day_tallied.connect(func(s): _tally = s)
		_main.director.begin()
	if _frame < 3:
		return false
	_t += delta
	if _t > 150.0:
		_fail("timed out in " + _state)
		return _finish()
	var waves: Node = _main.get_node("WaveManager")
	match _state:
		"wait_work":
			if _gs.phase == _gs.Phase.WORK:
				_check(_gs.sun_total > 30.0, "sun clock set (%.0f s)" % _gs.sun_total)
				_day1_sun = _gs.sun_total
				if _gs.last_day_of_section():
					_state = "last_day"
					_gs.sun_left = 0.3
				else:
					_state = "post"
		"last_day":
			if _gs.phase == _gs.Phase.LOST:
				_check(_gs.loss_reason == "stars", "last-day nightfall lost the run (%s)" % _gs.loss_reason)
				return _finish()
		"post":
			waves.stop()
			for e in _main.get_node("Enemies").get_children():
				e.queue_free()
			var posts := get_nodes_in_group("watch_posts")
			if _gs.first_stretch():   # the first stretch has no posts
				_check(posts.is_empty(), "no watch posts on the first stretch (run with --day=5 for the post checks)")
				return _finish()
			_check(posts.size() == 2, "two watch posts (%d)" % posts.size())
			_post = posts[0]
			_check(_post.needs("wood") and not _post.needs("stone"), "bare post wants timber")
			var n := 0
			while _post.needs("wood"):
				_post.deposit("wood", 1)
				n += 1
			_check(_post.can_build() and _post.try_build() and _post.built, "post raised with %d timber" % n)
			_check(_post.needs("stone") and _post.deposit("stone", 1) and _post.deposit("stone", 1), "post takes stone")
			_check(_post.ammo == _post.SHOTS_PER_LOAD * 2, "two loads = %d throws (%d)" % [_post.SHOTS_PER_LOAD * 2, _post.ammo])
			_enemy = load("res://scenes/enemy/enemy.tscn").instantiate()
			_enemy.type = 1   # brute: survives a few stones
			_enemy.position = _post.global_position + Vector3(1.5, 0.1, -7.0)
			_main.get_node("Enemies").add_child(_enemy, true)
			_main.get_node("Players").get_child(0).global_position = _post.global_position + Vector3(1.5, 0.1, 1.5)
			_mark = _t
			_state = "fire"
		"fire":
			var alive := is_instance_valid(_enemy)
			if alive:
				_hits = maxi(_hits, _enemy.hits)
			if _t - _mark > 1.8 and _t - _mark < 1.9:
				_shot("post")
				_shot("hud", 22.0)
			if _t - _mark > 5.5:
				_check(_post.ammo < _post.SHOTS_PER_LOAD * 2, "slinger threw (%d left)" % _post.ammo)
				_check(_hits > 0, "enemy hit %d times" % _hits)
				if alive:
					_enemy.queue_free()
				# A wave: fast-forward to its warning
				waves.start(_gs.current_day)
				waves._timer = 999.0   # no trickle, just the wave
				waves._surge_timer = waves.WAVE_WARN + 0.05
				_mark = _t
				_state = "wave"
		"wave":
			var count := _main.get_node("Enemies").get_child_count()
			if _t - _mark > waves.WAVE_WARN + 3.0:
				_check(count >= waves.WAVE_BASE, "a wave came in (%d enemies)" % count)
				waves.stop()
				for e in _main.get_node("Enemies").get_children():
					e.queue_free()
				# Nightfall with work left
				_gs.sun_left = 0.3
				_mark = _t
				_state = "nightfall"
		"nightfall":
			if _gs.phase == _gs.Phase.DUSK and not _tally.is_empty():
				_check(_tally.get("unfinished", 0) > 0, "nightfall ended the day, %d unfinished" % _tally.get("unfinished", 0))
				_state = "carried"
		"carried":
			if _gs.phase == _gs.Phase.DUSK:
				_main.director.force_ready()   # the tally waits for the crew now
			if _gs.phase == _gs.Phase.WORK:
				_check(_gs.targets_total == 6 and _gs.targets_done < 6, "the whole stretch is still the goal (%d/%d)" % [_gs.targets_done, _gs.targets_total])
				_check(is_equal_approx(_gs.sun_total, _day1_sun), "every day has the same light (%.0f s)" % _gs.sun_total)
				_check(_post.built, "post still standing the next day")
				return _finish()
	return false

func _shot(name: String, size := 12.0) -> void:
	if _out.is_empty():
		return
	var cam: Camera3D = _main.get_node("Camera3D")
	cam.size = size
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(_out + "/%s.png" % name)

func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1

func _fail(what: String) -> void:
	_check(false, what)

func _finish() -> bool:
	print("td_test: %d failed" % _fails)
	quit(1 if _fails else 0)
	return true
