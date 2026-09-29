extends SceneTree

# Key art for the Steam capsules (store/steam/render.mjs crops and titles it):
#   Godot --path . --script res://tools/capsule_shots.gd -- --nostory <out_dir> [size] [wait_s]
# A crew of four at a half-raised Sheep Gate stretch, a slinger winding up as raiders
# come on, no HUD and no world tags (GameState.attract). Renders 3840x2160 so every
# capsule, down to the 748x896 vertical, crops from one frame. The window can't be
# bigger than the screen, so a 4K SubViewport shares the world and mirrors the camera.
# size = camera ortho size (default 11), wait_s = seconds of play before the shot.
# Writes <out_dir>/key_art.png.

var _out := ""
var _size := 11.0
var _wait := 2.6
var _main: Node3D
var _gs: Node
var _frame := 0
var _t := 0.0
var _mark := -1.0
var _players: Array = []
var _vp: SubViewport
var _cam4k: Camera3D

func _initialize() -> void:
	var rest: Array = []
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			rest.append(a)
	_out = rest[0]
	if rest.size() > 1:
		_size = float(rest[1])
	if rest.size() > 2:
		_wait = float(rest[2])
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	_vp = SubViewport.new()
	_vp.size = Vector2i(3840, 2160)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.world_3d = root.world_3d
	_cam4k = Camera3D.new()
	_vp.add_child(_cam4k)
	root.add_child(_vp)

func _process(delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_gs = root.get_node("GameState")
		_main.director.begin()
	if _frame < 3:
		return false
	_t += delta
	if _mark < 0.0 and _gs.phase == _gs.Phase.WORK:
		_main.get_node("WaveManager").stop()
		_stage()
		_mark = _t
	if _mark >= 0.0:
		var cam: Camera3D = _main.get_node("Camera3D")
		cam.size = _size
		cam.global_position = Vector3(-5.6, 0.0, 0.6) + _main.CAM_OFFSET
		_cam4k.projection = cam.projection
		_cam4k.size = cam.size
		_cam4k.near = cam.near
		_cam4k.far = cam.far
		_cam4k.environment = cam.environment
		_cam4k.attributes = cam.attributes
		_cam4k.global_transform = cam.global_transform
		_cam4k.current = true
		if _t - _mark > _wait:
			var img := _vp.get_texture().get_image()
			img.save_png("%s/key_art.png" % _out)
			print("capsule_shots: key_art %dx%d" % [img.get_width(), img.get_height()])
			quit(0)
			return true
	if _t > 60.0:
		push_error("capsule_shots: timed out")
		return true
	return false

# Two builders on the stretch, a carrier bringing stone, a slinger winding up at the
# raiders coming on from the north
func _stage() -> void:
	_main.set_process(false)
	_main.hud.hide()
	_gs.attract = true
	var wall := _main.get_node("Wall")
	wall.get_node("SheepGate/PillarLeft").stage = 3
	wall.get_node("SheepGate/PillarRight").stage = 2
	wall.get_node("Section1").stage = 2
	wall.get_node("Section3").stage = 1
	# Exactly four workers: the host plus whatever bots the saved settings brought, topped
	# up or trimmed
	var players_root: Node3D = _main.get_node("Players")
	var proto: PackedScene = load("res://scenes/player/player.tscn")
	while players_root.get_child_count() < 4:
		var p := proto.instantiate()
		p.name = str(100 + players_root.get_child_count())
		p.set_multiplayer_authority(1)
		players_root.add_child(p)
	for n in players_root.get_children().slice(4):
		players_root.remove_child(n)
		n.queue_free()
	_players = players_root.get_children()
	var spots := [Vector3(-9.0, 0.1, 1.3), Vector3(-5.5, 0.1, 1.5), Vector3(-8.6, 0.1, 4.6), Vector3(-3.4, 0.1, 4.4)]
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
	# Raiders held mid-stride beyond the wall, so none reach the crew before the shot
	for i in 3:
		var e: Node3D = load("res://scenes/enemy/enemy.tscn").instantiate()
		e.type = 1 if i == 0 else 0
		e.position = Vector3(-3.0 + i * 1.7, 0.1, -3.2 - i * 0.9)
		_main.get_node("Enemies").add_child(e, true)
		e.set_physics_process(false)
		e.anim = "walk_down"
		e._bar.visible = false
