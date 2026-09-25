# Sprite credits

Character sheets are built with the **Universal LPC Spritesheet Character Generator**
(https://github.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator).
LPC art is dual-licensed CC-BY-SA 3.0 / GPL 3.0 (some layers also OGA-BY / CC-BY) — attribution
to the individual layer authors is required when distributing the game.

| File | Layers |
|------|--------|
| `player.png`, `enemy.png` | Generated with the tool above (base body, clothing, equipment) |
| `player_1..4.png` | `player.png` (eyes recoloured brown) + `feet/sandals/male` + `legs/skirts/plain/male` + `torso/clothes/longsleeve/longsleeve/male` + `torso/waist/sash_narrow/male` + `hat/cloth/bandana/adult`; tunic dyed per player. Built by `tools/build_player_sheets.py` |
| `enemy_scout/brute/raider.png` | Built by `tools/build_enemy_sheets.py`: `body/bodies/{male,muscular}` + `head/heads/human/{male,male_gaunt}` + `eyes/human/adult/anger` + `beards/beard/{basic,medium}` + `legs/skirts/plain/male` + `feet/sandals/male`; scout: `torso/clothes/shortsleeve` + `torso/waist/belt_leather` + `hat/cloth/hijab` + `weapon/polearm/spear`; brute: `torso/armour/leather` + `hat/helmet/pointed` + `shield/scutum` + `shield/scutum_trim` + spear; raider: shortsleeve + `torso/waist/sash_narrow` + `cape/tattered` + hijab + `weapon/sword/dagger`. Recoloured (skin, goat-hair cloth, bronze) |

TODO before release: copy the exact author lines for each layer from the generator's
`CREDITS.csv` into this file.
