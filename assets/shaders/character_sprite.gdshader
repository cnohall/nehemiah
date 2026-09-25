shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// LPC sprite: Y-axis billboard + 1px outline + hit flash + tint.
// SpriteBase3D maps UV into the full sheet (AtlasTexture region), so `sheet`
// is the whole sprite sheet and one texel = one sheet pixel.

uniform sampler2D sheet : source_color, filter_nearest;
uniform vec4 outline_color : source_color = vec4(0.17, 0.11, 0.07, 1.0);
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 flash_color : source_color = vec4(1.0, 0.96, 0.88, 1.0);
uniform float flash : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	// Same as SpriteBase3D BILLBOARD_FIXED_Y: upright, turned toward the camera
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 texel = 1.0 / vec2(textureSize(sheet, 0));
	vec4 c = texture(sheet, UV);
	c.rgb *= tint.rgb * COLOR.rgb;
	// Flash the body only — the outline stays dark so the silhouette survives
	c.rgb = mix(c.rgb, flash_color.rgb, flash * 0.75);
	if (c.a < 0.5) {
		float n = texture(sheet, UV + vec2(texel.x, 0.0)).a
			+ texture(sheet, UV - vec2(texel.x, 0.0)).a
			+ texture(sheet, UV + vec2(0.0, texel.y)).a
			+ texture(sheet, UV - vec2(0.0, texel.y)).a;
		if (n > 0.5) {
			c = outline_color;
		}
	}
	ALBEDO = c.rgb;
	ALPHA = c.a * COLOR.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
