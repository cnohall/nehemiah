// The 1800s tinted-lithograph look of the story illustrations (after David Roberts,
// The Holy Land, 1840s): grand views, small figures; shadow laid down as crayon grain
// over pale tint washes, drawn with a sepia pen.
import { W, H, rand, smooth, poly, defs as baseDefs, ink, figure } from "./kit.mjs";

export const SEP = "#3a2718";
export const STONE = "#dcc8a2";
export const lerp = (a, b, t) => a + (b - a) * t;
const f1 = (n) => n.toFixed(1);

export function blobPts(cx, cy, rx, ry, n = 11, irr = 0.18) {
	const pts = [], off = rand(0, Math.PI * 2);
	for (let i = 0; i < n; i++) {
		const a = off + (i / n) * Math.PI * 2, k = 1 + rand(-irr, irr);
		pts.push([cx + Math.cos(a) * rx * k, cy + Math.sin(a) * ry * k]);
	}
	return pts;
}
export const rect = (x, y, w, h) => [[x, y], [x + w, y], [x + w, y + h], [x, y + h]];

// ── Marks ─────────────────────────────────────────────────────

/** Shadow as crayon grain over a soft underlay; density 0–1 */
export function tone(pts, d, { round = true } = {}) {
	if (d <= 0) return "";
	const dp = round ? smooth(pts, true) : poly(pts);
	return `<path d="${dp}" fill="${SEP}" fill-opacity="${(d * 0.28).toFixed(3)}" filter="url(#soft)"/><path d="${dp}" fill="#000" fill-opacity="${Math.min(1, d * 0.85).toFixed(2)}" filter="url(#crayon)"/>`;
}

/** Colour wash with a bleeding edge */
export function tint(pts, c, o = 0.6, round = true) {
	return `<path d="${round ? smooth(pts, true) : poly(pts)}" fill="${c}" fill-opacity="${o}" filter="url(#wash1)"/>`;
}
/** Soft-edged light or colour, no drawn edge at all */
export function haze(pts, c, o = 0.3, blur = "blur12") {
	return `<path d="${smooth(pts, true)}" fill="${c}" fill-opacity="${o}" filter="url(#${blur})"/>`;
}

export const pen = (d, w = 1.1, o = 0.85) => `<g filter="url(#inkf)">${ink(d, w, SEP, o)}</g>`;
const penPath = (d, w = 0.9, o = 0.55) => `<path d="${d}" stroke="${SEP}" stroke-width="${w}" stroke-opacity="${o}" fill="none" stroke-linecap="round" filter="url(#inkf)"/>`;

export function glowAt(cx, cy, r, c, o) {
	const id = "g" + Math.floor(rand(0, 1e9));
	return `<radialGradient id="${id}"><stop offset="0" stop-color="${c}" stop-opacity="${o}"/><stop offset="1" stop-color="${c}" stop-opacity="0"/></radialGradient><circle cx="${f1(cx)}" cy="${f1(cy)}" r="${r}" fill="url(#${id})"/>`;
}

// ── Sky ───────────────────────────────────────────────────────

export function gradSky(stops, { grain = true } = {}) {
	const id = "sk" + Math.floor(rand(0, 1e9));
	const st = stops.map(([o, c]) => `<stop offset="${o}" stop-color="${c}"/>`).join("");
	return `<linearGradient id="${id}" x1="0" y1="0" x2="0" y2="1">${st}</linearGradient><rect x="-40" y="-40" width="${W + 80}" height="${H + 80}" fill="url(#${id})"${grain ? ` filter="url(#wash3)"` : ""}/>`;
}

/**
 * Cloud banks: long soft streaks of colour, lit along the top, shade gathered in a thin
 * band of grain underneath. Each [cx, cy, rx, ry, shade, colour, light].
 */
export function clouds(list) {
	let s = "";
	for (const [cx, cy, rx, ry, d, c = "#8f98a8", lit = "#fff3dc"] of list) {
		for (let i = 0; i < 6; i++) {
			const p = blobPts(cx + rand(-rx, rx) * 0.4, cy + rand(-ry, ry) * 0.3, rx * rand(0.35, 0.65), ry * rand(0.8, 1.3), 12, 0.35);
			s += haze(p, c, 0.13, "blur12");
		}
		s += haze(blobPts(cx - rx * 0.1, cy - ry * 0.5, rx * 0.65, ry * 0.45, 12, 0.3), lit, 0.4, "blur8");
		const under = blobPts(cx + rx * 0.08, cy + ry * 0.4, rx * 0.75, ry * 0.35, 14, 0.35);
		s += haze(under, c, 0.28 + d * 0.3, "blur8") + tone(under, d * 0.25);
	}
	return s;
}

export function stars(n, maxY, seedY = 0) {
	let s = "";
	for (let i = 0; i < n; i++) {
		const r = rand() < 0.08 ? rand(1.4, 2.2) : rand(0.5, 1.1);
		s += `<circle cx="${f1(rand(0, W))}" cy="${f1(rand(seedY, maxY))}" r="${f1(r)}" fill="#f4ecd4" fill-opacity="${rand(0.4, 0.95).toFixed(2)}"/>`;
	}
	return s;
}

/** Shafts of light from (cx, cy) fanning downward */
export function rays(cx, cy, angles, len, c = "#fff2d0", o = 0.16) {
	let s = "";
	for (const a of angles) {
		const r = (a * Math.PI) / 180, w = rand(0.03, 0.06);
		const p = [[cx, cy], [cx + Math.cos(r - w) * len, cy + Math.sin(r - w) * len], [cx + Math.cos(r + w) * len, cy + Math.sin(r + w) * len]];
		s += `<path d="${poly(p)}" fill="${c}" fill-opacity="${o}" filter="url(#blur12)"/>`;
	}
	return s;
}

// ── Land ──────────────────────────────────────────────────────

export function ridgePts(x0, x1, y0, amp, step = 50) {
	const pts = [], ph = rand(0, 10);
	for (let x = x0; x <= x1 + 0.1; x += step)
		pts.push([x, y0 + Math.sin(x / 330 + ph) * amp + Math.sin(x / 110 + ph * 3) * amp * 0.3 + rand(-amp, amp) * 0.15]);
	return pts;
}

/** y on a polyline at x (flat beyond its ends) */
export function yOn(pts, x) {
	if (x <= pts[0][0]) return pts[0][1];
	for (let i = 1; i < pts.length; i++) if (x <= pts[i][0]) {
		const [a, b] = [pts[i - 1], pts[i]];
		return lerp(a[1], b[1], (x - a[0]) / (b[0] - a[0]));
	}
	return pts[pts.length - 1][1];
}

/** A band of land from its top line down to `bottom`, with a tone that deepens downward */
export function landBand(top, { tintC, tintO = 0.55, d = 0.3, d2 = null, bottom = H + 40, line = 0.5 } = {}) {
	const pts = [...top, [top[top.length - 1][0], bottom], [top[0][0], bottom]];
	let s = (tintC ? tint(pts, tintC, tintO, false) : "") + tone(pts, d, { round: false });
	if (d2 !== null) {
		// Deeper toward the bottom of the band: a second layer from partway down
		const mid = top.map(([x, y]) => [x, y + (bottom - y) * 0.45]);
		s += tone([...mid, [mid[mid.length - 1][0], bottom], [mid[0][0], bottom]], d2, { round: false });
	}
	return s + (line ? pen(smooth(top), 1, line) : "");
}

/** Short strokes modelling the ground: n strokes in [x0, x1], below yAt(x) by dy0–dy1 */
export function slopeStrokes(x0, x1, yAt, n, len, ang, o = 0.45, dy = [4, 40]) {
	let d = "";
	for (let i = 0; i < n; i++) {
		const x = rand(x0, x1), y = yAt(x) + rand(dy[0], dy[1]);
		const r = ((ang + rand(-10, 10)) * Math.PI) / 180, l = len * rand(0.5, 1.2);
		d += `M${f1(x)},${f1(y)}L${f1(x + Math.cos(r) * l)},${f1(y + Math.sin(r) * l)}`;
	}
	return penPath(d, 0.8, o);
}

export function rocks(cx, cy, spread, n, k = 1, stone = "#d2bd98") {
	let s = "";
	const list = [];
	for (let i = 0; i < n; i++) {
		const t = rand(-1, 1);
		list.push([cx + t * spread, cy - (1 - Math.abs(t)) * spread * 0.16 * rand(0.3, 1) + rand(-5, 5)]);
	}
	list.sort((a, b) => a[1] - b[1]);
	for (const [x, y] of list) {
		const r = rand(7, 16) * k, p = blobPts(x, y, r, r * 0.62, 7, 0.25);
		s += tint(p, stone, 0.95) + tone(blobPts(x + r * 0.25, y + r * 0.22, r * 0.75, r * 0.38, 6, 0.2), 0.6) + pen(smooth(p, true), 0.8, 0.55);
	}
	return s;
}

export function scrub(x, y, r, d = 0.5) {
	const p = blobPts(x, y - r * 0.4, r, r * 0.55, 9, 0.35);
	return tint(p, "#7f7a50", 0.6) + tone(p, d);
}

export function olive(x, base, h, d = 0.5) {
	let s = tone([[x - h * 0.035, base], [x + h * 0.035, base], [x + h * 0.02, base - h * 0.45], [x - h * 0.02, base - h * 0.45]], 0.75, { round: false });
	for (let i = 0; i < 3; i++) {
		const p = blobPts(x + rand(-h * 0.25, h * 0.25), base - h * rand(0.55, 0.8), h * rand(0.25, 0.35), h * rand(0.16, 0.22), 9, 0.3);
		s += tint(p, "#7f8058", 0.65) + tone(p, d + rand(-0.1, 0.1));
	}
	return s;
}

export function palmL(x, base, h) {
	const top = [x + rand(-h * 0.1, h * 0.1), base - h];
	let s = pen(smooth([[x, base], [lerp(x, top[0], 0.5) + rand(-4, 4), base - h * 0.5], top]), Math.max(1.5, h * 0.04), 0.9);
	for (let i = 0; i < 8; i++) {
		const a = -Math.PI / 2 + (i / 7 - 0.5) * Math.PI * 1.6, l = h * rand(0.3, 0.42);
		const e = [top[0] + Math.cos(a) * l, top[1] + Math.sin(a) * l * 0.5 + l * 0.3];
		s += pen(smooth([top, [(top[0] + e[0]) / 2, (top[1] + e[1]) / 2 - l * 0.15], e]), Math.max(1, h * 0.02), 0.8);
	}
	return s;
}

export function road(pts, w0, w1, c = "#e2cfa6") {
	const L = [], Rr = [];
	pts.forEach(([x, y], i) => { const w = lerp(w0, w1, i / (pts.length - 1)); L.push([x - w, y]); Rr.push([x + w, y]); });
	const p = [...L, ...Rr.reverse()];
	return tint(p, c, 0.7) + penPath(smooth(L), 0.7, 0.35);
}

export function smoke(x, y, h, lean = 0.3, c = "#8a8078") {
	let s = "";
	for (let i = 0; i < 9; i++) {
		const t = i / 8, r = lerp(10, h * 0.22, t);
		s += haze(blobPts(x + lean * h * t * t + rand(-6, 6), y - h * t, r * 1.2, r, 9, 0.3), c, lerp(0.4, 0.12, t), "blur8");
	}
	return s;
}

// ── Building ──────────────────────────────────────────────────

/**
 * A wall in perspective from (x0, y0) to (x1, y1) along its foot, h0 → h1 tall.
 * `rag(t)` 0–1 says how much of the height still stands at t (broken stretches).
 * `walk`: draw the lit top surface (a finished wall seen a little from above).
 */
export function wallP({ x0, y0, x1, y1, h0, h1, rag = () => 1, courses = 9, stone = STONE, d = 0.3, N = 480, walk = 0 }) {
	const at = (t) => [lerp(x0, x1, t), lerp(y0, y1, t)];
	const hh = (t) => lerp(h0, h1, t);
	const top = [], base = [];
	for (let i = 0; i <= N; i++) {
		const t = i / N, [x, y] = at(t);
		base.push([x, y]);
		top.push([x, y - hh(t) * Math.max(0, Math.min(1, rag(t)))]);
	}
	const face = [...base, ...top.slice().reverse()];
	let s = tint(face, stone, 0.9, false) + tone(face, d, { round: false });
	let dl = "";
	for (let k = 1; k < courses; k++) {
		const f = k / courses;
		let run = [];
		const flush = () => { if (run.length > 1) dl += smooth(run.filter((_, i) => i % 12 === 0 || i === run.length - 1).map(([x, y]) => [x + rand(-0.4, 0.4), y + rand(-0.5, 0.5)])); run = []; };
		for (let i = 0; i <= N; i++) {
			const t = i / N;
			if (rag(t) > f + 0.02) { const [x, y] = at(t); run.push([x, y - hh(t) * f]); } else flush();
		}
		flush();
		let t = rand(0, 0.02);
		const len = Math.hypot(x1 - x0, y1 - y0);
		while (t < 1) {
			const [x, y] = at(t), h = hh(t);
			if (rag(t) > f + 1 / courses) dl += `M${f1(x)},${f1(y - h * f)}L${f1(x + rand(-0.4, 0.4))},${f1(y - h * (f + 1 / courses))}`;
			t += Math.max(0.002, ((h / courses) * rand(1.4, 2.6)) / len);
		}
	}
	s += penPath(dl, 0.8, 0.5);
	if (walk) {
		const w = top.map(([x, y], i) => [x, y - walk * hh(i / N) / h0]);
		s += tint([...top, ...w.slice().reverse()], "#f0e2c0", 0.95, false) + pen(poly(w.filter((_, i) => i % 6 === 0 || i === N), false), 1, 0.6);
	}
	s += pen(poly(top.filter((_, i) => i % 2 === 0 || i === N), false), 1.2, 0.8) + pen(smooth(base.filter((_, i) => i % 40 === 0 || i === N)), 1, 0.45);
	return s;
}

/** Wall along a chain of [x, y, h] points, one face per leg, a tower at each corner */
export function wallPath(pts, { d = [0.15], towers = true, tw = 1.3, courses = 7, stone = STONE, walk = 0, towerD = 0.2 } = {}) {
	let s = "";
	for (let i = 1; i < pts.length; i++) {
		const [x0, y0, h0] = pts[i - 1], [x1, y1, h1] = pts[i];
		s += wallP({ x0, y0, x1, y1, h0, h1, courses, stone, d: d[Math.min(i - 1, d.length - 1)], walk: walk ? walk * h0 / 60 : 0, N: 200 });
	}
	if (towers)
		for (const [x, y, h] of pts.slice(1, -1)) {
			const w = h * 0.55 * tw;
			s += tower({ x: x - w / 2, base: y + 2, w, h: h * 1.45, side: w * 0.3, rise: w * 0.08, d: towerD, sideD: 0.55, stone, courses: 8 });
		}
	return s;
}

/** A square tower: front face and a receding side face, ragged when broken */
export function tower({ x, base, w, h, side = 30, rise = 8, d = 0.25, sideD = 0.55, stone = STONE, ragged = 0, courses = 10, left = false }) {
	const j = Array.from({ length: 7 }, (_, i) => rand(0, ragged) * (i % 2 ? 1 : 0.4));
	const topF = j.map((v, i) => [x + (w * i) / 6, base - h + v]);
	const front = [[x, base], [x + w, base], ...topF.slice().reverse()];
	const sx = left ? x : x + w, sd = left ? -side : side;
	const sideF = [[sx, base], [sx + sd, base - rise], [sx + sd, base - h + rise * 0.6 + j[left ? 0 : 6]], [sx, base - h + j[left ? 0 : 6]]];
	let s = tint(front, stone, 0.92, false) + tint(sideF, stone, 0.92, false);
	s += tone(front, d, { round: false }) + tone(sideF, sideD, { round: false });
	let dl = "";
	for (let k = 1; k < courses; k++) {
		const y = base - (h * k) / courses;
		if (y < base - h + ragged) continue;
		dl += `M${f1(x)},${f1(y)}L${f1(x + w)},${f1(y + rand(-0.6, 0.6))}`;
		for (let xx = x + rand(6, 16); xx < x + w - 3; xx += rand(12, 26) * Math.max(0.5, w / 120)) dl += `M${f1(xx)},${f1(y)}L${f1(xx)},${f1(y + h / courses)}`;
	}
	s += penPath(dl, 0.8, 0.45);
	s += pen(poly(front), 1.1) + pen(poly(sideF), 1, 0.65);
	return s;
}

/** Dark arched opening */
export function arch(x, base, w, h, d = 0.92) {
	const r = w / 2, pts = [[x, base], [x, base - h + r]];
	for (let i = 1; i < 12; i++) { const a = Math.PI + (i / 12) * Math.PI; pts.push([x + r + Math.cos(a) * r, base - h + r + Math.sin(a) * r]); }
	pts.push([x + w, base - h + r], [x + w, base]);
	return `<path d="${poly(pts)}" fill="#2a1c14" fill-opacity="0.5"/>` + tone(pts, d, { round: false }) + pen(poly(pts), 1.2);
}

/** A block house seen at an angle: lit front, shaded side, flat roof */
export function houseP(x, base, w, h, { side = 0.35, d = 0.1, sideD = 0.5, c = "#e6d6b4", door = true, win = true, stones = false } = {}) {
	const sw = w * side;
	const front = rect(x, base - h, w, h);
	const sideF = [[x + w, base], [x + w + sw, base - sw * 0.3], [x + w + sw, base - h - sw * 0.3], [x + w, base - h]];
	const roof = [[x, base - h], [x + w, base - h], [x + w + sw, base - h - sw * 0.3], [x + sw, base - h - sw * 0.3]];
	let s = tint(front, c, 0.92, false) + tint(sideF, c, 0.92, false) + tint(roof, "#f4e6c6", 0.8, false);
	s += tone(front, d, { round: false }) + tone(sideF, sideD, { round: false });
	if (stones) {
		// Coursed rubble, and a parapet round the roof
		let dl = "";
		for (let y = base - h / 7; y > base - h + 2; y -= h / 7) {
			dl += `M${f1(x)},${f1(y)}L${f1(x + w)},${f1(y + rand(-0.8, 0.8))}`;
			for (let xx = x + rand(4, 14); xx < x + w - 3; xx += rand(14, 26)) dl += `M${f1(xx)},${f1(y)}L${f1(xx)},${f1(y + h / 7)}`;
		}
		s += penPath(dl, 0.7, 0.35);
		const par = rect(x - 2, base - h - h * 0.06, w + 4, h * 0.06);
		s += tint(par, c, 0.95, false) + pen(poly(par), 0.7, 0.6);
	}
	if (door && w > 12) { const dw = Math.min(w * 0.2, h * 0.3), dx = x + w * rand(0.15, 0.6); s += tone(rect(dx, base - h * 0.5, dw, h * 0.5), 0.95, { round: false }); }
	if (win && w > 20 && h > 14) { const ww = Math.min(w * 0.1, h * 0.1), wx = x + w * rand(0.55, 0.8); s += tone(rect(wx, base - h * 0.8, ww, ww * 1.4), 0.9, { round: false }); }
	s += pen(poly([[x, base], [x, base - h], [x + sw, base - h - sw * 0.3], [x + w + sw, base - h - sw * 0.3], [x + w + sw, base - sw * 0.3], [x + w, base], [x, base]], false), 0.7, 0.6);
	return s;
}

/**
 * Houses packed up a hillside in terraces, between the hill's top line and a lower
 * bound (usually the wall's top). Rows are laid back to front so nearer roofs overlap.
 */
export function city({ x0, x1, topY, botY, rowH = 18, lit = (x) => 0.5, scale = (y) => 1, c = "#ecd8ae", density = 0.9 }) {
	const rows = [];
	for (let y = Math.min(...[x0, (x0 + x1) / 2, x1].map(topY)) + 10; y < Math.max(...[x0, (x0 + x1) / 2, x1].map(botY)); y += rowH * rand(0.8, 1.1)) rows.push(y);
	let s = "";
	for (const y of rows) {
		const k = scale(y);
		let x = x0 + rand(-20, 10);
		while (x < x1) {
			const w = rand(22, 44) * k, h = rand(14, 26) * k;
			const inside = y > topY(x + w / 2) + 8 && y < botY(x + w / 2);
			if (inside && rand() < 0.04) s += olive(x + w / 2, y, 34 * k, 0.55);
			else if (inside && rand() < density)
				s += houseP(x, y, w, h, { side: 0.35, d: 0.05, sideD: lerp(0.35, 0.7, lit(x)), c, door: rand() < 0.4, win: rand() < 0.4 });
			x += w * rand(0.75, 1.05);
		}
	}
	return s;
}

/**
 * Persian column: bell base, fluted shaft, and the capital of two kneeling bull foreparts
 * back to back, heads outward, a saddle between their necks where a beam rests.
 * `parts` picks what to draw, so a beam laid in the saddle can pass between the bulls:
 * { base, shaft, left, right, beamEnd } (all on by default).
 */
export function columnP(x, base, h, { d = 0.3, c = "#d6c4a0", bull = "#cbb48c", parts = {} } = {}) {
	const on = { base: true, shaft: true, left: true, right: true, beamEnd: true, ...parts };
	const w = h * 0.075;
	let s = "";
	if (on.base) {
		const plinth = rect(x - w * 1.5, base - h * 0.02, w * 3, h * 0.02);
		const bell = [[x - w * 1.25, base - h * 0.02], [x - w * 1.0, base - h * 0.05], [x - w * 0.6, base - h * 0.075], [x + w * 0.6, base - h * 0.075], [x + w * 1.0, base - h * 0.05], [x + w * 1.25, base - h * 0.02]];
		s += tint(plinth, c, 0.95, false) + tone(rect(x + w * 0.3, base - h * 0.02, w * 1.2, h * 0.02), d + 0.2, { round: false });
		s += tint(bell, c, 0.95) + tone([[x + w * 0.15, base - h * 0.075], [x + w * 0.6, base - h * 0.075], [x + w * 1.0, base - h * 0.05], [x + w * 1.25, base - h * 0.02], [x + w * 0.15, base - h * 0.02]], d + 0.15, { round: false });
		s += pen(smooth(bell), 0.8, 0.6) + pen(poly(plinth), 0.8, 0.5);
	}
	const top = base - h * 0.8;
	const colTop = top - h * 0.03;
	if (on.shaft) {
		// One shaft, its shadow side a softer band inside the outline (not a second pole)
		const shaft = rect(x - w * 0.5, top, w, base - h * 0.075 - top);
		s += tint(shaft, c, 0.95, false) + tone(rect(x + w * 0.12, top, w * 0.38, base - h * 0.075 - top), d * 0.55, { round: false });
		let fl = "";
		for (let i = -2; i <= 2; i++) fl += `M${f1(x + i * w * 0.2)},${f1(top + 2)}L${f1(x + i * w * 0.2)},${f1(base - h * 0.08)}`;
		s += penPath(fl, 0.6, 0.22) + pen(poly(shaft), 0.9, 0.6);
		const col = rect(x - w * 0.75, colTop, w * 1.5, h * 0.03);
		s += tint(col, c, 0.95, false) + tone(rect(x + w * 0.2, colTop, w * 0.55, h * 0.03), d * 0.6, { round: false }) + pen(poly(col), 0.8, 0.6);
	}
	// The bulls, in units of w from the saddle, y up from the collar
	const P = (sg, pts) => pts.map(([a, b]) => [x + sg * a * w, colTop + b * w]);
	for (const sg of [-1, 1]) {
		if (!on[sg < 0 ? "left" : "right"]) continue;
		// Head held high over the chest, so the saddle between the two is a dip the beam drops into
		const body = P(sg, [[0, -0.02], [1.0, -0.05], [1.28, -0.38], [1.34, -0.86], [1.2, -1.12], [1.02, -1.4], [0.5, -1.3], [0, -1.26]]);
		const head = P(sg, [[1.0, -1.36], [1.12, -1.78], [1.5, -1.8], [1.86, -1.48], [2.08, -1.06], [1.98, -0.86], [1.62, -0.9], [1.3, -1.06]]);
		const leg = P(sg, [[0.92, -0.36], [1.3, -0.3], [1.34, 0], [1.8, 0], [1.84, -0.2], [1.4, -0.24]]);
		const ear = P(sg, [[1.12, -1.6], [0.74, -1.74], [0.82, -1.56], [1.06, -1.48]]);
		if (sg < 0) s += tint(leg, bull, 0.97, false);
		s += tint(body, bull, 0.97, false) + tint(ear, bull, 0.97, false) + tint(head, bull, 0.97, false);
		// Shade under the chest, the leg, the jaw; the far bull darker all over
		s += tone(P(sg, [[0.05, -0.04], [1.0, -0.06], [1.28, -0.4], [0.1, -0.55]]), d * 0.8, { round: false }) + (sg < 0 ? tone(leg, d * 0.6, { round: false }) : "");
		s += tone(P(sg, [[1.3, -1.06], [1.62, -0.9], [1.98, -0.86], [2.08, -1.06], [1.7, -1.1]]), d * 0.7, { round: false });
		if (sg > 0) s += tone(body, d * 0.45, { round: false }) + tone(head, d * 0.35, { round: false });
		s += pen(poly(body, false), 0.9, 0.75) + pen(poly(head), 1, 0.85) + (sg < 0 ? pen(poly(leg), 0.8, 0.6) : "") + pen(poly(ear), 0.8, 0.6);
		// Thick horn curving forward and up, eye, nostril, and the curled collar on the chest
		const horn = P(sg, [[1.26, -1.74], [1.36, -2.06], [1.64, -2.16]]);
		s += `<path d="${smooth(horn)}" stroke="#b89a70" stroke-width="${f1(Math.max(2, w * 0.16))}" stroke-linecap="round" fill="none"/>` + pen(smooth(horn), Math.max(0.8, w * 0.02), 0.7);
		const [ex, ey] = P(sg, [[1.5, -1.46]])[0], [nx, ny] = P(sg, [[1.96, -1.04]])[0];
		s += `<circle cx="${f1(ex)}" cy="${f1(ey)}" r="${f1(Math.max(1, w * 0.05))}" fill="${SEP}"/><circle cx="${f1(nx)}" cy="${f1(ny)}" r="${f1(Math.max(0.8, w * 0.035))}" fill="${SEP}" fill-opacity="0.7"/>`;
		let curls = "";
		for (let r = 0; r < 4; r++) for (let c = 0; c < 2; c++) {
			const [cx, cy] = [1.04 + c * 0.12 + r * 0.03, -0.44 - r * 0.17];
			curls += smooth(P(sg, [[cx - 0.05, cy], [cx, cy - 0.06], [cx + 0.05, cy]]));
		}
		s += penPath(curls, 0.8, 0.5);
	}
	if (on.beamEnd) {
		// The end of a beam running into the picture, seated in the saddle
		const be = rect(x - w * 0.42, colTop - w * 2.1, w * 0.84, w * 0.8);
		s += tint(be, "#8a6a4a", 0.95, false) + tone(be, 0.35, { round: false }) + pen(poly(be), 0.8, 0.6);
	}
	return s;
}
/** Where a beam rests on columnP's capital: the saddle between the bulls' necks */
export const saddleY = (base, h) => base - h * 0.83 - h * 0.075 * 1.26;

/** Black goat-hair tent: a low roof sagging between its poles, the front open, guy ropes */
export function tentP(x, base, w, h, { d = 0.75 } = {}) {
	const poles = [0.04, 0.34, 0.66, 0.96];
	const peak = (i) => [x + w * poles[i], base - h * (i === 1 || i === 2 ? 1 : 0.86)];
	const top = [peak(0)];
	for (let i = 1; i < poles.length; i++) {
		const [a, b] = [peak(i - 1), peak(i)];
		top.push([(a[0] + b[0]) / 2, (a[1] + b[1]) / 2 + h * 0.1], b);
	}
	const val = base - h * 0.5;
	const roof = [...top, [x + w, val + h * 0.04], [x, val + h * 0.04]];
	let s = tint(roof, "#3a2e28", 0.95) + tone(roof, d);
	for (let i = 1; i < 5; i++) s += pen(`M${f1(x + w * 0.04)},${f1(lerp(val, base - h * 0.88, i / 5))}L${f1(x + w * 0.96)},${f1(lerp(val, base - h * 0.88, i / 5))}`, 0.6, 0.25);
	// The open front between the middle poles, curtains either side
	s += `<path d="${poly(rect(x + w * 0.34, val, w * 0.32, base - val))}" fill="#140c08" fill-opacity="0.6"/>` + tone(rect(x + w * 0.34, val, w * 0.32, base - val), 1, { round: false });
	for (const [a, b] of [[0.04, 0.34], [0.66, 0.96]]) s += tint(rect(x + w * a, val, w * (b - a), base - val), "#4a3a30", 0.9, false) + tone(rect(x + w * a, val, w * (b - a), base - val), d + 0.1, { round: false });
	for (const t of poles) s += pen(`M${f1(x + w * t)},${f1(base)}L${f1(x + w * t)},${f1(base - h * 0.95)}`, 1, 0.7);
	s += pen(smooth(top), 1.1, 0.85) + pen(`M${f1(x)},${f1(val + h * 0.04)}L${f1(x + w)},${f1(val + h * 0.04)}`, 0.8, 0.6);
	for (const [px, ex] of [[x + w * 0.04, x - w * 0.12], [x + w * 0.96, x + w * 1.12]]) s += pen(`M${f1(px)},${f1(base - h * 0.86)}L${f1(ex)},${f1(base + 2)}`, 0.6, 0.45);
	return s;
}

/** A body of soldiers: rows of small helmeted figures, spears and round shields */
export function army({ x0, x1, y0, y1, rows = 4, per = 20, h0 = 40, h1 = 70, d = 0.7 }) {
	let s = "", spears = "";
	for (let r = 0; r < rows; r++) {
		const t = r / Math.max(1, rows - 1), y = lerp(y0, y1, t), h = lerp(h0, h1, t);
		for (let i = 0; i < per; i++) {
			const x = lerp(x0, x1, (i + rand(0.1, 0.9)) / per) + r * h * 0.3, hy = y + rand(-2, 2);
			const body = [[x - h * 0.13, hy], [x + h * 0.13, hy], [x + h * 0.09, hy - h * 0.72], [x - h * 0.09, hy - h * 0.72]];
			s += tint(body, rand() < 0.5 ? "#6a4038" : "#4e3a32", 0.9, false) + tone(body, d, { round: false });
			s += `<circle cx="${f1(x)}" cy="${f1(hy - h * 0.82)}" r="${f1(h * 0.1)}" fill="#8a6a3a"/>` + tone(blobPts(x, hy - h * 0.84, h * 0.1, h * 0.09, 7, 0.1), 0.5);
			if (r === rows - 1 || rand() < 0.4) s += `<ellipse cx="${f1(x - h * 0.06)}" cy="${f1(hy - h * 0.45)}" rx="${f1(h * 0.12)}" ry="${f1(h * 0.17)}" fill="#6a2a22" fill-opacity="0.9"/>`;
			const lean = rand(-0.06, 0.06);
			spears += `M${f1(x + h * 0.1)},${f1(hy - h * 0.1)}L${f1(x + h * 0.1 + lean * h * 1.6)},${f1(hy - h * 1.55)}`;
		}
	}
	return s + penPath(spears, 0.9, 0.8);
}

export function fire(x, y, s) {
	return glowAt(x, y - s, s * 9, "#ffb050", 0.55)
		+ `<path d="${smooth([[x - s, y], [x - s * 0.6, y - s * 1.2], [x - s * 0.1, y - s * 1.9], [x + s * 0.1, y - s * 3], [x + s * 0.5, y - s * 1.6], [x + s, y - s * 0.7], [x + s * 0.9, y]], true)}" fill="#e8883a" filter="url(#wash2)"/>`
		+ `<path d="${smooth([[x - s * 0.5, y], [x - s * 0.3, y - s], [x + s * 0.05, y - s * 1.8], [x + s * 0.4, y - s * 0.8], [x + s * 0.4, y]], true)}" fill="#f7d27a" filter="url(#wash2)"/>`;
}

/** A pole of a scaffold */
export function pole(x, base, top, w = 4) {
	return tint(rect(x - w / 2, top, w, base - top), "#7a5a3a", 0.95, false) + pen(`M${f1(x)},${f1(base)}L${f1(x + rand(-1, 1))},${f1(top)}`, 0.8, 0.6);
}
export function plank(x0, y0, x1, y1, w = 5) {
	return tint([[x0, y0], [x1, y1], [x1, y1 + w], [x0, y0 + w]], "#8a6a44", 0.95, false) + pen(`M${f1(x0)},${f1(y0 + w)}L${f1(x1)},${f1(y1 + w)}`, 0.8, 0.7);
}

// ── People ────────────────────────────────────────────────────

export const ROBES = ["#8a5a44", "#6f6c52", "#5a6070", "#9a7a54", "#7a4a3a", "#8a8068", "#6a5040", "#7c6a5a"];
export const WRAPS = ["#e2d6bc", "#cfc2a4", "#d8cab0", "#bfae90"];

/** A figure muted to the print's palette */
export const fig = (o) => figure({ shade: 0.75, wrap: WRAPS[0], ...o });

// ── Page ──────────────────────────────────────────────────────

/** Paper, grain and the crayon filter; body is the drawing. `paper`/`mottle`: overlay strengths */
export function page(body, { paper = 0.5, mottle = 0.3 } = {}) {
	const bg = "#eee1c4";
	const extra = `<defs>
	<filter id="crayon" filterUnits="userSpaceOnUse" x="0" y="0" width="${W}" height="${H}">
		<feTurbulence type="fractalNoise" baseFrequency="1.7 1.05" numOctaves="2" seed="3" result="n"/>
		<feColorMatrix in="n" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  1 0 0 0 0" result="na"/>
		<feComposite in="SourceAlpha" in2="na" operator="arithmetic" k1="0" k2="0.9" k3="-1" k4="0.18" result="diff"/>
		<feComponentTransfer in="diff" result="th"><feFuncA type="linear" slope="2.2" intercept="0"/></feComponentTransfer>
		<feFlood flood-color="${SEP}" result="c"/>
		<feComposite in="c" in2="th" operator="in"/>
	</filter>
	<filter id="soft" x="-5%" y="-5%" width="110%" height="110%"><feGaussianBlur stdDeviation="1.2"/></filter>
	<filter id="blur8" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="8"/></filter>
	<filter id="blur12" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="14"/></filter>
	<radialGradient id="vig" cx="0.5" cy="0.45" r="0.75"><stop offset="0.6" stop-color="${SEP}" stop-opacity="0"/><stop offset="1" stop-color="${SEP}" stop-opacity="0.35"/></radialGradient>
	</defs>`;
	const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">${baseDefs()}${extra}
	<rect width="${W}" height="${H}" fill="${bg}"/>
	${body}
	<rect width="${W}" height="${H}" filter="url(#mottle)" opacity="${mottle}" style="mix-blend-mode:multiply"/>
	<rect width="${W}" height="${H}" filter="url(#paper)" opacity="${paper}" style="mix-blend-mode:multiply"/>
	<rect width="${W}" height="${H}" fill="url(#vig)"/>
	</svg>`;
	return `<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;padding:0;overflow:hidden;background:${bg}}svg{display:block}</style></head><body>${svg}</body></html>`;
}

/**
 * Broken masonry: how much stands at t, held in steps (whole courses) between knots,
 * with `gaps` [[t0, t1, height]] knocked lower.
 */
export function stepRag({ knots = 24, lo = 0.5, hi = 1, courses = 9, gaps = [] } = {}) {
	const v = Array.from({ length: knots + 1 }, () => Math.ceil(rand(lo, hi) * courses) / courses);
	return (t) => {
		for (const [a, b, h] of gaps) if (t > a && t < b) {
			const m = Math.min(t - a, b - t) / ((b - a) / 2);
			return Math.max(h, Math.ceil((h + (1 - m) * (v[Math.floor(t * knots)] - h)) * courses) / courses);
		}
		return v[Math.min(knots, Math.floor(t * knots))];
	};
}

/** The temple on its terrace: sanctuary with a tall porch and two pillars, the court wall */
export function temple(x, base, k = 1, { d = 0.05, side = 0.55 } = {}) {
	let s = tower({ x: x - 150 * k, base, w: 300 * k, h: 26 * k, side: 30 * k, rise: 6 * k, d: d + 0.03, sideD: side - 0.1, stone: "#ecd8b0", courses: 3 });
	const b = base - 24 * k;
	s += tower({ x: x - 30 * k, base: b, w: 110 * k, h: 92 * k, side: 36 * k, rise: 6 * k, d, sideD: side, stone: "#f4e2bc", courses: 7 });
	s += tower({ x: x - 66 * k, base: b, w: 38 * k, h: 116 * k, side: 0, rise: 0, d: d + 0.04, sideD: side, stone: "#f4e2bc", courses: 9 });
	s += tone(rect(x - 58 * k, b - 62 * k, 22 * k, 62 * k), 0.95, { round: false });
	for (const px of [x - 62 * k, x - 32 * k]) s += tint(rect(px - 2.5 * k, b - 70 * k, 5 * k, 70 * k), "#d8a860", 0.95, false) + pen(poly(rect(px - 2.5 * k, b - 70 * k, 5 * k, 70 * k)), 0.7, 0.7);
	s += wallP({ x0: x - 150 * k, y0: base + 3 * k, x1: x + 150 * k, y1: base + 3 * k, h0: 14 * k, h1: 14 * k, courses: 2, d: 0.1, stone: "#ecd8b0", N: 60 });
	return s;
}
