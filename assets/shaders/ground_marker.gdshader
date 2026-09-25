shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// Flat quad under a character: soft contact shadow, optional coloured ring.

uniform vec4 shadow_color : source_color = vec4(0.18, 0.12, 0.06, 0.45);
uniform vec4 ring_color : source_color = vec4(0.0);
uniform float ring_radius = 0.33;   // UV units (quad edge = 0.5)
uniform float ring_width = 0.045;

void fragment() {
	float d = length(UV - 0.5);   // 0 at centre, 0.5 at quad edge
	float blob = 1.0 - smoothstep(0.04, 0.22, d);
	float ring = (1.0 - smoothstep(0.0, 0.012, abs(d - ring_radius) - ring_width * 0.5)) * ring_color.a;
	vec3 col = mix(shadow_color.rgb, ring_color.rgb, ring);
	ALBEDO = col;
	ALPHA = max(blob * shadow_color.a, ring);
}
