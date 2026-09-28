extends SceneTree

# Screenshots of the tower-defence layer (GDD §5.6) for the website: a watch post with
# its slinger at work as enemies come on, and the same site at evening with the sun
# arc running low and a wave on its way.
#   Godot --path . --script res://tools/td_shots.gd -- --nostory <out_dir>
# Writes td_post.png (HUD), td_post_close.png (no HUD), td_evening.png (HUD).

var _out := ""
var _main: Node3D
var _gs: Node
var _frame := 0
var _t := 0.0
var _state := "wait_work"
var _mark := 0.0
var _players: Array = []
var _post: Node3D

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
		_main.director.begin()
	if _frame < 3:
		return false
	_t += delta
	var waves: Node = _main.get_node("WaveManager")
	var cam: Camera3D = _main.get_node("Camera3D")
	match _state:
		"wait_work":
			if _gs.phase == _gs.Phase.WORK:
				waves.stop()
				_stage()
				_mark = _t
				_state = "post"
		"post":
			_frame_cam(cam, Vector2(-8.0, -2.0), 14.0)
			if _t - _mark > 2.4:
				_save("td_post")
				_main.hud.visible = false
				_frame_cam(cam, Vector2(-8.5, -1.5), 10.0)
				_mark = _t
				_state = "close"
		"close":
			_frame_cam(cam, Vector2(-8.5, -1.5), 10.0)
			if _t - _mark > 0.9:
				_save("td_post_close")
				_main.hud.visible = true
				_gs.sun_left = _gs.sun_total * 0.12
				waves.start(_gs.current_day)
				waves._timer = 999.0
				waves._surge_timer = waves.WAVE_WARN + 0.05
				for e in _main.get_node("Enemies").get_children():
					e.queue_free()
				_spawn_enemies(Vector3(-3.0, 0.1, -12.0), 4)
				_mark = _t
				_state = "evening"
		"evening":
			_frame_cam(cam, Vector2(-5.0, -1.0), 16.0)
			if _t - _mark > 6.5:
				_save("td_evening")
				quit(0)
				return true
	return false

func _frame_cam(cam: Camera3D, at: Vector2, size: float) -> void:
	cam.size = size
	cam.global_position = Vector3(at.x, 0.0, at.y) + _main.CAM_OFFSET

func _save(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("td_shots: ", name)

# Four workers at a half-raised stretch, the west post standing and stocked, a few
# enemies coming on from the north
func _stage() -> void:
	_main.set_process(false)
	var wall := _main.get_node("Wall")
	wall.get_node("SheepGate/PillarLeft").stage = 3
	wall.get_node("SheepGate/PillarRight").stage = 2
	wall.get_node("Section1").stage = 2
	wall.get_node("Section3").stage = 1
	_post = _main.get_node("Posts/PostWest")
	while _post.needs("wood"):
		_post.deposit("wood", 1)
	_post.try_build()
	_post.deposit("stone", 1)
	_post.deposit("stone", 1)
	var proto: PackedScene = load("res://scenes/player/player.tscn")
	var players_root: Node3D = _main.get_node("Players")
	_players.append(players_root.get_child(0))
	for i in 3:
		var p := proto.instantiate()
		p.name = str(100 + i)
		p.set_multiplayer_authority(1)
		players_root.add_child(p)
		_players.append(p)
	var spots := [Vector3(-11.0, 0.1, 1.3), Vector3(-5.0, 0.1, 1.5), Vector3(-8.5, 0.1, 5.5), Vector3(-2.5, 0.1, 4.0)]
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
	_spawn_enemies(Vector3(-7.0, 0.1, -13.0), 3)

func _spawn_enemies(at: Vector3, n: int) -> void:
	for i in n:
		var e: Node3D = load("res://scenes/enemy/enemy.tscn").instantiate()
		e.type = 1 if i == 0 else 0
		e.position = at + Vector3(i * 1.6 - 1.6, 0, randf_range(-0.8, 0.8))
		_main.get_node("Enemies").add_child(e, true)
