#!/usr/bin/env node
// Steam store + library art, written into store/steam/capsules/:
//   node store/steam/render.mjs [key_art.png]
//
// Input: a 3840x2160 no-HUD render (default store/steam/key_art.png) from
//   Godot --path . --script res://tools/capsule_shots.gd -- --nostory store/steam
// Every capsule crops that one frame and sets the title in the game's own Cinzel,
// the way store/play/render.mjs builds the Play graphics (headless Chrome, plain HTML).
// Sizes and rules: docs/steam/store_page.md §10. Library hero carries no text (Steam
// lays the library logo over it); the library logo is a transparent PNG.

import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const GAME = path.join(HERE, "..", "..");
const OUT = path.join(HERE, "capsules");
const ART = path.resolve(process.argv[2] ?? path.join(HERE, "key_art.png"));
const CHROME = [
  "C:/Program Files/Google/Chrome/Application/chrome.exe",
  "C:/Program Files (x86)/Google/Chrome/Application/chrome.exe",
].find((p) => fs.existsSync(p));
if (!CHROME) throw new Error("Chrome not found");
if (!fs.existsSync(ART)) throw new Error(`No key art at ${ART}`);

// UiStyle (scenes/ui/ui_style.gd)
const C = { gold: "#e0ae56", dusk: "#1b110b", cream: "#fbf7ee" };

function font(name, file) {
  const b64 = fs.readFileSync(path.join(GAME, "assets", "fonts", file)).toString("base64");
  return `@font-face{font-family:"${name}";src:url(data:font/ttf;base64,${b64}) format("truetype")}`;
}
const FONTS = font("Cinzel", "Cinzel/static/Cinzel-Bold.ttf");

// Title block: NEHEMIAH, a gold rule each side of THE WALL. `s` = title font size in px.
function title(s, align = "left") {
  return `
  <div class="title" style="text-align:${align}">
    <div class="name" style="font-size:${s}px">Nehemiah</div>
    <div class="sub" style="font-size:${Math.round(s * 0.3)}px;justify-content:${align === "center" ? "center" : "flex-start"}">
      <span class="rule"></span><span>The Wall</span><span class="rule"></span>
    </div>
  </div>`;
}

const BASE = `${FONTS}
  *{margin:0;padding:0;box-sizing:border-box}
  html,body{width:100%;height:100%;overflow:hidden}
  .title{font-family:"Cinzel",serif;color:${C.cream};letter-spacing:.04em;line-height:1}
  .name{text-transform:uppercase;text-shadow:0 .04em 0 ${C.dusk},0 .06em .25em rgba(27,17,11,.85)}
  .sub{display:flex;align-items:center;gap:.6em;margin-top:.35em;color:${C.gold};
       text-transform:uppercase;letter-spacing:.3em;text-shadow:0 .08em .3em rgba(27,17,11,.9)}
  .rule{display:block;width:2.2em;height:.08em;background:${C.gold};opacity:.85}`;

// A crop of the key art under a dusk wash toward the title corner
function capsule({ w, h, pos, size, titleSize, place, align = "left", wash }) {
  const art = pathToFileURL(ART).href;
  return `<!doctype html><meta charset="utf-8"><style>${BASE}
    body{width:${w}px;height:${h}px;background:${C.dusk} url("${art}") ${pos} / ${size ?? "cover"} no-repeat;position:relative}
    .wash{position:absolute;inset:0;background:${wash}}
    .place{position:absolute;${place}}
  </style><div class="wash"></div><div class="place">${title(titleSize, align)}</div>`;
}

const JOBS = [
  // Store
  { file: "header_capsule.png", w: 920, h: 430, html: capsule({
      w: 920, h: 430, pos: "58% 45%", titleSize: 74, place: "left:40px;bottom:36px",
      wash: "linear-gradient(35deg,rgba(27,17,11,.8) 0%,rgba(27,17,11,.35) 38%,transparent 60%)" }) },
  { file: "small_capsule.png", w: 462, h: 174, html: capsule({
      w: 462, h: 174, pos: "55% 40%", titleSize: 54, place: "left:0;right:0;top:50%;transform:translateY(-50%)", align: "center",
      wash: "rgba(27,17,11,.55)" }) },
  { file: "main_capsule.png", w: 1232, h: 706, html: capsule({
      w: 1232, h: 706, pos: "58% 42%", titleSize: 104, place: "left:56px;bottom:52px",
      wash: "linear-gradient(35deg,rgba(27,17,11,.8) 0%,rgba(27,17,11,.3) 36%,transparent 58%)" }) },
  { file: "vertical_capsule.png", w: 748, h: 896, html: capsule({
      w: 748, h: 896, pos: "47% 40%", titleSize: 92, place: "left:0;right:0;bottom:60px", align: "center",
      wash: "linear-gradient(0deg,rgba(27,17,11,.85) 0%,rgba(27,17,11,.4) 28%,transparent 48%)" }) },
  { file: "page_background.png", w: 1438, h: 810, html: capsule({
      w: 1438, h: 810, pos: "50% 50%", titleSize: 0, place: "display:none",
      wash: "linear-gradient(rgba(27,17,11,.72),rgba(27,17,11,.9))" }) },
  // Library
  { file: "library_capsule.png", w: 600, h: 900, html: capsule({
      w: 600, h: 900, pos: "46% 40%", titleSize: 76, place: "left:0;right:0;bottom:56px", align: "center",
      wash: "linear-gradient(0deg,rgba(27,17,11,.85) 0%,rgba(27,17,11,.4) 28%,transparent 48%)" }) },
  { file: "library_header.png", w: 920, h: 430, html: capsule({
      w: 920, h: 430, pos: "58% 45%", titleSize: 74, place: "left:40px;bottom:36px",
      wash: "linear-gradient(35deg,rgba(27,17,11,.8) 0%,rgba(27,17,11,.35) 38%,transparent 60%)" }) },
  { file: "library_hero.png", w: 3840, h: 1240, html: capsule({
      w: 3840, h: 1240, pos: "50% 38%", titleSize: 0, place: "display:none", wash: "transparent" }) },
  { file: "library_logo.png", w: 1280, h: 720, transparent: true, html: `<!doctype html><meta charset="utf-8"><style>${BASE}
      html,body{background:transparent}
      body{width:1280px;height:720px;display:flex;align-items:center;justify-content:center}
    </style>${title(200, "center")}` },
];

function render(html, out, w, h, transparent) {
  const tmp = path.join(HERE, ".render.html");
  fs.writeFileSync(tmp, html);
  const args = [
    "--headless=new", "--disable-gpu", "--hide-scrollbars", "--allow-file-access-from-files",
    `--window-size=${w},${h}`, "--force-device-scale-factor=1", "--virtual-time-budget=3000",
    `--screenshot=${out}`, pathToFileURL(tmp).href,
  ];
  if (transparent) args.unshift("--default-background-color=00000000");
  execFileSync(CHROME, args, { stdio: "ignore" });
  fs.rmSync(tmp);
}

fs.mkdirSync(OUT, { recursive: true });
for (const j of JOBS) {
  render(j.html, path.join(OUT, j.file), j.w, j.h, j.transparent);
  console.log(`${j.file} ${j.w}x${j.h}`);
}
