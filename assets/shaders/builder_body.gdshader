shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

instance uniform vec4 part_color : source_color = vec4(1.0);
instance uniform float flash = 0.0;
// 0 skin, 1 linen, 2 leather, 3 wicker, 4 stone, 5 wood, 6 bronze, 7 scale armour, 8 wool
instance uniform float surface_kind = 0.0;
// A warm rim (as toon_part) so figures lift off the pale ground at play zoom
uniform vec4 rim_color : source_color = vec4(1.0, 0.93, 0.78, 1.0);
uniform float rim_strength = 0.08;
uniform float wear = 0.10;
varying vec3 local_pos;

// Wear: soft blotches of grime and fading in the part's own space (they ride with it),
// so cloth and leather read as used, not as fresh paint
float blot(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n = dot(i, vec3(1.0, 57.0, 113.0));
	vec4 a = fract(sin(vec4(n, n + 1.0, n + 57.0, n + 58.0)) * 43758.5453);
	vec4 b = fract(sin(vec4(n + 113.0, n + 114.0, n + 170.0, n + 171.0)) * 43758.5453);
	vec4 m = mix(a, b, f.z);
	vec2 e = mix(m.xy, m.zw, f.y);
	return mix(e.x, e.y, f.x);
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec3 paint = part_color.rgb;
	if (surface_kind > 0.5 && surface_kind < 1.5) {
		float weave = sin(UV.x * 754.0) * sin(UV.y * 628.0);
		paint *= 0.985 + weave * 0.015;
		// Dust settles in the lower cloth: the hem picks up the ground's ochre
		// (skirt meshes hang below their belt pivot; sleeves and the chest never reach this low)
		paint = mix(paint, paint * vec3(0.90, 0.84, 0.74), smoothstep(-0.18, -0.46, local_pos.y) * 0.45);
	} else if (surface_kind > 1.5 && surface_kind < 2.5) {
		float grain = sin(UV.x * 197.0 + sin(UV.y * 137.0)) * sin(UV.y * 239.0);
		paint *= 0.98 + grain * 0.025;
	} else if (surface_kind > 4.5 && surface_kind < 5.5) {
		float grain = sin(UV.y * 108.0 + sin(UV.x * 15.0) * 2.0);
		paint *= 0.96 + grain * 0.045;
	} else if (surface_kind > 6.5 && surface_kind < 7.5) {
		// Scale armour: overlapping rows of small rounded plates, each lit at its lower lip
		// and shadowed where the next row laps over it
		vec2 g = vec2(UV.x * 44.0, UV.y * 15.0);
		float row = floor(g.y);
		vec2 c = fract(vec2(g.x + row * 0.5, g.y)) - vec2(0.5, 0.0);
		// Each plate a rounded tongue hanging from its row: dark gap at its sides and tip
		float side = smoothstep(0.36, 0.48, abs(c.x));
		float tip = smoothstep(0.62, 0.78, length(vec2(c.x * 1.5, (0.55 - c.y) * 1.1)));
		float gap = max(side * smoothstep(0.2, 0.6, c.y), tip);
		paint *= mix(1.0, 0.55, gap) * (0.84 + (1.0 - c.y) * 0.28);
	} else if (surface_kind > 7.5 && surface_kind < 8.5) {
		// Wool: a felted nap, no weave to see
		float nap = blot(local_pos * 70.0) * 0.6 + blot(local_pos * 23.0) * 0.4;
		paint *= 0.93 + nap * 0.1;
	}
	paint *= 1.0 - wear * blot(local_pos * 9.0 + part_color.rgb * 7.0);
	ALBEDO = mix(paint, vec3(1.0, 0.96, 0.88), flash * 0.8);
	bool metal = surface_kind > 5.5 && surface_kind < 7.5;
	ROUGHNESS = metal ? 0.60 : (surface_kind > 7.5 ? 0.97 : 0.90);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = rim_color.rgb * rim * rim_strength + vec3(1.0, 0.96, 0.88) * flash * 0.5;
}

void light() {
	float wrapped = clamp((dot(NORMAL, LIGHT) + 0.18) / 1.18, 0.0, 1.0);
	DIFFUSE_LIGHT += wrapped * ATTENUATION * LIGHT_COLOR / PI;
	float sheen = pow(max(dot(NORMAL, normalize(LIGHT + VIEW)), 0.0), 24.0);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * sheen * (surface_kind > 5.5 && surface_kind < 7.5 ? 0.035 : 0.002);
}
