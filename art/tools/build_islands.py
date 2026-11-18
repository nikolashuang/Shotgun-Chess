# Run inside Blender (Text Editor > Run Script) with art/ShotgunChessSprites.blend open.
# Builds the five floating campaign islands plus the chain and padlock layers in a temporary scene,
# renders each one to art/campaign/islands/<Name>.png, writes the scene to art/CampaignIslands.blend
# and removes it again so the sprite file is left as it was. build_campaign_art.py outlines and packs the renders.
import bpy, bmesh, math, os, random
from mathutils import Vector, Euler

ROOT = os.path.dirname(os.path.dirname(bpy.data.filepath))
OUT = os.path.join(ROOT, "art", "campaign", "islands")
SCENE_NAME = "CampaignIslands"

# Materials made by this script, so cleanup never touches the sprite file's own
CREATED_MATERIALS = set()

WIDTH, HEIGHT = 160, 160
ORTHO_SCALE = 6.6
CAMERA_PITCH = 62
AIM_Z = 0.28


def linear(hex_color):
    def channel(c):
        c = c / 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return [channel(int(hex_color[i:i + 2], 16)) for i in (0, 2, 4)] + [1]


# Toon material: three flat tones picked by how lit the surface is, like the piece sprites
def toon(name, dark, base, light):
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


# Shared palette
ROCK = ("3A2E3C", "5E4A5C", "7A6474")
DIRT = ("4A2F2A", "6E4436", "8A5A44")
WOOD = ("4A2F25", "7A4B33", "A0683F")
STONE = ("5A5260", "8A8290", "B5AEB5")
CREAM = ("B59A7A", "E9E3D6", "FFF8EC")
RUST = ("5E2F2A", "9C574B", "C8644F")
GOLD = ("8A5A2A", "D49A77", "F1D4AC")
STEEL = ("3E3A44", "7A7680", "B8B4BC")
WATER = ("3D5F8A", "5E8FC2", "A8D0F0")
MIST = ("8FB8DC", "C8E2F4", "F4FAFF")


def new_object(name, build, location, rotation, scale):
    bm = bmesh.new()
    build(bm)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    obj.location = location
    obj.rotation_euler = Euler([math.radians(r) for r in rotation])
    obj.scale = scale

    return obj


def build_torus(bm, major, minor, major_segments, minor_segments):
    rings = []

    for i in range(major_segments):
        a = 2 * math.pi * i / major_segments
        ring = []

        for j in range(minor_segments):
            b = 2 * math.pi * j / minor_segments
            radius = major + minor * math.cos(b)
            ring.append(bm.verts.new((radius * math.cos(a), radius * math.sin(a), minor * math.sin(b))))

        rings.append(ring)

    for i in range(major_segments):
        for j in range(minor_segments):
            a, b = rings[i], rings[(i + 1) % major_segments]
            bm.faces.new((a[j], b[j], b[(j + 1) % minor_segments], a[(j + 1) % minor_segments]))


class Island:
    def __init__(self, scene, name, seed):
        self.name = name
        self.random = random.Random(seed)
        self.collection = bpy.data.collections.new(name)
        scene.collection.children.link(self.collection)

    def add(self, obj, mat):
        self.collection.objects.link(obj)
        obj.data.materials.append(mat)

        return obj

    def jitter(self, obj, amount):
        for vertex in obj.data.vertices:
            vertex.co += Vector([self.random.uniform(-amount, amount) for _ in range(3)])

    def cube(self, mat, location, size, rotation=(0, 0, 0)):
        build = lambda bm: bmesh.ops.create_cube(bm, size=1)
        return self.add(new_object("Cube", build, location, rotation, size), mat)

    def cylinder(self, mat, location, radius, depth, vertices=8, rotation=(0, 0, 0)):
        return self.cone(mat, location, radius, depth, vertices, top=radius, rotation=rotation)

    def cone(self, mat, location, radius, depth, vertices=8, top=0.0, rotation=(0, 0, 0)):
        build = lambda bm: bmesh.ops.create_cone(bm, cap_ends=True, segments=vertices, radius1=radius, radius2=top, depth=depth)
        return self.add(new_object("Cone", build, location, rotation, (1, 1, 1)), mat)

    def ball(self, mat, location, radius, scale=(1, 1, 1)):
        build = lambda bm: bmesh.ops.create_icosphere(bm, subdivisions=1, radius=radius)
        return self.add(new_object("Ball", build, location, (0, 0, 0), scale), mat)

    def torus(self, mat, location, major, minor, rotation=(0, 0, 0), scale=(1, 1, 1)):
        build = lambda bm: build_torus(bm, major, minor, 8, 4)
        return self.add(new_object("Torus", build, location, rotation, scale), mat)

    # Floating rock: a grass cap over a dirt band over a jagged rock cone, with loose rocks underneath
    def base(self, top, radius=2.35):
        rock = toon("Rock", *ROCK)
        dirt = toon("Dirt", *DIRT)

        cap = self.cylinder(top, (0, 0, 0), radius, 0.16, vertices=11)
        self.jitter(cap, 0.04)
        band = self.cylinder(dirt, (0, 0, -0.26), radius * 0.97, 0.36, vertices=11)
        self.jitter(band, 0.06)
        under = self.cone(rock, (0, 0, -1.7), radius * 0.95, 2.6, vertices=11, top=0.12, rotation=(180, 0, 0))
        self.jitter(under, 0.18)

        for x, z, size in ((-1.9, -2.1, 0.32), (1.7, -2.5, 0.24), (0.6, -3.0, 0.18)):
            pebble = self.cone(rock, (x, 0.2, z), size, size * 2, vertices=5, rotation=(180, 0, 0))
            self.jitter(pebble, 0.05)

    def tree(self, location, height, leaves, trunk=None):
        x, y, z = location
        self.cylinder(trunk or toon("Wood", *WOOD), (x, y, z + height * 0.25), 0.09, height * 0.5, vertices=6)
        self.cone(leaves, (x, y, z + height * 0.55), height * 0.32, height * 0.55, vertices=7)
        self.cone(leaves, (x, y, z + height * 0.85), height * 0.24, height * 0.45, vertices=7)

    def house(self, location, size, wall, roof):
        x, y, z = location
        w, d, h = size
        self.cube(wall, (x, y, z + h / 2), (w, d, h))
        # A three sided cylinder turned on its side makes a gable roof
        roof_obj = self.cylinder(roof, (x, y, z + h + 0.12), w * 0.62, d * 1.1, vertices=3, rotation=(90, -90, 0))
        roof_obj.scale = (0.55, 1, 1)
        self.cube(toon("Shadow", "1E1820", "271F29", "332A35"), (x, y - d / 2 - 0.01, z + 0.18), (0.16, 0.02, 0.32))

    # A stream from source to the island's front rim, then a fall that hangs just in front of the rock face
    # and ends in a puff of mist, so it reads as one piece of water from the top down
    def waterfall(self, source, rim_x, length, width=0.42):
        water = toon("Water", *WATER)
        mist = toon("Mist", *MIST)

        # Front rim of the jittered grass cap, nudged out so the fall sits in front of the rock
        rim_y = -math.sqrt(2.35 ** 2 - rim_x ** 2) - 0.08
        sx, sy = source
        dx, dy = rim_x - sx, rim_y - sy
        stream_length = math.hypot(dx, dy)
        angle = math.degrees(math.atan2(-dx, dy))

        self.cube(water, ((sx + rim_x) / 2, (sy + rim_y) / 2, 0.09), (width, stream_length, 0.03), rotation=(0, 0, angle))
        # Lip that rolls over the rim edge
        self.cube(water, (rim_x, rim_y, 0.0), (width, 0.12, 0.2))
        self.cube(water, (rim_x, rim_y - 0.03, 0.08 - length / 2), (width, 0.05, length))

        bottom = 0.08 - length
        for offset, size in ((-0.16, 0.16), (0.0, 0.22), (0.17, 0.15)):
            self.ball(mist, (rim_x + offset, rim_y - 0.05, bottom + size * 0.3), size, scale=(1, 0.6, 0.8))

        return angle, rim_y


def training(island):
    grass = toon("TrainingGrass", "3F5A2E", "6E8B3D", "9DB45A")
    blue = toon("Banner", "243A6B", "3F5A9C", "6F8FD0")
    island.base(grass)

    stone = toon("Stone", *STONE)
    # Castle wall with crenellations and two towers
    island.cube(stone, (0, 1.2, 0.5), (3.4, 0.4, 1.0))
    for i in range(7):
        island.cube(stone, (-1.5 + i * 0.5, 1.2, 1.1), (0.24, 0.42, 0.22))
    for x in (-1.75, 1.75):
        island.cylinder(stone, (x, 1.1, 0.8), 0.42, 1.6, vertices=8)
        island.cone(blue, (x, 1.1, 1.95), 0.5, 0.7, vertices=8)
    island.cube(toon("Wood", *WOOD), (0, 0.98, 0.35), (0.45, 0.05, 0.7))
    for x in (-0.9, 0.9):
        island.cube(blue, (x, 0.98, 0.6), (0.32, 0.03, 0.6))

    # Practice board
    light = toon("TileLight", *CREAM)
    dark = toon("TileDark", *RUST)
    for i in range(4):
        for j in range(3):
            island.cube(light if (i + j) % 2 == 0 else dark, (-0.6 + i * 0.4, -0.2 - j * 0.4, 0.09), (0.4, 0.4, 0.04))

    # Targets and dummies
    red = toon("TargetRed", *RUST)
    for x in (1.25, 1.75):
        island.cube(toon("Wood", *WOOD), (x, -0.3, 0.3), (0.05, 0.05, 0.6))
        island.cylinder(light, (x, -0.33, 0.6), 0.24, 0.05, vertices=10, rotation=(90, 0, 0))
        island.cylinder(red, (x, -0.36, 0.6), 0.13, 0.05, vertices=10, rotation=(90, 0, 0))
    for x in (-1.5, -1.15):
        island.cylinder(toon("Wood", *WOOD), (x, -0.9, 0.3), 0.1, 0.6, vertices=6)
        island.ball(toon("Wood", *WOOD), (x, -0.9, 0.7), 0.14)


def forest(island):
    grass = toon("ForestGrass", "2E4A2A", "4F7A35", "7FA84A")
    leaves = toon("Leaves", "1F3A2A", "3A6B3A", "5E9A48")
    leaves_dark = toon("LeavesDark", "17302A", "2A5233", "467A3E")
    island.base(grass)

    for x, y, h, mat in ((-1.6, 0.9, 1.9, leaves), (-0.7, 1.4, 2.3, leaves_dark), (0.4, 1.3, 2.0, leaves),
                         (1.4, 1.0, 2.4, leaves_dark), (-1.9, -0.3, 1.5, leaves_dark), (1.9, 0.1, 1.6, leaves)):
        island.tree((x, y, 0.05), h, mat)

    # Tent and campfire
    tent = island.cone(toon("Canvas", "8A7358", "C9B08A", "E9D7B5"), (-0.6, -0.6, 0.4), 0.6, 0.8, vertices=4, rotation=(0, 0, 45))
    tent.scale = (1.2, 1, 1)
    island.cylinder(toon("Wood", *WOOD), (0.2, -1.0, 0.08), 0.2, 0.06, vertices=6)
    island.cone(glow("Fire", "F1A04A"), (0.2, -1.0, 0.25), 0.13, 0.3, vertices=5)

    # Stream running off the front edge as a waterfall, with a plank bridge over it
    angle, _ = island.waterfall((0.9, 0.2), 1.3, 1.25)
    island.cube(toon("Wood", *WOOD), (1.03, -0.5, 0.14), (0.9, 0.3, 0.04), rotation=(0, 0, angle))


def cliffside(island):
    ground = toon("ClayGround", "6E4436", "A0683F", "C98F5E")
    cliff = toon("Cliff", "4A3348", "6E4F68", "9A7590")
    island.base(ground)

    for x, y, h, r in ((-1.5, 0.9, 2.4, 0.65), (-0.4, 1.4, 1.7, 0.55), (1.5, 0.8, 2.1, 0.6)):
        spire = island.cone(cliff, (x, y, h / 2), r, h, vertices=7, top=r * 0.45)
        island.jitter(spire, 0.09)

    # Rope bridge between two spires
    wood = toon("Wood", *WOOD)
    for i in range(10):
        t = i / 9
        x = -1.0 + t * 2.0
        sag = math.sin(t * math.pi) * 0.35
        island.cube(wood, (x, 0.85, 1.75 - sag), (0.16, 0.36, 0.05))
    for y in (0.67, 1.03):
        island.cube(toon("Rope", *GOLD), (0, y, 1.75), (2.0, 0.02, 0.02))

    # Shack on stilts
    for x in (0.55, 1.25):
        island.cube(wood, (x, -0.4, 0.3), (0.07, 0.07, 0.6))
    island.house((0.9, -0.4, 0.55), (0.9, 0.7, 0.55), toon("Plank", *WOOD), toon("Roof", *RUST))

    # Spring at the foot of the left spire running off the cliff face
    island.waterfall((-1.2, 0.3), -1.0, 1.3, width=0.36)
    island.cube(toon("Crate", *GOLD), (-0.6, -0.5, 0.2), (0.32, 0.32, 0.32))


def outskirts(island):
    sand = toon("Sand", "A0683F", "D49A77", "F1D4AC")
    mesa = toon("Mesa", "6E3A2E", "9C574B", "C8644F")
    wood = toon("Wood", *WOOD)
    island.base(sand)

    for x, y, h, r in ((-1.4, 1.35, 1.6, 0.55), (0.2, 1.6, 2.1, 0.45)):
        rock = island.cylinder(mesa, (x, y, h / 2), r, h, vertices=7)
        island.jitter(rock, 0.06)

    # Windmill
    island.cone(wood, (1.3, 0.8, 1.0), 0.32, 2.0, vertices=4, top=0.12, rotation=(0, 0, 45))
    for angle in (20, 110):
        island.cube(toon("Blade", *CREAM), (1.3, 0.55, 2.0), (0.12, 0.03, 1.4), rotation=(0, angle + 20, 0))

    # Water tower
    for x, y in ((-0.25, 0.2), (0.25, 0.2), (-0.25, 0.6), (0.25, 0.6)):
        island.cube(wood, (x - 0.4, y, 0.5), (0.06, 0.06, 1.0))
    island.cylinder(toon("Tank", *WOOD), (-0.4, 0.4, 1.2), 0.42, 0.55, vertices=8)
    island.cone(toon("Roof", *RUST), (-0.4, 0.4, 1.6), 0.48, 0.3, vertices=8)

    island.house((-1.3, -0.5, 0.06), (0.9, 0.7, 0.6), toon("Plank", *WOOD), toon("Roof", *RUST))
    island.house((0.8, -0.6, 0.06), (0.8, 0.6, 0.5), toon("Plank", *WOOD), toon("RoofDark", "3A2420", "5E3A2E", "7A4B33"))

    # Fence along the front edge and a cactus
    for i in range(6):
        island.cube(wood, (-1.0 + i * 0.4, -1.55, 0.2), (0.07, 0.07, 0.4))
    island.cube(wood, (0, -1.55, 0.3), (2.1, 0.04, 0.05))
    cactus = toon("Cactus", "2E4A2A", "4F7A35", "7FA84A")
    island.cylinder(cactus, (1.8, -0.9, 0.35), 0.1, 0.7, vertices=6)
    island.cylinder(cactus, (1.95, -0.9, 0.45), 0.07, 0.3, vertices=6)


def gravehollow(island):
    ground = toon("GraveGround", "3A2F48", "5E4E72", "80709A")
    stone = toon("GraveStone", "3E3A48", "6E6878", "9A94A4")
    purple = glow("SoulGlow", "C08AF0")
    island.base(ground)

    # Chapel with spires and glowing windows
    chapel = toon("Chapel", "3A3448", "5E5674", "867C9C")
    island.cube(chapel, (0.6, 1.1, 0.7), (1.4, 0.8, 1.4))
    for x in (0.05, 1.15):
        island.cylinder(chapel, (x, 1.1, 1.2), 0.2, 2.4, vertices=6)
        island.cone(chapel, (x, 1.1, 2.7), 0.25, 0.7, vertices=6)
    island.cone(chapel, (0.6, 1.1, 1.75), 0.75, 0.7, vertices=4, rotation=(0, 0, 45))
    for x in (0.3, 0.9):
        island.cube(purple, (x, 0.69, 0.85), (0.18, 0.02, 0.4))
    island.cube(purple, (0.6, 0.69, 1.25), (0.22, 0.02, 0.22))

    # Gravestones
    for x, y in ((-1.6, 0.2), (-1.0, 0.0), (-0.4, -0.3), (-1.4, -0.6), (-0.8, -0.9), (0.6, -0.6), (1.3, -0.4)):
        island.cube(stone, (x, y, 0.25), (0.28, 0.12, 0.4))
        island.cylinder(stone, (x, y, 0.45), 0.14, 0.12, vertices=8, rotation=(90, 0, 0))

    # Dead tree
    bark = toon("DeadBark", "1E1820", "3A2E3C", "5E4A5C")
    island.cylinder(bark, (-1.4, 1.0, 0.8), 0.12, 1.6, vertices=5)
    for angle, length in ((35, 0.8), (-40, 0.7), (60, 0.5)):
        branch = island.cylinder(bark, (-1.4, 1.0, 1.3), 0.05, length, vertices=4, rotation=(0, angle, 0))
        branch.location.x += math.sin(math.radians(angle)) * length / 2
        branch.location.z += math.cos(math.radians(angle)) * length / 2

    # Soul wisps
    for x, y, z in ((-0.2, -1.2, 0.5), (1.6, 0.2, 0.9), (-1.9, -0.2, 0.7)):
        island.ball(purple, (x, y, z), 0.09)


# Chains cross the island diagonally with a padlock in front; each is its own layer for the unlock animation
def chain(island, start, end, links):
    steel = toon("Chain", *STEEL)
    start, end = Vector(start), Vector(end)
    direction = (end - start).normalized()
    angle = math.degrees(math.atan2(direction.z, direction.x))

    for i in range(links):
        t = i / (links - 1)
        # Alternate links face the camera and side on, like a real chain
        rotation = (90 if i % 2 == 0 else 0, -angle, 0)
        island.torus(steel, start.lerp(end, t), 0.2, 0.06, rotation=rotation, scale=(1.4, 1, 1))


def padlock(island):
    gold = toon("LockBody", *GOLD)
    island.cube(gold, (0, -2.2, 0.25), (0.9, 0.3, 0.75))
    island.torus(toon("Shackle", *STEEL), (0, -2.2, 0.65), 0.3, 0.08, rotation=(90, 0, 0))
    keyhole = toon("Keyhole", "1E1820", "1E1820", "271F29")
    island.cylinder(keyhole, (0, -2.37, 0.28), 0.08, 0.05, vertices=6, rotation=(90, 0, 0))
    island.cube(keyhole, (0, -2.37, 0.13), (0.06, 0.05, 0.2))


def setup_scene():
    old = bpy.data.scenes.get(SCENE_NAME)
    if old:
        remove_scene(old)

    scene = bpy.data.scenes.new(SCENE_NAME)
    scene.render.engine = bpy.data.scenes[0].render.engine
    scene.render.resolution_x = WIDTH
    scene.render.resolution_y = HEIGHT
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.filter_size = 0
    scene.view_settings.view_transform = "Standard"

    scene.world = bpy.data.worlds.new("IslandWorld")
    scene.world.color = (0.02, 0.02, 0.02)

    camera_data = bpy.data.cameras.new("IslandCam")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = ORTHO_SCALE
    camera = bpy.data.objects.new("IslandCam", camera_data)
    scene.collection.objects.link(camera)
    pitch = math.radians(CAMERA_PITCH)
    camera.rotation_euler = (pitch, 0, 0)
    camera.location = Vector((0, 0, AIM_Z)) - Vector((0, math.sin(pitch), -math.cos(pitch))) * 20
    scene.camera = camera

    sun_data = bpy.data.lights.new("IslandSun", "SUN")
    sun_data.energy = 3
    sun = bpy.data.objects.new("IslandSun", sun_data)
    sun.rotation_euler = (math.radians(50), math.radians(-35), math.radians(-25))
    scene.collection.objects.link(sun)

    return scene


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


def render(scene, islands):
    os.makedirs(OUT, exist_ok=True)

    for island in islands:
        for other in islands:
            other.collection.hide_render = other is not island

        scene.render.filepath = os.path.join(OUT, island.name + ".png")
        bpy.ops.render.render(write_still=True, scene=scene.name)


scene = setup_scene()

builders = [("Training", training), ("Forest", forest), ("Cliffside", cliffside), ("Outskirts", outskirts), ("Gravehollow", gravehollow)]
islands = []

for seed, (name, build) in enumerate(builders):
    island = Island(scene, name, seed + 1)
    build(island)
    islands.append(island)

chain_a = Island(scene, "ChainA", 10)
chain(chain_a, (-2.9, -1.7, 2.4), (2.9, -1.7, -1.4), 15)
islands.append(chain_a)

chain_b = Island(scene, "ChainB", 11)
chain(chain_b, (2.9, -1.7, 2.4), (-2.9, -1.7, -1.4), 15)
islands.append(chain_b)

lock = Island(scene, "Lock", 12)
padlock(lock)
islands.append(lock)

render(scene, islands)
for island in islands:
    island.collection.hide_render = False

bpy.data.libraries.write(os.path.join(ROOT, "art", "CampaignIslands.blend"), {scene}, fake_user=True)
remove_scene(scene)
