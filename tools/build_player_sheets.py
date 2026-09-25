"""Rebuild assets/sprites/player_1..4.png from LPC layers.

Needs a (sparse) clone of the Universal LPC Spritesheet Character Generator:
  git clone --filter=blob:none --depth 1 \
    https://github.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator.git lpc
Usage: python tools/build_player_sheets.py <path-to-lpc-clone>
"""
import colorsys
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SPRITES = ROOT / "assets" / "sprites"
L = Path(sys.argv[1]) / "spritesheets"

# Universal sheet layout: animation -> first row (4 direction rows, hurt has 1)
ROWS = {"spellcast": 0, "thrust": 4, "walk": 8, "slash": 12, "shoot": 16, "hurt": 20,
        "climb": 21, "idle": 22, "jump": 26, "sit": 30, "emote": 34, "run": 38,
        "combat_idle": 42, "backslash": 46, "halfslash": 50}
# Layers missing an animation borrow another one's frames (anim, column remap)
FALLBACK = {"run": ("walk", [1, 2, 3, 4, 5, 6, 7, 8]), "idle": ("walk", [0, 0]),
            "combat_idle": ("walk", [0, 0]), "halfslash": ("slash", None),
            "backslash": ("slash", None)}
# Greyscale cloth ramp used by recolourable LPC layers (dark -> light)
SRC_RAMP = [(77, 74, 93), (149, 128, 128), (196, 181, 159), (229, 230, 199), (255, 255, 255)]
# Base body ships with blue eyes — period-appropriate brown
EYES = {(42, 60, 73): (44, 28, 22), (86, 134, 174): (88, 56, 36), (87, 206, 228): (132, 92, 58)}

LINEN = (196, 182, 150)
LEATHER = (118, 84, 56)
# Tunic dye per player slot — follows main.gd PLAYER_COLORS (amber, green, red, blue)
DYES = [(200, 142, 56), (110, 120, 62), (158, 72, 54), (64, 88, 132)]


def ramp(base):
    h, l, s = colorsys.rgb_to_hls(*(c / 255 for c in base))
    out = []
    for t in (-0.26, -0.12, 0.0, 0.12, 0.22):
        hh = (h + (-0.02 if t < 0 else 0.015) * abs(t) / 0.2) % 1
        ll = min(0.92, max(0.08, l + t))
        ss = max(0.0, s * (1.0 - abs(t) * 0.8))
        out.append(tuple(int(c * 255) for c in colorsys.hls_to_rgb(hh, ll, ss)))
    return out


def remap(im, table):
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            c = px[x, y]
            if c[3] and c[:3] in table:
                px[x, y] = table[c[:3]] + (c[3],)
    return im


def load(layer, anim):
    p = L / layer / f"{anim}.png"
    return Image.open(p).convert("RGBA") if p.exists() else None


def layer_anim(layer, anim):
    im = load(layer, anim)
    if im is not None or anim not in FALLBACK:
        return im
    src_anim, cols = FALLBACK[anim]
    src = load(layer, src_anim)
    if src is None or cols is None:
        return src
    out = Image.new("RGBA", (64 * len(cols), src.height))
    for i, c in enumerate(cols):
        out.paste(src.crop((c * 64, 0, c * 64 + 64, src.height)), (i * 64, 0))
    return out


def compose(base, layers):
    sheet = base.copy()
    for layer, color in layers:
        table = dict(zip(SRC_RAMP, ramp(color))) if color else None
        for anim, row in ROWS.items():
            im = layer_anim(layer, anim)
            if im is None:
                continue
            if table:
                im = remap(im, table)
            region = Image.new("RGBA", sheet.size)
            region.paste(im.crop((0, 0, min(im.width, sheet.width), im.height)), (0, row * 64))
            sheet.alpha_composite(region)
    return sheet


def main():
    base = remap(Image.open(SPRITES / "player.png").convert("RGBA"), EYES)
    for i, dye in enumerate(DYES):
        sheet = compose(base, [
            ("feet/sandals/male", None),
            ("legs/skirts/plain/male", dye),                    # knee-length tunic skirt
            ("torso/clothes/longsleeve/longsleeve/male", dye),
            ("torso/waist/sash_narrow/male", LEATHER),
            ("hat/cloth/bandana/adult", LINEN),
        ])
        sheet.save(SPRITES / f"player_{i + 1}.png")
        print("wrote", f"player_{i + 1}.png")


if __name__ == "__main__":
    main()
