class_name SiteFocus
extends RefCounted

# Where the local player's next delivery goes: the nearest of today's unfinished build
# sites that needs what they carry, else the nearest unfinished one. Drives the one
# full (pulsing) site tag — the others dim — and the day plaque's "Next:" line.
# Worked out once per frame, however many callers ask.

static var _frame := -1
static var _site: Node3D
static var _matches_carry := false

static func site() -> Node3D:
	_refresh()
	return _site

## True when the focus site needs what the local player is carrying
static func matches_carry() -> bool:
	_refresh()
	return _matches_carry

static func _refresh() -> void:
	var f := Engine.get_process_frames()
	if f == _frame and (_site == null or is_instance_valid(_site)):
		return
	_frame = f
	_site = null
	_matches_carry = false
	var me := Player.local
	if me == null or not is_instance_valid(me):
		return
	var tree := Engine.get_main_loop() as SceneTree
	var carry: String = me.carried_kind
	var best_carry := INF
	var best_any := INF
	var any: Node3D = null
	var fit: Node3D = null
	for s: Node3D in tree.get_nodes_in_group("build_sites"):
		if not s.is_target or s.is_complete() or not s.is_visible_in_tree():
			continue
		var d: float = s.distance_to_point(me.global_position)
		if d < best_any:
			best_any = d
			any = s
		if not carry.is_empty() and s.needs(carry) and d < best_carry:
			best_carry = d
			fit = s
	_matches_carry = fit != null
	_site = fit if fit != null else any
