"""Sfx level audit + audition render. Needs ffmpeg on PATH.

    python tools/audio_audit.py            # table + build/audio_audit/sfx_audition.wav

Reads _defs and TRIM straight from scenes/sfx/sfx.gd, so it always matches the game.
- Per clip: peak 50 ms RMS and the TRIM that would level it to TARGET.
- Per event: effective level = clip level + TRIM + volume_db (before bus volume and
  3D distance falloff), flagging quiet events and variants that don't match.
- Audition WAV: 3 variants of each event at in-game gain and pitch, with a cue sheet.
"""
import os, random, re, statistics, subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "build", "audio_audit")
TARGET = -14.0   # peak RMS the TRIM table levels clips to

src = open(os.path.join(ROOT, "scenes/sfx/sfx.gd"), encoding="utf-8").read()
defs_block = src.split("var _defs := {")[1].split("\n}")[0]
trim_block = src.split("const TRIM := {")[1].split("\n}")[0]
trim = {k: float(v) for k, v in re.findall(r'"(\w+)":\s*(-?[\d.]+)', trim_block)}

def expand(files):
    m = re.match(r'_n\("([^"]+)", (\d+), (\d+)\)', files)
    if m:
        pat = m.group(1).replace("%03d", "{:03d}").replace("%d", "{}")
        return [pat.format(i) for i in range(int(m.group(2)), int(m.group(3)))]
    return re.findall(r'"([^"]+)"', files)

events = [(m.group(1), expand(m.group(2)), float(m.group(3)), float(m.group(4)), float(m.group(5)))
          for m in re.finditer(r'"(\w+)":\s*\[(\[[^\]]*\]|_n\([^)]*\)),\s*(-?[\d.]+),\s*([\d.]+),\s*([\d.]+)\]', defs_block)]

_levels = {}
def peak_rms(name):
    if name not in _levels:
        out = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", clip(name), "-af",
            "astats=metadata=1:reset=2205,ametadata=print:key=lavfi.astats.Overall.RMS_level",
            "-f", "null", "-"], capture_output=True, text=True).stderr
        vals = [float(v) for v in re.findall(r"RMS_level=(-?[\d.]+)", out)]
        _levels[name] = max(vals) if vals else -99.0
    return _levels[name]

def clip(name):
    return os.path.join(ROOT, "assets/audio/sfx", name + ".ogg")

rows = []
for name, files, vol, _, _ in events:
    lv = [peak_rms(f) + trim.get(f, 0.0) for f in files]
    rows.append((name, statistics.mean(lv) + vol, max(lv) - min(lv), vol))

print(f"{'event':16} {'eff dB':>7} {'spread':>7} {'vol_db':>7}")
for n, eff, spread, vol in sorted(rows, key=lambda r: r[1]):
    flag = "  <-- quiet" if eff < -25 and n != "step" else ("  <-- variants differ" if spread > 6 else "")
    print(f"{n:16} {eff:7.1f} {spread:7.1f} {vol:7.1f}{flag}")

print(f"\n{'clip':26} {'level':>7} {'trim':>6} {'to target':>9}")
for f in sorted(_levels):
    t = trim.get(f, 0.0)
    ideal = round((TARGET - _levels[f]) * 2) / 2
    if f in trim:
        print(f"{f:26} {_levels[f]:7.1f} {t:6.1f} {ideal:9.1f}{'  <-- stale' if f in trim and abs(ideal - t) > 1 else ''}")

# Audition: each clip padded to 0.9 s, 0.8 s gap between events
os.makedirs(OUT, exist_ok=True)
random.seed(1)
parts, cues, t = [], [], 0.0
for name, files, vol, pmin, pmax in events:
    cues.append((t, name))
    for f in random.sample(files, min(3, len(files))):
        parts.append((f, vol + trim.get(f, 0.0), random.uniform(pmin, pmax)))
        t += 0.9
    parts.append((None, 0.0, 0.0))
    t += 0.8

inputs, filt = [], []
for i, (f, db, pitch) in enumerate(parts):
    if f is None:
        inputs += ["-f", "lavfi", "-t", "0.8", "-i", "anullsrc=r=48000:cl=stereo"]
        filt.append(f"[{i}]anull[a{i}]")
    else:
        inputs += ["-i", clip(f)]
        # Godot pitch_scale resamples: speed and pitch move together
        filt.append(f"[{i}]aformat=channel_layouts=stereo,aresample=48000,asetrate={int(48000 * pitch)},"
                    f"aresample=48000,volume={db}dB,apad=whole_dur=0.9[a{i}]")
filt.append("".join(f"[a{i}]" for i in range(len(parts))) + f"concat=n={len(parts)}:v=0:a=1[out]")
wav = os.path.join(OUT, "sfx_audition.wav")
subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", *inputs,
                "-filter_complex", ";".join(filt), "-map", "[out]", wav], check=True)
with open(os.path.join(OUT, "sfx_audition_cues.txt"), "w") as fh:
    fh.writelines(f"{int(c // 60)}:{c % 60:05.2f}  {n}\n" for c, n in cues)
print(f"\nwrote {wav}")
