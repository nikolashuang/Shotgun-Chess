# The campfire flame shared by build_menu_fire.py and build_rest_camp.py:
# one tall teardrop flame layered dark red to pale gold, two side tongues, wisps breaking off the tip and rising sparks.
import bpy, bmesh, math
from mathutils import Vector

# Colours sampled from the menu background's firelight, outside to inside
FLAME_COLORS = ["A63A26", "E0622C", "FD8A35", "FFB146", "FFD98A"]

# (x offset, base radius, height, colour index, phase, lean) in world units; later entries draw in front
FLAMES = [
    (-0.2, 0.13, 0.55, 0, 0.3, -1),
    (0.19, 0.12, 0.5, 0, 0.7, 1),
    (-0.19, 0.08, 0.36, 1, 0.55, -1),
    (0.18, 0.07, 0.32, 1, 0.1, 1),
    (0.0, 0.34, 1.15, 0, 0.0, 0),
    (0.0, 0.27, 0.95, 1, 0.12, 0),
    (0.0, 0.2, 0.72, 2, 0.25, 0),
    (0.0, 0.13, 0.48, 3, 0.4, 0),
    (0.0, 0.07, 0.28, 4, 0.5, 0),
]
# Bits of flame that break off the tip and rise as they shrink: (x offset, radius, colour index, phase)
WISPS = [(-0.05, 0.07, 1, 0.0), (0.06, 0.05, 2, 0.5)]
SPARKS = 4
SPARK_COLOR = "FFB146"
OUTLINE_POINTS = 16


# Teardrop outline: round belly low down, narrowing to a point, h runs 0 (base) to 1 (tip)
def teardrop(h):
    if h < 0.25:
        return 0.7 + 1.2 * h
    return ((1 - h) / 0.75) ** 1.3


# A flat polygon facing the camera; its outline is bent every frame by Fire.pose
def flat_flame(collection, name, mat):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    verts = [bm.verts.new((0, 0, 0)) for _ in range(OUTLINE_POINTS * 2)]
    bm.faces.new(verts)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    return obj


def square(collection, name, mat, size):
    mesh = bpy.data.meshes.new(name)
    s = size / 2
    mesh.from_pydata([(-s, 0, -s), (s, 0, -s), (s, 0, s), (-s, 0, s)], [], [(0, 1, 2, 3)])
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    return obj


# Outline points of a flame at time t: a wave rises up the body so the tip licks side to side
def flame_points(radius, height, t, phase, lean):
    points = []
    stretch = height * (1 + 0.1 * math.sin((t + phase) * 2 * math.pi))
    hs = [i / (OUTLINE_POINTS - 1) for i in range(OUTLINE_POINTS)]

    for side in (1, -1):
        for h in (hs if side == 1 else reversed(hs)):
            r = radius * teardrop(h) * (1 + 0.08 * math.sin((2 * t - 2 * h + phase) * 2 * math.pi))
            wave = 0.09 * h ** 1.5 * math.sin((2 * t - 1.3 * h + phase) * 2 * math.pi)
            x = side * r + wave + lean * 0.12 * h ** 2
            points.append((x, h * stretch))

    return points


def set_outline(obj, points, scale):
    for v, (x, z) in zip(obj.data.vertices, points):
        v.co = (x * scale, 0, z * scale)


# glow(name, hex) makes the scene's flat emission material; scale sizes the whole fire to the background
class Fire:
    def __init__(self, collection, base, glow, scale=1.0):
        self.base = base
        self.scale = scale
        self.objects = []

        colors = [glow(f"Flame{i}", c) for i, c in enumerate(FLAME_COLORS)]
        self.flames = [(flat_flame(collection, "Flame", colors[c]), dx, r, h, ph, lean) for dx, r, h, c, ph, lean in FLAMES]
        self.wisps = [(flat_flame(collection, "Wisp", colors[c]), dx, r, ph) for dx, r, c, ph in WISPS]
        self.sparks = [square(collection, "Spark", glow("Spark", SPARK_COLOR), 0.05 * scale) for _ in range(SPARKS)]
        self.objects = [f[0] for f in self.flames] + [w[0] for w in self.wisps] + self.sparks

    # t runs 0 to 1 and loops
    def pose(self, t):
        s = self.scale

        # Later flames sit nearer the camera so the brighter layers draw over the darker ones
        for i, (obj, dx, r, h, ph, lean) in enumerate(self.flames):
            set_outline(obj, flame_points(r, h, t, ph, lean), s)
            obj.location = self.base + Vector((dx * s, -0.01 * i, 0))

        for i, (obj, dx, r, ph) in enumerate(self.wisps):
            rise = (t + ph) % 1
            size = r * (1 - rise)
            points = flame_points(size, size * 3, t, ph, 0) if size > 0.012 else [(0, 0)] * (OUTLINE_POINTS * 2)
            set_outline(obj, points, s)
            sway = 0.05 * math.sin((rise + ph) * 2 * math.pi)
            obj.location = self.base + Vector(((dx + sway) * s, -0.2 - 0.01 * i, (0.85 + rise * 0.55) * s))

        for i, spark in enumerate(self.sparks):
            rise = (t + i / SPARKS) % 1
            drift = 0.12 * math.sin((rise + i * 0.3) * 2 * math.pi)
            spark.location = self.base + Vector(((-0.2 + i * 0.13 + drift) * s, -0.3, (0.3 + rise * 1.2) * s))
            spark.scale = (1 - rise * 0.6,) * 3
