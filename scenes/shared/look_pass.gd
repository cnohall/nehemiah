class_name LookPass
extends MeshInstance3D

# Full-screen drawn look over a 3D scene (map_look.gdshader): a quad that covers the
# view whatever the camera, reading the rendered frame and its depth. Used by the circuit
# map and, to try out, the game itself (`-- --look=litho|cel`, F10 cycles in debug builds).
# The pass works on display colours, so while it is on the environment's tonemap goes
# linear (restored when it is off).
# `whole_screen`: the look goes over the finished 2D frame instead — a rect on a canvas
# layer (look_screen.gdshader) — so see-through sprites and the world tags take it too,
# and this quad only adds the depth ink lines to the world under it, leaving the tonemap
# alone. The rect sits just under the HUD (UNDER_HUD) so menus and panels stay clean,
# or over everything with `over_hud`.

enum { PLAIN, LITHO, MOSAIC, PLAN, CEL, LINES }
const UNDER_HUD := 2     # over the world tags (WorldTag.LAYER 1), under GameHUD (3)
const STYLES := [PLAIN, LITHO, CEL]     # Settings.ART_STYLES, in order
const NAMES :={ "plain": PLAIN, "litho": LITHO, "mosaic": MOSAIC, "plan": PLAN, "cel": CEL }

## The environment whose tonemap is switched while a look is on (may be null)
var env: Environment
## F10 cycles the looks, F9 toggles over_hud (debug builds; for trying them in play).
## Not F8: that is the editor's stop key.
var cycle_key := false
## The scene is lit for its filmic tonemap: carry it into the pass (the game world)
var keep_film := false:
	set(v):
		keep_film = v
		var m := material_override as ShaderMaterial
		m.set_shader_parameter("film_white", env.tonemap_white if v and env else 0.0)
		m.set_shader_parameter("film_exposure", _exposure)
## 0..1 crayon grain and paper texture (litho)
var grain := 1.0:
	set(v):
		grain = v
		(material_override as ShaderMaterial).set_shader_parameter("grain_amount", v)
		(_rect.material as ShaderMaterial).set_shader_parameter("grain_amount", v)
var whole_screen := false:
	set(v):
		whole_screen = v
		look = look
## The whole-screen look covers the HUD and menus as well
var over_hud := false:
	set(v):
		over_hud = v
		_layer.layer = 128 if v else base_layer
## The canvas layer the whole-screen look sits on when not over the HUD: UNDER_HUD in
## play; behind the root canvas (-1) under the title menu, a plain Control on layer 0
var base_layer := UNDER_HUD:
	set(v):
		base_layer = v
		over_hud = over_hud

var look := PLAIN:
	set(v):
		look = v
		var on := v != PLAIN
		var screen := on and whole_screen
		visible = on
		(material_override as ShaderMaterial).set_shader_parameter("look", LINES if screen else v)
		_layer.visible = screen
		(_rect.material as ShaderMaterial).set_shader_parameter("look", v)
		if env:
			var lin := on and not screen
			env.tonemap_mode = Environment.TONE_MAPPER_LINEAR if lin else _tonemap
			env.tonemap_exposure = 1.0 if lin else _exposure

var _tonemap := Environment.TONE_MAPPER_FILMIC
var _exposure := 1.0
var _layer := CanvasLayer.new()
var _rect := ColorRect.new()

func _init(environment: Environment = null) -> void:
	env = environment
	if env:
		_tonemap = env.tonemap_mode
		_exposure = env.tonemap_exposure
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	mesh = q
	custom_aabb = AABB(Vector3.ONE * -1e5, Vector3.ONE * 2e5)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scenes/story/map_look.gdshader")
	mat.render_priority = 100
	material_override = mat
	visible = false
	_layer.layer = UNDER_HUD
	_layer.visible = false
	add_child(_layer)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = load("res://scenes/shared/look_screen.gdshader")
	_rect.material = sm
	_layer.add_child(_rect)

## The look named on the command line (`--look=cel`), or PLAIN
static func from_args() -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--look="):
			return NAMES.get(a.trim_prefix("--look="), PLAIN)
	return PLAIN

func _unhandled_key_input(event: InputEvent) -> void:
	if not (cycle_key and OS.is_debug_build() and event.is_pressed() and not event.is_echo()):
		return
	match (event as InputEventKey).keycode:
		KEY_F10:
			# Plan is the map's top-down camera; in play it is litho again, so skip it
			look = [LITHO, CEL, PLAIN][[PLAIN, LITHO, CEL].find(look) if look != MOSAIC and look != PLAN else 0]
			print("look: ", NAMES.find_key(look))
		KEY_F9:
			over_hud = not over_hud
			print("look over the HUD too: ", over_hud)
