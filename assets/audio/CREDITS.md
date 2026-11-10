# Audio credits

All audio is by Kenney (www.kenney.nl), licensed CC0 1.0 (public domain) — no attribution required.

- `sfx/footstep*`, `handleSmallLeather*`, `dropLeather`, `cloth*`, `knifeSlice*` — RPG Audio
- `sfx/impact*` — Impact Sounds
- `jingles/jingles_PIZZI*` — Music Jingles (Pizzicato)

## Music

- `music/calm_caravan.ogg` — "Desert theme" by **yd**, CC0 — https://opengameart.org/content/desert-theme (trimmed, loudness-normalised)
- `music/work_desert_of_dreams.ogg` — "Caryil, The Desert of Dreams" by **insydnis**, CC-BY 3.0 — https://opengameart.org/content/the-desert-of-dreams (loudness-normalised). **Attribution required** — must appear in the game's credits.

Added Nov 10 2026 (all loudness-normalised to -19 LUFS, Vorbis q3; every CC-BY one is in `CreditsRoll`):

- `music/menu_un_desert.ogg` — "Un désert" by **Loyalty Freak Music**, CC0 — https://opengameart.org/content/un-d%C3%A9sert
- `music/story_temple_of_the_manes.ogg` — "Temple of the Manes" by **Kevin MacLeod** (incompetech.com), CC-BY 4.0 (https://creativecommons.org/licenses/by/4.0/) — https://incompetech.com/music/royalty-free/mp3-royaltyfree/Temple%20of%20the%20Manes.mp3. **Attribution required.**
- `music/dark_return_of_the_mummy.ogg` — "Return of the Mummy" by **Kevin MacLeod** (incompetech.com), CC-BY 4.0 (https://creativecommons.org/licenses/by/4.0/) — https://incompetech.com/music/royalty-free/mp3-royaltyfree/Return%20of%20the%20Mummy.mp3. **Attribution required.**
- Changes made (CC-BY 4.0 §3(a)(1)(B)): all of the above were loudness-normalised and re-encoded; noted in `CreditsRoll` ("All music loudness-adjusted from the originals").
- `music/finale_defying_commodus.ogg` — "Defying Commodus" by **Matthew Pablo** (matthewpablo.com), CC-BY 3.0 — https://opengameart.org/content/defying-commodus. **Attribution required.**
- `music/calm_old_music.ogg` — "Old Music" by **Alexandr Zhelanov** (soundcloud.com/alexandr-zhelanov), CC-BY 3.0 — https://opengameart.org/content/old-music. **Attribution required.**
- `music/work_ancient_temple.ogg` — "Ancient Temple" by **Alexandr Zhelanov**, CC-BY 4.0 — https://opengameart.org/content/ancient-temple. **Attribution required.**
- `music/calm_mystic_journey.ogg` — "Mystic Journey" by **Tausdei**, CC-BY 3.0 — https://opengameart.org/content/mystic-journey. **Attribution required.**
- `music/calm_nomads.ogg` — "Nomads" by **elerya**, CC-BY 3.0 — https://opengameart.org/content/nomads. **Attribution required.**

Rejected: "Desert calmness and fighting" (Dizzy Crow, CC0) — made for a fan game of a film series, its "adventurer's theme" may quote a copyrighted film score, and it's built on Hava Nagila (20th c.).

- `sfx/horn_000–002.ogg` — ram's horn blast, synthesized for this project (no third-party source)
- `sfx/shatter_000–003.ogg`, `sfx/splash_000–002.ogg` — clay jar breaking / its water spilling, synthesized for this project by `tools/synth_sherds.py`
- `sfx/wings_000–002.ogg`, `sfx/chirp_000–003.ogg`, `sfx/coo_000–002.ogg` — a flock taking off, sparrow chirps, a rock dove cooing, synthesized for this project by `tools/synth_birds.py`

- `music/alkakrab/*.ogg` — "Free 6 Desert Fantasy Ambient Tracks" by **AlkaKrab** — https://alkakrab.itch.io/free-6-desert-fantasy-ambient-tracks-game-music-pack (loop versions, gain-matched to -19 LUFS, Vorbis q3). Royalty-free, commercial use OK, credit appreciated not required. **Not in git:** license forbids redistributing the files as-is (open-source use needs the author's permission), so they are gitignored — re-extract from the pack (Loops/wav) to build with them.

## Narration

- `narration/en/*.ogg` — story cards read aloud, synthesized locally with **Kokoro-82M** (Apache 2.0, voice "am_michael") by `tools/narration/narrate.py` (Not Covered's pipeline). AI-generated: declare it in Steam's AI content disclosure. Keyed by md5 of the line; `lines.tsv` lists which file is which.
