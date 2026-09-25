shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, shadows_disabled;

// Small overhead bar: always faces the camera, drawn on top of the world.

uniform float fill : hint_range(0.0, 1.0) = 1.0;
uniform vec4 fill_color : source_color = vec4(0.52, 0.66, 0.28, 1.0);
uniform vec4 back_color : source_color = vec4(0.16, 0.11, 0.07, 0.85);
uniform float border = 0.12;   // fraction of the bar height

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 px = fwidth(UV);
	float bx = border * px.x / px.y * 0.5;   // same visual thickness on x as on y
	bool inner = UV.x > bx && UV.x < 1.0 - bx && UV.y > border && UV.y < 1.0 - border;
	float x = (UV.x - bx) / (1.0 - 2.0 * bx);
	vec4 c = (inner && x <= fill) ? fill_color : back_color;
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
