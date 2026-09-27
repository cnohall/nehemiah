// Shared body of toon_part / toon_part_web. Expects `part_color` and `flash`.
// Soft painted light + a faint warm rim so figures lift off the ground.

uniform vec4 flash_color : source_color = vec4(1.0, 0.96, 0.88, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.93, 0.78, 1.0);

void fragment() {
	ALBEDO = mix(part_color.rgb, flash_color.rgb, flash * 0.8);
	ROUGHNESS = 1.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = rim_color.rgb * rim * 0.08 + flash_color.rgb * flash * 0.5;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// A broad painted transition reveals rounded cheeks, cloth and hair locks.
	float t = smoothstep(-0.25, 0.85, ndl);
	DIFFUSE_LIGHT += mix(0.12, 1.0, t) * ATTENUATION * LIGHT_COLOR / PI;
}
