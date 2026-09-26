extends SceneTree

# Character close-ups for art review: the four trades shoulder to shoulder, framed
# tight (ortho 4.6) so faces, hair and props can be judged against the mockup.
#   Godot --path . --script res://tools/char_shots.gd -- --nostory <out_dir> [tag]

var _out := ""
var _tag := "char"
var _main: Node3D
var _frame := 0
var _players: Array = []
var _enemies: Array = []
const POSES := ["front", "carry", "side", "build"]
var _pose := 0
var _hold := 0

func _initialize() -> void:
	var rest: Array = []
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			rest.append(a)
	_out = rest[0]
	if rest.size() > 1:
		_tag = rest[1]
	root.size = Vector2i(1920, 1080)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_stage()
	if _frame < 6:
		return false
	_hold += 1
	if _hold == 1:
		_apply_pose(POSES[_pose])
	if _hold == 14:
		root.get_texture().get_image().save_png("%s/%s_%s.png" % [_out, _tag, POSES[_pose]])
		_pose += 1
		_hold = 0
		if _pose >= POSES.size():
			return true
	return false

func _stage() -> void:
	_main.set_process(false)
	_main.get_node("WaveManager").set_process(false)
	var proto: PackedScene = load("res://scenes/player/player.tscn")
	var players_root: Node3D = _main.get_node("Players")
	_players.append(players_root.get_child(0))
	for i in 3:
		var p := proto.instantiate()
		p.name = str(100 + i)
		p.set_multiplayer_authority(1)
		players_root.add_child(p)
		_players.append(p)
	# A screen-horizontal row: +x -z is screen right on the iso camera
	var c := Vector3(2.0, 0.1, 6.0)
	var step := Vector3(0.85, 0, -0.85)
	for i in _players.size():
		_players[i].set_physics_process(false)
		_players[i].global_position = c + step * (i - 1.5)
		_players[i].set_slot(i, _main.PLAYER_COLORS[i])
	# One enemy behind, for contrast
	var e: Node3D = load("res://scenes/enemy/enemy.tscn").instantiate()
	e.type = 1
	_main.get_node("Enemies").add_child(e, true)
	e.set_physics_process(false)
	e.global_position = c + Vector3(-2.2, 0, -2.2)
	_enemies.append(e)
	var cam: Camera3D = _main.get_node("Camera3D")
	cam.global_position = c + Vector3(-0.2, 0, -2.6) + _main.CAM_OFFSET
	cam.size = 4.6
	_main.hud.hide()
	_main.get_node("/root/GameState").set_crew(4)

func _apply_pose(pose: String) -> void:
	for i in _players.size():
		var p: Node3D = _players[i]
		p.carried_kind = ""
		p._rebuild_carry_prop()
		match pose:
			"front": p.anim = "idle_down"
			"carry":
				p.carried_kind = ["stone", "wood", "mortar", "stone"][i]
				p._rebuild_carry_prop()
				p.anim = "walk_down"
			"side": p.anim = "idle_left" if i % 2 == 0 else "idle_right"
			"build": p.anim = "build_right"
	for e in _enemies:
		e.anim = "idle_down"
