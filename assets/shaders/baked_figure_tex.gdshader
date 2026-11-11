shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// A figure authored in Blender (tools/blender/build_crew.py): one skinned mesh, painted textures.
//   albedo_tex  paint; dyed cloth is painted as its shade (near white) and takes the dye
//   normal_tex  fine relief: weave, strands, wicker
//   aux_tex     r ambient occlusion, g roughness, b dye mask

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D aux_tex : hint_default_white, filter_linear_mipmap;
instance uniform vec4 dye : source_color = vec4(1.0);
instance uniform float flash = 0.0;
uniform vec4 rim_color : source_color = vec4(1.0, 0.93, 0.78, 1.0);
uniform float rim_strength = 0.08;
uniform float ao_strength = 0.75;
uniform float normal_strength = 1.0;

void fragment() {
	vec3 aux = texture(aux_tex, UV).rgb;
	vec3 paint = texture(albedo_tex, UV).rgb * mix(vec3(1.0), dye.rgb, aux.b);
	paint *= mix(1.0, aux.r, ao_strength);
	ALBEDO = mix(paint, vec3(1.0, 0.96, 0.88), flash * 0.8);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = aux.g;
	SPECULAR = 0.3;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = rim_color.rgb * rim * rim_strength + vec3(1.0, 0.96, 0.88) * flash * 0.5;
}

void light() {
	float wrapped = clamp((dot(NORMAL, LIGHT) + 0.18) / 1.18, 0.0, 1.0);
	DIFFUSE_LIGHT += wrapped * ATTENUATION * LIGHT_COLOR / PI;
	vec3 half_direction = normalize(LIGHT + VIEW);
	float gloss = 1.0 - ROUGHNESS;
	float sheen = pow(max(dot(NORMAL, half_direction), 0.0), mix(18.0, 120.0, gloss));
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * sheen * gloss * gloss * 0.3;
}
