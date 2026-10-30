import test from "node:test";
import assert from "node:assert/strict";
import { summarize, toRow } from "../src/stats_core.js";

const base = { k: "beat", s: "abcdef012345", t: 0, sc: "Main", mode: "campaign", sec: 0, day: 1, ph: "WORK",
  done: 0, tot: 6, br: 0, crew: 1, simple: 0, fps: 60, lang: "en" };
const NOW = 1_800_000_000_000;

// A session's beacons, oldest first; `at` counts back from `end` in 30 s steps
function session(s, evs, end = NOW - 600_000) {
  return evs.map((e, i) => ({ ...toRow({ ...base, s, ...e }, end - (evs.length - 1 - i) * 30_000) }));
}

test("a good beacon becomes a row with only the known fields", () => {
  const row = toRow({ ...base, ip: "1.2.3.4", name: "Sam", extra: { a: 1 } }, 123);
  assert.equal(row.at, 123);
  assert.equal(row.ph, "WORK");
  assert.deepEqual(Object.keys(row).sort(), ["at", "br", "crew", "day", "done", "fps", "k", "lang", "mode", "ph",
    "s", "sc", "sec", "simple", "t", "tot", "vh", "vw"]);
  assert.ok(!("ip" in row) && !("name" in row) && !("extra" in row));
});

test("bad beacons are turned away", () => {
  assert.equal(toRow(null), null);
  assert.equal(toRow([]), null);
  assert.equal(toRow({ ...base, k: "pwn" }), null);
  assert.equal(toRow({ ...base, ph: "NOPE" }), null);
  assert.equal(toRow({ ...base, mode: "x" }), null);
  assert.equal(toRow({ ...base, s: "short" }), null);
  assert.equal(toRow({ ...base, s: "has space in it!!" }), null);
});

test("numbers are clamped, strings that aren't words are emptied", () => {
  const row = toRow({ ...base, sec: 999, day: -5, fps: "fast", sc: "<script>", lang: "en-US!" });
  assert.equal(row.sec, 11);
  assert.equal(row.day, 0);
  assert.equal(row.fps, 0);
  assert.equal(row.sc, "");
  assert.equal(row.lang, "");
});

test("the report finds where sessions stopped, and who got how far", () => {
  const rows = [
    // bounced from the menu
    ...session("aaaaaaaa0001", [{ sc: "MainMenu", ph: "GATHER", k: "open" }]),
    // played the Sheep Gate, finished it, died in the Fish Gate's work
    ...session("aaaaaaaa0002", [
      { t: 10 }, { t: 40, done: 3 }, { t: 70, done: 6, ph: "DUSK", k: "phase" },
      { t: 100, sec: 1, day: 5 }, { t: 130, sec: 1, day: 5, done: 2 },
    ]),
    // practised, then quit on the tutorial
    ...session("aaaaaaaa0003", [{ mode: "tutorial", t: 20 }, { mode: "tutorial", t: 50 }]),
    // still playing now
    ...session("aaaaaaaa0004", [{ t: 10 }, { t: 40 }], NOW - 10_000),
    // simple game, two in the crew, three stretches done
    ...session("aaaaaaaa0005", [
      { simple: 1, crew: 2, t: 10 },
      { simple: 1, crew: 2, t: 20, done: 6, ph: "DUSK", sec: 0, day: 4 },
      { simple: 1, crew: 2, t: 30, done: 6, ph: "DUSK", sec: 1, day: 8 },
      { simple: 1, crew: 2, t: 600, done: 6, ph: "DUSK", sec: 2, day: 12 },
      { simple: 1, crew: 2, t: 610, sec: 3, day: 13, done: 1 },
    ]),
  ];
  const r = summarize(rows, 7, NOW);
  assert.equal(r.sessions, 5);
  assert.equal(r.live_now, 1);
  assert.equal(r.funnel.opened, 5);
  assert.equal(r.funnel.practised, 1);
  assert.equal(r.funnel.started_a_stretch, 3);
  assert.equal(r.funnel.finished_a_stretch, 2);
  assert.equal(r.funnel.finished_three, 1);
  assert.deepEqual(r.furthest_stretch.map((f) => [f.stretch, f.sessions]), [[0, 1], [1, 1], [3, 1]]);
  const stops = Object.fromEntries(r.stopped_at.map((s) => [s.where, s.sessions]));
  assert.equal(stops["menu (MainMenu)"], 1);
  assert.equal(stops["Fish Gate · WORK"], 1);
  assert.equal(stops["Broad Wall · WORK"], 1);
  assert.equal(stops["tutorial"], 1);
  assert.equal(r.full_vs_simple.simple.sessions, 1);
  assert.equal(r.full_vs_simple.full.sessions, 2);
  assert.equal(r.solo_vs_company.company.sessions, 1);
  assert.equal(r.fps_in_play.median, 60);
  assert.equal(r.recent.length, 5);
  const mine = r.recent.find((x) => x.crew === 2);
  assert.equal(mine.game, "simple");
  assert.equal(mine.reached, "Broad Wall");
  assert.equal(mine.stretches_finished, 3);
  assert.equal(mine.stopped, "Broad Wall · WORK");
  assert.ok(r.recent.some((x) => x.stopped === "(live)"));
  assert.ok(r.recent.some((x) => x.reached === "menu only"));
});

test("an empty window is a report, not a crash", () => {
  const r = summarize([], 7, NOW);
  assert.equal(r.sessions, 0);
  assert.equal(r.minutes_played.median, null);
});
