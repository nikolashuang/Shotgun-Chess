# Run inside Blender (Text Editor > Run Script) with art/ShotgunChessSprites.blend open.
# Builds one small drawing per class ability (plus the Siege, Duels, Practice, Queue and Challenge cards) in a temporary scene,
# renders each one to art/armory/icons/<Name>.png, writes the scene to art/ArmoryIcons.blend
# and removes it again so the sprite file is left as it was. build_armory_art.py outlines and packs the renders.
import bpy, bmesh, math, os
from mathutils import Vector, Euler, Matrix

ROOT = os.path.dirname(os.path.dirname(bpy.data.filepath))
OUT = os.path.join(ROOT, "art", "armory", "icons")
SCENE_NAME = "ArmoryIcons"

CREATED_MATERIALS = set()

SIZE = 64
ORTHO_SCALE = 2.9
# Icons rendered wider than the usual square, at the same pixels per unit: (width, height)
RENDER_SIZES = {"RestUpgrade": (88, 48)}
# Most icons are drawn flat-on like the gun sprites; these keep the angled 3D camera
CAMERA_PITCH_2D = 90
CAMERA_PITCH_3D = 72
THREE_D = {"Siege", "RestBandage", "RestTrain", "RestUpgrade"}


def linear(hex_color):
    def channel(c):
        c = c / 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return [channel(int(hex_color[i:i + 2], 16)) for i in (0, 2, 4)] + [1]


# Same three tone toon shading as the islands
def toon(name, dark, base, light):
    name = "Icon" + name
    if name in bpy.data.materials:
        return bpy.data.materials[name]

    mat = bpy.data.materials.new(name)
    CREATED_MATERIALS.add(mat.name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()

    diffuse = nodes.new("ShaderNodeBsdfDiffuse")
    to_rgb = nodes.new("ShaderNodeShaderToRGB")
    to_bw = nodes.new("ShaderNodeRGBToBW")
    ramp = nodes.new("ShaderNodeValToRGB")
    emission = nodes.new("ShaderNodeEmission")
    output = nodes.new("ShaderNodeOutputMaterial")

    ramp.color_ramp.interpolation = "CONSTANT"
    elements = ramp.color_ramp.elements
    elements[0].position, elements[0].color = 0.0, linear(dark)
    elements[1].position, elements[1].color = 0.18, linear(base)
    third = elements.new(0.5)
    third.color = linear(light)

    links.new(diffuse.outputs[0], to_rgb.inputs[0])
    links.new(to_rgb.outputs[0], to_bw.inputs[0])
    links.new(to_bw.outputs[0], ramp.inputs[0])
    links.new(ramp.outputs[0], emission.inputs[0])
    links.new(emission.outputs[0], output.inputs[0])

    return mat


def glow(name, color):
    name = "Icon" + name
    if name in bpy.data.materials:
        return bpy.data.materials[name]

    mat = bpy.data.materials.new(name)
    CREATED_MATERIALS.add(mat.name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    emission = nodes.new("ShaderNodeEmission")
    emission.inputs[0].default_value = linear(color)
    output = nodes.new("ShaderNodeOutputMaterial")
    mat.node_tree.links.new(emission.outputs[0], output.inputs[0])

    return mat


STONE = ("5A5260", "8A8290", "B5AEB5")
CREAM = ("B59A7A", "E9E3D6", "FFF8EC")
WOOD = ("4A2F25", "7A4B33", "A0683F")
LEATHER = ("3A2420", "6E4436", "8A5A44")
GOLD = ("8A5A2A", "D49A77", "F1D4AC")
BRASS = ("6A4A1E", "C8954A", "F1D4AC")
STEEL = ("3E3A44", "7A7680", "B8B4BC")
RUST = ("5E2F2A", "9C574B", "C8644F")
DARK = ("1E1820", "332A35", "4A3E4C")
SMOKE = ("6A6470", "9A949E", "C8C2CC")
SOUL = "9FE8D8"
SOUL_CORE = "E8FFF8"
ENERGY = "F6D36A"
TARGET = "C8644F"
SPARK = "FFD27A"


def build_torus(bm, major, minor, major_segments, minor_segments, arc=2 * math.pi):
    closed = arc >= 2 * math.pi - 1e-4
    count = major_segments if closed else major_segments + 1
    rings = []

    for i in range(count):
        a = arc * i / major_segments
        ring = []

        for j in range(minor_segments):
            b = 2 * math.pi * j / minor_segments
            radius = major + minor * math.cos(b)
            ring.append(bm.verts.new((radius * math.cos(a), radius * math.sin(a), minor * math.sin(b))))

        rings.append(ring)

    for i in range(major_segments):
        a, b = rings[i], rings[(i + 1) % count]
        for j in range(minor_segments):
            bm.faces.new((a[j], b[j], b[(j + 1) % minor_segments], a[(j + 1) % minor_segments]))


class Icon:
    def __init__(self, scene, name):
        self.name = name
        self.collection = bpy.data.collections.new("Icon_" + name)
        scene.collection.children.link(self.collection)

    def add(self, build, mat, location, rotation=(0, 0, 0), scale=(1, 1, 1)):
        bm = bmesh.new()
        build(bm)
        mesh = bpy.data.meshes.new(self.name)
        bm.to_mesh(mesh)
        bm.free()

        obj = bpy.data.objects.new(self.name, mesh)
        obj.location = location
        obj.rotation_euler = Euler([math.radians(r) for r in rotation])
        obj.scale = scale
        obj.data.materials.append(mat)
        self.collection.objects.link(obj)

        return obj

    def cube(self, mat, location, size, rotation=(0, 0, 0)):
        return self.add(lambda bm: bmesh.ops.create_cube(bm, size=1), mat, location, rotation, size)

    def cylinder(self, mat, location, radius, depth, vertices=10, rotation=(0, 0, 0), top=None):
        top = radius if top is None else top
        return self.add(lambda bm: bmesh.ops.create_cone(bm, cap_ends=True, segments=vertices, radius1=radius, radius2=top, depth=depth), mat, location, rotation)

    def ball(self, mat, location, radius, scale=(1, 1, 1), segments=12):
        def build(bm):
            bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=segments // 2, radius=radius)

        return self.add(build, mat, location, (0, 0, 0), scale)

    def torus(self, mat, location, major, minor, rotation=(0, 0, 0), arc=360, segments=20):
        return self.add(lambda bm: build_torus(bm, major, minor, segments, 8, math.radians(arc)), mat, location, rotation)

    def star(self, mat, location, outer, inner, depth, rotation=(0, 0, 0), points=5):
        def build(bm):
            front, back = [], []
            for i in range(points * 2):
                a = math.pi / 2 + math.pi * i / points
                r = outer if i % 2 == 0 else inner
                front.append(bm.verts.new((r * math.cos(a), r * math.sin(a), depth / 2)))
                back.append(bm.verts.new((r * math.cos(a), r * math.sin(a), -depth / 2)))
            bm.faces.new(front)
            bm.faces.new(list(reversed(back)))
            for i in range(points * 2):
                n = (i + 1) % (points * 2)
                bm.faces.new((front[i], back[i], back[n], front[n]))

        return self.add(build, mat, location, rotation)

    # A rod between two points
    def rod(self, mat, start, end, radius, vertices=6):
        start, end = Vector(start), Vector(end)
        direction = end - start
        obj = self.cylinder(mat, (start + end) / 2, radius, direction.length, vertices)
        obj.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()

        return obj

    # Turns every part of the drawing about the origin: spin around Z, then tip around X
    def turn(self, spin=0, tip=0):
        matrix = Euler((math.radians(tip), 0, math.radians(spin)), "ZXY").to_matrix().to_4x4()
        for obj in self.collection.objects:
            obj.matrix_basis = matrix @ obj.matrix_basis

    def pawn(self, mat, location, scale=1):
        x, y, z = location
        self.cylinder(mat, (x, y, z + 0.08 * scale), 0.42 * scale, 0.16 * scale, 14)
        self.cylinder(mat, (x, y, z + 0.42 * scale), 0.3 * scale, 0.55 * scale, 14, top=0.14 * scale)
        self.ball(mat, (x, y, z + 0.82 * scale), 0.24 * scale)


# Flat things are tilted by the camera pitch so they face the viewer; set per icon before it's built
FACE = CAMERA_PITCH_2D


def assimilate(icon):
    icon.pawn(toon("Cream", *CREAM), (0, 0, -0.85), 1.25)
    soul = glow("Soul", SOUL)
    icon.torus(soul, (0, 0, -0.2), 0.75, 0.05, rotation=(20, 0, 0), arc=290)
    icon.ball(soul, (0.7, -0.1, 0.05), 0.15)
    icon.ball(glow("SoulCore", SOUL_CORE), (0.68, -0.18, 0.08), 0.07)


def reapers_high(icon):
    wood = toon("Wood", *WOOD)
    icon.rod(wood, (-0.75, 0, -1.0), (0.45, 0, 0.95), 0.07)
    steel = toon("Steel", *STEEL)
    icon.torus(steel, (-0.05, 0, 0.75), 0.55, 0.09, rotation=(90, 0, 0), arc=110, segments=10)
    icon.cube(steel, (0.4, 0, 0.88), (0.18, 0.12, 0.2))
    soul = glow("Soul", SOUL)
    for x, z, r in ((-0.6, 0.35, 0.16), (0.65, -0.35, 0.2), (-0.15, -0.7, 0.13)):
        icon.ball(soul, (x, 0, z), r)


def collector(icon):
    gold = toon("Brass", *BRASS)
    stamp = toon("CoinStamp", "6A4A1E", "A8844A", "D4A050")
    face = (FACE, 0, 0)
    front = Euler([math.radians(r) for r in face]).to_matrix() @ Vector((0, 0, 0.09))

    icon.cylinder(gold, (0, 0, 0), 0.85, 0.16, 28, rotation=face)
    icon.torus(stamp, front, 0.78, 0.05, rotation=face, segments=28)
    icon.star(stamp, front, 0.42, 0.18, 0.06, rotation=face)


# Open bear trap seen from above: jaw ring with teeth pointing in and the pressure plate in the middle
def trap_layout(icon):
    steel = toon("Steel", *STEEL)
    face = Euler((math.radians(FACE), 0, 0)).to_matrix()

    def on_face(x, y):
        return face @ Vector((x, y, 0))

    icon.torus(steel, (0, 0, 0), 0.8, 0.08, rotation=(FACE, 0, 0), segments=28)
    icon.torus(steel, (0, 0, 0), 0.66, 0.04, rotation=(FACE, 0, 0), segments=28)
    icon.cylinder(toon("Plate", "2A2830", "4E4A56", "6A6672"), on_face(0, 0) + face @ Vector((0, 0, -0.02)), 0.26, 0.06, 16, rotation=(FACE, 0, 0))
    icon.cylinder(steel, on_face(0, 0), 0.08, 0.1, 8, rotation=(FACE, 0, 0))

    # Teeth on the top and bottom jaws, skipping the hinges at the sides
    for i in range(12):
        a = 2 * math.pi * (i + 0.5) / 12
        if abs(math.cos(a)) > 0.9: continue

        rim = on_face(0.72 * math.cos(a), 0.72 * math.sin(a))
        tip = on_face(0.4 * math.cos(a), 0.4 * math.sin(a))
        tooth = icon.cylinder(toon("Teeth", "5A5662", "B8B4BC", "E9E3D6"), (rim + tip) / 2, 0.11, (tip - rim).length, 4, top=0.0)
        tooth.rotation_euler = (tip - rim).to_track_quat("Z", "Y").to_euler()

    for side in (-1, 1):
        icon.cylinder(steel, on_face(side * 0.82, 0), 0.12, 0.14, 8, rotation=(FACE, 0, 0))


def hunting_strike(icon):
    stone = toon("Stone", *STONE)
    rope = toon("Rope", *GOLD)
    center = (0.0, 0, 0.05)
    for x, z in ((-0.75, 0.55), (0.75, 0.45), (0.05, -0.85)):
        icon.rod(rope, center, (x, 0, z), 0.035)
        icon.ball(stone, (x, 0, z), 0.26)
    icon.ball(rope, center, 0.1)


# Two bullets flying out of the card toward the viewer, angled off to the right, with speed streaks behind them
def deadly_rounds(icon):
    brass = toon("Casing", "6A4A1E", "B8893F", "D9A84F")
    copper = toon("BulletTip", "5A2E1C", "9C5434", "C8784A")
    streak = glow("Streak", "F1D4AC")
    direction = Vector((0.42, -0.88, 0.22)).normalized()
    rotation = direction.to_track_quat("Z", "Y").to_euler()

    def bullet(base, scale):
        base = Vector(base)
        casing = icon.cylinder(brass, base + direction * 0.26 * scale, 0.17 * scale, 0.52 * scale, 16)
        casing.rotation_euler = rotation
        rim = icon.cylinder(brass, base, 0.19 * scale, 0.06 * scale, 16)
        rim.rotation_euler = rotation
        tip = icon.cylinder(copper, base + direction * 0.68 * scale, 0.17 * scale, 0.32 * scale, 16, top=0.05 * scale)
        tip.rotation_euler = rotation
        icon.ball(copper, base + direction * 0.84 * scale, 0.055 * scale)

        # Streaks trail back from the casing
        for offset, length in ((Vector((0, 0, 0.1)), 0.9), (Vector((0, 0, -0.1)), 0.65), (Vector((0.08, 0, 0)), 0.5)):
            start = base + offset * scale
            icon.rod(streak, start, start - direction * length * scale, 0.018, vertices=4)

    bullet((-0.33, 0.3, 0.34), 1.35)
    bullet((0.42, 0.1, -0.46), 1.1)


# Side-on long-barrel revolver modelled on the reference photo, barrel to the right
# Frame, grip and hammer are each one extruded outline so the gun reads as one solid piece
def fan_the_hammer(icon):
    steel = toon("DarkBlued", "16121A", "2E2A34", "4E4A56")
    drum = toon("DarkDrum", "221E28", "3E3A46", "625E6C")
    flute = toon("Flute", "1E1820", "2A2830", "3A3640")
    wood = toon("Grip", "3A2018", "6A3A24", "94573A")
    dx = -0.22

    def at(x, z, y=0):
        return (x + dx, y, z)

    # Extrudes a side outline (x, z points, counterclockwise) through the gun's thickness
    def outline(mat, points, depth, y=0):
        def build(bm):
            front = [bm.verts.new((x + dx, y - depth / 2, z)) for x, z in points]
            back = [bm.verts.new((x + dx, y + depth / 2, z)) for x, z in points]
            bm.faces.new(list(reversed(front)))
            bm.faces.new(back)
            for i in range(len(points)):
                n = (i + 1) % len(points)
                bm.faces.new((front[i], front[n], back[n], back[i]))

        return icon.add(build, mat, (0, 0, 0))

    # Frame: top strap over the cylinder, recoil shield, and the backstrap running down into the grip
    outline(steel, [
        (0.22, 0.12), (0.22, 0.44), (-0.36, 0.44), (-0.48, 0.38), (-0.56, 0.22),
        (-0.62, 0.02), (-0.52, -0.06), (-0.30, -0.02), (-0.02, -0.02), (0.08, 0.08),
    ], 0.14)

    # Hammer spur curling back off the top of the frame
    outline(steel, [(-0.34, 0.4), (-0.42, 0.52), (-0.52, 0.6), (-0.62, 0.62), (-0.64, 0.57), (-0.54, 0.52), (-0.48, 0.42), (-0.46, 0.36)], 0.08)

    # Wooden grip wrapping the backstrap: wider than the frame so it hugs it, angled down and back
    outline(wood, [
        (-0.3, 0.0), (-0.44, 0.18), (-0.56, 0.24), (-0.66, 0.18), (-0.72, 0.0), (-0.8, -0.32),
        (-0.88, -0.6), (-0.84, -0.76), (-0.66, -0.82), (-0.54, -0.74), (-0.48, -0.5), (-0.4, -0.22),
    ], 0.2)
    icon.cylinder(toon("Medallion", *GOLD), at(-0.58, -0.14, -0.11), 0.045, 0.02, 10, rotation=(90, 0, 0))

    # Long barrel with a top rib, a ramp front sight and the ejector shroud underneath
    icon.rod(steel, at(0.2, 0.32), at(1.38, 0.32), 0.08, vertices=12)
    icon.cube(steel, at(0.79, 0.41), (1.18, 0.05, 0.03))
    outline(steel, [(1.24, 0.4), (1.36, 0.4), (1.36, 0.5), (1.32, 0.5)], 0.04)
    icon.cube(steel, at(0.48, 0.2), (0.56, 0.1, 0.1))
    icon.ball(steel, at(0.76, 0.2), 0.05, scale=(1, 1, 1))

    # Fluted cylinder in front of the frame
    icon.rod(drum, at(-0.2, 0.24), at(0.18, 0.24), 0.2, vertices=14)
    for z in (0.17, 0.31):
        icon.cube(flute, at(-0.01, z, -0.21), (0.3, 0.02, 0.035))

    # Round trigger guard under the frame and a curved trigger
    icon.torus(steel, at(-0.18, -0.12), 0.13, 0.024, rotation=(90, 0, 0), segments=16)
    icon.cube(steel, at(-0.17, -0.08), (0.04, 0.05, 0.16), rotation=(0, 15, 0))

    # A little larger so the long barrel fills the card
    grow = Matrix.Scale(1.12, 4)
    for obj in icon.collection.objects:
        obj.matrix_basis = grow @ obj.matrix_basis


def bounty(icon):
    gold = toon("Brass", *BRASS)
    icon.star(gold, (0, 0, 0), 0.95, 0.45, 0.16, rotation=(FACE, 0, 0))
    for i in range(5):
        a = math.pi / 2 + 2 * math.pi * i / 5
        up = math.sin(a) * 0.95
        icon.ball(gold, (math.cos(a) * 0.95, -up * math.cos(math.radians(FACE)), up * math.sin(math.radians(FACE))), 0.1)
    icon.cylinder(toon("Rust", *RUST), (0, -0.05, 0), 0.25, 0.2, 14, rotation=(FACE, 0, 0))


def opportunist(icon):
    icon.pawn(toon("DarkPiece", *DARK), (0, 0, -0.9), 1.15)
    # Target reticle behind the lone piece
    red = glow("Target", TARGET)
    center = Vector((0, 0.5, -0.3))
    icon.torus(red, center, 0.72, 0.06, rotation=(FACE, 0, 0), segments=28)
    for angle in (0, 90, 180, 270):
        a = math.radians(angle)
        offset = Euler((math.radians(FACE), 0, 0)).to_matrix() @ Vector((math.cos(a) * 0.85, math.sin(a) * 0.85, 0))
        icon.cube(red, center + offset, (0.3 if angle % 180 == 0 else 0.08, 0.06, 0.08 if angle % 180 == 0 else 0.3))


def conceal(icon):
    smoke = toon("Smoke", *SMOKE)
    for x, z, r in ((-0.6, -0.55, 0.38), (0.55, -0.6, 0.34), (-0.05, -0.75, 0.32), (0.75, 0.05, 0.25), (-0.75, 0.0, 0.22)):
        icon.ball(smoke, (x, 0.3, z), r)
    icon.ball(toon("Bomb", *DARK), (0, 0, -0.1), 0.5)
    icon.cylinder(toon("Rope", *GOLD), (0.2, 0, 0.45), 0.05, 0.35, 6, rotation=(0, 30, 0))
    icon.ball(glow("Spark", SPARK), (0.32, 0, 0.65), 0.11)


def ambush(icon):
    steel = toon("Steel", *STEEL)
    tilt = -40
    turn = Euler((0, math.radians(tilt), 0)).to_matrix()

    def along(t):
        return turn @ Vector((0, 0, t))
    blade = icon.cylinder(steel, along(0.35), 0.16, 1.1, 4, rotation=(0, tilt, 0), top=0.0)
    blade.scale = (1, 0.3, 1)
    icon.cube(toon("Brass", *BRASS), along(-0.25), (0.55, 0.15, 0.1), rotation=(0, tilt, 0))
    icon.cylinder(toon("Leather", *LEATHER), along(-0.55), 0.08, 0.5, 8, rotation=(0, tilt, 0))
    icon.ball(toon("Brass", *BRASS), along(-0.85), 0.12)


def siege(icon):
    stone = toon("Stone", *STONE)
    icon.cylinder(stone, (0, 0, -0.35), 0.55, 1.2, 12)
    for i in range(8):
        a = 2 * math.pi * i / 8
        icon.cube(stone, (math.cos(a) * 0.5, math.sin(a) * 0.5, 0.35), (0.18, 0.18, 0.2), rotation=(0, 0, math.degrees(a)))
    dark = toon("Dark", *DARK)
    icon.cube(dark, (0, -0.52, -0.7), (0.3, 0.1, 0.45))
    icon.cube(dark, (0, -0.52, 0.0), (0.12, 0.1, 0.2))
    icon.rod(toon("Wood", *WOOD), (0, 0, 0.2), (0, 0, 1.15), 0.03)
    icon.cube(toon("Rust", *RUST), (0.22, 0, 1.0), (0.4, 0.04, 0.25))



# One shotgun drawn flat in the X/Z plane: barrels toward direction (degrees), stock behind
def shotgun(icon, angle, double=False):
    steel = toon("Steel", *STEEL)
    wood = toon("Wood", *WOOD)
    a = math.radians(angle)
    d = Vector((math.cos(a), 0, math.sin(a)))
    n = Vector((-math.sin(a), 0, math.cos(a)))

    offsets = (-0.06, 0.06) if double else (0,)
    for o in offsets:
        icon.rod(steel, -d * 0.1 + n * o, d * 1.05 + n * o, 0.065, vertices=8)
    icon.rod(steel, -d * 0.4, -d * 0.05, 0.12, vertices=8)
    icon.rod(wood, -d * 0.4 - n * 0.02, -d * 1.05 - n * 0.16, 0.14, vertices=8)
    icon.rod(wood, d * 0.2 - n * 0.13, d * 0.5 - n * 0.13, 0.09, vertices=8)


def duels(icon):
    shotgun(icon, 45, double=True)
    shotgun(icon, 135, double=True)


def practice(icon):
    wood = toon("Wood", *WOOD)
    straw = toon("Straw", *BRASS)
    icon.rod(wood, (0, 0.2, -1.3), (0, 0.2, 0.75), 0.07)
    icon.rod(wood, (-0.8, 0.2, 0.2), (0.8, 0.2, 0.2), 0.06)
    icon.ball(straw, (0, 0, -0.1), 0.5, scale=(1.05, 0.6, 1.4))
    icon.ball(straw, (0, 0, 0.82), 0.3)
    icon.cylinder(wood, (0, 0.2, -1.3), 0.35, 0.12, 12)
    red = glow("Target", TARGET)
    icon.torus(red, (0, -0.35, -0.05), 0.28, 0.05, rotation=(FACE, 0, 0), segments=20)
    icon.ball(red, (0, -0.4, -0.05), 0.08)


def queue(icon):
    wood = toon("Wood", *WOOD)
    glass = toon("Glass", *SMOKE)
    sand = toon("Sand", *GOLD)
    for z in (-0.98, 0.98):
        icon.cylinder(wood, (0, 0, z), 0.68, 0.14, 14)
    for x in (-0.58, 0.58):
        icon.rod(wood, (x, 0.3, -0.95), (x, 0.3, 0.95), 0.05)
    icon.cylinder(glass, (0, 0, -0.47), 0.48, 0.82, 14, top=0.06)
    icon.cylinder(glass, (0, 0, 0.47), 0.06, 0.82, 14, top=0.48)
    icon.cylinder(sand, (0, -0.6, -0.72), 0.36, 0.3, 14, top=0.05)
    icon.cylinder(sand, (0, -0.6, 0.3), 0.06, 0.3, 14, top=0.26)
    icon.rod(sand, (0, -0.6, 0.15), (0, -0.6, -0.6), 0.025)


def challenge(icon):
    paper = toon("Paper", *CREAM)
    ink = toon("Ink", *DARK)
    icon.cube(paper, (0, 0, -0.05), (1.7, 0.06, 1.15))
    icon.rod(ink, (-0.82, -0.05, 0.48), (0, -0.05, -0.12), 0.025)
    icon.rod(ink, (0.82, -0.05, 0.48), (0, -0.05, -0.12), 0.025)
    icon.cylinder(toon("Wax", *RUST), (0, -0.1, -0.12), 0.3, 0.08, 14, rotation=(90, 0, 0))
    icon.star(glow("Spark", SPARK), (0, -0.16, -0.12), 0.16, 0.07, 0.04, rotation=(FACE, 0, 0))


# Leather coin pouch tied with a gold cord, a coin leaning on the front
def pouch(icon):
    leather = toon("Leather", *LEATHER)
    cord = toon("Gold", *GOLD)

    icon.ball(leather, (0, 0, -0.32), 0.72, scale=(1, 0.8, 0.86), segments=16)
    icon.cylinder(leather, (0, 0, 0.36), 0.26, 0.3, 14)
    icon.cylinder(leather, (0, 0, 0.66), 0.24, 0.3, 14, top=0.46)
    icon.torus(cord, (0, 0, 0.42), 0.3, 0.07, rotation=(12, 0, 0), segments=18)
    icon.rod(cord, (0.22, -0.2, 0.38), (0.5, -0.25, 0.1), 0.05)
    icon.ball(cord, (0.52, -0.26, 0.07), 0.08)

    coin = toon("PouchCoin", "6A4A1E", "C8954A", "E0B05A")
    stamp = toon("CoinStamp", "6A4A1E", "A8844A", "D4A050")
    face = (FACE, 0, 0)
    icon.cylinder(coin, (-0.42, -0.62, -0.72), 0.3, 0.08, 20, rotation=face)
    icon.star(stamp, (-0.42, -0.67, -0.72), 0.16, 0.07, 0.03, rotation=face)


# Rest Site cards, seen from the angled camera like Siege so they read as small 3D scenes
# Leans the whole drawing in the picture plane (around Y), then turns it three-quarters on (around Z)
def lean(icon, tilt, spin):
    matrix = Euler((0, math.radians(tilt), math.radians(spin)), "YZX").to_matrix().to_4x4()
    for obj in icon.collection.objects:
        obj.matrix_basis = matrix @ obj.matrix_basis


# A fat roll of bandage cloth lying on the diagonal, strapped twice and patched on top
def rest_bandage(icon):
    cloth = toon("Bandage", "8A8290", "D8D2C6", "F2EEE6")
    seam = toon("BandageSeam", "5A5260", "8A8290", "B5AEB5")
    strap = toon("Strap", *LEATHER)
    steel = toon("Buckle", *STEEL)
    side = (0, 90, 0)

    icon.cylinder(cloth, (0, 0, 0), 0.56, 1.8, 24, rotation=side)
    # The rolled-up layers on the end facing the viewer
    for r in (0.14, 0.27, 0.4, 0.52):
        icon.torus(seam, (0.9, 0, 0), r, 0.03, rotation=side, segments=24)
    icon.cylinder(seam, (0.9, 0, 0), 0.07, 0.04, 10, rotation=side)

    for x in (-0.42, 0.5):
        icon.torus(strap, (x, 0, 0), 0.57, 0.06, rotation=side, segments=24)
        icon.cube(steel, (x, -0.6, 0.05), (0.2, 0.06, 0.16))

    # A stitched patch on the shoulder of the roll facing the viewer, built on top and rolled forward
    before = set(icon.collection.objects)
    patch = toon("Patch", "8A8290", "C8C2B8", "E9E3D6")
    icon.cube(patch, (0.05, 0, 0.56), (0.46, 0.46, 0.05))
    ink = toon("Stitch", *DARK)
    for o in (-0.09, 0.09):
        icon.rod(ink, (0.05 + o, -0.18, 0.6), (0.05 + o, 0.18, 0.6), 0.025, vertices=4)
        icon.rod(ink, (-0.13, o, 0.6), (0.23, o, 0.6), 0.025, vertices=4)
    roll_forward = Euler((math.radians(50), 0, 0)).to_matrix().to_4x4()
    for obj in set(icon.collection.objects) - before:
        obj.matrix_basis = roll_forward @ obj.matrix_basis
    lean(icon, -24, -32)


# One heavy dumbbell, tipped up on the diagonal
def rest_train(icon):
    iron = toon("Iron", *DARK)
    plate = toon("Plate", *STEEL)
    grip = toon("Grip", *SMOKE)
    side = (0, 90, 0)

    icon.cylinder(iron, (0, 0, 0), 0.07, 2.2, 10, rotation=side)
    icon.cylinder(grip, (0, 0, 0), 0.1, 0.7, 12, rotation=side)
    for sign in (-1, 1):
        icon.cylinder(iron, (sign * 0.42, 0, 0), 0.16, 0.08, 14, rotation=side)
        icon.cylinder(plate, (sign * 0.56, 0, 0), 0.58, 0.18, 22, rotation=side)
        icon.cylinder(plate, (sign * 0.76, 0, 0), 0.46, 0.16, 22, rotation=side)
        icon.cylinder(iron, (sign * 0.9, 0, 0), 0.14, 0.1, 14, rotation=side)
    lean(icon, -22, -34)


# Turned three-quarters on; build_rest_cards.py turns it into blueprint linework
def rest_upgrade(icon):
    shotgun(icon, 0)
    for obj in icon.collection.objects:
        obj.location *= 1.7
        obj.scale *= 1.7
    icon.turn(spin=-30)


def setup_scene():
    old = bpy.data.scenes.get(SCENE_NAME)
    if old:
        remove_scene(old)

    scene = bpy.data.scenes.new(SCENE_NAME)
    scene.render.engine = bpy.data.scenes[0].render.engine
    scene.render.resolution_x = SIZE
    scene.render.resolution_y = SIZE
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.filter_size = 0
    scene.view_settings.view_transform = "Standard"

    scene.world = bpy.data.worlds.new("IconWorld")
    scene.world.color = (0.02, 0.02, 0.02)

    camera_data = bpy.data.cameras.new("IconCam")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = ORTHO_SCALE
    camera = bpy.data.objects.new("IconCam", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera

    sun_data = bpy.data.lights.new("IconSun", "SUN")
    sun_data.energy = 3
    sun = bpy.data.objects.new("IconSun", sun_data)
    scene.collection.objects.link(sun)

    return scene


# 2D icons are seen straight on and lit from the front, so shading stays flat with a darker rim
def aim(scene, is_3d):
    pitch = math.radians(CAMERA_PITCH_3D if is_3d else CAMERA_PITCH_2D)
    camera = scene.camera
    camera.rotation_euler = (pitch, 0, 0)
    camera.location = -Vector((0, math.sin(pitch), -math.cos(pitch))) * 20

    sun = scene.objects["IconSun"]
    if is_3d:
        sun.rotation_euler = (math.radians(50), math.radians(-35), math.radians(-25))
    else:
        sun.rotation_euler = (math.radians(65), 0, math.radians(-20))


def remove_scene(scene):
    for obj in list(scene.collection.all_objects):
        data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)

        if data and data.users == 0:
            if isinstance(data, bpy.types.Mesh):
                bpy.data.meshes.remove(data)
            elif isinstance(data, bpy.types.Camera):
                bpy.data.cameras.remove(data)
            elif isinstance(data, bpy.types.Light):
                bpy.data.lights.remove(data)

    for collection in list(scene.collection.children_recursive):
        bpy.data.collections.remove(collection)

    world = scene.world
    bpy.data.scenes.remove(scene)

    if world and world.users == 0:
        bpy.data.worlds.remove(world)

    for name in CREATED_MATERIALS:
        mat = bpy.data.materials.get(name)

        if mat and mat.users == 0:
            bpy.data.materials.remove(mat)


# Names match ClassConfig: <Class>Passive, <Class>Special, <Class>Ultimate
# ReaperPassive isn't drawn here: build_armory_art.py uses the in-game soul sprite for it
BUILDERS = [
    ("ReaperSpecial", assimilate), ("ReaperUltimate", reapers_high),
    ("HunterPassive", collector), ("HunterSpecial", trap_layout), ("HunterUltimate", hunting_strike),
    ("GunslingerPassive", deadly_rounds), ("GunslingerSpecial", fan_the_hammer), ("GunslingerUltimate", bounty),
    ("OutlawPassive", opportunist), ("OutlawSpecial", conceal), ("OutlawUltimate", ambush),
    ("Siege", siege),
    ("Duels", duels), ("Practice", practice), ("Queue", queue), ("Challenge", challenge),
    ("Pouch", pouch),
    ("RestBandage", rest_bandage), ("RestTrain", rest_train), ("RestUpgrade", rest_upgrade),
]

ONLY = globals().get("ONLY")

scene = setup_scene()
icons = []

for name, build in BUILDERS:
    if ONLY and name not in ONLY: continue
    FACE = CAMERA_PITCH_3D if name in THREE_D else CAMERA_PITCH_2D
    icon = Icon(scene, name)
    build(icon)
    icons.append(icon)

os.makedirs(OUT, exist_ok=True)
for icon in icons:
    for other in icons:
        other.collection.hide_render = other is not icon

    aim(scene, icon.name in THREE_D)
    width, height = RENDER_SIZES.get(icon.name, (SIZE, SIZE))
    scene.render.resolution_x, scene.render.resolution_y = width, height
    scene.camera.data.ortho_scale = ORTHO_SCALE * max(width, height) / SIZE
    scene.render.filepath = os.path.join(OUT, icon.name + ".png")
    bpy.ops.render.render(write_still=True, scene=scene.name)

for icon in icons:
    icon.collection.hide_render = False

if not ONLY:
    bpy.data.libraries.write(os.path.join(ROOT, "art", "ArmoryIcons.blend"), {scene}, fake_user=True)
remove_scene(scene)
