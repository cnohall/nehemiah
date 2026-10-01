# Nehemiah: The Wall — Game Design Document
**Version 0.6 | September 2026**

---

## 1. Overview

Cooperative 2–4 player HD-2D isometric action-strategy set in 455 BCE Jerusalem. Players embody the workers and guards of Nehemiah's rebuilding effort, racing to reconstruct the city wall in 52 days while repelling Sanballat's and Tobiah's increasingly desperate forces. Tone: urgent and collaborative — think Overcooked meets tower defense, grounded in Biblical history.

**Core loop** (sun clock, §5.6): the campaign is 12 stretches of wall (§6), each worked over its days (~4).
1. Dawn — enemies come in a trickle plus announced waves
2. Players fight, carry materials and build at the same time: deliver a stage's loads, then stand at the wall and work it up (§5.4). The stretch goes up in build order (the work front)
3. A day ends when the sun sets ("till the stars appeared", Neh 4:21) or when the whole stretch stands; days left over are skipped and the next stretch starts tomorrow

**Platform:** desktop (Steam) first, built so a console / mobile port stays cheap: every action works on keyboard + mouse and on a gamepad, UI is navigable by pad, button hints follow the device in use (`InputMode`).

**Win condition:** The last stretch (Miphkad Gate) stands by day 52 and the circuit is closed
**Loss conditions:**
- 10 enemies get into the inner city over the run (`GameState.MAX_BREACHES`, a wrecker pours through a wall knocked back to bare foundation, or a runner goes through a gap)
- Nightfall on a stretch's last day with it unfinished ("The stars appeared")
- Either way: "Try the stretch again" restarts at that stretch's first day

---

## 2. Enemy Types

Three types, unlocked over the campaign (`wave_manager.gd`). Spawn rate and max alive scale with day and crew size.

**Difficulty** (host picks on the gathering screen, `Settings.DIFFICULTIES`): Gentle / Standard / Hard. *pace* ×0.7 / 1.0 / 1.3 multiplies spawn rate, max alive and wave/surge size on top of each section's pressure; *harm* ×0.7 / 1.0 / 1.25 multiplies every enemy blow (workers and wall). **Bots count by skill** toward the enemy's crew size (Apprentice 0.5, Builder 0.75, Master builder 1.0), so adding weak bots no longer adds a full worker's foes. Building costs still use the whole crew. (Added 28 Sep 2026)

| Type | Unlocks | Speed | Health | Damage | Notes |
|---|---|---|---|---|---|
| Scout | Day 1 | 3.5 | 40 | 5 | ~50% go for the wall ("wreckers"), rest run for gaps |
| Brute | Day 9 (25% of spawns) | 2.5 | 100 | 15 | Always a wrecker — slow, batters walls |
| Raider | Day 21 (~30% late mix) | 4.0 | 60 | 8 | Fast; ~50% wreckers |
| Saboteur (§5.9) | Day 6 (1 at a time, own timer) | 4.2 | 30 | 0 | Goes for the yard, not the wall: scatters the pile the work needs, then flees |

All but the saboteur attack nearby workers first. A wrecker that knocks a section back to bare foundation pours through the breach.
Debug: run with `-- --day=N` (debug builds) to start at a later day and see brutes/raiders.

---

## 3. Structures

1. **Wall units** (`WallSection`) — stages: framing (timber; beams on beam stretches) → courses (stone) → mortar. Each stage: deliver the loads, then work it up by hand (§5.4). Enemies batter them back down a stage at a time. Broad Wall's are double-thick (§6.3)
2. **Gates** (`Gate`) — two pillars built like wall units, then the **doors step**: deliver timber, work it → doors hang and close the gap. Workers pass through hung doors, enemies don't. Stretches with no gate seal the opening with stone instead
3. **Watch posts** (`WatchPost`, §5.6) — two behind the wall; raise with timber, feed with stone for the slinger on top. Bare again each new stretch
4. **Mortar trough** (`Trough`, mixing stretches) — not built: lime + water in → mortar out after 4 s

Supply: stockpiles in the yard (timber, stone, mortar; per stretch some are replaced by rubble heaps, lime bins and water jars — §6.3). Dropped loads stay on the ground.

---

## 4. Historical Notes

- Wall circuit: Nehemiah 3 order from the Sheep Gate (north-east) — west along the north, down the west side, east along the south, up the east side back to the Miphkad Gate: counterclockwise on a north-up map
- 52 days: Nehemiah 6:15 (Elul 25, 455 BCE)
- Enemy leaders: Sanballat the Horonite, Tobiah the Ammonite, Geshem the Arab
- Persian king: Artaxerxes I; his 20th year (Neh 2:1) = 455 BCE, per Watch Tower chronology (secular dating puts it at 445). Use BCE, not BC
- Workers armed while building: Nehemiah 4:17 ("trowel in one hand, weapon in the other")
- Families stationed behind the wall with weapons: Nehemiah 4:13

---

## 5. Playtest 1 Feedback & Backlog
**25 Sep 2026 — 2-player co-op session**

**Verdict:** Core loop is fun even without sound, in its early state. Keep the loop and polish it; don't redesign.

**Design principle:** Keep it simple, like Overcooked. Overcooked 1 already worked, and Overcooked 2 improved on it mostly with small changes. Add one mechanic at a time and playtest after each.

**Fun check** — every new mechanic's spec opens with this block, filled in before it's built:
- **Fantasy:** does it make you feel more like a builder of Neh. 4:17 — one hand on the work, one on the weapon? Or is it about something else?
- **Kind of fun it aims at** (MDA): pick one or two. Our core is **Fellowship** (the crew shouting at each other) and **Challenge** (build vs defend at once). Sensation / Discovery / Narrative / Submission are welcome as seasoning, but don't let them take the build slots while core ideas wait
- **Where it can go sour:** what frustration can it cause (unclear telegraph, off-screen hit, slow walk, one player stuck at a post)? Does it pay off in relief or triumph, or does it just nag?
- **A/B switch:** the command-line flag that turns it off (`-- --no-…`), so a playtest can show what it adds
- **Kill rule:** what we'd see in a playtest that makes us cut it rather than tune it

**Cut candidates** (settle in playtest 3, `PLAYTEST_3.md`): the *In good time* mark (overlaps the sun clock), plaques vs in-world day info (keep one), tally + story as two screens at a section's end, breakables / birds if they pull players off the work.

### 5.1 Structure
- 12 wall sections × ~4 days each ≈ 48–52 days → matches the Day 52 win condition
- Each section plays like one Overcooked level
- Short clips/cutscenes between sections as checkpoint and reward
  - ✅ **Circuit map** (`CircuitMap`, on the story cards and the section picker): a low-poly 3D diorama of Jerusalem (`CircuitDiorama`, built in code — Kidron/Hinnom valleys, Mount of Olives, whitewashed city, temple, olive groves, land fading into warm haze) with the 12 sections on the ring; labels, marks and the gold line on the current stretch are drawn over it in 2D. Prologue = Nehemiah's night ride (Neh 2:13-15), every stretch broken. Each section card: the stretch just finished rises in gold, the next one pulses, and the three foes watch from their lands. ✅ Finale (ending story, first card): the Miphkad stretch rises, a gold line runs the whole ring back to the Sheep Gate, and the foes fade (6:16)

### 5.2 Next (low cost, high impact)
1. ✅ **Sound** — done: footsteps, pickup/drop/deposit (per material), dash, sling throw/hit/miss, enemy swing/death, wall build/hit/crumble, alarm bell on breach, jingles for day start/end + win/loss. Kenney CC0 packs, `Sfx` autoload
   - **Music** — two moods crossfaded by day phase: *calm* (sparse plucked strings over a drone) for menu/dawn/dusk, *work* (steady warm pulse) while enemies come. Criteria: ancient Near-East palette (lyre, pipe, frame drum), dignified not martial, no vocals/liturgy. Ducks under jingles; own volume slider. Tracks in `assets/audio/CREDITS.md` — one is CC-BY, needs an in-game credits line
2. ✅ **Dropped materials stay on the ground** (Overcooked-style) — done: [G] drops at your feet, downed workers drop their load, [E] picks up (nearest of ground item vs stockpile). Cleared when a new wall section starts
3. ✅ **Enemies damage the wall if not killed** — done: "wreckers" (all brutes, ~50% of others) march on the nearest built wall and batter it. Makes fighting and building compete for the same players. Gives the loss condition a gradual build-up instead of a single breach
4. ✅ **Movement feel** — done: dash on [Space]/[Shift] (short burst, 0.7 s cooldown, works while carrying)

5. ✅ **Game feel pass** — gamepad (stick/d-pad, A pick up · B dash · Y drop · RT sling · right-stick aim · Start menu), analog walk, 0.15 s input buffer, camera look-ahead + shake (toggle in Settings), hitstop on sling hits, pad rumble. Camera a little closer (size 22)
6. ✅ **Rewarding day end** — the last stage lands in a breath of slow motion; enemies turn tail and run (shrink away in a puff); today's finished units bounce and puff one after another; the crew throws both arms up (the fallen get back up, builders down tools); light turns gold and the camera leans in. Then a tally card counts up the day: time, loads carried, foes felled, how many slipped through, and in co-op each worker's share (the day's best carrier / best shot in gold). The last day of a section reads "The <gate> stands". Dusk 6 → 9 s. No score, no stars — just the day's numbers

### 5.4 Hands-on building (Overcooked "chopping") — ✅ built, A/B with `-- --instant-build`
Delivering the last load no longer raises a stage by itself: someone has to **stand at the wall and work it**.
- The one who brings the last load starts working automatically; anyone else presses [E]/A at the wall ("Build [E]")
- Working keeps going while you stand still (no holding); moving, dashing, dropping, the sling or **a hit** stops it. Progress is kept
- Extra hands help: +70% each, max 3 at one site ("Enough hands here")
- Hands are full while working — builders can't sling. Guarding the builders is the Neh. 4:17 moment
- **Sword** (Neh. 4:18, "every builder had his sword girded by his side"): same button as the sling. A foe within 2 m → a quick cut instead of a wind-up: 20 damage to every foe in a 130° arc in front, shoves them back (scout 1.3 m, raider ~1 m, brute ~0.45 m), 0.45 s cooldown. Sling stays the safe way to chip at range; the sword pays better but means standing in reach. Unlimited sling stones stay — the stone-vs-wall choice lives in the watch posts
- The next stage rises block by block (doors plank by plank) as the work fills; a knock + dust per stroke
- Time per stage for one worker: framing 2 s, courses 3 s, mortar 2 s, doors/seal 2.5 s; solo works 25% faster. With trades on (§5.10) all ×1.6, and a trade's own work back at these times
- To keep days the same length, each stage costs one load less (never below 1); beams unchanged
- **No tool.** A tool is a fetch step with no decision in it (Overcooked only uses tools when they're scarce). Could return as a one-section twist (a single shared plumb line)
- Watch in playtests: solo pacing; whether hits interrupting work feels fair or nagging

### 5.5 Readability & HUD (vertical-slice pass)
- Bold player-colour ring; in multiplayer a small diamond in the player's colour over each head (pulses when downed)
- Carried loads 35% bigger; stone a shade darker than the sand, mortar in a reed basket
- Day plaque top-left (top-centre hid the wall being built). No enemy counter — off-screen pointers show threats
- Controls card shows keys or pad buttons, whichever is in use
- Gamepad host starts the day from the pause menu ("Begin the work", focused)
- Join: friends already in a lobby are listed with one-click Join; pause menu opens Steam's invite overlay
- Playtest feedback (28 Sep 2026): "bit of a learning curve — can't see how to add bots, pause the game". Answer: with no other people connected (solo, or bots only), the menu really pauses and the controls card says "Pause · menu"; online it stays "Menu" and play goes on. The host's difficulty / bots / bot skill rows are in the pause menu too (pad-navigable, work mid-day). While gathering with no bots, the gather panel says "Short of hands? Add bots to the crew." Still open: no tutorial / first-run prompts beyond the controls card and "Next:" line

### 5.6 Tower-defence layer — ◐ first pass, needs playtest
Three rules, each on by default and each switched off from the command line to A/B it (`-- --no-waves`, `-- --no-sun`, `-- --no-posts`; the host's choice goes to everyone who joins). Test: `tools/td_test.gd` (run with `--day=4` for the last-day loss).
- **Waves** (`WaveManager`): the trickle thins (×2) and the enemy comes in announced waves — bell + "Wave" pointer 5 s ahead, then a pack from one spot every 38 s (day 1) → 26 s (day 52). Pack = 2 + day/10 + one per two extra workers, × section pressure; from day 21 a wave comes at two spots, one on each half of the front. Tuned so the total count stays about the same — what changes is the rhythm (lulls to build, rushes to defend). Valley Gate keeps its own sharper surges (its twist)
- **Sun clock** (`GameState.sun_*`, `DayDirector._tick_sun`): "from the rising of the morning till the stars appeared" (Neh 4:21). With the sun on there are no per-day slices: **the whole stretch is the goal** (plaque: "The stretch 2 / 6"), worked over its days, and every day of a section has the same light = section par ÷ its days × `sun_slack` (1.2 by default; 1.0 = the days add up to par; `-- --sun-slack=1.3` to try another; solo ×1.25). **Work front** (`WorkFront`): the stretch goes up in build order (gate first, then outward) — only the first unfinished units are open, one per two workers — so effort isn't spread over six half-built units; a knocked-down unit reopens in its place. Bots and the "Next:" line follow the front; people may still deliver anywhere. A day ends at the stars, or when the stretch stands — then its days to spare are skipped and the next stretch starts tomorrow ("Finished with 2 days to spare"). Nightfall on a section's **last day** with the stretch unfinished loses the run ("The stars appeared"). Day plaque shows a sun arc + time left; the last quarter warms the light and says "The sun is low". (Changed 28 Sep 2026 from "each day's slice, leftovers carried over": bots and players both lost track of what the day was for)
- **Watch posts** (`WatchPost`, two behind the wall at x = ±8): "I set the people by their families" (Neh 4:13). Bring timber and work it up → a slinger climbs on. Feed it stone: one load = 6 throws, holds 3 loads. It throws at the nearest enemy within 12 m every 1.7 s for 9 damage (a scout takes five, a brute a dozen) — chips and staggers, never holds a flank alone. Stone for the post is stone not in the wall: that's the choice. Bare again on each new section. Tag pulses "Out of sling stones" during the work
- Watch in playtests: does waves' rhythm make building lulls feel safe (less Neh 4:17 tension)? Is `sun_slack` 1.0 fair for 1–4 players? Do posts get fed, or ignored? Do they let the crew skip fighting?
- Bots raise and feed posts: the wall comes first, a post gets what no wall wants (one load at a time), and a post that has run dry gets the next stone. They only raise a new post while the wall is on track (not on the last day, and at least as far along as the days gone by)
- **Salvage**: rubble heaps also regrow one stone every 20 s during the work (up to their stock), so a stretch can slow down but never run dry ("Digging out more")
- Open: section rating's "In good time" overlaps the sun now

### 5.7 Playtest 2 Feedback — ✅ built, needs playtest 3
**28 Sep 2026 — 2 human players, 0 bots.** Tests: `tools/playtest2_test.gd`, `tools/again_test.gd` (offline + `--host`/`--client`), `tools/tutorial_test.gd`

**Waiting for players (one shared widget):**
- ✅ **Tally card waits for everyone** (important). One ready check in `DayDirector` (`ready_changed`, `mark_ready`, `force_ready`) serves the story cards and the dusk tally. The tally stays up (after a 4 s minimum for the cheer) until every person in the scene is ready; the title screen's bot crew still moves on by itself after 9 s. At dusk [E] no longer picks things up. Still two screens at a section's end (tally, then the story); fold them together only if that still feels clunky
- ✅ **Ready state** (`ReadyRow`): hold [E] / A (0.6 s, a bar fills) or click to say you're ready; with company, a chip per person (colour, "You" or their trade, a drawn tick when ready), "Waiting for N builders", and the host's "Begin now". In the story, with company, Esc reads "I'm ready" instead of "Skip" (the old skip-vs-continue confusion)
- ✅ **Loading panel**: `NetworkManager.crew_info` — the server keeps who's in the session (Steam name, still loading or in) and mirrors it to every peer; a client introduces itself on connect. The HUD shows "<name> is joining…" top centre while anyone loads; player cards and ready chips show Steam names (the trade when there's none) and a dimmed "joining" state

**Flow:**
- ✅ **Section ends when the stretch stands.** Players felt it ran to the end of the day. The code already ends the day the moment the last unit stands (`_on_stage_changed`); the likely culprit was the "Next:" line, which said "The day's stretch is done" whenever the player had no open site, even with pieces left. Now it only says so when it's true, otherwise counts what's left ("2 pieces still to finish — look for the amber footings"), says "Last piece!", and a finished piece knocked back down flashes the day plaque with a line saying so
- ✅ **Watch posts raised while gathering carried into day 1** (`section_changed` doesn't fire going from gathering to day 1). Posts are now reset at every fresh section's dawn
- ✅ **Stuck outside a finished wall.** Hung gate doors are on their own collision layer (16), which enemies and the nav bake collide with but workers don't: workers walk through, enemies still can't. Anywhere else, [E] against a finished wall (or sealed infill) with nothing else to do **climbs over** it (either way; carrying is fine, a beam isn't). Only finished walls, so a press at a half-built one never hops you to the wrong side

**Combat:**
- ✅ **Revive isn't discoverable.** **No self-revive:** a teammate (or bot) has to help you up. A "Help up [E]" tag pulses over a downed worker for everyone else. The 8 s countdown only runs when nobody is left standing (solo, or the whole crew down). Bots will cross the whole site to help (range 16 → 60 m)
- ✅ **Full health on revive** (`REVIVE_HEALTH` 0.5 → 1.0)
- ✅ **Breaches deeper into the city**: `BREACH_Z` 13.5 → 21 (goal 15 → 23), well behind the stockpiles, so a runner through a gap can still be chased down
- ✅ **Bug: running on the spot on the loss / story screen**: input stopped but the animation wasn't updated, so the last run cycle kept looping

**Content:**
- ✅ **Play again**: `Highlights` grabs a small still at the run's moments (a stretch standing, a wall knocked back, a breach, someone down or helped up, each dusk; 14 kept, the least worth keeping dropped first) and the end screen plays them as a captioned slideshow. Buttons: Try the stretch again (campaign loss: restarts at the lost stretch's first day) / Play again (campaign win) / Play it again + Next stretch (section replay). The host's pick decides, or a majority of the people; Return to Title stays personal. Every peer reloads the game scene together (`DayDirector._restart`); clients re-ask for the roster until the host's new scene answers. A true 3D replay would need recording and re-simulating everything: not now
- ✅ **More dancing**: standing still at dusk or after the win, each worker dances, one per crew slot — dabke stomp, clapping step, arms-up sway (Neh 12:27, the dedication "with gladness… with singing")
- ✅ **Optional tutorial**: "Learn the Basics" on the title — a solo practice at the Sheep Gate, the priests' stretch beside the temple (Neh 3:1), in 9 steps that each wait for the player: walk, dash, carry, deliver, build, the sling against one scout, help a fallen crewmate up, then "Let us rise up and build" (Neh 2:18). `GameState.tutorial`: no waves, no story, no sun clock, nothing saved

**Later:**
- ☐ **Cross-play** between web, mobile and Steam: look into it after the Steam launch. It needs one shared transport (WebRTC or a WebSocket relay via the existing Cloudflare DO); Steam/ENet/EOS don't talk to each other. Keep lobby code from blocking it

### 5.8 The world tells it — ◐ first pass (29 Sep 2026), needs playtest 3
- **Diegetic HUD** (Settings "Day info": *In the world* default, *Plaques* brings the old day/threat plaques back). The **sun** sinks from mid-morning (61°) to 22° and swings west as the daylight runs out — shadows lengthen toward the stars (`DayLight`). A **scribe** (`Scribe`) at a desk by the yard keeps the record on a scroll over his head: day and stretch, one block per piece (inked when it stands), red strokes for each one through, out of ten; he calls pieces standing or falling. Two **watchmen** (`Watchmen`) on timber stands at the ends of the stretch (Neh. 4:9) call waves and their side, a battered wall, the first brute/raider of the day, a breach, the sun low; a call from off-screen slides in from the edge (`Shout`, a `WorldTag` kind). The "Next:" line stays as an ink-rimmed caption low on screen. Watch: do new players still find the day count and breaches?
- **Taunts** (`Taunts`): a herald of Sanballat's outside the wall calls the taunt across it (as his servant came with the open letter, 6:5) — at the start of the work and every 40 s until the stretch is half built; the call slides in from the screen edge. Sheep Gate (2:19), Jeshanah / Broad Wall / Tower of Ovens (4:2-3), East Gate (Sanballat's letter, 6:6). (The line used to be daubed on the ground outside the wall too; cut Sep 29 2026, it read strangely)
- **Wall cam**: when a stretch stands the camera runs along it (3.2 s) and a dedication tablet rises on each piece with the name of whoever carried most to it (Steam name, else the trade). Server credits each load to its unit (`DayDirector.note_load(peer, site)`); the tally waits for the run. Free trailer material
- **Scribe's map** (`CircuitMap.aged`, `GameState.chronicle`): the circuit map on the story cards and the end screen wears with the run — edges darken with the days, folds at 4 and 8 sections, an ink blot where the enemy got in, a lamp-oil ring on stretches worked till the stars or past par, a margin note per stretch ("2 got in", "worked till the stars", "1 day to spare", "rebuilt what fell"). The end screen is the final map, words on a parchment column at left
- **Explore Jerusalem** (`Festival`, title menu, solo offline, nothing saved): the Festival of Booths after the wall (Neh. 8) at the Water Gate. Ezra reads from a wooden platform (Lev. 23:40, 42; Neh. 8:15); fetch **branches** from the slopes outside and build five booths — broad place, courtyards, by the well, the temple court (8:15-16); carry **portions** to four with nothing prepared (8:10); talk to Nehemiah, a Levite, Shallum's daughters, Meremoth, a priest, the gatekeeper, children (`Folk`, [E]); go up to the **temple** (`Temple`: walled court, sanctuary facing east, altar with its fire). Journal ticks it off; all done → "There was very great gladness" (8:17). Not the Sabbath: Neh. 13:15-19 forbids carrying loads on it. Not the zero-menu start either — first launch should still meet the real loop (the practice); revisit if players want a gentler first minute
  - **Round the wall** (30 Sep 2026): the whole circuit is walkable — walk off either end of a stretch and you come to the next in Neh. 3's order (a fade, the ground changes to that section's terrain), round from the Miphkad Gate back to the Sheep Gate; a signpost at each end names the next gate. Every stretch has the builders Neh. 3 names there (quoted), townsfolk and a booth site; three hold the feast in full: Water Gate (Ezra), Sheep Gate (the temple, moved here beside the priests' stretch, 3:1), Fountain Gate (pool of Shelah, branches from the King's Garden). Progress holds across stretches; the journal adds "Walk the wall round — n of 12 gates". Goals: 5 booths, all 4 portions, 8 builders met, Ezra, the temple. Next, if it earns it: a city behind the wall that differs by district (City of David south, temple mount north) instead of the same streets everywhere
- **Breakables** (`Breakables`, `Breakable`; 29 Sep 2026): clay water jars, tall storage jars and reed baskets of figs stand about each stretch — by the landmarks first (jars beside the potters' stalls, baskets by the fish stalls and ovens, water jars at the Pool of Shelah and at each priest's door, olive baskets under the Kidron trees), then a few loose clusters inside the wall and out on the enemy's side. They rock when anyone brushes past; a sword cut, a sling stone or a dash breaks one, and so does a raider trampling through on the way to the wall (Zelda's pots, Hades' urns). Sherds, a wet patch that dries, spilled grain or scattered figs stay till dawn, when fresh ones are put out. No collision, nothing inside, no score — set dressing that answers back. The attack press cuts at a pot at your feet only when no foe is in sling range, so it never steals a throw. Watch: does breaking them distract from the work? If players want a reason, the next step is a rare fig cake that heals a little (1 Sam. 25:18)
- **Birds** (`Birds`, `Bird`; 30 Sep 2026): flocks of house sparrows and rock doves (Matt. 10:29; Lev. 1:14) peck and hop on open ground each side of the wall (doves only on the city side). A worker walking into one puts it up; so do a foe coming on (the flocks outside lift before the enemy reaches the wall, an early warning shown in the world) and anything loud: a dash, a sword swing, a jar breaking, a wall piece falling, the horn, a breach (`Sfx.STARTLES`). One flock's wings can put up the next. They climb away sideways on screen (not at the camera), and come back once it's been quiet round their spot for 12–22 s. Sparrows chirp, doves coo. Local to each peer, nothing replicated. Watch: are the flushes readable at play zoom, and are they fun or just noise? Web: ~30 birds of 6 meshes each, so check draw calls
- **Lamps at dusk** (`ScatterLayer.set_lamps`, `DayLight.lamps`): as the sun sinks (evening 0.3 → 0.95) the house windows light one by one with a warm oil-lamp glow, all of them once night falls ("from the rising of the morning till the stars appeared", Neh. 4:21). Out at dawn. The birds go to roost as the lamps come on and come back at dawn
- Tests / shots: `tools/hud_shots.gd`, `wallcam_shots.gd`, `festival_shots.gd`, `map_age_shots.gd`, `breakable_test.gd`, `birds_test.gd`, `birds_shots.gd`
- New strings are English only so far — run the i18n extract for es / pt_BR / de / ko

### 5.9 Saboteur — ◐ first pass built (30 Sep 2026), needs playtest 3
**Fun check:**
- **Fantasy:** guarding the work, not just the wall — "cause the work to cease" (4:11) is what you're stopping
- **Kind of fun:** Fellowship first (someone has to leave the wall — who?), then Challenge (a third thing to watch)
- **Where it can go sour:** one player parked in the yard all day; a scattered pile nobody saw happen feels unfair (the watchman call and pointer have to carry that)
- **A/B switch:** `-- --no-saboteur`
- **Kill rule:** if the crew in playtests just ignores him, or one player guards the yard all day even after we tune the interval
**Why:** all three enemy types ask the same question — reach the wall before it's battered or slipped through — and differ only in stats. Days 1–8 are scouts only. The saboteur is the first foe that goes after a *different part of the work*: the supply, not the wall. It gives the crew a new job, "keep the yard", without new stats or weapons.

**Grounded in:** "Our adversaries said, 'They will not know or see, until we come in the middle of them and kill them, and cause the work to cease.'" (Neh 4:11, WEB). Their aim was to stop the work, not to fight it out.

**Behaviour** (`Type.SABOTEUR` in `enemy.gd`, server-authoritative like the rest):
1. Spawns with the trickle on the enemy's side, never in a wave pack (he comes quietly)
2. **Gets in:** runs for the nearest gap (an unbuilt unit or a gate without doors). No gap left → he **climbs** a finished unit, choosing the one farthest from any worker: a 2.5 s climb, in plain view; any hit knocks him off and the climb starts over
3. **Picks a pile:** the stockpile whose material the work front needs now (`WorkFront`'s open units); ties → the nearest. Skips beam piles (too heavy to throw about)
4. **Scatters it:** 1.5 s at the pile, then the pile is **scattered**: loads strewn over the pad, nothing can be taken from it. Rubble heaps and lime bins scatter the same way; water jars are knocked over
5. Scatters **two piles at most**, then flees back out the way he came (existing flee: `FLEE_SPEED`, off at `FLEE_Z`). Never counts as a breach: the harm he does is lost time
6. **Doesn't fight.** He ignores workers (no aggro), doesn't batter walls, has no weapon. A worker in reach just gets dodged around

**Tidying a scattered pile:** the Neh. 4:17 cost. Stand at the pile and press [E] / A ("Tidy [E]"), then work it like a wall stage (§5.4): 2 s for one worker, extra hands +70%, moving or a hit stops it, progress is kept. Tidied → the pile works again. A scattered pile's tag pulses "Scattered — tidy [E]" for everyone.

**Stats:**
| Speed | Health | Damage | Knockback felt |
|---|---|---|---|
| 4.2 (fastest) | 30 (2 sling hits, 2 sword cuts, 4 post shots) | 0 | 1.2 (light) |

**Unlock and count:** day 6, the second day of the Fish Gate, so beams (the section's twist) get one day to themselves. At most **1 alive**, and at most one every 50 s, through day 20. From day 21, 2 alive with 3–4 workers. Not scaled by section pressure; difficulty *pace* scales the interval. Water Gate (night watch): he comes out of the dark like the rest, and a torch by the yard is the answer.

**Readability:**
- Silhouette: slim, crouched run, dark hood, an empty sack over one shoulder, no spear or shield. Same goat-hair cloth + oxblood outline as the other foes (`CharacterRig` look "saboteur")
- The first one of the day gets a **watchman call** ("One's slipped in — the yard!"), and an off-screen pointer "Saboteur" follows him while he's inside the wall
- The strewn loads on a scattered pile are clearly spilled, not stacked: at a glance the pile reads as unusable
- The dusk tally adds a line only on days it happened: "Piles scattered: n"

**Bots:** a bot that needs a scattered pile's material tidies it before anything else. A bot with empty hands within 10 m of a saboteur chases him with the sword. Bots don't guard the yard ahead of time.

**Tutorial:** none. The watchman call, the pointer and the "Tidy [E]" tag teach it the first time (as the brute's first appearance does today).

**Build notes:**
- `SupplyPile`: `scattered` bool, synced like `count`; `request_pickup()` refuses while scattered; `tidy_progress` synced for the build-style bar. A strewn-loads mesh layer toggled on the pad
- `enemy.gd`: a saboteur branch in `_pick_target` (pile, not player/wall), the climb as a timed state, `_fleeing` reused
- `WaveManager`: its own timer for saboteurs, apart from the trickle and the waves
- A/B switch `-- --no-saboteur`, like `--no-waves`. Debug `-- --day=6` to see one on day 1 of the run
- Test `tools/saboteur_test.gd`: gets in through a gap, scatters the right pile, pickups refused, tidy restores, flees after two, climbs when there's no gap, knocked off by a hit
- New strings English only at first; run the i18n extract for es / pt_BR / de / ko

**Not in v1:** stealing dropped loads, tipping the mortar trough, setting fires (Neh 4:11 says "cause the work to cease", not burn it), tidying while carrying.

**Watch in playtests:**
- Does one person end up parked in the yard all day? (He should be something that interrupts you, not a post to stand at.) If so: longer interval, or he only comes in during waves
- Is 2 s of tidying felt, or ignored? Is the climb readable enough to stop before he's over?
- Solo: is it a fair tax, or does it wreck the sun-clock par? Tune `sun_slack` against it, not him
- Does it hide the archer's job (guarding builders) when both are in? Archer spec waits for this playtest

### 5.10 Trades — ◐ first pass (30 Sep 2026), needs playtest 3
**Fun check:**
- **Fantasy:** the crew of Neh. 4 as it was: builders, burden-bearers (4:10), craftsmen, and those behind them with the spears (4:16). *You're* the carpenter, not just worker #3
- **Kind of fun:** Fellowship ("you frame, I'll haul"), a little Challenge (who covers the job nobody is quick at?)
- **Where it can go sour:** a crew waiting for "the mason" instead of just laying stone; solo feeling locked into one trade; four people picking the same one
- **A/B switch:** `-- --no-trades` (host's choice is sent to joiners, like `--no-waves`)
- **Kill rule:** players ignore their trade entirely (the perk is invisible), or wait around for the right trade instead of working

**Rules** (`Trade`, `scenes/shared/trade.gd`):
- **Nobody is locked out of anything.** Every trade can carry, build, fight. A trade only makes one thing faster (Overcooked has no roles; this is the softest kind)
- **Work is longer:** every stage's hands-on time ×1.6 (courses 3 → 4.8 s, framing 2 → 3.2 s, mortar 2 → 3.2 s, doors 2.5 → 4 s). **A trade's own work runs ×1.6**, so the specialist works at the old pace and everyone else is slower. More time at the wall = more Neh. 4:17 (the builders are exposed; someone has to guard them)
- **Builder** — stone stages (courses, the stone seal) ×1.6
- **Carpenter** — timber stages (framing, beams, gate doors, watch posts) ×1.6
- **Water carrier** — walks loaded ×1.25 (5.5 → ~6.9; running is 8). Every load, not just water. Beams unchanged (the pair's tether)
- **Overseer** — sword and sling ×1.6 damage (a full-charge sling fells a scout; sword: raider 2 cuts, brute 4)
- Mortar has no specialist: always the slow stage, a job anyone takes
- Extra hands: the quickest at the site counts in full, each other hand adds 70% *of their own pace* (`BuildWork.hands`)
- Loads, par and `sun_slack` are unchanged: bot run on the Fish Gate took 196 s with and without trades (the longer work is paid back by the specialists)

**Choosing:** "Your trade: …" in the gather panel and the pause menu (click steps to the next; a caption says what it's quicker at). Anyone, any time; remembered in `settings.cfg` (`Settings.trade`, -1 = your place's own, the old default). Travels in `NetworkManager.crew_info` (`choose_trade`). Duplicates are allowed — no lobby arguments; four carpenters just have slow stone. **Bots take the trades nobody holds** (`Trade.assign`), so solo + 3 bots is always the full crew. The look follows the trade (`CharacterRig.worker_look(trade, colour)`); the colour stays the slot's.

**Bots:** overseer is first on guard when foes close on the work; water carrier fetches while anything is wanted; builder and carpenter go to their own work first. Any of them falls back to whatever is open.

**Watch in playtests:**
- Do people notice their perk without being told? (If not: a small tag at the wall "Carpenter's work" or a faster strike sound)
- Does the crew split up by trade, or still swarm? Either is fine; waiting for the specialist is not
- Is 4.8 s of courses for a non-builder dull, or tense? Tune `WORK_MULT` before `PACE`
- Solo: is Builder the right default? Should solo work get the ×1.6 at all (`SOLO_WORK_MULT` already makes it 25% quicker)?
- New strings English only; run the i18n extract for es / pt_BR / de / ko

### 5.11 The pull to day 52 — ◐ first pass (30 Sep 2026), needs playtest 3
**Feedback (friends, 30 Sep 2026):** fun for 2–3 stretches, then no pull to finish. It was often unclear what a player could do (two to a beam, and so on).

**Diagnosis:**
1. **Nothing brought people back after a session.** A campaign is about 1.5 hours, and Host always started at day 1. Most crews stop at a stretch's end and never return
2. **Mechanics were announced, not taught.** One line on the dawn banner, read while scouts were coming
3. **The middle twists were chores.** Salvage, thick and haul made the walk longer or the loads heavier, with no new decision
4. **No escalation you could see.** The three leaders appeared only on story cards
5. **Marks bought nothing.** A number on the card and nothing more

**Built (each part can be cut on its own after playtest 3):**
- **Continue** (`GameState.campaign_save`): the run is saved at the dawn of each new stretch after the first, with its day, marks and chronicle, and cleared on the win. The title shows "Continue — Broad Wall, day 13" first, and Host becomes "New Game". "Try the stretch again" restores the marks and map the same way. A new run doesn't overwrite the save until it reaches its second stretch. Test: `tools/continue_test.gd`
- **Twist cards** (`TwistCard`, a StoryData slide per twist new to the section, after its card): three drawn panels with a caption each, e.g. *a beam dragged alone goes slowly → a friend takes the other end [E] → carry it together*. They're part of the story, so the ready check makes the whole crew see them before the work starts. Shots: `tools/twist_card_shots.gd`
- **What can I do here?** (`ActionLens`): hold [Tab] or View (rebindable `reveal`). Everything within 16 m that answers a press gets a chip (take stone, work it up, help up, take the other end, hand over, climb over, tidy, don't go with him), plus a chip on yourself for the other buttons. It's listed on the controls card
- **Beam prompt:** while one worker drags a beam alone, its free end says "Take the other end [E]" on every other free worker's screen. Help reach went up from 2.0 to 3.2 m so the end itself is in reach
- **Bot demo** (`BotDemo`): the first time in a section that a bot does something the section brought (holds a beam end, carries lime or water, digs rubble, uses the relay mat), it gets a callout "Watch the carpenter — two to a beam" and an edge pointer
- **Saboteur** (§5.9, first pass as specced): day 6+, own timer, climbs a finished piece if there's no gap, strews up to 2 piles and then leaves. Strewn piles are tidied like a stage (`SupplyPile` + `BuildWork`, `Act.TIDY`). Bots chase him within 10 m and tidy one pile each. There's a watchman call and an edge pointer while he's inside, and the tally says "Piles scattered". `--no-saboteur`. Test: `tools/saboteur_test.gd`
- **Twists with a decision in them:**
  - *salvage:* rubble heaps outside the wall hold twice the stone, in the enemy's reach
  - *thick:* a double-thick piece takes half of every blow, so the extra stone pays back against brutes
  - *haul:* a relay mat halfway (`RelayMat`). A load dropped on it stacks in a free place, so one worker can run the yard end and another the wall end. The water-carrier bot runs the yard end
- **Leaders on the rise** (`Leaders`): Sanballat, Tobiah and Geshem come to a rise outside the wall at the arc's peaks and call across it in their own words (WEB). When the stretch stands, or on the win, they turn and go (6:16). They follow `SectionBeats.beat_fired` when a beat names a leader, and otherwise fall back to Broad Wall, Valley Gate, East Gate and the finale. They never fight
- **The far goal in view:** every tally says "4 of 12 stretches stand · 36 days to the fifty-second"
- **Session log** (`user://sessions.log`): one line per game left, recording where it stopped. It's for playtest 3 (PLAYTEST_3 §4a)

**Not yet:** harder variants of a three-mark stretch (e.g. Broad Wall at night); the title-screen world changing with progress; the finished stretches staying visible from the next one; relay behaviour for people-only crews (the mat works, but only bots are told to use it).

**Watch in playtests:** do people read the cards or skip them? Is the lens used without prompting? Does the saboteur park a player in the yard? Do crews come back to Continue?

### 5.12 Nehemiah's journey, not just the wall — ◐ first pass (1 Oct 2026), needs playtest 3
**Goal:** players leave having lived Nehemiah's arc (burden → hope → ridicule → fear → trouble inside → deception → joy), not "a fun Overcooked". Not overdone: one story layer per stretch, riding the existing story ready check — no new screens or phases.
**Gap found:** the loop dramatised Neh 3, 4 and 6 as mechanics. Missing: prayer under pressure (4:4, 4:9), the trouble *inside* (Neh 5), the open letter and Shemaiah's trap (6:5-13), the Tekoite contrast (3:5, 27).
**Built (data only, no new systems):**
- **Prayer-and-guard:** story cards "Hear, our God" (4:4, after Tobiah) and "We prayed, and set a watch" (4:9, before the horn card); the choice card now quotes 4:9 ("we made our prayer… and set a watch") — it *is* that decision. (It used to misquote 4:19; WEB says "great and widely spread out")
- **Neh 5 at the Fountain Gate** (the breather, §6): three cards before the stretch — the cry of the people, "Give it back", Nehemiah's table. Its own choice pair: *Open Nehemiah's table* (5:17: build +20%, warning −40%) / *Give back their fields* (5:11: −20% harm, posts from dawn, build −15%). Beats: "half" = the families are back on their land (5:12), "last" = quiet in the valley (2:18). Both options are generous; the price is time or watchfulness, never a morality meter
- **Water Gate:** "A second portion" (3:5, 27) — the Tekoite nobles and commoners
- **East Gate:** the open letter (6:5-9) after Ono. **Miphkad Gate:** Shemaiah's temple trap, "Should a man like me flee?" (6:10-13)
- **Playable Neh 5 — hungry households** (`Households`, `scenes/festival/households.gd`; first pass, same day): at the Fountain Gate, a basket stand ("Portion", endless) stands in the yard and three households inside the wall wait hungry, each with its own verse (5:2 many mouths, 5:3 mortgaged fields, 5:4 the king's tribute). Carry a portion, [E] beside them: they cheer and say they'll come back to the wall (5:16). **Each family fed = building +6% for the stretch** (`GameState.households_fed` → `mod("work")`). Optional: nothing ends the stretch if they go hungry. Reuses `Folk`'s portion interface, in its own group `households` (not `build_sites`, so enemies, bots and the work front ignore them); bots don't carry to them. `-- --no-households`. Test `tools/households_test.gd -- --nostory --day=34`, shots `tools/households_shots.gd`. Not synced for late joiners (a joiner mid-stretch sees them all hungry)
  - **Watch:** is it noticed at all with the sun clock running? Does one player become the portion-runner? If it's ignored, raise the reward or the tag; if it's a chore, cut it
**Not yet (in order):** bots that feed them; the margin note on the scribe's map ("fed 3 households"); Shemaiah as a mid-work offer of a safe place that costs the wall; the night ride as a playable opening (2:12-16); Nehemiah present on the site (4:14 before waves); named neighbour crews (§6.4 #5); months on the HUD (Nisan → Elul).
**Kill rule / test:** ask playtesters "what happened?" after a session. If they retell story beats, not scores, it works. If they skip the cards, shorten them before adding more.
**Notes:** new strings English only (run the i18n extract for es / pt_BR / de / ko). `tools/beats_test.gd --day=34` reports "warned pack" FAIL: the Fountain Gate has no packs by design (same before this pass).

### 5.2a Art direction — "slightly Overcooked"
Keep the earthy palette, borrow Overcooked's readability:
- Stations told apart by period-appropriate bases, not colour-coding: stone on a timber pallet, logs on sleeper beams, mortar on a reed mat with spilled lime (bright colour rugs tried and dropped: broke immersion)
- Pulsing cream ring under whatever [E] will act on (Overcooked's counter highlight)
- Squash & stretch on pickup / drop / dash; walls bounce when a stage goes up, shake when hit
- Crisp, warm, saturated lighting; tilt-shift blur kept light
- **Vibrant pass (v0.6)** — reference: Clash of Clans / Overcooked readability, kept to the period palette (no neon):
  - Value ladder: golden-ochre earth (mid) < pale limestone wall and whitewashed houses (light) < characters with dark outlines. The wall is always the brightest thing on the ground
  - Hue contrast: warm sun, cool blue-violet shadows; dusty olive scrub patches and green bushes break up the earth
  - Colour accents from daily life: painted doors (Levant blue-green, indigo), saturated awnings, rugs drying on flat roofs — the roofs are what the camera sees
  - Stations: colour-neutral but high contrast (mortar = timber tub of grey mortar, not a white heap)
  - **Characters (v0.7)**: low-poly chibi figures built from primitives in code (`CharacterRig`), replacing the LPC pixel sprites, which clashed with the smooth low-poly world and were too small to read. Big head, stubby robe, dark outline (inverted hull), soft two-tone light. Player colour = the robe; cream head-wrap on top (what the camera sees most). Each slot has its own face (beard style, grey hair, skin tone) so the crew reads as four people. Enemies: dark goat-hair cloth, oxblood outline, a silhouette per type (scout: hood and spear; brute: bronze helmet, red shield, spear; raider: red hood, cape, dagger). Still a little cartoonish; levers if needed: smaller head, longer robe, less rim light
  - World labels (site needs, pile names, toasts): bold Spectral, white on a heavy ink rim (`UiStyle.world_label`)
  - Tech: all palette colours are sRGB (`vertex_color_is_srgb`, `source_color` in the ground shader); Filmic tonemap; the dirt track is drawn in the ground shader

### 5.3 Backlog (bigger features, one at a time)
| Idea | Value | Risk |
|---|---|---|
| Enemies that attack the work itself, one at a time: **saboteur** (raids the yard, scatters loads; Neh 4:11 — spec §5.9) → **archer** (stays outside, hits builders on the scaffold; 4:17) | Variety across 52 days; makes guarding the yard / builders a real job | Low — add incrementally |
| Civilians (women, children) inside the city | Raises stakes, fits Neh 4:13 | Adds AI work |
| Prep days (gather materials, craft weapons) | Rhythm between sections | Slows pacing |
| Stand on a tile to spawn builders/fighters (mobile-ad style) | Addictive progression hook | Can drift toward an idle game |
| Medkits / healing | Survivability | Low priority |

Done and removed from the table: wall damage (§5.2), brute + raider (§2), ballistas → watch posts (§5.6), player roles → trades (§5.10).

**Suggested order:** playtest 3 first (§5.6–5.8 are all first pass) → saboteur → archer

---

---

## 6. The Twelve Sections — one twist each

**Problem to solve:** 52 days of the same carry-and-build loop gets repetitive. **Rule (Overcooked):** every section adds *one* new ingredient to what players already know; no ingredient stays unchanged for more than ~2 sections. Twists come from the text (Neh 3–6) or from real ancient building work — never invented gimmicks.

**Pacing arc** follows the narrative: quiet start → mockery (Neh 4:1-3) → conspiracy and armed work at half height (4:6-8, 4:16-18) → a breather → schemes to stop the leaders (Neh 6) → completion (6:15-16).

| # | Section (Neh 3) | Days | New ingredient | Grounded in | Pressure |
|---|---|---|---|---|---|
| 1 | **Sheep Gate** (3:1) | 1–4 | Core loop. Gates end with a **doors step**: hang the doors, fit bolts and bars — a recurring finale for every gate section | "set up its doors, its bolts and its bars" (3:3, 3:6, 3:13…) | Low — scouts only |
| 2 | **Fish Gate** (3:3) | 5–8 | **Beams** — long timbers that need **two workers** to carry | "they laid its beams" (3:3, 3:6) | Low |
| 3 | **Jeshanah (Old) Gate** (3:6) | 9–12 | **Salvage** — no stone stockpile; stone comes from rubble heaps scattered across the site. **Old and burned units** (`ruins`, §6.4): one unit's courses still stand, another's charred framing must be pulled down first | Sanballat: will they revive the stones from the heaps of rubbish, burned as they are? (4:2) | Brutes arrive |
| 4 | **Broad Wall** (3:8) | 13–17 | **Double-thick, two-face wall** — outer face, inner face, rubble core (§6.3); four hands per unit | Built by goldsmiths and ointment makers — craftsmen, not masons (3:8) | Mockery beat (4:3) as the section intro |
| 5 | **Tower of the Ovens** (3:11) | 18–23 | **Mortar mixing** — carry lime + water to a trough, mix, then deliver. The Overcooked "cooking" step | Ovens / lime burning; mortar was made on site | Rising |
| 6 | **Valley Gate** (3:13) | 24–29 | **The horn** — a worker can sound it to call everyone to a spot; enemies come in surges from the valley | "At the place where you hear the horn, gather to us" (4:20); half worked, half held spears (4:16) | **Peak #1** — conspiracy (4:7-8); raiders from day 21 |
| 7 | **Dung Gate** (3:14) | 30–33 | **Long haul** — the site is far from the supply yard; chains of drops and hand-offs pay off | 1,000 cubits of wall up to the Dung Gate (3:13) | Medium |
| 8 | **Fountain Gate** (3:15) | 34–36 | **Breather** — short, beautiful: the Pool of Shelah, the King's Garden, stairs down from the City of David. Water is close (fast mortar) | 3:15 | **Low** — deliberate rest |
| 9 | **Water Gate** (3:26) | 37–41 | **Night watch** — some days end in darkness; torches light small areas, enemies come out of the dark | Guards at night, work by day (4:22-23) | Rising |
| 10 | **Horse Gate** (3:28) | 42–47 | **Cramped streets** — each priest builds "in front of his own house": tight lanes, little room to pass (the Overcooked "small kitchen") | 3:28 | High |
| 11 | **East Gate** (3:29) | 48–50 | **Schemes** — messengers appear with invitations "to the plain of Ono"; following one pulls a worker away from the wall. Ignoring them is the right move | 6:1-4 (four times, the same answer) | **Peak #2** — Geshem's raiders from the east |
| 12 | **Inspection (Miphkad) Gate** (3:31) | 51–52 | **Finale** — close the circuit back to the Sheep Gate (3:32). All ingredients at once. When the last section is complete, the enemies lose heart and withdraw | 6:15-16 | Highest, then release |

### 6.1 Also against repetition
- **Layout per section** — each section is its own map (terrain, where the supply yard sits, where the gaps are), not a re-skin.
- **Section intros** — a short, still illustrated card or clip between sections with its Neh 3 reference, and the narrative beat where one applies (mockery, conspiracy, Ono). Dignified, no cartoon cutscenes. ◐ System done (`StoryData` / `StoryPlayer`, Phase.STORY): prologue before day 1 (Neh 1–2), a card per section, beats at Jeshanah (4:2), Broad Wall (4:3), Valley Gate (4:7-20), East Gate (6:2-4). Every reader must finish (or skip) before the day starts; host can "Begin now". The eleven story slides have art (`art` key per slide, `assets/story`): tinted-lithograph views after David Roberts' Holy Land prints (1840s) — grand, small figures, sepia tints — painted in code by `tools/story_art` (`node tools/story_art/render.mjs`; walls always leave the frame, end in a tower or pass behind something). Section cards keep the circuit map. Verses: World English Bible (public domain; NWT barred by jw.org terms for software/commercial use). ✅ Ending after day 52 (`StoryData.ENDING`, campaign only, each reader at their own pace, then the end screen): the ring closes (6:15), they lost heart (6:16), the dedication (12:31-43). Then the **credits** (`CreditsRoll`): they roll up the dark column over the finished city with the ring closing, ending on Neh 13:31 "Remember me, my God, for good." Also a main menu entry. Chris Nohall (development), Joakim Müller (game design), Joakim Henriquez (art director), plus the attributions the licences ask for (CC-BY music, OFL fonts, MIT Godot/GodotSteam, WEB). Tests: `tools/ending_test.gd`, `tools/credits_test.gd`; shots/video: `tools/ending_shots.gd`, `tools/credits_shots.gd`.
- **Section rating** ✅ — three marks per section, each earned on its own: *In good time* (section work time ≤ par: 7 min + extra for beams/salvage/mixing/haul — TODO tune, the log prints time vs par), *None got through* (no breaches in the section), *The wall holds* (average wall health ≥ 80% at the end). Shown on the section's last dusk card, beside each gate on the circuit map, and totalled on the end screen. Each player's best per section is saved to `user://progress.cfg` (not for `--day=N` runs) — and the replay picker reads it: main menu → **Choose a Section** opens the circuit map (`SectionPicker`), finished stretches standing with their best marks; a section opens once the one before it is finished (debug `-- --unlock-all`). Picking one hosts a game of just that section (`GameState.replay_section`): its card only, its days, then an end screen with the marks and "Back to the map". Test: `tools/replay_test.gd`. Replay value without coins or loot.
- **Friends and Foes** ✅ — main menu page (`FriendsAndFoes`): the whole cast as a lineup of portrait medallions (crew | foes); the one picked stands in an arched plate (dawn before the finished wall for friends, dusk outside a broken one for foes, night for the unmet), sways in 3/4 view, turns on drag and plays a signature move (build, cheer, thrust, slash), beside a verbatim WEB quote in their own words, who they are, and for enemies speed / toughness / strength. "Met N of 12" counter. Foes stay ink silhouettes ("Not yet met", with the gate where they first show) until this player meets them: enemies and the messenger on sight, leaders in their story beat (`GameState.mark_met` → `progress.cfg [met]`; older saves backfill from finished sections via `MET_AT`). The section picker shows each stretch's twists as chips, a line on what's new there, and its foes (`?` until met); a locked stretch keeps its twists hidden. Shots: `tools/folk_shots.gd`.

### 6.2 Style guardrails (against "cartoonish")
Borrow Overcooked's **structure and readability**, not its tone.
- ✅ Keep: focus ring, subtle squash on pickup/drop, colour-neutral stations, clear silhouettes, satisfying sounds
- ❌ Avoid: floating "+10!" numbers, bouncy text, neon or candy colours, slapstick (knockback spins, comic sound effects), enemies that "poof", invented hazards (fire traps, conveyor belts)
- Enemies are opposition to the work, not jokes — they fall and fade quietly
- Humour, if any, comes from the co-op chaos between players — never from the setting or biblical figures

### 6.3 Build order
1. Section framework — ◐ twists done (`GameState.SECTIONS[i].twists`, `has_twist()`, dawn banner introduces new twists, twist-only supply piles). ✅ per-section layouts (data-driven, `SECTIONS[i].yard` / `.gate`, applied by `SectionStage` on every peer): supply yard moves per section (Dung Gate ~30 m east = long haul); stretches with no gate (Broad Wall, Tower of Ovens) seal the opening with stone instead of doors. ✅ Terrain per section (`SECTIONS[i].terrain`, built by `SectionTerrain`, solid + in the nav bake, ground tint/scrub/valley shade per section): sheepfold · fish stalls · burned ruins · forge & perfume stalls · bread ovens · valley terraces (two gaps funnel enemies) · refuse heaps (lanes on the long haul) · Pool of Shelah + King's Garden · torches + Ophel boulders · priests' houses (narrow lanes) · Kidron olive grove · market + sheepfold again. Sections can pin single piles (`piles`) and set enemy pace (`pressure`)
2. ✅ Doors step (gate sections: after both pillars, deliver timber → doors hang and close the gap) and ✅ beams (Fish + Jeshanah Gate: framing takes beams; drag alone slowly, or a partner takes the other end — tethered pair at carry pace)
3. ✅ Salvage (3): Jeshanah has no stone pile — 5 burned rubble heaps (3 inside, 2 **outside** the wall) with 4 stones each, refilled at dawn, and regrowing one every 20 s during the work so a stretch never runs dry. ✅ Mortar mixing (5): Tower of Ovens + Valley Gate have no mortar pile — lime (bin) + water (clay jars) → stone trough mixes by itself in 4 s (progress bar, stirring paddle) → carry mortar to the wall. ✅ Horn (6)
4. ✅ Sections 7–12 (first pass, needs playtest):
   - **Dung Gate** `haul`: yard 30 m east, refuse heaps split the route. **Hand-off** (all sections): [G] beside an empty-handed teammate puts the load in their hands
   - **Fountain Gate** `spring`: pressure ×0.55, water jars by the pool near the wall, mixing
   - **Water Gate** `night`: from its 2nd day darkness falls over ~16 s of work (`DayLight`), torches light up, each worker carries a lamp; lifts at dawn
   - **Horse Gate** `cramped`: row of low priests' houses between wall and yard, ~2 m lanes
   - **East Gate** `schemes`: up to 4 messengers a day (6:4), one at a time. He walks up and waits beside a worker; when he's nearer than anything else, [E] goes with him — led off ~7 s, then walk back. Ignored 12 s, he leaves
   - **Miphkad Gate**: doors + beams + salvage + mixing + schemes, pressure ×1.3; on the win the enemy withdraws (6:16)
   - ✅ **Valley Gate** `horn`: [R] / LB sounds the horn (8 s shared cooldown): everyone hears it (synth ram's horn), a standard in the caller's colour + ground ring stands 9 s, off-screen pointer "Horn" for the others. The enemy comes in **surges**: a "Surge" pointer + bell 3.5 s ahead, then a pack of 3 + day/12 from one spot every ~24 s, over a trickle thinned ×1.8. Also in the finale
   - ✅ **Broad Wall** `thick`: plain stretches 2.2 m deep (collision too), built in **two faces** — the stone stage is two jobs, outer face (toward the foe, −z) then inner, each paid and worked on its own (`WallSection.face`, label "Outer face / Inner face", replicated); the rubble core fills between and is mortared last, with a parapet on both edges (a walkway). +2 stone / +1 mortar in all, work ×1.3, 4 hands per site instead of 3, takes half the blows. A blow back to the timber takes both faces. Shots: `tools/thick_shots.gd`. Not yet: the two faces worked by two crews at once (a real split) — if playtests say the sequence is just "longer", make the faces parallel
   - Still open: night on the finale?, per-section terrain *shape* (heights). Watch solo pacing on surge days

### 6.5 A choice before each stretch — ◐ reworked (1 Oct 2026), needs playtest 3
**Fun check:** *Fantasy* — Nehemiah deciding how to meet "the work is great and large" (4:19). *Kind of fun:* Fellowship (the crew agrees, or argues), Challenge (a price you chose to pay). *Where it can go sour:* one option is always right (then it's a chore, cut it); a vote that stalls a session in multiplayer; one more screen before the work.
**First pass was too weak** (a free +20% daylight, a post nobody felt, a "keep to the plan" that lost to both, no memory of it). Reworked as **two real trades per stretch, tied to what the stretch brings**, and written down.
**What:** the last story card of every new stretch (not the first, not a replay, not the tutorial/festival) — `StoryData` slide `choice: true`, shown by `StoryPlayer`, **no extra screen or phase**: it rides on the story ready check. ← → / 1–2 / click to pick, E to confirm. Each reader's pick goes to the server (`DayDirector.cast_choice`); **most votes win, the host's pick breaks a tie, no votes = the first of the two**. Bots don't vote. In play for that stretch only (`GameState.boon`, synced).
**Every option is a gain and a cost, and the card text is generated from the modifiers** (`GameState.BOONS[k].mods`, `boon_lines()`), so what it says is what it does. Modifiers: `work` (build speed), `harm` (blows the wall takes), `pressure` (foes), `warn` (warning before waves/surges), `beam_solo`, `carry`, `clear` (burned timbers), `mix` (mortar), and `posts` (watch posts stand from dawn). `-- --boon=<key>` (debug) forces one for every stretch, to A/B a trade.
**The axis everywhere:** pace (the *In good time* mark) against defence (*None got through*, *The wall holds*). Stretches without their own pair (Fountain Gate to Miphkad Gate) offer **Press the work** (build +20%, wall takes +25% harm) or **Hold the line** (watch posts from dawn, −25% harm, build −10%).
**Tailored pairs** (each pair a trade on that stretch's twist; first = default):
- Fish Gate (beams): *Practised porters* (a lone beam +90% faster; +15% foes) / *Watch the market side* (posts; warning +50%; build −10%)
- Jeshanah (salvage, ruins): *Dig out the rubble* (burned timbers 2× faster, build +10%; +20% foes) / *Shore up the old courses* (−30% harm; timbers 40% slower)
- Broad Wall (thick): *Rush the faces* (build +30%; +40% harm) / *Pack the core* (−40% harm; build −15%)
- Tower of Ovens (mixing): *Fire the ovens high* (mortar mixes in half the time; +20% foes) / *Bank the ovens* (posts; warning +50%; mortar +50% time)
- Valley Gate (horn): *Work the terraces* (build +20%; warning −50%) / *Lookouts on the heights* (warning +120%, posts; build −10%)
- Dung Gate (haul): *Carry in bundles* (loaded walk +25%; +25% harm) / *Hold the road* (−20% harm, posts; loaded walk −15%)
**Remembered:** the scribe's map writes how each stretch was met in its margin (`chronicle[i].boon`), saved with Continue. The dawn banner repeats the pick and its gain/cost.
**Kill rule:** playtesters pick the same option every time at a stretch, or skip the card. **Tune:** every number above is a guess (the log prints time, breaches, and wall health per stretch — compare picks). **Later:** pairs for stretches 8–12, a carry-over cost ("worked till the stars" leaves the crew tired next stretch), "another portion" (3:11) as a bonus mark. Tests: `tools/choice_test.gd -- --day=N <out_dir> [key]` (also checks every boon has a gain and a cost).

### 6.4 Section beats and the stretch's arc — ◐ first pass (30 Sep 2026), needs playtest 3
**What the code says about "longer":** sections run 4 / 4 / 4 / 5 / 6 / 6 / 4 / 3 / 5 / 6 / 3 / 2 days, but under the sun clock every day of a section gets par ÷ days × `sun_slack`, so a section's total light ≈ par × 1.2 whatever its day count (Tower of Ovens: six ~96 s days; Miphkad: two ~360 s days). Every stretch is the same 6 units (`WorkFront.UNIT_ORDER`). More days only cuts the same work into more dawns and dusks. So arcs are keyed to **progress**, not to day numbers.

**Fun check:**
- **Fantasy:** the enemy answering the work, as in the text: "they heard that the repairing… went forward… they were very angry" (4:7)
- **Kind of fun:** Challenge (a climax mid-stretch and at the end), Fellowship ("both ends — split up!")
- **Where it can go sour:** a pack at the last unit that feels like a punishment for building; a verse bubble too long to read mid-fight
- **A/B switch:** `-- --no-beats`
- **Kill rule:** playtesters don't tell a beat from an ordinary wave

**Rules** (`SectionBeats`, `scenes/section_beats/section_beats.gd`, all data in its `BEATS`): each section may have a **"half"** beat (half its units stand) and a **"last"** beat (one unit left). Each fires once per stretch, during the work only. A beat is a watchman's call, a WEB verse where the text has one, and usually a warned pack (5 s bell + "Onslaught" pointer) at the gate, one flank, both flanks, the east end (via `RingCompass`), or the end nearest the yard. Pack grows by one per two workers (bots by skill) × difficulty pace; a saboteur only when he's on. The Fountain Gate stays a breather (calls only). Broad Wall half = 4:6 "joined together to half its height" + anger; Tower of Ovens = 4:8 conspiracy, then 4:11 saboteur; Valley Gate last = 4:20; East Gate = Geshem from the east + 6:3, 6:9; Miphkad last = everything, 4:21.
- `beat_fired(section_index, key, beat)` on every peer; `beat.leader` ("sanballat" / "tobiah" / "geshem" / "all") drives the leaders' set-pieces (`Leaders`)
- Test: `tools/beats_test.gd` (`-- --nostory --day=9`)

**Done (1 Oct 2026, first pass, needs playtest 3):**
1. ✅ **Per-unit recipes** (twist `ruins`; `GameState.SECTIONS[i].recipes`, unit node name → recipe, `WallSection.recipe()`): not every unit starts from bare footing. `old` = the stone stage already stands (only mortar wanted, a quick unit); `burned` = charred framing to pull down first — a job of pure work, no materials, no loads accepted until it's down (`cleared`, label "Clear the charred timbers [E]", carpenters quicker at it). Jeshanah: Section1 old, Section3 burned (the *Old* Gate, 4:2). Miphkad finale: Section1 burned, Section4 old. Twist card + dawn line + picker chip. Test: `tools/recipes_test.gd` (`-- --nostory --day=9`, `--day=13` also checks the faces), shots `tools/ruins_shots.gd`
2. ✅ **A choice before each new stretch** (§6.5) instead of spare days skipped

**Next, in order** (each one mechanic, own `--no-` flag, playtest between):
3. **Par scaled with days** if 6-day sections still feel choppy: fewer, longer days, or more work per unit where days are many
4. **Mid-day events**, one at a time: timber caravan from Asaph's forest to escort in (2:8, beam sections), families to a weak spot (4:13)
5. **Neighbour crews** (Neh. 3's "next to him…"): an NPC crew on the adjacent unit that lags (the Tekoite nobles, 3:5) or hands over leftovers. Needs AI work
6. Walking work front (each day further along the wall): biggest; only if the above isn't enough
