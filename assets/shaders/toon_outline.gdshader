shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;

// Inverted-hull outline pass for CharacterRig parts: the back faces, pushed out
// along the normal, drawn flat dark. Cartoon silhouette that survives any lighting.

uniform vec4 outline_color : source_color = vec4(0.17, 0.11, 0.07, 1.0);
uniform float width = 0.013;   // a thin rim: a heavy one reads as a cartoon's ink line

void vertex() {
	VERTEX += NORMAL * width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
