"""Build the Hangul fallback fonts (assets/fonts/NotoSerifKR/*-subset.ttf).

Cinzel and Spectral have no Hangul, and the web build can't fall back to a system
font, so Settings adds these behind every UI font. Noto Serif KR (SIL OFL 1.1) is
~24 MB; this keeps the 2,350 common syllables of KS X 1001 plus every character
ko.po uses, at two weights.

    pip install fonttools
    python tools/i18n/subset_kr_font.py [path/to/NotoSerifKR[wght].ttf]

Without a path it downloads the variable font from github.com/google/fonts.
Rerun after ko.po gains characters outside KS X 1001 (the check prints them).
"""
import os
import sys
import tempfile
import urllib.request

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "fonts", "NotoSerifKR")
SRC_URL = "https://github.com/google/fonts/raw/main/ofl/notoserifkr/NotoSerifKR%5Bwght%5D.ttf"
WEIGHTS = {"Medium": 500, "Bold": 700}


def wanted_text():
    chars = set()
    # KS X 1001: the Hangul syllables EUC-KR can encode
    for cp in range(0xAC00, 0xD7A4):
        try:
            # Two bytes = a real KS X 1001 code; Python spells the rest as 8-byte jamo runs
            if len(chr(cp).encode("euc-kr")) == 2:
                chars.add(chr(cp))
        except UnicodeEncodeError:
            pass
    ko = open(os.path.join(ROOT, "locale", "ko.po"), encoding="utf-8").read()
    extra = {c for c in ko if ord(c) > 0x7F}
    missing = sorted(c for c in extra if 0xAC00 <= ord(c) <= 0xD7A3 and c not in chars)
    if missing:
        print("ko.po uses syllables outside KS X 1001 (kept):", "".join(missing))
    chars |= extra
    # Compatibility jamo and CJK punctuation, for names and typed text
    chars |= {chr(c) for c in range(0x3131, 0x318F)}
    chars |= {chr(c) for c in range(0x3000, 0x3040)}
    return "".join(sorted(chars))


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else None
    if src is None:
        src = os.path.join(tempfile.gettempdir(), "NotoSerifKR-var.ttf")
        if not os.path.exists(src):
            print("downloading", SRC_URL)
            urllib.request.urlretrieve(SRC_URL, src)
    os.makedirs(OUT, exist_ok=True)
    text = wanted_text()
    for name, wght in WEIGHTS.items():
        font = instancer.instantiateVariableFont(TTFont(src), {"wght": wght})
        opts = subset.Options()
        opts.hinting = False   # Godot rasterizes unhinted by default
        opts.name_IDs = ["*"]
        opts.name_languages = ["*"]
        opts.notdef_outline = True
        sub = subset.Subsetter(opts)
        sub.populate(text=text)
        sub.subset(font)
        path = os.path.join(OUT, f"NotoSerifKR-{name}-subset.ttf")
        font.save(path)
        print(path, os.path.getsize(path) // 1024, "KB")


if __name__ == "__main__":
    main()
