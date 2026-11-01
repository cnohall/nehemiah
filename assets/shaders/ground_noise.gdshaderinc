// The ground's noise, shared by ground.gdshader (live, until the bake lands) and
// ground_bake.gdshader (GroundMesh bakes it into textures once at load)

// Painted grit tiles every GRIT_CELLS cells so it can be baked into one repeating texture
const float GRIT_CELLS = 48.0;

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

// vnoise with each wave's frequency snapped so it repeats every `period`
float vnoise_tiled(vec2 p, float period) {
	vec2 q = p * TAU / period;
	float a = sin(round(period * 0.2706) * q.x + round(period * 0.1385) * q.y + sin(round(period * 0.0525) * q.y));
	float b = sin(round(period * -0.1162) * q.x + round(period * 0.2276) * q.y + 0.6 * sin(round(period * 0.0923) * q.x));
	float c = sin(round(period * 0.3676) * q.x - round(period * 0.1862) * q.y);
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

// Painted grit: soft dots, a few per cell, some darker (grit, shade) some lighter
// (sun-caught grains). `gp` in cells; k picks the layer (0 coarse, 1 fine). Returns the
// brightness change (multiply by 1 + it)
float grit(vec2 gp, int k) {
	vec2 gi = floor(gp);
	float best = 9.0;
	float bh = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = gi + vec2(float(x), float(y));
			vec2 cw = mod(c, GRIT_CELLS);
			float h = hash2(cw + float(k) * 17.0);
			vec2 pt = c + vec2(hash2(cw + 3.1), hash2(cw + 7.7));
			float d = length(gp - pt);
			if (d < best) { best = d; bh = h; }
		}
	}
	// Ragged edges: grit isn't round
	best += (vnoise_tiled(gp * 3.0 + float(k) * 5.0, GRIT_CELLS * 3.0) - 0.5) * 0.16;
	float r = k == 0 ? 0.17 : 0.2;
	float dotm = (1.0 - smoothstep(r * 0.6, r, best)) * step(0.45, bh);
	float sgn = bh > 0.82 ? 0.07 : (k == 0 ? -0.08 : -0.11);
	return dotm * sgn;
}

// The ground's static noise fields at world point `w` (p = w * scale):
//   coarse  = macro, mid, scrub, ochre
//   feature = the painted features' drifts: soot (3), limestone (4), damp (5), sawdust (6)
//   fine    = detail, micro
vec4 ground_coarse(vec2 p) {
	return vec4(fbm(p), fbm(p * 2.8 + vec2(5.1, 3.3)),
		fbm(p * 1.6 + vec2(11.3, 4.1)), fbm(p * 1.9 + vec2(21.7, 3.3)));
}

vec4 ground_feature(vec2 p) {
	return vec4(fbm(p * 1.3 + vec2(3.0, 9.0)), fbm(p * 1.6 + vec2(13.0, 5.0)),
		fbm(p * 2.4 + vec2(8.0, 2.0)), fbm(p * 2.0 + vec2(17.0, 6.0)));
}

vec2 ground_fine(vec2 p) {
	return vec2(fbm(p * 7.2 + vec2(1.9, 8.7)), vnoise(p * 18.0 + vec2(4.5, 9.3)));
}
