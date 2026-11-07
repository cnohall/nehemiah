extends SceneTree

# Cost of building one figure (CharacterRig.setup) — a spawn's hitch. Average over N builds,
# first build reported apart (it fills the shared mesh cache).
#   Godot --path . --script res://tools/rig_build_time.gd [-- --prewarm]
func _initialize() -> void:
	if "--prewarm" in OS.get_cmdline_user_args():
		var t := Time.get_ticks_usec()
		CharacterRig.prewarm()
		print("prewarm %.2f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	for kind in ["scout", "brute", "raider"]:
		var times: Array[float] = []
		for i in 11:
			var t := Time.get_ticks_usec()
			var rig := CharacterRig.new()
			root.add_child(rig)
			rig.setup(CharacterRig.enemy_look(kind))
			times.append((Time.get_ticks_usec() - t) / 1000.0)
		var rest := times.slice(1)
		print("%-7s first %.2f ms, then avg %.2f ms, parts %d" % [kind, times[0],
			rest.reduce(func(a, b): return a + b) / rest.size(), root.get_child(root.get_child_count() - 1)._parts.size()])
	quit()
