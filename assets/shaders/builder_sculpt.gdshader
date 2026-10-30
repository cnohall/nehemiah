shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

instance uniform vec4 part_color : source_color = vec4(1.0);
instance uniform float flash = 0.0;
// A warm rim (as toon_part) so figures lift off the pale ground at play zoom
uniform vec4 rim_color : source_color = vec4(1.0, 0.93, 0.78, 1.0);
uniform float rim_strength = 0.08;
uniform float wear = 0.08;
// 1: beaten metal (helmets, their own material): a tighter, brighter highlight
uniform float metal = 0.0;
varying vec3 local_pos;

// Wear: soft blotches of grime and fading in the part's own space (they ride with it),
// so a head-cloth reads as worn in the sun, not as fresh paint; on skin, a weathered tone
float blot(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n = dot(i, vec3(1.0, 57.0, 113.0));
	vec4 a = fract(sin(vec4(n, n + 1.0, n + 57.0, n + 58.0)) * 43758.5453);
	vec4 b = fract(sin(vec4(n + 113.0, n + 114.0, n + 170.0, n + 171.0)) * 43758.5453);
	vec4 m = mix(a, b, f.z);
	vec2 e = mix(m.xy, m.zw, f.y);
	return mix(e.x, e.y, f.x);
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec3 paint = part_color.rgb;
	paint *= 1.0 - wear * blot(local_pos * 11.0 + part_color.rgb * 7.0);
	ALBEDO = mix(paint, vec3(1.0, 0.96, 0.88), flash * 0.8);
	ROUGHNESS = mix(0.86, 0.55, metal);
	SPECULAR = 0.22;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = rim_color.rgb * rim * rim_strength + vec3(1.0, 0.96, 0.88) * flash * 0.5;
}

void light() {
	float wrapped = clamp((dot(NORMAL, LIGHT) + 0.18) / 1.18, 0.0, 1.0);
	DIFFUSE_LIGHT += wrapped * ATTENUATION * LIGHT_COLOR / PI;
	vec3 half_direction = normalize(LIGHT + VIEW);
	float sheen = pow(max(dot(NORMAL, half_direction), 0.0), 28.0);
	float gloss = pow(max(dot(NORMAL, half_direction), 0.0), 40.0);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * (sheen * 0.0015 + gloss * 0.05 * metal);
}
