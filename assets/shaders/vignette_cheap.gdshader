shader_type canvas_item;

// Phone stand-in for main.tscn's PostFX pass: the same warm vignette, blended over
// the frame as a plain overlay — no screen-texture copy, no tilt-shift blur.

uniform float vignette_strength = 0.22;
uniform vec3 tint = vec3(0.30, 0.24, 0.20);

void fragment() {
	vec2 uv = SCREEN_UV - 0.5;
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float v = smoothstep(0.35, 0.95, length(uv) * 1.1);
	// The desktop pass multiplies by tint * 2.2; an overlay of the darker tint reads alike
	COLOR = vec4(tint * 0.6, v * vignette_strength * 1.6);
}
