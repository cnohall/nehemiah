# Steam store page — Nehemiah

Copy-paste source for Steamworks → Store Page Admin. Launch as **Coming Soon** (wishlists), no price shown.
Facts mirror GAME_DESIGN.md v0.6 and nehemiah-website `src/lib/dictionaries/en.ts` — keep in sync.

---

## 0. Before the page exists (user-only, needs login)

1. partner.steamgames.com → sign up as **Corner Stone Games** (company or individual).
2. Fill tax interview + bank info (identity verification can take days).
3. Pay Steam Direct fee ($100, recouped after $1,000 gross) → get the **App ID**.
4. Swap App ID in `scenes/network_manager/network_manager.gd` (`STEAM_APP_ID := 480`) and any `steam_appid.txt`.
   Achievements then go live automatically (`achievements.gd` skips 480).
5. Store page review: 3–5 business days. Page must be public as Coming Soon **≥ 2 weeks** before release.

---

## 1. Basic info

| Field | Value |
|---|---|
| App name | **Nehemiah: The Wall** (matches `project.godot`; plain "Nehemiah" is hard to find in search) |
| Developer | Corner Stone Games |
| Publisher | Corner Stone Games |
| Franchise | — |
| Release date | Coming soon |
| Website | https://www.nehemiahgame.com |
| Genres | Action, Strategy, Indie, Casual |

---

## 2. Short description (≤ 300 chars)

```
Overcooked meets tower defense, in 455 BCE Jerusalem. Carry wood, stone and mortar, raise the wall stone by stone, and drive off Sanballat's raiders before they break through. Co-op for 2–4 builders, 52 days, 12 sections of wall.
```
(229 chars)

---

## 3. About This Game (Steam BBCode)

```
[h2]Rebuild the wall of Jerusalem in 52 days.[/h2]

Nehemiah is a co-op action-strategy game for 2–4 players. Your crew has one job: get today's stretch of wall built before the raiders break through. Someone has to haul the stone. Someone has to work the wall. And someone has to keep the enemy off the builders — because builders with full hands can't defend themselves.

[h2]Every day, three jobs[/h2]
[list]
[*][b]Carry[/b] — Haul wood, stone and mortar from the stockpiles. Drop a load, pass it on, keep the line moving.
[*][b]Build[/b] — Stand at the wall and work it up, course by course. More hands build faster. A hit stops the work.
[*][b]Defend[/b] — Sling stones at the raiders, like Nehemiah's workers who built with one hand and kept a weapon in the other.
[/list]

The day ends when the wall is up. Let too many enemies through a breach and the city falls.

[h2]Twelve sections, twelve twists[/h2]
The work goes around the city gate by gate, in the order of Nehemiah chapter 3, and every section changes how you play:
[list]
[*]Hang the doors, bolts and bars of the Sheep Gate
[*]Heavy beams at the Fish Gate that take two builders to carry
[*]No quarry stone at the Old Gate — salvage it from the burned rubble
[*]Mix your own mortar at the Tower of the Ovens
[*]Surges up the valley — sound the horn to gather the crew
[*]Night work at the Water Gate, by torchlight
[*]Messengers calling you down to Ono. Don't go with them.
[/list]

[h2]Enemies that learn the wall[/h2]
Scouts probe for gaps from day one. Brutes arrive to batter your wall back down. Raiders come fast and hit where you aren't. Sanballat, Tobiah and Geshem did all they could to stop the work. The builders kept going.

[h2]Features[/h2]
[list]
[*]Online co-op for up to 4 players — invite friends through Steam
[*]Solo play, with a lone builder who works a little faster
[*]52-day campaign across 12 sections of wall
[*]Three marks to earn on every section: in good time, none got through, the wall holds
[*]Full controller support on every screen
[*]Grounded in the Bible account of Nehemiah — scripture from the World English Bible
[/list]

[i]"So the wall was finished in the twenty-fifth day of Elul, in fifty-two days." — Nehemiah 6:15[/i]
```

---

## 4. Tags (pick up to 20, order = weight)

1. Co-op
2. Online Co-Op
3. Tower Defense
4. Action
5. Strategy
6. Building
7. Team-Based
8. Isometric
9. Casual
10. Indie
11. Historical
12. Singleplayer
13. Controller
14. Base Building
15. Cute
16. Colorful
17. Family Friendly
18. Stylized
19. Time Management
20. Christian / Religious — *use if the Steamworks tag picker offers one; else pick "Short" or leave blank*

**Do NOT tag** Local Co-Op / Shared/Split Screen / Remote Play Together — game has no couch co-op.

---

## 5. Features checkboxes (Steamworks → Store Page → Basic Info)

- [x] Single-player
- [x] Online Co-op
- [x] Steam Achievements (25 — see §9)
- [x] Full Controller Support
- [ ] Steam Cloud — only if `progress.cfg` set up in Steam Auto-Cloud (easy win, do it)
- [ ] Remote Play Together — skip unless local co-op added
- [ ] In-App Purchases — no

---

## 6. Languages

| Language | Interface | Full audio | Subtitles |
|---|---|---|---|
| English | ✔ | — | ✔ |
| German | ✔ after native review | — | ✔ |
| Spanish (Spain / LatAm — pick) | ✔ after native review | — | ✔ |
| Portuguese – Brazil | ✔ after native review | — | ✔ |
| Korean | ✔ after native review | — | ✔ |

`locale/*.po` are drafts. Only tick a language once reviewed — Steam reviews punish bad translations.
Localized short description + About: translate §2–3 per ticked language (Steam shows them per region).

---

## 7. System requirements (Windows, Forward+ / Vulkan)

| | Minimum | Recommended |
|---|---|---|
| OS | Windows 10 64-bit | Windows 11 64-bit |
| CPU | Dual-core 2.0 GHz | Quad-core 3.0 GHz |
| RAM | 4 GB | 8 GB |
| GPU | Vulkan 1.0 capable (GTX 750 / Intel UHD 620) | GTX 1050 / RX 560 |
| Storage | 500 MB | 500 MB |
| Network | Broadband for online co-op | Broadband |
| Notes | Controller optional | |

**Verify** on a low-end PC before submitting; UHD 620 with MSAA 2x + SSAO may need lower settings. Check final export size.
Mac/Linux: GodotSteam ships osx/linux64 — add later if tested; don't list now.

---

## 8. Content survey (Mature Content)

- Violence: **Mild, non-graphic.** Sling stones drive enemies off; no blood, no gore, no death animations.
  *(Confirm wording matches what's on screen before answering.)*
- Sexual content / nudity / drugs / gambling / strong language: None.
- User-generated content: None. Online chat: Steam overlay only (no in-game chat).
- Religious content: Based on the book of Nehemiah — mention in "Describe content" box.

Expected rating fit: PEGI 7 / ESRB E10+ range. IARC questionnaire runs inside Steamworks.

---

## 9. Achievements (Steamworks → Stats & Achievements)

API names must match `scenes/achievements/achievements.gd` exactly. Icons: 256×256 JPG, unlocked + locked (greyscale) each.

| API name | Name | Description |
|---|---|---|
| SECTION_01…12 | The {Section} stands | Finish the {Section} ({ref}) — 12 entries, generated from `GameState.SECTIONS` |
| FIRST_DAY | Let us rise up and build | Finish the first day's work (Neh. 2:18) |
| WALL_DONE | Elul 25 | Finish the wall on day 52 (Neh. 6:15) |
| NONE_THROUGH | Not one slipped through | Finish the wall without a single enemy reaching the city |
| THREE_MARKS | Well built | Earn all three marks on a section |
| ALL_MARKS | Every stone in its place | Hold all three marks on every section |
| SOLO_MARKS | Over against his own house | Earn all three marks on a section working alone (Neh. 3:28) |
| CREW_2 | Two are better than one | Finish a section with a crew of two or more |
| CREW_4 | Every hand at the wall | Finish a section with a crew of four |
| LOADS_DAY | Burden bearer | Deliver 20 loads in a single day |
| FOES_DAY | On guard | Drive off 15 enemies in a single day |
| LOADS_ALL | The strength of the bearers | Deliver 1000 loads in all (Neh. 4:10) |
| FOES_ALL | A watch day and night | Drive off 500 enemies in all (Neh. 4:9) |
| GREAT_WORK | I am doing a great work | *Hidden.* Finish a section the messengers came to without anyone going down to Ono (Neh. 6:3) |

Note: `achievements.gd` references `tools/steam_achievements.md`, which doesn't exist — this table can replace it.

---

## 10. Graphical assets

All required for Coming Soon unless marked. No review scores/awards/"wishlist now" text on capsules. Logo must be legible at small size.

| Asset | Size (px) | Content |
|---|---|---|
| Header capsule | 920×430 | Logo + key art (crew at wall, raider approaching) |
| Small capsule | 462×174 | Logo dominant — art barely visible at this size |
| Main capsule | 1232×706 | Key art + logo, front-page feature |
| Vertical capsule | 748×896 | Portrait crop of key art + logo |
| Page background *(optional)* | 1438×810 | Low-contrast wall/parchment texture |
| Library capsule | 600×900 | Portrait key art + logo |
| Library header | 920×430 | Same as header capsule |
| Library hero | 3840×1240 | Wide scene, **no logo/text**, key area centered |
| Library logo | 1280×720 PNG, transparent | Logo only |
| Community icon | 184×184 JPG | Sling icon (current game icon) |
| Client icon | .ico (16/32/64/256) | `icon.ico` |
| Screenshots | 1920×1080, min 5 (aim 8–10) | Gameplay only, no UI mockups |
| Trailer *(strongly recommended)* | 1920×1080 MP4, 30–90 s | First 5 s = gameplay, not logos |

### Screenshot shot list (render via `tools/*_shots.gd`)
1. 4-player crew at Sheep Gate wall, raider inbound (hero shot)
2. Carry chain — builders passing loads at Dung Gate
3. Two builders hauling a beam at Fish Gate
4. Brute battering a half-built wall, guard slinging
5. Night work by torchlight at Water Gate
6. Mortar trough at Tower of the Ovens
7. Circuit map / story screen (one only)
8. Section result screen with three marks

### Trailer beat sheet (~60 s)
0–5 s crew already building under attack → 5–20 s carry/build/defend each shown → 20–40 s twists montage (beam, night, horn, Ono) → 40–50 s wall rises, day 52 → 50–60 s logo + "Wishlist on Steam" + "Co-op for 2–4".
