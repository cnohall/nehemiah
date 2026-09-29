"""Synthesize the bird sounds (no third-party source):
    sfx/wings_000-002.ogg  a flock taking off: a burst of wingbeats, thinning out
    sfx/chirp_000-003.ogg  a sparrow's short chirps
    sfx/coo_000-002.ogg    a rock dove's soft coo

    python tools/synth_birds.py
Rerun tools/audio_audit.py afterwards if levels are adjusted.
"""
import numpy as np
from synth_sherds import SR, env, band, place, write


def wings(seed):
    rng = np.random.default_rng(seed)
    n = int(0.9 * SR)
    buf = np.zeros(n)
    # Several birds, each beating fast at first and tailing off as they climb away
    for _ in range(rng.integers(4, 7)):
        at = rng.uniform(0.0, 0.08)
        rate = rng.uniform(13, 18)
        beats = rng.integers(7, 12)
        for b in range(beats):
            t = at + b / rate * (1 + b * 0.03)
            if t > 0.8:
                break
            amp = rng.uniform(0.5, 1.0) * np.exp(-b * 0.22)
            bn = int(0.05 * SR)
            place(buf, band(rng.normal(size=bn), 300, rng.uniform(2500, 4500)) * env(bn, 0.004, 0.012) * amp, t)
    return buf


def chirp(seed):
    rng = np.random.default_rng(seed)
    n = int(0.45 * SR)
    buf = np.zeros(n)
    at = 0.0
    for _ in range(rng.integers(1, 4)):
        cn = int(rng.uniform(0.04, 0.08) * SR)
        t = np.arange(cn) / SR
        f0 = rng.uniform(3200, 4200)
        # A quick up-then-down sweep, like "chip"
        sweep = f0 * (1 + 0.35 * np.sin(np.pi * t / t[-1])) - rng.uniform(0, 600) * t / t[-1]
        phase = 2 * np.pi * np.cumsum(sweep) / SR
        tone = np.sin(phase) + 0.25 * np.sin(2 * phase)
        place(buf, tone * env(cn, 0.004, cn / SR * 0.5) * rng.uniform(0.6, 1.0), at)
        at += cn / SR + rng.uniform(0.03, 0.08)
    return buf


def coo(seed):
    rng = np.random.default_rng(seed)
    n = int(1.0 * SR)
    buf = np.zeros(n)
    at = 0.0
    # "hoo-OO-oo": three soft notes, the middle one longest and a touch higher
    for length, lift, amp in ((0.16, 1.0, 0.6), (0.34, 1.12, 1.0), (0.2, 0.95, 0.5)):
        cn = int(length * SR)
        t = np.arange(cn) / SR
        f = rng.uniform(290, 330) * lift * (1 + 0.02 * np.sin(2 * np.pi * 7 * t))
        phase = 2 * np.pi * np.cumsum(f) / SR
        tone = np.sin(phase) + 0.3 * np.sin(2 * phase) + 0.08 * rng.normal(size=cn)
        shape = np.sin(np.pi * t / t[-1]) ** 1.5
        place(buf, band(tone, 150, 1400) * shape * amp, at)
        at += length + 0.04
    return buf


if __name__ == "__main__":
    for i in range(3):
        write("wings_%03d.ogg" % i, wings(300 + i))
    for i in range(4):
        write("chirp_%03d.ogg" % i, chirp(400 + i))
    for i in range(3):
        write("coo_%03d.ogg" % i, coo(500 + i))
