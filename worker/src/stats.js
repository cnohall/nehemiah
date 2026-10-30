// Anonymous play stats: where do sessions stop? (GDD §5.24, PLAYTEST_4.md)
//
// The web build sends a small beacon (POST /t) at every phase change, every 30 s while
// open, and when the tab is hidden. The last beacon of a session is where it stopped.
//
// What is kept: the fields in stats_core.js COLS — where on the circuit, how many pieces
// stand, how many got in, crew size, the game mode, frame rate, language. What is not:
// the address, the user agent, any cookie or id that outlives a page load (the session id
// is made fresh by the page). Of the request only the body and the Origin header are read.
//
// Reading it: GET /t/report?days=7 with `Authorization: Bearer <STATS_KEY>`
// (`wrangler secret put STATS_KEY`). With no secret set the report is off.
// `node report.mjs` in this folder prints it as tables.

import { DurableObject } from "cloudflare:workers";
import { COLS, summarize, toRow } from "./stats_core.js";

const MAX_BODY = 1024;
const PER_SESSION = 1000;      // events one session id may leave
const PER_DAY = 60000;         // events from everyone in a day
const KEEP_DAYS = 120;

export class Stats extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
    this.sql.exec(`CREATE TABLE IF NOT EXISTS ev (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      at INTEGER NOT NULL, s TEXT NOT NULL, k TEXT NOT NULL, t INTEGER, sc TEXT, mode TEXT,
      sec INTEGER, day INTEGER, ph TEXT, done INTEGER, tot INTEGER, br INTEGER, crew INTEGER,
      simple INTEGER, fps INTEGER, lang TEXT, vw INTEGER, vh INTEGER)`);
    this.sql.exec("CREATE INDEX IF NOT EXISTS ev_at ON ev (at)");
    // Running counts for the caps, so a beacon costs one row read, not a scan
    this.sql.exec("CREATE TABLE IF NOT EXISTS cap (k TEXT PRIMARY KEY, n INTEGER NOT NULL, at INTEGER NOT NULL)");
  }

  async fetch(req) {
    const url = new URL(req.url);
    if (url.pathname === "/t/report") return this.#report(req, url);
    if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
    // Only the page the Worker serves may report: a beacon from another site is not ours
    const origin = req.headers.get("origin");
    if (origin && origin !== url.origin) return new Response(null, { status: 403 });
    const text = await req.text();
    if (text.length > MAX_BODY) return new Response(null, { status: 413 });
    let row;
    try {
      row = toRow(JSON.parse(text));
    } catch {
      row = null;
    }
    if (!row) return new Response(null, { status: 400 });
    return new Response(null, { status: this.#store(row) });
  }

  #count(k, at) {
    return this.sql.exec(
      "INSERT INTO cap (k, n, at) VALUES (?, 1, ?) ON CONFLICT (k) DO UPDATE SET n = n + 1, at = excluded.at RETURNING n",
      k, at,
    ).one().n;
  }

  #store(row) {
    if (this.#count(`d:${new Date(row.at).toISOString().slice(0, 10)}`, row.at) > PER_DAY) return 429;
    if (this.#count(`s:${row.s}`, row.at) > PER_SESSION) return 429;
    this.sql.exec(`INSERT INTO ev (${COLS.join(",")}) VALUES (${COLS.map(() => "?").join(",")})`,
      ...COLS.map((c) => row[c]));
    if (Math.random() < 0.01) {
      const old = row.at - KEEP_DAYS * 86400000;
      this.sql.exec("DELETE FROM ev WHERE at < ?", old);
      this.sql.exec("DELETE FROM cap WHERE at < ?", old);
    }
    return 204;
  }

  #report(req, url) {
    const key = this.env.STATS_KEY;
    if (!key) return new Response("Not found", { status: 404 });
    if (req.headers.get("authorization") !== `Bearer ${key}`) return new Response("Unauthorized", { status: 401 });
    const days = Math.min(30, Math.max(1, Number(url.searchParams.get("days")) || 7));
    const now = Date.now();
    const rows = this.sql.exec(`SELECT ${COLS.join(",")} FROM ev WHERE at >= ? ORDER BY id`, now - days * 86400000).toArray();
    return Response.json(summarize(rows, days, now));
  }
}
