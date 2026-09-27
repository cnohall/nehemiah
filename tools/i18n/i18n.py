"""Translation upkeep for the game (locale/*.po, gettext; the English text is the key).

    python tools/i18n/i18n.py pot     # rewrite locale/messages.pot from the code
    python tools/i18n/i18n.py check   # what's missing, stale or broken in each .po

What counts as translatable:
  - tr("..."), tr_n("...", "..."), TranslationServer.translate("...") in .gd
  - text / tooltip_text / placeholder_text in .tscn (Labels and Buttons translate
    their own text at draw time, so a literal set on one needs no tr())
  - string literals in .gd that already have an entry in a .po (the check reports
    likely UI sentences that don't, so new ones get noticed)

Placeholders (%s, %d, {interact}) must appear in the same order in every language:
GDScript's % operator has no positional arguments.
"""
import glob
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LOCALE = os.path.join(ROOT, "locale")

STR = r'"((?:[^"\\]|\\.)*)"'
TR = re.compile(r'\b(?:tr|TranslationServer\.translate)\(\s*' + STR)
TR_N = re.compile(r'\btr_n\(\s*' + STR + r'\s*,\s*' + STR)
LIT = re.compile(STR)
TSCN = re.compile(r'^(?:text|tooltip_text|placeholder_text) = ' + STR + r'\s*$', re.M)
FMT = re.compile(r"%[-0-9.]*[sdf%]|\{[a-z]+\}")
# Lines whose strings never reach the player
QUIET = re.compile(r'print|push_warning|push_error|printerr|assert|get_node|has_node|\$|^\s*#|preload|load\(|add_sync|call_group|is_in_group|add_to_group|has_method|connect\(')
# Not player text, or not a msgid on its own: scene preview values the code overwrites,
# world-tag markup that WorldTag takes apart ("Wall 80%"), Steam's rich presence
IGNORE = {
    "of 52", "Day 1", "Day 52 of 52", "1 of 4 builders here", "Sheep Gate · Neh. 3:1",
    "A new stretch: Sheep Gate · Neh. 3:1", "Wall %d%%", "Building the wall", "Desert theme", "Hold RT",
}
# Built at runtime (kind.capitalize() on a world tag), so no literal in the code
DYNAMIC = {"Stone", "Wood", "Mortar", "Lime", "Water", "Beam", "Beams", "Rubble"}
# A literal that reads like UI text: two words or more, starting with a capital
SENTENCE = re.compile(r'^[A-Z][a-z’\']+( [A-Za-z’\'—·,.!?…:%s]+)+[.!?…]?$')


def unescape(s):
    return s.encode("utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8") if "\\" in s else s


def files(pattern):
    return [f for f in glob.glob(os.path.join(ROOT, "scenes", "**", pattern), recursive=True)]


def scan():
    """msgid → plural (or None), plus every literal in .gd for the stale / candidate checks."""
    ids, literals = {}, {}
    for f in files("*.gd"):
        rel = os.path.relpath(f, ROOT)
        for n, line in enumerate(open(f, encoding="utf-8"), 1):
            for m in TR_N.finditer(line):
                ids[unescape(m.group(1))] = unescape(m.group(2))
            for m in TR.finditer(line):
                ids.setdefault(unescape(m.group(1)), None)
            if QUIET.search(line):
                continue
            for m in LIT.finditer(line):
                literals.setdefault(unescape(m.group(1)), f"{rel}:{n}")
    for f in files("*.tscn"):
        for m in TSCN.finditer(open(f, encoding="utf-8").read()):
            s = unescape(m.group(1))
            if re.search(r"[A-Za-z]{2}", s) and s not in IGNORE:
                ids.setdefault(s, None)
    return ids, literals


def read_po(path):
    """msgid → (plural, [msgstr...]) — enough of the format for our own files."""
    out, cur, key = {}, {}, None
    def flush():
        if "msgid" in cur and cur["msgid"]:
            out[cur["msgid"]] = (cur.get("msgid_plural"), [cur[k] for k in sorted(cur) if k.startswith("msgstr")])
    for raw in open(path, encoding="utf-8"):
        line = raw.strip()
        if not line or line.startswith("#"):
            if not line:
                flush()
                cur = {}
            continue
        m = re.match(r'^(msgid|msgid_plural|msgstr(?:\[\d\])?) (".*")$', line)
        if m:
            key = m.group(1)
            cur[key] = unescape(m.group(2)[1:-1].replace('\\"', '"'))
        elif line.startswith('"') and key:
            cur[key] += unescape(line[1:-1].replace('\\"', '"'))
    flush()
    return out


def q(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def pot():
    ids, literals = scan()
    code = "".join(open(f, encoding="utf-8").read() for f in files("*.gd"))
    # Auto-translated literals are only known through the catalogs
    for po in glob.glob(os.path.join(LOCALE, "*.po")):
        for msgid, (plural, _) in read_po(po).items():
            if msgid in literals or msgid in ids or msgid in DYNAMIC or msgid in code:
                ids.setdefault(msgid, plural)
    out = ['msgid ""\nmsgstr ""\n"Project-Id-Version: Nehemiah\\n"\n"Content-Type: text/plain; charset=UTF-8\\n"\n\n']
    for msgid in sorted(ids):
        where = literals.get(msgid)
        if where:
            out.append(f"#: {where}\n")
        if ids[msgid]:
            out.append(f"msgid {q(msgid)}\nmsgid_plural {q(ids[msgid])}\nmsgstr[0] \"\"\nmsgstr[1] \"\"\n\n")
        else:
            out.append(f"msgid {q(msgid)}\nmsgstr \"\"\n\n")
    open(os.path.join(LOCALE, "messages.pot"), "w", encoding="utf-8", newline="\n").write("".join(out))
    print(f"locale/messages.pot: {len(ids)} strings")


def check():
    ids, literals = scan()
    code = "".join(open(f, encoding="utf-8").read() for f in files("*.gd"))
    plurals = {p for p in ids.values() if p}
    bad = 0
    known = set()
    for po in sorted(glob.glob(os.path.join(LOCALE, "*.po"))):
        name = os.path.basename(po)
        entries = read_po(po)
        known |= set(entries)
        missing = [i for i in ids if i not in entries]
        # Used somewhere: a literal of its own, or inside world-tag markup ("Build  [%s]")
        stale = [i for i in entries if i not in ids and i not in literals and i not in DYNAMIC and i not in code]
        empty = [i for i, (_, s) in entries.items() if not all(s)]
        broken = [i for i, (_, s) in entries.items() if any(FMT.findall(t) != FMT.findall(i) for t in s if t)]
        print(f"{name}: {len(entries)} entries, {len(missing)} missing, {len(empty)} empty, "
              f"{len(stale)} unused, {len(broken)} placeholder mismatches")
        for label, items in (("missing", missing), ("empty", empty), ("unused", stale), ("placeholders", broken)):
            for i in items:
                print(f"  {label}: {i}")
        bad += len(missing) + len(broken)
    loose = sorted(s for s in literals if s not in known and s not in ids and s not in plurals
                   and s not in IGNORE and SENTENCE.match(s))
    if loose:
        print("UI-looking literals with no translation (wrap in tr() or add to the .po files if the player sees them):")
        for s in loose:
            print(f"  {literals[s]}: {s}")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    {"pot": pot, "check": check}.get(sys.argv[1] if len(sys.argv) > 1 else "", lambda: print(__doc__))()
