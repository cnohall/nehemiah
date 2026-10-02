class_name Fox
extends Node3D

# Tobiah's fox (Neh. 4:3: "if a fox climbed up it, he would break down their stone wall").
# A small fox that trots along the wall's front once when asked — the seed at the Broad
# Wall, and again over a stretch the night raid pulled down (DayDirector). Cosmetic only:
# every peer builds and runs its own, nothing is synced. Joins "setback_fx".

const RUN_TIME := 5.5
const REACH    := 9.0      # metres either side of where it is asked to cross
const WALL_Z   := -1.4     # just outside the wall
const FUR      := Color(0.78, 0.40, 0.15)
const PALE     := Color(0.94, 0.88, 0.76)
const DARK     := Color(0.24, 0.16, 0.12)

var _fox: Node3D
var _t := -1.0
var _from := Vector3.ZERO
var _to := Vector3.ZERO

func _ready() -> void:
	add_to_group("setback_fx")

## Every peer: the fox crosses the wall's front around world x
func fox_over(x: float) -> void:
	if _fox != null:
		_fox.queue_free()
	_fox = _build()
	_fox.scale = Vector3.ONE * 1.7   # small things read at this camera height only when a little oversize
	add_child(_fox)
	var dir := 1.0 if x <= 0.0 else -1.0   # runs toward the middle of the site
	_from = Vector3(x - REACH * dir, 0.12, WALL_Z)
	_to = Vector3(x + REACH * dir, 0.12, WALL_Z)
	_fox.position = _from
	_fox.rotation.y = 0.0 if dir > 0.0 else PI
	_t = 0.0

func _process(delta: float) -> void:
	if _t < 0.0 or _fox == null:
		return
	_t += delta
	var k := clampf(_t / RUN_TIME, 0.0, 1.0)
	_fox.position = _from.lerp(_to, k) + Vector3(0, absf(sin(_t * 14.0)) * 0.06, 0)
	if k >= 1.0:
		_fox.queue_free()
		_fox = null
		_t = -1.0

static func _build() -> Node3D:
	var root := Node3D.new()
	var parts := [
		[Vector3(0.62, 0.26, 0.26), Vector3(0, 0.30, 0), FUR],            # body
		[Vector3(0.26, 0.24, 0.24), Vector3(0.40, 0.38, 0), FUR],         # head
		[Vector3(0.16, 0.10, 0.14), Vector3(0.56, 0.34, 0), PALE],        # snout
		[Vector3(0.06, 0.12, 0.06), Vector3(0.38, 0.54, 0.08), DARK],     # ears
		[Vector3(0.06, 0.12, 0.06), Vector3(0.38, 0.54, -0.08), DARK],
		[Vector3(0.50, 0.12, 0.12), Vector3(-0.50, 0.34, 0), FUR],        # tail
		[Vector3(0.14, 0.13, 0.13), Vector3(-0.78, 0.34, 0), PALE],       # its white tip
	]
	for sx: float in [-0.2, 0.2]:
		for sz: float in [-0.08, 0.08]:
			parts.append([Vector3(0.06, 0.2, 0.06), Vector3(sx, 0.1, sz), DARK])   # legs
	for p: Array in parts:
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = p[0]
		m.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = p[2]
		mat.roughness = 0.9
		m.material_override = mat
		m.position = p[1]
		root.add_child(m)
	return root
