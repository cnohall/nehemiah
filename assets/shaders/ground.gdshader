shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_back;

uniform float scale     : hint_range(0.01, 0.2)  = 0.042;
uniform float roughness : hint_range(0.0,  1.0)  = 0.97;

// Judean earth (sRGB). Warm ochre, mid-value so the pale limestone wall, the
// stations and the workers all stand out against it.
uniform vec3 col_sand_bright : source_color = vec3(0.875, 0.745, 0.530);  // sunlit sand
uniform vec3 col_sand_mid    : source_color = vec3(0.805, 0.655, 0.445);  // base earth
uniform vec3 col_sand_dark   : source_color = vec3(0.705, 0.550, 0.370);  // darker drifts
uniform vec3 col_dirt        : source_color = vec3(0.600, 0.390, 0.250);  // red-brown soil
uniform vec3 col_trodden     : source_color = vec3(0.870, 0.770, 0.600);  // packed, pale path
// Dirt track from the gate out toward the enemy camp (matches ScatterLayer.GATE_X)
uniform float gate_x = -4.0;
uniform vec3 col_scrub       : source_color = vec3(0.460, 0.520, 0.260);  // dry olive scrub
uniform vec3 col_scrub_lit   : source_color = vec3(0.560, 0.610, 0.310);
// Per-section look (SectionTerrain): where the supply yard is trodden, how much scrub
// grows (+ = greener, e.g. the King's Garden), an overall cast (ash at the Dung Gate)
// and how far the ground outside falls away into shade (the valleys)
uniform vec2 yard_center = vec2(0.0, 10.0);
uniform float scrub_bias = 0.0;
uniform vec3 section_tint : source_color = vec3(0.5, 0.5, 0.5);
uniform float tint_amount = 0.0;
uniform float outside_shade = 0.0;

// Meadows: green ground under the grass colonies ScatterLayer plants — same mask as
// ScatterLayer.meadow(); kept off the work yard (work_rect: x0, z0, x1, z1)
uniform vec3 col_meadow     : source_color = vec3(0.560, 0.590, 0.300);   // dusty late-summer green
uniform vec3 col_meadow_dk  : source_color = vec3(0.440, 0.490, 0.230);
uniform vec3 col_ochre      : source_color = vec3(0.780, 0.500, 0.280);  // red-ochre earth
uniform vec4 work_rect = vec4(-14.0, -2.5, 14.0, 13.0);

// Cloud shadows drifting on the wind (DayLight fades the strength with the evening)
uniform float cloud_strength = 0.13;
uniform vec2 wind_dir = vec2(0.85, 0.52);
uniform float cloud_speed = 1.3;   // metres a second

// A painted feature of the section's ground (SectionTerrain sets it): 0 none, 1 dry wadi,
// 2 ploughed furrows, 3 ash and soot, 4 bare limestone, 5 damp market ground,
// 6 sawdust and shavings, 7 trampled fold
uniform int feature = 0;

varying vec2 world_xz;
varying float world_y;
varying float slope;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	world_y = VERTEX.y;
	slope = 1.0 - NORMAL.y;
}

float hash2(vec2 p) {
	p = fract(p * vec2(234.34, 435.35));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	// Continuous, differently angled waves avoid the visible cells of grid noise.
	float a = sin(p.x * 1.70 + p.y * 0.87 + sin(p.y * 0.33));
	float b = sin(p.x * -0.73 + p.y * 1.43 + 0.6 * sin(p.x * 0.58));
	float c = sin(p.x * 2.31 - p.y * 1.17);
	return 0.5 + 0.16 * a + 0.11 * b + 0.07 * c;
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

// Shared with ScatterLayer.meadow() — keep the two in step
float meadow_mask(vec2 w) {
	return sin(w.x * 0.21 + w.y * 0.13) * sin(w.y * 0.17 - w.x * 0.07)
		+ 0.45 * sin(w.x * 0.43 + 1.7) * sin(w.y * 0.39 + 0.4);
}

float work_area(vec2 w) {
	vec2 lo = work_rect.xy;
	vec2 hi = work_rect.zw;
	vec2 d = max(lo - w, w - hi);
	return 1.0 - smoothstep(0.0, 4.0, max(d.x, d.y));
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
	float street = (1.0 - smoothstep(2.6, 4.0, abs(world_xz.x - gate_x) + edge_noise))
		* smoothstep(9.0, 13.0, world_xz.y);
	// Cross street in the city (ScatterLayer.CROSS_Z)
	street = max(street, (1.0 - smoothstep(2.2, 3.4, abs(world_xz.y - 23.75) + edge_noise)) * step(12.0, world_xz.y));
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
	scrub *= 1.0 - smoothstep(12.0, 15.0, world_xz.y);   // city ground is swept earth
	scrub *= 1.0 - (1.0 - smoothstep(6.0, 9.0, abs(world_xz.y))) * (1.0 - smoothstep(24.0, 28.0, abs(world_xz.x)));
	vec3 scrub_col = mix(col_scrub, col_scrub_lit, smoothstep(0.35, 0.75, detail));
	col = mix(col, scrub_col, scrub * 0.45);

	// Red-ochre earth breaking through in soft, irregular patches.
	float ochre = smoothstep(0.58, 0.74, fbm(p * 1.9 + vec2(21.7, 3.3))) * (1.0 - trodden * 0.6);
	col = mix(col, col_ochre, ochre * 0.4);

	// Meadows: green ground where the grass colonies grow, darker at the heart
	float mm = meadow_mask(world_xz) + (detail - 0.5) * 0.3;
	float meadow = smoothstep(0.5, 0.72, mm) * (1.0 - trodden) * (1.0 - work_area(world_xz))
		* (1.0 - smoothstep(12.0, 15.0, world_xz.y));
	vec3 meadow_col = mix(col_meadow, col_meadow_dk, smoothstep(0.8, 1.1, mm));
	col = mix(col, meadow_col, meadow * 0.62);

	float rough_out = roughness;
	if (feature == 1) {
		// A dry wadi winding across the enemy's approach: pale water-worn gravel, banks a shade darker
		float cz = -8.5 + 2.4 * sin(world_xz.x * 0.11 + 0.7) + 1.1 * sin(world_xz.x * 0.31);
		float dd = abs(world_xz.y - cz) + (detail - 0.5) * 0.9;
		float bed = 1.0 - smoothstep(1.3, 2.3, dd);
		float bank = (1.0 - smoothstep(2.3, 3.2, dd)) - bed;
		col = mix(col, col * 0.84, bank * 0.55);
		col = mix(col, mix(vec3(0.76, 0.69, 0.57), vec3(0.60, 0.55, 0.47), micro), bed * 0.72);
	} else if (feature == 2) {
		// A ploughed plot beside the wall: furrows run along x, a haze of green in the rows
		vec2 fr = world_xz - vec2(23.0, -9.5);
		float inside = (1.0 - smoothstep(6.5, 8.0, abs(fr.x))) * (1.0 - smoothstep(3.0, 4.0, abs(fr.y) + (detail - 0.5) * 0.7));
		float rows = sin(world_xz.y * 5.4 + sin(world_xz.x * 0.3) * 0.5) * 0.5 + 0.5;
		col = mix(col, col * (0.80 + 0.28 * rows), inside * 0.9);
		col = mix(col, vec3(0.44, 0.54, 0.25), inside * smoothstep(0.55, 1.0, rows) * 0.3);
	} else if (feature == 3) {
		// Ash and soot: burned ground in drifts, darkest round the middle
		float soot = smoothstep(0.52, 0.74, fbm(p * 1.3 + vec2(3.0, 9.0)) + (mid - 0.5) * 0.3);
		soot *= (1.0 - smoothstep(18.0, 28.0, abs(world_xz.x))) * (1.0 - smoothstep(9.0, 18.0, abs(world_xz.y)));
		col = mix(col, col * vec3(0.46, 0.42, 0.40), soot * 0.72);
	} else if (feature == 4) {
		// Bare limestone breaking through the earth: pale, in tilted strata
		float rockm = smoothstep(0.56, 0.74, fbm(p * 1.6 + vec2(13.0, 5.0)) + (detail - 0.5) * 0.25) * (1.0 - trodden);
		float strata = 0.5 + 0.5 * sin((world_xz.x * 0.55 + world_xz.y * 0.95) * 2.2 + detail * 3.0);
		col = mix(col, mix(vec3(0.78, 0.74, 0.66), vec3(0.68, 0.64, 0.56), strata), rockm * 0.8);
	} else if (feature == 5) {
		// Fish market: hosed, trodden wet ground
		float damp = smoothstep(0.50, 0.70, fbm(p * 2.4 + vec2(8.0, 2.0)) + (mid - 0.5) * 0.3);
		damp *= (1.0 - smoothstep(14.0, 22.0, abs(world_xz.x))) * (1.0 - smoothstep(6.0, 11.0, abs(world_xz.y)));
		col = mix(col, col * vec3(0.72, 0.77, 0.80), damp * 0.6);
		rough_out = mix(roughness, 0.35, damp);
	} else if (feature == 6) {
		// Workshops: pale sawdust and shavings, with a dark scatter of filings
		float saw = smoothstep(0.54, 0.72, fbm(p * 2.0 + vec2(17.0, 6.0)) + (mid - 0.5) * 0.3);
		saw *= (1.0 - smoothstep(16.0, 24.0, abs(world_xz.x))) * (1.0 - smoothstep(8.0, 14.0, abs(world_xz.y)));
		col = mix(col, vec3(0.90, 0.80, 0.58), saw * 0.55);
		col *= 1.0 - saw * step(0.82, micro) * 0.25;
	} else if (feature == 7) {
		// Sheepfold: ground trampled bare and dark round the fold, straw in the dirt
		float fd = length((world_xz - vec2(-15.0, -7.2)) * vec2(1.0, 1.15)) + (detail - 0.5) * 2.0;
		float tr = 1.0 - smoothstep(4.0, 8.5, fd);
		col = mix(col, vec3(0.60, 0.46, 0.32), tr * 0.7);
		col = mix(col, vec3(0.86, 0.76, 0.46), tr * step(0.84, micro) * 0.6);
	}

	col = mix(col, section_tint, tint_amount * (0.7 + 0.6 * (mid - 0.5)));
	// Falling away outside the wall: darker and a touch cooler with distance
	float fall = smoothstep(-4.0, -30.0, world_xz.y) * outside_shade;
	col = mix(col, col * vec3(0.72, 0.74, 0.86), fall);

	// Wind ripples: faint bands bent by the noise, strongest on open sand
	float rip = sin(dot(world_xz, vec2(0.62, 0.78)) * 5.5 + mid * 9.0 + detail * 3.0);
	col *= 1.0 + rip * 0.022 * (1.0 - trodden) * (1.0 - scrub);

	// Micro grain — soft sandy texture
	col *= 0.93 + 0.07 * micro;

	// Painted grit: soft dots, a few per cell, some darker (grit, shade) some lighter
	// (sun-caught grains). Two scales so it doesn't read as a grid.
	for (int k = 0; k < 2; k++) {
		float sc = k == 0 ? 1.8 : 4.2;
		vec2 gp = world_xz * sc;
		vec2 gi = floor(gp);
		float best = 9.0;
		float bh = 0.0;
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec2 c = gi + vec2(float(x), float(y));
				float h = hash2(c + float(k) * 17.0);
				vec2 pt = c + vec2(hash2(c + 3.1), hash2(c + 7.7));
				float d = length(gp - pt);
				if (d < best) { best = d; bh = h; }
			}
		}
		// Ragged edges: grit isn't round
		best += (vnoise(gp * 3.0 + float(k) * 5.0) - 0.5) * 0.16;
		float r = k == 0 ? 0.17 : 0.2;
		float dotm = (1.0 - smoothstep(r * 0.6, r, best)) * step(0.45, bh);
		float sgn = bh > 0.82 ? 0.07 : (k == 0 ? -0.08 : -0.11);
		col *= 1.0 + dotm * sgn * (1.0 - scrub * 0.6);
	}

	// Steep ground is stone: the terrace risers read as dry-stone retaining walls (courses
	// run level, each stone its own value), the valley sides as bare limestone
	float rock = smoothstep(0.10, 0.34, slope);
	if (rock > 0.0) {
		float course = floor(world_y * 3.2);
		float stone = hash2(vec2(floor(world_xz.x * 1.1 + course * 0.37), course));
		vec3 rock_col = mix(vec3(0.74, 0.69, 0.58), vec3(0.62, 0.56, 0.46), stone);
		float joint = smoothstep(0.0, 0.07, fract(world_y * 3.2)) * smoothstep(0.0, 0.05, fract(world_xz.x * 1.1 + course * 0.37));
		rock_col *= 0.84 + 0.16 * joint;
		rock_col *= 0.9 + 0.2 * detail;
		col = mix(col, rock_col, rock);
	}

	// Cloud shadows: two slow layers of soft blobs sliding downwind, cool-tinted
	vec2 cq = (world_xz - wind_dir * TIME * cloud_speed) * 0.032;
	float cn = vnoise(cq) * 0.62 + vnoise(cq * 2.3 + vec2(7.1, 2.9) - wind_dir * TIME * 0.03) * 0.38;
	float cloud = smoothstep(0.50, 0.70, cn);
	col *= mix(vec3(1.0), vec3(0.78, 0.83, 0.95), cloud * cloud_strength * 4.0);
	col *= 1.0 - cloud * cloud_strength;

	ALBEDO    = col;
	ROUGHNESS = rough_out;
	SPECULAR  = 0.0;
}
