"""Sfx level audit + audition render. Needs ffmpeg on PATH.

    python tools/audio_audit.py            # table + build/audio_audit/sfx_audition.wav

Reads _defs and TRIM straight from scenes/sfx/sfx.gd, so it always matches the game.
- Per clip: peak 50 ms RMS and the TRIM that would level it to TARGET.
- Per event: effective level = clip level + TRIM + volume_db (before bus volume and
  3D distance falloff), flagging quiet events and variants that don't match.
- Audition WAV: 3 variants of each event at in-game gain and pitch, with a cue sheet.
- Mix layers: music, narration, jingles and effects as heard at default Settings, so
  one layer never drowns another (rerun after adding music, voice or a jingle).
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

# ── Mix layers at default settings ──────────────────────────
# Loudness of each layer as the player hears it with untouched Settings (bus volumes and
# the Sfx player gains applied; Master left out, it moves everything together). Music and
# voice: integrated LUFS. Jingles and effects: max momentary (400 ms) LUFS, which reads a
# sustained swish fairly but under-reads a click (use the peak column above for those).
import glob, math

def _r128(path, pad):
    af = ("apad=pad_dur=0.5," if pad else "") + "ebur128=metadata=1,ametadata=print:key=lavfi.r128.M"
    err = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-af", af, "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    m = [float(v) for v in re.findall(r"lavfi.r128.M=(-?[\d.]+)", err) if float(v) > -70]
    i = re.findall(r"I:\s*(-?[\d.]+) LUFS", err)
    return (float(i[-1]) if i else -99.0), (max(m) if m else -99.0)

settings = open(os.path.join(ROOT, "scenes/settings/settings.gd"), encoding="utf-8").read()
def _bus(var):
    return 20 * math.log10(float(re.search(r"^var %s := ([\d.]+)" % var, settings, re.M).group(1)))
def _const(name):
    return float(re.search(r"const %s := (-?[\d.]+)" % name, src).group(1))
MUSIC_BUS, SFX_BUS, VOICE_BUS = _bus("music_volume"), _bus("sfx_volume"), _bus("voice_volume")
base = _const("MUSIC_BASE_DB")
music_defs = src.split("var _music_defs := {")[1].split("\n}")[0]
trims = {f: float(db) for f, db in re.findall(r'\["([\w/]+)", (-?[\d.]+)\]', music_defs)}
story_trim = trims.get("story_temple_of_the_manes", 0.0)
jingle_db = float(re.search(r"_jingle.volume_db = (-?[\d.]+)", src).group(1))

print(f"\nMix layers at default settings (LUFS)")
music = []
for f, t in sorted(trims.items()):
    p = os.path.join(ROOT, "assets/audio/music", f + ".ogg")
    if os.path.exists(p):
        music.append((f, _r128(p, False)[0] + t + base + MUSIC_BUS))
lv = [v for _, v in music]
print(f"  music      {statistics.median(lv):6.1f}  (spread {max(lv) - min(lv):.1f})")
for f, v in music:   # the story track sits lower on purpose (under the reading)
    if abs(v - statistics.median(lv)) > 1.0 and not f.startswith("story_"):
        print(f"    {f:34} {v:6.1f}  <-- off the pack")
voice = [_r128(p, False)[0] + VOICE_BUS for p in glob.glob(os.path.join(ROOT, "assets/audio/narration/en/*.ogg"))]
if voice:
    under = statistics.median(lv) + story_trim + _const("VOICE_DUCK_DB")
    print(f"  narration  {statistics.median(voice):6.1f}  (spread {max(voice) - min(voice):.1f}; "
          f"{statistics.median(voice) - under:.1f} LU over the dipped story music)")
jm = [_r128(p, True)[1] + jingle_db + SFX_BUS for p in glob.glob(os.path.join(ROOT, "assets/audio/jingles/*.ogg"))]
print(f"  jingles    {statistics.median(jm):6.1f}  (max momentary)")
ev = []
for name, files, vol, _, _ in events:
    ms = [_r128(clip(f), True)[1] + trim.get(f, 0.0) for f in files]
    ev.append((name, statistics.mean(ms) + vol + SFX_BUS))
med = statistics.median(v for _, v in ev)
print(f"  effects    {med:6.1f}  (median event, max momentary, within 10 m)")
for n, v in sorted(ev, key=lambda r: -r[1])[:4]:
    print(f"    loudest: {n:16} {v:6.1f}")
