# Handoff: player character models

Goal: make the four crew figures (worker slots 0-3) look better. They are the
most-seen thing in the game. Blender is available.

## Where things stand (Nov 11 2026)

- **Figures are built in code.** `scenes/shared/character_rig.gd` (rig, poses,
  looks, ~1800 lines), `builder_head.gd` (face, hair, beard, hats),
  `builder_body.gd` (tunic, robe, belt, basket, sleeves). Each figure is about
  130-200 MeshInstance3D parts on pivots. Looks come from
  `CharacterRig.worker_look(slot, color)`. Enemies use `enemy_look`, folk use
  `Folk.look_for`, all on the same head and body.
- **Blender spike, committed 020fcd8, opt-in, builder (slot 0) only.**
  `tools/blender/build.ps1 [-Slot 0] [-Name builder] [-Shots]` runs
  `export_rig.gd` (dumps the code rig at rest to JSON), then `build_figure.py`
  (Blender: fuses parts by cap holes, voxel remesh, smooth, grooves for hair and
  beard, decimate, bakes AO and paint, exports a glb), then a Godot import.
  Output: `assets/models/figures/builder.glb`. At runtime,
  `scenes/shared/baked_figure.gd` skins the glb to the code pivots, so all
  animation stays in code. Shader `baked_figure.gdshader`: COLOR is sRGB paint
  (convert it to linear), dye verts with a=0 store shade, and the `dye` instance
  uniform needs source_color. Turn it on with the look key
  `"baked": "res://assets/models/figures/builder.glb"`.
  - Perf (40 figures, Radeon 890M): code rig 12.6 ms, baked 8.7 ms. Objects go
    from 12,682 to 122. 127k tris per figure, which is high.
  - Known weak spots: tunic shoulders a bit lumpy, collar lapels lost in the
    fuse. Hammer, paddle and sword stay code parts (`kept_pivots`).
  - Not done yet: slots 1-3, trades, enemies, folk. `set_look` rebuilds. Dye
    logic per look.
- **Review harnesses** (Godot path below):
  - `tools/blender/compare_shots.gd`: code rig vs baked, side by side.
    Poses idle/walk/run/build. Views front/iso/back/close/head/head_side/body.
  - `tools/look_lineup.gd -- <out_dir> <tag>`: trades, folk and enemies.
  - `tools/cast_lineup.gd`: before/after lineup.
  - `tools/perf_crowd.gd --builder [--baked]`: crowd frame time.

## Tools

- Godot 4.7.2 console:
  `C:\Users\chris\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`
- Blender 5.2.3 portable: `C:\Users\chris\blender\blender-5.2.3-windows-x64\blender.exe`
  (run with `-b --factory-startup -P script.py`)
- Screenshots: `--path . --write-movie <dir>\f.png --fixed-fps 10 --quit-after N --script <harness.gd>`.
  In `--script` harnesses autoloads are not in scope, so use `root.get_node`.
- Look at the PNGs yourself (Read tool) before showing the user anything.

## Art rules (do not break)

- **Cartoony figures, earnest story** (GDD §6.2). Big head (`HEAD_SCALE` 1.15),
  short legs (`LEG_STRETCH` 0.85), big eyes with a catchlight, fists 1.05. The
  tall build was cut on purpose, so don't bring it back. No slapstick, no neon.
- **HD-2D, seen from an isometric play camera.** A figure is small on screen
  with 4 players at once, so the silhouette and the crew colour must read at
  play distance before close-up detail matters. Judge from the play camera
  first, close-ups second.
- **Crew colour is the player ID.** Worker dye has to stay strong and readable.
  CrewMark shapes exist for colour-blind players, so keep them.
- **Skin parity.** Every figure takes skin from `CharacterRig.SKIN`. Foes are
  set apart by cloth, outline and silhouette, never by skin tone.
- **455 BCE Judean workers.** Tunics, belts, head cloths, sandals or bare feet.
  Modest clothing. No fantasy armour on the crew, no anachronisms. Write BCE,
  never BC.
- Palette: warm and earthy (`scenes/shared/palette.gd`). Warm ambient, no blue
  shadows.
- Player-facing strings: no em dashes. Use ":" or ".".

## Constraints

- Animation, poses, blink, hair tails and skirt sway live in code (`char_anim.gd`,
  CharacterRig). A Blender mesh must skin to the existing pivots (`bone_map` in
  baked_figure.gd). Don't fork the animation into Blender unless the user agrees.
- Perf targets: web (WebGL, LIVE at nehemiahgame.com) and Android (mobile-spike
  branch) are weaker than desktop. Lower the tri count, don't raise it.
- Multiplayer: looks must come out the same on every peer (use deterministic
  picks like `name.hash()`, never randi).
- Work on master only. Don't branch without asking. Don't commit until the user
  says so.
- After any rig or figure change, re-shoot the twist cards:
  `powershell -File tools/twist_pics.ps1`.

## Suggested approach

1. **Diagnose first.** Render the current crew from the play camera and up
   close (code rig and baked builder), look at the shots, and list the 5-8
   biggest visual problems. Ask the user which ones matter to them before you
   build anything.
2. **Pick a route with the user:**
   - A. Keep the design in code and push the Blender fuse pipeline further:
     roll it out to slots 1-3, fix the shoulders and collar, cut tris toward
     about 30-50k.
   - B. Hand-author a base mesh in Blender (sculpt, retopo, paint) that skins
     to the same pivots. Higher ceiling, more work, and design changes then
     happen in Blender instead of code.
   - C. A mix: code proportions plus hand-made pieces where the fuse is weak
     (hands, hair, cloth folds).
3. Work in small passes. Show before/after shots at play distance after each
   one. Measure with perf_crowd at the end of each pass.
