extends SceneTree

# Triangles per mesh of one sculpted figure, biggest first.
func _initialize() -> void:
	var rig := CharacterRig.new()
	root.add_child(rig)
	rig.setup(CharacterRig.enemy_look("raider"))
	var seen := {}
	var total := 0
	for p in rig._parts:
		var m: Mesh = p.mesh
		var tris := 0
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			tris += (arr[Mesh.ARRAY_INDEX].size() if arr[Mesh.ARRAY_INDEX] != null else arr[Mesh.ARRAY_VERTEX].size()) / 3
		total += tris
		var k := "%s" % [m.get_class()]
		seen[tris] = seen.get(tris, 0) + 1
		if tris > 1000:
			print("%6d  %s" % [tris, p.name])
	print("total=%d parts=%d" % [total, rig._parts.size()], " ", seen)
	quit()
