extends SceneTree

# Raw captures for the Play Store listing, in the phone layout (touch HUD), one
# language per run. store-assets/render_screenshots.mjs frames and captions them.
#   Godot --path . --resolution 1848x822 --script res://tools/store_shots.gd -- --touch --lang=de <out_dir>
# Writes <out_dir>/<lang>/{1_build,2_wave,3_post,4_evening,5_story,6_join}.png

var _out := "user://store"
var _lang := "en"
var _frame := 0
var _steps := []
var _main: Node
var _gs: Node
var _players: Array = []

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lang="):
			_lang = a.trim_prefix("--lang=")
		elif not a.begins_with("--"):
			_out = a
	_out = _out.path_join(_lang)
	DirAccess.make_dir_recursive_absolute(_out)
	change_scene_to_file("res://scenes/ui/main_menu.tscn")
	var menu := func(): return current_scene
	_steps = [
		[20, func(): TranslationServer.set_locale(_lang); root.get_node("Settings").bot_count = 0],
		[165, func(): menu.call()._open_join(); for c in "KXBQ": menu.call()._type(c)],
		[200, func(): _shot("6_join")],
		[205, func(): menu.call()._on_back(); menu.call()._stop_world(); root.get_node("NetworkManager").host()],
		[380, func(): _main = current_scene; _gs = root.get_node("GameState"); _main.director.begin()],
		[640, func(): _shot("5_story")],
		[645, func(): _main.director.force_story_end()],
		[690, func(): _wait_work()],
	]

func _process(_delta: float) -> bool:
	_frame += 1
	while not _steps.is_empty() and _frame >= _steps[0][0]:
		var step: Array = _steps.pop_front()
		step[1].call()
	return false

func _shot(name: String) -> void:
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("shot ", _lang, " ", name)

# Dawn → work, then the staged scenes one after another (frame counts from now)
func _wait_work() -> void:
	if _gs.phase != _gs.Phase.WORK:
		_steps.push_front([_frame + 10, _wait_work])
		return
	var f := _frame
	_main.get_node("WaveManager").stop()
	_stage()
	_steps = [
		[f + 40, func(): _cam(Vector2(-6.5, 2.0), 13.0); _hide_banner()],
		[f + 60, func(): _shot("1_build")],
		[f + 62, func(): _spawn_enemies(Vector3(-3.0, 0.1, -12.0), 4); _warn_wave(Vector3(-3.0, 0.1, -14.0))],
		[f + 64, func(): _cam(Vector2(-5.0, -2.5), 15.0)],
		[f + 150, func(): _shot("2_wave")],
		[f + 152, func(): _cam(Vector2(-8.5, -1.0), 9.5)],
		[f + 200, func(): _shot("3_post")],
		[f + 202, func(): _gs.sun_left = _gs.sun_total * 0.12],
		[f + 204, func(): _cam(Vector2(-5.0, 0.0), 14.0)],
		[f + 275, func(): _shot("4_evening")],
		[f + 280, func(): quit()],
	]

func _cam(at: Vector2, size: float) -> void:
	var cam: Camera3D = _main.get_node("Camera3D")
	cam.size = size
	cam.global_position = Vector3(at.x, 0.0, at.y) + _main.CAM_OFFSET

func _hide_banner() -> void:
	_main.hud.banner.hide()

func _warn_wave(at: Vector3) -> void:
	get_root().get_tree().call_group("offscreen_alerts", "ping", at, Color(0.86, 0.38, 0.26), "Wave", 30.0)

# A half-raised Sheep Gate, the west watch post up and stocked, four workers at it
func _stage() -> void:
	_main.set_process(false)
	var wall := _main.get_node("Wall")
	wall.get_node("SheepGate/PillarLeft").stage = 3
	wall.get_node("SheepGate/PillarRight").stage = 2
	wall.get_node("Section1").stage = 2
	wall.get_node("Section3").stage = 1
	var post := _main.get_node("Posts/PostWest")
	while post.needs("wood"):
		post.deposit("wood", 1)
	post.try_build()
	post.deposit("stone", 1)
	post.deposit("stone", 1)
	var proto: PackedScene = load("res://scenes/player/player.tscn")
	var players_root: Node3D = _main.get_node("Players")
	_players.append(players_root.get_child(0))
	for i in 3:
		var p := proto.instantiate()
		p.name = str(100 + i)
		p.set_multiplayer_authority(1)
		players_root.add_child(p)
		_players.append(p)
	var spots := [Vector3(-10.5, 0.1, 1.2), Vector3(-5.2, 0.1, 1.4), Vector3(-8.0, 0.1, 5.2), Vector3(-2.8, 0.1, 3.6)]
	for i in _players.size():
		var p: Node3D = _players[i]
		p.set_physics_process(false)
		p.global_position = spots[i]
		p.set_slot(i, _main.PLAYER_COLORS[i])
	_players[0].anim = "build_up"
	_players[1].anim = "build_up"
	_players[2].carried_kind = "stone"
	_players[2]._rebuild_carry_prop()
	_players[2].anim = "walk_up"
	_players[3].anim = "windup_up"
	_gs.set_crew(4)
	_main._assign_colors()
	_main._refresh_hud()

func _spawn_enemies(at: Vector3, n: int) -> void:
	for i in n:
		var e: Node3D = load("res://scenes/enemy/enemy.tscn").instantiate()
		e.type = 1 if i == 0 else 0
		e.position = at + Vector3(i * 1.6 - 2.4, 0, randf_range(-0.8, 0.8))
		_main.get_node("Enemies").add_child(e, true)
