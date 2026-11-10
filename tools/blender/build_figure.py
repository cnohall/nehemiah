"""Build a CharacterRig figure as one skinned mesh (Blender 5.2, run headless).

    blender -b --factory-startup -P tools/blender/build_figure.py -- <rig.json> <out.glb> [preview_dir]

<rig.json> comes from tools/blender/export_rig.gd: every part of the figure at rest, in rig
space, with its colour, surface kind, bone and fuse group. Here:
  * fused groups (skin, hair, beard, tunic, skirt) are closed, joined and voxel-remeshed into
    one continuous surface each: no seams between parts, softened joins, the nose grown out of
    the face, the fingers out of the fist; then smoothed and decimated to a budget, and their
    colour / kind / bone carried over from the nearest original part
  * small crisp parts (eyes, brows, leatherwork, basket) keep their shapes and normals
  * weights are smoothed across the joints (knee, elbow, wrist, ankle) so limbs bend
  * ambient occlusion and a little wear are baked into the vertex data
  * exported as glTF (y up) with an armature whose bones sit on the rig's pivots, pointing up
    with no roll, so every bone's rest is the identity rotation in Godot (BakedFigure)
"""
import bpy
import bmesh
import json
import math
import os
import sys
from mathutils import Vector, noise
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
PREVIEW = os.path.abspath(argv[2]) if len(argv) > 2 else ""

# Voxel size (m, rig space) and triangle budget per fused group
FUSED = {
    "face": (0.0045, 12000),
    "hair": (0.004, 9000),
    "beard": (0.005, 5500),
    "arm_l_skin": (0.0045, 3200),
    "arm_r_skin": (0.0045, 3200),
    "leg_l_skin": (0.0045, 2200),
    "leg_r_skin": (0.0045, 2200),
    "tunic": (0.005, 8000),
    "skirt": (0.006, 4000),
}
SMOOTH_REPEAT = {"face": 14, "hair": 2, "beard": 4, "tunic": 10, "skirt": 3, "arm_l_skin": 6, "arm_r_skin": 6,
    "leg_l_skin": 4, "leg_r_skin": 4}
# A light relax after decimation: evens out the triangles the collapse left
RELAX = {"face": 4, "hair": 1, "beard": 1, "tunic": 3, "skirt": 2, "arm_l_skin": 2, "arm_r_skin": 2}
# Edge rings each bone's weight spreads across a joint
WEIGHT_SMOOTH = {"arm_l_skin": 14, "arm_r_skin": 14, "leg_l_skin": 14, "leg_r_skin": 14, "tunic": 10}
# Small round parts subdivided for a clean silhouette (eyes are looked at closest of all)
SUBDIVIDE = {"eye": 2, "brow": 1, "ear": 1}
HEAD = Vector((0.0, 0.926, 0.0))   # head pivot in rig space (Godot), set from the export
HEAD_SCALE = 1.15
BELT_TOP = 0.60     # rig-space height of the belt's top edge (torso 0.306 + 0.291)


def head_point(x, y, z):
    """A point authored in BuilderHead's space, in Blender's."""
    return g2b(*(HEAD + Vector((x, y, z)) * HEAD_SCALE))


def subdivide(ob, levels):
    """Weld the seams (Godot splits vertices along them), then Catmull-Clark: a round eye,
    a soft brow, instead of the facets of a low sphere."""
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(me)
    bm.free()
    m = ob.modifiers.new("subd", "SUBSURF")
    m.levels = levels
    m.render_levels = levels
    select_only([ob])
    bpy.ops.object.modifier_apply(modifier=m.name)
    for poly in ob.data.polygons:
        poly.use_smooth = True


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def relax(ob, iterations, factor=0.5):
    if not iterations:
        return
    m = ob.modifiers.new("relax", "SMOOTH")
    m.factor = factor
    m.iterations = iterations
    select_only([ob])
    bpy.ops.object.modifier_apply(modifier=m.name)


def grooves(group, me):
    """Sculpted strands: clean narrow valleys pressed in along the normal. Hair is combed
    front to back (valleys across x), the beard falls in locks round the jaw (valleys by
    angle round the head). Each valley bends a little; none is cut into a thin lock tip
    (depth fades with the lock's thickness, measured by a ray back through it)."""
    if group == "tunic":
        blouse(me)
        return
    depth = {"hair": 0.0045, "beard": 0.0065}.get(group)
    if depth is None:
        return
    verts = [v.co.copy() for v in me.vertices]
    tree = BVHTree.FromPolygons(verts, [list(p.vertices) for p in me.polygons])
    normals = [v.normal.copy() for v in me.vertices]
    for v, p, n in zip(me.vertices, verts, normals):
        hit = tree.ray_cast(p - n * 1e-4, -n, 0.2)
        thick = hit[3] if hit[0] is not None else 0.2
        fade = smoothstep(0.012, 0.05, thick)
        warp = noise.noise(p * 4.0) * 0.8
        if group == "hair":
            phase = p.x * 50.0 + warp
        else:
            phase = math.atan2(p.x, -p.y) * 15.0 + warp + p.z * 3.0
        d = math.remainder(phase, math.tau)            # distance to the nearest valley, radians
        valley = math.exp(-(d * d) / (2.0 * 0.45 * 0.45))
        v.co = p - n * depth * valley * fade


def blouse(me):
    """The tunic gathered by the belt: soft folds rising from it over the belly and back,
    fading by the chest, and a little overhang where the cloth blouses over the belt."""
    normals = [v.normal.copy() for v in me.vertices]
    for v, n in zip(me.vertices, normals):
        p = v.co.copy()
        h = p.z - BELT_TOP
        if h < -0.02 or h > 0.24 or abs(n.z) > 0.8:
            continue
        rise = smoothstep(-0.02, 0.015, h) * (1.0 - smoothstep(0.05, 0.24, h))
        a = math.atan2(p.x, -p.y)
        fold = math.sin(a * 11.0 + noise.noise(p * 6.0) * 1.4) * 0.5 + 0.5
        over = smoothstep(0.0, 0.03, h) * (1.0 - smoothstep(0.03, 0.09, h))
        v.co = p + n * (fold * 0.009 * rise + over * 0.008)


def paint(group, me, flat):
    """Painterly touches on a fused group's colour (r, g, b, a per vertex): sun on the crown
    of the hair, a flush on the cheeks and nose, the hem dusty from the yard."""
    co = [v.co for v in me.vertices]
    if group == "hair":
        z0 = min(c.z for c in co)
        z1 = max(c.z for c in co)
        for i, c in enumerate(co):
            t = (c.z - z0) / max(z1 - z0, 1e-4)
            f = 0.88 + 0.30 * t * t
            for k in range(3):
                flat[i * 4 + k] = min(1.0, flat[i * 4 + k] * f)
    elif group == "beard":
        # Lighter where the locks swell out, darker in at the chin
        for i, c in enumerate(co):
            t = smoothstep(-0.25, -0.42, c.y)
            f = 0.9 + 0.2 * t
            for k in range(3):
                flat[i * 4 + k] = min(1.0, flat[i * 4 + k] * f)
    elif group == "face":
        flush = (0.86, 0.46, 0.38)
        spots = [(head_point(0.19, 0.25, 0.26), 0.075, 0.38), (head_point(-0.19, 0.25, 0.26), 0.075, 0.38),
            (head_point(0.0, 0.29, 0.40), 0.06, 0.22), (head_point(0.33, 0.32, 0.03), 0.06, 0.25),
            (head_point(-0.33, 0.32, 0.03), 0.06, 0.25)]
        for i, c in enumerate(co):
            a = 0.0
            for at, r, k in spots:
                a = max(a, k * math.exp(-(c - at).length_squared / (2 * r * r)))
            for k in range(3):
                flat[i * 4 + k] += (flush[k] - flat[i * 4 + k]) * a
    if group in ("skirt", "leg_l_skin", "leg_r_skin"):
        dust = (0.90, 0.84, 0.74)
        for i, c in enumerate(co):
            a = smoothstep(0.34, 0.04, c.z) * 0.45
            for k in range(3):
                flat[i * 4 + k] *= 1.0 + (dust[k] - 1.0) * a


def cavity(me, flat, dark=0.32, light=0.10):
    """Dirt in the hollows, a catch of light on the ridges: each vertex against the mean of
    its neighbours, along its normal, smoothed once so it reads as shade, not noise."""
    nbr = [[] for _ in me.vertices]
    for e in me.edges:
        a, b = e.vertices
        nbr[a].append(b)
        nbr[b].append(a)
    co = [v.co for v in me.vertices]
    curv = []
    for i, v in enumerate(me.vertices):
        ns = nbr[i]
        if not ns:
            curv.append(0.0)
            continue
        mean = sum((co[j] for j in ns), Vector()) / len(ns)
        span = sum((co[j] - co[i]).length for j in ns) / len(ns)
        curv.append((mean - co[i]).dot(v.normal) / max(span, 1e-5))
    for _ in range(2):
        curv = [(c + sum(curv[j] for j in nbr[i]) / len(nbr[i])) * 0.5 if nbr[i] else c for i, c in enumerate(curv)]
    for i, c in enumerate(curv):
        f = 1.0 - dark * smoothstep(0.02, 0.25, c) + light * smoothstep(0.02, 0.25, -c)
        for k in range(3):
            flat[i * 4 + k] = min(1.0, flat[i * 4 + k] * f)


WEAR = 0.09
AO_DISTANCE = 0.12


def g2b(x, y, z):
    """Godot (y up, +z front) -> Blender (z up, -y front); the glTF export maps it back."""
    return Vector((x, -z, y))


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def family(c, base):
    """c is base lightened or darkened (Godot Color.lightened / darkened) by some amount."""
    for k in range(101):
        a = k / 100.0
        light = [b + (1.0 - b) * a for b in base]
        dark = [b * (1.0 - a) for b in base]
        if sum(abs(x - y) for x, y in zip(c, light)) < 0.006 or sum(abs(x - y) for x, y in zip(c, dark)) < 0.006:
            return True
    return False


def make_part(p, i):
    v = p["v"]
    verts = [g2b(v[k], v[k + 1], v[k + 2]) for k in range(0, len(v), 3)]
    idx = p["i"]
    faces = [(idx[k], idx[k + 1], idx[k + 2]) for k in range(0, len(idx), 3)]
    me = bpy.data.meshes.new("part%d" % i)
    me.from_pydata(verts, [], faces)
    me.update()
    n = p["n"]
    normals = [g2b(n[k], n[k + 1], n[k + 2]).normalized() for k in range(0, len(n), 3)]
    ob = bpy.data.objects.new("part%d_%s" % (i, p["group"]), me)
    bpy.context.scene.collection.objects.link(ob)
    for poly in me.polygons:
        poly.use_smooth = True
    try:
        me.normals_split_custom_set_from_vertices(normals)
    except Exception:
        pass
    ob["group"] = p["group"]
    ob["bone"] = p["bone"]
    ob["kind"] = p["kind"]
    ob["color"] = p["color"]
    return ob


def set_attrs(ob, color, kind, alpha=1.0):
    me = ob.data
    col = me.color_attributes.get("Col") or me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    data = [x for _ in me.vertices for x in (color[0], color[1], color[2], alpha)]
    col.data.foreach_set("color", data)
    k = me.attributes.get("kind") or me.attributes.new("kind", "FLOAT", "POINT")
    k.data.foreach_set("value", [kind] * len(me.vertices))


def assign_bone(ob, bone):
    vg = ob.vertex_groups.get(bone) or ob.vertex_groups.new(name=bone)
    vg.add(list(range(len(ob.data.vertices))), 1.0, "REPLACE")


def select_only(obs, active=None):
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active or obs[0]


def closed_copy(ob):
    """A copy with its open ends capped, so the voxel remesher sees a volume."""
    me = ob.data.copy()
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.holes_fill(bm, edges=bm.edges, sides=0)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    c = bpy.data.objects.new(ob.name + "_closed", me)
    bpy.context.scene.collection.objects.link(c)
    return c


def fuse(group, obs, voxel, budget, dye):
    closed = [closed_copy(o) for o in obs]
    select_only(closed)
    bpy.ops.object.join()
    g = bpy.context.view_layer.objects.active
    g.name = "fused_" + group
    g.data.remesh_voxel_size = voxel
    g.data.remesh_voxel_adaptivity = 0.0
    bpy.ops.object.voxel_remesh()
    rep = SMOOTH_REPEAT.get(group, 2)
    if rep:
        m = g.modifiers.new("smooth", "LAPLACIANSMOOTH")
        m.lambda_factor = 0.6
        m.iterations = rep
        m.use_volume_preserve = True
        bpy.ops.object.modifier_apply(modifier=m.name)
    grooves(group, g.data)
    tris = sum(len(p.vertices) - 2 for p in g.data.polygons)
    if tris > budget:
        m = g.modifiers.new("dec", "DECIMATE")
        m.ratio = budget / tris
        bpy.ops.object.modifier_apply(modifier=m.name)
    relax(g, RELAX.get(group, 1), 0.4)
    bpy.ops.object.shade_smooth()
    # Carry colour, kind and bone over from the nearest original surface
    verts, polys, owner = [], [], []
    for oi, o in enumerate(obs):
        base = len(verts)
        verts.extend(v.co.copy() for v in o.data.vertices)
        for p in o.data.polygons:
            polys.append([base + i for i in p.vertices])
            owner.append(oi)
    tree = BVHTree.FromPolygons(verts, polys)
    me = g.data
    cols, kinds, bones = [], [], []
    for v in me.vertices:
        hit = tree.find_nearest(v.co)
        o = obs[owner[hit[2]]] if hit[2] is not None else obs[0]
        cols.append(o["color"])
        kinds.append(o["kind"])
        bones.append(o["bone"])
    col = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    flat = []
    for c in cols:
        flat.extend(dyed(c, dye))
    paint(group, me, flat)
    col.data.foreach_set("color", flat)
    k = me.attributes.new("kind", "FLOAT", "POINT")
    k.data.foreach_set("value", kinds)
    names = sorted(set(bones))
    weights = [[1.0 if bones[i] == n else 0.0 for n in names] for i in range(len(bones))]
    if len(names) > 1:
        weights = smooth_weights(me, weights, WEIGHT_SMOOTH.get(group, 12))
    for n in names:
        g.vertex_groups.new(name=n)
    for i, w in enumerate(weights):
        top = sorted(range(len(names)), key=lambda j: -w[j])[:4]
        total = sum(w[j] for j in top) or 1.0
        for j in top:
            if w[j] > 1e-3:
                g.vertex_groups[names[j]].add([i], w[j] / total, "REPLACE")
    print("  fused %-11s %2d parts -> %6d tris" % (group, len(obs), sum(len(p.vertices) - 2 for p in me.polygons)))
    return g


def smooth_weights(me, weights, repeat):
    """Spread each bone's hold across the joints (graph Laplacian over the edges), so a knee
    or a wrist bends in a curve instead of creasing where two parts met."""
    nbr = [[] for _ in me.vertices]
    for e in me.edges:
        a, b = e.vertices
        nbr[a].append(b)
        nbr[b].append(a)
    w = weights
    for _ in range(repeat):
        nw = []
        for i, ns in enumerate(nbr):
            if not ns:
                nw.append(w[i])
                continue
            avg = [sum(w[j][k] for j in ns) / len(ns) for k in range(len(w[i]))]
            nw.append([w[i][k] * 0.5 + avg[k] * 0.5 for k in range(len(w[i]))])
        w = nw
    return w


def dyed(c, dye):
    """(r, g, b, a): fixed paint has a = 1; dyed cloth stores half its shade against the dye."""
    if dye is None:
        return (c[0], c[1], c[2], 1.0)
    return tuple(min(1.0, c[i] / max(dye[i], 1e-3) * 0.5) for i in range(3)) + (0.0,)


def build_armature(bones):
    arm = bpy.data.armatures.new("Rig")
    ob = bpy.data.objects.new("Rig", arm)
    bpy.context.scene.collection.objects.link(ob)
    select_only([ob])
    bpy.ops.object.mode_set(mode="EDIT")
    made = {}
    for b in bones:
        eb = arm.edit_bones.new(b["name"])
        eb.head = g2b(*b["origin"])
        eb.tail = eb.head + Vector((0, 0, 0.06))   # straight up, no roll: identity rest in Godot
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
    scene.cycles.samples = 64
    scene.world = scene.world or bpy.data.worlds.new("World")
    # Contact shade only: what sits within a hand's breadth (rig units), not the far side
    scene.world.light_settings.distance = AO_DISTANCE
    me = ob.data
    ao = me.color_attributes.new("AO", "FLOAT_COLOR", "POINT")
    me.color_attributes.active_color = ao
    mat = bpy.data.materials.new("bake")
    me.materials.append(mat)
    scene.render.bake.target = "VERTEX_COLORS"
    select_only([ob])
    bpy.ops.object.bake(type="AO", target="VERTEX_COLORS")
    vals = [0.0] * (len(me.vertices) * 4)
    ao.data.foreach_get("color", vals)
    out = [vals[i * 4] for i in range(len(me.vertices))]
    me.color_attributes.remove(ao)
    me.materials.clear()
    return unbury(me, out)


def unbury(me, ao):
    """A vertex inside another part (a band's edge under the hair, a lock's root in the cap)
    bakes black and bleeds dark into the faces that reach out of it. Fill those from their
    open neighbours, then lift the rest: creases shade, nothing goes black."""
    nbr = [[] for _ in me.vertices]
    for e in me.edges:
        a, b = e.vertices
        nbr[a].append(b)
        nbr[b].append(a)
    buried = [a < 0.08 for a in ao]
    for _ in range(12):
        changed = False
        for i, ns in enumerate(nbr):
            if not buried[i]:
                continue
            open_ = [ao[j] for j in ns if not buried[j]]
            if open_:
                ao[i] = sum(open_) / len(open_)
                buried[i] = False
                changed = True
        if not changed:
            break
    return [1.0 if b else min(1.0, 0.25 + a * 0.9) for a, b in zip(ao, buried)]


def finish(ob, ao):
    me = ob.data
    kinds = [0.0] * len(me.vertices)
    me.attributes["kind"].data.foreach_get("value", kinds)
    col = me.color_attributes["Col"]
    flat = [0.0] * (len(me.vertices) * 4)
    col.data.foreach_get("color", flat)
    # Wear: soft blotches of grime in rest space, so they ride with the figure
    for i, v in enumerate(me.vertices):
        w = 1.0 - WEAR * (noise.noise(v.co * 9.0) * 0.5 + 0.5)
        for c in range(3):
            flat[i * 4 + c] *= w
    col.data.foreach_set("color", flat)
    me.color_attributes.active_color = col
    me.color_attributes.render_color_index = me.color_attributes.find("Col")
    uv = me.uv_layers.new(name="UVMap")
    for loop in me.loops:
        k = kinds[loop.vertex_index]
        a = ao[loop.vertex_index]
        # u: kind (sculpt parts -> 9); v: occlusion (glTF flips v, so store 1 - ao)
        uv.data[loop.index].uv = (9.0 if k < 0 else k, 1.0 - a)
    me.attributes.remove(me.attributes["kind"])


def preview(ob, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.color_type = "VERTEX"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.show_cavity = False
    scene.render.resolution_x = 900
    scene.render.resolution_y = 1100
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 2.1
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    target = Vector((0, 0, 0.95))
    for name, yaw, pitch in [("front", 0.0, 0.0), ("iso", -0.6, 0.6), ("side", -math.pi / 2, 0.0)]:
        d = Vector((math.sin(yaw) * math.cos(pitch), -math.cos(yaw) * math.cos(pitch), math.sin(pitch)))
        cam.location = target + d * 5.0
        cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(out_dir, "blender_%s.png" % name)
        bpy.ops.render.render(write_still=True)


def main():
    clear()
    doc = json.load(open(SRC))
    dye = doc.get("dye")
    global HEAD
    global BELT_TOP
    for b in doc["bones"]:
        if b["name"] == "head":
            HEAD = Vector(b["origin"])
        if b["name"] == "torso":
            BELT_TOP = b["origin"][1] + 0.291
    rig = build_armature(doc["bones"])
    parts = [make_part(p, i) for i, p in enumerate(doc["parts"])]
    by_group = {}
    for o in parts:
        g = o["group"]
        centre = sum((v.co for v in o.data.vertices), Vector()) / max(1, len(o.data.vertices))
        # Ears stay their own crisp shapes (fused into the face they go lumpy)
        if g == "face" and abs(centre.x) > 0.3 * HEAD_SCALE:
            g = "ear"
        o["group"] = g
        by_group.setdefault(g, []).append(o)
        # The head-band sits a little proud of the hair it binds: a clean edge, no stair-cut
        if g == "band" and o["bone"] == "head":
            for v in o.data.vertices:
                v.co += v.normal * 0.007
    pieces = []
    for group, obs in sorted(by_group.items()):
        if group in FUSED:
            voxel, budget = FUSED[group]
            pieces.append(fuse(group, obs, voxel, budget, dye if group == "band" else None))
            for o in obs:
                bpy.data.objects.remove(o)
        else:
            for o in obs:
                if group in SUBDIVIDE:
                    subdivide(o, SUBDIVIDE[group])
                is_dye = group == "band" and dye is not None and family(o["color"], dye)
                c = dyed(o["color"], dye if is_dye else None)
                set_attrs(o, c[:3], o["kind"], c[3])
                assign_bone(o, o["bone"])
                pieces.append(o)
    # Leftover closed copies were joined into the fused objects; only the pieces remain
    for o in list(bpy.context.scene.objects):
        if o not in pieces and o != rig:
            bpy.data.objects.remove(o)
    select_only(pieces)
    bpy.ops.object.join()
    fig = bpy.context.view_layer.objects.active
    fig.name = "Figure"
    col = fig.data.color_attributes["Col"]
    flat = [0.0] * (len(fig.data.vertices) * 4)
    col.data.foreach_get("color", flat)
    cavity(fig.data, flat)
    col.data.foreach_set("color", flat)
    ao = bake_ao(fig)
    finish(fig, ao)
    fig.parent = rig
    mod = fig.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    tris = sum(len(p.vertices) - 2 for p in fig.data.polygons)
    print("figure: %d verts, %d tris, %d bones" % (len(fig.data.vertices), tris, len(rig.data.bones)))
    if PREVIEW:
        preview(fig, PREVIEW)
    select_only([fig, rig], fig)
    os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True,
        export_skins=True, export_animations=False, export_yup=True, export_normals=True,
        export_texcoords=True, export_vertex_color="ACTIVE", export_all_vertex_colors=False,
        export_materials="NONE", export_apply=False)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.splitext(SRC)[0] + ".blend")   # beside the json (build/), not in res://
    print("wrote", OUT)


main()
