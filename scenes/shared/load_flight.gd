class_name LoadFlight

# Cosmetic only: a load hopping between hands and the world (pile → arms, arms → wall,
# arms → a mate's arms), so a pickup or a put-down reads as a motion instead of a swap.
# Every peer flies its own copy; nothing here is synced or touches game state.

const TIME := 0.24          # s in the air
const ARC := 0.55           # m the hop rises above the straight line
# Set on a wall: the wall usually stands beyond the worker from the camera, so the load
# goes up over the head, where it can be seen, and takes a beat longer
const SET_TIME := 0.36
const SET_ARC := 1.9
const SINK_TIME := 0.14     # s a load takes to settle into a wall once it lands

enum End {
	HANDS,   # caught: just vanishes (the carried prop pops in its place)
	SINK,    # set on a wall / tipped out: squashes, shrinks into it, a puff of dust
}

## Fly `kind` from `from` (its world transform: place, turn, size) to the point `to`
## returns, polled every frame so a moving target (a worker's arms) is followed.
## `end_scale`: its size on arrival.
static func fly(parent: Node, kind: String, from: Transform3D, to: Callable, end_scale: float, end := End.HANDS) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var holder := Node3D.new()
	holder.top_level = true
	var prop := DroppedItem.build_prop(kind)
	for mi in prop.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(prop)
	parent.add_child(holder)
	var start_rot := from.basis.get_rotation_quaternion()
	var start_scale := from.basis.get_scale().x
	var spin := Quaternion(Vector3.UP, start_rot.get_euler().y + randf_range(-0.9, 0.9))
	var origin := from.origin
	var last := [origin]   # where the target last was, should its worker leave mid-flight
	holder.global_transform = from
	var tw := holder.create_tween()
	var arc := SET_ARC if end == End.SINK else ARC
	tw.tween_method(func(t: float) -> void:
		if to.is_valid():
			last[0] = to.call()
		var dest: Vector3 = last[0]
		var k := ease(t, 0.8)   # leaves quick, eases into the catch
		var p := origin.lerp(dest, k) + Vector3.UP * sin(t * PI) * arc
		var s := lerpf(start_scale, end_scale, k)
		holder.global_transform = Transform3D(Basis(start_rot.slerp(spin, k)).scaled(Vector3.ONE * s), p),
		0.0, 1.0, SET_TIME if end == End.SINK else TIME)
	if end == End.SINK:
		tw.tween_callback(func() -> void:
			DustFx.puff(parent, holder.global_position, 6, 0.4))
		tw.tween_property(prop, "scale", Vector3(1.3, 0.55, 1.3), SINK_TIME * 0.4) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(prop, "scale", Vector3.ONE * 0.05, SINK_TIME * 0.6) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(holder.queue_free)
