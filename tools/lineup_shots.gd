extends SceneTree

# Readability check: the four player slots side by side at gameplay zoom, in each pose
# (idle, carrying, working, winding up, downed), plus two enemies for contrast.
#   Godot --path . --script res://tools/lineup_shots.gd -- --nostory <out_dir>

var _out := ""
var _main: Node3D
var _frame := 0
var _players: Array = []
const POSES := ["idle", "carry", "build", "windup", "collapse"]
var _pose := 0
var _hold := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
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
	if _hold == 12:
		root.get_texture().get_image().save_png("%s/pose_%s.png" % [_out, POSES[_pose]])
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
	var me: Node3D = players_root.get_child(0)
	_players.append(me)
	for i in 3:
		var p := proto.instantiate()
		p.name = str(100 + i)
		p.set_multiplayer_authority(1)
		players_root.add_child(p)
		_players.append(p)
	for i in _players.size():
		_players[i].set_physics_process(false)
		_players[i].global_position = Vector3(-3.0 + i * 2.0, 0.1, 6.0 + i * -2.0) + Vector3(0, 0, 2)
		_players[i].set_slot(i, _main.PLAYER_COLORS[i])
	var cam: Camera3D = _main.get_node("Camera3D")
	var c: Vector3 = Vector3(0.0, 0.0, 5.0)
	cam.global_position = c + _main.CAM_OFFSET
	_main.hud.hide()
	_main.get_node("/root/GameState").set_crew(4)

func _apply_pose(pose: String) -> void:
	for p in _players:
		p.carried_kind = ""
		p._rebuild_carry_prop()
		match pose:
			"idle": p.anim = "idle_down"
			"carry":
				p.carried_kind = ["stone", "wood", "mortar", "stone"][_players.find(p)]
				p._rebuild_carry_prop()
				p.anim = "walk_down"
			"build": p.anim = "build_right"
			"windup":
				p.anim = "windup_right"
				p.whirling = true
			"collapse":
				p.whirling = false
				p.anim = "collapse"
