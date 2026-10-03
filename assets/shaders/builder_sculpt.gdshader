shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

instance uniform vec4 part_color : source_color = vec4(1.0);
instance uniform float flash = 0.0;

void fragment() {
	vec3 paint = part_color.rgb;
	ALBEDO = mix(paint, vec3(1.0, 0.96, 0.88), flash * 0.8);
	ROUGHNESS = 0.84;
	SPECULAR = 0.22;
	EMISSION = vec3(1.0, 0.96, 0.88) * flash * 0.5;
}

void light() {
	float wrapped = clamp((dot(NORMAL, LIGHT) + 0.18) / 1.18, 0.0, 1.0);
	DIFFUSE_LIGHT += wrapped * ATTENUATION * LIGHT_COLOR / PI;
	vec3 half_direction = normalize(LIGHT + VIEW);
	float sheen = pow(max(dot(NORMAL, half_direction), 0.0), 28.0);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * sheen * 0.0015;
}
