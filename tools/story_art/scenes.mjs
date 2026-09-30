// The story illustrations, one per StoryData slide with `art`, as tinted lithographs
// (litho.mjs). The story player lays its text over the lower left and darkens the
// bottom, so each view keeps its subject in the upper two thirds and toward the right.
// Walls always leave the frame, end in a tower or gate, or pass behind something.
import { W, H, rand, pick, I, smooth, poly } from "./kit.mjs";
import {
	lerp, tone, tint, haze, pen, gradSky, clouds, glowAt, stars, rays, ridgePts, yOn, landBand, slopeStrokes,
	rocks, scrub, olive, road, smoke, wallP, wallPath, tower, arch, houseP, city, columnP, tentP, army,
	fire, pole, plank, fig, ROBES, WRAPS, stepRag, blobPts, rect, temple, palmL,
} from "./litho.mjs";

/** A straight wall with helpers to stand things on it */
function wallRun(o) {
	const rag = o.rag ?? (() => 1);
	const t = (x) => Math.max(0, Math.min(1, (x - o.x0) / (o.x1 - o.x0)));
	const baseAt = (x) => lerp(o.y0, o.y1, t(x));
	const topAt = (x) => baseAt(x) - lerp(o.h0, o.h1, t(x)) * rag(t(x));
	return { svg: wallP({ ...o, rag }), baseAt, topAt, hAt: (x) => lerp(o.h0, o.h1, t(x)) };
}

function crowd(n, [x0, x1], [y0, y1], [h0, h1], { toward = null, avoid = null, arms = 0.15, gear = 0 } = {}) {
	const list = [];
	for (let i = 0; i < n; i++) {
		const y = rand(y0, y1), x = rand(x0, x1);
		if (avoid && Math.abs(x - avoid[0]) < avoid[2] && Math.abs(y - avoid[1]) < avoid[2] * 0.5) continue;
		list.push([x, y]);
	}
	list.sort((a, b) => a[1] - b[1]);
	let s = "";
	for (const [x, y] of list) {
		const h = lerp(h0, h1, (y - y0) / Math.max(1, y1 - y0));
		const woman = rand() < 0.25, child = !woman && rand() < 0.08;
		const up = rand() < arms;
		const behind = [];
		if (gear && !woman && !child && rand() < gear) behind.push(rand() < 0.5 ? I.spear("front", -84, 70, 40) : I.sword());
		s += fig({ x, y, h: child ? h * 0.6 : h, dir: toward === null ? pick([-1, 1]) : x < toward ? 1 : -1, robe: pick(ROBES), wrap: woman ? pick(["#6a4a4a", "#5a4a5e", "#7a5a44"]) : pick(WRAPS),
			hat: woman ? "veil" : child ? "cap" : "wrap", beard: woman || child ? "none" : pick(["full", "short", "grey"]), look: -8,
			back: [80, 95], front: up ? [-50, -80] : [75, 90], behind });
	}
	return s;
}

function fox(x, y, k) {
	const P = (pts) => pts.map(([a, b]) => [x + a * k, y + b * k]);
	const body = P([[-40, -22], [-10, -30], [25, -30], [42, -34], [48, -46], [58, -44], [66, -38], [54, -30], [44, -22], [30, -16], [-10, -15], [-38, -14]]);
	const tail = P([[-38, -24], [-62, -30], [-86, -26], [-92, -18], [-76, -14], [-54, -14], [-38, -16]]);
	let s = tint(tail, "#b8622e", 0.95) + tint(body, "#c06a30", 0.95) + tone(P([[-30, -20], [30, -20], [40, -16], [-30, -15]]), 0.5);
	s += tint(P([[44, -40], [46, -53], [50, -44]]), "#8a4420", 1) + tint(P([[52, -42], [55, -55], [58, -43]]), "#8a4420", 1);
	s += tint(P([[-92, -18], [-86, -25], [-80, -21], [-84, -15]]), "#f0e6d0", 1);
	for (const [a, b] of [[-28, 8], [-18, -6], [22, 6], [32, -4]]) s += pen(smooth(P([[a, -17], [a + b * 0.3, -6], [a + b * 0.5, 0]])), 2.2 * k, 0.9);
	return s + pen(smooth(body, true), 1, 0.8) + pen(smooth(tail, true), 1, 0.7);
}

function donkey(x, y, k, dir = 1) {
	const P = (pts) => pts.map(([a, b]) => [x + a * k * dir, y + b * k]);
	const c = "#8a7a6a";
	let s = "";
	// Far legs first, then the body over them, then the near legs
	const leg = (a, lean) => {
		const d = smooth(P([[a, -34], [a + lean * 0.5, -16], [a + lean, -2]]));
		return `<path d="${d}" stroke="${c}" stroke-width="${f(7 * k)}" stroke-linecap="round" fill="none"/>` + tone(P([[a + lean - 3, -4], [a + lean + 3, -4], [a + lean + 3, 0], [a + lean - 3, 0]]), 0.9, { round: false }) + pen(d, 0.6, 0.5);
	};
	s += leg(-30, 3) + leg(26, -2);
	const body = P([[-44, -44], [-38, -58], [-10, -64], [22, -62], [38, -56], [44, -44], [36, -32], [0, -30], [-36, -32]]);
	const neck = P([[30, -58], [42, -78], [52, -86], [60, -80], [48, -60], [40, -46]]);
	const head = P([[48, -88], [58, -92], [74, -78], [78, -70], [70, -66], [54, -78]]);
	s += tint(neck, c, 0.97) + tint(body, c, 0.97) + tint(head, c, 0.97);
	s += tone(P([[-40, -40], [40, -40], [36, -32], [0, -30], [-36, -32]]), 0.55) + tone(P([[62, -74], [78, -70], [70, -66]]), 0.7);
	for (const e of [[50, -88, 46, -106], [55, -90, 56, -108]]) s += tint(P([[e[0] - 2, e[1]], [e[2], e[3]], [e[0] + 3, e[1]]]), "#7a6a5a", 1, false) + pen(smooth(P([[e[0] - 2, e[1]], [e[2], e[3]], [e[0] + 3, e[1]]])), 0.7, 0.7);
	s += tint(P([[-24, -64], [18, -64], [20, -42], [-24, -40]]), "#8a3a2a", 0.95, false) + pen(poly(P([[-24, -64], [18, -64], [20, -42], [-24, -40]])), 0.7, 0.6);
	s += pen(smooth(body, true), 1, 0.8) + pen(smooth(neck), 0.9, 0.7) + pen(smooth(head, true), 1, 0.8);
	s += pen(smooth(P([[-44, -48], [-52, -36], [-50, -22]])), 1.4, 0.8);
	s += leg(-22, -3) + leg(34, 2);
	s += tone(blobPts(x, y + 1, 56 * k, 4 * k, 8, 0.2), 0.5);
	return s;
}
const f = (n) => n.toFixed(1);

const shadowBand = (y0, d = 0.72, c = "#4a3830") => landBand([[-40, y0], [500, y0 + 30], [1000, y0 + 90], [1300, H + 40]], { tintC: c, tintO: 0.5, d, line: 0.4 });

export const SCENES = {
	// Neh 1:1-4 — Shushan, a winter night: Hanani and the men from Judah bring the news
	judah: {
		seed: 101,
		draw() {
			let s = gradSky([[0, "#161c30"], [0.45, "#303852"], [0.62, "#57536a"]]);
			s += stars(220, 520);
			s += glowAt(360, 170, 260, "#e8e2cc", 0.35) + tint(blobPts(360, 170, 30, 30, 12, 0.04), "#f2ead2", 0.95);
			s += clouds([[760, 150, 460, 26, 0.28, "#2a3048", "#9a98b0"], [1500, 260, 380, 22, 0.22, "#2a3048", "#8a88a0"]]);
			// The plain of Susa, the Ulai river, the lower town on its mound
			s += landBand(ridgePts(-40, W + 40, 598, 6), { tintC: "#4a4a5c", d: 0.42, line: 0.3 });
			s += haze([[-40, 640], [600, 628], [1100, 645], [W + 40, 632], [W + 40, 648], [1100, 660], [600, 642], [-40, 654]], "#9aa0b4", 0.35, "blur8");
			const mound = [[40, 600], [150, 560], [420, 548], [620, 575], [700, 600]];
			s += landBand(mound, { tintC: "#565064", d: 0.4, bottom: 610, line: 0.4 });
			s += city({ x0: 120, x1: 640, topY: (x) => yOn(mound, x), botY: () => 600, rowH: 12, scale: () => 0.5, c: "#8a8498", lit: () => 0.6 });
			for (const x of [180, 340, 520]) s += glowAt(x, 588, 16, "#ffb050", 0.5);
			for (const [x, y, h] of [[690, 626, 70], [760, 632, 58], [840, 628, 76], [930, 636, 52]]) s += palmL(x, y, h);
			// The palace terrace behind its parapet, a colonnade marching away to the right
			s += landBand([[-40, 700], [W + 40, 690]], { tintC: "#5e5260", d: 0.45, d2: 0.5, line: 0.5 });
			s += wallP({ x0: -60, y0: 712, x1: 1100, y1: 712, h0: 34, h1: 30, courses: 3, d: 0.45, stone: "#7e7488", N: 120 });
			for (let i = 0; i < 9; i++) s += pen(`M${lerp(900, 2000, i / 8)},${lerp(700, 1080, i / 8) - 5}L${lerp(700, -300, i / 8)},${lerp(700, 1080, i / 8) + 10}`, 0.6, 0.18);
			const cols = [];
			for (let i = 0; i < 7; i++) {
				const k = Math.pow(i / 6, 1.6);
				cols.push([lerp(1080, 1870, k), lerp(708, 1060, k), lerp(300, 1150, k)]);
			}
			s += pen(poly(cols.map(([x, b, h]) => [x, b - h * 0.97]), false), 5, 0.55);
			for (const [x, b, h] of cols) s += columnP(x, b, h, { d: 0.55, c: "#8e8494" });
			// A lamp on its stand, and the men round it
			s += tint(rect(1296, 640, 7, 170), "#6a5030", 0.95, false) + fire(1300, 640, 9);
			s += glowAt(1250, 700, 460, "#f0a050", 0.3);
			s += fig({ x: 910, y: 820, h: 175, dir: 1, robe: "#5e5448", mantle: "#7a6a52", wrap: "#b0a288", beard: "grey", back: [80, 95], front: [70, 70], items: [I.staff("front", 5)], shade: 0.9 });
			s += fig({ x: 1030, y: 832, h: 182, dir: 1, robe: "#6a5a48", wrap: "#b8a88a", back: [80, 95], front: [40, -20], items: [I.staff("front", 3)], shade: 0.9 });
			s += fig({ x: 820, y: 808, h: 165, dir: 1, robe: "#4e4a46", wrap: "#a89a80", back: [80, 95], front: [75, 90], shade: 0.9 });
			// Nehemiah, the king's cupbearer, bowed with grief (1:4)
			s += fig({ x: 1175, y: 840, h: 190, dir: -1, robe: "#7a3c38", mantle: "#384568", wrap: "#e6dcc4", beard: "short", lean: 4, look: 24, back: [30, -120], front: [35, -125], shade: 0.8 });
			s += shadowBand(900, 0.75, "#2a2838");
			return s;
		},
	},

	// Neh 2:1-8 — the throne hall at Shushan: Artaxerxes, the queen beside him, the cup
	request: {
		seed: 204,
		draw() {
			const vx = 960;
			let s = gradSky([[0, "#6a4a34"], [0.5, "#a07a54"], [1, "#b89468"]]);
			// Far wall of the hall, a doorway of light, hangings
			s += tint(rect(560, 150, 800, 420), "#c8a878", 0.9, false) + tone(rect(560, 150, 800, 420), 0.25, { round: false });
			s += tint(rect(900, 250, 120, 290), "#f8e4b8", 0.95, false) + glowAt(960, 400, 260, "#fff0c8", 0.5);
			for (const x of [640, 1200]) s += tint(rect(x, 190, 80, 250), "#7a2e2a", 0.9, false) + tone(rect(x + 40, 190, 40, 250), 0.5, { round: false });
			// Ceiling beams and floor lines toward the far wall
			const ceil = [[-40, -40], [W + 40, -40], [1360, 150], [560, 150]];
			s += tint(ceil, "#5a3a26", 0.9, false) + tone(ceil, 0.6, { round: false });
			for (let i = 0; i <= 12; i++) s += pen(`M${lerp(-400, 2320, i / 12)},-40L${lerp(560, 1360, i / 12)},150`, 1, 0.5);
			s += landBand([[-40, 570], [W + 40, 570]], { tintC: "#b08c62", d: 0.2, d2: 0.35, line: 0.5 });
			for (let i = 0; i <= 16; i++) s += pen(`M${lerp(560, 1360, i / 16)},570L${lerp(-900, 2820, i / 16)},${H + 40}`, 0.7, 0.3);
			for (let y = 590; y < H; y += (y - 560) * 0.28) s += pen(`M-40,${y}L${W + 40},${y}`, 0.6, 0.25);
			// Light falling from high windows on the left
			s += rays(-100, -60, [32, 38, 44, 50], 1700, "#fff0c8", 0.14);
			// Two rows of columns, the nearest running out of the frame
			for (const side of [-1, 1]) {
				for (let i = 0; i < 6; i++) {
					const k = Math.pow(i / 5, 1.8);
					s += columnP(vx + side * lerp(330, 1020, k), lerp(575, 1150, k), lerp(430, 1400, k), { d: 0.45, c: "#dcc8a0" });
				}
			}
			// The dais: king and queen enthroned, guards at the steps
			s += tower({ x: 830, base: 600, w: 250, h: 30, side: 30, rise: 6, d: 0.2, sideD: 0.6, stone: "#a88862", courses: 2 });
			s += tint(rect(935, 470, 52, 104), "#6a4424", 0.95, false) + tint(rect(930, 462, 62, 12), "#d8a850", 0.95, false) + pen(poly(rect(935, 470, 52, 104)), 1, 0.7);
			s += tint(rect(1012, 500, 38, 74), "#6a4424", 0.95, false) + pen(poly(rect(1012, 500, 38, 74)), 0.9, 0.7);
			s += fig({ x: 1025, y: 572, h: 100, dir: -1, robe: "#e2d6c0", wrap: "#6b1f2a", hat: "veil", beard: "none", seated: true, back: [70, 30], front: [60, 20], skin: "#c79466", shade: 0.5 });
			s += fig({ x: 958, y: 574, h: 110, dir: -1, robe: "#6b2238", hat: "crown", beard: "full", seated: true, back: [60, 20], front: [10, -30], items: [I.scepter("front", -40)], shade: 0.5 });
			s += fig({ x: 1110, y: 604, h: 120, dir: -1, robe: "#3d4f6e", wrap: "#d9c9a4", hat: "cap", back: [80, 95], front: [70, -40], behind: [I.spear("front", -88, 90, 60)] });
			s += fig({ x: 800, y: 604, h: 118, dir: 1, robe: "#3d4f6e", wrap: "#d9c9a4", hat: "cap", back: [80, 95], front: [70, -40], behind: [I.spear("front", -88, 90, 60)] });
			// Nehemiah, the cup in his hand, before the king
			s += fig({ x: 870, y: 690, h: 160, dir: 1, robe: "#8b4a3a", mantle: "#d8c08a", wrap: "#efe4c8", beard: "short", lean: 3, look: 8, back: [80, 95], front: [20, -30], items: [I.cup("front")] });
			return s;
		},
	},

	// Neh 2:17-18 — dawn by the burned gate: "Let us rise up and build"
	build: {
		seed: 218,
		draw() {
			let s = gradSky([[0, "#a9b6bf"], [0.45, "#e6d3b0"], [0.62, "#f4d19c"]]);
			s += glowAt(1500, 470, 520, "#fff2cc", 0.75);
			s += clouds([[380, 120, 420, 40, 0.4], [1000, 70, 480, 34, 0.35], [1560, 190, 320, 30, 0.28, "#b89888"], [700, 300, 360, 24, 0.24], [1320, 340, 260, 20, 0.18, "#d0a888"]]);
			// Mount of Olives across the Kidron
			const far = ridgePts(-40, W + 40, 470, 20);
			s += landBand(far, { tintC: "#aaa3a2", d: 0.2, line: 0.35 });
			for (let i = 0; i < 40; i++) { const x = rand(0, W); s += olive(x, yOn(far, x) + rand(14, 60), rand(10, 16), 0.55); }
			s += landBand([[-40, 600], [600, 575], [1300, 560], [W + 40, 545]], { tintC: "#8a7a70", tintO: 0.45, d: 0.45, line: 0.3 });
			// Near ground where the people gather
			const ground = [[-40, 700], [500, 672], [900, 648], [1300, 625], [W + 40, 610]];
			s += landBand(ground, { tintC: "#c9ab80", d: 0.14, d2: 0.2, line: 0.5 });
			s += slopeStrokes(900, W, (x) => yOn(ground, x), 90, 24, 172, 0.3, [10, 300]);
			// The wall beyond the gate, off along the ridge and out of the picture
			s += wallP({ x0: 1195, y0: 640, x1: W + 60, y1: 585, h0: 150, h1: 70, courses: 7, d: 0.14,
				rag: stepRag({ knots: 16, lo: 0.4, hi: 0.95, courses: 7, gaps: [[0.44, 0.58, 0.1]] }) });
			s += olive(1700, 612, 90) + olive(1790, 602, 70);
			// The gate: tower stumps and the burned-out arch
			s += tower({ x: 1000, base: 655, w: 190, h: 230, side: 34, rise: 10, ragged: 30, d: 0.22, sideD: 0.6 });
			s += arch(1045, 655, 100, 170);
			s += tone(blobPts(1095, 505, 62, 40, 9, 0.3), 0.5);
			for (const [x1, y1, x2, y2] of [[1040, 655, 1120, 520], [1070, 660, 1150, 600], [1110, 520, 1180, 660], [1150, 665, 1260, 690]]) {
				const pts = [[x1 - 5, y1], [x2 - 5, y2], [x2 + 5, y2], [x1 + 5, y1]];
				s += tint(pts, "#2a1c14", 0.9, false) + tone(pts, 0.95, { round: false }) + pen(smooth([[x1, y1], [x2, y2]]), 1.1);
			}
			// The broken wall toward us on the left, out of the frame, a breach in it
			s += wallP({ x0: -80, y0: 930, x1: 1000, y1: 655, h0: 430, h1: 200, courses: 11, d: 0.34,
				rag: stepRag({ knots: 18, lo: 0.62, hi: 1, courses: 11, gaps: [[0.38, 0.58, 0.08]] }) });
			s += rocks(560, 812, 230, 60, 0.9) + rocks(1160, 690, 150, 26, 0.5) + rocks(900, 702, 120, 20, 0.6);
			for (const [x, y] of [[1820, 700], [1880, 760], [980, 740], [1760, 830]]) s += scrub(x, y, 22);
			// Nehemiah on a fallen block, the people gathered round
			s += tower({ x: 1395, base: 712, w: 60, h: 24, side: 12, rise: 4, d: 0.15, sideD: 0.6, courses: 1 });
			s += fig({ x: 1420, y: 690, h: 96, dir: -1, robe: "#7b3b2e", mantle: "#384568", wrap: "#efe4c8", beard: "full", back: [80, 90], front: [-45, -70], look: -6 });
			s += crowd(40, [1130, 1780], [700, 800], [60, 92], { toward: 1420, avoid: [1420, 700, 70], arms: 0.15 });
			s += landBand([[-40, 900], [300, 930], [700, 1000], [900, 1080]], { tintC: "#6a5244", tintO: 0.6, d: 0.72, line: 0.6 });
			s += rocks(300, 965, 300, 30, 1.6);
			return s;
		},
	},

	// Neh 4:1-2 — Sanballat mocks the Jews before the army of Samaria
	sanballat: {
		seed: 401,
		draw() {
			let s = gradSky([[0, "#4a3848"], [0.38, "#b0685a"], [0.58, "#e8a064"], [0.68, "#f2c888"]]);
			s += glowAt(420, 520, 560, "#ffd8a0", 0.7);
			s += clouds([[520, 140, 460, 36, 0.4, "#6a4050", "#f0b080"], [1300, 90, 520, 40, 0.45, "#6a4050", "#e0a078"], [1600, 300, 300, 24, 0.3, "#8a5050"]]);
			// Far hills; on the southern skyline, Jerusalem's broken wall, very small
			const far = ridgePts(-40, W + 40, 540, 22);
			s += landBand(far, { tintC: "#a07a78", d: 0.25, line: 0.3 });
			// Jerusalem's broken wall along the far skyline, a gate-tower stump at each end
			const jx = [240, 330, 420, 510, 600];
			for (let i = 1; i < jx.length; i++)
				s += wallP({ x0: jx[i - 1], y0: yOn(far, jx[i - 1]) + 5, x1: jx[i], y1: yOn(far, jx[i]) + 5, h0: 18, h1: 18, courses: 3, d: 0.3, stone: "#b8907a", N: 90, rag: stepRag({ knots: 8, lo: 0.3, hi: 1, courses: 2 }) });
			for (const x of [jx[0], jx[jx.length - 1]]) s += tower({ x: x - 6, base: yOn(far, x) + 6, w: 14, h: 28, side: 4, rise: 1, d: 0.25, sideD: 0.55, stone: "#b8907a", courses: 3, ragged: 4 });
			// The camp: black tents on the slope
			const slope = [[-40, 650], [600, 620], [1200, 640], [W + 40, 610]];
			s += landBand(slope, { tintC: "#8a5a4a", d: 0.35, d2: 0.45, line: 0.4 });
			for (const [x, w] of [[120, 170], [330, 140], [1500, 150], [1690, 180]]) s += tentP(x, yOn(slope, x) + 30, w, w * 0.34);
			for (const x of [300, 1650]) s += smoke(x, yOn(slope, x) + 10, 160, 0.4, "#9a8078");
			// The army drawn up in ranks
			s += army({ x0: 260, x1: 1180, y0: 690, y1: 790, rows: 5, per: 24, h0: 44, h1: 70 });
			// A rock above them, Sanballat on it, his officers beside him
			const rockTop = [[1150, 980], [1190, 860], [1250, 790], [1400, 752], [1560, 760], [1680, 812], [1760, 890], [1800, 980]];
			const rockP = [...rockTop, [1800, 980], [1860, H + 40], [1100, H + 40], [1150, 980]];
			s += tint(rockP, "#7a5a4a", 0.9, false) + tone(rockP, 0.5, { round: false }) + pen(smooth(rockTop), 1.2, 0.8);
			s += slopeStrokes(1200, 1720, (x) => yOn(rockTop, x), 50, 30, 120, 0.45, [10, 120]);
			s += fig({ x: 1520, y: 768, h: 160, dir: -1, robe: "#5a3a3a", wrap: "#2a1a22", hat: "cap", beard: "short", back: [80, 95], front: [75, 90], behind: [I.spear("front", -86, 70, 30)] });
			s += fig({ x: 1600, y: 780, h: 150, dir: -1, robe: "#4a3a40", wrap: "#2a1a22", hat: "helmet", beard: "short", back: [80, 95], front: [70, -50], behind: [I.spear("front", -86, 70, 40)] });
			s += fig({ x: 1400, y: 760, h: 175, dir: -1, robe: "#6b2238", mantle: "#c79b3e", wrap: "#2a1a22", hat: "cap", beard: "full", back: [130, 20], front: [-5, 5], look: -8, behind: [I.sword()] });
			s += shadowBand(900, 0.75, "#4a2a28");
			return s;
		},
	},

	// Neh 4:3, 6 — the wall at half height; Tobiah: "if a fox climbed up it…"
	tobiah: {
		seed: 403,
		draw() {
			let s = gradSky([[0, "#5a4050"], [0.4, "#c07a5a"], [0.6, "#eeb070"], [0.7, "#f4cc90"]]);
			s += glowAt(640, 380, 520, "#ffe0a8", 0.6);
			s += clouds([[400, 110, 420, 34, 0.38, "#7a4a58", "#ffc890"], [1200, 70, 520, 36, 0.4, "#7a4a58"], [1450, 250, 320, 24, 0.25, "#9a6060"]]);
			// Inside the wall the city climbs its hill
			const hill = [[-40, 470], [300, 420], [700, 380], [1000, 400], [1400, 470], [W + 40, 520]];
			s += landBand(hill, { tintC: "#c8a07a", d: 0.18, line: 0.45 });
			const w = wallRun({ x0: -60, y0: 600, x1: W + 80, y1: 880, h0: 150, h1: 330, courses: 10, d: 0.3,
				rag: stepRag({ knots: 22, lo: 0.45, hi: 0.58, courses: 10 }) });
			s += city({ x0: -20, x1: 1900, topY: (x) => yOn(hill, x), botY: (x) => w.topAt(x) + 4, rowH: 20, scale: (y) => lerp(0.8, 1.3, (y - 400) / 300), c: "#e8cea4", lit: (x) => (x > 1000 ? 0.7 : 0.4), density: 0.8 });
			s += w.svg;
			// Scaffolds and a builder or two at the top
			for (const x of [420, 880, 1420]) s += pole(x, w.baseAt(x), w.topAt(x) - w.hAt(x) * 0.35, 5) + pole(x + 60, w.baseAt(x + 60), w.topAt(x + 60) - w.hAt(x) * 0.35, 5);
			s += fig({ x: 450, y: w.topAt(450) + 3, h: 70, dir: 1, robe: ROBES[1], back: [40, 50], front: [35, 45], items: [I.block("front")] });
			s += fig({ x: 1460, y: w.topAt(1460) + 3, h: 110, dir: -1, robe: ROBES[4], back: [60, 80], front: [20, 50] });
			// The fox trotting along the top
			s += fox(990, w.topAt(990) + 2, 1.25);
			// Ground outside, Tobiah laughing and Sanballat pointing at it
			s += landBand([[-40, 620], [800, 720], [1500, 850], [W + 40, 900]], { tintC: "#a87a58", d: 0.3, d2: 0.45, line: 0.4 });
			s += rocks(700, 740, 200, 20, 0.8) + scrub(1150, 800, 26) + scrub(300, 680, 20);
			s += fig({ x: 1700, y: 1000, h: 250, dir: -1, robe: "#6b2238", mantle: "#c79b3e", wrap: "#2a1a22", hat: "cap", beard: "full", back: [90, 100], front: [-25, -30], look: -4, behind: [I.sword()] });
			s += fig({ x: 1520, y: 990, h: 240, dir: -1, robe: "#2f4a4a", mantle: "#a07a3a", wrap: "#d8c49a", beard: "short", lean: -8, look: -26, back: [80, 20], front: [70, 10] });
			s += shadowBand(930, 0.7, "#4a3028");
			return s;
		},
	},

	// Neh 4:7-8 — night: Sanballat, Tobiah and Geshem plot round a fire before a tent
	conspiracy: {
		seed: 407,
		draw() {
			let s = gradSky([[0, "#0e1224"], [0.5, "#222840"], [0.66, "#3a3448"]]);
			s += stars(240, 500);
			s += clouds([[600, 200, 480, 22, 0.3, "#1a1e30", "#6a6a88"]]);
			// Far off on its hill, Jerusalem's wall with the watch-fires on it
			const far = ridgePts(-40, W + 40, 520, 24);
			s += landBand(far, { tintC: "#2e2e40", d: 0.5, line: 0.3 });
			const jw = wallRun({ x0: 120, y0: yOn(far, 120) + 6, x1: 820, y1: yOn(far, 820) + 6, h0: 22, h1: 22, courses: 3, d: 0.5, stone: "#5a5468", rag: stepRag({ knots: 20, lo: 0.4, hi: 0.8, courses: 3 }) });
			s += jw.svg;
			for (const x of [200, 380, 560, 740]) s += fire(x, jw.topAt(x) - 1, 3);
			// The hollow of the camp
			s += landBand([[-40, 640], [700, 660], [1300, 650], [W + 40, 630]], { tintC: "#2a2630", d: 0.6, d2: 0.7, line: 0.3 });
			s += tentP(260, 690, 220, 70, { d: 0.85 }) + tentP(1600, 680, 240, 80, { d: 0.85 });
			// The great tent, the fire, the three of them
			s += tentP(980, 760, 560, 230, { d: 0.8 });
			s += glowAt(1250, 800, 700, "#f0903a", 0.42);
			s += haze(blobPts(1250, 840, 420, 80, 12, 0.2), "#c07040", 0.35);
			s += rocks(1250, 842, 50, 9, 0.8, "#6a5a50") + fire(1250, 838, 24);
			// Long shadows thrown away from the fire
			s += haze([[1075, 862], [1110, 860], [930, 925], [880, 918]], "#140c0a", 0.5, "blur8") + haze([[1405, 864], [1440, 862], [1610, 930], [1570, 936]], "#140c0a", 0.5, "blur8");
			s += fig({ x: 1250, y: 790, h: 140, dir: 1, robe: "#2f4a4a", mantle: "#6a5a3a", wrap: "#a89a7a", beard: "short", lean: 8, look: 12, back: [70, 40], front: [45, 10], shade: 0.95 });
			s += fig({ x: 1090, y: 862, h: 170, dir: 1, robe: "#3a2a24", mantle: "#5d4a30", wrap: "#b8ab90", hat: "hood", beard: "full", back: [80, 100], front: [30, -10], shade: 0.95, behind: [I.sword()] });
			s += fig({ x: 1420, y: 866, h: 172, dir: -1, robe: "#5a1d2e", mantle: "#8a6a2e", wrap: "#2a1a22", hat: "cap", beard: "full", back: [80, 95], front: [20, 40], items: [I.scroll("front", true)], shade: 0.95 });
			s += shadowBand(930, 0.8, "#1a1820");
			return s;
		},
	},

	// Neh 4:13-14 — people set by families in the low places behind the wall
	remember: {
		seed: 414,
		draw() {
			let s = gradSky([[0, "#7a7890"], [0.4, "#d8a080"], [0.6, "#f4d4a0"]]);
			s += glowAt(1500, 470, 520, "#fff0c8", 0.65);
			s += clouds([[500, 120, 440, 34, 0.35, "#7a6a88", "#ffe0b8"], [1250, 180, 420, 28, 0.3, "#8a7890"], [1700, 80, 300, 24, 0.25, "#8a7890"]]);
			// Hills beyond the wall
			s += landBand(ridgePts(-40, W + 40, 500, 20), { tintC: "#a89a98", d: 0.2, line: 0.3 });
			// The wall at half height, right across, and the watch on it
			const w = wallRun({ x0: -60, y0: 650, x1: W + 60, y1: 615, h0: 190, h1: 160, courses: 10, d: 0.32,
				rag: stepRag({ knots: 26, lo: 0.48, hi: 0.6, courses: 10 }) });
			s += w.svg;
			for (const x of [300, 820, 1720]) s += fig({ x, y: w.topAt(x) + 3, h: 64, dir: 1, robe: pick(ROBES), look: -6, back: [80, 95], front: [70, -50], behind: [I.spear("front", -86, 70, 40)] });
			// The open ground behind it; houses at the edges
			const ground = [[-40, 650], [W + 40, 615]];
			s += landBand(ground, { tintC: "#c8a67a", d: 0.12, d2: 0.22, line: 0 });
			s += slopeStrokes(0, W, (x) => yOn(ground, x), 110, 26, 175, 0.28, [20, 380]);
			for (const [x, b, w2, h] of [[-70, 880, 200, 170], [120, 846, 120, 110], [1770, 852, 180, 150]]) s += houseP(x, b, w2, h, { side: 0.3, d: 0.16, sideD: 0.62, stones: true, c: "#dcc8a4" });
			// Nehemiah up on a terrace of rubble, speaking
			s += rocks(1310, 745, 110, 30, 1) + tower({ x: 1270, base: 740, w: 90, h: 34, side: 14, rise: 4, d: 0.15, sideD: 0.6, courses: 2 });
			s += fig({ x: 1320, y: 710, h: 130, dir: -1, robe: "#7b3b2e", mantle: "#384568", wrap: "#efe4c8", beard: "full", back: [80, 95], front: [-30, -50], look: -2 });
			// Families with swords, spears and bows
			s += crowd(46, [420, 1720], [720, 860], [80, 128], { toward: 1320, avoid: [1320, 720, 90], gear: 0.7 });
			s += shadowBand(930, 0.7, "#5a4030");
			return s;
		},
	},

	// Neh 4:16-20 — half work, half hold the spears; the horn-blower by Nehemiah
	armed: {
		seed: 418,
		draw() {
			let s = gradSky([[0, "#98aab6"], [0.45, "#e6d8b6"], [0.62, "#f0dcb0"]]);
			s += glowAt(1400, 200, 520, "#fff6d8", 0.6);
			s += clouds([[500, 100, 460, 36, 0.35], [1300, 150, 420, 30, 0.3], [1700, 300, 260, 22, 0.2]]);
			// The valley beyond
			const far = ridgePts(-40, W + 40, 480, 26);
			s += landBand(far, { tintC: "#b0a898", d: 0.2, line: 0.3 });
			for (let i = 0; i < 30; i++) { const x = rand(900, W); s += olive(x, yOn(far, x) + rand(20, 80), rand(12, 18)); }
			const ground = [[-40, 640], [900, 610], [W + 40, 600]];
			s += landBand(ground, { tintC: "#d0b284", d: 0.12, d2: 0.2, line: 0.4 });
			s += slopeStrokes(700, W, (x) => yOn(ground, x), 80, 26, 175, 0.3, [20, 360]);
			// The wall going up: from out of the frame on the left, away to the right
			const w = wallRun({ x0: -80, y0: 960, x1: W + 80, y1: 600, h0: 470, h1: 120, courses: 12, d: 0.3,
				rag: stepRag({ knots: 30, lo: 0.6, hi: 0.72, courses: 12 }) });
			s += w.svg;
			for (const x of [520, 600, 1060, 1110, 1480]) s += pole(x, w.baseAt(x), w.topAt(x) - w.hAt(x) * 0.3, lerp(7, 3, x / W));
			s += plank(510, w.topAt(520) - w.hAt(520) * 0.18, 610, w.topAt(600) - w.hAt(600) * 0.18, 6);
			// Builders on the top, a sword at the side (4:18); a guard with them
			for (const [x, o] of [
				[300, { back: [40, 50], front: [35, 45], items: [I.block("front")], behind: [I.sword()] }],
				[560, { back: [60, 80], front: [20, 50], behind: [I.sword()] }],
				[760, { back: [80, 95], front: [70, -50], behind: [I.spear("front", -86, 70, 40)], items: [I.shield("back")] }],
				[1090, { back: [40, 50], front: [35, 45], items: [I.block("front")] }],
				[1350, { back: [80, 95], front: [70, -50], behind: [I.spear("front", -86, 70, 40)] }],
			]) s += fig({ x, y: w.topAt(x) + 4, h: w.hAt(x) * 0.36, dir: pick([-1, 1]), robe: pick(ROBES), ...o });
			// Carriers along the foot of the wall, a load in one hand and a weapon in the other (4:17)
			for (const x of [980, 1180, 1330, 1560]) {
				const y = w.baseAt(x) + rand(30, 70);
				s += fig({ x, y, h: lerp(120, 70, (x - 900) / 800), dir: 1, robe: pick(ROBES), stride: 0.8, back: [-120, -150], front: [70, -60], items: [I.load(pick(["stone", "basket"]))], behind: [I.spear("front", -84, 60, 40)] });
			}
			s += rocks(1180, 870, 220, 30, 1) + rocks(700, 900, 160, 18, 1.2) + slopeStrokes(600, 1300, (x) => w.baseAt(x), 50, 30, 175, 0.3, [20, 150]);
			// Nehemiah on the rise, the man with the ram's horn beside him
			s += landBand([[1240, H + 40], [1290, 990], [1360, 930], [1460, 895], [1580, 874], [1720, 866], [W + 40, 878]], { tintC: "#a8845c", d: 0.4, line: 0.6 });
			s += scrub(1400, 930, 24, 0.6) + scrub(1860, 890, 22, 0.6);
			s += fig({ x: 1600, y: 880, h: 200, dir: -1, robe: "#7b3b2e", mantle: "#384568", wrap: "#efe4c8", beard: "full", back: [85, 95], front: [0, -35], look: -3, behind: [I.sword()] });
			s += fig({ x: 1760, y: 890, h: 190, dir: -1, robe: "#9a7a54", wrap: "#efe4c8", beard: "short", back: [25, -25], front: [5, -20], look: -14, items: [I.horn()] });
			s += shadowBand(960, 0.7, "#5a4432");
			return s;
		},
	},

	// Neh 6:2-4 — the messenger's letter; "I am doing a great work, so that I can't come down"
	ono: {
		seed: 602,
		draw() {
			let s = gradSky([[0, "#8aa2b4"], [0.42, "#e2d8b8"], [0.55, "#eee0bc"]]);
			s += clouds([[400, 110, 440, 30, 0.3], [1000, 60, 460, 32, 0.32], [1500, 170, 300, 24, 0.22]]);
			// The coastal plain toward Ono, far off in haze, villages and orchards on it
			const far = ridgePts(-40, W + 40, 470, 5);
			s += landBand(far, { tintC: "#c0bca8", d: 0.1, line: 0.25 });
			for (const x of [140, 420, 760]) s += city({ x0: x, x1: x + 70, topY: () => 462, botY: () => 482, rowH: 7, scale: () => 0.32, c: "#c8bca0" });
			for (let i = 0; i < 22; i++) s += olive(rand(0, 1000), 488 + rand(0, 40), rand(8, 13), 0.4);
			const mid = [[-40, 540], [700, 530], [W + 40, 520]];
			s += landBand(mid, { tintC: "#ccb48a", d: 0.14, line: 0.3 });
			for (let i = 0; i < 12; i++) s += olive(rand(0, 900), 560 + rand(0, 50), rand(16, 24), 0.5);
			const ground = [[-40, 640], [700, 622], [W + 40, 608]];
			s += landBand(ground, { tintC: "#d2b486", d: 0.12, d2: 0.22, line: 0.4 });
			// The road up from the plain to the wall
			s += road([[230, 530], [330, 580], [520, 650], [780, 740], [1000, 850], [1120, 905]], 4, 46);
			s += slopeStrokes(0, 1000, (x) => yOn(ground, x), 70, 26, 176, 0.28, [20, 380]);
			s += rocks(560, 760, 120, 14, 1) + scrub(300, 700, 26) + scrub(780, 690, 22);
			// The wall all but finished, coming up from the right to its corner tower
			const w = wallRun({ x0: 1130, y0: 700, x1: W + 80, y1: 1000, h0: 270, h1: 620, courses: 14, d: 0.24 });
			s += w.svg;
			s += tower({ x: 1030, base: 708, w: 130, h: 360, side: 34, rise: 8, d: 0.14, sideD: 0.52, courses: 15, left: true });
			// Scaffold at the top where the last courses go on, Nehemiah on it
			const px = 1500, top = w.topAt(px);
			s += pole(1430, w.baseAt(1430), top - 110, 6) + pole(1640, w.baseAt(1640), top - 140, 7);
			s += plank(1400, top - 4, 1680, w.topAt(1680) - 4, 8);
			s += fig({ x: px, y: top - 2, h: 170, dir: -1, robe: "#7b3b2e", mantle: "#384568", wrap: "#efe4c8", beard: "full", back: [70, 40], front: [-10, -80], look: 10, items: [I.block("back")] });
			s += fig({ x: 1610, y: w.topAt(1610) - 4, h: 160, dir: -1, robe: ROBES[1], back: [40, 50], front: [35, 45], items: [I.block("front")], behind: [I.sword()] });
			// The messenger at the foot of it, the open letter held up; his donkey behind him
			s += donkey(960, 862, 1.5, 1);
			s += fig({ x: 1150, y: 890, h: 175, dir: 1, robe: "#5a1d2e", mantle: "#c79b3e", wrap: "#2a1a22", hat: "cap", beard: "short", look: -22, back: [-30, -70], front: [-40, -60], items: [I.scroll("front", true)] });
			s += shadowBand(950, 0.65, "#5a4432");
			return s;
		},
	},

	// Neh 6:16 — the enemies look across the valley at the finished wall and lose heart
	lostheart: {
		seed: 616,
		draw() {
			let s = gradSky([[0, "#6f6a80"], [0.35, "#c8927a"], [0.55, "#f0c088"], [0.65, "#f6d8a0"]]);
			s += glowAt(360, 400, 620, "#ffe6b0", 0.8);
			s += clouds([[520, 110, 460, 36, 0.4, "#8a7088", "#ffd8a8"], [1260, 70, 520, 40, 0.42, "#7a6480"], [1640, 240, 320, 26, 0.3, "#b07a78"], [260, 270, 260, 20, 0.18, "#e0a080"]]);
			s += landBand(ridgePts(-40, W + 40, 370, 22), { tintC: "#b8a4a0", d: 0.2, line: 0.3 });
			// The city on its hill, the temple at the top
			const hill = [[-40, 520], [200, 470], [450, 390], [640, 330], [820, 318], [1020, 350], [1300, 430], [1600, 480], [W + 40, 510]];
			s += landBand(hill, { tintC: "#d2ae80", d: 0.14, line: 0.5 });
			s += haze(blobPts(1250, 470, 420, 110, 12, 0.15), "#8a6050", 0.25);
			// The whole wall, round the hill and on out of the picture at both sides
			const wl = [[-80, 612, 60], [240, 628, 64], [560, 645, 70], [860, 650, 72], [1160, 638, 68], [1460, 618, 64], [1760, 596, 58], [W + 80, 578, 52]];
			const wallTop = (x) => yOn(wl.map(([a, b, h]) => [a, b - h]), x);
			s += city({ x0: -20, x1: 1960, topY: (x) => yOn(hill, x), botY: (x) => wallTop(x) + 2, rowH: 16, scale: (y) => lerp(0.75, 1.1, (y - 320) / 320), lit: (x) => (x > 820 ? 0.8 : 0.35), density: 0.95 });
			// The temple on its terrace
			s += temple(740, 346, 0.95);
			s += smoke(640, 330, 120, 0.5, "#a09088");
			s += wallPath(wl, { d: [0.1, 0.1, 0.12, 0.3, 0.34, 0.36, 0.36], towerD: 0.12, stone: "#ecd4a4" });
			s += tint([[-40, 280], [860, 280], [860, 680], [-40, 680]], "#f4b860", 0.2, false);
			// The Hinnom valley in shadow, olive terraces
			const val = [[-40, 672], [500, 700], [1000, 708], [1500, 688], [W + 40, 660]];
			s += landBand(val, { tintC: "#6a4a48", tintO: 0.5, d: 0.52, d2: 0.62, line: 0.3 });
			for (let r = 0; r < 3; r++) for (let i = 0; i < 16; i++) { const x = rand(40, 1500); s += olive(x, yOn(val, x) + 40 + r * 36 + rand(-6, 6), 34 + r * 6, 0.6); }
			// The near ridge, the three who came to look
			const near = [[980, H + 40], [1000, 1010], [1040, 960], [1110, 912], [1200, 878], [1320, 856], [1500, 840], [1720, 832], [W + 40, 850]];
			s += landBand(near, { tintC: "#4a3030", tintO: 0.6, d: 0.72, d2: 0.8, line: 0.7 });
			s += rocks(1300, 880, 140, 14, 1.2, "#8a6a58") + rocks(1820, 870, 90, 9, 1.2, "#8a6a58") + scrub(1150, 910, 30, 0.8) + scrub(1880, 860, 26, 0.8);
			s += slopeStrokes(1080, W, (x) => yOn(near, x), 60, 34, 140, 0.4, [20, 180]);
			// Sanballat, Tobiah and Geshem: dark cloaks against the light, heads down
			const dark = { shade: 1, shadow: false, stride: 0.2 };
			s += fig({ x: 1430, y: 848, h: 200, dir: -1, robe: "#3a2428", mantle: "#4a3024", wrap: "#2a1a1e", hat: "cap", beard: "full", look: 20, back: [95, 100], front: [80, 60], items: [I.staff("front", 4)], ...dark });
			s += fig({ x: 1580, y: 842, h: 190, dir: -1, robe: "#2a3434", mantle: "#4a3a2a", wrap: "#6a5a48", beard: "short", look: 28, back: [95, 100], front: [95, 100], ...dark });
			s += fig({ x: 1712, y: 838, h: 186, dir: 1, robe: "#3a2a22", mantle: "#5a4a34", wrap: "#7a6a52", hat: "hood", beard: "full", look: 16, back: [95, 100], front: [85, 70], ...dark });
			s += landBand([[-40, 960], [400, 990], [900, 1040], [1100, H + 40]], { tintC: "#3a2828", tintO: 0.6, d: 0.78, line: 0.4 });
			return s;
		},
	},

	// Neh 12:31-43 — two choirs go round on top of the wall; the joy heard far away
	dedication: {
		seed: 1231,
		draw() {
			let s = gradSky([[0, "#98a6c0"], [0.4, "#f0cca0"], [0.6, "#f8e2b4"]]);
			s += glowAt(1500, 180, 560, "#fff6d8", 0.75) + rays(1500, 120, [120, 130, 140, 150, 160], 1500, "#fff4d8", 0.14);
			s += clouds([[420, 110, 440, 32, 0.3, "#8a90b0", "#fff0d0"], [1000, 230, 380, 24, 0.22, "#9a98b0"]]);
			// The temple on the height beyond, smoke of the sacrifices rising (12:43)
			const hill = [[-40, 470], [300, 400], [620, 360], [900, 350], [1250, 400], [W + 40, 460]];
			s += landBand(hill, { tintC: "#d8bc90", d: 0.12, line: 0.45 });
			s += temple(790, 372, 1.05);
			s += smoke(700, 350, 280, 0.6, "#a0948a");
			// Far wall across the valley, the second choir on it
			const far = wallRun({ x0: -60, y0: 520, x1: 1250, y1: 470, h0: 60, h1: 44, courses: 5, d: 0.1, stone: "#ecd8b0" });
			s += city({ x0: 0, x1: 1240, topY: (x) => yOn(hill, x), botY: (x) => far.topAt(x), rowH: 13, scale: () => 0.7, lit: () => 0.4 });
			s += far.svg;
			for (let x = 120; x < 1100; x += 34) s += fig({ x, y: far.topAt(x) + 1, h: 34, dir: 1, robe: pick(["#f2ead8", "#e4d8c0"]), wrap: "#f4ecd8", beard: "short", stride: 0.5, shade: 0.4 });
			// The near wall, finished, running from out of the frame away to a corner tower
			const ground = [[-40, 560], [W + 40, 540]];
			s += landBand(ground, { tintC: "#d6b886", d: 0.1, d2: 0.22, line: 0 });
			const w = wallRun({ x0: 1280, y0: 520, x1: W + 80, y1: 1000, h0: 110, h1: 420, courses: 12, d: 0.25, walk: 1 });
			s += w.svg;
			s += tower({ x: 1220, base: 530, w: 90, h: 160, side: 26, rise: 6, d: 0.1, sideD: 0.55, courses: 10 });
			// The first choir along its top, singers and players (12:36)
			const gear = [[I.lyre("back")], [I.cymbals()], [I.trumpet("front")], [], [I.lyre("back")], []];
			let i = 0;
			for (let x = 1340; x < 1900; x += lerp(30, 70, (x - 1340) / 560)) {
				const h = w.hAt(x) * 0.45;
				s += fig({ x, y: w.topAt(x) - h * 0.02, h, dir: -1, robe: pick(["#f2ead8", "#e4d8c0", "#ece2cc"]), mantle: i % 4 === 0 ? "#384568" : null, wrap: "#f4ecd8", beard: pick(["full", "short", "grey"]), stride: 0.6, back: i % 6 === 1 ? [20, -20] : [40, -30], front: i % 6 === 2 ? [5, -20] : [40, -40], items: gear[i % 6], shade: 0.4 });
				i++;
			}
			// The people below, arms up in gladness
			s += crowd(60, [300, 1260], [590, 760], [50, 100], { toward: 1400, arms: 0.55 });
			s += crowd(16, [900, 1500], [790, 900], [110, 150], { toward: 1700, arms: 0.6 });
			s += shadowBand(930, 0.62, "#5a4432");
			return s;
		},
	},
};
