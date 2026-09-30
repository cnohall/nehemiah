shader_type spatial;
render_mode diffuse_lambert, cull_disabled, world_vertex_coords;

// Grass tufts (ScatterLayer._tuft_mesh). Colour from the multimesh instance, authored in
// sRGB; UV.y runs 0 at the root to 1 at the blade tip.
//   Lit as if facing straight up, like the ground under it, so a tuft reads as a soft
//   clump rather than a bundle of dark-sided spikes. Dark at the root, sun-bleached
//   toward the tip, and a slow sway so the ground feels alive.

uniform float sway = 0.035;
uniform vec3 tip_tint : source_color = vec3(0.88, 0.80, 0.52);
uniform float tip_bleach = 0.28;
uniform float root_dark = 0.5;

varying float v_h;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void vertex() {
	v_h = UV.y;
	float ph = dot(VERTEX.xz, vec2(0.37, 0.23));
	float w = sin(TIME * 1.7 + ph) * 0.6 + sin(TIME * 2.9 + ph * 1.7) * 0.4;
	VERTEX.xz += vec2(0.8, 0.5) * w * sway * v_h * v_h;
}

void fragment() {
	vec3 c = to_linear(COLOR.rgb);
	vec3 tip = mix(c, tip_tint, tip_bleach) * 1.08;
	ALBEDO = mix(c * root_dark, tip, smoothstep(0.0, 1.0, v_h));
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}
