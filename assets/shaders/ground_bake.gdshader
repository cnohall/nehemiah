shader_type canvas_item;
render_mode blend_disabled;

// Bakes the ground's static noise into textures (GroundMesh, once at load), so the ground
// samples them instead of running ~150 sines and a Voronoi search per pixel.
//   layer 0 coarse, 1 feature: ground_coarse / ground_feature over the ground (origin, extent)
//   layer 2 fine: ground_fine (detail, micro) over the same span
//   layer 3 grit: one GRIT_CELLS tile, both layers, stored as 0.5 + 4 x the brightness change

#include "res://assets/shaders/ground_noise.gdshaderinc"

uniform int layer = 0;
uniform vec2 origin = vec2(-110.0, -90.0);
uniform vec2 extent = vec2(220.0, 180.0);
uniform float scale = 0.042;

void fragment() {
	vec2 p = (origin + UV * extent) * scale;
	if (layer == 0) {
		COLOR = ground_coarse(p);
	} else if (layer == 1) {
		COLOR = ground_feature(p);
	} else if (layer == 2) {
		COLOR = vec4(ground_fine(p), 0.0, 1.0);
	} else {
		vec2 gp = UV * GRIT_CELLS;
		COLOR = vec4(0.5 + 4.0 * grit(gp, 0), 0.5 + 4.0 * grit(gp, 1), 0.0, 1.0);
	}
}
