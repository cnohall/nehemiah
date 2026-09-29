// Pushes the Play listing (text + graphics for every locale under metadata/) and,
// optionally, an .aab as a draft release on a testing track.
//
//   PLAY_KEY_JSON=path/to/key.json node store/play/push.mjs [flags]
//
//   --dry-run        validate and print the plan, touch nothing
//   --no-images      push listing text only
//   --bundle=PATH    upload this .aab and put it on --track as a release
//   --track=alpha    alpha = closed testing, internal = internal testing
//   --status=draft   draft (default) waits for a click in Play Console; completed
//                    sends it straight to review and out to the track's testers
//   --inspect        print what Play holds, change nothing
//
// Release notes ("What's new") come from metadata/<locale>/release_notes.txt when
// present (500 characters at most).
//
// No dependencies: signs the service-account JWT with node:crypto and talks to
// the REST API with fetch. Everything happens inside one edit, committed at the
// end; any failure deletes the edit so nothing is half-applied.
//
// While the app was still a draft on Play, releases could only be created as drafts;
// since the first closed test went out, --status=completed works too.

import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";

const PACKAGE = "com.fivestones.nehemiah";
const HERE = path.dirname(fileURLToPath(import.meta.url));
const METADATA = path.join(HERE, "metadata");
const API = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PACKAGE}`;
const UPLOAD = `https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/${PACKAGE}`;

const TEXT = { title: ["title.txt", 30], shortDescription: ["short_description.txt", 80], fullDescription: ["full_description.txt", 4000] };
const IMAGE_SETS = ["phoneScreenshots", "sevenInchScreenshots", "tenInchScreenshots"];
const IMAGE_SINGLES = ["featureGraphic", "icon"];

const args = { dryRun: false, images: true, bundle: null, track: "alpha", status: "draft", inspect: false };
for (const a of process.argv.slice(2)) {
	if (a === "--dry-run") args.dryRun = true;
	else if (a === "--no-images") args.images = false;
	else if (a === "--inspect") args.inspect = true;
	else if (a.startsWith("--bundle=")) args.bundle = a.slice(9);
	else if (a.startsWith("--track=")) args.track = a.slice(8);
	else if (a.startsWith("--status=")) args.status = a.slice(9);
	else throw new Error(`unknown argument: ${a}`);
}

// Play counts code points, not UTF-16 units (matters for Korean).
const count = (s) => [...s].length;

function readLocale(locale) {
	const dir = path.join(METADATA, locale);
	const listing = { language: locale };
	const errors = [];
	for (const [field, [file, limit]] of Object.entries(TEXT)) {
		const p = path.join(dir, file);
		if (!fs.existsSync(p)) { errors.push(`missing ${file}`); continue; }
		listing[field] = fs.readFileSync(p, "utf8").replace(/\r\n/g, "\n").trim();
		const n = count(listing[field]);
		if (n === 0 || n > limit) errors.push(`${field} is ${n} chars (1-${limit})`);
	}
	const notes = path.join(dir, "release_notes.txt");
	const releaseNotes = fs.existsSync(notes) ? fs.readFileSync(notes, "utf8").replace(/\r\n/g, "\n").trim() : "";
	if (count(releaseNotes) > 500) errors.push(`release notes are ${count(releaseNotes)} chars (max 500)`);
	const images = {};
	const imgDir = path.join(dir, "images");
	for (const set of IMAGE_SETS) {
		const d = path.join(imgDir, set);
		if (!fs.existsSync(d)) continue;
		const files = fs.readdirSync(d).filter((f) => /\.png$/i.test(f))
			.sort((a, b) => a.localeCompare(b, "en", { numeric: true })).map((f) => path.join(d, f));
		if (files.length < 2 || files.length > 8) errors.push(`${set} has ${files.length} images (2-8)`);
		if (files.length) images[set] = files;
	}
	for (const single of IMAGE_SINGLES) {
		const p = path.join(imgDir, `${single}.png`);
		if (fs.existsSync(p)) images[single] = [p];
	}
	return { locale, listing, images, releaseNotes, errors };
}

async function token(keyFile) {
	const key = JSON.parse(fs.readFileSync(keyFile, "utf8"));
	const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
	const now = Math.floor(Date.now() / 1000);
	const unsigned = `${b64({ alg: "RS256", typ: "JWT" })}.${b64({
		iss: key.client_email, scope: "https://www.googleapis.com/auth/androidpublisher",
		aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600,
	})}`;
	const sig = crypto.createSign("RSA-SHA256").update(unsigned).sign(key.private_key, "base64url");
	const res = await fetch("https://oauth2.googleapis.com/token", {
		method: "POST",
		headers: { "content-type": "application/x-www-form-urlencoded" },
		body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${unsigned}.${sig}` }),
	});
	if (!res.ok) throw new Error(`token: ${res.status} ${await res.text()}`);
	return (await res.json()).access_token;
}

function client(accessToken) {
	return async (method, url, { json, file, type } = {}) => {
		const headers = { authorization: `Bearer ${accessToken}` };
		let body;
		if (json) { headers["content-type"] = "application/json"; body = JSON.stringify(json); }
		if (file) { headers["content-type"] = type; body = fs.readFileSync(file); }
		const res = await fetch(url, { method, headers, body });
		const text = await res.text();
		if (!res.ok) throw new Error(`${method} ${url.replace(/^.*applications\/[^/]+/, "")}: ${res.status} ${text}`);
		return text ? JSON.parse(text) : {};
	};
}

async function inspect(call, edit) {
	const { listings = [] } = await call("GET", `${API}/edits/${edit}/listings`);
	for (const l of listings) console.log(`listing ${l.language.padEnd(6)} ${l.title}`);
	for (const locale of listings.map((l) => l.language)) {
		const counts = [];
		for (const t of [...IMAGE_SETS, ...IMAGE_SINGLES]) {
			const { images = [] } = await call("GET", `${API}/edits/${edit}/listings/${locale}/${t}`);
			if (images.length) counts.push(`${t}=${images.length}`);
		}
		console.log(`images  ${locale.padEnd(6)} ${counts.join(" ") || "(none)"}`);
	}
	const { tracks = [] } = await call("GET", `${API}/edits/${edit}/tracks`);
	for (const t of tracks) console.log(`track   ${t.track.padEnd(10)} ${JSON.stringify(t.releases || [])}`);
	for (const t of ["alpha", "internal"]) {
		const testers = await call("GET", `${API}/edits/${edit}/testers/${t}`).catch((e) => ({ error: e.message }));
		console.log(`testers ${t.padEnd(10)} ${JSON.stringify(testers)}`);
	}
	const { bundles = [] } = await call("GET", `${API}/edits/${edit}/bundles`);
	console.log(`bundles ${bundles.map((b) => b.versionCode).join(", ") || "(none)"}`);
}

const locales = fs.readdirSync(METADATA).filter((d) => fs.statSync(path.join(METADATA, d)).isDirectory()).sort();
const payloads = locales.map(readLocale);
for (const p of payloads) {
	const imgs = Object.entries(p.images).map(([t, f]) => `${t}=${f.length}`).join(" ");
	console.log(`${p.locale.padEnd(6)} title=${count(p.listing.title || "")} short=${count(p.listing.shortDescription || "")} full=${count(p.listing.fullDescription || "")} [${imgs}]`);
}
const problems = payloads.filter((p) => p.errors.length);
if (problems.length) {
	for (const p of problems) console.error(`${p.locale}: ${p.errors.join("; ")}`);
	process.exit(1);
}
if (args.bundle && !fs.existsSync(args.bundle)) throw new Error(`bundle not found: ${args.bundle}`);
if (!["draft", "completed"].includes(args.status)) throw new Error(`--status must be draft or completed`);
const releaseNotes = payloads.filter((p) => p.releaseNotes).map((p) => ({ language: p.locale, text: p.releaseNotes }));
if (args.bundle) console.log(`release: ${args.track}, ${args.status}, notes in ${releaseNotes.map((n) => n.language).join(" ") || "(none)"}`);
if (args.dryRun) { console.log("\ndry run, nothing sent"); process.exit(0); }

const keyFile = process.env.PLAY_KEY_JSON;
if (!keyFile) throw new Error("set PLAY_KEY_JSON to the service account key");
const call = client(await token(keyFile));
const { id: edit } = await call("POST", `${API}/edits`, { json: {} });
console.log(`\nedit ${edit} opened`);

try {
	if (args.inspect) {
		await inspect(call, edit);
		await call("DELETE", `${API}/edits/${edit}`);
		console.log("edit discarded, nothing changed");
		process.exit(0);
	}

	for (const { locale, listing, images } of payloads) {
		await call("PUT", `${API}/edits/${edit}/listings/${locale}`, { json: listing });
		console.log(`listing ${locale}`);
		if (!args.images) continue;
		// Play replaces graphics wholesale per type; a type with no local files is left alone.
		for (const [type, files] of Object.entries(images)) {
			await call("DELETE", `${API}/edits/${edit}/listings/${locale}/${type}`);
			for (const f of files) await call("POST", `${UPLOAD}/edits/${edit}/listings/${locale}/${type}?uploadType=media`, { file: f, type: "image/png" });
			console.log(`  ${type}: ${files.length}`);
		}
	}

	if (args.bundle) {
		console.log(`uploading ${args.bundle} ...`);
		const { versionCode } = await call("POST", `${UPLOAD}/edits/${edit}/bundles?uploadType=media`, { file: args.bundle, type: "application/octet-stream" });
		console.log(`bundle versionCode ${versionCode}`);
		await call("PUT", `${API}/edits/${edit}/tracks/${args.track}`, {
			json: { track: args.track, releases: [{ name: String(versionCode), versionCodes: [String(versionCode)], status: args.status,
				...(releaseNotes.length ? { releaseNotes } : {}) }] },
		});
		console.log(`track ${args.track}: ${args.status} release ${versionCode}`);
	}

	await call("POST", `${API}/edits/${edit}:commit`);
	console.log("\ncommitted");
} catch (err) {
	await call("DELETE", `${API}/edits/${edit}`).catch(() => {});
	console.error(`\nedit discarded: ${err.message}`);
	process.exit(1);
}
