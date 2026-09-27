extends SceneTree

# Touch sling check: hosts a LAN game in the phone preview, presses + drags the
# on-screen sling, and prints how far the throw direction lands from the drag
# direction on screen (should be ~0°) plus a screenshot of the aim guide.
#   Godot --path . --resolution 1848x822 --script res://tools/touch_aim_test.gd -- --touch --lan <out_dir>

var _frame := 0
var _out := ""
var _tc
var _sling := Vector2.ZERO

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	change_scene_to_file("res://scenes/ui/main_menu.tscn")

func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 60:
		root.get_node("NetworkManager").host()
	if _frame == 200:
		var TC = load("res://scenes/ui/touch_controls.gd")
		for n in current_scene.find_children("*", "", true, false):
			if n.get_script() == TC:
				_tc = n
		_sling = _tc._buttons.sling.pos
		_tc._touch_down(0, _sling + Vector2(8, 6))   # off-centre press
		_tc._touch_move(0, _sling + Vector2(8, 6) + Vector2(-40, -25))
	if _frame == 230:
		var P = load("res://scenes/player/player.gd")
		var me = P.local
		var cam := root.get_camera_3d()
		# Projected throw direction must match the drag direction on screen
		var worst := 0.0
		for deg in range(0, 360, 15):
			var v := Vector2.RIGHT.rotated(deg_to_rad(deg))
			var g: Vector3 = me._screen_dir_to_ground(v)
			var sp := cam.unproject_position(me.global_position + g * 5.0) - cam.unproject_position(me.global_position)
			worst = maxf(worst, absf(rad_to_deg(v.angle_to(sp))))
			var naive := cam.unproject_position(me.global_position + P.screen_to_ground(v).normalized() * 5.0) - cam.unproject_position(me.global_position)
			if deg % 45 == 0:
				print("deg %d  projected err %.2f  naive err %.2f" % [deg, rad_to_deg(v.angle_to(sp)), rad_to_deg(v.angle_to(naive))])
		print("worst projected error: ", worst)
		print("aim_vec ", _tc.aim_vec, " charging ", me._charging, " touch ", me._touch_charge, " preview ", me.aim_preview())
		root.get_texture().get_image().save_png(_out.path_join("aim.png"))
		_tc._touch_up(0)
	if _frame == 234:
		print("after release: charging ", load("res://scenes/player/player.gd").local._charging, " aiming ", _tc.aiming)
		quit()
	return false
