"""Synthesize the breakable-prop sounds (no third-party source):
    sfx/shatter_000-003.ogg  clay jar breaking: crack, ringing sherds, pieces landing
    sfx/splash_000-002.ogg   the water in it hitting the ground

    python tools/synth_sherds.py
Rerun tools/audio_audit.py afterwards if levels are adjusted.
"""
import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfilt

SR = 44100
OUT = "assets/audio/sfx/"


def env(n, attack, decay):
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-t / decay)


def band(x, lo, hi):
    sos = butter(2, [lo, hi], btype="band", fs=SR, output="sos")
    return sosfilt(sos, x)


def ping(n, freq, decay, rng):
    # Inharmonic partials, like a fired-clay shard
    t = np.arange(n) / SR
    out = np.zeros(n)
    for ratio, amp in ((1.0, 1.0), (2.32, 0.5), (3.87, 0.3), (5.4, 0.15)):
        out += amp * np.sin(2 * np.pi * freq * ratio * t + rng.uniform(0, 6.28)) * np.exp(-t * ratio / decay)
    return out


def place(buf, clip, at):
    i = int(at * SR)
    j = min(len(buf), i + len(clip))
    buf[i:j] += clip[: j - i]


def shatter(seed):
    rng = np.random.default_rng(seed)
    n = int(0.6 * SR)
    buf = np.zeros(n)
    # The crack: a hard, bright noise burst with a low body thump under it
    crack_n = int(0.05 * SR)
    place(buf, band(rng.normal(size=crack_n), 1500, 12000) * env(crack_n, 0.0005, 0.008) * 1.4, 0.0)
    thump_n = int(0.08 * SR)
    t = np.arange(thump_n) / SR
    place(buf, np.sin(2 * np.pi * rng.uniform(140, 200) * t) * env(thump_n, 0.001, 0.02) * 0.6, 0.0)
    # The jar ringing as it splits
    for _ in range(4):
        place(buf, ping(int(0.2 * SR), rng.uniform(1600, 3600), rng.uniform(0.02, 0.05), rng) * 0.35, rng.uniform(0.0, 0.01))
    # Sherds landing and skittering
    for _ in range(rng.integers(7, 11)):
        at = rng.uniform(0.05, 0.42)
        amp = 0.35 * np.exp(-at * 4.0) * rng.uniform(0.5, 1.0)
        tick_n = int(0.01 * SR)
        place(buf, band(rng.normal(size=tick_n), 2500, 10000) * env(tick_n, 0.0003, 0.002) * amp, at)
        place(buf, ping(int(0.08 * SR), rng.uniform(2800, 6000), rng.uniform(0.008, 0.02), rng) * amp * 0.5, at)
    return buf


def splash(seed):
    rng = np.random.default_rng(seed)
    n = int(0.55 * SR)
    buf = band(rng.normal(size=n), 250, 3200) * env(n, 0.006, 0.09)
    # A few bubbles: short upward chirps
    for _ in range(rng.integers(4, 7)):
        bn = int(0.03 * SR)
        t = np.arange(bn) / SR
        f0 = rng.uniform(500, 900)
        phase = 2 * np.pi * np.cumsum(f0 * (1 + 2.5 * t / t[-1])) / SR
        place(buf, np.sin(phase) * env(bn, 0.002, 0.01) * rng.uniform(0.1, 0.25), rng.uniform(0.02, 0.25))
    return buf


def write(name, x):
    x = x / np.max(np.abs(x)) * 0.7   # ~-3 dBFS peak
    fade = int(0.02 * SR)
    x[-fade:] *= np.linspace(1, 0, fade)
    sf.write(OUT + name, x.astype(np.float32), SR, format="OGG", subtype="VORBIS")


if __name__ == "__main__":
    for i in range(4):
        write("shatter_%03d.ogg" % i, shatter(100 + i))
    for i in range(3):
        write("splash_%03d.ogg" % i, splash(200 + i))
