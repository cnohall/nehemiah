"""Synthesizes the ram's horn (shofar) blasts: assets/audio/sfx/horn_000-002.ogg.
   python tools/make_horn.py   (needs numpy, scipy, ffmpeg on PATH)
A shofar has no valves: a raw conical-bore buzz with a breathy, scooped attack, a note that
leans up as the player pushes, a brassy formant around 1-1.6 kHz, then an echo off the valley."""
import subprocess, numpy as np
from scipy.signal import butter, lfilter, fftconvolve

SR = 44100
OUT = "assets/audio/sfx/horn_%03d.ogg"

def lp(x, f, o=2): b, a = butter(o, f / (SR / 2)); return lfilter(b, a, x)
def bp(x, lo, hi, o=2): b, a = butter(o, [lo / (SR / 2), hi / (SR / 2)], "band"); return lfilter(b, a, x)

def blast(f0, dur, rise, seed, tail=1.6):
    rng = np.random.default_rng(seed)
    n = int(SR * dur)
    t = np.arange(n) / SR
    # Pitch: scoops up into the note, leans higher as the blast pushes, a little unsteady
    scoop = -2.2 * np.exp(-t / 0.07)
    drift = rise * (1 - np.exp(-t / (dur * 0.45)))
    wob = lp(rng.normal(0, 1, n), 6) * 0.35
    cents = scoop * 100 + drift * 100 + wob * 40 + 6 * np.sin(2 * np.pi * 5.2 * t) * np.clip(t - 0.25, 0, 1)
    f = f0 * 2 ** (cents / 1200)
    ph = 2 * np.pi * np.cumsum(f) / SR
    sig = np.zeros(n)
    for k in range(1, 22):
        fk = f0 * k
        # brass-horn spectrum: formant bumps near 1.1 kHz and 2.4 kHz, rolled off above
        amp = (1 / k ** 0.55) * (1 + 1.6 * np.exp(-((fk - 1100) / 450) ** 2) + 0.7 * np.exp(-((fk - 2400) / 700) ** 2))
        # upper harmonics arrive with the push (brighter as it opens up)
        bright = np.clip(t / 0.18, 0, 1) ** (0.5 + 0.12 * k)
        sig += amp * bright * np.sin(k * ph + rng.uniform(0, 6.28))
    # Lip buzz: amplitude ripple at the fundamental plus breath noise through the bore
    buzz = 1 + 0.12 * lp(rng.normal(0, 1, n), 400)
    breath = bp(rng.normal(0, 1, n), 700, 3200) * (0.55 * np.exp(-t / 0.16) + 0.06)
    sig = sig * buzz / 6.0 + breath * 0.5
    # Envelope: breath-in swell, steady, then a drop-off
    att, rel = 0.09, 0.28
    env = np.minimum(1, t / att) ** 1.5 * np.minimum(1, (dur - t) / rel) ** 1.2
    env *= 1 - 0.1 * np.sin(2 * np.pi * 0.9 * t)
    sig = lp(sig * env, 5200)
    # Valley echo: a dark, sparse reverb, plus one slap-back
    ir_n = int(SR * tail)
    ir = rng.normal(0, 1, ir_n) * np.exp(-np.arange(ir_n) / SR / 0.5)
    ir = lp(ir, 1800)
    ir[: int(0.01 * SR)] = 0
    wet = np.pad(fftconvolve(sig, ir), (0, 2))[: n + ir_n] * 0.012
    out = np.concatenate([sig, np.zeros(ir_n)]) + wet
    slap = int(0.38 * SR)
    out[slap:] += 0.22 * np.concatenate([sig, np.zeros(ir_n)])[: len(out) - slap] * 0.6
    out = out / np.max(np.abs(out))
    return np.tanh(2.6 * out) / np.tanh(2.6) * 0.9   # soft-limit: a horn is loud and dense

# Three takes: one long tekiah, one with a shorter push, one lower and fuller
takes = [(293.7, 1.9, 1.4, 1), (311.1, 1.5, 0.9, 2), (277.2, 2.2, 1.7, 3)]
for i, (f0, dur, rise, seed) in enumerate(takes):
    pcm = (blast(f0, dur, rise, seed) * 32767).astype("<i2").tobytes()
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "5", OUT % i], input=pcm, check=True)
    print("wrote", OUT % i)
