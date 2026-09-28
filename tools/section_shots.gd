extends SceneTree

# One screenshot per section of the wall, for the website's circuit map:
#   Godot --path . --script res://tools/section_shots.gd -- --nostory --day=N <out_dir> [wait_s]
# Starts the day, poses a four-player crew at a part-built wall while the first
# enemies come in, and saves <out_dir>/section_<index>.png with the HUD hidden.
# wait_s (default 9) = seconds of play before the shot; the Water Gate needs ~25 for
# darkness to fall (run it with --day=38).

var _out := ""
var _wait := 9.0
var _main: Node3D
var _frame := 0
var _t := 0.0
var _posed := false
var _pending := 0

func _initialize() -> void:
	var rest: Array = []
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			rest.append(a)
	_out = rest[0]
	if rest.size() > 1:
		_wait = float(rest[1])
	root.size = Vector2i(1920, 1080)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main

func _process(delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_main.director.begin()
	if _frame < 3:
		return false
	_t += delta
	var gs = root.get_node("GameState")
	if not _posed and gs.phase == gs.Phase.WORK and _t > 2.0:
		_pose(gs)
		_posed = true
	if _posed and _pending == 0 and _t >= _wait:
		var yard: Vector2 = gs.get_current_section()["yard"]
		var cam: Camera3D = _main.get_node("Camera3D")
		_main.set_process(false)
		cam.size = 26.0
		cam.global_position = Vector3(yard.x * 0.3, 0.0, -0.5) + _main.CAM_OFFSET
		_main.hud.hide()
		_pending = 3
		return false
	if _pending > 0:
		_pending -= 1
		if _pending == 0:
			var path := "%s/section_%02d.png" % [_out, gs.current_section_index + 1]
			root.get_texture().get_image().save_png(path)
			print("section_shots: saved ", path)
			return true
	if _t > 90.0:
		push_error("section_shots: timed out")
		return true
	return false

# Wall part-built, with a crew of four at it: two building, one carrying, one on guard
func _pose(gs) -> void:
	var i := 0
	for part in _main.get_node("Wall").get_children():
		if "stage" in part:
			part.stage = [3, 2, 1, 2, 3][i % 5]
			i += 1
	var yard: Vector2 = gs.get_current_section()["yard"]
	var cx := yard.x * 0.4
	var players_root: Node3D = _main.get_node("Players")
	var crew: Array = [players_root.get_child(0)]
	var proto: PackedScene = load("res://scenes/player/player.tscn")
	for n in 3:
		var p := proto.instantiate()
		p.name = str(100 + n)
		p.set_multiplayer_authority(1)
		players_root.add_child(p)
		crew.append(p)
	var spots := [Vector3(cx - 1.5, 0.1, 1.3), Vector3(cx + 1.5, 0.1, 3.4), Vector3(cx - 3.0, 0.1, 4.4), Vector3(cx + 3.5, 0.1, 1.4)]
	var anims := ["build_up", "walk_up", "idle_down", "build_up"]
	for n in crew.size():
		var p: Node3D = crew[n]
		p.set_physics_process(false)
		p.global_position = spots[n]
		p.set_slot(n, _main.PLAYER_COLORS[n])
		p.anim = anims[n]
	crew[1].carried_kind = "stone"
	crew[1]._rebuild_carry_prop()
	gs.set_crew(4)
