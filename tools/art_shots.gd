extends SceneTree

# Art-style check: walls raised to every stage, the crew posed around them, shot close
# (hero framing) and at gameplay zoom with the HUD.
#   Godot --path . --script res://tools/art_shots.gd -- --nostory <out_dir> [tag]

var _out := ""
var _tag := "art"
var _main: Node3D
var _frame := 0
var _players: Array = []

# [camera focus (x, z), ortho size, hud?, name]
const SHOTS := [
	[Vector2(6.0, 3.0), 11.0, false, "close"],
	[Vector2(3.0, 4.0), 22.0, true, "gameplay"],
	[Vector2(-2.0, 12.0), 16.0, false, "city"],
]
var _shot := 0
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
	if _frame < 20:
		return false
	_hold += 1
	if _hold == 1:
		var s: Array = SHOTS[_shot]
		var cam: Camera3D = _main.get_node("Camera3D")
		cam.size = s[1]
		cam.global_position = Vector3(s[0].x, 0.0, s[0].y) + _main.CAM_OFFSET
		_main.hud.visible = s[2]
	if _hold == 8:
		root.get_texture().get_image().save_png("%s/%s_%s.png" % [_out, _tag, SHOTS[_shot][3]])
		_shot += 1
		_hold = 0
		if _shot >= SHOTS.size():
			return true
	return false

func _stage() -> void:
	_main.set_process(false)
	_main.get_node("WaveManager").set_process(false)
	var wall := _main.get_node("Wall")
	wall.get_node("Section1").stage = 3
	wall.get_node("Section3").stage = 2
	wall.get_node("Section4").stage = 1
	wall.get_node("TowerRight").stage = 3
	var proto: PackedScene = load("res://scenes/player/player.tscn")
	var players_root: Node3D = _main.get_node("Players")
	_players.append(players_root.get_child(0))
	for i in 3:
		var p := proto.instantiate()
		p.name = str(100 + i)
		p.set_multiplayer_authority(1)
		players_root.add_child(p)
		_players.append(p)
	var spots := [Vector3(4.5, 0.1, 1.3), Vector3(7.5, 0.1, 3.2), Vector3(3.2, 0.1, 4.2), Vector3(9.5, 0.1, 1.4)]
	for i in _players.size():
		var p: Node3D = _players[i]
		p.set_physics_process(false)
		p.global_position = spots[i]
		p.set_slot(i, _main.PLAYER_COLORS[i])
	_players[0].anim = "build_up"
	_players[1].carried_kind = "stone"
	_players[1]._rebuild_carry_prop()
	_players[1].anim = "walk_up"
	_players[2].anim = "idle_down"
	_players[3].anim = "build_up"
	_main.get_node("/root/GameState").set_crew(4)
