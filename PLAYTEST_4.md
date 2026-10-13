# Playtest 4 — does the pull exist, and does Simple earn its place?

**Goal:** answer four questions with strangers, not the dev circle. Decide from the numbers below, not from how the session felt.

1. **Is there a pull past stretch 3?** (Friends, 30 Sep: "fun for 2–3 stretches, then no pull to finish.") Nothing since has been tested on someone new.
2. **Does the first stretch have a peak?** The concept ladder (13 Oct) put new foes on a stretch's last day, so on paper Sheep Gate tops out at 3 scouts. Clear, but is it exciting?
3. **Simple or Full?** Simple removes trades, boons, the saboteur and the rest (GDD §5.23). Does it lose the Fellowship, or just the confusion?
4. **Is the loss rule fair?** 10 breaches over the *whole run* (`GameState.MAX_BREACHES`; the count carries across days). Does a rough early stretch haunt a late one?

**Rule for observers (same as playtest 3):** don't help, don't explain, don't say "try pressing…". The confusion is the data. If they ask a question, write it down and answer "what would you try?"

---

## 0. Before the first session

- [ ] **Close playtest 3.** Fill the verdict column in `GAME_DESIGN.md` §0 and the table at the end of `PLAYTEST_3.md` from the 4 Oct notes. Every row still says "pending". Playtest 4 can't compare against a baseline nobody wrote down.
- [ ] **Ship the stats.** In `C:\Programming\nehemiah-web` (branch `web-port`): merge master, `cd worker; npm test`, `npx wrangler secret put STATS_KEY`, `npm run deploy` (runs the v2 migration for `Stats`). The live build is older than master, and it has no stats until this is done.
- [ ] **Check it end to end.** Open play.nehemiahgame.com yourself, wait a minute, then `$env:STATS_KEY="…"; node report.mjs 1`. One session should show.
- [ ] **Privacy line on the site.** `nehemiah-website` privacy page: the web build sends anonymous play stats (where a game stops, how it runs); no name, no address, nothing kept on the device; Settings → Advanced → Play stats turns it off.
- [ ] **Fix the settings per group in advance** (see §1). Settings live in the browser, so use one browser profile per group or reset between groups.

---

## 1. Who and what

**Groups:** at least 4, ideally 6, of 2–3 people who have *never seen the game*, mixed skill, who play casual co-op (family, friends, a youth group). Fewer than 4 groups tells you about the people, not the game. Assign by alternating, not by who asks: groups 1, 3, 5 get **Simple**, groups 2, 4, 6 get **Full**.

**Setup (observer does this, then steps back):** Settings → Advanced → Game → Simple or Full. Host's choice, the other players inherit it. No bots when there are 2+ people; one Builder bot when someone plays alone.

**The session (about 45 minutes, one sitting):**
1. Hand them the link. No tutorial pushed; "Learn the Basics" is there if they choose it. Start the stopwatch when the first day's work begins.
2. They play on their own from day 1. **They may stop whenever they like. Do not ask them to continue.** When and why they stop is the main result.
3. At 45 minutes, or when they stop, go to the questions (§3).

Three stretches (days 1–12: Sheep Gate, Fish Gate, Jeshanah Gate) is about 25 minutes at par. If a group is still happily going at 45 minutes, that is a good sign: write it down and let them finish the stretch.

**Unobserved track (optional, costs nothing):** send the plain link, no flags, to a few people who will play without you. The play stats (§5) show where they stopped; ask the follow-up question (§4) a day or two later.

---

## 2. Observer sheet (fill during play)

Tally marks plus a clock reading ("T+4:30" from the first day's work). Time-stamping is the point: it shows when the game hooked them, not just whether it did.

**The first ten minutes** (question 2)
- [ ] First laugh, shout or "oh no": T+____ (target: inside 6 minutes)
- [ ] First near-miss (a wall piece almost lost, a foe reaching the gap): T+____
- [ ] First time someone is downed, and who helps: T+____
- [ ] Someone says it's boring / slow / "when do the enemies come?": T+____
- [ ] The Sheep Gate's last-unit pack (3 scouts): did they react (a shout, a rush to the gate) or ignore it?

**Friction** ("what do I do?" is the main count)
- [ ] "What do I do now?" / "where does this go?" — tally: ______
- [ ] Hit while building and complains
- [ ] Doesn't see a breach or battered wall until too late
- [ ] Can't find the day count / how much is left
- [ ] Stuck: wrong side of a wall, can't pick up, can't reach a pile
- [ ] Someone else's confusion (they ask each other): who explains to whom?

**Fellowship** (the core fun; want a lot of these)
- [ ] Someone calls out a job ("I'll get stone", "cover me") — tally: ______
- [ ] Someone saves or helps up a crewmate — tally: ______
- [ ] Laughter or shouting that comes from the chaos — tally: ______
- [ ] Someone says "we", not "I", about the wall

**Pull** (question 1)
- [ ] Reached the end of stretch 1 / 2 / 3 (circle): T+____
- [ ] The moment they would have stopped, if you hadn't been there (a sigh, "should we do one more?", a phone check): T+____ , stretch ____
- [ ] Read a twist card through, or skipped it
- [ ] Used the Tab view unprompted
- [ ] Argued over a choice card (Full only), and whether it was the same pick every time

**Loss** (question 4)
- [ ] A run lost: stretch ____ , breaches at the end ____ / 10, and did they say "it was that earlier stretch"?
- [ ] The breach counter noticed before it got to 7 or 8?
- [ ] "Try the stretch again": did they use it, or leave?

**Feel**
- [ ] Stutter or lag (web): when, how bad
- [ ] Anything that read as noise (birds, jars, shouts, sheep) — Simple turns most off, so compare

---

## 3. Questions at the end (ask out loud, 5 minutes)

1. What was the best moment? What was the most annoying one?
2. Did you ever not know what to do next? When?
3. Did it feel like it was going somewhere, or like more of the same? Which stretch felt most like more of the same?
4. If this were on tonight, would you play the next stretch? Would you ask a friend to play with you? (Yes / maybe / no, and why)
5. Tell me what happened, as if to someone who wasn't here. *(Retelling the story beats, not the controls, is the §5.12 test.)*
6. What could you do that you didn't know about until someone said so?

---

## 4. Follow-up (the only retention measure there is)

The stats are anonymous on purpose, so a return visit can't be linked to anyone. Ask instead. **One message, 48 hours later, to every player:**

> Did you open Nehemiah again since we played? Yes / no. If yes, what made you? If no, what would have?

Count yes / no per group. A group where nobody returned, and nobody could say what would make them, is the answer to question 1.

---

## 5. Reading the play stats

`cd C:\Programming\nehemiah-web\worker; $env:STATS_KEY="…"; node report.mjs 3` (the number is the days to look back). It shows:

- **Funnel:** opened → started a stretch → finished a day → finished a stretch → finished three. The sharpest drop is the headline.
- **Where sessions stopped** (a session ends after 2.5 minutes of silence): which stretch and phase. A stop at DUSK is a natural break; a stop in WORK is confusion or boredom.
- **Full vs Simple, solo vs company**, minutes played, the furthest stretch.
- **Recent sessions** by UTC start time: match them to your notes by the clock.
- **Frames per second in play** (median and the worst tenth).

It can't see: who they were, whether they came back, or anything said aloud. That is what the observer sheet and §4 are for.

---

## 6. Deciding

Fill this in right after the last session. **The thresholds below are proposed now so the numbers can't be bent afterwards: change them before the first session, never after.**

| Question | Evidence | Threshold | Result |
|---|---|---|---|
| 1. Pull past stretch 3 | Groups that reached the end of stretch 3 on their own, and the §4 follow-up | at least 2 of 3 groups per mode reach it, and at least half the players return | |
| 2. A peak in the first ten minutes | The first laugh / shout / near-miss timestamps | at least 5 of 6 groups have a Fellowship moment inside 6 minutes | |
| 3. Simple vs Full | "What do I do?" ticks, Fellowship ticks, groups reaching stretch 3 | Simple wins if its "what do I do?" ticks per group are at most half of Full's **and** its Fellowship ticks are at least 70% of Full's | |
| 4. The breach rule | Runs lost with an early stretch blamed, breaches noticed late | 2 or more such runs: make breaches per stretch, or give a way to win them back | |

**What each result does:**
- *Pull fails, Simple is calmer, Fellowship holds* → ship Simple as the default ("Story"), Full as "Full crew" (GDD §5.23 point 4); the problem is then pace and variety, not rules.
- *Pull fails in both* → the loop needs variety, not subtraction: look at the same-six-units sameness (GDD §6.4 "Next", #4 mid-day events and #6 the walking work front) before any new system.
- *No early peak* → put a half-way wave with a bell into Sheep Gate and move the prologue cards after stretch 1 (GDD §7.1 #5) before touching Next Fest.
- *Fellowship lower in Simple* → bring back one shared decision, not the rules: the ping wheel (GDD §7.1 #4) is the cheapest.

| System | Keep / tune / cut | Why (what we saw) |
|---|---|---|
| Simple game as the default | | |
| Concept ladder (one new thing per stretch) | | |
| Cumulative breach rule | | |
| First stretch: timber and stone only, no posts | | |
| The prologue before day 1 | | |
| Anything that read as noise | | |

**Rules for deciding (unchanged):** **cut** what causes friction and wasn't named a best moment; **tune** what was missed but liked once seen; **keep** what produced Fellowship. New players outweigh the dev circle on clarity.
