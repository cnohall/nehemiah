class_name NetSmooth
extends Node
## Remote copies of moving things (players, enemies, messengers) are drawn a little in the
## past, blended between the owner's snapshots. Packets arrive in uneven bunches, and
## setting `position` straight from them made remote figures step, stall and jump.
##
## The owner replicates `net_pos` (position + its own clock, see `stamp`) instead of
## `position`, which stays spawn-only. On every other peer the setter hands each snapshot
## to `receive`, which keeps a short buffer on a NetSmooth child that moves its parent.

const DELAY      := 0.1    # draw this far behind the sender's clock (two 20 Hz snapshots)
const MAX_EXTRAP := 0.1    # past the newest snapshot, keep going this long, then hold
const TELEPORT   := 4.0    # a jump this big between snapshots is a teleport: snap, don't slide
const CREEP      := 0.02   # the clock offset drifts up this fast (s/s), so a slower route is found again
const RESYNC     := 2.0    # a sample this much later than the offset: a new clock (another host), start over
const KEEP       := 24

# Sender peer id -> [local time minus sender time (the quickest packet seen), local time last updated].
# Shared by every node one peer owns: the host's enemies all run on the host's clock.
static var _offsets := {}

var _snaps: Array[Vector4] = []
var _prev := Vector4.ZERO   # the last snapshot dropped from the front, for extrapolating
var _has_prev := false

static func now() -> float:
	return Time.get_ticks_usec() / 1000000.0

## Owner: what goes on the wire (the `net_pos` getter)
static func stamp(n: Node3D) -> Vector4:
	var p := n.position
	return Vector4(p.x, p.y, p.z, now())

## Receiver: the `net_pos` setter. The smoother is made on first use.
static func receive(n: Node3D, v: Vector4) -> void:
	if n.is_multiplayer_authority():
		return
	var s := n.get_node_or_null(^"NetSmooth") as NetSmooth
	if s == null:
		s = NetSmooth.new()
		s.name = "NetSmooth"
		s.process_priority = -100   # move the parent before anything poses off it this frame
		n.add_child(s)
	s._push(n.get_multiplayer_authority(), v)

func _push(peer: int, v: Vector4) -> void:
	var t := now()
	var sample := t - v.w
	var o: Array = _offsets.get(peer, [])
	if o.is_empty():
		o = [sample, t]
	else:
		var crept: float = o[0] + CREEP * (t - float(o[1]))
		o = [sample if sample > crept + RESYNC else minf(crept, sample), t]
	_offsets[peer] = o
	if not _snaps.is_empty():
		var last := _snaps[-1]
		if v.w <= last.w:
			return   # late or duplicate
		if _xyz(v).distance_to(_xyz(last)) > TELEPORT:
			_snaps.clear()
			_has_prev = false
	_snaps.append(v)
	if _snaps.size() > KEEP:
		_drop_front()

func _drop_front() -> void:
	_prev = _snaps.pop_front()
	_has_prev = true

func _process(_delta: float) -> void:
	var n := get_parent() as Node3D
	if _snaps.is_empty() or n.is_multiplayer_authority():
		return
	var o: Array = _offsets.get(n.get_multiplayer_authority(), [])
	if o.is_empty():
		return
	var rt := now() - float(o[0]) - DELAY   # render time, on the sender's clock
	while _snaps.size() >= 2 and _snaps[1].w <= rt:
		_drop_front()
	var a := _snaps[0]
	if rt <= a.w:
		# Not there yet (just spawned, or the clock was reset): hold at the oldest
		n.position = _xyz(a)
	elif _snaps.size() >= 2:
		var b := _snaps[1]
		n.position = _xyz(a).lerp(_xyz(b), (rt - a.w) / (b.w - a.w))
	elif _has_prev and a.w > _prev.w:
		# Ran past the newest (a late packet): carry on the way it was going, briefly
		var vel := (_xyz(a) - _xyz(_prev)) / (a.w - _prev.w)
		n.position = _xyz(a) + vel * minf(rt - a.w, MAX_EXTRAP)
	else:
		n.position = _xyz(a)

static func _xyz(v: Vector4) -> Vector3:
	return Vector3(v.x, v.y, v.z)
