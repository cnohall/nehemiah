# Nehemiah: The Wall — Game Design Document
**Version 0.6 | September 2026**

---

## 1. Overview

Cooperative 2–4 player HD-2D isometric action-strategy set in 445 BC Jerusalem. Players embody the workers and guards of Nehemiah's rebuilding effort, racing to reconstruct the city wall in 52 days while repelling Sanballat's and Tobiah's increasingly desperate forces. Tone: urgent and collaborative — think Overcooked meets tower defense, grounded in Biblical history.

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
- 52 days: Nehemiah 6:15 (Elul 25, 445 BC)
- Enemy leaders: Sanballat the Horonite, Tobiah the Ammonite, Geshem the Arab
- Persian king: Artaxerxes I (465–424 BC)
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

### 5.2 Next (low cost, high impact)
1. ✅ **Sound** — done: footsteps, pickup/drop/deposit (per material), dash, sling throw/hit/miss, enemy swing/death, wall build/hit/crumble, alarm bell on breach, jingles for day start/end + win/loss. Kenney CC0 packs, `Sfx` autoload
   - **Music** — two moods crossfaded by day phase: *calm* (sparse plucked strings over a drone) for menu/dawn/dusk, *work* (steady warm pulse) while enemies come. Criteria: ancient Near-East palette (lyre, pipe, frame drum), dignified not martial, no vocals/liturgy. Ducks under jingles; own volume slider. Tracks in `assets/audio/CREDITS.md` — one is CC-BY, needs an in-game credits line
2. ✅ **Dropped materials stay on the ground** (Overcooked-style) — done: [G] drops at your feet, downed workers drop their load, [E] picks up (nearest of ground item vs stockpile). Cleared when a new wall section starts
3. ✅ **Enemies damage the wall if not killed** — done: "wreckers" (all brutes, ~50% of others) march on the nearest built wall and batter it. Makes fighting and building compete for the same players. Gives the loss condition a gradual build-up instead of a single breach
4. ✅ **Movement feel** — done: dash on [Space]/[Shift] (short burst, 0.7 s cooldown, works while carrying)

5. ✅ **Game feel pass** — gamepad (stick/d-pad, A pick up · B dash · Y drop · RT sling · right-stick aim · Start menu), analog walk, 0.15 s input buffer, camera look-ahead + shake (toggle in Settings), hitstop on sling hits, pad rumble. Camera a little closer (size 22)

### 5.4 Hands-on building (Overcooked "chopping") — ✅ built, A/B with `-- --instant-build`
Delivering the last load no longer raises a stage by itself: someone has to **stand at the wall and work it**.
- The one who brings the last load starts working automatically; anyone else presses [E]/A at the wall ("Build [E]")
- Working keeps going while you stand still (no holding); moving, dashing, dropping, the sling or **a hit** stops it. Progress is kept
- Extra hands help: +70% each, max 3 at one site ("Enough hands here")
- Hands are full while working — builders can't sling. Guarding the builders is the Neh. 4:17 moment
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

### 5.2a Art direction — "slightly Overcooked"
Keep the HD-2D sprites and earthy palette, borrow Overcooked's readability:
- Stations told apart by period-appropriate bases, not colour-coding: stone on a timber pallet, logs on sleeper beams, mortar on a reed mat with spilled lime (bright colour rugs tried and dropped: broke immersion)
- Pulsing cream ring under whatever [E] will act on (Overcooked's counter highlight)
- Squash & stretch on pickup / drop / dash; walls bounce when a stage goes up, shake when hit
- Crisp, warm, saturated lighting; tilt-shift blur kept light

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
- **Section intros** — a short, still illustrated card or clip between sections with its Neh 3 reference, and the narrative beat where one applies (mockery, conspiracy, Ono). Dignified, no cartoon cutscenes. ◐ System done (`StoryData` / `StoryPlayer`, Phase.STORY): prologue before day 1 (Neh 1–2), a card per section, beats at Jeshanah (4:2), Broad Wall (4:3), Valley Gate (4:7-20), East Gate (6:2-4). Every reader must finish (or skip) before the day starts; host can "Begin now". Drawn silhouette backdrops stand in until art exists (`art` key per slide). TODO: verify NWT quotations, commission art, ending story after day 52
- **Section rating** (later) — 1–3 marks per section for pace, no breaches and wall health. Replay value without coins or loot.

### 6.2 Style guardrails (against "cartoonish")
Borrow Overcooked's **structure and readability**, not its tone.
- ✅ Keep: focus ring, subtle squash on pickup/drop, colour-neutral stations, clear silhouettes, satisfying sounds
- ❌ Avoid: floating "+10!" numbers, bouncy text, neon or candy colours, slapstick (knockback spins, comic sound effects), enemies that "poof", invented hazards (fire traps, conveyor belts)
- Enemies are opposition to the work, not jokes — they fall and fade quietly
- Humour, if any, comes from the co-op chaos between players — never from the setting or biblical figures

### 6.3 Build order
1. Section framework — ◐ twists done (`GameState.SECTIONS[i].twists`, `has_twist()`, dawn banner introduces new twists, twist-only supply piles). ✅ per-section layouts (data-driven, `SECTIONS[i].yard` / `.gate`, applied by `SectionStage` on every peer): supply yard moves per section (Dung Gate ~30 m east = long haul); stretches with no gate (Broad Wall, Tower of Ovens) seal the opening with stone instead of doors. Terrain/map shape per section still to come
2. ✅ Doors step (gate sections: after both pillars, deliver timber → doors hang and close the gap) and ✅ beams (Fish + Jeshanah Gate: framing takes beams; drag alone slowly, or a partner takes the other end — tethered pair at carry pace)
3. ✅ Salvage (3): Jeshanah has no stone pile — 5 burned rubble heaps (3 inside, 2 **outside** the wall) with 4 stones each, refilled at dawn. ✅ Mortar mixing (5): Tower of Ovens + Valley Gate have no mortar pile — lime (bin) + water (clay jars) → stone trough mixes by itself in 4 s (progress bar, stirring paddle) → carry mortar to the wall. Next: horn (6)
4. The rest, in section order
