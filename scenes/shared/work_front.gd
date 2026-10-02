class_name WorkFront
extends RefCounted

# Where the work is, under the sun clock (GameState.sun): the whole stretch is the goal,
# but spreading loads over all of it leaves every unit half-built at nightfall. So the
# work goes in build order (DayDirector.UNIT_ORDER — the gate first, then outward) and
# only the first few unfinished units are "open": one per two workers, at least one.
# A finished unit knocked back down reopens in its place, so repairs come first.
# Bots only serve open sites and the local player's focus picks among them; people may
# still deliver anywhere. Worked out on every peer from replicated state (stages, crew).
# Without the sun clock every site is open (the day's slice is already small).

# Build order within a section: the named gate first, then outward to the towers
const UNIT_ORDER := ["SheepGate", "Section1", "Section3", "TowerLeft", "Section4", "TowerRight"]

static var _frame := -1
static var _open: Array = []   # wall parts of the open units

## True when `site` is part of the work front (or isn't a wall unit at all: trough, posts)
static func is_open(site: Node) -> bool:
	if not GameState.sun:
		return true
	_refresh(site.get_tree())
	if _open.has(site):
		return true
	return not _is_unit_part(site)

static func _is_unit_part(site: Node) -> bool:
	var unit := site if site.get_parent() != null and site.get_parent().name == "Wall" else site.get_parent()
	return unit != null and str(unit.name) in UNIT_ORDER

static func _refresh(tree: SceneTree) -> void:
	var f := Engine.get_process_frames()
	if f == _frame:
		return
	_frame = f
	_open.clear()
	var wall := tree.current_scene.get_node_or_null("Wall") if tree.current_scene != null else null
	if wall == null:
		return
	var width := maxi(1, ceili(GameState.crew_size / 2.0))
	for unit_name: String in UNIT_ORDER:
		var node := wall.get_node_or_null(unit_name)
		if node == null:
			continue
		var parts: Array = node.get_children().filter(func(c): return c.has_method("try_build"))
		if node.has_method("try_build"):
			parts.append(node)
		if parts.all(func(p): return p.is_complete()):
			# Standing, but battered: mending is on the front too, and takes no share of it
			_open.append_array(parts.filter(func(p): return p.has_method("repairing") and p.repairing()))
			continue
		_open.append_array(parts)
		width -= 1
		if width == 0:
			return
