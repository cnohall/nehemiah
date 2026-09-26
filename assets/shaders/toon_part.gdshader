shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// One body part of a CharacterRig. Colour + hit flash are per-instance, so every
// part of every character shares this one material.

instance uniform vec4 part_color : source_color = vec4(1.0);
instance uniform float flash = 0.0;

#include "res://assets/shaders/toon_part.gdshaderinc"
