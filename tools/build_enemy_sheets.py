"""Rebuild assets/sprites/enemy_scout|brute|raider.png from LPC layers.

Needs a (sparse) clone of the Universal LPC Spritesheet Character Generator — see
build_player_sheets.py. Extra sparse paths: body/bodies/{male,muscular},
head/heads/human/{male,male_gaunt}, eyes/human/adult/anger, hair/buzzcut,
beards/beard/{basic,medium}, hat/cloth/hijab, hat/helmet/pointed,
torso/clothes/shortsleeve/shortsleeve, torso/armour/leather, cape/tattered,
shield/{scutum,scutum_trim}, weapon/polearm/spear, weapon/sword/dagger.
Usage: python tools/build_enemy_sheets.py <path-to-lpc-clone>

Art direction: enemies share one colour family no player uses — undyed black
goat-hair and dark oxblood leather, bronze fittings. Players are mid-value and
saturated; enemies are dark, so friend/foe reads by value before hue.
Scout = Samaritan levy (headcloth, spear). Brute = Ammonite heavy (conical
helmet, leather, tall shield). Raider = Geshem's Arab (wrapped head, trailing
cloak, dagger).
"""
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_player_sheets import FALLBACK, ROWS, SRC_RAMP, ramp, remap  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SPRITES = ROOT / "assets" / "sprites"
L = Path(sys.argv[1]) / "spritesheets"
SHEET_SIZE = (832, 3456)

# Only the animations enemies play (enemy.gd _ANIMS): thrust, walk, idle, hurt
ANIMS = {a: ROWS[a] for a in ("thrust", "walk", "hurt", "idle")}

# Default LPC "light" skin ramp -> Levantine olive/tan
SKIN = {(250, 236, 231): (214, 172, 132), (249, 213, 186): (198, 150, 108),
        (228, 164, 124): (172, 122, 82), (204, 134, 101): (142, 96, 64),
        (153, 66, 60): (98, 58, 42)}
SKIN_DARK = {k: tuple(int(c * 0.86) for c in v) for k, v in SKIN.items()}
# Blue eyes -> dark brown; whites slightly warm so they don't glow
EYES = {(41, 61, 75): (34, 22, 18), (80, 212, 236): (92, 60, 40), (81, 135, 179): (62, 40, 28),
        (87, 206, 228): (92, 60, 40), (242, 247, 248): (226, 218, 204)}
# Orange hair/beard ramp -> near-black brown
HAIR = {(255, 138, 0): (84, 60, 44), (229, 86, 0): (66, 46, 34), (191, 64, 0): (52, 36, 28),
        (164, 38, 0): (42, 28, 22), (106, 17, 8): (30, 20, 18)}

GOATHAIR = (54, 46, 52)    # undyed black goat-hair, faint violet cast
DUSK = (44, 40, 58)        # raider wrap — indigo-black
OXBLOOD = (86, 44, 38)
# Grey-metal ramp -> bronze
BRONZE = {(29, 19, 30): (40, 24, 20), (77, 74, 93): (92, 62, 36), (114, 107, 126): (140, 98, 52),
          (134, 126, 127): (166, 122, 66), (177, 153, 152): (196, 152, 90)}


def cloth(base):
    return dict(zip(SRC_RAMP, ramp(base)))


PREFERRED = ("medium", "spear", "dagger", "scutum", "scutum_trim")


def find(layer, anim):
    """Layer dirs come as <dir>/<anim>.png or <dir>/<anim>/<variant>.png."""
    d = L / layer
    p = d / f"{anim}.png"
    if p.exists():
        return Image.open(p).convert("RGBA")
    sub = d / anim
    if sub.is_dir():
        files = sorted(sub.glob("*.png"), key=lambda f: f.stem not in PREFERRED)
        if files:
            return Image.open(files[0]).convert("RGBA")
    return None


def layer_anim(layer, anim):
    im = find(layer, anim)
    if im is not None or anim not in FALLBACK:
        return im
    src_anim, cols = FALLBACK[anim]
    src = find(layer, src_anim)
    if src is None or cols is None:
        return src
    out = Image.new("RGBA", (64 * len(cols), src.height))
    for i, c in enumerate(cols):
        out.paste(src.crop((c * 64, 0, c * 64 + 64, src.height)), (i * 64, 0))
    return out


def compose(layers):
    """layers: (path, colour table or None) in back-to-front order."""
    sheet = Image.new("RGBA", SHEET_SIZE)
    for layer, table in layers:
        for anim, row in ANIMS.items():
            im = layer_anim(layer, anim)
            if im is None:
                continue
            if table:
                im = remap(im.copy(), table)
            region = Image.new("RGBA", sheet.size)
            region.paste(im.crop((0, 0, min(im.width, sheet.width), im.height)), (0, row * 64))
            sheet.alpha_composite(region)
    return sheet


def face(skin, head="head/heads/human/male"):
    return [(head, {**skin, **EYES}), ("eyes/human/adult/anger", EYES)]


def main():
    types = {
        "scout": [
            ("weapon/polearm/spear/background", BRONZE),
            ("body/bodies/male", SKIN),
            *face(SKIN),
            ("legs/skirts/plain/male", cloth(GOATHAIR)),
            ("torso/clothes/shortsleeve/shortsleeve/male", cloth(GOATHAIR)),
            ("torso/waist/belt_leather/male", None),
            ("feet/sandals/male", None),
            ("beards/beard/basic", HAIR),
            ("hat/cloth/hijab/male", cloth((84, 72, 64))),   # coarse undyed wool wrap
            ("weapon/polearm/spear/foreground", BRONZE),
        ],
        "brute": [
            ("shield/scutum/paint/bg", cloth(OXBLOOD)),
            ("shield/scutum_trim/bg", BRONZE),
            ("weapon/polearm/spear/background", BRONZE),
            ("body/bodies/muscular", SKIN_DARK),
            *face(SKIN_DARK),
            ("legs/skirts/plain/male", cloth(OXBLOOD)),
            ("torso/armour/leather/male", None),
            ("feet/sandals/male", None),
            ("beards/beard/medium", HAIR),
            ("hat/helmet/pointed/adult", BRONZE),
            ("weapon/polearm/spear/foreground", BRONZE),
            ("shield/scutum/paint/fg/male", cloth(OXBLOOD)),
            ("shield/scutum_trim/fg/male", BRONZE),
        ],
        "raider": [
            ("cape/tattered/bg", cloth(DUSK)),
            ("weapon/sword/dagger/behind", BRONZE),
            ("body/bodies/male", SKIN_DARK),
            *face(SKIN_DARK, "head/heads/human/male_gaunt"),
            ("legs/skirts/plain/male", cloth(DUSK)),
            ("torso/clothes/shortsleeve/shortsleeve/male", cloth(DUSK)),
            ("torso/waist/sash_narrow/male", cloth(OXBLOOD)),
            ("feet/sandals/male", None),
            ("beards/beard/basic", HAIR),
            ("cape/tattered/fg", cloth(DUSK)),
            ("hat/cloth/hijab/male", cloth(DUSK)),
            ("weapon/sword/dagger", BRONZE),
        ],
    }
    for name, layers in types.items():
        compose(layers).save(SPRITES / f"enemy_{name}.png")
        print("wrote", f"enemy_{name}.png")


if __name__ == "__main__":
    main()
