# Playtest 3 — plan and questionnaire

**Goal:** find out which of the first-pass systems (GDD §5.6–5.8) earn their place, and cut or tune the rest before the saboteur (§5.9). Each system gets **keep / tune / cut**.

**Who:** at least one session with people who have **never played** (ideally the audience: a family or friends who play casual co-op, mixed skill). Dev-circle players can't judge the learning curve any more. The web build (nehemiahgame.com) is the cheapest way in.

**Rule for observers:** don't help, don't explain. Write down the moment someone is confused, and what they said. The confusion is the data.

---

## 1. Sessions

Each run is one section, so everyone plays about the same length. Swap the flags between runs; the host's flags go to everyone who joins.

The host runs a **debug build** on desktop: `--day=N` and `--instant-build` only work there (`--no-waves` / `--no-sun` / `--no-posts` work in any desktop build). The web build takes no flags, so first-time players on the web play **run A only**, which is the part that matters most for them.

| Run | Start | Flags | What it tests |
|---|---|---|---|
| A | `-- --day=1` (Sheep Gate) | none — everything on | Baseline. New players start here, with no tutorial unless they ask for it |
| B | `-- --day=9` (Jeshanah, brutes) | `-- --no-waves --no-posts` | Old trickle, no posts: does the build/defend tension feel better or worse? |
| C | `-- --day=9` | `-- --no-sun` | Per-day slices instead of the sun clock: is the whole-stretch goal clearer? |
| D | `-- --day=24` (Valley Gate, raiders) | none; Settings → Day info → **Plaques** | Plaques vs the scribe and watchmen, at peak pressure |

Optional, if there's time: run A again with `-- --instant-build` (debug build) to recheck hands-on building with new players.

No flag yet for birds, breakables, lamps, taunts or the wall cam — watch them in every run. If one looks like a cut, add a `--no-…` flag and confirm it in the next playtest.

---

## 2. Observer sheet (fill during play)

Tally marks are enough. Note the run letter and the time.

**Friction**
- [ ] Someone asks "what do I do now?" / "where does this go?"
- [ ] Hit while building, and complains about it
- [ ] Doesn't see a breach or a battered wall until it's too late
- [ ] Doesn't notice the sun is low (in-world mode)
- [ ] Can't find the day count or how much of the stretch is left
- [ ] Stuck: wrong side of a wall, can't pick up, can't reach a pile
- [ ] Downed and nobody noticed for 5 s+

**Fellowship** (the core — want lots of these)
- [ ] Someone calls out a job ("I'll get stone", "cover me")
- [ ] Someone saves or helps up a crewmate
- [ ] Laughter or shouting that comes from the co-op chaos

**Tower-defence layer (§5.6)**
- [ ] Wave bell heard and reacted to (they turned to face it)
- [ ] Watch post raised — in which minute?
- [ ] Watch post fed after it ran dry — or left empty?
- [ ] Everyone builds during a wave and lets the posts defend (they skip the fighting)

**The world tells it (§5.8)**
- [ ] Looked at the scribe's scroll or a watchman's call on purpose
- [ ] Breaks jars instead of working (count)
- [ ] Mentions or reacts to the birds (good or bad)
- [ ] Wall cam: watched it, or tried to skip / moved on

**Ending a section**
- [ ] Tally screen + story screen felt like one screen too many (they sighed, or said so)
- [ ] Knew why they won / lost

---

## 3. Questions after each run (ask out loud, 2 minutes)

1. What was the best moment? What was the most annoying one?
2. Did you ever not know what to do next?
3. Did the day feel too short, too long, or about right?
4. When you lost something (a wall piece, a crewmate, the run), did you see it coming?

## 4. Questions at the end (all runs)

For the players, in plain words:

1. Which run was most fun? Which was least? Why?
2. The bell and the groups of enemies (runs A, C, D) vs enemies coming one at a time (run B) — which did you like better?
3. The towers with a slinger on them: did you bother building them? Did they help?
4. The whole stretch as one goal with the sun going down (A, B, D) vs a set job each day (C) — which was clearer?
5. The scribe and watchmen shouting vs the boards in the corner (run D) — which one did you actually read?
6. Did anything on the screen feel like noise? (Birds, jars, shouts, anything.)
7. Was anything unfair?
8. Would you play the next section? Would you ask a friend to play it with you?

---

## 5. Deciding

After the sessions, fill this in and copy the result into GDD §5.

| System | Flag | Keep / tune / cut | Why (what we saw) |
|---|---|---|---|
| Waves | `--no-waves` | | |
| Sun clock / whole-stretch goal | `--no-sun` | | |
| Watch posts | `--no-posts` | | |
| Hands-on building | `--instant-build` | | |
| In-world day info vs plaques | Settings | | keep one only |
| *In good time* mark | — | | overlaps the sun clock |
| Tally + story at section end | — | | fold into one screen? |
| Taunts | — | | |
| Wall cam | — | | |
| Breakables | — | | |
| Birds | — | | |
| Lamps at dusk | — | | (cost is web draw calls, not fun) |

**Rules for deciding**
- **Cut** if it causes friction and nobody names it as a best moment
- **Tune** if players missed it (didn't see or hear it) but liked it once they did
- **Keep** if it produced Fellowship moments (calls, saves, laughter) or a best moment
- New players outweigh the dev circle on anything about clarity; the dev circle outweighs them on anything about depth over 52 days
