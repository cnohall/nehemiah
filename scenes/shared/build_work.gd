class_name BuildWork
extends Node3D

# The hands-on step of raising a wall (GDD §6 — Overcooked's "chopping"). Once a build
# site holds every material for its next stage, workers stand at it and work: progress
# fills while at least one is at it, faster with more hands, and is kept if they walk
# away. Full → the site's try_build() raises the stage.
#
# Child of a build site ("Work"); the site replicates `progress` through its own Sync.
# Server owns the builder list and advances progress; every peer shows the bar.

signal finished   # server: the stage went up — builders are let go
signal progress_changed(value: float)   # every peer — the site shows the stones going up

const EXTRA_HAND  := 0.7    # each extra worker adds 70% of one worker's pace
const MAX_HANDS   := 3
const REACH_SLACK := 0.8    # a builder may drift this far past interact reach before being let go
const BAR_COLOR   := Color(0.93, 0.78, 0.42)

## Seconds of work for one worker, set by the site per stage
var work_time := 2.5
## 0..1 toward the next stage (replicated by the site)
var progress := 0.0:
	set(value):
		if value == progress:
			return
		progress = value
		_refresh_bar()
		progress_changed.emit(value)

var _builders: Array[Node3D] = []   # server
var _bar: HealthBar

func _ready() -> void:
	_bar = HealthBar.new(1.1, 0.12)
	add_child(_bar)

## Server: a worker starts / stops working here. Returns false when full or not ready.
func add_builder(p: Node3D) -> bool:
	if not multiplayer.is_server() or not get_parent().can_build():
		return false
	if p in _builders:
		return true
	var hands := MAX_HANDS + (1 if get_parent().has_method("is_thick") and get_parent().is_thick() else 0)
	if _builders.size() >= hands:
		return false
	_builders.append(p)
	return true

func remove_builder(p: Node3D) -> void:
	_builders.erase(p)

func builder_count() -> int:
	return _builders.size()

## Server: new section / stage knocked down — start over, everyone let go
func reset() -> void:
	progress = 0.0
	_release_all()

func _process(delta: float) -> void:
	if not multiplayer.is_server() or _builders.is_empty():
		return
	var site := get_parent()
	_builders = _builders.filter(func(p: Node3D) -> bool:
		return is_instance_valid(p) and not p.downed and p.building_site == site \
			and site.distance_to_point(p.global_position) < p.INTERACT_REACH + REACH_SLACK)
	if _builders.is_empty():
		return
	if not site.can_build():
		_release_all()
		return
	var hands := 1.0 + EXTRA_HAND * (_builders.size() - 1)
	progress = minf(1.0, progress + delta * hands / work_time)
	if progress >= 1.0:
		progress = 0.0
		site.try_build()
		_release_all()
		finished.emit()

func _release_all() -> void:
	for p in _builders:
		if is_instance_valid(p):
			p.stop_building_from_server()
	_builders.clear()

func _refresh_bar() -> void:
	if _bar == null:
		return
	_bar.visible = progress > 0.0
	if progress > 0.0:
		_bar.show_value(progress, BAR_COLOR)

## Show the first part of a preview, piece by piece in the order it was built:
## multimesh instances one block at a time, other children one at a time. Pieces
## before `skip` (already standing in the current stage) are shown from the start.
static func reveal(root: Node, fraction: float, skip := 0) -> void:
	var total := 0
	for c in root.get_children():
		total += c.multimesh.instance_count if c is MultiMeshInstance3D else 1
	var shown := roundi(lerpf(skip, total, clampf(fraction, 0.0, 1.0)))
	for c in root.get_children():
		if c is MultiMeshInstance3D:
			var n: int = c.multimesh.instance_count
			c.multimesh.visible_instance_count = clampi(shown, 0, n)
			shown -= n
		else:
			c.visible = shown > 0
			shown -= 1
