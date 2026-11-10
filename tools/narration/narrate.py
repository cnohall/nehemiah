"""Story narration with local TTS, borrowing Not Covered's voice pipeline (make_voices.py) as a library:
same venvs, same cached weights, same finishing (level, Whisper check).

The game's set (Kokoro "am_michael", picked by ear Nov 10 2026):
    C:/Programming/patients-please/build/tts_venv/Scripts/python.exe tools/narration/narrate.py all
        -> assets/audio/narration/en/<md5(text)[:10]>.ogg for every story line StoryData can show (Narration.gd
           looks them up by the same key, so an edited line falls silent until it is re-recorded; stale files
           are removed). Then `godot --headless --import`.
    C:/Programming/patients-please/build/qwen_venv/Scripts/python.exe tools/narration/narrate.py check
        -> Whisper hears every line back and lists the ones that came out wrong (respell them in SPOKEN)

Experiments (Qwen voice design needs ~6 GB free RAM):
    C:/Programming/patients-please/build/qwen_venv/Scripts/python.exe tools/narration/narrate.py design
        -> <out>/cand_<n>.wav: candidate narrator voices reading REF_TEXT; ref.wav = best by score
    ... narrate.py kokoro
        -> <out>/prologue_kokoro_<voice>.ogg: light preview in stock Kokoro voices (no big model, any RAM)
    ... narrate.py lines [--pick N]
        -> <out>/lines/<nn>.ogg for each LINES entry, cloned from ref.wav (or cand_N), plus <out>/prologue_mix.ogg:
           the lines in order over the story music at in-game levels

<out> defaults to C:/Users/chris/Desktop/nehemiah/narration_spike; --out DIR to change it. Needs ~6 GB free RAM (one 4.5 GB model at a time).
"""
import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

import numpy as np

PP = Path("C:/Programming/patients-please/tools")
sys.path.insert(0, str(PP))
import make_voices as mv  # noqa: E402  (sets HF_HOME to Not Covered's weight cache)
import soundfile as sf  # noqa: E402

GAME = Path(__file__).resolve().parents[2]
OUT = Path("C:/Users/chris/Desktop/nehemiah/narration_spike")
MUSIC = GAME / "assets/audio/music/story_temple_of_the_manes.ogg"

DESIGN = ("A man in his sixties, a storyteller. Low, warm, slightly weathered voice. He reads slowly and calmly, "
          "like telling an old story by lamplight to people gathered close. Clear English, gentle gravity, "
          "no theatrics, no accent.")
REF_TEXT = "In those days the walls of the city lay broken, and its gates had been burned with fire."
# The prologue (StoryData.BEATS[0]) "text" lines; spoken spellings where names trip the model
LINES = [
    "Nehemiah, cupbearer to King Artaxerxes, asks about the Jews who returned to Jerusalem.",
    "He prays to the God of the heavens, then asks the king to send him to rebuild the city of his forefathers. The king grants it.",
    "Telling no one, he rides out in the dark and inspects the broken walls and the burned gates.",
    "He tells the people how the hand of his God has been with him.",
]
NARRATOR = ("am_michael", "en-us", 0.88)   # Kokoro voice, language, speed
NARRATION = GAME / "assets/audio/narration/en"
STORY = GAME / "scenes/story/story_data.gd"
# Spoken spellings for words the voice gets wrong: {word in the text: how to spell it for the voice}
SPOKEN = {
    "Artaxerxes": "Arta-zerk-seez",
    "Horonite": "Horro-nite",
    "Sanballat": "San-ballat",
    "Rechab": "Ree-kab",
    "Malchijah": "Mal-kye-jah",
    "Zanoah": "Za-no-ah",
    "Shemaiah": "Shem-eye-ah",
}
MUSIC_DB = -6.0 - 3.0 + 20 * np.log10(0.6)  # Sfx MUSIC_BASE_DB + story trim + default Settings.music_volume
CANDIDATES = 6
BATCH = 2  # small: RAM is tight on this machine
F0 = (75, 140)  # an older man


def design(q):
    q._load("design")
    OUT.mkdir(parents=True, exist_ok=True)
    wavs = []
    for _ in range(0, CANDIDATES, BATCH):
        ws, sr = q.design.generate_voice_design(text=[REF_TEXT] * BATCH, language=["English"] * BATCH,
                                                instruct=[DESIGN] * BATCH, max_new_tokens=400)
        wavs += list(ws)
        print("designed %d/%d (RAM free %.1f GB)" % (len(wavs), CANDIDATES, mv.free_gb()), flush=True)
    best, best_score, rows = 0, -9, []
    for i, w in enumerate(wavs):
        w = mv.trim_and_squeeze(np.asarray(w, dtype=np.float32), sr)
        sf.write(OUT / ("cand_%d.wav" % i), mv.level(w, sr), sr)
        heard = q.hear(w, sr)
        sim = mv.similarity(REF_TEXT, heard)
        f0 = q.f0(w, sr)
        dur = len(w) / sr
        score = sim - (0.0 if F0[0] <= f0 <= F0[1] else 0.6) - (0.0 if 4.0 <= dur <= 9.0 else 0.3) \
            - (0.0 if abs(w).max() < 0.98 else 0.3) - 0.003 * abs(f0 - sum(F0) / 2)
        rows.append(dict(cand=i, dur=round(dur, 1), f0=round(f0), sim=round(sim, 2), score=round(score, 3), heard=heard))
        print("  cand %d: %.1fs f0 %3.0f Hz sim %.2f score %.3f | %s" % (i, dur, f0, sim, score, heard), flush=True)
        if score > best_score:
            best, best_score = i, score
    (OUT / "ref.wav").write_bytes((OUT / ("cand_%d.wav" % best)).read_bytes())
    (OUT / "ref.json").write_text(json.dumps({"design": DESIGN, "ref_text": REF_TEXT, "picked": best, "cands": rows}, indent=1))
    print("picked cand %d" % best, flush=True)


def lines(q, pick):
    ref = OUT / ("cand_%d.wav" % pick if pick is not None else "ref.wav")
    a, sr0 = sf.read(ref)
    q._load("base")
    prompt = q.base.create_voice_clone_prompt(ref_audio=(a.astype(np.float32), sr0), ref_text=REF_TEXT, x_vector_only_mode=False)
    d = OUT / "lines"
    d.mkdir(parents=True, exist_ok=True)
    out = []
    for n, text in enumerate(LINES):
        best = (-9, None, None)
        for attempt in range(mv.RETRIES):
            wavs, sr = q.base.generate_voice_clone(text=[mv.prep(text)], language=["English"],
                                                   voice_clone_prompt=prompt, max_new_tokens=400)
            w = mv.trim_and_squeeze(np.asarray(wavs[0], dtype=np.float32), sr)
            score, why = q.judge(text, w, sr)
            if score > best[0]:
                best = (score, w, sr)
            print("  line %d take %d: %.1fs score %.2f %s (RAM free %.1f GB)" % (n, attempt + 1, len(w) / sr, score, why, mv.free_gb()), flush=True)
            if not why:
                break
        _, w, sr = best
        w = mv.level(w, sr)
        sf.write(d / ("%02d.wav" % n), w, sr)
        mv.write_ogg(w, sr, d / ("%02d.ogg" % n))
        out.append(d / ("%02d.wav" % n))
    mix(out)


def story_lines():
    """Every narration line in StoryData: the beats, the ending, and the section cards. Not the choice card
    (it's instructions) and not verse-only slides."""
    src = STORY.read_text(encoding="utf-8")
    lines = re.findall(r'"text":\s*"((?:[^"\\]|\\.)*)"', src)
    lines = [t for t in lines if "Choose how the crew" not in t]
    block = re.search(r"const SECTION_LINES := \[(.*?)\n\]", src, re.S).group(1)
    lines += re.findall(r'^\s*"((?:[^"\\]|\\.)*)",?\s*$', block, re.M)
    return list(dict.fromkeys(t.replace('\\"', '"') for t in lines))


def key(text):
    return hashlib.md5(text.encode("utf-8")).hexdigest()[:10]   # and Narration.key


def spoken(text):
    for word, say in SPOKEN.items():
        text = re.sub(r"\b%s\b" % re.escape(word), say, text)
    return mv.prep(text)


def record_all():
    k = mv.Kokoro()
    voice, lang, speed = NARRATOR
    NARRATION.mkdir(parents=True, exist_ok=True)
    lines = story_lines()
    want = {key(t) for t in lines}
    for f in NARRATION.glob("*.ogg"):
        if f.stem not in want:
            f.unlink()
            Path(str(f) + ".import").unlink(missing_ok=True)
            print("removed stale", f.name)
    rows = []
    for t in lines:
        a, sr = k.k.create(spoken(t), voice=k.style(voice), speed=speed, lang=lang, sentence_pause=0.5, clause_pause=0.18)
        mv.write_ogg(mv.level(a, sr), sr, NARRATION / (key(t) + ".ogg"))
        rows.append("%s\t%.1f\t%s" % (key(t), len(a) / sr, t))
        print("%s %4.1fs %s" % (key(t), len(a) / sr, t[:70]), flush=True)
    (NARRATION / "lines.tsv").write_text("\n".join(rows) + "\n", encoding="utf-8")
    print("%d lines -> %s" % (len(lines), NARRATION))


def check():
    q = mv.Qwen()
    bad = 0
    for t in story_lines():
        a, sr = sf.read(str(NARRATION / (key(t) + ".ogg")))
        heard = q.hear(a, sr)
        sim = mv.similarity(t, heard)
        if sim < 0.9:
            bad += 1
            print("%.2f %s\n     said: %s\n    heard: %s" % (sim, key(t), t, heard), flush=True)
    print("%d lines to look at" % bad)


KOKORO_VOICES = [("bm_george", "en-gb"), ("bm_fable", "en-gb"), ("am_onyx", "en-us"), ("am_michael", "en-us")]


def kokoro():
    """Quick, light preview (no 4.5 GB model): the prologue in a few stock Kokoro voices, a touch slow."""
    k = mv.Kokoro()
    for voice, lang in KOKORO_VOICES:
        d = OUT / ("kokoro_" + voice)
        d.mkdir(parents=True, exist_ok=True)
        wavs = []
        for n, text in enumerate(LINES):
            a, sr = k.k.create(mv.prep(text), voice=k.style(voice), speed=0.88, lang=lang,
                               sentence_pause=0.5, clause_pause=0.18)
            a = mv.level(a, sr)
            sf.write(d / ("%02d.wav" % n), a, sr)
            wavs.append(d / ("%02d.wav" % n))
        mix(wavs, "prologue_kokoro_%s.ogg" % voice)


def mix(wavs, name="prologue_mix.ogg"):
    """Lines in order with the gaps a reader leaves between cards, over the story music at its in-game level
    (-6 dB base, -3 dB story trim, Music bus at its default 0.6 = -4.4 dB) dipping further under the voice."""
    if not wavs:
        sys.exit("no lines to mix yet: run `lines` (or `kokoro`) first")
    lead, gap = 2.0, 3.0
    parts, t = [], lead
    for w in wavs:
        dur = sf.info(str(w)).duration
        parts.append((w, t))
        t += dur + gap
    total = t + 1.5
    args = ["ffmpeg", "-v", "error", "-y", "-i", str(MUSIC)]
    for w, _ in parts:
        args += ["-i", str(w)]
    f = []
    for i, (_, start) in enumerate(parts, 1):
        f.append("[%d]aresample=44100,pan=stereo|c0=c0|c1=c0,adelay=%d|%d[v%d]" % (i, start * 1000, start * 1000, i))
    f.append("".join("[v%d]" % i for i in range(1, len(parts) + 1)) + "amix=inputs=%d:normalize=0[voice]" % len(parts))
    f.append("[voice]asplit[vo][sc]")
    f.append("[0]atrim=0:%.1f,volume=%.1fdB,afade=t=out:st=%.1f:d=1.5[m]" % (total, MUSIC_DB, total - 1.5))
    f.append("[m][sc]sidechaincompress=threshold=0.02:ratio=4:attack=80:release=900[duck]")
    f.append("[duck][vo]amix=inputs=2:normalize=0,alimiter=limit=0.9[out]")
    subprocess.run(args + ["-filter_complex", ";".join(f), "-map", "[out]", "-c:a", "libvorbis", "-q:a", "5",
                           str(OUT / name)], check=True)
    print("wrote", OUT / name, flush=True)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("step", choices=["all", "check", "design", "lines", "mix", "kokoro"])
    ap.add_argument("--pick", type=int)
    ap.add_argument("--out", type=Path, help="where everything is written (default: %s)" % OUT)
    a = ap.parse_args()
    if a.out:
        OUT = a.out
    if a.step == "all":
        record_all()
        sys.exit()
    if a.step == "check":
        check()
        sys.exit()
    if a.step == "kokoro":
        kokoro()
        sys.exit()
    if a.step == "mix":
        mix(sorted((OUT / "lines").glob("*.wav")))
        sys.exit()
    if mv.free_gb() < mv.MIN_FREE_GB:
        sys.exit("only %.1f GB RAM free, need %.1f" % (mv.free_gb(), mv.MIN_FREE_GB))
    q = mv.Qwen()
    design(q) if a.step == "design" else lines(q, a.pick)
