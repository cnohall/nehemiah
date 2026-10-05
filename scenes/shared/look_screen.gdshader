shader_type canvas_item;

// The drawn looks over the whole finished screen, HUD and all (a rect on the top canvas
// layer). No depth here: outlines come from tone breaks, and the world's own depth lines
// from map_look.gdshader's lines-only pass underneath.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

vec3 scr(vec2 uv) {
	return texture(screen_tex, uv).rgb;    // 2D is already display colours
}
float depth_edge(vec2 uv, vec2 px, mat4 inv_proj, float w) {
	return 0.0;
}

#include "res://scenes/shared/look.gdshaderinc"

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	mat4 none = mat4(1.0);
	vec3 col;
	if (look == 4) {
		col = cel(SCREEN_UV, px, none);
	} else if (look == 2) {
		col = mosaic(SCREEN_UV, FRAGCOORD.xy, px, none);
	} else {
		col = litho(SCREEN_UV, FRAGCOORD.xy, px, none, look == 3);
	}
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
