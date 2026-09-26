// Export the web build, upload it to R2 (gzipped) and deploy the Worker.
//
//   node deploy.mjs                 export + upload + deploy
//   node deploy.mjs --skip-export   reuse build/web as-is
//   node deploy.mjs --local         upload to the local R2 that `wrangler dev` uses; no deploy
//
// GODOT = path to the Godot 4.7.2 console binary (defaults to the one on this machine).
// The "Web" export preset lives in the repo root's export_presets.cfg (gitignored).

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import zlib from "node:zlib";

const BUCKET = "nehemiah-game";
const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const web = path.join(root, "build", "web");
const args = new Set(process.argv.slice(2));
const local = args.has("--local");

const GODOT = process.env.GODOT ||
  "C:/Users/chris/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe";

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript",
  ".wasm": "application/wasm",
  ".pck": "application/octet-stream",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".json": "application/json",
  ".webmanifest": "application/manifest+json",
};
const COMPRESSIBLE = new Set([".html", ".js", ".wasm", ".pck", ".json", ".svg"]);

function run(cmd, argv, opts = {}) {
  const r = spawnSync(cmd, argv, { stdio: "inherit", shell: process.platform === "win32", ...opts });
  if (r.status !== 0) {
    console.error(`\n✗ ${cmd} ${argv.join(" ")} failed (${r.status})`);
    process.exit(1);
  }
}

if (!args.has("--skip-export")) {
  console.log("→ exporting web build");
  fs.mkdirSync(web, { recursive: true });
  run(`"${GODOT}"`, ["--headless", "--path", `"${root}"`, "--export-release", "Web", `"${path.join(web, "index.html")}"`]);
}
if (!fs.existsSync(path.join(web, "index.html"))) {
  console.error(`No web build at ${web}`);
  process.exit(1);
}

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "nehemiah-r2-"));
// index.html last, so a page never loads against a half-uploaded build's html
const files = fs.readdirSync(web).filter((f) => fs.statSync(path.join(web, f)).isFile())
  .sort((a, b) => (a === "index.html") - (b === "index.html"));

for (const name of files) {
  const ext = path.extname(name).toLowerCase();
  let file = path.join(web, name);
  const flags = ["--content-type", `"${MIME[ext] || "application/octet-stream"}"`];
  if (COMPRESSIBLE.has(ext)) {
    const gz = path.join(tmp, name + ".gz");
    fs.writeFileSync(gz, zlib.gzipSync(fs.readFileSync(file), { level: 9 }));
    file = gz;
    flags.push("--content-encoding", "gzip");
  }
  console.log(`→ ${name} (${(fs.statSync(file).size / 1e6).toFixed(1)} MB)`);
  run("npx", ["wrangler", "r2", "object", "put", `${BUCKET}/${name}`, "--file", `"${file}"`, ...flags,
    local ? "--local" : "--remote"], { cwd: here });
}
fs.rmSync(tmp, { recursive: true, force: true });

if (!local) {
  console.log("→ deploying worker");
  run("npx", ["wrangler", "deploy"], { cwd: here });
}
console.log("✓ done");
