shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// One body part of a CharacterRig. Colour + hit flash are per-instance, so every
// part of every character shares this one material.
// Soft two-tone light (painted, not plasticky) + a warm rim so figures lift off the ground.

instance uniform vec4 part_color : source_color = vec4(1.0);
instance uniform float flash = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 0.96, 0.88, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.93, 0.78, 1.0);

void fragment() {
	ALBEDO = mix(part_color.rgb, flash_color.rgb, flash * 0.8);
	ROUGHNESS = 1.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = rim_color.rgb * rim * 0.18 + flash_color.rgb * flash * 0.5;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// Wide soft terminator: lit side flat, shadow side a clear second tone
	float t = smoothstep(-0.05, 0.3, ndl);
	DIFFUSE_LIGHT += mix(0.08, 1.0, t) * ATTENUATION * LIGHT_COLOR / PI;
}
