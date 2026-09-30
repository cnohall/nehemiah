shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

instance uniform vec4 part_color : source_color = vec4(1.0);
instance uniform float flash = 0.0;
// Skin, linen, leather, wicker, stone, wood, bronze.
instance uniform float surface_kind = 0.0;

void fragment() {
	vec3 paint = part_color.rgb;
	if (surface_kind > 0.5 && surface_kind < 1.5) {
		float weave = sin(UV.x * 754.0) * sin(UV.y * 628.0);
		paint *= 0.985 + weave * 0.015;
	} else if (surface_kind > 1.5 && surface_kind < 2.5) {
		float grain = sin(UV.x * 197.0 + sin(UV.y * 137.0)) * sin(UV.y * 239.0);
		paint *= 0.98 + grain * 0.025;
	} else if (surface_kind > 4.5 && surface_kind < 5.5) {
		float grain = sin(UV.y * 108.0 + sin(UV.x * 15.0) * 2.0);
		paint *= 0.96 + grain * 0.045;
	}
	ALBEDO = mix(paint, vec3(1.0, 0.96, 0.88), flash * 0.8);
	ROUGHNESS = surface_kind > 5.5 ? 0.60 : 0.90;
	EMISSION = vec3(1.0, 0.96, 0.88) * flash * 0.5;
}

void light() {
	float wrapped = clamp((dot(NORMAL, LIGHT) + 0.18) / 1.18, 0.0, 1.0);
	DIFFUSE_LIGHT += wrapped * ATTENUATION * LIGHT_COLOR / PI;
	float sheen = pow(max(dot(NORMAL, normalize(LIGHT + VIEW)), 0.0), 24.0);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * sheen * (surface_kind > 5.5 ? 0.035 : 0.002);
}
