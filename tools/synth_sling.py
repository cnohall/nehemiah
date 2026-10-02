"""Synthesize the sling's sounds (no third-party source):
    sfx/sling_whirl_000-002.ogg  one pass of the stone round the head: a short airy whoosh
    sfx/sling_glint_000-001.ogg  the cord gone taut at full spin: a small bright ting
    sfx/sling_crack_000-002.ogg  the release: the pouch snaps, a rush of air off the cord
    sfx/stone_thock_000-003.ogg  a stone striking a body: a dull unpitched blow, a little grit
    sfx/true_hit_000-002.ogg     a true shot: the same blow, heavier and lower

    python tools/synth_sling.py   (needs numpy, scipy, soundfile, ffmpeg on PATH)
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


def hp(x, f, o=2):
    return sosfilt(butter(o, f, btype="high", fs=SR, output="sos"), x)


def t_of(dur):
    return np.arange(int(SR * dur)) / SR


def sweep_noise(dur, f_lo, f_hi, rng, q=0.35):
    # Noise through a band that slides from f_lo to f_hi — done in short blocks
    n = int(SR * dur)
    out = np.zeros(n)
    noise = rng.normal(0, 1, n + 2048)
    blocks = 24
    edges = np.linspace(0, n, blocks + 1).astype(int)
    for b in range(blocks):
        f = f_lo + (f_hi - f_lo) * (b / (blocks - 1))
        seg = band(noise[edges[b]: edges[b + 1] + 2048], f * (1 - q), f * (1 + q))[2048:]
        out[edges[b]: edges[b + 1]] = seg
    return out


def norm(x, peak=0.9):
    return x / (np.max(np.abs(x)) + 1e-9) * peak


def write(name, x):
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "5", OUT % name], input=pcm, check=True)
    print("wrote", OUT % name)


def whirl(seed):
    # The stone passing the ear: rises and falls in pitch and loudness (a doppler-ish swell)
    rng = np.random.default_rng(seed)
    dur = 0.16
    t = t_of(dur)
    up = sweep_noise(dur * 0.55, 380, 1400, rng)
    down = sweep_noise(dur * 0.45, 1400, 600, rng)
    x = np.pad(np.concatenate([up, down]), (0, len(t)))[: len(t)]
    env = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 1.6
    return norm(lp(x * env, 3200), 0.7)


def glint(seed):
    # Taut cord: a light, high, slightly metallic ting that fades fast
    rng = np.random.default_rng(seed)
    t = t_of(0.35)
    f = 2350 + seed * 140
    x = np.zeros_like(t)
    for ratio, amp, dec in ((1.0, 1.0, 0.11), (2.01, 0.35, 0.06), (2.76, 0.25, 0.045), (4.1, 0.12, 0.03)):
        x += amp * np.sin(2 * np.pi * f * ratio * t + rng.uniform(0, 6.28)) * np.exp(-t / dec)
    x *= np.clip(t / 0.002, 0, 1)
    return norm(x, 0.55)


def crack(seed):
    # Release: no tone at all (a pitched hum read as a cartoon whistle). A short dry snap
    # of the leather pouch, then the rush of air off the cord, dark and quick
    rng = np.random.default_rng(seed)
    t = t_of(0.22)
    n = len(t)
    snap = band(rng.normal(0, 1, n), 900, 3800) * np.exp(-t / 0.006)
    flap = band(rng.normal(0, 1, n), 300, 1400) * np.exp(-np.maximum(t - 0.004, 0) / 0.02) * (t > 0.004)
    rush = lp(sweep_noise(0.22, 1300, 450, rng), 2400) * np.sin(np.pi * np.clip(t / 0.16, 0, 1)) ** 2
    x = 1.0 * snap + 0.55 * flap + 0.45 * rush
    return norm(lp(x, 6000), 0.85)


def thock(seed, heavy=False):
    # Stone on a body: no pitch glide (that read as a cartoon bonk). A dull blow of
    # dark noise through cloth and flesh, a little grit of the stone's edge on top, short.
    # Heavy: more weight and a low dull knock, still unpitched
    rng = np.random.default_rng(seed)
    dur = 0.32 if heavy else 0.2
    t = t_of(dur)
    n = len(t)
    body = lp(rng.normal(0, 1, n), 420 if heavy else 650, 4) * np.exp(-t / (0.05 if heavy else 0.03))
    grit = band(rng.normal(0, 1, n), 1500, 4000) * np.exp(-t / 0.005)
    cloth = band(rng.normal(0, 1, n), 400, 1600) * np.exp(-t / 0.018)
    x = 1.0 * body + 0.3 * grit + 0.35 * cloth
    if heavy:
        weight = lp(rng.normal(0, 1, n), 140, 4) * np.exp(-t / 0.09)
        x += 1.4 * weight / (np.max(np.abs(weight)) + 1e-9) * np.max(np.abs(body))
    x *= np.clip(t / 0.0015, 0, 1)
    return norm(np.tanh(1.3 * x / (np.max(np.abs(x)) + 1e-9)), 0.9)


for i in range(3):
    write("sling_whirl_%03d" % i, whirl(10 + i))
for i in range(2):
    write("sling_glint_%03d" % i, glint(i))
for i in range(3):
    write("sling_crack_%03d" % i, crack(20 + i))
for i in range(4):
    write("stone_thock_%03d" % i, thock(30 + i))
for i in range(3):
    write("true_hit_%03d" % i, thock(40 + i, heavy=True))
