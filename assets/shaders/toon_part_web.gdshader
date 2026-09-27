shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// toon_part for the web build. WebGL pays per draw call, so there each rig's parts
// are merged per pivot (CharacterRig._bake_web) with the part colour in the vertices
// (COLOR arrives already linear); one material per rig carries the hit flash.

uniform float flash = 0.0;
varying vec4 part_color;

void vertex() {
	part_color = COLOR;
}

#include "res://assets/shaders/toon_part.gdshaderinc"
