"""Redraws the Takiko Games logo as vectors from the 1152×922 source image.

The wave panel is traced: upscaled, snapped to the logo's five inks, and outlined by
vtracer. The wordmark is not traced: it is Montserrat Bold glyph outlines, fitted to where
each line of text sits in the source, so it stays sharp at any size and needs no font.

    pip install vtracer fonttools pillow numpy
    python tools/brand/redraw_logo.py
    npx svgo@3 --multipass -p 2 assets/brand/*.svg

Writes assets/brand/takiko_{logo,logo_light,mark,wordmark}.svg. Montserrat (SIL OFL) is
downloaded next to this script on first run.
"""
import re
import urllib.request
from pathlib import Path

import numpy as np
import vtracer
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from PIL import Image, ImageFilter

HERE = Path(__file__).parent
BRAND = HERE.parent.parent / "assets" / "brand"
SRC = BRAND / "takiko_games_source.png"
FONT = HERE / "Montserrat.ttf"
FONT_URL = "https://github.com/google/fonts/raw/main/ofl/montserrat/Montserrat%5Bwght%5D.ttf"

PX0, PY0, PW, PH = 431, 157, 290, 463   # the panel in source px
INSET = 3       # source px trimmed off the panel before tracing: its edge is paper-tinted
SCALE = 6       # upscale before tracing
PAD = 30        # traced px mirrored past each edge, so vtracer's border slivers fall outside the clip
FRAME = 5       # source px along the edges where the dark hairline becomes panel navy
WEIGHT = 700

# The logo's inks (k-means off the source, pinned so reruns match). Anti-alias midtones
# (foam fringe) get no colour of their own: they go to the nearest ink
INKS = np.array([(13, 48, 57), (15, 62, 76), (41, 85, 93), (56, 113, 109), (241, 245, 242)], np.float32)
NAVY = "#0e3d4b"    # panel ground
TEXT = "#0e313d"    # wordmark on light grounds
CREAM = "#f0e8d6"   # wordmark on dark grounds


def trace_panel(tmp: Path) -> list[str]:
    src = Image.open(SRC).convert("RGB")
    src = src.crop((PX0 + INSET, PY0 + INSET, PX0 + PW - INSET, PY0 + PH - INSET))
    big = src.resize((src.width * SCALE, src.height * SCALE), Image.LANCZOS)
    big = big.filter(ImageFilter.GaussianBlur(SCALE * 0.45))
    px = np.asarray(big).reshape(-1, 3).astype(np.float32)
    labels = np.empty(len(px), np.uint8)
    for i in range(0, len(px), 400_000):
        labels[i:i + 400_000] = np.argmin(((px[i:i + 400_000, None] - INKS[None]) ** 2).sum(-1), 1)
    lab = labels.reshape(big.height, big.width)
    # Mode filter knocks out single-pixel speckle along region borders
    lab = np.asarray(Image.fromarray(lab).filter(ImageFilter.ModeFilter(5))).copy()
    # The source frames the panel with a dark hairline a few px in; near the edges the
    # darkest ink becomes the panel navy so the frame reads as one clean colour
    band = np.zeros_like(lab, bool)
    b = FRAME * SCALE
    band[:b] = band[-b:] = True
    band[:, :b] = band[:, -b:] = True
    lab[band & (lab == 0)] = 1
    lab = np.pad(lab, PAD, mode="reflect")
    flat, svg = tmp / "panel_flat.png", tmp / "panel_traced.svg"
    Image.fromarray(INKS.astype(np.uint8)[lab]).save(flat)
    vtracer.convert_image_to_svg_py(
        str(flat), str(svg),
        colormode="color", hierarchical="stacked", mode="spline",
        filter_speckle=24, color_precision=8, layer_difference=8,
        corner_threshold=60, length_threshold=4.0, splice_threshold=45, path_precision=1,
    )
    return re.findall(r"<path[^>]*/>", svg.read_text(encoding="utf-8"))


def text_boxes() -> list[tuple[int, int, int, int]]:
    """Ink box (x0, y0, x1, y1) of each line of the source wordmark, in source px."""
    im = np.asarray(Image.open(SRC).convert("L")).astype(int)
    top, left = PY0 + PH + 10, PX0 - 5
    dark = im[top:top + 130, left:PX0 + PW + 5] < 150
    rows = np.where(dark.any(1))[0]
    split = np.where(np.diff(rows) > 3)[0][0]
    boxes = []
    for y0, y1 in [(rows[0], rows[split]), (rows[split + 1], rows[-1])]:
        cols = np.where(dark[y0:y1 + 1].any(0))[0]
        boxes.append((left + cols[0], top + y0, left + cols[-1] + 1, top + y1 + 1))
    return boxes


def wordmark(boxes) -> str:
    if not FONT.exists():
        urllib.request.urlretrieve(FONT_URL, FONT)
    font = instancer.instantiateVariableFont(TTFont(FONT), {"wght": WEIGHT})
    gs, cmap = font.getGlyphSet(), font.getBestCmap()

    def line(word, box):
        # Cap height sets the scale; tracking is solved so the ink width matches too
        x0, y0, x1, y1 = box
        glyphs = [gs[cmap[ord(c)]] for c in word]
        ink = []
        for g in glyphs:
            bp = BoundsPen(gs)
            g.draw(bp)
            ink.append(bp.bounds)
        bottom = min(b[1] for b in ink)
        s = (y1 - y0) / (max(b[3] for b in ink) - bottom)
        base = sum(g.width for g in glyphs[:-1]) + ink[-1][2] - ink[0][0]
        track = ((x1 - x0) / s - base) / (len(word) - 1)
        parts, x = [], -ink[0][0]
        for g in glyphs:
            pen = SVGPathPen(gs)
            g.draw(pen)
            parts.append(f'<path transform="translate({x:.1f} 0)" d="{pen.getCommands()}"/>')
            x += g.width + track
        return (f'<g transform="translate({x0 - PX0:.2f} {y1 + bottom * s - PY0:.2f}) scale({s:.5f} {-s:.5f})">'
                + "".join(parts) + "</g>")

    return line("TAKIKO", boxes[0]) + line("GAMES", boxes[1])


def write(name, body, w, h, x=0.0, y=0.0):
    out = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{x:g} {y:g} {w:g} {h:g}" role="img">'
           f"<title>Takiko Games</title>{body}</svg>")
    (BRAND / name).write_text(out, encoding="utf-8")
    print(name, f"{len(out) // 1024} KiB")


def main():
    tmp = HERE / ".build"
    tmp.mkdir(exist_ok=True)
    k = 1 / SCALE
    off = INSET - PAD * k
    panel = (f'<clipPath id="panel"><rect width="{PW}" height="{PH}"/></clipPath>'
             f'<g clip-path="url(#panel)"><rect width="{PW}" height="{PH}" fill="{NAVY}"/>'
             f'<g transform="translate({off:.3f} {off:.3f}) scale({k:.6f})">'
             + "".join(trace_panel(tmp)) + "</g></g>")
    boxes = text_boxes()
    words = wordmark(boxes)
    h = boxes[1][3] - PY0
    write("takiko_logo.svg", panel + f'<g fill="{TEXT}">{words}</g>', PW, h)
    write("takiko_logo_light.svg", panel + f'<g fill="{CREAM}">{words}</g>', PW, h)
    write("takiko_mark.svg", panel, PW, PH)
    tx = min(b[0] for b in boxes) - PX0
    ty = boxes[0][1] - PY0
    write("takiko_wordmark.svg", f'<g fill="{TEXT}">{words}</g>',
          max(b[2] for b in boxes) - PX0 - tx, h - ty, tx, ty)


if __name__ == "__main__":
    main()
