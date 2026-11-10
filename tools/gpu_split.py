"""GPU pass split of the real game, averaged over a perf_scene run.

    python tools/gpu_split.py [label=perf_scene args ...]
    e.g. python tools/gpu_split.py base= postfx=--hide=PostFX scatter=--hide=ScatterLayer

Each label runs tools/perf_scene.gd under --gpu-profile (5120x1440, High, day 21 unless the
args say otherwise) and prints the frame/GPU averages and every pass's mean in ms, side by side.
"""
import os
import re
import subprocess
import sys

GODOT = os.environ.get("GODOT", r"C:\Users\chris\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe")
BASE = ["--nostory", "--day=21", "--secs=10"] + ([] if os.environ.get("RES") == "1080" else ["--window=5120x1440"])
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run(args):
    out = subprocess.run([GODOT, "--path", ROOT, "--gpu-profile", "--script", "res://tools/perf_scene.gd", "--"] + BASE + args,
        capture_output=True, text=True, errors="replace").stdout
    passes = {}
    for name, ms in re.findall(r"^\s*-(.+?): ([\d.]+)ms", out, re.M):
        passes.setdefault(name, []).append(float(ms))
    head = {}
    for key in ("frame", "gpu", "draws"):
        m = re.search(r"^%s\s+avg\s+([\d.]+)" % key, out, re.M)
        if m:
            head[key] = float(m.group(1))
    # Skip the first profiles (warm-up, before the window opened at full size)
    return head, {k: sum(v[len(v) // 3:]) / max(1, len(v) - len(v) // 3) for k, v in passes.items()}


def main():
    runs = []
    for spec in sys.argv[1:] or ["base="]:
        label, _, rest = spec.partition("=")
        head, passes = run(rest.split() if rest else [])
        runs.append((label, head, passes))
        print("ran", label, head, flush=True)
    names = sorted({n for _, _, p in runs for n in p}, key=lambda n: -runs[0][2].get(n, 0))
    print("%-36s" % "pass" + "".join("%11s" % r[0] for r in runs))
    for key in ("frame", "gpu", "draws"):
        print("%-36s" % key + "".join("%11.2f" % r[1].get(key, 0) for r in runs))
    for n in names:
        if max(r[2].get(n, 0) for r in runs) < 0.1:
            continue
        print("%-36s" % n[:36] + "".join("%11.2f" % r[2].get(n, 0) for r in runs))


main()
