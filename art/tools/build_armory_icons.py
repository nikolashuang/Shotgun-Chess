# Run inside Blender (Text Editor > Run Script) with art/ShotgunChessSprites.blend open.
# Builds one small drawing per class ability (plus the Siege card's castle) in a temporary scene,
# renders each one to art/armory/icons/<Name>.png, writes the scene to art/ArmoryIcons.blend
# and removes it again so the sprite file is left as it was. build_armory_art.py outlines and packs the renders.
import bpy, bmesh, math, os
from mathutils import Vector, Euler

ROOT = os.path.dirname(os.path.dirname(bpy.data.filepath))
OUT = os.path.join(ROOT, "art", "armory", "icons")
SCENE_NAME = "ArmoryIcons"

CREATED_MATERIALS = set()

SIZE = 64
ORTHO_SCALE = 2.9
# Most icons are drawn flat-on like the gun sprites; these keep the angled 3D camera
CAMERA_PITCH_2D = 90
CAMERA_PITCH_3D = 72
THREE_D = {"Siege", "GunslingerSpecial"}


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


def deadeye(icon):
    red = glow("Target", TARGET)
    icon.torus(red, (0, 0, 0), 0.75, 0.07, rotation=(FACE, 0, 0), segments=28)
    icon.torus(red, (0, 0, 0), 0.35, 0.05, rotation=(FACE, 0, 0), segments=20)
    for angle in (0, 90, 180, 270):
        a = math.radians(angle)
        x, up = math.cos(a) * 0.95, math.sin(a) * 0.95
        icon.cube(red, (x, -up * math.cos(math.radians(FACE)), up * math.sin(math.radians(FACE))), (0.1 if angle % 180 else 0.4, 0.1, 0.4 if angle % 180 else 0.1))
    icon.ball(glow("TargetCore", "F1D4AC"), (0, 0, 0), 0.1)


# Side-on service revolver modelled on the reference photo, barrel to the right
def fan_the_hammer(icon):
    steel = toon("Blued", "2A2830", "4E4A56", "8A8694")
    drum = toon("Drum", "3A3640", "5E5A66", "9A96A4")
    flute = toon("Flute", "1E1820", "2A2830", "3A3640")
    wood = toon("Grip", "3A2018", "6A3A24", "94573A")
    dx = -0.24

    def at(x, z, y=0):
        return (x + dx, y, z)

    # Barrel with a rounded muzzle, top rib and a half-moon front sight
    icon.rod(steel, at(0.2, 0.34), at(1.26, 0.34), 0.085, vertices=12)
    icon.ball(steel, at(1.26, 0.34), 0.085, scale=(0.6, 1, 1))
    icon.cube(steel, at(0.73, 0.42), (1.06, 0.05, 0.03))
    icon.cylinder(steel, at(1.16, 0.44), 0.06, 0.04, 10, rotation=(90, 0, 0))

    # Ejector rod under the barrel, ending in a round knob
    icon.rod(steel, at(0.22, 0.2), at(0.82, 0.2), 0.035, vertices=8)
    icon.ball(steel, at(0.84, 0.2), 0.055)

    # Fluted cylinder with a bevelled front
    icon.rod(drum, at(-0.18, 0.29), at(0.17, 0.29), 0.21, vertices=14)
    icon.cylinder(drum, at(0.2, 0.29), 0.21, 0.06, 14, rotation=(0, 90, 0), top=0.16)
    for z in (0.23, 0.35):
        icon.cube(flute, at(0.0, z, -0.22), (0.26, 0.02, 0.03))

    # Frame: top strap, rounded recoil shield and backstrap, bottom strap
    icon.cube(steel, at(0.0, 0.52), (0.5, 0.12, 0.07))
    icon.cube(steel, at(-0.31, 0.3), (0.2, 0.14, 0.44))
    icon.cylinder(steel, at(-0.34, 0.44), 0.14, 0.14, 14, rotation=(90, 0, 0))
    icon.cube(steel, at(-0.12, 0.1), (0.5, 0.12, 0.08))

    # Hammer spur curling back with a rounded tip
    icon.cube(steel, at(-0.44, 0.6), (0.1, 0.09, 0.22), rotation=(0, -40, 0))
    icon.ball(steel, at(-0.53, 0.69), 0.075)

    # Round trigger guard and a curved trigger
    icon.torus(steel, at(-0.12, -0.04), 0.14, 0.025, rotation=(90, 0, 0), segments=16)
    icon.cube(steel, at(-0.1, -0.01), (0.04, 0.05, 0.16), rotation=(0, 15, 0))

    # Wooden grip angled down and back, rounded at the butt, with a medallion
    icon.cube(wood, at(-0.55, -0.27), (0.34, 0.16, 0.74), rotation=(0, 20, 0))
    icon.cylinder(wood, at(-0.68, -0.62), 0.17, 0.16, 14, rotation=(90, 0, 0))
    icon.ball(wood, at(-0.36, -0.05), 0.1, scale=(1, 0.8, 1))
    icon.cylinder(toon("Medallion", *GOLD), at(-0.5, -0.12, -0.1), 0.05, 0.03, 8, rotation=(90, 0, 0))


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
    ("GunslingerPassive", deadeye), ("GunslingerSpecial", fan_the_hammer), ("GunslingerUltimate", bounty),
    ("OutlawPassive", opportunist), ("OutlawSpecial", conceal), ("OutlawUltimate", ambush),
    ("Siege", siege),
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
    scene.render.filepath = os.path.join(OUT, icon.name + ".png")
    bpy.ops.render.render(write_still=True, scene=scene.name)

for icon in icons:
    icon.collection.hide_render = False

if not ONLY:
    bpy.data.libraries.write(os.path.join(ROOT, "art", "ArmoryIcons.blend"), {scene}, fake_user=True)
remove_scene(scene)
