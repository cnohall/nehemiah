#!/usr/bin/env node
// Play Store graphics for every locale in captions.json:
//   phone screenshots (1920x1080, landscape, the game is landscape) and the feature
//   graphic (1024x500), written into metadata/<locale>/images/.
//
//   node store/play/render.mjs [--locales=en-US,de-DE]
//
// Inputs:
//   store/play/captures/<game lang>/*.png   raw phone-layout captures from mobile-spike:
//     Godot --path . --resolution 1848x822 --script res://tools/store_shots.gd -- --touch --lang=<l> <captures dir>
//   store/play/captions.json               shot order + caption per locale
//   store/play/feature_art.png             1920x1080 no-HUD art for the feature graphic
//
// Headless Chrome renders plain HTML/CSS (like gem-reader's store assets), so long
// German captions and Korean text lay out without hand-tuning. The look is the game's
// own: parchment and dusk grounds, Cinzel captions, a gold marker (UiStyle colours).

import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const GAME = path.join(HERE, "..", "..");
const CONFIG = JSON.parse(fs.readFileSync(path.join(HERE, "captions.json"), "utf8"));
const CHROME = [
  "C:/Program Files/Google/Chrome/Application/chrome.exe",
  "C:/Program Files (x86)/Google/Chrome/Application/chrome.exe",
].find((p) => fs.existsSync(p));
if (!CHROME) throw new Error("Chrome not found");

// UiStyle (scenes/ui/ui_style.gd), so the store and the game can't drift apart
const C = {
  parchment: "#f5eee1", parchmentDeep: "#e5d9c7", ink: "#231810", inkSoft: "#64513f",
  gold: "#e0ae56", terracotta: "#ac5020", dusk: "#1b110b", cream: "#fbf7ee",
};
// Grounds alternate so the first three (Play's search triptych) don't read as one smear
const GROUNDS = [
  { bg: C.dusk, bg2: "#2a1a10", ink: C.cream, bezel: "#0c0805" },
  { bg: C.parchmentDeep, bg2: "#d6c6ae", ink: C.ink, bezel: "#2a1d12" },
];

const TAGLINES = {
  "en-US": "Rebuild the wall of Jerusalem in 52 days",
  "es-419": "Reconstruye la muralla de Jerusalén en 52 días",
  "pt-BR": "Reconstrua a muralha de Jerusalém em 52 dias",
  "de-DE": "Baue Jerusalems Mauer in 52 Tagen wieder auf",
  "ko-KR": "52일 만에 예루살렘 성벽을 다시 쌓아요",
};

function font(name, file) {
  const b64 = fs.readFileSync(path.join(GAME, "assets", "fonts", file)).toString("base64");
  return `@font-face{font-family:"${name}";src:url(data:font/ttf;base64,${b64}) format("truetype")}`;
}
const FONTS = [
  font("Cinzel", "Cinzel/static/Cinzel-Bold.ttf"),
  font("Spectral", "Spectral/Spectral-Medium.ttf"),
].join("\n");
// Cinzel and Spectral have no Hangul: Korean falls back to the system serif
const FAMILY = `"Cinzel", "Spectral", "Batang", "Malgun Gothic", serif`;

const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const caption = (s) =>
  s.split(/(==[^=]+==)/).map((p) => (p.startsWith("==") ? `<mark>${esc(p.slice(2, -2))}</mark>` : esc(p))).join("");

function shotHtml(text, captureUrl, g) {
  const len = text.replace(/==/g, "").length;
  const size = len > 44 ? 58 : len > 36 ? 64 : 72;
  return `<!doctype html><html><head><meta charset="utf-8"><style>
${FONTS}
html,body{margin:0;width:1920px;height:1080px;overflow:hidden}
body{background:radial-gradient(120% 90% at 50% 0%, ${g.bg} 0%, ${g.bg2} 100%);font-family:${FAMILY};color:${g.ink}}
.cap{position:absolute;top:0;left:0;right:0;height:215px;display:flex;align-items:center;justify-content:center;
  padding:0 120px;box-sizing:border-box;text-align:center;font-size:${size}px;line-height:1.25;letter-spacing:.01em}
mark{background:${C.gold};color:${C.ink};padding:0 .22em;border-radius:6px;box-decoration-break:clone;-webkit-box-decoration-break:clone}
.phone{position:absolute;left:50%;top:228px;transform:translateX(-50%);width:1680px;padding:22px;border-radius:56px;
  background:linear-gradient(180deg,#3a2a1c,${g.bezel});box-shadow:0 40px 80px -30px rgba(0,0,0,.55)}
.phone img{display:block;width:100%;border-radius:36px}
</style></head><body><div class="cap"><div>${caption(text)}</div></div>
<div class="phone"><img src="${captureUrl}"></div></body></html>`;
}

function featureHtml(tagline, artUrl) {
  return `<!doctype html><html><head><meta charset="utf-8"><style>
${FONTS}
html,body{margin:0;width:1024px;height:500px;overflow:hidden;background:${C.dusk}}
.art{position:absolute;inset:0;background:url("${artUrl}") 62% 42%/cover}
.veil{position:absolute;inset:0;background:linear-gradient(90deg,rgba(27,17,11,.92) 0%,rgba(27,17,11,.7) 38%,rgba(27,17,11,0) 68%)}
.text{position:absolute;left:56px;top:0;bottom:0;width:560px;display:flex;flex-direction:column;justify-content:center;color:${C.cream}}
h1{margin:0;font-family:"Cinzel",serif;font-size:76px;letter-spacing:.04em;line-height:1}
.rule{width:120px;height:3px;background:${C.gold};margin:22px 0 18px}
p{margin:0;font-family:"Spectral","Batang","Malgun Gothic",serif;font-size:28px;line-height:1.3;color:#f0d9a8;text-wrap:balance}
</style></head><body><div class="art"></div><div class="veil"></div>
<div class="text"><h1>Nehemiah</h1><div class="rule"></div><p>${esc(tagline)}</p></div></body></html>`;
}

function render(html, out, w, h) {
  const tmp = path.join(HERE, ".render.html");
  fs.writeFileSync(tmp, html);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  execFileSync(CHROME, [
    "--headless=new", "--disable-gpu", "--hide-scrollbars", "--allow-file-access-from-files",
    `--window-size=${w},${h}`, "--force-device-scale-factor=1", "--virtual-time-budget=3000",
    `--screenshot=${out}`, pathToFileURL(tmp).href,
  ], { stdio: "ignore" });
  fs.rmSync(tmp);
}

const only = process.argv.find((a) => a.startsWith("--locales="))?.slice(10).split(",");
for (const [locale, lang] of Object.entries(CONFIG.langs)) {
  if (only && !only.includes(locale)) continue;
  const dir = path.join(HERE, "metadata", locale, "images");
  fs.rmSync(path.join(dir, "phoneScreenshots"), { recursive: true, force: true });
  CONFIG.shots.forEach((shot, i) => {
    const cap = path.join(HERE, "captures", lang, shot.capture);
    if (!fs.existsSync(cap)) throw new Error(`missing capture ${cap}`);
    const out = path.join(dir, "phoneScreenshots", `${i + 1}.png`);
    render(shotHtml(shot.captions[locale], pathToFileURL(cap).href, GROUNDS[i % 2]), out, 1920, 1080);
  });
  render(featureHtml(TAGLINES[locale], pathToFileURL(path.join(HERE, "feature_art.png")).href),
    path.join(dir, "featureGraphic.png"), 1024, 500);
  fs.copyFileSync(path.join(GAME, "icon.png"), path.join(dir, "icon.png"));
  console.log("rendered", locale);
}
