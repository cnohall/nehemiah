shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// Full-screen pass over the circuit diorama that turns the model into something drawn.
// look 1: tinted lithograph (ink lines from depth, crayon tone on paper, hatched shade)
// look 2: mosaic, after the Madaba map (Voronoi tesserae in a short stone palette)
// look 3: the scribe's ink plan (as 1, flatter washes, heavier line; camera goes top-down)

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform int look = 1;
uniform vec3 paper = vec3(0.93, 0.86, 0.71);
uniform vec3 ink = vec3(0.22, 0.14, 0.09);
uniform float tile = 7.0;         // mosaic: tessera size, px at 1080p

void vertex() {
	POSITION = vec4(VERTEX.xy, 0.5, 1.0);
}

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
vec2 hash2(vec2 p) {
	return vec2(hash(p), hash(p + 17.17));
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		s += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}
vec3 srgb(vec3 c) {
	return mix(1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, c * 12.92, lessThan(c, vec3(0.0031308)));
}
vec3 to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}
vec3 scr(vec2 uv) {
	return srgb(clamp(texture(screen_tex, uv).rgb, 0.0, 1.0));
}
float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

float lin_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, d) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, d);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return -v.z / v.w;
}

// 0..1 ink where depth or tone breaks (silhouettes, roof edges, wall faces)
float edge(vec2 uv, vec2 px, mat4 inv_proj, float w) {
	float d = lin_depth(uv, inv_proj);
	float dd = 0.0;
	float dl = 0.0;
	float l0 = luma(scr(uv));
	for (int k = 0; k < 4; k++) {
		vec2 o = vec2(k == 0 ? w : (k == 1 ? -w : 0.0), k == 2 ? w : (k == 3 ? -w : 0.0)) * px;
		dd += abs(lin_depth(uv + o, inv_proj) - d);
		dl += abs(luma(scr(uv + o)) - l0);
	}
	float e = smoothstep(0.012, 0.03, dd / d);
	e = max(e, smoothstep(0.10, 0.22, dl));
	return e;
}

vec3 litho(vec2 uv, vec2 frag, vec2 px, mat4 inv_proj, bool plan) {
	float res = 1080.0 * px.y;     // 1 at 1080p
	vec2 f = frag * res;           // fragment in 1080p pixels: grain the same size at any resolution
	// Wobble the lookup a touch: a hand-drawn line never sits dead on the form
	vec2 wob = (vec2(vnoise(f * 0.06), vnoise(f * 0.06 + 9.0)) - 0.5) * 2.2 * px / res;
	vec3 c = scr(uv + wob);
	float l = luma(c);
	// Tone: a few soft bands, broken by crayon grain on the stone
	float grain = fbm(f * vec2(0.9, 0.35)) * 0.6 + hash(floor(f)) * 0.4;
	float bands = plan ? 3.0 : 5.0;
	float t = clamp(l * 1.25, 0.0, 1.0);
	t = floor(t * bands + grain * 0.9) / bands;
	// Colour: a muted tint of the scene's hue laid over paper, like a hand-coloured print
	vec3 hue = c / max(l, 0.05);
	vec3 tint = mix(vec3(1.0), clamp(hue, 0.0, 1.6), plan ? 0.4 : 0.45);
	vec3 col = paper * mix(vec3(0.42, 0.32, 0.24), tint, t);
	// Hatching in the shade: diagonal strokes, cross-hatched in the deepest
	float h1 = smoothstep(0.55, 0.85, abs(fract((f.x + f.y) / 5.0) * 2.0 - 1.0));
	float h2 = smoothstep(0.55, 0.85, abs(fract((f.x - f.y) / 6.0) * 2.0 - 1.0));
	float shade = 1.0 - smoothstep(0.25, 0.5, l);
	float hatch = h1 * shade + h2 * (1.0 - smoothstep(0.12, 0.28, l));
	hatch *= 0.6 + 0.4 * vnoise(f * 0.08);
	col = mix(col, ink, clamp(hatch, 0.0, 1.0) * 0.45);
	// Ink line, broken here and there
	float e = edge(uv + wob, px, inv_proj, plan ? 1.4 : 1.0);
	e *= smoothstep(0.15, 0.45, vnoise(f * 0.11 + 3.0)) * 0.35 + 0.65;
	col = mix(col, ink, e * (plan ? 0.9 : 0.75));
	// Paper: fibres and mottling
	float fib = fbm(f * vec2(0.02, 0.05)) - 0.5;
	col *= 1.0 + fib * 0.10 + (hash(floor(f * 0.7)) - 0.5) * 0.05;
	return col;
}

// The Madaba palette: limestone, ochre, red, dark red, slate, green, gold, black
const vec3 TESS[10] = vec3[](
	vec3(0.93, 0.89, 0.80), vec3(0.83, 0.74, 0.60), vec3(0.76, 0.58, 0.38), vec3(0.62, 0.30, 0.20),
	vec3(0.42, 0.20, 0.16), vec3(0.47, 0.50, 0.52), vec3(0.42, 0.48, 0.30), vec3(0.84, 0.66, 0.30),
	vec3(0.17, 0.14, 0.12), vec3(0.65, 0.63, 0.60));

vec3 mosaic(vec2 uv, vec2 frag, vec2 px, mat4 inv_proj) {
	float res = 1080.0 * px.y;
	vec2 f = frag * res;
	vec2 g = f / tile;
	vec2 cell = floor(g);
	float d1 = 9.0;
	float d2 = 9.0;
	vec2 best = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = cell + vec2(float(x), float(y));
			// Rows of tesserae that follow the grid, jittered so no two sit square
			vec2 p = c + 0.5 + (hash2(c) - 0.5) * 0.55;
			float d = length(g - p);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				best = p;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	vec2 cuv = best * tile * px / res;
	// The stone takes the cell's average, so a tile reads one colour, not one pixel's
	vec2 sp = tile * 0.3 * px / res;
	vec3 c = (scr(cuv) * 2.0 + scr(cuv + sp) + scr(cuv - sp) + scr(cuv + vec2(sp.x, -sp.y)) + scr(cuv + vec2(-sp.x, sp.y))) / 6.0;
	float e = edge(cuv, px, inv_proj, 1.5);
	// Nearest stone in the palette, after a nudge so neighbouring tiles vary
	c = pow(c, vec3(0.75)) * (0.92 + 0.16 * hash(best + 3.1));
	vec3 pick = TESS[0];
	float bd = 99.0;
	for (int k = 0; k < 10; k++) {
		if (k == 8) {
			continue;     // black is kept for outlines
		}
		vec3 dv = c - TESS[k];
		float d = dot(dv, dv * vec3(1.0, 1.3, 0.8));
		if (d < bd) {
			bd = d;
			pick = TESS[k];
		}
	}
	if (e > 0.5) {
		pick *= 0.8;      // a darker stone of the same colour along the forms' edges
	}
	// Each stone a little uneven, catching light on one side
	pick *= 0.94 + 0.10 * hash(best) + 0.05 * dot(normalize(g - best + 1e-4), vec2(-0.6, -0.8)) * d1;
	// Grout between the stones
	float grout = 1.0 - smoothstep(0.04, 0.11, d2 - d1);
	return mix(pick, vec3(0.55, 0.50, 0.43), grout * 0.85);
}

void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;
	vec2 frag = FRAGCOORD.xy;
	vec3 col;
	if (look == 2) {
		col = mosaic(SCREEN_UV, frag, px, INV_PROJECTION_MATRIX);
	} else {
		col = litho(SCREEN_UV, frag, px, INV_PROJECTION_MATRIX, look == 3);
	}
	ALBEDO = to_linear(clamp(col, 0.0, 1.0));
}

