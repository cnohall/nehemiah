"""A crew figure authored in Blender (5.2, headless): clean lofted meshes, painted textures.
    blender -b --factory-startup -P tools/blender/build_crew.py -- <rig.json> <out.glb>
Unlike build_figure.py (which fuses the code rig's own parts), every piece here is a
parametric surface S(u, v) written for the purpose: a lathe, a tube along a path, an
ellipsoid or a patch on the skull. Only the bones (names and rest positions) come from
<rig.json> (tools/blender/export_rig.gd), so the figure skins to the rig's pivots and the
animation stays in code (BakedFigure).
Each part gives
  shape(U, V)      the surface, in rig space (Godot's: y up, +z the figure's front)
  form(U, V, P)    metres pushed out along the normal: folds, locks, the nose (in the mesh)
  paint(ctx)       colour, roughness, dye mask and a fine height (the normal map)
  weights(P, U, V) bone weights
and its (u, v) is its texture space: every part gets a rectangle of one atlas, so the paint
is written in the same coordinates as the shape. Three textures come out beside the glb:
  <name>_albedo.png  paint (sRGB); dyed cloth is painted as its shade, near white
  <name>_normal.png  tangent-space normals from the fine height
  <name>_aux.png     r ambient occlusion (Cycles), g roughness, b dye mask
"""
import bpy
import bmesh
import json
import math
import os
import sys
import numpy as np
argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
# The figure: a crew slot (CharacterRig.worker_look): 0 builder, 1 water carrier, 2 carpenter,
# 3 overseer; or an enemy kind (CharacterRig.enemy_look), built as SLOT 4 with FOE its look
FOES = {
    "scout": dict(robe=(0.36, 0.28, 0.22), sash=(0.62, 0.20, 0.14), hood=(0.17, 0.14, 0.13), beard="short"),
    "brute": dict(robe=(0.34, 0.22, 0.16), sash=(0.22, 0.14, 0.10), helmet=(0.60, 0.45, 0.25), armour=(0.50, 0.33, 0.19),
        beard="full", shield=(0.56, 0.18, 0.12)),
    "raider": dict(robe=(0.20, 0.17, 0.18), sash=(0.60, 0.16, 0.12), hood=(0.46, 0.12, 0.10), beard="short", cape=(0.52, 0.13, 0.11)),
    "saboteur": dict(robe=(0.16, 0.14, 0.13), sash=(0.30, 0.22, 0.14), hood=(0.10, 0.09, 0.09), beard="short", sack=(0.58, 0.48, 0.32)),
}
# Townsfolk (Folk.look_for) and the watch, each built on a crew figure's frame (base): the band
# and swept hair of the carpenter, the wrap, veil and long robe of the overseer, the water
# carrier without his load. Dye masks: robe_mask how much of the dye the robe takes (worker_look
# tints it toward the dye), wrap_mask the wrap's; band_fixed / robe / wrap paint a set colour
UNDYED = (0.83, 0.77, 0.65)
MUREX = (0.47, 0.22, 0.27)
NPCS = {
    "man": dict(base=2, beard="short", hair=(0.20, 0.12, 0.07), robe_mask=0.25),
    "child": dict(base=2, beard="", hair=(0.20, 0.12, 0.07), robe_mask=0.0),
    "woman": dict(base=3, beard="", hair=(0.20, 0.12, 0.07), robe_mask=0.55, wrap_mask=0.6, band_shade=0.8, vest=True),
    "elder": dict(base=3, beard="long", hair=(0.82, 0.80, 0.76), band_fixed=(0.24, 0.16, 0.11), wrap=(0.90, 0.86, 0.77)),
    "priest": dict(base=3, beard="long", hair=(0.30, 0.20, 0.12), vest=True, robe=(0.95, 0.93, 0.88), wrap=(0.97, 0.96, 0.92)),
    "scribe": dict(base=3, beard="long", hair=(0.70, 0.68, 0.64), vest=True, robe=(0.95, 0.93, 0.88), wrap=(0.97, 0.96, 0.92),
        scroll=True),
    "governor": dict(base=3, beard="full", hair=(0.20, 0.105, 0.06), vest=True, wrap_mask=1.0, band_fixed=MUREX,
        robe=tuple(m + (u - m) * 0.35 for m, u in zip(MUREX, UNDYED))),
    "watchman": dict(base=1, nopack=True),
}
_fig = argv[2] if len(argv) > 2 else "0"
FOE = FOES.get(_fig)
NPC = NPCS.get(_fig, {})
SLOT = 4 if FOE else NPC["base"] if NPC else int(_fig)
FOE = FOE or {}
FOE_TRIM = np.array([0.12, 0.09, 0.08])
TEX = 1024
PAD = 4
TAU = math.tau
# CharacterRig.SKIN / HAIR_* for the slot
# A foe is painted in the first skin tone and tinted to his own at runtime (BakedFigure's
# skin_tint, by the albedo's alpha): foes draw from the crew's SKIN range, never darker
SKIN = np.array([[0.76, 0.55, 0.40], [0.63, 0.44, 0.31], [0.81, 0.62, 0.47], [0.54, 0.38, 0.27], [0.76, 0.55, 0.40]][SLOT])
HAIR = np.array([[0.20, 0.105, 0.06], [0.16, 0.11, 0.08], [0.50, 0.27, 0.11], [0.62, 0.60, 0.56], [0.19, 0.12, 0.08]][SLOT])
TINT_SKIN = SLOT == 4 or bool(NPC)
if NPC:
    SKIN = np.array([0.76, 0.55, 0.40])      # painted in the first tone, tinted to the person's
    if "hair" in NPC:
        HAIR = np.array(NPC["hair"])

ROBE = np.array(NPC.get("robe", (0.93, 0.90, 0.83)))    # the overseer's long robe and head-wrap, undyed
WOOD = np.array([0.66, 0.46, 0.27])
APRON = np.array([0.58, 0.40, 0.25])
CREAM = np.array([0.95, 0.92, 0.85])   # the water carrier's undyed scarf
LINEN = np.array([0.89, 0.83, 0.70])
LEATHER = np.array([0.40, 0.23, 0.12])
FLUSH = np.array([0.86, 0.46, 0.38])
WICKER = np.array([0.76, 0.50, 0.22])
STONE = np.array([0.60, 0.58, 0.56])
DUST = np.array([0.74, 0.64, 0.50])
# ── Maths ────────────────────────────────────────────────────────────────────

def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)

def g1(d, s):
    return np.exp(-(d * d) / (2.0 * s * s))

def g2(dx, dy, sx, sy):
    return np.exp(-(dx * dx) / (2.0 * sx * sx) - (dy * dy) / (2.0 * sy * sy))

def spow(c, e):
    return np.sign(c) * np.abs(c) ** e

def unit(v):
    return v / (np.linalg.norm(v, axis=-1, keepdims=True) + 1e-12)

def mixc(rgb, colour, t):
    return rgb + (np.asarray(colour) - rgb) * np.clip(t, 0.0, 1.0)[..., None]

def ip(keys, t, linear=False):
    """Rows of (t, values…) interpolated at t (any shape): Catmull-Rom, or straight lines."""
    k = np.asarray(keys, float)
    tk, yk = k[:, 0], k[:, 1:]
    t = np.clip(np.asarray(t, float), tk[0], tk[-1])
    i = np.clip(np.searchsorted(tk, t, side="right") - 1, 0, len(tk) - 2)
    h = (tk[i + 1] - tk[i])[..., None]
    s = (t - tk[i])[..., None] / h
    y0, y1 = yk[i], yk[i + 1]
    if linear:
        return y0 + (y1 - y0) * s
    m = np.empty_like(yk)
    m[1:-1] = (yk[2:] - yk[:-2]) / (tk[2:] - tk[:-2])[:, None]
    m[0] = (yk[1] - yk[0]) / (tk[1] - tk[0])
    m[-1] = (yk[-1] - yk[-2]) / (tk[-1] - tk[-2])
    s2, s3 = s * s, s * s * s
    return (2 * s3 - 3 * s2 + 1) * y0 + (s3 - 2 * s2 + s) * h * m[i] + (-2 * s3 + 3 * s2) * y1 + (s3 - s2) * h * m[i + 1]

def _hash(ix, iy, iz):
    n = ix.astype(np.int64) * 374761393 + iy.astype(np.int64) * 668265263 + iz.astype(np.int64) * 1274126177
    n = (n ^ (n >> 13)) * 1103515245
    n = n ^ (n >> 16)
    return (n & 0xFFFF).astype(float) / 65535.0

def vnoise(p):
    """Value noise in 0..1 over points (..., 3)."""
    f = np.floor(p)
    t = p - f
    t = t * t * (3.0 - 2.0 * t)
    ix, iy, iz = f[..., 0], f[..., 1], f[..., 2]
    out = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (t[..., 0] if dx else 1 - t[..., 0]) * (t[..., 1] if dy else 1 - t[..., 1]) * (t[..., 2] if dz else 1 - t[..., 2])
                out = out + w * _hash(ix + dx, iy + dy, iz + dz)
    return out

def fbm(p, octaves=3):
    out, amp, total = 0.0, 1.0, 0.0
    for o in range(octaves):
        out = out + amp * vnoise(p * (2.0 ** o) + o * 17.3)
        total += amp
        amp *= 0.5
    return out / total

def grid_normals(P):
    n = np.cross(np.gradient(P, axis=1), np.gradient(P, axis=0))
    ln = np.linalg.norm(n, axis=-1, keepdims=True)
    fallback = unit(P - P.reshape(-1, 3).mean(0))
    return np.where(ln > 1e-10, n / (ln + 1e-20), fallback)

# ── Surfaces ─────────────────────────────────────────────────────────────────

def lathe(keys, U, V, e=2.0, linear=False):
    """Rings stacked up y. keys: (v, y, rx, rz[, cx, cz]); u = 0 is the front (+z)."""
    k = ip(keys, V, linear)
    a = TAU * U
    ex = 2.0 / e
    cx = k[..., 3] if k.shape[-1] > 3 else 0.0
    cz = k[..., 4] if k.shape[-1] > 4 else 0.0
    return np.stack([cx + k[..., 1] * spow(np.sin(a), ex), k[..., 0], cz + k[..., 2] * spow(np.cos(a), ex)], -1)

def tube(keys, U, V, hint=(0, 0, 1), side=None, e=2.0):
    """A section swept along a path. keys: (v, x, y, z, ra, rb): ra across (the side
    vector: tangent × hint, or `side`), rb the other way."""
    d = 1e-3
    Vc = np.clip(V, d, 1.0 - d)
    k = ip(keys, Vc)
    T = unit(ip(keys, Vc + d)[..., :3] - ip(keys, Vc - d)[..., :3])
    if side is not None:
        S = np.broadcast_to(np.asarray(side, float), T.shape)
        O = unit(np.cross(S, T))
    else:
        S = unit(np.cross(T, np.asarray(hint, float)))
        O = np.cross(S, T)
    a = TAU * U
    ex = 2.0 / e
    return k[..., :3] + S * (k[..., 3] * spow(np.cos(a), ex))[..., None] + O * (k[..., 4] * spow(np.sin(a), ex))[..., None]

def ellipsoid(c, r, U, V):
    a = TAU * U
    lat = (V - 0.5) * math.pi
    return np.stack([c[0] + r[0] * np.cos(lat) * np.sin(a), c[1] + r[1] * np.sin(lat), c[2] + r[2] * np.cos(lat) * np.cos(a)], -1)

def ribbon(centre, U, V, ra, rb, out_from, e=4.0):
    """A flat band along centre(v) lying on a body: its face turned away from `out_from`."""
    d = 1e-3
    Vc = np.clip(V, d, 1.0 - d)
    C = centre(Vc)
    T = unit(centre(Vc + d) - centre(Vc - d))
    O = C - np.asarray(out_from, float)
    O = unit(O - T * np.sum(O * T, -1, keepdims=True))
    S = np.cross(T, O)
    a = TAU * U
    ex = 2.0 / e
    return C + S * (ra * spow(np.cos(a), ex))[..., None] + O * (rb * spow(np.sin(a), ex))[..., None]

# The skull: a superellipsoid the head, cloth, hair and beard are all measured from
HC = np.array([0.0, 1.285, 0.0])
HRX, HRY, HRZ, HE = 0.335, 0.385, 0.31, 2.4

def skull_f(y):
    t = np.clip(np.abs((y - HC[1]) / HRY), 0.0, 1.0)
    return (1.0 - t ** HE) ** (1.0 / HE)

def ell_r(a, rx, rz):
    return 1.0 / np.sqrt((np.sin(a) / rx) ** 2 + (np.cos(a) / rz) ** 2)

def skull_r(a, y):
    return ell_r(a, HRX, HRZ) * skull_f(y)

def polar(a, y, r):
    return np.stack([r * np.sin(a), y + 0.0 * a, HC[2] + r * np.cos(a)], -1)

def skull_z(x, y):
    """Front surface of the skull at (x, y)."""
    f = skull_f(y)
    return HC[2] + HRZ * f * np.sqrt(np.clip(1.0 - (x / (HRX * f + 1e-6)) ** 2, 0.0, 1.0))

def rim_y(a):
    """The head cloth's edge: high on the brow, low on the nape."""
    return 1.47 + 0.055 * np.cos(a)

def beard_top(deg):
    return ip([(0, 1.045), (12, 1.07), (28, 1.135), (50, 1.20), (80, 1.275), (112, 1.30)], np.abs(deg))[..., 0]

def beard_bottom(deg):
    base = ip([(0, 0.775), (30, 0.80), (60, 0.90), (85, 1.05), (112, 1.19)], np.abs(deg))[..., 0]
    return base + 0.045 * (1.0 - np.abs(np.cos(np.radians(deg) * 180.0 / 26.0)) ** 0.7)

TUNIC = [  # v, y, rx, rz, cx, cz
    (0.00, 0.215, 0.335, 0.245, 0, 0.0),
    (0.03, 0.172, 0.388, 0.287, 0, 0.005),
    (0.20, 0.33, 0.362, 0.268, 0, 0.005),
    (0.40, 0.50, 0.325, 0.240, 0, 0.0),
    (0.46, 0.545, 0.315, 0.232, 0, 0.0),
    (0.53, 0.60, 0.335, 0.245, 0, 0.0),
    (0.72, 0.80, 0.350, 0.248, 0, 0.0),
    (0.86, 0.92, 0.335, 0.228, 0, 0.0),
    (0.94, 0.985, 0.26, 0.19, 0, 0.0),
    (1.00, 1.005, 0.17, 0.15, 0, 0.0),
]
if SLOT == 3:
    # The overseer's robe, long to the ankle and flared, so the legs walk inside it
    TUNIC = [(0.00, 0.17, 0.40, 0.355, 0, 0.0), (0.03, 0.12, 0.455, 0.405, 0, 0.01), (0.20, 0.30, 0.395, 0.325, 0, 0.005),
        (0.40, 0.50, 0.325, 0.240, 0, 0.0)] + TUNIC[4:]
TUNIC_E = 2.6
HEM_Y = 0.12 if SLOT == 3 else 0.172
TUNIC_Y = [(k[1], k[2], k[3]) for k in TUNIC[1:]]   # by height, for what's worn over it

# ── Parts ────────────────────────────────────────────────────────────────────
PARTS = []

class Ctx:
    pass

class Part:
    def __init__(self, name, shape, nu, nv, paint, weights, closed=True, form=None, mirror=False,
            res=1.0, ref=None, rect_of=None):
        self.name, self.shape, self.nu, self.nv = name, shape, nu, nv
        self.paint, self.weights, self.closed, self.form = paint, weights, closed, form
        self.mirror, self.res, self.ref, self.rect_of = mirror, res, ref, rect_of
        self.sign = 1.0
        self.rect = None
        PARTS.append(self)
    def surface(self, U, V):
        P = self.shape(U, V)
        f = np.zeros(U.shape)
        if self.form is not None:
            f = self.form(U, V, P)
            P = P + grid_normals(P) * self.sign * f[..., None]
        return P, f
    def prepare(self):
        U, V = np.meshgrid(np.linspace(0, 1, self.nu + 1), np.linspace(0, 1, self.nv + 1))
        P0 = self.shape(U, V)
        ref = np.asarray(self.ref, float) if self.ref is not None else P0.reshape(-1, 3).mean(0)
        self.sign = 1.0 if np.mean(np.sum(grid_normals(P0) * (P0 - ref), -1)) >= 0.0 else -1.0
        self.U, self.V = U, V
        self.P, _ = self.surface(U, V)
        self.Lu = float(np.linalg.norm(np.diff(self.P, axis=1), axis=-1).sum(1).mean())
        self.Lv = float(np.linalg.norm(np.diff(self.P, axis=0), axis=-1).sum(0).mean())

def W(bone):
    return lambda P, U, V: {bone: np.ones(len(P))}

def out(rgb, h=None, rough=0.85, dye=0.0):
    return {"rgb": rgb, "h": h, "rough": rough, "dye": dye}

def threads(c, period=0.006, amp=1.0):
    """Homespun cloth: slubs and a soft unevenness as a fine height (a regular weave would
    need finer texels than a figure gets)."""
    return amp * (0.0005 * (fbm(c.P * 140.0, 2) - 0.5) + 0.0006 * (fbm(c.P * np.array([30.0, 220.0, 30.0]), 2) - 0.5))


def cloth(c, base, shade=0.5):
    """Linen-like paint: a little mottle, darker in the folds the form pressed in."""
    rgb = np.ones(c.U.shape + (3,)) * base
    rgb = rgb * (0.96 + 0.08 * fbm(c.P * 9.0))[..., None]
    span = max(float(np.abs(c.f).max()), 1e-4)
    return rgb * (1.0 - shade * 0.22 * np.clip(-c.f / span, -1.0, 1.0) - shade * 0.06)[..., None]

# Head ------------------------------------------------------------------------
def head_shape(U, V):
    t = TAU * U
    a = t - 0.5 * np.sin(t)      # columns gathered at the face
    y = ip([(0, 0.91), (0.10, 1.0), (0.80, 1.47), (1.0, 1.62)], V, True)[..., 0]
    return polar(a, y, skull_r(a, y))

def head_form(U, V, P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    ax = np.abs(x)
    front = sstep(-0.02, 0.12, z)
    h = 0.125 * g2(x, y - 1.215, 0.066, 0.056)            # nose
    h += 0.040 * g2(x, y - 1.31, 0.036, 0.075)            # its bridge
    h += 0.030 * g2(ax - 0.20, y - 1.185, 0.085, 0.07)    # cheeks
    h += 0.012 * g2(ax - 0.16, y - 1.425, 0.11, 0.028)    # brow ridge
    h -= 0.014 * g2(ax - 0.155, y - 1.30, 0.07, 0.06)     # eye sockets
    h += 0.030 * g2(x, y - 1.082, 0.055, 0.02)            # lower lip
    return h * front

def head_paint(c):
    x, y, z = c.x, c.y, c.z
    ax = np.abs(x)
    deg = np.degrees(np.arctan2(ax, z))
    front = sstep(-0.02, 0.12, z)
    rgb = np.ones(c.U.shape + (3,)) * SKIN * (0.97 + 0.06 * fbm(c.P * 7.0))[..., None]
    flush = 0.42 * g2(ax - 0.20, y - 1.18, 0.08, 0.065) + 0.34 * g2(x, y - 1.205, 0.06, 0.05)
    rgb = mixc(rgb, FLUSH, flush * front)
    rgb = rgb * (1.0 - 0.16 * g2(ax - 0.155, y - 1.30, 0.085, 0.075) * front)[..., None]
    # Upper lid: a soft dark crease over each eye
    d = ((ax - 0.155) / 0.092) ** 2 + ((y - 1.292) / 0.102) ** 2
    lid = g1(d - 1.0, 0.16) * sstep(1.27, 1.33, y) * front
    rgb = mixc(rgb, SKIN * 0.55, 0.5 * lid)
    # Mouth under the moustache, the lower lip showing
    rgb = mixc(rgb, np.array([0.34, 0.15, 0.12]), g2(x, y - 1.112, 0.06, 0.008) * front)
    rgb = mixc(rgb, np.array([0.74, 0.42, 0.36]), 0.8 * g2(x, y - 1.082, 0.05, 0.016) * front)
    # Under the beard and the hair the skin is shaded to them: no pale gap at their edges
    under = sstep(beard_top(deg) + 0.03, beard_top(deg) - 0.01, y) * sstep(118, 108, deg) * (1.0 if NPC.get("beard", "x") else 0.0)
    crown = np.maximum(sstep(1.46, 1.52, y), sstep(75, 95, deg) * sstep(1.12, 1.2, y))
    rgb = mixc(rgb, HAIR * 0.9, np.maximum(under, crown))
    o = out(rgb, rough=0.80 - 0.08 * g2(x, y - 1.22, 0.05, 0.05) * front)
    o["skin"] = 1.0 - np.maximum(under, crown)
    return o

Part("head", head_shape, 40, 26, head_paint, W("head"), form=head_form, res=1.7)

def ear_form(U, V, P):
    out_ = sstep(0.39, 0.43, P[..., 0])
    return -0.022 * g2(P[..., 1] - 1.285, P[..., 2] - 0.0, 0.05, 0.03) * out_

def ear_paint(c):
    rgb = np.ones(c.U.shape + (3,)) * SKIN
    rgb = mixc(rgb, FLUSH, 0.3 + 0.0 * c.x)
    rgb = mixc(rgb, SKIN * 0.5, 0.8 * g2(c.y - 1.285, c.z, 0.045, 0.026) * sstep(0.39, 0.43, c.x))
    o = out(rgb, rough=0.75)
    o["skin"] = 1.0
    return o

Part("ear", lambda U, V: ellipsoid((0.365, 1.29, 0.0), (0.075, 0.108, 0.062), U, V), 8, 6, ear_paint, W("head"),
    form=ear_form, mirror=True, res=1.2)

def eye_part(tag, cx):
    c0 = np.array([cx, 1.292, 0.250])
    rx, ry, rz = 0.072, 0.082, 0.072
    inward = -1.0 if cx > 0 else 1.0
    def shape(U, V):
        sx, sy = 2 * U - 1, 2 * V - 1
        dx = sx * np.sqrt(np.clip(1 - sy * sy / 2, 0, 1))
        dy = sy * np.sqrt(np.clip(1 - sx * sx / 2, 0, 1))
        return np.stack([c0[0] + rx * dx, c0[1] + ry * dy, c0[2] + rz * np.sqrt(np.clip(1 - dx * dx - dy * dy, 0, 1))], -1)
    def paint(c):
        ex, ey = (c.x - c0[0]) / rx, (c.y - c0[1]) / ry
        r = np.sqrt(ex * ex + ey * ey)
        rgb = np.ones(c.U.shape + (3,)) * np.array([0.95, 0.93, 0.88])
        rgb = rgb * (1.0 - 0.14 * sstep(0.2, 1.0, ey))[..., None]         # the lid's shade
        ix, iy = ex - inward * 0.05, ey - 0.20
        ir = np.sqrt(ix * ix + iy * iy)
        iris = np.array([0.36, 0.21, 0.10]) * (0.85 + 0.4 * sstep(0.2, -0.5, iy))[..., None]
        rgb = np.where((ir < 0.58)[..., None], iris, rgb)
        rgb = mixc(rgb, np.array([0.13, 0.07, 0.04]), 0.7 * g1(ir - 0.58, 0.045))   # limbal ring
        rgb = mixc(rgb, np.array([0.04, 0.025, 0.02]), sstep(0.31, 0.27, ir))
        rgb = mixc(rgb, np.array([1.0, 1.0, 0.98]), 0.9 * sstep(0.11, 0.07, np.hypot(ix - 0.20, iy - 0.16)))
        # A soft rim; the iris sits high, its top under the lid's edge, so no white shows above it:
        # a calm look up at the camera, not a stare
        rgb = mixc(rgb, np.array([0.16, 0.08, 0.05]), 0.45 * sstep(0.84, 0.97, r))
        lid_y = 0.86 - 0.2 * ex * ex
        if SLOT == 4:
            lid_y = 0.58 - 0.18 * ex * ex - 0.22 * ex * inward
        rgb = mixc(rgb, rgb * 0.85, sstep(lid_y - 0.3, lid_y, ey))                  # its shadow
        rgb = mixc(rgb, np.array([0.15, 0.08, 0.05]), 0.85 * g1(ey - lid_y, 0.03))        # lash line
        lid = SKIN * 0.9 + (FLUSH - SKIN) * 0.1
        rgb = mixc(rgb, lid, sstep(lid_y + 0.03, lid_y + 0.08, ey))
        rough = 0.30 + 0.45 * sstep(lid_y + 0.03, lid_y + 0.08, ey)
        o = out(rgb, rough=rough)
        o["skin"] = sstep(lid_y + 0.03, lid_y + 0.08, ey)
        return o
    Part("eye_" + tag, shape, 8, 8, paint, W("eye_" + tag), closed=False, res=3.2, ref=c0 - np.array([0, 0, 0.3]))

eye_part("l", 0.155)
eye_part("r", -0.155)

def hair_paint(c, flow=40.0, tip=0.0):
    """Hair: strands along v, lighter where the locks swell, a warm sheen."""
    streak = fbm(np.stack([c.U * flow, c.V * 2.0, c.U * 0.0 + 3.0], -1))
    rgb = np.ones(c.U.shape + (3,)) * HAIR * (0.9 + 0.5 * streak)[..., None]
    span = max(float(np.abs(c.f).max()), 1e-4)
    rgb = rgb * (1.0 + 0.45 * np.clip(c.f / span, -1.0, 1.0))[..., None]
    rgb = mixc(rgb, HAIR * 2.2, 0.25 * tip)
    h = 0.0011 * np.sin(TAU * c.U * flow * 0.9 + 4.0 * streak)
    return out(rgb, h=h, rough=0.8)

BROW = [(0, 0.05, 1.44, 0.004, 0.004), (0.12, 0.075, 1.448, 0.02, 0.016), (0.5, 0.165, 1.46, 0.023, 0.018),
    (0.88, 0.255, 1.432, 0.017, 0.014), (1.0, 0.282, 1.414, 0.004, 0.004)]
if SLOT == 4:
    BROW = [(0, 0.045, 1.398, 0.004, 0.004), (0.12, 0.07, 1.405, 0.026, 0.02), (0.5, 0.165, 1.44, 0.028, 0.022),
        (0.88, 0.25, 1.462, 0.02, 0.016), (1.0, 0.275, 1.462, 0.004, 0.004)]

def brow_shape(U, V):
    keys = []
    for t, x, y, ra, rb in BROW:
        keys.append((t, x, y, float(skull_z(x, y)) + 0.02, ra, rb))
    return tube(keys, U, V)

Part("brow", brow_shape, 6, 7, lambda c: hair_paint(c, 6.0), W("head"), mirror=True, res=1.6)

def moustache_shape(U, V):
    keys = [(0, -0.012, 1.160, 0.352, 0.03, 0.03), (0.3, 0.065, 1.150, 0.345, 0.044, 0.03), (0.62, 0.15, 1.108, 0.312, 0.042, 0.028),
        (0.88, 0.208, 1.055, 0.272, 0.024, 0.02), (1.0, 0.222, 1.028, 0.258, 0.004, 0.004)]
    return tube(keys, U, V)

def lock_form(U, V, P):
    return 0.004 * np.sin(TAU * U * 3.0) * np.sin(V * math.pi)

if NPC.get("beard", "x"):
  Part("moustache", moustache_shape, 8, 8, lambda c: hair_paint(c, 6.0, c.V), W("head"), form=lock_form, mirror=True, res=1.5)

# Beard: a patch round the jaw, ear to ear, its lower edge cut into locks
BEARD_A = 112.0
# Full (the builder) or short and close (the water carrier): its length down the chin, its
# depth off the jaw, its rows of curls
BEARD_LEN, BEARD_THICK, BEARD_ROWS = [(1.0, 1.0, 3.0), (0.62, 0.62, 2.0), (1.0, 1.05, 3.0), (1.6, 1.1, 4.0),
    (0.62, 0.62, 2.0) if FOE.get("beard") == "short" else (1.0, 1.0, 3.0)][SLOT]
if "beard" in NPC:
    BEARD_LEN, BEARD_THICK, BEARD_ROWS = {"short": (0.62, 0.62, 2.0), "full": (1.0, 1.0, 3.0), "long": (1.6, 1.1, 4.0),
        "": (1.0, 1.0, 3.0)}[NPC["beard"]]

def beard_shape(U, V):
    deg = BEARD_A * (2.0 * U - 1.0)
    a = np.radians(deg)
    y = beard_top(deg) + (beard_bottom(deg) - beard_top(deg)) * BEARD_LEN * V
    base = skull_r(a, np.maximum(y, 1.0)) * (1.0 - 0.35 * sstep(1.0, 0.78, y))
    edge = sstep(0.0, 0.10, U) * sstep(1.0, 0.90, U)
    thick = (0.05 + 0.085 * np.cos(np.radians(deg * 90.0 / BEARD_A)) ** 1.2) * edge * BEARD_THICK
    bulge = np.sin(math.pi * np.clip(V, 0, 1) ** 0.62) ** 0.75
    r = base - 0.014 + (thick + 0.014) * bulge
    r = r * (1.0 - 0.3 * sstep(0.8, 1.0, V))
    if BEARD_LEN > 1.2:
        r = r + 0.10 * sstep(0.95, 0.72, y) * np.cos(a) ** 2
    return polar(a, y, r)

def beard_locks(U, V):
    """Rows of curls, each row set half a curl across from the one above (as beards were cut
    in Persian-period carving): 1 on a curl's crest, 0 in the furrows between."""
    deg = BEARD_A * (2.0 * U - 1.0)
    row = np.floor(np.clip(V, 0, 0.999) * BEARD_ROWS)
    fr = np.clip(V, 0, 0.999) * BEARD_ROWS - row
    across = np.abs(np.cos(math.pi * (deg / 26.0 + 0.5 * row))) ** 0.7
    down = np.sin(math.pi * fr ** 0.8) ** 0.5
    last = row >= BEARD_ROWS - 1.0
    return across * np.where(last, np.maximum(down, sstep(0.0, 0.5, fr)), down)


def beard_form(U, V, P):
    return 0.034 * BEARD_THICK * (beard_locks(U, V) - 0.55) * sstep(0.03, 0.14, V) * sstep(0.0, 0.08, U) * sstep(1.0, 0.92, U)


def beard_paint(c):
    o = hair_paint(c, 34.0)
    o["rgb"] = o["rgb"] * (0.62 + 0.55 * beard_locks(c.U, c.V))[..., None]
    return o


if NPC.get("beard", "x"):
    Part("beard", beard_shape, 44, 16, beard_paint, W("head"), closed=False, form=beard_form, ref=HC, res=1.3)

# Head cloth: the crew colour, seen first from the play camera. A length of dyed cloth wound
# round the head (the band) over a cloth crown, knotted behind, its two ends hanging.
# The water carrier's is a narrower scarf, undyed with dyed stripes, tied low round his curls
# with no crown: the curls heap up over it
# The carpenter's is a plain dyed band round a bush of hair; the overseer's a narrow dyed band
# over a tall undyed wrap, its cloth falling behind to the shoulders
BAND_R, BAND_H, BAND_LIFT, BAND_OUT = [(0.058, 0.086, 0.05, 0.05), (0.046, 0.058, 0.03, 0.058),
    (0.044, 0.054, 0.035, 0.075), (0.042, 0.05, 0.035, 0.085), (0.05, 0.06, 0.03, 0.06)][SLOT]

def band_centre(a):
    y = rim_y(a) + BAND_LIFT
    return y, skull_r(a, y) + BAND_OUT

def band_shape(U, V):
    a = TAU * U
    y, r = band_centre(a)
    phi = np.radians(-150.0 + 300.0 * V)
    return polar(a, y + BAND_H * np.sin(phi), r + BAND_R * np.cos(phi)) + np.array([0.0, 0.0, -0.012])

def band_wind(U, V):
    return 3.0 * V + 4.0 * U          # the winding: whole turns round the head, so it meets itself

def band_form(U, V, P):
    w = band_wind(U, V)
    return (0.013 * np.cos(TAU * w) + 0.004 * np.sin(TAU * (w * 2.0 + 0.3))) * np.sin(math.pi * np.clip(V, 0, 1)) ** 0.5

def scarf_stripes(fr):
    """Across a length of the scarf (fr 0..1 edge to edge): a broad dyed stripe down its
    middle, a fine one either side, undyed between: 1 where dyed."""
    d = np.abs(fr - 0.5)
    return np.maximum(sstep(0.20, 0.18, d), 0.9 * sstep(0.022, 0.012, np.abs(d - 0.30)))

def npc_cloth(c, fixed=None, mask=1.0, shade=1.0):
    """A townsperson's cloth: a set colour, or dyed (by `mask` of the dye) from a pale shade."""
    if fixed is not None:
        return out(cloth(c, np.array(fixed), 1.0), h=threads(c), rough=0.9)
    o = dyed(c)
    o["rgb"] = o["rgb"] * shade
    o["dye"] = o["dye"] * mask
    return o

def band_paint(c):
    w = band_wind(c.U, c.V)
    if NPC and SLOT in (2, 3):
        return npc_cloth(c, NPC.get("band_fixed"), 1.0, NPC.get("band_shade", 1.0))
    if SLOT in (2, 3):
        return dyed(c)
    if SLOT == 1:
        return scarf(c, scarf_stripes(w % 1.0))
    stripe = sstep(0.035, 0.05, 0.07 - np.abs((w + 0.5) % 1.0 - 0.5)) * sstep(0.1, 0.2, c.V) * sstep(0.9, 0.8, c.V)
    return dyed(c, 0.9 * stripe)

CROWN_TOP, CROWN_PUFF = (1.80, 0.05) if SLOT == 3 else (1.735, 0.0)

def crown_shape(U, V):
    a = TAU * U
    y0, r0 = band_centre(a)
    y0 = y0 + 0.03
    t = np.sin(np.clip(V, 0, 1) * math.pi / 2.0)
    y = y0 + (CROWN_TOP - y0) * t ** 1.1
    r = (r0 + 0.012 + CROWN_PUFF * np.sin(math.pi * np.clip(V, 0, 1) * 0.8)) * np.cos(np.clip(V, 0, 1) * math.pi / 2.0) ** 0.75
    return polar(a, y, r) + np.array([0.0, 0.0, -0.012])

KNOT = np.array([-0.195, 1.47, -0.425])
KNOT_A = math.atan2(KNOT[0], KNOT[2])
# The knot rides on the band: lower with it on the water carrier's scarf
KNOT_DY = float(band_centre(KNOT_A)[0]) - float(rim_y(KNOT_A) + 0.05)
KNOT = KNOT + np.array([0.0, KNOT_DY, 0.0])

def crown_form(U, V, P):
    a = TAU * U
    return 0.007 * np.sin(7.0 * (a - KNOT_A) + 9.0 * V + 2.0 * vnoise(P * 5.0)) * sstep(0.05, 0.3, V) * sstep(1.0, 0.7, V)

def dyed(c, stripes=None):
    """Dyed cloth: its shade painted near white, the dye mask set; `stripes` stays undyed."""
    rgb = cloth(c, np.array([0.93, 0.93, 0.93]), 1.0)
    dye = np.ones(c.U.shape)
    if stripes is not None:
        rgb = mixc(rgb, LINEN * 1.04, stripes)
        dye = 1.0 - stripes
    return out(rgb, h=threads(c), rough=0.9, dye=dye)

def scarf(c, dye):
    """Undyed cloth (the water carrier's scarf) with dyed stripes woven in: `dye` 1 where dyed."""
    rgb = cloth(c, CREAM, 1.0)
    rgb = mixc(rgb, np.array([0.93, 0.93, 0.93]) * (0.9 + 0.1 * fbm(c.P * 9.0))[..., None], dye)
    return out(rgb, h=threads(c), rough=0.9, dye=dye)

def knot_paint(c):
    if SLOT == 1:
        return scarf(c, scarf_stripes((c.U * 3.0) % 1.0))
    return dyed(c)

def wrap_paint(c):
    """The overseer's head-wrap: undyed linen, wound."""
    if NPC.get("wrap_mask"):
        return npc_cloth(c, None, NPC["wrap_mask"])
    return out(cloth(c, np.array(NPC.get("wrap", ROBE)), 1.0), h=threads(c), rough=0.9)

if SLOT < 4:
    Part("band", band_shape, 28, 7, band_paint, W("head"), form=band_form, ref=HC, res=1.2)
if SLOT == 0:
    Part("crown", crown_shape, 20, 6, dyed, W("head"), form=crown_form, ref=HC, res=1.0)
if SLOT == 3:
    Part("crown", crown_shape, 24, 8, wrap_paint, W("head"), form=lambda U, V, P: 1.3 * crown_form(U, V, P), ref=HC, res=1.0)
if SLOT < 3:
    Part("knot", lambda U, V: ellipsoid(KNOT, (0.066, 0.056, 0.05), U, V), 8, 5, knot_paint, W("head"), res=0.8)

def tail(name, bone, pts):
    keys = [(t, x, y + KNOT_DY, z, ra, 0.011) for t, x, y, z, ra in pts]
    def form(U, V, P):
        return 0.006 * np.sin(V * 9.0 + (2.0 if bone == "tail_1" else 0.0)) * np.cos(TAU * U)
    def paint(c):
        if SLOT == 1:
            # Striped along its length, as the cloth was woven; a fringe at the end
            o = scarf(c, scarf_stripes((c.U * 2.0 + 0.25) % 1.0) * sstep(0.93, 0.90, c.V))
            o["rgb"] = o["rgb"] * (1.0 - 0.3 * sstep(0.93, 0.95, c.V) * (0.5 + 0.5 * np.sin(TAU * c.U * 12.0)))[..., None]
            return o
        return dyed(c, sstep(0.01, 0.02, 0.03 - np.abs(c.V - 0.86)))
    Part(name, lambda U, V: tube(keys, U, V, e=3.0), 6, 7, paint, W(bone), form=form, res=0.9)

if SLOT < 3:
  tail("tail_a", "tail_0", [(0, -0.21, 1.465, -0.44, 0.02), (0.3, -0.27, 1.36, -0.475, 0.052), (0.7, -0.325, 1.235, -0.49, 0.06),
    (0.97, -0.355, 1.15, -0.48, 0.052), (1.0, -0.358, 1.142, -0.478, 0.004)])
  tail("tail_b", "tail_1", [(0, -0.18, 1.46, -0.445, 0.02), (0.3, -0.16, 1.37, -0.48, 0.048), (0.7, -0.135, 1.275, -0.495, 0.054),
    (0.97, -0.122, 1.205, -0.485, 0.048), (1.0, -0.12, 1.198, -0.483, 0.004)])

# Hair: a mass of curls at the back, below the cloth, and locks out from under its edge
HAIR_A0 = [68.0, 56.0, 62.0, 68.0, 68.0][SLOT]       # from in front of one ear round the nape to the other

def hair_back_shape(U, V):
    a = np.radians(HAIR_A0 + (360.0 - 2.0 * HAIR_A0) * U)
    side = np.abs(np.cos(a))                    # 0 at the ears, 1 at the nape
    bottom = 1.215 - 0.085 * sstep(0.2, 0.9, side) - 0.04 * np.abs(np.sin(a * 5.5))
    top = rim_y(a) + BAND_LIFT - 0.015
    y = top + (bottom - top) * V
    edge = sstep(0.0, 0.07, U) * sstep(1.0, 0.93, U)
    thick = -0.012 + (0.03 + 0.05 * sstep(0.0, 0.5, V) * sstep(1.0, 0.86, V)) * edge
    thick = thick - 0.03 * sstep(0.9, 1.0, V)
    return polar(a, y, skull_r(a, y) + thick)

def hair_back_form(U, V, P):
    a = 68.0 + 224.0 * U
    curls = np.sin(np.radians(a) * 13.0 + 2.2 * np.sin(P[..., 1] * 34.0)) * np.sin(P[..., 1] * 40.0 + a * 0.05)
    return 0.012 * curls * sstep(0.12, 0.3, V) * sstep(1.0, 0.9, V)

if SLOT in (0, 2) or "helmet" in FOE:
    Part("hair_back", hair_back_shape, 24, 8, lambda c: hair_paint(c, 20.0, sstep(0.6, 1.0, c.V)), W("head"), closed=False,
        form=hair_back_form, ref=HC, res=1.0)

def lock(name, a0, sweep, length, width, y_off=0.0, first=None):
    y0 = float(rim_y(math.radians(a0))) + y_off
    keys = []
    for t, da, y, ro, ra, rb in [(0, 0, y0 + 0.05, -0.012, width * 0.6, 0.012), (0.3, sweep * 0.2, y0 + 0.002, 0.034, width * 1.2, 0.03),
            (0.7, sweep * 0.7, y0 - length * 0.65, 0.046, width, 0.027), (1.0, sweep, y0 - length, 0.045, 0.004, 0.004)]:
        a = math.radians(a0 + da)
        p = polar(np.array(a), np.array(y), skull_r(np.array(a), np.array(y)) + ro)
        keys.append((t, float(p[0]), float(p[1]), float(p[2]), ra, rb))
    hint = (math.sin(math.radians(a0)), 0.25, math.cos(math.radians(a0)))
    return Part(name, lambda U, V: tube(keys, U, V, hint=hint), 6, 6, lambda c: hair_paint(c, 5.0, c.V), W("head"), form=lock_form,
        res=1.0, rect_of=first)

_first = None
if SLOT == 0:
    for i, (a0, sweep, length, width) in enumerate([(-8, 22, 0.062, 0.05), (14, 24, 0.05, 0.048), (-30, -22, 0.055, 0.05),
            (36, 20, 0.07, 0.05), (-52, -18, 0.075, 0.048), (57, 14, 0.085, 0.046), (-70, -8, 0.10, 0.044), (74, 6, 0.11, 0.044)]):
        p = lock("lock%d" % i, a0, sweep, length, width, first=_first)
        _first = _first or p
# Sideburns, down in front of the ears to meet the beard
if (SLOT in (0, 2, 3) or "helmet" in FOE) and NPC.get("beard", "x"):
    _b = lock("burn_l", 66, -6, 0.23, 0.04, -0.03, _first)
    lock("burn_r", -66, 6, 0.23, 0.04, -0.03, _first or _b)

# The water carrier's curls: a cap of tight curls heaped over the scarf, in rows (each row
# set half a curl across from the one below, like the beard), a fringe of them under its
# front edge
CURL_T = 0.045                                     # the cap's depth off the skull

def curls_y0(a):
    return rim_y(a) + BAND_LIFT - 0.045 - 0.03 * sstep(0.3, 0.9, np.cos(a))

def curls_shape(U, V):
    a = TAU * U
    y0 = curls_y0(a)
    top = HC[1] + HRY + CURL_T
    y = y0 + (top - y0) * np.sin(np.clip(V, 0, 1) * math.pi / 2.0) ** 0.85
    f = (1.0 - np.clip(np.abs((y - HC[1]) / (HRY + CURL_T)), 0.0, 1.0) ** HE) ** (1.0 / HE)
    r = ell_r(a, HRX + CURL_T, HRZ + CURL_T) * f
    return polar(a, y, r)

def worley(p, seed=0.0):
    """Distance from each point (..., 3) to the nearest of a jittered lattice of points, one
    per unit cell: 0 at a feature, about 0.5..0.9 at the borders between them."""
    f = np.floor(p)
    best = np.full(p.shape[:-1], 9.0)
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for dz in (-1, 0, 1):
                c = f + np.array([dx, dy, dz], float)
                ix, iy, iz = c[..., 0], c[..., 1], c[..., 2]
                j = np.stack([_hash(ix, iy, iz + seed), _hash(ix + 31, iy, iz + seed), _hash(ix, iy + 57, iz + seed)], -1)
                d = np.linalg.norm(c + 0.15 + 0.7 * j - p, axis=-1)
                best = np.minimum(best, d)
    return best

CURL_CELL = 0.072      # metres between curls

def curl_bumps(P):
    """1 on a curl's crown, 0 in the furrows: round, uneven, measured in space (no seams, no
    pole), so it is the same where the cap, the nape and the fringe meet."""
    d = worley(P / CURL_CELL, 3.0)
    return np.sqrt(np.clip(1.0 - (d / 0.62) ** 2, 0.0, 1.0))

def curls_form(U, V, P):
    return 0.03 * (curl_bumps(P) - 0.5) * sstep(0.0, 0.08, V)

def curls_paint(c):
    o = hair_paint(c, 30.0)
    b = curl_bumps(c.P)
    o["rgb"] = o["rgb"] * (0.68 + 0.5 * b)[..., None]
    # Each curl a tight coil: a few fine turns round its crown
    ang = np.arctan2(c.y - HC[1], c.x) * 0.0 + fbm(c.P * 80.0)
    o["h"] = 0.0008 * np.sin(TAU * (b * 3.0 + ang))
    return o

# The carpenter's bush: a quiet cap of hair, and over it broad locks swept from the brow back
# over the crown (as on the code rig), so the crown is a lock, not a point where seams meet
def bush_form(U, V, P):
    d = worley((P - HC) / np.array([0.08, 0.07, 0.14]), 7.0)
    return 0.012 * (np.sqrt(np.clip(1.0 - (d / 0.7) ** 2, 0.0, 1.0)) - 0.5) * sstep(0.0, 0.1, V) + 0.02 * np.sin(math.pi * np.clip(V, 0, 1))

def bush_paint(c):
    o = hair_paint(c, 22.0)
    o["rgb"] = o["rgb"] * 0.78
    return o

def sweep_lock(name, x0, width, lift, first):
    """A lock in the plane x = x0: up from over the brow, over the top, down the back."""
    T = 0.06 + lift
    keys = []
    for t, psi, out_, ra in [(0.0, 31, 0.0, 0.01), (0.08, 38, 0.035, width * 0.8), (0.35, 70, 0.05, width), (0.65, 115, 0.045, width * 0.95),
            (0.92, 150, 0.025, width * 0.6), (1.0, 158, 0.0, 0.006)]:
        k = math.sqrt(max(1.0 - (x0 / (HRX + T)) ** 2, 0.05))
        r_y, r_z = (HRY + T + out_) * k, (HRZ + T + out_) * k
        ps = math.radians(psi)
        keys.append((t, x0 * (1.0 + 0.15 * math.sin(ps)), HC[1] + r_y * math.sin(ps) * 0.97, HC[2] + r_z * math.cos(ps), ra, 0.034))
    return Part(name, lambda U, V: tube(keys, U, V, side=(1.0, 0.0, 0.0)), 8, 10, lambda c: hair_paint(c, 6.0, 0.4 * sstep(0.4, 0.0, np.abs(c.V - 0.4))),
        W("head"), form=lock_form, res=1.0, rect_of=first)

if SLOT == 2:
    CURL_T = 0.06
    Part("bush", curls_shape, 44, 14, bush_paint, W("head"), form=bush_form, ref=HC, res=1.1)
    _l = None
    for i, (x0, w, lift) in enumerate([(0.0, 0.085, 0.012), (0.13, 0.08, 0.0), (-0.13, 0.08, 0.004), (0.245, 0.065, -0.012), (-0.245, 0.065, -0.01)]):
        p = sweep_lock("sweep%d" % i, x0, w, lift, _l)
        _l = _l or p
if SLOT == 1:
    Part("curls", curls_shape, 64, 20, curls_paint, W("head"), form=curls_form, ref=HC, res=1.2)
    Part("hair_back", hair_back_shape, 36, 10, curls_paint, W("head"), closed=False,
        form=lambda U, V, P: curls_form(U, V, P) * sstep(1.0, 0.85, V), ref=HC, res=1.0)

VEIL_A0 = 64.0

def veil_shape(U, V):
    deg = VEIL_A0 + (360.0 - 2.0 * VEIL_A0) * U
    a = np.radians(deg)
    top = rim_y(a) + BAND_LIFT - BAND_H * 0.6
    bottom = 1.10 - 0.11 * sstep(95.0, 150.0, np.minimum(deg, 360.0 - deg))   # past the jaw at the sides, to the shoulders behind
    y = top + (bottom - top) * V
    side = sstep(0.0, 0.08, U) * sstep(1.0, 0.92, U)
    r = skull_r(a, np.maximum(y, 1.12)) + BAND_OUT + 0.01 + 0.09 * np.clip(V, 0, 1) ** 1.4 - 0.02 * (1.0 - side)
    return polar(a, y, r)

def veil_form(U, V, P):
    a = np.radians(VEIL_A0 + (360.0 - 2.0 * VEIL_A0) * U)
    return 0.012 * np.sin(a * 7.0 + 1.5 * vnoise(P * 4.0)) * sstep(0.1, 0.5, V)

def veil_paint(c):
    if NPC.get("wrap_mask"):
        return npc_cloth(c, None, NPC["wrap_mask"])
    if NPC:
        o = wrap_paint(c)
        if NPC.get("vest"):
            stripe = sstep(0.012, 0.006, np.abs(c.V - 0.93))
            o["rgb"] = mixc(o["rgb"], np.array([0.93] * 3), stripe)
            o["dye"] = stripe
        return o
    return scarf(c, sstep(0.012, 0.006, np.abs(c.V - 0.93)))   # a dyed stripe along its hem

def veil_w(P, U, V):
    deg = VEIL_A0 + (360.0 - 2.0 * VEIL_A0) * U
    back = sstep(115.0, 145.0, np.minimum(deg, 360.0 - deg))
    return {"head": 1.0 - back, "veil": back}

if SLOT == 3:
    Part("veil", veil_shape, 30, 9, veil_paint, veil_w, closed=False, form=veil_form, ref=HC, res=0.9)

# Body ------------------------------------------------------------------------
def tunic_form(U, V, P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    a = np.arctan2(x, z)
    live = sstep(0.03, 0.07, V)
    pleats = 0.017 * sstep(0.53, 0.33, y) * np.sin(9.0 * a + 1.2 * np.sin(y * 8.0)) * (1.4 if SLOT == 3 else 1.0)
    gather = 0.011 * sstep(0.55, 0.62, y) * sstep(0.84, 0.64, y) * np.sin(13.0 * a + 2.0 * vnoise(P * 4.0))
    hem = 0.016 * sstep(0.42, 0.18, y) * np.sin(6.0 * a + 0.7)
    blouse = 0.010 * g1(y - 0.615, 0.03)
    return (pleats + gather + hem + blouse) * live

def tunic_paint(c):
    y = c.y
    a = np.arctan2(c.x, c.z)
    hy = HEM_Y - 0.172
    rgb = cloth(c, np.array(FOE["robe"]) if SLOT == 4 else ROBE if SLOT == 3 else LINEN, 1.0)
    rgb = mixc(rgb, DUST, 0.4 * sstep(0.36 + hy, 0.17 + hy, y) * (0.6 + 0.4 * fbm(c.P * 14.0)))
    rgb = rgb * (1.0 - 0.10 * g1(np.abs(np.sin(a)) - 1.0, 0.012) * sstep(0.95, 0.85, y))[..., None]    # side seams
    stripe = np.maximum(sstep(0.012, 0.017, 0.022 - np.abs(y - 0.222 - hy)), sstep(0.004, 0.007, 0.009 - np.abs(y - 0.262 - hy)))
    collar = sstep(0.945, 0.955, c.V)
    dye = np.maximum(stripe, collar)
    shade = 0.93 if SLOT != 2 else 0.5          # the carpenter's trim a deeper dye than his tunic
    rgb = mixc(rgb, np.array([shade] * 3) * (0.9 + 0.1 * fbm(c.P * 9.0))[..., None], dye)
    if SLOT == 4:
        # A foe's cloth is dark goat hair, its trim darker still: nothing dyed for the crew colour
        rgb = mixc(rgb, cloth(c, FOE_TRIM, 0.3), dye)
        dye = dye * 0.0
    if SLOT == 2 and not NPC:
        # The carpenter's tunic is dyed all over, a little muted (worker_look: dye toward undyed wool)
        dye = np.maximum(dye, 0.82 * (1.0 - dye))
    elif NPC.get("robe_mask"):
        dye = np.maximum(dye, NPC["robe_mask"] * (1.0 - dye))
    rgb = rgb * (0.45 + 0.55 * sstep(0.01, 0.03, c.V))[..., None]      # up inside the hem
    return out(rgb, h=threads(c, 0.007), rough=0.92, dye=dye)

def tunic_w(P, U, V):
    sk = sstep(0.60, 0.47, P[:, 1])
    return {"torso": 1.0 - sk, "skirt": sk}

Part("tunic", lambda U, V: lathe(TUNIC, U, V, TUNIC_E), 32, 20, tunic_paint, tunic_w, form=tunic_form, res=1.0)

def sleeve_paint(c):
    if SLOT == 4:
        return out(cloth(c, np.array(FOE["robe"])), h=threads(c, 0.007), rough=0.92)
    rgb = cloth(c, ROBE if SLOT == 3 else LINEN)
    dye = sstep(0.018, 0.026, 0.035 - np.abs(c.V - 0.775))
    rgb = mixc(rgb, np.array([0.93 if SLOT != 2 else 0.5] * 3), dye)
    if SLOT == 2 and not NPC:
        dye = np.maximum(dye, 0.82 * (1.0 - dye))
    elif NPC.get("robe_mask"):
        dye = np.maximum(dye, NPC["robe_mask"] * (1.0 - dye))
    rgb = rgb * (0.45 + 0.55 * sstep(0.96, 0.92, c.V))[..., None]
    return out(rgb, h=threads(c, 0.007), rough=0.92, dye=dye)

SLEEVE = [(0, 0.26, 0.90, 0.0, 0.085, 0.10), (0.25, 0.335, 0.868, 0.0, 0.10, 0.116), (0.55, 0.372, 0.78, 0.0, 0.103, 0.118),
    (0.85, 0.372, 0.665, 0.0, 0.108, 0.122), (0.92, 0.37, 0.632, 0.0, 0.112, 0.126), (1.0, 0.368, 0.66, 0.0, 0.086, 0.096)]
Part("sleeve", lambda U, V: tube(SLEEVE, U, V), 14, 8, sleeve_paint,
    lambda P, U, V: {"torso": 1.0 - sstep(0.05, 0.4, V), "arm_l": sstep(0.05, 0.4, V)},
    form=lambda U, V, P: 0.005 * np.sin(V * 26.0 + 2.0 * np.sin(TAU * U)) * sstep(0.2, 0.4, V) * sstep(0.9, 0.8, V), mirror=True, res=0.9)

def skin_paint(c):
    rgb = np.ones(c.U.shape + (3,)) * SKIN * (0.97 + 0.06 * fbm(c.P * 8.0))[..., None]
    o = out(rgb, rough=0.74)
    o["skin"] = 1.0
    return o

def arm_w(P, U, V):
    y = P[:, 1]
    e = sstep(0.655, 0.56, y)
    h = sstep(0.425, 0.365, y)
    return {"arm_l": 1.0 - e, "elbow_l": e * (1.0 - h), "hand_l": e * h}

ARM = [(0, 0.365, 0.84, 0.0, 0.078, 0.078), (0.3, 0.365, 0.70, 0.0, 0.081, 0.083), (0.52, 0.365, 0.606, 0.0, 0.073, 0.075),
    (0.72, 0.365, 0.52, 0.008, 0.081, 0.084), (0.93, 0.362, 0.43, 0.01, 0.064, 0.066), (1.0, 0.36, 0.39, 0.01, 0.058, 0.06)]

def arm_paint(c):
    o = skin_paint(c)
    o["rgb"] = mixc(o["rgb"], FLUSH, 0.22 * g1(c.y - 0.606, 0.03))
    if SLOT == 4:
        sleeve = sstep(0.43, 0.45, c.y)
        cuff = sstep(0.43, 0.445, c.y) * sstep(0.48, 0.465, c.y)
        cl = cloth(c, np.array(FOE["robe"]))
        cl = mixc(cl, FOE_TRIM, cuff)
        o["rgb"] = mixc(o["rgb"], cl, sleeve)
        o["skin"] = 1.0 - sleeve
        o["h"] = threads(c, 0.007) * sleeve
        o["rough"] = 0.74 + 0.18 * sleeve
    return o

Part("arm", lambda U, V: tube(ARM, U, V), 10, 9, arm_paint, arm_w, mirror=True, res=0.8)
if SLOT == 2 and not NPC:
    BRACER = [(0, 0.365, 0.565, 0.006, 0.084, 0.087), (0.5, 0.364, 0.50, 0.009, 0.088, 0.091), (1.0, 0.363, 0.44, 0.01, 0.072, 0.074)]
    def bracer_paint(c):
        o = leather_paint(c, 0.9)
        lace = sstep(0.75, 0.95, np.abs(np.sin(TAU * c.V * 3.0))) * sstep(0.08, 0.02, np.abs(c.U - 0.75))
        o["rgb"] = o["rgb"] * (1.0 - 0.25 * g1(c.V - 0.05, 0.03) - 0.25 * g1(c.V - 0.95, 0.03))[..., None]
        o["rgb"] = mixc(o["rgb"], LEATHER * 0.5, lace)
        return o
    Part("bracer", lambda U, V: tube(BRACER, U, V), 10, 3, bracer_paint, arm_w, mirror=True, res=0.8)
HAND = np.array([0.36, 0.352, 0.012])

def hand_form(U, V, P):
    x, y, z = P[..., 0] - HAND[0], P[..., 1] - HAND[1], P[..., 2] - HAND[2]
    front = sstep(0.0, 0.045, z) * sstep(0.055, 0.0, y)
    grooves = sum(g1(x - xi, 0.0085) for xi in (-0.044, 0.0, 0.044))
    knuckles = sum(g2(x - xi, y - 0.035, 0.016, 0.018) for xi in (-0.066, -0.022, 0.022, 0.066))
    return -0.013 * grooves * front + 0.008 * knuckles * sstep(0.0, 0.04, z)

def hand_paint(c):
    o = skin_paint(c)
    x, y, z = c.x - HAND[0], c.y - HAND[1], c.z - HAND[2]
    front = sstep(0.0, 0.045, z) * sstep(0.055, 0.0, y)
    grooves = sum(g1(x - xi, 0.006) for xi in (-0.044, 0.0, 0.044))
    rgb = mixc(o["rgb"], SKIN * 0.55, 0.7 * grooves * front)
    knuckles = sum(g2(x - xi, y - 0.035, 0.014, 0.016) for xi in (-0.066, -0.022, 0.022, 0.066))
    o["rgb"] = mixc(rgb, FLUSH, 0.3 * knuckles * sstep(0.0, 0.04, z))
    return o

Part("hand", lambda U, V: ellipsoid(HAND, (0.092, 0.088, 0.08), U, V), 14, 9, hand_paint, W("hand_l"), form=hand_form,
    mirror=True, res=1.3)
THUMB = [(0, 0.292, 0.415, 0.02, 0.004, 0.004), (0.15, 0.284, 0.40, 0.03, 0.028, 0.028), (0.55, 0.272, 0.36, 0.062, 0.031, 0.03),
    (0.9, 0.288, 0.322, 0.082, 0.024, 0.024), (1.0, 0.294, 0.31, 0.086, 0.004, 0.004)]
Part("thumb", lambda U, V: tube(THUMB, U, V), 6, 6, skin_paint, W("hand_l"), mirror=True, res=1.0)

def leg_w(P, U, V):
    y = P[:, 1]
    k = sstep(0.23, 0.175, y)
    an = sstep(0.17, 0.13, y)
    return {"leg_l": 1.0 - k, "knee_l": k * (1.0 - an), "ankle_l": k * an}

LEG = [(0, 0.163, 0.36, 0.0, 0.09, 0.092), (0.55, 0.163, 0.20, 0.0, 0.083, 0.086), (0.85, 0.163, 0.13, 0.0, 0.07, 0.073),
    (1.0, 0.163, 0.09, 0.005, 0.066, 0.068)]
Part("leg", lambda U, V: tube(LEG, U, V), 10, 5, skin_paint, leg_w, mirror=True, res=0.7)
FOOT = [(0, 0.163, 0.088, -0.088, 0.004, 0.004), (0.1, 0.163, 0.09, -0.072, 0.056, 0.04), (0.32, 0.163, 0.093, -0.02, 0.072, 0.048),
    (0.62, 0.163, 0.086, 0.07, 0.083, 0.04), (0.86, 0.163, 0.076, 0.15, 0.084, 0.03), (0.96, 0.163, 0.07, 0.186, 0.062, 0.022),
    (1.0, 0.163, 0.068, 0.198, 0.004, 0.004)]
TOES = (-0.05, -0.018, 0.012, 0.04)

def foot_straps(P):
    z = P[..., 2]
    top = sstep(0.07, 0.085, P[..., 1])
    return np.maximum(np.maximum(g1(z - 0.10, 0.014), g1(z - 0.02, 0.016)) * top, g1(z + 0.065, 0.012) * sstep(0.08, 0.095, P[..., 1]))

def foot_form(U, V, P):
    x = P[..., 0] - 0.163
    toes = sum(g1(x - xi, 0.006) for xi in TOES) * sstep(0.135, 0.16, P[..., 2]) * sstep(0.06, 0.075, P[..., 1])
    return 0.007 * sstep(0.3, 0.7, foot_straps(P)) - 0.007 * toes

def foot_paint(c):
    o = skin_paint(c)
    x = c.x - 0.163
    toes = sum(g1(x - xi, 0.0045) for xi in TOES) * sstep(0.135, 0.16, c.z) * sstep(0.06, 0.075, c.y)
    rgb = mixc(o["rgb"], SKIN * 0.5, 0.8 * toes)
    rgb = mixc(rgb, DUST, 0.3 * sstep(0.09, 0.055, c.y))
    strap = sstep(0.35, 0.6, foot_straps(c.P))
    o["rgb"] = mixc(rgb, LEATHER * (0.8 + 0.4 * fbm(c.P * 30.0))[..., None], strap)
    o["skin"] = 1.0 - strap
    o["rough"] = 0.74 - 0.12 * strap
    return o

Part("foot", lambda U, V: tube(FOOT, U, V, hint=(0, 1, 0)), 10, 9, foot_paint, W("ankle_l"), form=foot_form, mirror=True, res=1.1)
SOLE = [(0, 0.163, 0.027, -0.106, 0.004, 0.004), (0.06, 0.163, 0.027, -0.097, 0.068, 0.021), (0.3, 0.163, 0.027, -0.03, 0.088, 0.022),
    (0.7, 0.163, 0.027, 0.10, 0.10, 0.022), (0.94, 0.163, 0.027, 0.19, 0.086, 0.021), (1.0, 0.163, 0.027, 0.209, 0.004, 0.004)]

def leather_paint(c, tone=1.0):
    rgb = np.ones(c.U.shape + (3,)) * LEATHER * tone * (0.8 + 0.4 * fbm(c.P * 26.0))[..., None]
    return out(rgb, h=0.0006 * fbm(c.P * 90.0), rough=0.6)

Part("sole", lambda U, V: tube(SOLE, U, V, hint=(0, 1, 0), e=4.0), 8, 6, lambda c: leather_paint(c, 0.7), W("ankle_l"), mirror=True, res=0.6)

# Sash: dyed, wound three times round the waist, knotted at the front
def tunic_ring(a, y, off):
    k = ip(TUNIC_Y, y)
    ex = 2.0 / TUNIC_E
    return np.stack([(k[..., 0] + off) * spow(np.sin(a), ex), y, (k[..., 1] + off) * spow(np.cos(a), ex)], -1)

# The builder and water carrier wear a dyed sash; the carpenter and overseer a leather belt
SASH_Y, SASH_H, SASH_OUT = (0.488, 0.118, 0.046) if SLOT in (0, 1, 4) else (0.515, 0.07, 0.03)

def sash_shape(U, V):
    a = TAU * U
    y = SASH_Y + SASH_H * V + 0.006 * np.sin(a * 2.0 + 1.0)
    return tunic_ring(a, y, -0.014 + SASH_OUT * np.sin(math.pi * np.clip(V, 0, 1)) ** 0.5)

def belt_paint(c):
    o = leather_paint(c, 0.85)
    o["rgb"] = o["rgb"] * (1.0 - 0.3 * sstep(0.75, 0.95, np.abs(np.cos(math.pi * c.V))))[..., None]
    return o

def sash_form(U, V, P):
    return 0.006 * np.cos(TAU * 3.0 * (V + 0.04 * np.sin(TAU * U * 2.0))) * np.sin(math.pi * V)

def sash_w(P, U, V):
    sk = sstep(0.60, 0.47, P[:, 1])
    return {"torso": 1.0 - sk, "skirt": sk}

if SLOT in (0, 1):
    Part("sash", sash_shape, 32, 5, dyed, sash_w, closed=True, form=sash_form, ref=(0, 0.55, 0), res=1.0)
    Part("sash_knot", lambda U, V: ellipsoid((0.105, 0.548, 0.272), (0.058, 0.05, 0.04), U, V), 8, 5, dyed, sash_w, res=0.8)
elif SLOT == 4:
    # A foe's sash: a band of red (or dun) cloth, knotted at the side
    def foe_sash(c):
        return out(cloth(c, np.array(FOE["sash"]), 1.0), h=threads(c), rough=0.9)
    Part("sash", sash_shape, 32, 5, foe_sash, sash_w, closed=True, form=sash_form, ref=(0, 0.55, 0), res=1.0)
    Part("sash_knot", lambda U, V: ellipsoid((-0.22, 0.548, 0.21), (0.05, 0.05, 0.04), U, V), 8, 5, foe_sash, sash_w, res=0.8)
else:
    Part("belt", sash_shape, 32, 3, belt_paint, sash_w, closed=True, ref=(0, 0.55, 0), res=1.0)

def sash_end(name, pts):
    keys = [(t, x, y, z, ra, 0.011) for t, x, y, z, ra in pts]
    def paint(c):
        o = dyed(c, sstep(0.008, 0.016, 0.024 - np.abs(c.V - 0.84)))
        fringe = sstep(0.93, 0.95, c.V) * (0.5 + 0.5 * np.sin(TAU * c.U * 14.0))
        o["rgb"] = o["rgb"] * (1.0 - 0.35 * fringe)[..., None]
        return o
    Part(name, lambda U, V: tube(keys, U, V, e=3.0), 6, 6, paint, sash_w,
        form=lambda U, V, P: 0.005 * np.sin(V * 8.0) * np.cos(TAU * U), res=0.9)

if SLOT == 0:
    sash_end("sash_end_a", [(0, 0.10, 0.535, 0.275, 0.022), (0.4, 0.085, 0.44, 0.292, 0.042), (0.97, 0.07, 0.315, 0.30, 0.05), (1.0, 0.07, 0.308, 0.30, 0.004)])
    sash_end("sash_end_b", [(0, 0.125, 0.535, 0.275, 0.022), (0.4, 0.158, 0.455, 0.288, 0.04), (0.97, 0.182, 0.365, 0.292, 0.046), (1.0, 0.183, 0.358, 0.292, 0.004)])
elif SLOT == 1:
    # The water carrier's hang long, down the front of the skirt: more of the crew colour
    # where the play camera sees it
    sash_end("sash_end_a", [(0, 0.10, 0.535, 0.275, 0.024), (0.35, 0.08, 0.42, 0.30, 0.046), (0.7, 0.062, 0.31, 0.318, 0.054),
        (0.97, 0.05, 0.22, 0.322, 0.054), (1.0, 0.05, 0.212, 0.322, 0.004)])
    sash_end("sash_end_b", [(0, 0.125, 0.535, 0.275, 0.022), (0.35, 0.16, 0.44, 0.295, 0.042), (0.7, 0.19, 0.345, 0.31, 0.05),
        (0.97, 0.205, 0.27, 0.31, 0.048), (1.0, 0.206, 0.262, 0.31, 0.004)])
# The basket's strap: over the left shoulder, across the chest to the right hip. The water
# carrier's goes the other way, over the right shoulder (the waterskin's neck rides there)
STRAP = [(0, 0.80, 150), (0.12, 0.92, 145), (0.22, 0.975, 125), (0.30, 0.998, 90), (0.40, 0.96, 45), (0.55, 0.86, 15),
    (0.70, 0.76, -20), (0.85, 0.67, -55), (1.0, 0.62, -100)]   # v, height, angle round the torso
if SLOT == 1:
    STRAP = [(v, y, -a) for v, y, a in STRAP]


def strap_centre(V):
    k = ip(STRAP, V)
    return tunic_ring(np.radians(k[..., 1]), k[..., 0], 0.02)


def strap_paint(c):
    o = leather_paint(c)
    edge = np.abs(np.cos(TAU * c.U))            # 1 at the strap's two edges
    o["rgb"] = o["rgb"] * (1.0 - 0.35 * sstep(0.7, 0.95, edge))[..., None]
    return o


def rope_paint(c):
    """Twisted hemp: the carpenter's planks are lashed on with it."""
    twist = 0.5 + 0.5 * np.sin(TAU * (c.V * 70.0 + c.U * 2.0))
    rgb = np.ones(c.U.shape + (3,)) * np.array([0.70, 0.58, 0.40]) * (0.7 + 0.35 * twist)[..., None]
    return out(rgb, h=0.0012 * twist, rough=0.9)

if SLOT in (0, 1) and not NPC:
    Part("strap", lambda U, V: ribbon(strap_centre, U, V, 0.036, 0.008, (0, 0.75, 0)), 8, 26, strap_paint, W("torso"), res=0.9)
if SLOT == 2 and not NPC:
    Part("strap", lambda U, V: ribbon(strap_centre, U, V, 0.022, 0.012, (0, 0.75, 0)), 6, 26, rope_paint, W("torso"), res=0.9)

# Basket on the back, stones in it
BASKET_Z = -0.44
BASKET = [(0.0, 0.47, 0.02, 0.02, 0, BASKET_Z), (0.06, 0.475, 0.22, 0.15, 0, BASKET_Z), (0.12, 0.50, 0.25, 0.172, 0, BASKET_Z),
    (0.55, 0.95, 0.325, 0.222, 0, BASKET_Z), (0.60, 0.995, 0.345, 0.238, 0, BASKET_Z), (0.64, 1.022, 0.33, 0.226, 0, BASKET_Z),
    (0.68, 1.0, 0.308, 0.208, 0, BASKET_Z), (0.76, 0.965, 0.30, 0.20, 0, BASKET_Z), (0.90, 1.0, 0.17, 0.115, 0, BASKET_Z),
    (1.0, 1.02, 0.01, 0.01, 0, BASKET_Z)]   # filled to just under the rim: the load heaped in the middle
STAKES, ROWS = 26.0, 13.0

def basket_weave(U, V):
    row = (V - 0.10) / 0.45 * ROWS
    wall = sstep(0.09, 0.12, V) * sstep(0.565, 0.545, V)
    weaver = 0.5 + 0.5 * np.cos(TAU * row)
    over = 0.5 + 0.5 * np.cos(TAU * U * STAKES + math.pi * np.floor(row + 0.5))
    rope = (0.5 + 0.5 * np.cos(TAU * U * 44.0 + (V - 0.62) * 90.0)) * sstep(0.565, 0.585, V) * sstep(0.70, 0.68, V)
    return (weaver * (0.45 + 0.55 * over)) * wall + rope, wall

def basket_paint(c):
    wv, wall = basket_weave(c.U, c.V)
    row = np.floor((c.V - 0.10) / 0.45 * ROWS + 0.5)
    tone = 0.85 + 0.3 * _hash(row, row * 0, row * 0 + 5)
    rgb = np.ones(c.U.shape + (3,)) * WICKER * np.where(wall > 0.5, tone, 1.0)[..., None]
    rgb = rgb * (0.42 + 0.68 * wv)[..., None]
    inner = sstep(0.69, 0.72, c.V)
    rgb = mixc(rgb, WICKER * 0.3, inner)
    rgb = mixc(rgb, WICKER * 0.5, sstep(0.10, 0.07, c.V))
    # The load: rubble and grit between the big stones
    load = sstep(0.75, 0.78, c.V)
    grit = fbm(c.P * 45.0)
    rubble = STONE * (0.45 + 0.5 * grit)[..., None]
    rubble = mixc(rubble, DUST * 0.8, 0.35 * fbm(c.P * 12.0))
    rgb = mixc(rgb, rubble, load)
    return out(rgb, h=0.004 * wv * (1.0 - inner) + 0.006 * grit * load, rough=0.7 + 0.2 * load)

if SLOT == 0:
    Part("basket", lambda U, V: lathe(BASKET, U, V, linear=True), 24, 14, basket_paint, W("torso"), res=1.0)

def stone(name, c0, r, seed, first):
    """A rough-hewn block: few faces, flat shaded, so it reads as broken stone."""
    def form(U, V, P):
        return 0.5 * r * (vnoise(P * (1.6 / r) + seed) - 0.5) + 0.22 * r * (vnoise(P * (3.4 / r) + seed) - 0.5)
    def paint(c):
        n = fbm(c.P * 22.0 + seed)
        rgb = np.ones(c.U.shape + (3,)) * STONE * (0.86 + 0.3 * n)[..., None]
        rgb = mixc(rgb, DUST, 0.3 * fbm(c.P * 9.0))
        return out(rgb, h=0.0015 * fbm(c.P * 60.0), rough=0.92)
    p = Part(name, lambda U, V: ellipsoid(c0, (r, r * 0.78, r * 0.92), U, V), 6, 4, paint, W("torso"), form=form, res=0.8, rect_of=first)
    p.flat = True
    return p

# Heaped: bedded in the rubble, shoulder to shoulder, one on top
_first = None
if SLOT == 0:
    for i, (c0, r) in enumerate([((-0.17, 1.0, -0.475), 0.095), ((-0.01, 1.025, -0.505), 0.10), ((0.15, 1.0, -0.485), 0.095),
            ((-0.20, 0.995, -0.375), 0.08), ((-0.07, 1.02, -0.385), 0.10), ((0.085, 1.03, -0.40), 0.095), ((0.21, 0.99, -0.39), 0.08),
            ((0.02, 1.085, -0.445), 0.09)]):
        p = stone("stone%d" % i, c0, r, i * 7.1, _first)
        _first = _first or p

# The water carrier's goatskin, slung across his back: the whole hide sewn shut, full and
# sagging low, its neck up over his right shoulder tied off with cord, the legs tied in stubs
GOAT = np.array([0.40, 0.25, 0.14])
SKIN_BAG = [(0.00, 0.30, 0.50, -0.43, 0.012, 0.012), (0.08, 0.275, 0.53, -0.435, 0.16, 0.13),
    (0.28, 0.17, 0.64, -0.46, 0.27, 0.235), (0.50, 0.06, 0.77, -0.455, 0.25, 0.215),
    (0.74, -0.06, 0.91, -0.43, 0.18, 0.16), (0.92, -0.15, 1.01, -0.40, 0.10, 0.09), (1.0, -0.165, 1.035, -0.39, 0.07, 0.065)]
SKIN_NECK = [(0, -0.15, 1.01, -0.40, 0.075, 0.07), (0.35, -0.22, 1.05, -0.32, 0.052, 0.05),
    (0.7, -0.27, 1.04, -0.20, 0.046, 0.044), (0.95, -0.285, 1.02, -0.11, 0.04, 0.038), (1.0, -0.286, 1.018, -0.10, 0.004, 0.004)]

def goat_paint(c, wet=0.0, cord=None):
    wet = wet + np.zeros(c.U.shape)
    n = fbm(c.P * 18.0)
    rgb = np.ones(c.U.shape + (3,)) * GOAT * (0.8 + 0.4 * n)[..., None]
    span = max(float(np.abs(c.f).max()), 1e-4)
    rgb = rgb * (1.0 + 0.35 * np.clip(c.f / span, -1.0, 1.0))[..., None]
    rgb = rgb * (1.0 - 0.25 * wet)[..., None]                      # darker where it's damp
    rough = 0.62 - 0.25 * wet
    if cord is not None:
        rgb = mixc(rgb, LINEN * 0.75 * (0.85 + 0.3 * np.sin(TAU * (c.U * 3.0 + c.V * 30.0)))[..., None], cord)
        rough = rough + 0.25 * cord
    return out(rgb, h=0.0008 * fbm(c.P * 70.0), rough=rough)

def bag_form(U, V, P):
    a = TAU * U
    sag = 0.03 * sstep(0.5, 0.15, V) * np.sin(a) ** 2               # full at the bottom
    creases = 0.008 * np.sin(a * 5.0 + V * 22.0 + 2.0 * vnoise(P * 6.0)) * sstep(0.55, 0.85, V)
    return sag + creases

def bag_paint(c):
    o = goat_paint(c, wet=sstep(0.35, 0.05, c.V) * (0.6 + 0.4 * fbm(c.P * 7.0)))
    # The seam along its edges, stitched with sinew
    edge = np.abs(np.cos(TAU * c.U))
    seam = sstep(0.985, 0.998, edge) * sstep(0.0, 0.2, np.cos(TAU * c.U)) * sstep(0.04, 0.1, c.V) * sstep(0.96, 0.9, c.V)
    stitch = seam * sstep(0.2, 0.6, np.sin(TAU * c.V * 34.0))
    o["rgb"] = mixc(o["rgb"] * (1.0 - 0.2 * seam)[..., None], DUST * 0.9, 0.5 * stitch)
    # Worn pale where it rubs, darker in the hollows the load pulls
    o["rgb"] = mixc(o["rgb"], GOAT * 1.5, 0.35 * sstep(0.55, 0.85, fbm(c.P * 6.0 + 4.0)))
    return o

def neck_paint(c):
    cord = np.maximum(sstep(0.04, 0.025, np.abs(c.V - 0.62)), sstep(0.03, 0.018, np.abs(c.V - 0.74)))
    return goat_paint(c, wet=sstep(0.85, 1.0, c.V), cord=cord)

def leg_stub(name, pts, first):
    keys = [(t, x, y, z, r, r * 0.9) for t, x, y, z, r in pts]
    def paint(c):
        return goat_paint(c, cord=sstep(0.06, 0.04, np.abs(c.V - 0.55)))
    return Part(name, lambda U, V: tube(keys, U, V), 6, 5, paint, W("torso"), res=0.9, rect_of=first)

if SLOT == 1 and not NPC.get("nopack"):
    Part("waterskin", lambda U, V: tube(SKIN_BAG, U, V), 18, 14, bag_paint, W("torso"), form=bag_form, res=1.0)
    Part("waterskin_neck", lambda U, V: tube(SKIN_NECK, U, V), 8, 6, neck_paint, W("torso"),
        form=lambda U, V, P: 0.004 * np.sin(V * 18.0) * np.cos(TAU * U * 2.0), res=1.2)
    _s = leg_stub("skin_leg_a", [(0, 0.28, 0.53, -0.44, 0.048), (0.6, 0.36, 0.47, -0.45, 0.038), (1.0, 0.385, 0.45, -0.45, 0.006)], None)
    leg_stub("skin_leg_b", [(0, 0.22, 0.86, -0.46, 0.045), (0.6, 0.30, 0.92, -0.47, 0.036), (1.0, 0.325, 0.94, -0.47, 0.006)], _s)

def tunic_front_z(x, y, off=0.0):
    k = ip(TUNIC_Y, y)
    rx, rz = k[..., 0] + off, k[..., 1] + off
    t = np.clip(np.abs(x) / rx, 0.0, 0.999)
    return rz * (1.0 - t ** TUNIC_E) ** (1.0 / TUNIC_E)

# The carpenter's leather apron: from the belt to the knee, a pocket with his tools in it
def apron_shape(U, V):
    y = 0.53 - 0.33 * V
    half = 0.17 + 0.04 * V
    x = (2.0 * U - 1.0) * half
    z = tunic_front_z(x * 0.9, y, 0.012) + 0.012 + 0.02 * V
    return np.stack([x, y, z], -1)

def apron_form(U, V, P):
    return 0.004 * np.sin(U * 9.0 + V * 3.0) * sstep(0.2, 0.8, V)

def apron_paint(c):
    rgb = np.ones(c.U.shape + (3,)) * APRON * (0.82 + 0.3 * fbm(c.P * 20.0))[..., None]
    rgb = mixc(rgb, APRON * 0.6, 0.5 * fbm(c.P * 6.0 + 3.0) * sstep(0.3, 1.0, c.V))       # worn dark
    edge = np.maximum(sstep(0.05, 0.0, c.U) + sstep(0.95, 1.0, c.U), sstep(0.96, 1.0, c.V))
    rgb = rgb * (1.0 - 0.3 * np.clip(edge, 0, 1))[..., None]
    # The pocket: a patch sewn on, its stitches pale
    px, py = (c.U - 0.68) / 0.2, (c.V - 0.5) / 0.22
    patch = sstep(1.0, 0.95, np.maximum(np.abs(px), np.abs(py)))
    seam = patch * sstep(0.85, 0.9, np.maximum(np.abs(px), np.abs(py))) * sstep(0.2, 0.6, np.sin(TAU * (c.U + c.V) * 40.0))
    rgb = rgb * (1.0 - 0.15 * patch * sstep(0.9, 0.6, py + 1.0))[..., None]
    rgb = mixc(rgb, DUST, 0.7 * seam)
    return out(rgb, h=0.0008 * fbm(c.P * 60.0) + 0.002 * patch, rough=0.6)

def handle(name, pts, colour, first=None):
    keys = [(t, x, y, z, r, r) for t, x, y, z, r in pts]
    def paint(c):
        rgb = np.ones(c.U.shape + (3,)) * colour * (0.85 + 0.3 * fbm(c.P * np.array([20.0, 80.0, 20.0])))[..., None]
        return out(rgb, h=0.0005 * fbm(c.P * 90.0), rough=0.6)
    return Part(name, lambda U, V: tube(keys, U, V), 6, 4, paint, W("skirt"), res=1.0, rect_of=first)

# Planks: three boards lashed in a bundle, slung corner to corner across his back
PLANK_A, PLANK_B = np.array([0.46, 0.50]), np.array([-0.40, 1.14])

def plank(name, dz, shift, length_trim, first):
    d = PLANK_B - PLANK_A
    n = np.array([-d[1], d[0]]) / np.linalg.norm(d)
    a = PLANK_A + n * shift + d * length_trim
    b = PLANK_B + n * shift - d * length_trim * 0.5
    z = -0.32 - dz
    u = (b - a) / np.linalg.norm(b - a)
    a0, b0 = a - u * 0.006, b + u * 0.006
    keys = [(0.0, a0[0], a0[1], z, 0.066, 0.011), (0.006, a[0], a[1], z, 0.09, 0.018), (0.5, (a[0] + b[0]) / 2, (a[1] + b[1]) / 2, z, 0.09, 0.018),
        (0.994, b[0], b[1], z, 0.09, 0.018), (1.0, b0[0], b0[1], z, 0.066, 0.011)]   # square-sawn ends, the arrises eased
    def paint(c):
        grain = fbm(np.stack([c.U * 6.0, c.V * 1.5, c.U * 0.0 + dz * 40.0], -1) * np.array([1.0, 1.0, 1.0]) * 3.0)
        rings = 0.5 + 0.5 * np.sin(TAU * (c.U * 3.0 + 2.0 * grain))
        rgb = np.ones(c.U.shape + (3,)) * WOOD * (0.78 + 0.25 * rings + 0.1 * grain)[..., None]
        ends = np.maximum(sstep(0.03, 0.0, c.V), sstep(0.97, 1.0, c.V))
        rgb = mixc(rgb, WOOD * 0.62, ends)
        lash = np.maximum(g1(c.V - 0.3, 0.018), g1(c.V - 0.72, 0.018))
        rgb = mixc(rgb, np.array([0.70, 0.58, 0.40]) * (0.75 + 0.3 * np.sin(TAU * c.U * 8.0 + c.V * 300.0))[..., None], sstep(0.4, 0.6, lash))
        return out(rgb, h=0.0008 * rings + 0.003 * lash, rough=0.75)
    p = Part(name, lambda U, V: tube(keys, U, V, hint=(0, 0, 1), e=8.0), 8, 6, paint, W("torso"), res=0.9, rect_of=first)
    return p

if SLOT == 2 and not NPC:
    Part("apron", apron_shape, 8, 8, apron_paint, lambda P, U, V: {"torso": 1.0 - sstep(0.50, 0.42, P[:, 1]), "skirt": sstep(0.50, 0.42, P[:, 1])},
        closed=False, form=apron_form, ref=(0, 0.4, 0), res=1.0)
    # A mallet's handle and a chisel's out of the pocket, a rule by them
    _h = handle("tool_a", [(0, 0.075, 0.37, 0.31, 0.016), (0.6, 0.085, 0.47, 0.322, 0.017), (1.0, 0.09, 0.52, 0.325, 0.02)], WOOD * 0.85)
    handle("tool_b", [(0, 0.125, 0.37, 0.31, 0.013), (0.7, 0.14, 0.455, 0.322, 0.014), (1.0, 0.145, 0.48, 0.324, 0.016)], WOOD * 0.6, _h)
    _p = plank("plank_a", 0.0, 0.0, 0.0, None)
    plank("plank_b", 0.034, 0.05, 0.03, _p)
    plank("plank_c", 0.068, -0.04, 0.06, _p)

# The overseer's open vest, dyed, over his robe from the shoulders to below the knee, open
# down the front so the robe shows; a scroll tucked in his belt
def vest_open(y):
    return np.radians(17.0 + 12.0 * sstep(0.62, 0.3, y))

def vest_shape(U, V):
    y = 0.97 - 0.66 * V
    a0 = vest_open(y)
    a = a0 + (TAU - 2.0 * a0) * U
    off = 0.016 + 0.014 * sstep(0.5, 0.3, y)
    return tunic_ring(a, y, off)

def vest_paint(c):
    o = dyed(c)
    edge = np.maximum(sstep(0.04, 0.0, c.U) + sstep(0.96, 1.0, c.U), sstep(0.97, 1.0, c.V))
    o["rgb"] = mixc(o["rgb"], o["rgb"] * 0.62, np.clip(edge, 0, 1))         # a deeper dyed edging
    return o

def scroll_paint(c):
    paper = np.array([0.88, 0.80, 0.60]) * (0.88 + 0.2 * fbm(c.P * 30.0))[..., None]
    rgb = np.ones(c.U.shape + (3,)) * paper
    tie = np.maximum(g1(c.V - 0.3, 0.025), g1(c.V - 0.7, 0.025))
    rgb = mixc(rgb, LEATHER * 0.8, sstep(0.4, 0.6, tie))
    ends = np.maximum(sstep(0.04, 0.0, c.V), sstep(0.96, 1.0, c.V))
    rgb = mixc(rgb, paper * 0.75 * (0.8 + 0.4 * np.sin(TAU * c.U * 3.0))[..., None], ends)
    return out(rgb, h=0.002 * tie, rough=0.8)

if SLOT == 3 and (NPC.get("vest") or not NPC):
    Part("vest", vest_shape, 30, 14, vest_paint, tunic_w, closed=False, form=lambda U, V, P: 0.6 * tunic_form(U, V, P),
        ref=(0, 0.6, 0), res=1.0)
if SLOT == 3 and (NPC.get("scroll") or not NPC):
    SCROLL = [(0, 0.10, 0.44, 0.285, 0.004, 0.004), (0.02, 0.105, 0.445, 0.285, 0.05, 0.05), (0.98, 0.255, 0.70, 0.27, 0.05, 0.05),
        (1.0, 0.26, 0.705, 0.27, 0.004, 0.004)]
    Part("scroll", lambda U, V: tube(SCROLL, U, V), 10, 6, scroll_paint, W("torso"), res=1.0)

# A hood of dark goat hair over the head and down onto the shoulders, open round the face; a
# lining so its inside shows dark where the opening lets it be seen
HOOD_T = 0.10

def hood_open(y):
    return np.radians(62.0) * sstep(1.50, 1.42, y)          # the face opening, below the brow

def hood_shape(U, V, inset=0.0, v0=0.0):
    top = HC[1] + HRY + HOOD_T
    V = v0 + (1.0 - v0) * V                 # the lining starts below the crown: no second pole
    y = top - (top - 0.97) * np.clip(V, 0, 1) ** 1.15
    a0 = hood_open(y)
    a = a0 + (TAU - 2.0 * a0) * U
    yy = np.maximum(y, 1.10)
    f = (1.0 - np.clip(np.abs((yy - HC[1]) / (HRY + HOOD_T)), 0.0, 1.0) ** HE) ** (1.0 / HE)
    r = ell_r(a, HRX + HOOD_T, HRZ + HOOD_T) * f
    drape = sstep(1.14, 0.97, y)
    r = r + 0.20 * drape - inset + 0.03 * drape * (np.cos(a) < 0)
    return polar(a, y, r) + np.array([0.0, 0.0, -0.01])

def hood_form(U, V, P):
    a = np.arctan2(P[..., 0], P[..., 2])
    return 0.016 * np.sin(a * 7.0 + 1.5 * vnoise(P * 4.0)) * sstep(1.25, 1.02, P[..., 1]) + 0.006 * np.sin(a * 11.0) * sstep(1.55, 1.75, P[..., 1])

def hood_paint(c):
    rgb = cloth(c, np.array(FOE["hood"]), 1.0)
    edge = (sstep(0.025, 0.0, c.U) + sstep(0.975, 1.0, c.U)) * sstep(1.52, 1.44, c.y)
    rgb = mixc(rgb, rgb * 0.62, np.clip(edge, 0, 1))                      # the rolled edge round the face
    rgb = mixc(rgb, rgb * 0.75, sstep(0.94, 1.0, c.V))
    return out(rgb, h=threads(c, 0.008, 1.4), rough=0.94)

def hood_w(P, U, V):
    t = sstep(1.10, 1.0, P[:, 1])
    return {"head": 1.0 - t, "torso": t}

# A pointed bronze helmet (the Assyrian and Persian kind the hill peoples copied): a rolled rim,
# a rib up each side, a nose bar, a horsehair crest streaming back, a leather curtain at the nape
HELM = [(0.0, 1.43, 0.405, 0.385), (0.05, 1.45, 0.415, 0.395), (0.12, 1.49, 0.40, 0.38), (0.4, 1.66, 0.345, 0.325),
    (0.65, 1.82, 0.235, 0.22), (0.85, 1.93, 0.115, 0.108), (0.96, 1.985, 0.035, 0.035), (1.0, 1.995, 0.003, 0.003)]

def helm_shape(U, V):
    P = lathe(HELM, U, V)
    return P + np.stack([0 * P[..., 0], 0.13 * P[..., 2] * (1.0 - sstep(0.0, 0.5, V)), 0 * P[..., 0]], -1)

def helm_form(U, V, P):
    a = TAU * U
    rim = 0.016 * sstep(0.0, 0.025, V) * sstep(0.09, 0.05, V)
    ribs = 0.009 * g1(np.abs(np.sin(a)) - 1.0, 0.004) * sstep(0.1, 0.2, V)
    return rim + ribs + 0.0015 * (vnoise(P * 60.0) - 0.5)

def bronze(c, base, polish=1.0):
    n = fbm(c.P * 25.0)
    rgb = np.ones(c.U.shape + (3,)) * base * (0.82 + 0.35 * n)[..., None]
    rgb = mixc(rgb, np.array([0.30, 0.38, 0.30]), 0.25 * sstep(0.55, 0.8, fbm(c.P * 9.0 + 2.0)))   # patina
    return out(rgb, h=0.0015 * (vnoise(c.P * 60.0) - 0.5), rough=0.34 + 0.25 * n * polish)

def helm_paint(c):
    o = bronze(c, np.array(FOE["helmet"]))
    o["rgb"] = o["rgb"] * (1.0 - 0.25 * sstep(0.06, 0.09, c.V) * sstep(0.12, 0.09, c.V))[..., None]
    return o

CREST = np.array([0.62, 0.14, 0.10])
CREST_KEYS = [(0, 0.0, 1.99, 0.03, 0.03, 0.03), (0.2, 0.0, 2.05, -0.06, 0.045, 0.10), (0.5, 0.0, 2.02, -0.24, 0.05, 0.11),
    (0.8, 0.0, 1.90, -0.40, 0.042, 0.085), (1.0, 0.0, 1.76, -0.50, 0.01, 0.01)]

def crest_paint(c):
    strands = 0.5 + 0.5 * np.sin(TAU * c.U * 9.0 + 3.0 * fbm(c.P * 20.0))
    rgb = np.ones(c.U.shape + (3,)) * CREST * (0.7 + 0.45 * strands)[..., None]
    return out(rgb, h=0.001 * strands, rough=0.7)

def curtain_shape(U, V):
    deg = 95.0 + 170.0 * U
    a = np.radians(deg)
    y = 1.40 + 0.05 * np.cos(a) - 0.33 * V
    r = ell_r(a, HRX, HRZ) * 0.92 + 0.07 + 0.09 * V
    return polar(a, y, r)

def curtain_paint(c):
    o = leather_paint(c, 0.75)
    o["rgb"] = o["rgb"] * (1.0 - 0.3 * sstep(0.92, 1.0, c.V))[..., None]
    return o

# A corselet of small bronze-and-leather scales, row on row, over the tunic
def corselet_shape(U, V):
    y = 0.985 - 0.47 * V
    return tunic_ring(TAU * U, y, 0.022 + 0.01 * sstep(0.8, 1.0, V) - 0.04 * sstep(0.08, 0.0, V))

def scales(c):
    row = (0.985 - c.y) / 0.034
    r = np.floor(row)
    a = np.arctan2(c.x, c.z)
    u = a / TAU * 46.0 + 0.5 * (r % 2)
    fu, fr = u - np.floor(u), row - r
    # each scale rounded at its foot, lying over the one below: high at its foot, low at its head
    shape = np.clip(1.0 - ((fu - 0.5) / 0.5) ** 2 - (sstep(0.5, 1.0, fr) ** 2), 0.0, 1.0)
    return shape * (0.4 + 0.6 * fr), r

def corselet_paint(c):
    sh, r = scales(c)
    base = np.array(FOE["armour"])
    glint = 0.85 + 0.3 * _hash(r, np.floor(np.arctan2(c.x, c.z) / TAU * 46.0 + 0.5 * (r % 2)), r * 0 + 2)
    rgb = np.ones(c.U.shape + (3,)) * base * glint[..., None] * (0.55 + 0.6 * sh)[..., None]
    edge = np.maximum(sstep(0.06, 0.0, c.V), sstep(0.94, 1.0, c.V))
    rgb = mixc(rgb, LEATHER * 0.6, edge)
    return out(rgb, h=0.004 * sh, rough=0.45 + 0.3 * (1.0 - sh))

# A round shield of hide on a wicker frame on his left side: a dished face, a laced rim, a
# bronze boss in a ring of rivets, a pale band painted round it
SH_C = np.array([0.535, 0.64, 0.11])
SH_N = np.array([1.0, 0.0, 0.62]) / np.linalg.norm([1.0, 0.0, 0.62])
SH_R = 0.30

def shield_frame():
    up = np.array([0.0, 1.0, 0.0])
    side = np.cross(up, SH_N)
    return up, side / np.linalg.norm(side)

def shield_shape(U, V):
    up, side = shield_frame()
    a = TAU * U
    lat = (V - 0.5) * math.pi
    d = np.cos(lat)
    face = np.sin(lat)                                   # +1 the outer face, -1 the inner
    depth = np.where(face > 0, 0.07 * np.abs(face) ** 0.6, 0.03 * face)
    P = SH_C + (SH_R * d * np.cos(a))[..., None] * side + (SH_R * d * np.sin(a))[..., None] * up + depth[..., None] * SH_N
    return P

def shield_paint(c):
    up, side = shield_frame()
    q = c.P - SH_C
    out_ = np.sum(q * SH_N, -1)
    d = np.linalg.norm(q - out_[..., None] * SH_N, axis=-1) / SH_R
    ang = np.arctan2(np.sum(q * up, -1), np.sum(q * side, -1))
    face = sstep(-0.005, 0.01, out_)
    rgb = np.ones(c.U.shape + (3,)) * np.array(FOE["shield"]) * (0.8 + 0.3 * fbm(c.P * 18.0))[..., None]
    rgb = mixc(rgb, np.array([0.86, 0.78, 0.60]), sstep(0.66, 0.69, d) * sstep(0.80, 0.77, d))     # the pale band
    rgb = mixc(rgb, LEATHER * 0.7, sstep(0.9, 0.93, d))                                            # laced rim
    lace = sstep(0.93, 0.97, d) * sstep(0.3, 0.7, np.sin(ang * 24.0))
    rgb = mixc(rgb, LEATHER * 0.45, lace)
    rivet = sstep(0.05, 0.02, np.hypot(d - 0.52, (np.mod(ang * 8.0 / TAU, 1.0) - 0.5) * 0.4))
    boss = sstep(0.2, 0.17, d)
    rgb = mixc(rgb, np.array([0.70, 0.55, 0.30]), np.maximum(rivet, boss))
    back = np.ones(c.U.shape + (3,)) * WICKER * 0.6 * (0.7 + 0.5 * (0.5 + 0.5 * np.sin(ang * 30.0)))[..., None]
    rgb = mixc(back, rgb, face)
    return out(rgb, h=0.003 * boss * face + 0.0015 * lace, rough=0.75 - 0.4 * np.maximum(rivet, boss))

# A cloak from the shoulders to the calf, on the rig's cape pivot: it streams behind a run
def cape_shape(U, V, inset=0.0):
    y = 0.99 - 0.66 * V
    spread = 62.0 - 8.0 * V
    a = np.radians(180.0 - spread + 2.0 * spread * U)
    off = 0.035 + 0.11 * V ** 1.2 - inset
    return tunic_ring(a, y, off) + np.stack([0.0 * V, 0.0 * V, -0.02 - 0.03 * V], -1)

def cape_form(U, V, P):
    return 0.018 * np.sin(U * TAU * 3.0 + 0.6 * vnoise(P * 4.0)) * sstep(0.1, 0.5, V)

def cape_paint(c, lining=False):
    base = np.array(FOE["cape"]) * (0.55 if lining else 1.0)
    rgb = cloth(c, base, 1.0)
    rgb = mixc(rgb, rgb * 0.7, sstep(0.95, 1.0, c.V))
    return out(rgb, h=threads(c, 0.008), rough=0.92)

def cape_w(P, U, V):
    t = sstep(0.96, 0.86, P[:, 1])
    return {"torso": 1.0 - t, "cape": t}

# An empty sack slung on his back: he's not here to fight
SACK_C = np.array([0.02, 0.66, -0.42])

def sack_form(U, V, P):
    return 0.012 * np.sin(U * TAU * 5.0 + V * 7.0 + 2.0 * vnoise(P * 5.0)) + 0.02 * sstep(0.5, 0.0, V)

def sack_paint(c):
    weave = (0.5 + 0.5 * np.sin(c.P[..., 0] * 900.0)) * (0.5 + 0.5 * np.sin(c.P[..., 1] * 900.0))
    rgb = np.ones(c.U.shape + (3,)) * np.array(FOE["sack"]) * (0.75 + 0.3 * fbm(c.P * 12.0) + 0.1 * weave)[..., None]
    span = max(float(np.abs(c.f).max()), 1e-4)
    rgb = rgb * (1.0 + 0.3 * np.clip(c.f / span, -1.0, 1.0))[..., None]
    return out(rgb, h=0.0008 * weave, rough=0.95)

if SLOT == 4:
    if "hood" in FOE:
        Part("hood", hood_shape, 44, 20, hood_paint, hood_w, closed=False, form=hood_form, ref=HC, res=1.0)
        Part("hood_lining", lambda U, V: hood_shape(U, V, 0.012, 0.35), 30, 10,
            lambda c: out(cloth(c, np.array(FOE["hood"]) * 0.5, 0.5), rough=0.95), hood_w, closed=False,
            ref=HC + np.array([0.0, 0.0, 3.0]), res=0.4)
    if "helmet" in FOE:
        Part("helmet", helm_shape, 28, 12, helm_paint, W("head"), form=helm_form, res=1.0)
        Part("crest", lambda U, V: tube(CREST_KEYS, U, V, side=(1.0, 0.0, 0.0)), 8, 10, crest_paint, W("head"), res=0.9)
        Part("nosebar", lambda U, V: tube([(0, 0.0, 1.47, 0.39, 0.02, 0.012), (0.5, 0.0, 1.38, 0.425, 0.022, 0.012),
            (1.0, 0.0, 1.31, 0.43, 0.018, 0.01)], U, V, side=(1.0, 0.0, 0.0)), 6, 4, lambda c: bronze(c, np.array(FOE["helmet"]) * 0.85),
            W("head"), res=0.9)
        Part("curtain", curtain_shape, 16, 5, curtain_paint, W("head"), closed=False, ref=HC, res=0.8)
    if "armour" in FOE:
        Part("corselet", corselet_shape, 40, 14, corselet_paint, tunic_w, ref=(0, 0.75, 0), res=1.2)
    if "shield" in FOE:
        Part("shield", shield_shape, 24, 10, shield_paint, W("torso"), ref=SH_C, res=1.1)
    if "cape" in FOE:
        Part("cape", cape_shape, 14, 12, cape_paint, cape_w, closed=False, form=cape_form, ref=(0, 0.7, 0), res=0.9)
        Part("cape_lining", lambda U, V: cape_shape(U, V, 0.01), 14, 12, lambda c: cape_paint(c, True), cape_w, closed=False,
            form=cape_form, ref=(0, 0.7, -3.0), res=0.4)
    if "sack" in FOE:
        Part("sack", lambda U, V: ellipsoid(SACK_C, (0.23, 0.27, 0.14), U, V), 14, 10, sack_paint, W("torso"), form=sack_form, res=0.9)
        Part("sack_neck", lambda U, V: tube([(0, 0.02, 0.90, -0.42, 0.07, 0.05), (0.5, 0.05, 0.97, -0.41, 0.045, 0.04),
            (1.0, 0.09, 1.0, -0.40, 0.03, 0.03)], U, V), 6, 4, sack_paint, W("torso"), res=0.9)
        Part("strap", lambda U, V: ribbon(strap_centre, U, V, 0.022, 0.012, (0, 0.75, 0)), 6, 26, rope_paint, W("torso"), res=0.9)

# ── Atlas ────────────────────────────────────────────────────────────────────
def pack(parts):
    """Shelf-pack one rectangle per part (those that don't borrow another's) into the atlas:
    the densest texel size that fits."""
    own = [p for p in parts if p.rect_of is None]
    def sizes(d):
        out_ = []
        for p in own:
            w = int(min(max(p.Lu * d * p.res, 12), 480)) + 2 * PAD
            h = int(min(max(p.Lv * d * p.res, 12), 480)) + 2 * PAD
            out_.append((p, w, h))
        return sorted(out_, key=lambda s: -s[2])
    def place(d):
        x = y = shelf = 0
        rects = {}
        for p, w, h in sizes(d):
            if x + w > TEX:
                x, y, shelf = 0, y + shelf, 0
            if y + h > TEX:
                return None
            rects[p] = (x, y, w, h)
            x += w
            shelf = max(shelf, h)
        return rects
    lo, hi = 50.0, 4000.0
    best = None
    for _ in range(24):
        mid = (lo + hi) / 2
        r = place(mid)
        if r is None:
            hi = mid
        else:
            best, lo = r, mid
    for p, r in best.items():
        p.rect = r
    for p in parts:
        if p.rect_of is not None:
            p.rect = p.rect_of.rect
    print("atlas: %.0f px per metre" % lo)

def paint_atlas(parts):
    albedo = np.full((TEX, TEX, 4), 0.5)
    albedo[..., 3] = 1.0
    normal = np.zeros((TEX, TEX, 3))
    normal[..., :] = (0.5, 0.5, 1.0)
    aux = np.zeros((TEX, TEX, 3))
    aux[..., 0] = 1.0
    aux[..., 1] = 0.85
    for p in parts:
        if p.rect_of is not None:
            continue
        x0, y0, w, h = p.rect
        u = (np.arange(w) + 0.5 - PAD) / (w - 2 * PAD)
        v = (np.arange(h) + 0.5 - PAD) / (h - 2 * PAD)
        if not p.closed:
            u = np.clip(u, 0.0, 1.0)
        v = np.clip(v, 0.0, 1.0)
        U, V = np.meshgrid(u, v)
        c = Ctx()
        c.U, c.V = U, V
        c.P, c.f = p.surface(U, V)
        c.x, c.y, c.z = c.P[..., 0], c.P[..., 1], c.P[..., 2]
        c.su, c.sv = U * p.Lu, V * p.Lv
        c.mu, c.mv = p.Lu / (w - 2 * PAD), p.Lv / (h - 2 * PAD)
        o = p.paint(c)
        albedo[y0:y0 + h, x0:x0 + w, :3] = np.clip(o["rgb"], 0.0, 1.0)
        if TINT_SKIN and "skin" in o:
            albedo[y0:y0 + h, x0:x0 + w, 3] = 1.0 - np.clip(o["skin"] + np.zeros(U.shape), 0.0, 1.0)
        aux[y0:y0 + h, x0:x0 + w, 1] = o["rough"]
        aux[y0:y0 + h, x0:x0 + w, 2] = o["dye"]
        if o["h"] is not None:
            hh = o["h"] + np.zeros(U.shape)
            su = np.maximum(np.linalg.norm(np.gradient(c.P, axis=1), axis=-1), c.mu * 0.25)
            sv = np.maximum(np.linalg.norm(np.gradient(c.P, axis=0), axis=-1), c.mv * 0.25)
            n = unit(np.stack([-np.gradient(hh, axis=1) / su, -np.gradient(hh, axis=0) / sv, np.ones(U.shape)], -1))
            normal[y0:y0 + h, x0:x0 + w] = n * 0.5 + 0.5
    return albedo, normal, aux

# ── Blender ──────────────────────────────────────────────────────────────────
def g2b(P):
    """Godot (y up, +z front) -> Blender (z up, -y front); the glTF export maps it back."""
    return np.stack([P[..., 0], -P[..., 2], P[..., 1]], -1)

def select_only(obs, active=None):
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active or obs[0]

def build_mesh(p, mirrored):
    nu, nv = p.nu, p.nv
    P = p.P.copy()
    U, V = p.U, p.V
    cols = nu if p.closed else nu + 1
    P = P[:, :cols]
    flat = P.reshape(-1, 3)
    weights = p.weights(flat, U[:, :cols].reshape(-1), V[:, :cols].reshape(-1))
    if mirrored:
        flat = flat * np.array([-1.0, 1.0, 1.0])
        weights = {(k[:-2] + "_r" if k.endswith("_l") else k): w for k, w in weights.items()}
    x0, y0, w, h = p.rect
    faces, uvs = [], []
    keep = (p.sign > 0) != mirrored
    for i in range(nv):
        for j in range(nu):
            j1 = (j + 1) % nu if p.closed else j + 1
            quad = [(i, j, j), (i, j1, j + 1), (i + 1, j1, j + 1), (i + 1, j, j)]
            if not keep:
                quad.reverse()
            faces.append([a * cols + b for a, b, _ in quad])
            uvs.append([((x0 + PAD + (c / nu) * (w - 2 * PAD)) / TEX, (y0 + PAD + (a / nv) * (h - 2 * PAD)) / TEX) for a, _, c in quad])
    me = bpy.data.meshes.new(p.name)
    me.from_pydata([tuple(v) for v in g2b(flat)], [], faces)
    me.update()
    uv = me.uv_layers.new(name="UVMap")
    for poly, quv in zip(me.polygons, uvs):
        for li, t in zip(poly.loop_indices, quv):
            uv.data[li].uv = t
        poly.use_smooth = not getattr(p, "flat", False)
    ob = bpy.data.objects.new(p.name + ("_r" if mirrored else ""), me)
    bpy.context.scene.collection.objects.link(ob)
    for bone, wts in weights.items():
        vg = ob.vertex_groups.new(name=bone)
        for vi, wt in enumerate(wts):
            if wt > 1e-3:
                vg.add([vi], float(wt), "REPLACE")
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-6)
    bm.to_mesh(me)
    bm.free()
    return ob

def build_armature(bones):
    arm = bpy.data.armatures.new("Rig")
    ob = bpy.data.objects.new("Rig", arm)
    bpy.context.scene.collection.objects.link(ob)
    select_only([ob])
    bpy.ops.object.mode_set(mode="EDIT")
    made = {}
    for b in bones:
        eb = arm.edit_bones.new(b["name"])
        o = b["origin"]
        eb.head = (o[0], -o[2], o[1])
        eb.tail = (o[0], -o[2], o[1] + 0.06)    # straight up, no roll: identity rest in Godot
        eb.roll = 0.0
        made[b["name"]] = eb
    for b in bones:
        if b["parent"]:
            made[b["name"]].parent = made[b["parent"]]
    bpy.ops.object.mode_set(mode="OBJECT")
    return ob

def bake_ao(ob):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.world = bpy.data.worlds.new("World")
    scene.world.light_settings.distance = 0.22
    img = bpy.data.images.new("ao", TEX, TEX, alpha=False, float_buffer=True)
    img.colorspace_settings.name = "Non-Color"
    mat = bpy.data.materials.new("bake")
    try:
        mat.use_nodes = True
    except Exception:
        pass
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = img
    mat.node_tree.nodes.active = node
    ob.data.materials.append(mat)
    scene.render.bake.margin = 8
    select_only([ob])
    bpy.ops.object.bake(type="AO")
    px = np.empty(TEX * TEX * 4, np.float32)
    img.pixels.foreach_get(px)
    ob.data.materials.clear()
    return px.reshape(TEX, TEX, 4)[..., 0].astype(float)

def save_png(path, arr, srgb):
    h, w = arr.shape[:2]
    alpha = arr.shape[2] == 4
    img = bpy.data.images.new(os.path.basename(path), w, h, alpha=alpha)
    img.colorspace_settings.name = "sRGB" if srgb else "Non-Color"
    img.alpha_mode = "STRAIGHT"
    rgba = np.ones((h, w, 4), np.float32)
    rgba[..., :arr.shape[2]] = np.clip(arr, 0.0, 1.0)
    img.pixels.foreach_set(rgba.ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    doc = json.load(open(SRC))
    rig = build_armature(doc["bones"])
    names = {b["name"] for b in doc["bones"]}
    for p in PARTS:
        p.prepare()
    pack(PARTS)
    albedo, normal, aux = paint_atlas(PARTS)
    obs = []
    for p in PARTS:
        obs.append(build_mesh(p, False))
        if p.mirror:
            obs.append(build_mesh(p, True))
    for o in obs:
        for vg in o.vertex_groups:
            if vg.name not in names:
                raise SystemExit("part %s: no bone %s" % (o.name, vg.name))
    select_only(obs)
    bpy.ops.object.join()
    fig = bpy.context.view_layer.objects.active
    fig.name = "Figure"
    ao = bake_ao(fig)
    aux[..., 0] = np.clip(0.25 + 0.85 * ao, 0.0, 1.0)
    base = os.path.splitext(os.path.abspath(OUT))[0]
    os.makedirs(os.path.dirname(base), exist_ok=True)
    save_png(base + "_albedo.png", albedo, True)
    save_png(base + "_normal.png", normal, False)
    save_png(base + "_aux.png", aux, False)
    fig.parent = rig
    mod = fig.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    tris = sum(len(p.vertices) - 2 for p in fig.data.polygons)
    print("figure: %d verts, %d tris, %d bones" % (len(fig.data.vertices), tris, len(rig.data.bones)))
    select_only([fig, rig], fig)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True,
        export_skins=True, export_animations=False, export_yup=True, export_normals=True,
        export_texcoords=True, export_tangents=True, export_vertex_color="NONE",
        export_materials="NONE", export_apply=False)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.splitext(SRC)[0] + "_crew.blend")
    print("wrote", OUT)

main()
