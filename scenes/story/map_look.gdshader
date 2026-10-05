shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// Full-screen pass over a 3D scene that turns the model into something drawn.
// look 1: tinted lithograph (ink lines from depth, crayon tone on paper, hatched shade)
// look 2: mosaic, after the Madaba map (Voronoi tesserae in a short stone palette)
// look 3: the scribe's ink plan (as 1, flatter washes, heavier line; camera goes top-down)
// look 4: cel shading (flat light bands, ink outlines, no paper)
// look 5: depth ink lines only — look_screen.gdshader draws the rest over the whole
//         screen, HUD included, and has no depth of its own

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float film_white = 0.0;    // > 0: filmic-tonemap the frame first (game world)
uniform float film_exposure = 1.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 0.5, 1.0);
}

vec3 srgb(vec3 c) {
	return mix(1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, c * 12.92, lessThan(c, vec3(0.0031308)));
}
vec3 to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}
vec3 hable(vec3 x) {
	return (x * (0.15 * x + 0.05) + 0.004) / (x * (0.15 * x + 0.5) + 0.06) - 0.0667;
}
vec3 scr(vec2 uv) {
	vec3 c = texture(screen_tex, uv).rgb;
	if (film_white > 0.0) {
		// The scene was lit for a filmic tonemap the pass has switched off: apply it here
		c = hable(c * film_exposure * 2.0) / hable(vec3(film_white));
	}
	return srgb(clamp(c, 0.0, 1.0));
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

#include "res://scenes/shared/look.gdshaderinc"

void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;
	vec2 frag = FRAGCOORD.xy;
	if (look == 5) {
		// Lines only, laid over the frame rather than repainting it: the screen copy is
		// taken before see-through things draw (signs, sprites), which must survive
		ALBEDO = to_linear(ink) * 0.5;
		ALPHA = depth_edge(SCREEN_UV, px, INV_PROJECTION_MATRIX, 1.0) * 0.8;
	} else {
		vec3 col;
		if (look == 4) {
			col = cel(SCREEN_UV, px, INV_PROJECTION_MATRIX);
		} else if (look == 2) {
			col = mosaic(SCREEN_UV, frag, px, INV_PROJECTION_MATRIX);
		} else {
			col = litho(SCREEN_UV, frag, px, INV_PROJECTION_MATRIX, look == 3);
		}
		ALBEDO = to_linear(clamp(col, 0.0, 1.0));
	}
}
