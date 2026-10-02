extends Node3D

# POC for GDD §5.14: Jerusalem hidden in cloud, a night walk with a lantern lifts it, and
# touching a gate reveals its name (Nehemiah 2:12-16). Standalone: reuses CircuitDiorama for
# the city. The cloud is two planes whose shader looks the reveal mask up where the view ray
# meets the ground, so the hole sits over the lantern, not shifted by the camera tilt.
#   Godot --path . res://scenes/night_ride/night_ride.tscn        (WASD / arrows / stick)
#   ... -- --demo   walks the ring by itself (for shots, tools/night_ride_shots.ps1)

const MASK_N := 192
const MASK_WORLD := 96.0        # world metres the mask covers, centred on the origin
const SEE_R := 8.0              # lantern reveal radius
const GATE_R := 2.8             # touch distance
const START_GATE := 5           # Valley Gate: where Nehemiah rode out (2:13)
const SPEED := 9.0
const WALK_LIMIT := 0.6         # unit-space radius from the city centre

const CLOUD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform sampler2D mask : filter_linear, repeat_disable;
uniform float world_size = 96.0;
uniform float ground_y = 2.0;
uniform vec3 cloud : source_color = vec3(0.34, 0.36, 0.48);
uniform float scale = 0.07;
uniform float drift = 0.02;
uniform float lift = 0.0;
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec3 dir = normalize(wpos - CAMERA_POSITION_WORLD);
	vec3 gp = wpos + dir * ((ground_y - wpos.y) / dir.y);
	float seen = clamp(texture(mask, gp.xz / world_size + 0.5).r + lift, 0.0, 1.0);
	vec2 q = wpos.xz * scale + vec2(TIME * drift, TIME * drift * 0.6);
	float n = vnoise(q) * 0.6 + vnoise(q * 2.3) * 0.3 + vnoise(q * 5.1) * 0.1;
	ALBEDO = cloud * (0.8 + 0.4 * n);
	ALPHA = (1.0 - smoothstep(0.05, 0.95, seen)) * mix(0.78, 1.0, n);
}
"""

var dio: CircuitDiorama
var cam: Camera3D
var hero: Node3D
var lantern: OmniLight3D
var beacon: MeshInstance3D
var mask_img: Image
var mask_tex: ImageTexture
var mask_dirty := false
var found: Array[bool] = []
var gate_pos: Array[Vector3] = []
var hero_pos := Vector3.ZERO
var last_stamp := Vector3(1e9, 0, 0)
var demo := false
var demo_t := float(START_GATE) + 0.4
var time := 0.0
var finished := false
var lift := 0.0
var time_done := 0.0
var clouds: Array[ShaderMaterial] = []

var count_label: Label
var toast: Label
var hint: Label
var name_rows: Array[Label] = []

func _ready() -> void:
	demo = "--demo" in OS.get_cmdline_user_args()
	dio = CircuitDiorama.new()
	add_child(dio)
	dio.set_night(true)
	dio.set_torch(-1.0)
	for i in CircuitDiorama.GATES.size():
		dio.set_section(i, false)
		found.append(false)
		gate_pos.append(dio.unit_to_world(CircuitDiorama.GATES[i]))

	cam = Camera3D.new()
	cam.fov = 36.0
	cam.far = 400.0
	add_child(cam)
	cam.make_current()

	_build_hero()
	_build_cloud()
	_build_beacon()
	_build_hud()

	var start_u: Vector2 = CircuitDiorama.GATES[START_GATE].lerp(CircuitDiorama.CENTER, -0.4)
	hero_pos = dio.unit_to_world(start_u)
	_place_hero(0.0)
	_stamp(hero_pos, SEE_R * 1.3)
	_flush_mask()
	_snap_camera()

func _build_hero() -> void:
	hero = Node3D.new()
	add_child(hero)
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.5
	cap.height = 1.9
	body.mesh = cap
	body.position.y = 1.0
	body.material_override = _flat(Color(0.18, 0.26, 0.58))
	hero.add_child(body)
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.42
	sph.height = 0.84
	head.mesh = sph
	head.position.y = 2.15
	head.material_override = _flat(Color(0.72, 0.52, 0.38))
	hero.add_child(head)
	var wrap := MeshInstance3D.new()
	var wm := SphereMesh.new()
	wm.radius = 0.46
	wm.height = 0.5
	wrap.mesh = wm
	wrap.position.y = 2.38
	wrap.material_override = _flat(Color(0.93, 0.88, 0.74))
	hero.add_child(wrap)
	var flame := MeshInstance3D.new()
	var fs := SphereMesh.new()
	fs.radius = 0.2
	fs.height = 0.4
	flame.mesh = fs
	flame.position = Vector3(0.7, 1.5, 0.2)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1.0, 0.82, 0.45)
	flame.material_override = fm
	hero.add_child(flame)
	lantern = OmniLight3D.new()
	lantern.light_color = Color(1.0, 0.66, 0.3)
	lantern.omni_range = 12.0
	lantern.light_energy = 3.5
	lantern.position = Vector3(0.7, 1.7, 0.2)
	hero.add_child(lantern)

func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m

func _build_cloud() -> void:
	mask_img = Image.create(MASK_N, MASK_N, false, Image.FORMAT_L8)
	mask_img.fill(Color.BLACK)
	mask_tex = ImageTexture.create_from_image(mask_img)
	for layer in [[9.5, 0.07, 0.02, Color(0.36, 0.38, 0.5)], [6.0, 0.11, -0.03, Color(0.30, 0.32, 0.44)]]:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(150, 150)
		mi.mesh = pm
		var sm := ShaderMaterial.new()
		sm.shader = Shader.new()
		sm.shader.code = CLOUD_SHADER
		sm.set_shader_parameter("mask", mask_tex)
		sm.set_shader_parameter("world_size", MASK_WORLD)
		sm.set_shader_parameter("scale", layer[1])
		sm.set_shader_parameter("drift", layer[2])
		sm.set_shader_parameter("cloud", layer[3])
		mi.material_override = sm
		clouds.append(sm)
		mi.position = Vector3(0, layer[0], 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

func _build_beacon() -> void:
	beacon = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.18
	cm.bottom_radius = 0.5
	cm.height = 16.0
	beacon.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.72, 0.3, 0.2)
	m.no_depth_test = true
	m.render_priority = 5
	beacon.material_override = m
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beacon.visible = false
	add_child(beacon)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.96, 0.92, 0.82, 0.92)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = Vector2(20, 20)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	count_label = _label("Gates found 0 / 12", 22, Color(0.30, 0.20, 0.10))
	box.add_child(count_label)
	for i in GameState.SECTIONS.size():
		var row := _label("· · ·", 16, Color(0.55, 0.45, 0.35))
		name_rows.append(row)
		box.add_child(row)
	toast = _label("", 40, Color(1.0, 0.93, 0.78))
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.position = Vector2(-300, 110)
	toast.size = Vector2(600, 120)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.modulate.a = 0.0
	layer.add_child(toast)
	hint = _label("By night, with a few men. Walk the wall. Touch each gate.", 22, Color(1.0, 0.93, 0.78))
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-400, -90)
	hint.size = Vector2(800, 40)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(hint)

func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.03, 0.9))
	l.add_theme_constant_override("outline_size", 0 if size < 30 else 8)
	return l

func _process(delta: float) -> void:
	time += delta
	var dir := _input_dir()
	if demo:
		demo_t += delta * 0.4
		var target := dio.ring_world(demo_t)
		var d := Vector2(target.x - hero_pos.x, target.z - hero_pos.z)
		dir = d.limit_length(1.0) if d.length() > 0.3 else Vector2.ZERO
	if dir.length() > 0.05 and not finished:
		hero_pos += Vector3(dir.x, 0, dir.y) * SPEED * delta
		hero.rotation.y = lerp_angle(hero.rotation.y, atan2(dir.x, dir.y), minf(1.0, delta * 12.0))
	var u := _to_unit(hero_pos)
	var off := u - CircuitDiorama.CENTER
	if off.length() > WALK_LIMIT:
		u = CircuitDiorama.CENTER + off.normalized() * WALK_LIMIT
		hero_pos = dio.unit_to_world(u)
	_place_hero(delta)
	if hero_pos.distance_to(last_stamp) > 0.4:
		_stamp(hero_pos, SEE_R)
	if mask_dirty:
		_flush_mask()
	_check_gates()
	_update_beacon()
	lantern.light_energy = 3.5 * (0.88 + 0.12 * sin(time * 17.0) * sin(time * 7.3))
	if finished and time_done > 0.0 and time > time_done:
		lift = minf(1.0, lift + delta / 3.0)
		for c in clouds:
			c.set_shader_parameter("lift", lift)
	_follow_camera(delta)

func _input_dir() -> Vector2:
	var v := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if Input.is_key_pressed(KEY_A): v.x -= 1.0
	if Input.is_key_pressed(KEY_D): v.x += 1.0
	if Input.is_key_pressed(KEY_W): v.y -= 1.0
	if Input.is_key_pressed(KEY_S): v.y += 1.0
	return v.limit_length(1.0)

func _to_unit(p: Vector3) -> Vector2:
	return Vector2(p.x / CircuitDiorama.W + 0.5, p.z / CircuitDiorama.W + 0.5)

func _place_hero(delta: float) -> void:
	var y := dio.height(_to_unit(hero_pos))
	hero_pos.y = lerpf(hero_pos.y, y, 1.0 if delta <= 0.0 else minf(1.0, delta * 14.0))
	hero.position = hero_pos

func _stamp(p: Vector3, radius: float) -> void:
	last_stamp = p
	var cx := (p.x / MASK_WORLD + 0.5) * MASK_N
	var cz := (p.z / MASK_WORLD + 0.5) * MASK_N
	var r := radius / MASK_WORLD * MASK_N
	for y in range(maxi(0, int(cz - r) - 1), mini(MASK_N, int(cz + r) + 2)):
		for x in range(maxi(0, int(cx - r) - 1), mini(MASK_N, int(cx + r) + 2)):
			var d := Vector2(x + 0.5 - cx, y + 0.5 - cz).length()
			var v := 1.0 - smoothstep(r * 0.45, r, d)
			if v > mask_img.get_pixel(x, y).r:
				mask_img.set_pixel(x, y, Color(v, v, v))
	mask_dirty = true

func _flush_mask() -> void:
	mask_tex.update(mask_img)
	mask_dirty = false

func _check_gates() -> void:
	for i in gate_pos.size():
		if found[i]:
			continue
		var d := Vector2(gate_pos[i].x - hero_pos.x, gate_pos[i].z - hero_pos.z).length()
		if d < GATE_R:
			_found_gate(i)

func _found_gate(i: int) -> void:
	found[i] = true
	_stamp(gate_pos[i], SEE_R * 1.9)
	dio.set_glow(i, 1.0)
	var sec: Dictionary = GameState.SECTIONS[i]
	var label := Label3D.new()
	label.text = sec["name"]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.009
	label.font_size = 96
	label.outline_size = 24
	label.modulate = Color(1.0, 0.93, 0.74)
	label.outline_modulate = Color(0.1, 0.06, 0.03)
	label.render_priority = 10
	label.position = gate_pos[i] + Vector3(0, 5.5, 0)
	add_child(label)
	var n := found.count(true)
	count_label.text = "Gates found %d / 12" % n
	name_rows[i].text = "%s  (%s)" % [sec["name"], sec["ref"]]
	name_rows[i].add_theme_color_override("font_color", Color(0.30, 0.20, 0.10))
	hint.visible = false
	_show_toast("%s\n%s" % [sec["name"], sec["ref"]])
	if n == found.size():
		finished = true
		time_done = time + 2.0
		get_tree().create_timer(2.6).timeout.connect(func() -> void:
			_show_toast("Jerusalem lies before him.\n\"Let us rise up and build.\"  Neh. 2:18", 5.0))

func _show_toast(text: String, hold := 2.2) -> void:
	toast.text = text
	var tw := create_tween()
	tw.tween_property(toast, "modulate:a", 1.0, 0.25)
	tw.tween_interval(hold)
	tw.tween_property(toast, "modulate:a", 0.0, 0.8)

func _update_beacon() -> void:
	var best := -1
	var best_d := 45.0
	for i in gate_pos.size():
		if found[i]:
			continue
		var d := hero_pos.distance_to(gate_pos[i])
		if d < best_d:
			best_d = d
			best = i
	beacon.visible = best >= 0
	if best >= 0:
		beacon.position = gate_pos[best] + Vector3(0, 8.0, 0)
		(beacon.material_override as StandardMaterial3D).albedo_color.a = 0.16 + 0.08 * sin(time * 3.0)

func _snap_camera() -> void:
	cam.position = _cam_goal()
	cam.look_at(hero_pos + Vector3(0, 1, 0))

func _cam_goal() -> Vector3:
	var pitch := deg_to_rad(52.0)
	return hero_pos + Vector3(0, sin(pitch), cos(pitch)) * 36.0

func _follow_camera(delta: float) -> void:
	var offset := _cam_goal() - hero_pos
	cam.position = cam.position.lerp(hero_pos + offset, minf(1.0, delta * 4.0))
	cam.look_at(cam.position - offset + Vector3(0, 1, 0))
