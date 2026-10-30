// The pure half of the play stats (stats.js has the Durable Object): turning a beacon into
// a row, and rows into the report. No Workers APIs here, so `node --test test/` runs it.

export const IDLE_MS = 150 * 1000;    // no beacon for this long (heartbeat is 30 s) = the session ended

export const KINDS = ["open", "phase", "beat", "hide", "show", "leave"];
export const MODES = ["campaign", "tutorial", "explore", "replay"];
export const PHASES = ["DAWN", "WORK", "DUSK", "WON", "LOST", "GATHER", "STORY"];

// Keep in step with GameState.SECTIONS (names only: indexes are what's stored)
export const SECTION_NAMES = ["Sheep Gate", "Fish Gate", "Jeshanah Gate", "Broad Wall", "Tower of the Ovens",
  "Valley Gate", "Gate of the Ash Heaps", "Fountain Gate", "Water Gate", "Horse Gate", "East Gate",
  "Miphkad Gate"];

// Columns of a row, in table order
export const COLS = ["at", "s", "k", "t", "sc", "mode", "sec", "day", "ph", "done", "tot", "br", "crew", "simple",
  "fps", "lang", "vw", "vh"];

const int = (v, lo, hi) => (Number.isFinite(v) ? Math.min(hi, Math.max(lo, Math.trunc(v))) : 0);
const pick = (v, list) => (list.includes(v) ? v : null);
const word = (v, max) => (typeof v === "string" && /^[A-Za-z0-9_-]+$/.test(v) && v.length <= max ? v : "");

// One beacon → one row, or null when it isn't one of ours. Anything not named here is dropped.
export function toRow(msg, now = Date.now()) {
  if (!msg || typeof msg !== "object" || Array.isArray(msg)) return null;
  const k = pick(msg.k, KINDS);
  const mode = pick(msg.mode, MODES);
  const ph = pick(msg.ph, PHASES);
  const s = word(msg.s, 16);
  if (!k || !mode || !ph || s.length < 8) return null;
  return {
    at: now,
    s,
    k,
    t: int(msg.t, 0, 86400),
    sc: word(msg.sc, 24),
    mode,
    sec: int(msg.sec, 0, 11),
    day: int(msg.day, 0, 60),
    ph,
    done: int(msg.done, 0, 99),
    tot: int(msg.tot, 0, 99),
    br: int(msg.br, 0, 99),
    crew: int(msg.crew, 0, 8),
    simple: msg.simple ? 1 : 0,
    fps: int(msg.fps, 0, 1000),
    lang: word(msg.lang, 8),
    vw: int(msg.vw, 0, 10000),
    vh: int(msg.vh, 0, 10000),
  };
}

// ── The report ─────────────────────────────────────────────

const sorted = (xs) => [...xs].sort((x, y) => x - y);
const at = (xs, q) => (xs.length ? sorted(xs)[Math.min(xs.length - 1, Math.floor((xs.length - 1) * q))] : null);
const median = (xs) => at(xs, 0.5);
// Where a session's last beacon says it was
const where = (l) => (l.sc !== "Main"
  ? `menu (${l.sc || "?"})`
  : l.mode !== "campaign"
    ? l.mode
    : `${SECTION_NAMES[l.sec] ?? l.sec} · ${l.ph}`);
const minutes = (secs) => (secs == null ? null : Math.round((secs / 60) * 10) / 10);

// rows (oldest first) → what to read after a playtest
export function summarize(rows, days, now) {
  const bySession = new Map();
  for (const r of rows) {
    if (!bySession.has(r.s)) bySession.set(r.s, []);
    bySession.get(r.s).push(r);
  }
  const sessions = [];
  for (const evs of bySession.values()) {
    const last = evs[evs.length - 1];
    // Playing the campaign: the game scene, in a stretch's work
    const campaign = evs.filter((e) => e.sc === "Main" && e.mode === "campaign");
    const worked = campaign.filter((e) => e.ph === "WORK");
    const dusks = campaign.filter((e) => e.ph === "DUSK" || e.ph === "WON");
    // A day ends at the stars or when the stretch stands: dusk with every piece up = a stretch done
    const stood = new Set(dusks.filter((e) => e.tot > 0 && e.done >= e.tot).map((e) => e.sec));
    sessions.push({
      last,
      first: evs[0].at,
      secs: Math.max(...evs.map((e) => e.t)),
      played: worked.length > 0,
      practised: evs.some((e) => e.sc === "Main" && e.mode === "tutorial"),
      // furthest stretch where the work was started
      reached: worked.length ? Math.max(...worked.map((e) => e.sec)) : -1,
      days: new Set(dusks.map((e) => e.day)).size,
      stretches: stood.size,
      simple: evs.some((e) => e.simple === 1),
      crew: Math.max(...evs.map((e) => e.crew)),
      ended: now - last.at > IDLE_MS,
      fps: evs.filter((e) => e.k === "beat" && e.sc === "Main" && e.fps > 0).map((e) => e.fps),
    });
  }
  const played = sessions.filter((s) => s.played);

  const reached = {};
  for (const s of played) reached[s.reached] = (reached[s.reached] || 0) + 1;

  // Where the ended sessions stopped: the last beacon's place
  const stops = new Map();
  for (const s of sessions.filter((x) => x.ended)) {
    const l = s.last;
    const w = where(l);
    const e = stops.get(w) || { where: w, n: 0, done: 0, tot: 0 };
    e.n++;
    e.done += l.done;
    e.tot += l.tot;
    stops.set(w, e);
  }

  const group = (list) => ({
    sessions: list.length,
    median_minutes: minutes(median(list.map((s) => s.secs))),
    median_stretch_reached: median(list.map((s) => s.reached)),
    median_stretches_finished: median(list.map((s) => s.stretches)),
  });

  return {
    window_days: days,
    generated: new Date(now).toISOString(),
    sessions: sessions.length,
    live_now: sessions.filter((s) => !s.ended).length,
    funnel: {
      opened: sessions.length,
      practised: sessions.filter((s) => s.practised).length,
      started_a_stretch: played.length,
      finished_a_day: played.filter((s) => s.days >= 1).length,
      finished_a_stretch: played.filter((s) => s.stretches >= 1).length,
      finished_three: played.filter((s) => s.stretches >= 3).length,
    },
    minutes_played: {
      median: minutes(median(played.map((s) => s.secs))),
      p90: minutes(at(played.map((s) => s.secs), 0.9)),
    },
    furthest_stretch: Object.entries(reached)
      .map(([i, n]) => ({ stretch: Number(i), name: SECTION_NAMES[i], sessions: n }))
      .sort((a, b) => a.stretch - b.stretch),
    stopped_at: [...stops.values()]
      .map((e) => ({
        where: e.where,
        sessions: e.n,
        avg_pieces: e.tot ? `${(e.done / e.n).toFixed(1)}/${(e.tot / e.n).toFixed(1)}` : null,
      }))
      .sort((a, b) => b.sessions - a.sessions),
    full_vs_simple: { full: group(played.filter((s) => !s.simple)), simple: group(played.filter((s) => s.simple)) },
    solo_vs_company: { solo: group(played.filter((s) => s.crew <= 1)), company: group(played.filter((s) => s.crew > 1)) },
    // Newest first, to match against an observer's notes by start time
    recent: [...sessions].sort((a, b) => b.first - a.first).slice(0, 30).map((s) => ({
      started: new Date(s.first).toISOString().slice(0, 16).replace("T", " "),
      minutes: minutes(s.secs),
      reached: s.reached >= 0 ? SECTION_NAMES[s.reached] : s.practised ? "practice" : "menu only",
      stretches_finished: s.stretches,
      stopped: s.ended ? where(s.last) : "(live)",
      crew: s.crew,
      game: s.simple ? "simple" : "full",
    })),
    fps_in_play: { median: median(played.flatMap((s) => s.fps)), p10: at(played.flatMap((s) => s.fps), 0.1) },
  };
}
