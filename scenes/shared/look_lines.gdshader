shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// map_look.gdshader's look 5 on its own: the world's depth ink lines, laid over the frame
// under the whole-screen look (look_screen.gdshader). Depth only: map_look declares the
// screen texture for its other looks, and that alone made the renderer copy the whole
// frame every frame (2.6 ms GPU at 5120x1440, High) for a pass that never read it.

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 ink = vec3(0.22, 0.14, 0.09);

void vertex() {
	POSITION = vec4(VERTEX.xy, 0.5, 1.0);
}

vec3 to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

float lin_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, d) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, d);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return -v.z / v.w;
}

float depth_edge(vec2 uv, vec2 px, mat4 inv_proj, float w) {
	float d = lin_depth(uv, inv_proj);
	float dd = 0.0;
	for (int k = 0; k < 4; k++) {
		vec2 o = vec2(k == 0 ? w : (k == 1 ? -w : 0.0), k == 2 ? w : (k == 3 ? -w : 0.0)) * px;
		dd += abs(lin_depth(uv + o, inv_proj) - d);
	}
	return smoothstep(0.012, 0.03, dd / d);
}

void fragment() {
	ALBEDO = to_linear(ink) * 0.5;
	ALPHA = depth_edge(SCREEN_UV, 1.0 / VIEWPORT_SIZE, INV_PROJECTION_MATRIX, 1.0) * 0.8;
}
