shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_back;

uniform float scale     : hint_range(0.01, 0.2)  = 0.042;
uniform float roughness : hint_range(0.0,  1.0)  = 0.97;

// Warm sandy Jerusalem palette (matched to reference)
uniform vec3 col_sand_bright = vec3(0.875, 0.745, 0.475);  // highlight sand
uniform vec3 col_sand_mid    = vec3(0.795, 0.660, 0.385);  // base sand
uniform vec3 col_sand_dark   = vec3(0.695, 0.560, 0.295);  // shadow sand
uniform vec3 col_dirt        = vec3(0.590, 0.465, 0.235);  // dark dirt patch
uniform vec3 col_trodden     = vec3(0.640, 0.525, 0.360);  // packed earth under foot

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
	float yard = 1.0 - smoothstep(5.0, 9.0, length(world_xz - vec2(0.0, 10.0)) + edge_noise);
	float street = (1.0 - smoothstep(2.0, 3.5, abs(world_xz.x) + edge_noise))
		* smoothstep(9.0, 13.0, world_xz.y);
	float trodden = clamp(max(max(wall_band, yard), street), 0.0, 1.0);
	col = mix(col, col_trodden, trodden * 0.55);

	// Micro grain — subtle brightness flicker for sandy texture
	col *= 0.90 + 0.10 * micro;

	// Pebble speckle
	float peb = step(0.965, hash2(floor(world_xz * 9.0)));
	col = mix(col, col_sand_dark * 0.85, peb * 0.5);

	ALBEDO    = col;
	ROUGHNESS = roughness;
	SPECULAR  = 0.0;
}
