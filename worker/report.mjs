// Play stats as tables (see src/stats.js).
//   $env:STATS_KEY = "..."; node report.mjs [days] [base-url]
// Defaults: 7 days, https://play.nehemiahgame.com. For `wrangler dev`: node report.mjs 7 http://localhost:8787

const key = process.env.STATS_KEY;
if (!key) {
  console.error("Set STATS_KEY (the secret put with `wrangler secret put STATS_KEY`).");
  process.exit(1);
}
const days = Number(process.argv[2]) || 7;
const base = (process.argv[3] || "https://play.nehemiahgame.com").replace(/\/$/, "");

const res = await fetch(`${base}/t/report?days=${days}`, { headers: { authorization: `Bearer ${key}` } });
if (!res.ok) {
  console.error(`${res.status} ${res.statusText}${res.status === 404 ? " (no STATS_KEY secret on the Worker, or not deployed yet)" : ""}`);
  process.exit(1);
}
const r = await res.json();

console.log(`\nLast ${r.window_days} days · ${r.sessions} sessions (${r.live_now} live now)\n`);

console.log("Funnel");
console.table(r.funnel);
console.log("Minutes played (sessions that started a stretch)");
console.table([r.minutes_played]);
console.log("Furthest stretch reached");
console.table(r.furthest_stretch);
console.log("Where sessions stopped (ended = quiet for 2.5 min)");
console.table(r.stopped_at);
console.log("Full vs Simple");
console.table(r.full_vs_simple);
console.log("Solo vs company");
console.table(r.solo_vs_company);
console.log("Recent sessions (UTC start time, newest first)");
console.table(r.recent);
console.log("Frames per second while playing");
console.table([r.fps_in_play]);
