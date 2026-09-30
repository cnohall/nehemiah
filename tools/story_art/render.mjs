// Render the story illustrations: node tools/story_art/render.mjs [name ...] [--out DIR]
// Each scene → HTML → headless Chrome screenshot (PNG) → ffmpeg JPG in assets/story/.
// With --out, the PNGs go there instead (previews) and assets/ is left alone.
import { execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync, existsSync, mkdtempSync } from "node:fs";
import { join, resolve, dirname } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { W, H, seed } from "./kit.mjs";
import { page } from "./litho.mjs";
import { SCENES } from "./scenes.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "../..");
const args = process.argv.slice(2);
const oi = args.indexOf("--out");
const out = oi >= 0 ? resolve(args.splice(oi, 2)[1]) : null;
const names = args.length ? args : Object.keys(SCENES);

const CHROME = ["C:/Program Files/Google/Chrome/Application/chrome.exe", "/usr/bin/google-chrome"].find(existsSync);
const tmp = mkdtempSync(join(tmpdir(), "story-art-"));
const dest = out ?? join(root, "assets/story");
mkdirSync(dest, { recursive: true });

for (const name of names) {
	const scene = SCENES[name];
	if (!scene) throw new Error(`no scene ${name}`);
	seed(scene.seed ?? name.length * 7919);
	const html = join(tmp, `${name}.html`);
	writeFileSync(html, page(scene.draw()));
	const png = join(out ?? tmp, `${name}.png`);
	execFileSync(CHROME, ["--headless=new", "--disable-gpu", "--hide-scrollbars", `--window-size=${W},${H}`,
		"--force-device-scale-factor=1", "--virtual-time-budget=4000", `--screenshot=${png}`, `file:///${html.replace(/\\/g, "/")}`], { stdio: "ignore" });
	if (!out)
		execFileSync("ffmpeg", ["-y", "-loglevel", "error", "-i", png, "-q:v", "6", join(dest, `${name}.jpg`)]);
	console.log(name, "→", out ? png : join(dest, `${name}.jpg`));
}
