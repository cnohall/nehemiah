shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

// Still water seen from above (pools, the well, troughs): a deep tint that lightens toward
// the sky at glancing angles, two sets of slow ripples that bend the normal, and sun glints
// that wink on the crests. Flat quads only; no refraction, no transparency cost.

uniform vec3 deep : source_color = vec3(0.12, 0.34, 0.40);
uniform vec3 shallow : source_color = vec3(0.30, 0.58, 0.60);
uniform float ripple = 0.35;
uniform float scale = 1.6;

varying vec2 wxz;

float h(vec2 p) {
	return sin(p.x * 1.7 + TIME * 0.9) * sin(p.y * 1.3 - TIME * 0.7)
		+ 0.6 * sin(p.x * 2.9 - p.y * 2.1 + TIME * 1.4)
		+ 0.35 * sin(p.x * 5.3 + p.y * 4.1 - TIME * 2.1);
}

void vertex() {
	wxz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 p = wxz * scale;
	float e = 0.05;
	float dx = h(p + vec2(e, 0.0)) - h(p - vec2(e, 0.0));
	float dz = h(p + vec2(0.0, e)) - h(p - vec2(0.0, e));
	vec2 slope = vec2(dx, dz) / (2.0 * e) * 0.05 * ripple;
	vec3 n = normalize(vec3(-slope.x, 1.0, -slope.y));
	vec3 vn = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	NORMAL = vn;
	float fres = pow(1.0 - clamp(dot(vn, VIEW), 0.0, 1.0), 2.0);
	float crest = smoothstep(0.55, 1.0, h(p * 0.9 + 3.0) * 0.5 + 0.5);
	ALBEDO = mix(deep, shallow, clamp(fres * 1.5 + crest * 0.18, 0.0, 1.0));
	ROUGHNESS = 0.08;
	SPECULAR = 0.9;
	EMISSION = vec3(1.0, 0.95, 0.8) * smoothstep(0.93, 1.0, h(p * 1.7 + TIME * 0.2) * 0.35 + 0.65) * 0.35;
}
