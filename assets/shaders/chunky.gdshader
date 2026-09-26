shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

// Chunky world geometry (see Chunky.gd). Colour comes from the vertex / multimesh
// instance colour, authored in sRGB.
//   bevel > 0: the unit block's chamfer vertices are re-inset per instance so the
//              chamfer is `bevel` metres wide on every block, however it's stretched.
//   edge_light: chamfers catch a little extra light — the hand-cut highlight.
//   facets: flat-shaded triangles (foliage, boulders).

uniform float bevel = 0.06;
uniform float unit_inset = 0.15;
uniform bool facets = false;
uniform float edge_light = 0.22;
uniform float top_light = 0.07;
uniform float grain = 0.06;
// Wood: grain streaks running along the block's local Y (timbers are stretched on Y)
uniform float streaks = 0.0;
// Contact darkening toward the ground — grounds blocks without relying on SSAO alone
uniform float ground_ao = 0.28;
uniform float ground_ao_height = 0.55;

varying float v_edge;
varying vec3 v_wnormal;
varying vec3 v_wpos;
varying vec3 v_lpos;
varying vec3 v_scale;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	vec3 an = abs(NORMAL);
	v_edge = step(0.1, 1.0 - max(an.x, max(an.y, an.z)));
	if (bevel > 0.0 && unit_inset > 0.0) {
		vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
		vec3 inset = min(vec3(bevel) / max(sc, vec3(0.001)), vec3(0.3));
		vec3 is_in = step(abs(VERTEX), vec3(0.5 - unit_inset * 0.5));
		VERTEX = mix(VERTEX, sign(VERTEX) * (0.5 - inset), is_in);
	}
	vec3 sc2 = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	v_lpos = VERTEX * sc2;
	v_scale = sc2;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = to_linear(COLOR.rgb);
	float n = vnoise(v_wpos * 3.1) * 0.6 + vnoise(v_wpos * 9.0) * 0.4;
	c *= 1.0 - grain + n * grain * 2.0;
	c *= 1.0 + top_light * smoothstep(0.6, 0.9, v_wnormal.y);
	c *= 1.0 + edge_light * v_edge;
	if (streaks > 0.0) {
		// Grain runs along the longest axis of the timber
		vec3 f = vec3(1.0);
		if (v_scale.y >= v_scale.x && v_scale.y >= v_scale.z) f.y = 0.07;
		else if (v_scale.x >= v_scale.z) f.x = 0.07;
		else f.z = 0.07;
		float g = vnoise(v_lpos * f * 22.0);
		g = g * 0.7 + vnoise(v_lpos * f * 60.0 + 7.0) * 0.3;
		c *= 1.0 - streaks + g * streaks * 1.6;
	}
	c *= mix(1.0 - ground_ao, 1.0, smoothstep(0.0, ground_ao_height, v_wpos.y));
	ALBEDO = c;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	if (facets) {
		NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	}
}
