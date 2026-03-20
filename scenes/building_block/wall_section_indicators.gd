class_name WallSectionIndicators
extends Node3D
## Visual material indicators shown above a WallSection.
## Owns all ghost + fill meshes so wall_section.gd stays focused on logic.
## Call build() once after creation, init_worldspace() after the parent is placed,
## and refresh() whenever material counts or completion state change.

const PIP_STONE  := Color(0.72, 0.68, 0.60)
const PIP_WOOD   := Color(0.58, 0.36, 0.16)
const PIP_MORTAR := Color(0.50, 0.50, 0.58)

var _fill_stone:  MeshInstance3D = null
var _fill_wood:   MeshInstance3D = null
var _fill_mortar: MeshInstance3D = null

var _ghost_stone_mat:  StandardMaterial3D = null
var _ghost_wood_mat:   StandardMaterial3D = null
var _ghost_mortar_mat: StandardMaterial3D = null

# ── Setup ─────────────────────────────────────────────────────────────────────

func build() -> void:
	_fill_stone  = _create_indicator(Vector3(-0.8, 0, 0), "stone")
	_fill_wood   = _create_indicator(Vector3( 0.0, 0, 0), "wood")
	_fill_mortar = _create_indicator(Vector3( 0.8, 0, 0), "mortar")

func init_worldspace(section_global_pos: Vector3, max_height: float) -> void:
	set_as_top_level(true)
	global_position = section_global_pos + Vector3(0, max_height + 1.0, 0)

# ── Update ────────────────────────────────────────────────────────────────────

func refresh(
	stone: int, wood: int, mortar: int,
	blocking: String, is_completed: bool
) -> void:
	visible = not is_completed
	_set_ghost_highlight(_ghost_wood_mat,   blocking == "wood")
	_set_ghost_highlight(_ghost_stone_mat,  blocking == "stone")
	_set_ghost_highlight(_ghost_mortar_mat, blocking == "mortar")
	_set_fill(_fill_stone,  stone,  WallSection.STONE_NEEDED,  PIP_STONE)
	_set_fill(_fill_wood,   wood,   WallSection.WOOD_NEEDED,   PIP_WOOD)
	_set_fill(_fill_mortar, mortar, WallSection.MORTAR_NEEDED, PIP_MORTAR)

# ── Private ───────────────────────────────────────────────────────────────────

func _create_indicator(offset: Vector3, type: String) -> MeshInstance3D:
	var mesh: Mesh
	match type:
		"stone":
			var s := SphereMesh.new()
			s.radius = 0.22; s.height = 0.44
			mesh = s
		"wood":
			var b := BoxMesh.new()
			b.size = Vector3(0.55, 0.15, 0.15)
			mesh = b
		"mortar":
			var c := CylinderMesh.new()
			c.top_radius = 0.18; c.bottom_radius = 0.14; c.height = 0.22
			mesh = c

	# Ghost — always visible, very dim
	var ghost := MeshInstance3D.new()
	ghost.mesh = mesh
	var ghost_mat := StandardMaterial3D.new()
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.12)
	ghost.material_override = ghost_mat
	ghost.position = offset
	add_child(ghost)
	match type:
		"stone":  _ghost_stone_mat  = ghost_mat
		"wood":   _ghost_wood_mat   = ghost_mat
		"mortar": _ghost_mortar_mat = ghost_mat

	# Fill — starts invisible, grows to full scale as materials arrive
	var fill := MeshInstance3D.new()
	fill.mesh = mesh
	var fill_mat := StandardMaterial3D.new()
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	match type:
		"stone":  fill_mat.albedo_color = PIP_STONE
		"wood":   fill_mat.albedo_color = PIP_WOOD
		"mortar": fill_mat.albedo_color = PIP_MORTAR
	fill.material_override = fill_mat
	fill.position = offset
	fill.scale = Vector3.ZERO
	add_child(fill)
	return fill

func _set_ghost_highlight(mat: StandardMaterial3D, active: bool) -> void:
	if mat:
		mat.albedo_color = Color(1.0, 1.0, 1.0, 0.45 if active else 0.12)

func _set_fill(fill: MeshInstance3D, count: int, needed: int, color: Color) -> void:
	if not fill:
		return
	fill.scale = Vector3.ONE * clampf(float(count) / float(needed), 0.0, 1.0)
	var mat := fill.material_override as StandardMaterial3D
	if not mat:
		return
	mat.albedo_color = color
	mat.emission_enabled = count >= needed
	if count >= needed:
		mat.emission = color * 0.5
