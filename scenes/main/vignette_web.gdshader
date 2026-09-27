shader_type canvas_item;
render_mode blend_mul;

// Web stand-in for Main's PostFX pass: the warm vignette alone, multiplied over the
// frame. No tilt-shift — reading the screen texture (and building its mips) every
// frame is the priciest pass on WebGL.

uniform float vignette_strength = 0.22;
uniform vec3 tint = vec3(0.30, 0.24, 0.20);

void fragment() {
	vec2 uv = SCREEN_UV - 0.5;
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float v = smoothstep(0.35, 0.95, length(uv) * 1.1);
	COLOR = vec4(mix(vec3(1.0), tint * 2.2, v * vignette_strength), 1.0);
}
