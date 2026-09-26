extends SceneTree

# Renders the title-screen backdrop from the real game world:
#   Godot --path . --script res://tools/capture_menu_bg.gd
# (not headless — it needs the GPU). Re-run whenever the world art changes.

const OUT        := "res://assets/ui/menu_bg.jpg"
const FOCUS      := Vector3(-7.0, 0.0, 5.5)    # crew and gate land right of centre, title sits over open ground
const CAM_OFFSET := Vector3(20.0, 20.0, 20.0)
const CAM_SIZE   := 17.0
const SETTLE     := 3.0                         # seconds for dust puffs / shadows to settle

var _frame := 0
var _elapsed := 0.0
var _main: Node3D

func _initialize() -> void:
	root.size = Vector2i(1920, 1080)
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)

func _process(delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_stage_scene()
	if _frame > 3:
		_elapsed += delta
	if _elapsed >= SETTLE:
		var img := root.get_texture().get_image()
		img.save_jpg(ProjectSettings.globalize_path(OUT), 0.9)
		print("saved ", OUT)
		return true
	return false

func _stage_scene() -> void:
	_main.set_process(false)
	_main.get_node("DayDirector").set_process(false)
	_main.get_node("WaveManager").set_process(false)
	_main.hud.hide()
	_main.get_node("PostFX").hide()   # the menu applies its own veil
	for p in _main.get_node("Players").get_children():
		p.queue_free()
	_main.get_node("/root/GameState").day_changed.emit(GameState.TOTAL_DAYS)   # outer stretches finished
	for w in _main.get_tree().get_nodes_in_group("wall_sections"):
		w.is_target = false
		w.stage = w.Stage.MORTARED
		w.set_process(false)
	var tags := root.get_node_or_null("WorldTags")
	if tags:
		tags.hide()
	_pose_crew()
	var cam: Camera3D = _main.get_node("Camera3D")
	cam.size = CAM_SIZE
	cam.global_position = FOCUS + CAM_OFFSET

# The four trades at work by the gate, so the title shows who you'll play
func _pose_crew() -> void:
	var proto: PackedScene = load("res://scenes/player/player.tscn")
	var poses := [
		[Vector3(-0.6, 0.1, 1.45), "build_up", ""],
		[Vector3(2.8, 0.1, 5.2), "walk_down", "water"],
		[Vector3(-2.6, 0.1, 5.4), "walk_right", "wood"],
		[Vector3(2.4, 0.1, 2.0), "idle_down", ""],
	]
	for i in poses.size():
		var p := proto.instantiate()
		p.name = str(200 + i)
		p.set_multiplayer_authority(1)
		_main.get_node("Players").add_child(p)
		p.set_physics_process(false)
		p.global_position = poses[i][0]
		p.set_slot(i, _main.PLAYER_COLORS[i])
		p.carried_kind = poses[i][2]
		p._rebuild_carry_prop()
		p.anim = poses[i][1]
