shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// A Blender-built figure (BakedFigure, tools/blender): one skinned mesh, its paint per vertex.
//   COLOR.rgb  paint, wear and grime baked in (Blender)
//   COLOR.a    1 = fixed paint; 0 = dyed cloth: rgb is half the shade relative to the dye
//   UV.x       surface kind as builder_body.gdshader (0 skin, 1 linen, 2 leather … 6 bronze, 9 sculpt)
//   UV.y       ambient occlusion baked in Blender (1 open, 0 shut in)

instance uniform vec4 dye : source_color = vec4(1.0);
instance uniform float flash = 0.0;
uniform vec4 rim_color : source_color = vec4(1.0, 0.93, 0.78, 1.0);
uniform float rim_strength = 0.08;
// How much of the baked occlusion shows: a soft shade in creases, never black
uniform float ao_strength = 0.4;

varying float kind;
varying float ao;

void vertex() {
	kind = UV.x;
	ao = UV.y;
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	// Paint is stored as authored (sRGB, as CharacterRig's colours); albedo wants linear
	// Dyed cloth: its shade against the dye, taken to linear by the same curve (≈ power 2.2)
	vec3 paint = COLOR.a > 0.5 ? to_linear(COLOR.rgb) : min(dye.rgb * pow(COLOR.rgb * 2.0, vec3(2.2)), vec3(1.0));
	paint *= mix(1.0, ao, ao_strength);
	ALBEDO = mix(paint, vec3(1.0, 0.96, 0.88), flash * 0.8);
	bool metal = kind > 5.5 && kind < 7.5;
	ROUGHNESS = metal ? 0.60 : 0.88;
	SPECULAR = 0.22;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = rim_color.rgb * rim * rim_strength + vec3(1.0, 0.96, 0.88) * flash * 0.5;
}

void light() {
	float wrapped = clamp((dot(NORMAL, LIGHT) + 0.18) / 1.18, 0.0, 1.0);
	DIFFUSE_LIGHT += wrapped * ATTENUATION * LIGHT_COLOR / PI;
	vec3 half_direction = normalize(LIGHT + VIEW);
	float sheen = pow(max(dot(NORMAL, half_direction), 0.0), 28.0);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * sheen * (kind > 5.5 && kind < 7.5 ? 0.035 : 0.0015);
}
