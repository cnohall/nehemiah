// Painting kit for the story illustrations: ink-and-watercolour look built from SVG.
// Seeded wobble on every line, washes with bleeding edges and granulation, paper grain.
// Each scene (scenes.mjs) builds a list of layers with these helpers; render.mjs turns
// them into 1920×1080 JPGs through headless Chrome.

export const W = 1920, H = 1080;

export const C = {
	ink: "#2a1c13", sepia: "#5b3a24", paper: "#efe2c4", cream: "#f4e9d0",
	lime: "#e6d6b2", limeShade: "#b9a47e", sand: "#d7b47a", ochre: "#c48d45",
	terracotta: "#b0573a", rust: "#8e3b25", oxblood: "#5e2320", olive: "#7a7743",
	sage: "#9c9a6a", indigo: "#34426a", teal: "#3f6b6a", violet: "#5a4b6e",
	dusk: "#2b1f26", night: "#141a2c", gold: "#e0ac4f", skin: "#b8804f",
	skinDark: "#8f5d38", white: "#f3ecdc", goat: "#3b302b", bronze: "#9a7338",
};

// ── Random ────────────────────────────────────────────────────

export function rng(seed) {
	let a = seed >>> 0;
	return () => {
		a = (a + 0x6D2B79F5) | 0;
		let t = Math.imul(a ^ (a >>> 15), 1 | a);
		t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
		return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
	};
}
let R = rng(1);
export const seed = (s) => { R = rng(s); };
export const rand = (a = 0, b = 1) => a + (b - a) * R();
export const pick = (arr) => arr[Math.floor(R() * arr.length)];
let _id = 0;
export const uid = (p = "i") => `${p}${++_id}`;

// ── Paths ─────────────────────────────────────────────────────

const f = (n) => Math.round(n * 10) / 10;

/** Catmull-Rom through the points → cubic Béziers */
export function smooth(pts, closed = false) {
	if (pts.length < 3) return "M" + pts.map((p) => `${f(p[0])},${f(p[1])}`).join("L") + (closed ? "Z" : "");
	const n = pts.length;
	const at = (i) => closed ? pts[(i + n) % n] : pts[Math.max(0, Math.min(n - 1, i))];
	let d = `M${f(pts[0][0])},${f(pts[0][1])}`;
	const last = closed ? n : n - 1;
	for (let i = 0; i < last; i++) {
		const p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2);
		const c1 = [p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6];
		const c2 = [p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6];
		d += `C${f(c1[0])},${f(c1[1])} ${f(c2[0])},${f(c2[1])} ${f(p2[0])},${f(p2[1])}`;
	}
	return d + (closed ? "Z" : "");
}
export const poly = (pts, closed = true) => "M" + pts.map((p) => `${f(p[0])},${f(p[1])}`).join("L") + (closed ? "Z" : "");

export const jitter = (pts, a) => pts.map(([x, y]) => [x + rand(-a, a), y + rand(-a, a)]);

/** Points along a segment, nudged sideways — a hand-drawn straight line */
export function line(x1, y1, x2, y2, n = 4, a = 1.5) {
	const pts = [];
	for (let i = 0; i <= n; i++) {
		const t = i / n;
		const e = i === 0 || i === n ? a * 0.4 : a;
		pts.push([x1 + (x2 - x1) * t + rand(-e, e), y1 + (y2 - y1) * t + rand(-e, e)]);
	}
	return pts;
}

/** Irregular closed blob */
export function blob(cx, cy, rx, ry, n = 11, irr = 0.18) {
	const pts = [];
	const off = rand(0, Math.PI * 2);
	for (let i = 0; i < n; i++) {
		const a = off + (i / n) * Math.PI * 2;
		const k = 1 + rand(-irr, irr);
		pts.push([cx + Math.cos(a) * rx * k, cy + Math.sin(a) * ry * k]);
	}
	return smooth(pts, true);
}

/** A block with slightly crooked sides (a stone, a house) */
export function slab(x, y, w, h, a = 1.5) {
	return poly([
		[x + rand(-a, a), y + rand(-a, a)], [x + w * 0.5, y + rand(-a, a) * 0.6], [x + w + rand(-a, a), y + rand(-a, a)],
		[x + w + rand(-a, a), y + h + rand(-a, a)], [x + rand(-a, a), y + h + rand(-a, a)],
	]);
}

// ── Marks ─────────────────────────────────────────────────────

export const fill = (d, c, o = 1, extra = "") => `<path d="${d}" fill="${c}"${o < 1 ? ` fill-opacity="${o}"` : ""} ${extra}/>`;

/** Ink stroke: a main line and, now and then, a faint second pass beside it */
export function ink(d, w = 2.2, c = C.ink, o = 0.9) {
	let s = `<path d="${d}" fill="none" stroke="${c}" stroke-width="${f(w)}" stroke-opacity="${o}" stroke-linecap="round" stroke-linejoin="round"/>`;
	if (R() < 0.45)
		s += `<path d="${d}" transform="translate(${f(rand(-1.2, 1.2))},${f(rand(-1.2, 1.2))})" fill="none" stroke="${c}" stroke-width="${f(w * 0.45)}" stroke-opacity="${o * 0.45}" stroke-linecap="round"/>`;
	return s;
}

/** Hatching inside a clip path: short parallel strokes */
export function hatch(clipD, bx, by, bw, bh, { angle = -55, gap = 7, w = 1.1, c = C.ink, o = 0.45, jit = 1.5 } = {}) {
	const id = uid("h");
	const r = (angle * Math.PI) / 180;
	const dx = Math.cos(r), dy = Math.sin(r);
	const len = Math.hypot(bw, bh);
	const cx = bx + bw / 2, cy = by + bh / 2;
	let d = "";
	for (let t = -len / 2; t < len / 2; t += gap + rand(-gap * 0.25, gap * 0.25)) {
		const ox = cx - dy * t, oy = cy + dx * t;
		const l = len * rand(0.45, 0.6);
		d += `M${f(ox - dx * l + rand(-jit, jit))},${f(oy - dy * l)}L${f(ox + dx * l)},${f(oy + dy * l + rand(-jit, jit))}`;
	}
	return `<clipPath id="${id}"><path d="${clipD}"/></clipPath><g clip-path="url(#${id})"><path d="${d}" stroke="${c}" stroke-width="${w}" stroke-opacity="${o}" stroke-linecap="round" fill="none"/></g>`;
}

export const g = (inner, attrs = "") => `<g ${attrs}>${inner}</g>`;
export const wash = (inner, n = 1, o = 1) => `<g filter="url(#wash${n})"${o < 1 ? ` opacity="${o}"` : ""}>${inner}</g>`;
export const inked = (inner) => `<g filter="url(#inkf)">${inner}</g>`;

// ── Sky and land ──────────────────────────────────────────────

/** Graded sky wash with a few blooms of darker and lighter pigment */
export function sky(stops, { blooms = 7, dark = C.violet, light = C.cream } = {}) {
	const id = uid("sky");
	const st = stops.map(([o, c]) => `<stop offset="${o}" stop-color="${c}"/>`).join("");
	let s = `<linearGradient id="${id}" x1="0" y1="0" x2="0" y2="1">${st}</linearGradient>`;
	s += `<rect x="-60" y="-60" width="${W + 120}" height="${H + 120}" fill="url(#${id})"/>`;
	let b = "";
	for (let i = 0; i < blooms; i++) {
		const d = R() < 0.5;
		b += fill(blob(rand(0, W), rand(0, H * 0.55), rand(160, 420), rand(50, 140), 9, 0.3), d ? dark : light, rand(0.08, 0.18));
	}
	return s + wash(b, 3);
}

export function glow(cx, cy, r, c, o = 0.7) {
	const id = uid("gl");
	return `<radialGradient id="${id}"><stop offset="0" stop-color="${c}" stop-opacity="${o}"/><stop offset="1" stop-color="${c}" stop-opacity="0"/></radialGradient><circle cx="${cx}" cy="${cy}" r="${r}" fill="url(#${id})"/>`;
}

export function stars(n, maxY = H * 0.5, c = C.cream) {
	let s = "";
	for (let i = 0; i < n; i++) {
		const r = R() < 0.1 ? rand(1.8, 2.6) : rand(0.6, 1.4);
		s += `<circle cx="${f(rand(0, W))}" cy="${f(rand(0, maxY))}" r="${f(r)}" fill="${c}" fill-opacity="${f(rand(0.35, 0.9))}"/>`;
	}
	return s;
}

/** A ridge of land from y0 down to the bottom of the frame */
export function ridge(y0, amp, c, { x0 = -60, x1 = W + 60, step = 60, bottom = H + 60, rough = 0.5 } = {}) {
	const pts = [];
	let y = y0;
	const ph = rand(0, 10);
	for (let x = x0; x <= x1; x += step) {
		y = y0 + Math.sin(x / 380 + ph) * amp + Math.sin(x / 150 + ph * 2) * amp * 0.35 + rand(-amp, amp) * rough * 0.4;
		pts.push([x, y]);
	}
	const top = smooth(pts);
	return { d: `${top}L${x1},${bottom}L${x0},${bottom}Z`, top, pts, fill: c };
}

export function land(r, n = 2) {
	return wash(fill(r.d, r.fill), n) + inked(ink(r.top, 1.6, C.ink, 0.35));
}

// ── Building ──────────────────────────────────────────────────

/**
 * Courses of ashlar. `height(x)` gives how high the wall stands at x (0 = razed);
 * stones above it are left off, so a broken wall has a ragged top.
 */
export function wall(x0, x1, base, full, { course = 26, stone = C.lime, shade = C.limeShade, height = () => 1, outline = 0.6, lit = 0 } = {}) {
	let fills = "", lines = "", sh = "";
	const rows = Math.ceil(full / course);
	for (let r = 0; r < rows; r++) {
		const y = base - (r + 1) * course;
		let x = x0 + (r % 2 ? -rand(10, 30) : 0);
		while (x < x1) {
			const w = course * rand(1.4, 2.4);
			const mid = Math.min(x + w / 2, x1);
			const hgt = height(mid) * full + rand(-course * 0.6, course * 0.3);
			if ((r + 1) * course <= hgt) {
				const xa = Math.max(x, x0), xb = Math.min(x + w, x1);
				const d = slab(xa, y, xb - xa - 2, course - 2, 1.6);
				const tone = R() < 0.25 ? shade : stone;
				fills += fill(d, tone, rand(0.85, 1));
				if (R() < 0.35) sh += fill(slab(xa, y + course * 0.55, xb - xa - 2, course * 0.4, 1), C.ink, 0.1);
				if (R() < outline) lines += ink(smooth(line(xa, y + course - 2, xb - 2, y + course - 2, 3, 1)), 1.3, C.ink, 0.55);
				if (R() < outline * 0.5) lines += ink(smooth(line(xb - 2, y, xb - 2, y + course - 2, 2, 1)), 1.1, C.ink, 0.45);
			}
			x += w;
		}
	}
	let s = wash(fills, 1) + wash(sh, 2) + inked(lines);
	if (lit) s += g(fills, `opacity="${lit}" style="mix-blend-mode:screen" filter="url(#wash1)"`);
	return s;
}

export function rubble(cx, cy, spread, n, { stone = C.lime, shade = C.limeShade, burnt = 0 } = {}) {
	let fills = "", lines = "";
	for (let i = 0; i < n; i++) {
		const t = rand(-1, 1);
		const x = cx + t * spread;
		const y = cy - (1 - Math.abs(t)) * spread * 0.25 * rand(0.4, 1) + rand(-4, 4);
		const s = rand(9, 20);
		const d = blob(x, y, s, s * 0.62, 6, 0.3);
		fills += fill(d, R() < burnt ? C.goat : R() < 0.5 ? shade : stone);
		fills += fill(blob(x + s * 0.2, y + s * 0.3, s * 0.8, s * 0.3, 6, 0.2), C.ink, 0.22);
		if (R() < 0.6) lines += ink(d, 1.1, C.ink, 0.5);
	}
	return wash(fills, 2) + inked(lines);
}

/** A charred beam lying at an angle */
export function beam(x, y, len, ang, w = 9) {
	const r = (ang * Math.PI) / 180;
	const x2 = x + Math.cos(r) * len, y2 = y + Math.sin(r) * len;
	const d = smooth(line(x, y, x2, y2, 3, 1.5));
	return `<path d="${d}" stroke="${C.goat}" stroke-width="${w}" stroke-linecap="round" fill="none" filter="url(#wash2)"/>` + inked(ink(d, 1.2, C.ink, 0.6));
}

/** Flat-roofed house block; `side` draws the shaded flank */
export function house(x, base, w, h, { c = C.lime, door = true, win = 1, side = 0.3 } = {}) {
	let s = "";
	const top = base - h;
	s += fill(slab(x, top, w, h, 2), c);
	if (side) s += fill(slab(x + w - w * side, top, w * side, h, 1.5), C.ink, 0.16);
	s += fill(slab(x - 4, top - 7, w + 8, 9, 1.5), C.limeShade);
	let lines = ink(smooth(line(x, top, x, base, 3, 1.2)), 1.4) + ink(smooth(line(x + w, top, x + w, base, 3, 1.2)), 1.4) + ink(smooth(line(x - 4, top - 7, x + w + 4, top - 7, 4, 1)), 1.4, C.ink, 0.7);
	if (door) {
		const dw = w * 0.2, dx = x + w * rand(0.2, 0.5);
		s += fill(slab(dx, base - h * 0.45, dw, h * 0.45, 1), C.indigo, 0.85);
	}
	for (let i = 0; i < win; i++) s += fill(slab(x + w * rand(0.15, 0.7), top + h * rand(0.15, 0.3), w * 0.09, h * 0.1, 1), C.ink, 0.75);
	return wash(s, 1) + inked(lines);
}

export function tree(x, base, h, { c = C.olive, trunk = C.sepia } = {}) {
	const tr = smooth([[x, base], [x + rand(-4, 4), base - h * 0.35], [x + rand(-8, 8), base - h * 0.55]]);
	let s = `<path d="${tr}" stroke="${trunk}" stroke-width="${h * 0.07}" fill="none" stroke-linecap="round"/>`;
	let lines = ink(tr, 1.3, C.ink, 0.6);
	for (let i = 0; i < 4; i++) {
		const d = blob(x + rand(-h * 0.3, h * 0.3), base - h * rand(0.6, 0.9), h * rand(0.22, 0.34), h * rand(0.14, 0.2), 9, 0.3);
		s += fill(d, i % 2 ? c : C.sage, 0.85);
		if (i === 0) lines += ink(d, 1.1, C.ink, 0.4);
	}
	return wash(s, 2) + inked(lines);
}

export function palm(x, base, h) {
	const top = [x + rand(-h * 0.12, h * 0.12), base - h];
	const tr = smooth([[x, base], [x + (top[0] - x) * 0.5 + rand(-5, 5), base - h * 0.5], top]);
	let s = `<path d="${tr}" stroke="${C.sepia}" stroke-width="${h * 0.045}" fill="none"/>`;
	let lines = ink(tr, 1.2, C.ink, 0.6);
	for (let i = 0; i < 8; i++) {
		const a = -Math.PI / 2 + (i / 7 - 0.5) * Math.PI * 1.5 + rand(-0.15, 0.15);
		const l = h * rand(0.3, 0.42);
		const e = [top[0] + Math.cos(a) * l, top[1] + Math.sin(a) * l * 0.6 + l * 0.35];
		const m = [(top[0] + e[0]) / 2, (top[1] + e[1]) / 2 - l * 0.18];
		const d = smooth([top, m, e]);
		s += `<path d="${d}" stroke="${C.olive}" stroke-width="${h * 0.035}" fill="none" stroke-linecap="round"/>`;
		lines += ink(d, 0.9, C.ink, 0.5);
	}
	return wash(s, 2) + inked(lines);
}

/** Persian column: bell base, fluted shaft, double-bull capital */
export function column(x, base, h, { c = C.lime, lit = C.gold } = {}) {
	const w = h * 0.07;
	let s = "", lines = "";
	s += fill(smooth([[x - w * 1.3, base], [x - w * 1.1, base - h * 0.05], [x - w * 0.6, base - h * 0.08], [x + w * 0.6, base - h * 0.08], [x + w * 1.1, base - h * 0.05], [x + w * 1.3, base]], true), c);
	const shaft = slab(x - w * 0.5, base - h * 0.84, w, h * 0.77, 1);
	s += fill(shaft, c);
	s += fill(slab(x + w * 0.1, base - h * 0.84, w * 0.4, h * 0.77, 0.6), C.ink, 0.18);
	for (let i = -2; i <= 2; i++) lines += ink(smooth(line(x + i * w * 0.18, base - h * 0.83, x + i * w * 0.18, base - h * 0.09, 3, 0.6)), 0.8, C.ink, 0.35);
	// Capital: two kneeling bull foreparts back to back
	const cy = base - h * 0.9;
	for (const sgn of [-1, 1]) {
		const bull = blob(x + sgn * w * 1.05, cy, w * 1.2, h * 0.055, 9, 0.12);
		s += fill(bull, C.sand);
		lines += ink(bull, 1.3, C.ink, 0.75);
		lines += ink(smooth([[x + sgn * w * 1.9, cy - h * 0.02], [x + sgn * w * 2.4, cy - h * 0.05], [x + sgn * w * 2.3, cy - h * 0.075]]), 1.4); // horn
		lines += ink(smooth([[x + sgn * w * 1.6, cy + h * 0.04], [x + sgn * w * 1.7, cy + h * 0.075]]), 1.6); // foreleg
	}
	s += fill(slab(x - w * 2.4, cy - h * 0.1, w * 4.8, h * 0.035, 1), C.sepia);
	lines += ink(shaft, 1.2, C.ink, 0.55);
	return wash(s, 1) + inked(lines) + (lit ? g(fill(slab(x - w * 0.5, base - h * 0.84, w * 0.35, h * 0.77, 0.6), lit, 0.25), `filter="url(#wash1)"`) : "");
}

export function flame(x, y, s) {
	let o = glow(x, y - s * 0.4, s * 5, C.gold, 0.55);
	o += fill(smooth([[x - s * 0.7, y], [x - s * 0.5, y - s * 0.9], [x - s * 0.1, y - s * 1.3], [x + s * 0.05, y - s * 2.2], [x + s * 0.4, y - s * 1.2], [x + s * 0.7, y - s * 0.6], [x + s * 0.6, y]], true), "#e8883a", 0.95);
	o += fill(smooth([[x - s * 0.35, y], [x - s * 0.2, y - s * 0.7], [x + s * 0.05, y - s * 1.3], [x + s * 0.3, y - s * 0.6], [x + s * 0.3, y]], true), "#f7d27a", 0.95);
	return g(o, `filter="url(#wash2)"`);
}

// ── People ────────────────────────────────────────────────────

const deg = (a) => (a * Math.PI) / 180;

/**
 * A robed figure, drawn facing right (dir -1 mirrors). Local units: feet at 0, top of
 * the head at -100. Arms: [upper, fore] angles in degrees, 0 = forward, 90 = down.
 *
 * opts: x, y, h, dir, robe, mantle, wrap, skin, beard ("full"|"short"|"grey"|"none"),
 *   back [a1, a2], front [a1, a2], lean, stride, hat ("wrap"|"crown"|"helmet"|"hood"|"cap"|"veil"),
 *   items: array of (pts) => svg in local units, drawn after the front arm,
 *   behind: array of (pts) => svg drawn before the body (a spear held behind, a sword at the hip)
 *   look: head tilt in degrees (negative = up)
 *   shade: 0–1 strength of the shadow side
 */
export function figure(o) {
	const {
		x, y, h, dir = 1, robe = C.terracotta, mantle = null, wrap = C.cream, skin = C.skin,
		beard = "full", back = [80, 95], front = [75, 90], lean = 0, stride = 0.3, hat = "wrap",
		items = [], behind = [], look = 0, shade = 0.5, silhouette = false, seated = false,
	} = o;
	const k = h / 100;
	const wrap_ = silhouette ? robe : wrap;
	const sw = Math.max(0.9, Math.min(2.6, h / 110)) / k;
	const ink_ = silhouette ? robe : C.ink;
	const P = {};
	const sh = [lean * 0.6, -76], shB = [sh[0] - 3.5, -75], shF = [sh[0] + 3.5, -74.5];
	const head = [lean + 1, -89];
	P.head = head;
	const arm = (s, [a1, a2]) => {
		const e = [s[0] + Math.cos(deg(a1)) * 15, s[1] + Math.sin(deg(a1)) * 15];
		const hd = [e[0] + Math.cos(deg(a2)) * 14, e[1] + Math.sin(deg(a2)) * 14];
		return { s, e, h: hd };
	};
	const A = arm(shB, back), B = arm(shF, front);
	P.back = A.h; P.front = B.h; P.backElbow = A.e; P.frontElbow = B.e;
	P.hip = [lean * 0.25 - 1, -48]; P.foot = [stride * 10, 0];
	let s = "";

	const limb = (L, c, dark) => {
		// Sleeve tapering from the shoulder to the wrist, then the hand
		const seg = (a, b, w) => `<path d="M${f(a[0])},${f(a[1])}L${f(b[0])},${f(b[1])}" stroke="${ink_}" stroke-width="${w + sw * 1.6}" stroke-linecap="round"/>`;
		const segC = (a, b, w, col, op = 1) => `<path d="M${f(a[0])},${f(a[1])}L${f(b[0])},${f(b[1])}" stroke="${col}" stroke-opacity="${op}" stroke-width="${w}" stroke-linecap="round"/>`;
		let o2 = seg(L.s, L.e, 7) + seg(L.e, L.h, 5.2) + segC(L.s, L.e, 7, c) + segC(L.e, L.h, 5.2, c);
		if (dark) o2 += segC(L.s, L.e, 7, C.ink, 0.25 * shade + 0.1) + segC(L.e, L.h, 5.2, C.ink, 0.25 * shade + 0.1);
		const hx = L.h[0] + (L.h[0] - L.e[0]) * 0.12, hy = L.h[1] + (L.h[1] - L.e[1]) * 0.12;
		return o2 + `<ellipse cx="${f(hx)}" cy="${f(hy)}" rx="2.3" ry="2.6" fill="${silhouette ? robe : skin}" stroke="${ink_}" stroke-width="${sw * 0.7}"/>`;
	};

	if (o.shadow !== false) s += fill(blob(2, 0, 22 + stride * 6, 3.4, 8, 0.15), C.ink, silhouette ? 0 : 0.22);
	for (const fn of behind) s += fn(P);
	s += limb(A, robe, true);

	// Feet
	const fx = stride * 7;
	for (const [dx, c] of seated ? [[20, C.sepia], [24, C.sepia]] : [[-fx - 1, silhouette ? robe : C.sepia], [fx + 2, silhouette ? robe : C.sepia]])
		s += fill(blob(dx + 2, -1, 4.6, 2, 6, 0.1), c) ;

	// Robe
	const hem = 14 + stride * 5;
	const robePts = [
		[sh[0] - 8.5, -77], [sh[0] + 8, -77.5], [lean * 0.35 + 10, -52], [lean * 0.1 + hem * 0.75, -20],
		[hem + stride * 3, -1.5], [2, -0.5 + rand(-0.6, 0.6)], [-hem + 1, -1.5], [lean * 0.1 - hem * 0.72, -22], [lean * 0.35 - 10.5, -52],
	];
	// Seated: the robe falls over the lap and the knees, down the shins to the feet
	const seatPts = [
		[sh[0] - 8.5, -77], [sh[0] + 8, -77.5], [9, -55], [14, -46], [25, -44], [27, -38], [24, -18], [26, -1.5],
		[14, -1], [13, -28], [0, -33], [-11, -36], [-12, -55],
	];
	const robeD = smooth(jitter(seated ? seatPts : robePts, 0.5), true);
	s += fill(robeD, robe);
	if (!silhouette) {
		s += hatch(robeD, -22, -80, 22, 80, { gap: 3.2, w: 0.55, o: 0.35 * shade, angle: -60 });
		s += fill(smooth([[lean * 0.35 - 10.5, -52], [sh[0] - 8.5, -77], [sh[0] - 3, -60], [-6, -30], [-hem + 1, -1.5], [lean * 0.1 - hem * 0.72, -22]], true), C.ink, 0.18 * shade);
		// Folds
		for (let i = 0; i < 3; i++) {
			const fx0 = rand(-7, 6);
			s += `<path d="${smooth([[fx0 + lean * 0.3, -50], [fx0 * 1.3 + rand(-1, 1), -28], [fx0 * 1.6 + rand(-1.5, 1.5), -4]])}" stroke="${C.ink}" stroke-opacity="0.35" stroke-width="${sw * 0.7}" fill="none" stroke-linecap="round"/>`;
		}
		// Sash
		if (!seated) s += `<path d="${smooth([[lean * 0.35 - 10, -50], [lean * 0.35, -48.5], [lean * 0.35 + 9.5, -50.5]])}" stroke="${C.ink}" stroke-opacity="0.35" stroke-width="3.2" fill="none"/>`;
	}
	// Mantle over the back shoulder, down across the body
	if (mantle) {
		const md = smooth([[sh[0] - 9, -77], [sh[0] + 2, -78], [sh[0] + 6, -70], [lean * 0.3 + 2, -44], [lean * 0.1 - 6, -14], [-hem * 0.7, -8], [lean * 0.3 - 11, -40]], true);
		s += fill(md, mantle) + (silhouette ? "" : fill(md, C.ink, 0.12 * shade));
		s += `<path d="${md}" stroke="${ink_}" stroke-width="${sw}" fill="none" stroke-linejoin="round"/>`;
	}
	s += `<path d="${robeD}" stroke="${ink_}" stroke-width="${sw * 1.15}" fill="none" stroke-linejoin="round"/>`;

	// Head: neck, face, beard, headgear
	const hx = head[0], hy = head[1];
	const hg = `transform="rotate(${look} ${f(hx)} ${f(hy + 6)})"`;
	let hs = fill(slab(hx - 2.5, hy + 5, 5, 6, 0.3), silhouette ? robe : C.skinDark);
	const faceD = smooth([[hx - 6.5, hy - 1], [hx - 4, hy - 7.3], [hx + 3, hy - 7.2], [hx + 6.6, hy - 2.5], [hx + 8.3, hy + 0.4], [hx + 6.6, hy + 2], [hx + 5.2, hy + 6], [hx, hy + 7.6], [hx - 5.5, hy + 4.5]], true);
	hs += fill(faceD, silhouette ? robe : skin) + `<path d="${faceD}" stroke="${ink_}" stroke-width="${sw}" fill="none"/>`;
	if (!silhouette) hs += `<circle cx="${f(hx + 3.8)}" cy="${f(hy - 1.3)}" r="0.9" fill="${C.ink}"/>`;
	if (beard !== "none") {
		const bc = beard === "grey" ? "#cfc6b4" : silhouette ? robe : "#3a2618";
		const long = beard === "short" ? 4 : 8;
		const bd = smooth([[hx - 3.5, hy + 1], [hx + 1.5, hy + 3.2], [hx + 5.8, hy + 3.5], [hx + 5, hy + 6 + long * 0.4], [hx + 1, hy + 7 + long], [hx - 3.5, hy + 5]], true);
		hs += fill(bd, bc) + `<path d="${bd}" stroke="${ink_}" stroke-width="${sw * 0.7}" fill="none"/>`;
	}
	if (hat === "wrap" || hat === "hood" || hat === "veil") {
		const tail = hat === "veil" ? 18 : hat === "hood" ? 14 : 10;
		const wd = smooth([[hx + 3.4, hy - 3.6], [hx + 4.5, hy - 7.6], [hx - 1, hy - 10.4], [hx - 7.4, hy - 7], [hx - 8.4, hy + 2], [hx - 9.8, hy + tail * 0.6], [hx - 6.5, hy + tail], [hx - 3, hy + 3], [hx - 1, hy - 2.5]], true);
		hs += fill(wd, wrap_) + `<path d="${wd}" stroke="${ink_}" stroke-width="${sw}" fill="none"/>`;
		if (!silhouette) hs += `<path d="${smooth([[hx + 3.6, hy - 5.8], [hx - 1.5, hy - 5.2], [hx - 6.5, hy - 2]])}" stroke="${C.ink}" stroke-opacity="0.3" stroke-width="${sw * 0.8}" fill="none"/>`;
		if (hat === "hood") hs += fill(wd, C.ink, 0.25);
	} else if (hat === "crown") {
		// Persian crenellated crown
		const cd = poly([[hx - 6.5, hy - 5.5], [hx - 6.8, hy - 15], [hx - 4.5, hy - 12.5], [hx - 2.2, hy - 16], [hx, hy - 12.8], [hx + 2.2, hy - 16], [hx + 4.5, hy - 12.5], [hx + 6.6, hy - 15], [hx + 6.2, hy - 5.8]]);
		hs += fill(cd, C.gold) + `<path d="${cd}" stroke="${C.ink}" stroke-width="${sw}" fill="none"/>`;
		hs += fill(smooth([[hx - 6.6, hy - 5], [hx - 9, hy + 3], [hx - 7.5, hy + 8], [hx - 4, hy + 2]], true), "#2a1a12");
	} else if (hat === "helmet") {
		const hd = smooth([[hx + 5.8, hy - 3], [hx + 4.8, hy - 8.4], [hx - 1, hy - 12.2], [hx - 7.5, hy - 7.5], [hx - 7.5, hy + 2], [hx + 0.5, hy - 2.5]], true);
		hs += fill(hd, C.bronze) + `<path d="${hd}" stroke="${C.ink}" stroke-width="${sw}" fill="none"/>`;
	} else if (hat === "cap") {
		const cd = smooth([[hx + 4.8, hy - 4], [hx + 3.5, hy - 12], [hx - 3, hy - 13.5], [hx - 7.5, hy - 6], [hx - 7, hy - 2.5]], true);
		hs += fill(cd, wrap_) + `<path d="${cd}" stroke="${ink_}" stroke-width="${sw}" fill="none"/>`;
	}
	s += g(hs, hg);

	for (const fn of items) s += fn(P);
	s += limb(B, robe, false);

	const flip = dir < 0 ? -k : k;
	return `<g transform="translate(${f(x)},${f(y)}) scale(${f(flip * 1000) / 1000},${f(k * 1000) / 1000})" filter="url(#fig)">${s}</g>`;
}

// Items, in figure-local units. Each is (P) => svg.
const lw = 1.3;
export const I = {
	spear: (hand = "front", ang = -80, len = 115, below = 22) => (P) => {
		const [x, y] = P[hand], r = deg(ang);
		const x1 = x - Math.cos(r) * below, y1 = y - Math.sin(r) * below, x2 = x + Math.cos(r) * len, y2 = y + Math.sin(r) * len;
		const head = [[x2 + Math.cos(r) * 9, y2 + Math.sin(r) * 9], [x2 + Math.cos(r + 1.4) * 2.4, y2 + Math.sin(r + 1.4) * 2.4], [x2 - Math.cos(r + 1.4) * 2.4, y2 - Math.sin(r + 1.4) * 2.4]];
		return `<path d="M${f(x1)},${f(y1)}L${f(x2)},${f(y2)}" stroke="${C.sepia}" stroke-width="2.2" stroke-linecap="round"/><path d="M${f(x1)},${f(y1)}L${f(x2)},${f(y2)}" stroke="${C.ink}" stroke-width="0.7" stroke-opacity="0.6"/>`
			+ `<path d="${poly(head)}" fill="${C.bronze}" stroke="${C.ink}" stroke-width="0.8"/>`;
	},
	staff: (hand = "front", tilt = 4) => (P) => {
		const [x, y] = P[hand];
		return `<path d="${smooth([[x + tilt * 0.3, y - 22], [x, y], [x - tilt, 0]])}" stroke="${C.sepia}" stroke-width="2.4" fill="none" stroke-linecap="round"/>`;
	},
	sword: () => (P) => {
		const [x, y] = P.hip;
		return `<path d="M${f(x - 4)},${f(y - 1)}L${f(x - 13)},${f(y + 20)}" stroke="${C.sepia}" stroke-width="3.2" stroke-linecap="round"/><path d="M${f(x - 5)},${f(y - 3)}L${f(x - 2)},${f(y - 6)}" stroke="${C.bronze}" stroke-width="2.4"/>`;
	},
	blade: (hand = "front", ang = -40, len = 22) => (P) => {
		const [x, y] = P[hand], r = deg(ang);
		return `<path d="M${f(x)},${f(y)}L${f(x + Math.cos(r) * len)},${f(y + Math.sin(r) * len)}" stroke="#cfc7b0" stroke-width="2.4" stroke-linecap="round"/><path d="M${f(x)},${f(y)}L${f(x + Math.cos(r) * len)},${f(y + Math.sin(r) * len)}" stroke="${C.ink}" stroke-width="0.6"/>`
			+ `<path d="M${f(x - Math.sin(r) * 3)},${f(y + Math.cos(r) * 3)}L${f(x + Math.sin(r) * 3)},${f(y - Math.cos(r) * 3)}" stroke="${C.bronze}" stroke-width="2"/>`;
	},
	cup: (hand = "front") => (P) => {
		const [x, y] = P[hand];
		return `<path d="${smooth([[x - 4, y - 7], [x - 3, y - 2], [x, y - 0.5], [x + 3, y - 2], [x + 4, y - 7]], true)}" fill="${C.gold}" stroke="${C.ink}" stroke-width="0.8"/><path d="M${f(x)},${f(y)}L${f(x)},${f(y + 3.5)}M${f(x - 2.5)},${f(y + 3.5)}L${f(x + 2.5)},${f(y + 3.5)}" stroke="${C.ink}" stroke-width="1"/>`;
	},
	scroll: (hand = "front", open = false) => (P) => {
		const [x, y] = P[hand];
		if (!open) return `<rect x="${f(x - 2)}" y="${f(y - 9)}" width="4.5" height="14" rx="1.5" fill="${C.cream}" stroke="${C.ink}" stroke-width="0.8" transform="rotate(20 ${f(x)} ${f(y)})"/>`;
		return `<path d="${poly([[x - 1, y - 8], [x + 17, y - 11], [x + 18, y + 7], [x, y + 9]])}" fill="${C.cream}" stroke="${C.ink}" stroke-width="0.8"/>`
			+ [0, 1, 2, 3].map((i) => `<path d="M${f(x + 3)},${f(y - 5 + i * 3.4)}L${f(x + 14)},${f(y - 7 + i * 3.4)}" stroke="${C.ink}" stroke-width="0.6" stroke-opacity="0.5"/>`).join("");
	},
	/** A load up on the shoulder, steadied by a hand */
	load: (kind = "stone", hand = "front") => (P) => {
		const [x, y] = [P.head[0] - 16, P.head[1] - 2];
		if (kind === "basket")
			return `<path d="${smooth([[x - 12, y - 12], [x + 11, y - 13], [x + 8, y + 1], [x - 9, y + 2]], true)}" fill="${C.ochre}" stroke="${C.ink}" stroke-width="1"/><path d="M${f(x - 10)},${f(y - 7)}L${f(x + 9)},${f(y - 8)}M${f(x - 9)},${f(y - 2)}L${f(x + 8)},${f(y - 3)}" stroke="${C.ink}" stroke-width="0.6" stroke-opacity="0.5"/>`;
		return `<path d="${slab(x - 11, y - 12, 20, 13, 0.8)}" fill="${C.lime}" stroke="${C.ink}" stroke-width="1"/><path d="${slab(x - 11, y - 5, 20, 6, 0.5)}" fill="${C.ink}" fill-opacity="0.15"/>`;
	},
	/** A stone held out in both hands, being set down */
	block: (hand = "front") => (P) => {
		const [x, y] = P[hand];
		return `<path d="${slab(x - 14, y - 11, 18, 12, 0.7)}" fill="${C.lime}" stroke="${C.ink}" stroke-width="1"/><path d="${slab(x - 14, y - 5, 18, 6, 0.4)}" fill="${C.ink}" fill-opacity="0.15"/>`;
	},
	trumpet: (hand = "front") => (P) => {
		const [hx, hy] = P.head, [x, y] = P[hand];
		const m = [hx + 6, hy + 2.5], e = [x + (x - m[0]) * 0.6, y + (y - m[1]) * 0.6];
		return `<path d="M${f(m[0])},${f(m[1])}L${f(e[0])},${f(e[1])}" stroke="${C.gold}" stroke-width="1.8" stroke-linecap="round"/><path d="${blob(e[0], e[1], 2.8, 2.8, 6, 0.05)}" fill="${C.gold}" stroke="${C.ink}" stroke-width="0.6"/>`;
	},
	horn: () => (P) => {
		// Ram's horn (shofar) from the lips, sweeping forward and up to a wide bell
		const [hx, hy] = P.head;
		const c = [[hx + 7, hy + 2.5], [hx + 15, hy + 1.5], [hx + 23, hy - 3], [hx + 28, hy - 11], [hx + 29, hy - 18]];
		const wd = [0.9, 1.6, 2.4, 3.3, 4.4];
		const L = [], Rr = [];
		for (let i = 0; i < c.length; i++) {
			const a = c[Math.max(0, i - 1)], b = c[Math.min(c.length - 1, i + 1)];
			const nx = -(b[1] - a[1]), ny = b[0] - a[0], l = Math.hypot(nx, ny);
			L.push([c[i][0] + nx / l * wd[i], c[i][1] + ny / l * wd[i]]);
			Rr.push([c[i][0] - nx / l * wd[i], c[i][1] - ny / l * wd[i]]);
		}
		const d = smooth([...L, ...Rr.reverse()], true);
		return `<path d="${d}" fill="${C.cream}" stroke="${C.ink}" stroke-width="0.8"/><path d="${smooth(c)}" stroke="${C.sand}" stroke-width="1" fill="none"/>`;
	},
	lyre: (hand = "back") => (P) => {
		const [x, y] = P[hand];
		const d = smooth([[x - 7, y - 20], [x - 8, y - 8], [x - 3, y + 2], [x + 3, y + 2], [x + 8, y - 8], [x + 7, y - 20]]);
		return `<path d="${d}" stroke="${C.sepia}" stroke-width="2.2" fill="none"/><path d="M${f(x - 7)},${f(y - 18)}L${f(x + 7)},${f(y - 18)}" stroke="${C.sepia}" stroke-width="1.8"/>`
			+ [-3, -1, 1, 3].map((i) => `<path d="M${f(x + i)},${f(y - 18)}L${f(x + i * 0.8)},${f(y + 1)}" stroke="${C.cream}" stroke-width="0.4"/>`).join("");
	},
	cymbals: () => (P) => [P.front, P.back].map(([x, y]) => `<ellipse cx="${f(x)}" cy="${f(y)}" rx="5" ry="1.8" fill="${C.gold}" stroke="${C.ink}" stroke-width="0.7"/>`).join(""),
	shield: (hand = "back") => (P) => {
		const [x, y] = P[hand];
		return `<ellipse cx="${f(x + 2)}" cy="${f(y - 4)}" rx="10" ry="15" fill="${C.oxblood}" stroke="${C.ink}" stroke-width="1.2"/><circle cx="${f(x + 2)}" cy="${f(y - 4)}" r="2.2" fill="${C.bronze}"/>`;
	},
	bow: (hand = "back") => (P) => {
		const [x, y] = P[hand];
		return `<path d="${smooth([[x - 2, y - 26], [x + 7, y - 8], [x + 7, y + 8], [x - 2, y + 26]])}" stroke="${C.sepia}" stroke-width="2" fill="none"/><path d="M${f(x - 2)},${f(y - 26)}L${f(x - 2)},${f(y + 26)}" stroke="${C.cream}" stroke-width="0.5"/>`;
	},
	scepter: (hand = "front", ang = -60) => (P) => {
		const [x, y] = P[hand], r = deg(ang);
		const e = [x + Math.cos(r) * 26, y + Math.sin(r) * 26];
		return `<path d="M${f(x - Math.cos(r) * 6)},${f(y - Math.sin(r) * 6)}L${f(e[0])},${f(e[1])}" stroke="${C.gold}" stroke-width="1.8" stroke-linecap="round"/><circle cx="${f(e[0])}" cy="${f(e[1])}" r="2.4" fill="${C.gold}" stroke="${C.ink}" stroke-width="0.6"/>`;
	},
	torch: (hand = "front") => (P) => {
		const [x, y] = P[hand];
		return `<path d="M${f(x)},${f(y + 6)}L${f(x + 3)},${f(y - 14)}" stroke="${C.sepia}" stroke-width="2.4" stroke-linecap="round"/>` + flameLocal(x + 3, y - 14, 4);
	},
};

function flameLocal(x, y, s) {
	return `<path d="${smooth([[x - s * 0.6, y], [x - s * 0.4, y - s], [x, y - s * 2.1], [x + s * 0.5, y - s * 0.9], [x + s * 0.6, y]], true)}" fill="#f0a347"/>`;
}

// ── Page ──────────────────────────────────────────────────────

/** Filters shared by every scene, plus the paper grain laid over the top */
export function defs() {
	const washF = (n, freq, scale, s) => `<filter id="wash${n}" x="-10%" y="-10%" width="120%" height="120%">
		<feTurbulence type="fractalNoise" baseFrequency="${freq}" numOctaves="3" seed="${s}" result="n"/>
		<feDisplacementMap in="SourceGraphic" in2="n" scale="${scale}" xChannelSelector="R" yChannelSelector="G" result="d"/>
		<feGaussianBlur in="d" stdDeviation="2.2" result="b"/>
		<feComposite in="d" in2="b" operator="arithmetic" k1="0" k2="1.5" k3="-0.5" k4="0" result="e"/>
		<feTurbulence type="fractalNoise" baseFrequency="0.55" numOctaves="2" seed="${s + 7}" result="gr"/>
		<feColorMatrix in="gr" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 -0.9 1.25" result="ga"/>
		<feComposite in="e" in2="ga" operator="in"/>
	</filter>`;
	return `<defs>
	${washF(1, 0.022, 7, 3)}
	${washF(2, 0.03, 10, 11)}
	${washF(3, 0.006, 60, 19)}
	<filter id="inkf" x="-5%" y="-5%" width="110%" height="110%">
		<feTurbulence type="fractalNoise" baseFrequency="0.04" numOctaves="2" seed="5" result="n"/>
		<feDisplacementMap in="SourceGraphic" in2="n" scale="3.5" xChannelSelector="R" yChannelSelector="G"/>
	</filter>
	<filter id="fig" x="-30%" y="-30%" width="160%" height="160%">
		<feTurbulence type="fractalNoise" baseFrequency="0.05" numOctaves="2" seed="9" result="n"/>
		<feDisplacementMap in="SourceGraphic" in2="n" scale="2.6" xChannelSelector="R" yChannelSelector="G" result="d"/>
		<feTurbulence type="fractalNoise" baseFrequency="0.7" numOctaves="2" seed="13" result="gr"/>
		<feColorMatrix in="gr" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 -0.6 1.2" result="ga"/>
		<feComposite in="d" in2="ga" operator="in"/>
	</filter>
	<filter id="paper" x="0" y="0" width="100%" height="100%">
		<feTurbulence type="fractalNoise" baseFrequency="0.75" numOctaves="4" seed="2" result="n"/>
		<feDiffuseLighting in="n" surfaceScale="1.6" lighting-color="#fff6e6" result="l"><feDistantLight azimuth="45" elevation="58"/></feDiffuseLighting>
	</filter>
	<filter id="mottle" x="0" y="0" width="100%" height="100%">
		<feTurbulence type="fractalNoise" baseFrequency="0.0035 0.005" numOctaves="3" seed="4" result="n"/>
		<feColorMatrix type="matrix" values="0 0 0 0 0.35  0 0 0 0 0.22  0 0 0 0 0.12  0 0 0 1.4 -0.55"/>
	</filter>
	</defs>`;
}

export function page(body) {
	const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">${defs()}
	<rect width="${W}" height="${H}" fill="${C.paper}"/>
	${body}
	<rect width="${W}" height="${H}" filter="url(#mottle)" opacity="0.45" style="mix-blend-mode:multiply"/>
	<rect width="${W}" height="${H}" filter="url(#paper)" opacity="0.55" style="mix-blend-mode:multiply"/>
	</svg>`;
	return `<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;padding:0;overflow:hidden;background:${C.paper}}svg{display:block}</style></head><body>${svg}</body></html>`;
}
