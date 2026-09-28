shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

instance uniform vec4 part_color : source_color = vec4(1.0);
instance uniform float flash = 0.0;
instance uniform float hair_detail = 0.0;

void fragment() {
	vec3 paint = part_color.rgb * COLOR.rgb;   // merged rigs: colour per vertex
	// UV.x runs around each sculpted lock, UV.y follows its growth direction.
	// Fine tonal strands reinforce the actual grooves without extra draw calls.
	float strand = sin(UV.x * 75.398 + sin(UV.y * 7.0) * 0.6);
	float groove = pow(max(0.0, strand), 8.0);
	paint *= 1.0 - groove * 0.16 * hair_detail;
	ALBEDO = mix(paint, vec3(1.0, 0.96, 0.88), flash * 0.8);
	ROUGHNESS = mix(0.85, 0.68, hair_detail);
	SPECULAR = 0.22;
	EMISSION = vec3(1.0, 0.96, 0.88) * flash * 0.5;
}

void light() {
	float wrapped = clamp((dot(NORMAL, LIGHT) + 0.18) / 1.18, 0.0, 1.0);
	DIFFUSE_LIGHT += wrapped * ATTENUATION * LIGHT_COLOR / PI;
	vec3 half_direction = normalize(LIGHT + VIEW);
	float sheen = pow(max(dot(NORMAL, half_direction), 0.0), 28.0);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * sheen * (0.0015 + hair_detail * 0.010);
}
