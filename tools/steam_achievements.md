# Steam achievements — Steamworks setup

Source of truth: `scenes/achievements/achievements.gd` (`all()`). Enter these under
Steamworks → Stats & Achievements → Achievements, API names exactly as below, then
publish. Each needs a 256×256 icon (achieved) and a greyed one (unachieved).

Nothing is sent to Steam while `NetworkManager.STEAM_APP_ID` is 480 (Spacewar). Unlocks
are still saved in `user://progress.cfg` and pushed on the first start under the real ID.

| API name | Display name | Description | Hidden |
|---|---|---|---|
| SECTION_01 | The Sheep Gate stands | Finish the Sheep Gate (Neh. 3:1) | |
| SECTION_02 | The Fish Gate stands | Finish the Fish Gate (Neh. 3:3) | |
| SECTION_03 | The Jeshanah Gate stands | Finish the Jeshanah Gate (Neh. 3:6) | |
| SECTION_04 | The Broad Wall stands | Finish the Broad Wall (Neh. 3:8) | |
| SECTION_05 | The Tower of the Ovens stands | Finish the Tower of the Ovens (Neh. 3:11) | |
| SECTION_06 | The Valley Gate stands | Finish the Valley Gate (Neh. 3:13) | |
| SECTION_07 | The Gate of the Ash Heaps stands | Finish the Gate of the Ash Heaps (Neh. 3:14) | |
| SECTION_08 | The Fountain Gate stands | Finish the Fountain Gate (Neh. 3:15) | |
| SECTION_09 | The Water Gate stands | Finish the Water Gate (Neh. 3:26) | |
| SECTION_10 | The Horse Gate stands | Finish the Horse Gate (Neh. 3:28) | |
| SECTION_11 | The East Gate stands | Finish the East Gate (Neh. 3:29) | |
| SECTION_12 | The Miphkad Gate stands | Finish the Miphkad Gate (Neh. 3:31) | |
| FIRST_DAY | Let us rise up and build | Finish the first day's work (Neh. 2:18) | |
| WALL_DONE | Elul 25 | Finish the wall on day 52 (Neh. 6:15) | |
| NONE_THROUGH | Not one slipped through | Finish the wall without a single enemy reaching the city | |
| THREE_MARKS | Well built | Earn all three marks on a section | |
| ALL_MARKS | Every stone in its place | Hold all three marks on every section | |
| SOLO_MARKS | Over against his own house | Earn all three marks on a section working alone (Neh. 3:28) | |
| CREW_2 | Two are better than one | Finish a section with a crew of two or more | |
| CREW_4 | Every hand at the wall | Finish a section with a crew of four | |
| LOADS_DAY | Burden bearer | Deliver 20 loads in a single day | |
| FOES_DAY | On guard | Drive off 15 enemies in a single day | |
| LOADS_ALL | The strength of the bearers | Deliver 1000 loads in all (Neh. 4:10) | |
| FOES_ALL | A watch day and night | Drive off 500 enemies in all (Neh. 4:9) | |
| GREAT_WORK | I am doing a great work | Finish a section the messengers came to without anyone going down to Ono (Neh. 6:3) | ✓ |

Thresholds (`LOADS_IN_A_DAY`, `FOES_IN_A_DAY`, `LOADS_TOTAL`, `FOES_TOTAL`) are first
guesses — tune from playtest tallies and update this table.
Localized names/descriptions go in Steamworks per language (es, pt-BR, de, ko).
