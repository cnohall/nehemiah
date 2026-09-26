shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_back;

uniform float scale     : hint_range(0.01, 0.2)  = 0.042;
uniform float roughness : hint_range(0.0,  1.0)  = 0.97;

// Warm Judean earth (sRGB). Mid-value ochre so the pale limestone wall, the
// stations and the workers all stand out against it.
uniform vec3 col_sand_bright : source_color = vec3(0.880, 0.720, 0.470);  // sunlit sand
uniform vec3 col_sand_mid    : source_color = vec3(0.820, 0.620, 0.380);  // base earth
uniform vec3 col_sand_dark   : source_color = vec3(0.720, 0.510, 0.320);  // darker drifts
uniform vec3 col_dirt        : source_color = vec3(0.640, 0.400, 0.260);  // red-brown soil
uniform vec3 col_trodden     : source_color = vec3(0.900, 0.790, 0.620);  // packed, pale path
// Dirt track from the gate out toward the enemy camp (matches ScatterLayer.GATE_X)
uniform float gate_x = -4.0;
uniform vec3 col_scrub       : source_color = vec3(0.520, 0.570, 0.290);  // dry olive scrub
uniform vec3 col_scrub_lit   : source_color = vec3(0.620, 0.650, 0.340);
// Per-section look (SectionTerrain): where the supply yard is trodden, how much scrub
// grows (+ = greener, e.g. the King's Garden), an overall cast (ash at the Dung Gate)
// and how far the ground outside falls away into shade (the valleys)
uniform vec2 yard_center = vec2(0.0, 10.0);
uniform float scrub_bias = 0.0;
uniform vec3 section_tint : source_color = vec3(0.5, 0.5, 0.5);
uniform float tint_amount = 0.0;
uniform float outside_shade = 0.0;

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

float hash2(vec2 p) {
	p = fract(p * vec2(234.34, 435.35));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash2(i),             hash2(i + vec2(1,0)), u.x),
		mix(hash2(i + vec2(0,1)), hash2(i + vec2(1,1)), u.x),
		u.y
	);
}

float fbm(vec2 p) {
	float v = 0.0, a = 0.55;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p  = p * 2.13 + vec2(3.71, 1.93);
		a *= 0.48;
	}
	return v;
}

void fragment() {
	vec2 p = world_xz * scale;

	float macro  = fbm(p);
	float mid    = fbm(p * 2.8  + vec2(5.1, 3.3));
	float detail = fbm(p * 7.2  + vec2(1.9, 8.7));
	float micro  = vnoise(p * 18.0 + vec2(4.5, 9.3));

	// Sand layers — mostly yellow-warm, subtle variation
	vec3 col = mix(col_sand_mid, col_sand_bright, smoothstep(0.42, 0.68, macro));
	col = mix(col, col_sand_dark, smoothstep(0.55, 0.78, mid) * 0.45);
	col = mix(col, col_dirt,      smoothstep(0.72, 0.88, detail) * 0.28);

	// Trodden earth: along the wall line, around the supply yard, and the street south
	float edge_noise = (detail - 0.5) * 1.6;
	float wall_band = 1.0 - smoothstep(2.5, 5.0, abs(world_xz.y) + edge_noise);
	wall_band *= 1.0 - smoothstep(22.0, 26.0, abs(world_xz.x));
	float yard = 1.0 - smoothstep(5.0, 9.0, length(world_xz - yard_center) + edge_noise);
	float street = (1.0 - smoothstep(2.0, 3.5, abs(world_xz.x) + edge_noise))
		* smoothstep(9.0, 13.0, world_xz.y);
	// The track: straight through the yard to the gate, then winding north
	float track_x = world_xz.y < -1.5
		? gate_x - 3.0 * sin(world_xz.y * 0.09) - (world_xz.y + 1.5) * 0.12
		: gate_x;
	float track = (1.0 - smoothstep(1.1, 2.0, abs(world_xz.x - track_x) + edge_noise * 0.6))
		* (1.0 - smoothstep(13.0, 15.0, world_xz.y));
	float trodden = clamp(max(max(max(wall_band, yard), street), track), 0.0, 1.0);
	col = mix(col, col_trodden, trodden * 0.6);

	// Patches of dry scrub off the beaten track — the hills weren't bare sand
	float scrub = smoothstep(0.56 - scrub_bias, 0.66 - scrub_bias, fbm(p * 1.6 + vec2(11.3, 4.1)) + (mid - 0.5) * 0.25);
	scrub *= 1.0 - trodden;
	scrub *= 1.0 - (1.0 - smoothstep(6.0, 9.0, abs(world_xz.y))) * (1.0 - smoothstep(24.0, 28.0, abs(world_xz.x)));
	vec3 scrub_col = mix(col_scrub, col_scrub_lit, smoothstep(0.35, 0.75, detail));
	col = mix(col, scrub_col, scrub * 0.85);

	col = mix(col, section_tint, tint_amount * (0.7 + 0.6 * (mid - 0.5)));
	// Falling away outside the wall: darker and a touch cooler with distance
	float fall = smoothstep(-4.0, -30.0, world_xz.y) * outside_shade;
	col = mix(col, col * vec3(0.72, 0.74, 0.86), fall);

	// Micro grain — subtle brightness flicker for sandy texture
	col *= 0.90 + 0.10 * micro;

	// Pebble speckle
	float peb = step(0.965, hash2(floor(world_xz * 9.0)));
	col = mix(col, col_sand_dark * 0.85, peb * 0.5);

	ALBEDO    = col;
	ROUGHNESS = roughness;
	SPECULAR  = 0.0;
}
