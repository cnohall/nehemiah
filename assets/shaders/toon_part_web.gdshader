shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// toon_part for the web build: WebGL drops per-instance uniforms on some parts
// (they rendered solid black), so there each rig keeps one material per colour.

uniform vec4 part_color : source_color = vec4(1.0);
uniform float flash = 0.0;

#include "res://assets/shaders/toon_part.gdshaderinc"
