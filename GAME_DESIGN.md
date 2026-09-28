# Nehemiah: The Wall — Game Design Document
**Version 0.6 | September 2026**

---

## 1. Overview

Cooperative 2–4 player HD-2D isometric action-strategy set in 455 BCE Jerusalem. Players embody the workers and guards of Nehemiah's rebuilding effort, racing to reconstruct the city wall in 52 days while repelling Sanballat's and Tobiah's increasingly desperate forces. Tone: urgent and collaborative — think Overcooked meets tower defense, grounded in Biblical history.

**Core loop per day:**
1. Day begins — enemies spawn in waves
2. Players fight, carry materials, and build walls simultaneously — deliver a stage's loads, then stand at the wall and work it up (§5.4)
3. Day ends when all wall sections for that day are complete (sprint model)

**Platform:** desktop (Steam) first, built so a console / mobile port stays cheap: every action works on keyboard + mouse and on a gamepad, UI is navigable by pad, button hints follow the device in use (`InputMode`).

**Win condition:** Complete the wall section on day 52
**Loss condition:** The enemies break through the wall and reach the inner city

---

## 2. Enemy Types

Three types, unlocked over the campaign (`wave_manager.gd`). Spawn rate and max alive scale with day and crew size.

**Difficulty** (host picks on the gathering screen, `Settings.DIFFICULTIES`): Gentle / Standard / Hard. *pace* ×0.7 / 1.0 / 1.3 multiplies spawn rate, max alive and wave/surge size on top of each section's pressure; *harm* ×0.7 / 1.0 / 1.25 multiplies every enemy blow (workers and wall). **Bots count by skill** toward the enemy's crew size (Apprentice 0.5, Builder 0.75, Master builder 1.0), so adding weak bots no longer adds a full worker's foes. Building costs still use the whole crew. (Added 28 Sep 2026)

| Type | Unlocks | Speed | Health | Damage | Notes |
|---|---|---|---|---|---|
| Scout | Day 1 | 3.5 | 40 | 5 | ~50% go for the wall ("wreckers"), rest run for gaps |
| Brute | Day 9 (25% of spawns) | 2.5 | 100 | 15 | Always a wrecker — slow, batters walls |
| Raider | Day 21 (~30% late mix) | 4.0 | 60 | 8 | Fast; ~50% wreckers |

All attack nearby workers first. A wrecker that knocks a section back to bare foundation pours through the breach.
Debug: run with `-- --day=N` (debug builds) to start at a later day and see brutes/raiders.

---

## 3. Structures

Just one type of structure so far

1. Wall sections - required materials to build, wood, stones, and mortar

---

## 4. Historical Notes

- Wall circuit: Nehemiah 3, clockwise from Sheep Gate
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
- Time per stage for one worker: framing 2 s, courses 3 s, mortar 2 s, doors/seal 2.5 s; solo works 25% faster
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
| Different enemy types | Needed for variety across 52 days | Low — add incrementally |
| Ballistas mounted on the wall | Tower-defense layer, a way to spend materials | May let players skip combat |
| Civilians (women, children) inside the city | Raises stakes, fits Neh 4:13 | Adds AI work |
| Player roles | More reason to coordinate | Could fragment co-op; Overcooked has no roles |
| Prep days (gather materials, craft weapons) | Rhythm between sections | Slows pacing |
| Stand on a tile to spawn builders/fighters (mobile-ad style) | Addictive progression hook | Can drift toward an idle game |
| Medkits / healing | Survivability | Low priority |

**Suggested order:** wall damage → second enemy type → ballistas

---

---

## 6. The Twelve Sections — one twist each

**Problem to solve:** 52 days of the same carry-and-build loop gets repetitive. **Rule (Overcooked):** every section adds *one* new ingredient to what players already know; no ingredient stays unchanged for more than ~2 sections. Twists come from the text (Neh 3–6) or from real ancient building work — never invented gimmicks.

**Pacing arc** follows the narrative: quiet start → mockery (Neh 4:1-3) → conspiracy and armed work at half height (4:6-8, 4:16-18) → a breather → schemes to stop the leaders (Neh 6) → completion (6:15-16).

| # | Section (Neh 3) | Days | New ingredient | Grounded in | Pressure |
|---|---|---|---|---|---|
| 1 | **Sheep Gate** (3:1) | 1–4 | Core loop. Gates end with a **doors step**: hang the doors, fit bolts and bars — a recurring finale for every gate section | "set up its doors, its bolts and its bars" (3:3, 3:6, 3:13…) | Low — scouts only |
| 2 | **Fish Gate** (3:3) | 5–8 | **Beams** — long timbers that need **two workers** to carry | "they laid its beams" (3:3, 3:6) | Low |
| 3 | **Jeshanah (Old) Gate** (3:6) | 9–12 | **Salvage** — no stone stockpile; stone comes from rubble heaps scattered across the site | Sanballat: will they revive the stones from the heaps of rubbish, burned as they are? (4:2) | Brutes arrive |
| 4 | **Broad Wall** (3:8) | 13–17 | **Double-thick sections** — more material per unit; work is split across more fronts | Built by goldsmiths and ointment makers — craftsmen, not masons (3:8) | Mockery beat (4:3) as the section intro |
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
- **Section intros** — a short, still illustrated card or clip between sections with its Neh 3 reference, and the narrative beat where one applies (mockery, conspiracy, Ono). Dignified, no cartoon cutscenes. ◐ System done (`StoryData` / `StoryPlayer`, Phase.STORY): prologue before day 1 (Neh 1–2), a card per section, beats at Jeshanah (4:2), Broad Wall (4:3), Valley Gate (4:7-20), East Gate (6:2-4). Every reader must finish (or skip) before the day starts; host can "Begin now". Drawn silhouette backdrops stand in until art exists (`art` key per slide). Verses: World English Bible (public domain; NWT barred by jw.org terms for software/commercial use). ✅ Ending after day 52 (`StoryData.ENDING`, campaign only, each reader at their own pace, then the end screen): the ring closes (6:15), they lost heart (6:16), the dedication (12:31-43). Then the **credits** (`CreditsRoll`): they roll up the dark column over the finished city with the ring closing, ending on Neh 13:31 "Remember me, my God, for good." Also a main menu entry. Chris Nohall (development), Joakim Henriquez (design), plus the attributions the licences ask for (CC-BY music, OFL fonts, MIT Godot/GodotSteam, WEB). Tests: `tools/ending_test.gd`, `tools/credits_test.gd`; shots/video: `tools/ending_shots.gd`, `tools/credits_shots.gd`. TODO: commission art
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
   - ✅ **Broad Wall** `thick`: plain stretches 1.3 m deep (collision too), +2 stone / +1 mortar per stage, work ×1.3, 4 hands per site instead of 3
   - Still open: night on the finale?, per-section terrain *shape* (heights). Watch solo pacing on surge days
