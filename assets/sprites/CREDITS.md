# Sprite credits

Character sheets are built with the **Universal LPC Spritesheet Character Generator**
(https://github.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator).
LPC art is dual-licensed CC-BY-SA 3.0 / GPL 3.0 (some layers also OGA-BY / CC-BY) — attribution
to the individual layer authors is required when distributing the game.

| File | Layers |
|------|--------|
| `player.png`, `enemy.png` | Generated with the tool above (base body, clothing, equipment) |
| `player_1..4.png` | `player.png` (eyes recoloured brown) + `feet/sandals/male` + `legs/skirts/plain/male` + `torso/clothes/longsleeve/longsleeve/male` + `torso/waist/sash_narrow/male` + `hat/cloth/bandana/adult`; tunic dyed per player. Built by `tools/build_player_sheets.py` |

TODO before release: copy the exact author lines for each layer from the generator's
`CREDITS.csv` into this file.
