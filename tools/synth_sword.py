"""Synthesize the sword's turned blow (GDD §5.16, no third-party source):
    sfx/riposte_000-002.ogg  a cut landing as a foe draws back: bronze biting the spear
                             shaft — a short bright clash, then the heavy blow

    python tools/synth_sword.py   (needs numpy, scipy, ffmpeg on PATH)
The clash is inharmonic and dies in a few hundredths of a second: a held, tuned ring
would read as a bell (or a cartoon), like the sling's first pitched "bonk".
Rerun tools/audio_audit.py afterwards if levels are adjusted.
"""
import subprocess
import numpy as np
from scipy.signal import butter, sosfilt

SR = 44100
OUT = "assets/audio/sfx/%s.ogg"


def band(x, lo, hi, o=2):
    return sosfilt(butter(o, [lo, hi], btype="band", fs=SR, output="sos"), x)


def lp(x, f, o=2):
    return sosfilt(butter(o, f, btype="low", fs=SR, output="sos"), x)


def t_of(dur):
    return np.arange(int(SR * dur)) / SR


def norm(x, peak=0.9):
    return x / (np.max(np.abs(x)) + 1e-9) * peak


def write(name, x):
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "5", OUT % name], input=pcm, check=True)
    print("wrote", OUT % name)


def riposte(seed):
    rng = np.random.default_rng(seed)
    dur = 0.38
    t = t_of(dur)
    n = len(t)
    # Clash: a burst of bright noise plus a few inharmonic partials, all gone in ~40 ms
    f = 1650 + seed % 3 * 120
    clash = band(rng.normal(0, 1, n), 2500, 7500) * np.exp(-t / 0.008)
    for ratio, amp, dec in ((1.0, 0.5, 0.035), (1.73, 0.4, 0.028), (2.92, 0.3, 0.02), (4.37, 0.2, 0.014)):
        clash += amp * np.sin(2 * np.pi * f * ratio * t + rng.uniform(0, 6.28)) * np.exp(-t / dec)
    # Scrape: the edge sliding off the shaft
    scrape = band(rng.normal(0, 1, n), 1800, 4200) * np.exp(-np.maximum(t - 0.01, 0) / 0.03) * (t > 0.01)
    # Blow: the dull heavy thump of the foe taken off his feet, unpitched
    blow_t = np.maximum(t - 0.012, 0)
    body = lp(rng.normal(0, 1, n), 420, 4) * np.exp(-blow_t / 0.05) * (t > 0.012)
    weight = lp(rng.normal(0, 1, n), 140, 4) * np.exp(-blow_t / 0.09) * (t > 0.012)
    body = norm(body) + 1.2 * norm(weight)
    x = 0.55 * norm(clash) + 0.25 * norm(scrape) + 0.8 * norm(body)
    x *= np.clip(t / 0.001, 0, 1)
    return norm(np.tanh(1.3 * x / (np.max(np.abs(x)) + 1e-9)), 0.9)


for i in range(3):
    write("riposte_%03d" % i, riposte(50 + i))
