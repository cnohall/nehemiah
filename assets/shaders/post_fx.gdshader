shader_type canvas_item;

// Screen-space finishing pass (Main's PostFX): tilt-shift blur toward the top and bottom of
// the screen, a warm vignette and a dither.
// The blur reads the screen copy itself, not its mip chain: with filter_linear_mipmap Godot
// built a blurred mip pyramid of the whole frame every frame (1.8 ms at 5120x1440, more than
// this whole pass), for a blur that never reaches past mip 1. Here mip 1 (Godot blurs each
// level) is stood in for by four bilinear taps 2.5 px out on the diagonals, blended in as
// the textureLod blend did: tools/postfx_check.gd, mean 0.4 of an 8-bit step off the old.

uniform float vignette_strength = 0.22;
uniform vec3 tint = vec3(0.30, 0.24, 0.20);
uniform float focus_center = 0.52;   // screen-y of the sharp band
uniform float focus_half = 0.34;    // half-height of the sharp band
uniform float blur_ramp = 0.3;
uniform float max_lod = 0.9;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

vec3 at(vec2 uv, float lod, vec2 px) {
	vec3 sharp = texture(screen_tex, uv).rgb;
	if (lod <= 0.0) {
		return sharp;
	}
	vec2 h = px * 2.5;
	vec3 soft = (texture(screen_tex, uv + h).rgb + texture(screen_tex, uv - h).rgb
		+ texture(screen_tex, uv + vec2(h.x, -h.y)).rgb + texture(screen_tex, uv + vec2(-h.x, h.y)).rgb) * 0.25;
	return mix(sharp, soft, lod);
}

void fragment() {
	float off = abs(SCREEN_UV.y - focus_center);
	float lod = smoothstep(focus_half, focus_half + blur_ramp, off) * max_lod;
	vec2 px = SCREEN_PIXEL_SIZE;
	// Five taps a (mip-)texel apart smooth out the blocky look of a bare high mip
	vec2 d = px * exp2(lod) * 0.7;
	vec3 col = at(SCREEN_UV, lod, px) * 0.36;
	col += at(SCREEN_UV + vec2(d.x, d.y), lod, px) * 0.16;
	col += at(SCREEN_UV + vec2(-d.x, d.y), lod, px) * 0.16;
	col += at(SCREEN_UV + vec2(d.x, -d.y), lod, px) * 0.16;
	col += at(SCREEN_UV + vec2(-d.x, -d.y), lod, px) * 0.16;
	vec2 uv = SCREEN_UV - 0.5;
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float v = smoothstep(0.35, 0.95, length(uv) * 1.1);
	col = mix(col, col * tint * 2.2, v * vignette_strength);
	// Interleaved-gradient dither, under one 8-bit step: breaks up banding in the pale
	// ground and the vignette falloff
	col += (fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715)))) - 0.5) / 255.0;
	COLOR = vec4(col, 1.0);
}
