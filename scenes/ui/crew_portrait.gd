class_name CrewPortrait
extends Control

# A worker's head and shoulders, rendered live from their own CharacterRig in a tiny
# private world: framed in a disc of the player's colour. The figure idles, so the
# portrait breathes; `downed` greys it out.

const PX := 72

var _vp: SubViewport
var _rig: CharacterRig
var _color := Color.WHITE
var _rim: Control
var downed := false:
	set(value):
		downed = value
		modulate = Color(0.62, 0.58, 0.55) if value else Color.WHITE

func _init() -> void:
	custom_minimum_size = Vector2(PX, PX)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The disc drawn below is also the mask: the figure never spills past its frame
	clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var box := SubViewportContainer.new()
	box.stretch = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	_vp = SubViewport.new()
	_vp.size = Vector2i(PX * 2, PX * 2)   # supersampled, shown at half size
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	box.add_child(_vp)
	var world := Node3D.new()
	_vp.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 0.6, 0)
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 1.5
	world.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.95, 0.85, 0.72)
	env.environment.ambient_light_energy = 0.55
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.add_child(env)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.45
	# Three-quarter view of the face (idle_down faces +x +z)
	cam.transform = Transform3D.IDENTITY.looking_at(Vector3(0, 1.55, 0) - Vector3(2.3, 2.1, 1.1)).translated(Vector3(2.3, 2.1, 1.1))
	world.add_child(cam)
	# Rim over the figure, inside the mask
	_rim = Control.new()
	_rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rim.draw.connect(func():
		var c := _rim.size * 0.5
		var r := minf(_rim.size.x, _rim.size.y) * 0.5
		_rim.draw_arc(c, r - 3.0, 0, TAU, 56, UiStyle.PARCHMENT, 4.0, true)
		_rim.draw_arc(c, r - 1.0, 0, TAU, 56, _color.darkened(0.2), 2.0, true))
	add_child(_rim)
	var holder := Node3D.new()
	world.add_child(holder)
	_rig = CharacterRig.new()
	holder.add_child(_rig)

func set_worker(slot: int, color: Color) -> void:
	_color = color
	if _rig.get_child_count() == 0:
		_rig.setup(CharacterRig.worker_look(slot, color))
		_rig.set_ring_color(Color(0, 0, 0, 0))
	else:
		_rig.set_look(CharacterRig.worker_look(slot, color))
	_rig.play("idle_down")
	queue_redraw()
	_rim.queue_redraw()

func _draw() -> void:
	# Disc in the player's colour — backdrop and clip mask for the figure
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	draw_circle(c, r, _color.lerp(UiStyle.PARCHMENT, 0.45))
	draw_circle(c + Vector2(0, r * 0.35), r * 0.7, _color.lerp(UiStyle.PARCHMENT, 0.3))
