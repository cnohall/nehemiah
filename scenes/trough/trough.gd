extends StaticBody3D

# Mortar trough ("mixing" twist, GDD §6 — the Overcooked "cooking" step). Workers bring
# one load of lime and one of water; the trough mixes them by itself over MIX_TIME,
# then holds one load of mortar for anyone to take to the wall.
# Plays two roles for players: a build site (accepts lime / water) and, once mixed, a
# supply pile of kind "mortar". Server owns the state; clients mirror it via Sync.

const MIX_TIME   := 4.0
const LABEL_RANGE := 6.0
const STONE      := Color(0.66, 0.60, 0.52)
const WATER      := Color(0.36, 0.48, 0.52)
const LIME       := Color(0.92, 0.91, 0.86)
const MORTAR     := Color(0.70, 0.67, 0.60)
const BAR_COLOR  := Color(0.86, 0.66, 0.30)

## Kind this counts as while it holds finished mortar (read by Player pickups)
var kind := "mortar"
var has_lime := false:
	set(value):
		has_lime = value
		_refresh()
var has_water := false:
	set(value):
		has_water = value
		_refresh()
var mix_left := 0.0      # > 0 while mixing
var mortar_ready := false:
	set(value):
		if value and not mortar_ready and is_node_ready():
			Sfx.play("mix_done", global_position)
		mortar_ready = value
		_refresh()

var _lime_layer: MeshInstance3D
var _water_layer: MeshInstance3D
var _paste: MeshInstance3D
var _paddle: Node3D
var _bar: HealthBar
var _label: WorldTag

func _ready() -> void:
	_build_visuals()
	_build_sync()
	GameState.section_changed.connect(_refresh.unbind(1))
	_refresh()

func _process(delta: float) -> void:
	var mixing := has_lime and has_water and not mortar_ready
	if mixing:
		_paddle.rotation.y += delta * 3.0
		if multiplayer.is_server():
			mix_left = maxf(0.0, mix_left - delta)
			if mix_left == 0.0:
				has_lime = false
				has_water = false
				mortar_ready = true
		_bar.show_value(1.0 - mix_left / MIX_TIME, BAR_COLOR)
	_label.visible = _active() and not mixing and _local_player_near()

# ── Build-site side: takes lime and water ──────────────────

func needs(material: String) -> bool:
	if not _active() or mortar_ready or (has_lime and has_water):
		return false
	return (material == "lime" and not has_lime) or (material == "water" and not has_water)

func next_need() -> String:
	if needs("lime"):
		return "lime"
	return "water" if needs("water") else ""

func deposit(material: String, _amount: int) -> bool:
	if not multiplayer.is_server() or not needs(material):
		return false
	if material == "lime":
		has_lime = true
	else:
		has_water = true
	if has_lime and has_water:
		mix_left = MIX_TIME
	return true

func can_build() -> bool:
	return false

func try_build() -> bool:
	return false

func is_complete() -> bool:
	return true

## Mixing runs by itself — there's no hands-on work here (see BuildWork)
func work() -> BuildWork:
	return null

func work_material() -> String:
	return ""

# ── Supply side: hands out the mixed load ──────────────────

func request_pickup() -> bool:
	if not multiplayer.is_server() or not mortar_ready:
		return false
	mortar_ready = false
	return true

# ── Shared ─────────────────────────────────────────────────

func distance_to_point(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length() - 0.6

func approach_point(from: Vector3, _standoff: float) -> Vector3:
	return Vector3(global_position.x, from.y, global_position.z)

func _active() -> bool:
	return GameState.has_twist("mixing")

# Group membership follows state, so Player's normal pickup / deposit code just works
func _refresh() -> void:
	if not is_node_ready():
		return
	var active := _active()
	visible = active
	$CollisionShape3D.set_deferred("disabled", not active)
	_set_group("build_sites", active and not mortar_ready)
	_set_group("supply_piles", active and mortar_ready)
	_lime_layer.visible = has_lime and not has_water
	_water_layer.visible = has_water and not has_lime
	_paste.visible = (has_lime and has_water) or mortar_ready
	_paddle.visible = has_lime and has_water and not mortar_ready
	if not (has_lime and has_water and not mortar_ready):
		_bar.visible = false
	_update_label()

func _set_group(group: String, on: bool) -> void:
	if on and not is_in_group(group):
		add_to_group(group)
	elif not on and is_in_group(group):
		remove_from_group(group)

func _update_label() -> void:
	if mortar_ready:
		_label.text = "Mortar ready"
	else:
		_label.text = "Trough  ·  Lime %d/1  Water %d/1" % [int(has_lime), int(has_water)]

func _local_player_near() -> bool:
	return Player.local != null and distance_to_point(Player.local.global_position) < LABEL_RANGE

# ── Visuals ────────────────────────────────────────────────

# Hewn stone trough on two blocks, with a wooden paddle for stirring
func _build_visuals() -> void:
	for x: float in [-0.6, 0.6]:
		_box(Vector3(0.3, 0.3, 0.8), Vector3(x, 0.25, 0), STONE.darkened(0.15))
	_box(Vector3(1.7, 0.1, 0.9), Vector3(0, 0.45, 0), STONE)              # floor
	for z: float in [-0.4, 0.4]:
		_box(Vector3(1.7, 0.3, 0.1), Vector3(0, 0.6, z), STONE)            # long sides
	for x: float in [-0.8, 0.8]:
		_box(Vector3(0.1, 0.3, 0.9), Vector3(x, 0.6, 0), STONE)            # ends
	_lime_layer = _box(Vector3(1.45, 0.08, 0.66), Vector3(0, 0.54, 0), LIME)
	_water_layer = _box(Vector3(1.45, 0.08, 0.66), Vector3(0, 0.56, 0), WATER)
	_paste = _box(Vector3(1.45, 0.14, 0.66), Vector3(0, 0.57, 0), MORTAR)
	_paddle = Node3D.new()
	_paddle.position = Vector3(0, 0.6, 0)
	add_child(_paddle)
	var handle := _box(Vector3(0.06, 0.9, 0.06), Vector3(0.25, 0.3, 0), Color(0.45, 0.33, 0.20))
	handle.reparent(_paddle, false)
	handle.rotation.z = 0.35
	_bar = HealthBar.new(0.9, 0.09)
	_bar.position = Vector3(0, 1.5, 0)
	add_child(_bar)
	_label = WorldTag.make(WorldTag.Kind.SITE)
	_label.position = Vector3(0, 1.8, 0)
	_label.visible = false
	add_child(_label)

func _box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mi.material_override = mat
	add_child(mi)
	return mi

# ── Networking ─────────────────────────────────────────────

func _build_sync() -> void:
	NetworkManager.add_sync(self, [^".:has_lime", ^".:has_water", ^".:mix_left", ^".:mortar_ready"])
