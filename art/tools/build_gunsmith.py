# Run inside Blender (Text Editor > Run Script) with art/ShotgunChessSprites.blend open.
# Builds the Wandering Gunsmith that plays over art/campaign/mystery/Gunsmith.png in a temporary scene:
# a bishop in a black drape beside the anvil, raising his hammer and bringing it down with a burst of sparks.
# Renders FRAMES frames to art/campaign/mystery/smith/Smith_<i>.png, then removes the scene again.
# build_mystery_art.py outlines, tints and packs them.
import bpy, bmesh, math, os
from mathutils import Vector, Euler, Matrix

ROOT = os.path.dirname(os.path.dirname(bpy.data.filepath))
OUT = os.path.join(ROOT, "art", "campaign", "mystery", "smith")
SCENE_NAME = "Gunsmith"

FRAMES = 8

# The render covers this part of the 1672x941 background, in background pixels: left, top, right, bottom
# One world unit is 100 background pixels; the render is a quarter of the background's resolution
REGION = (520, 220, 920, 620)
PIXELS_PER_UNIT = 100
RENDER_SCALE = 4

CREATED_MATERIALS = set()


def at(x, y, depth=0.0):
    center_x = (REGION[0] + REGION[2]) / 2
    center_y = (REGION[1] + REGION[3]) / 2
    return Vector(((x - center_x) / PIXELS_PER_UNIT, depth, (center_y - y) / PIXELS_PER_UNIT))


def linear(hex_color):
    def channel(c):
        c = c / 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return [channel(int(hex_color[i:i + 2], 16)) for i in (0, 2, 4)] + [1]


def toon(name, dark, base, light):
    name = "Smith" + name
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
    name = "Smith" + name
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


DRAPE = ("141016", "241C26", "3A2E3C")
HANDLE = ("3A2018", "6A3A24", "94573A")
IRON = ("2A2630", "5A5662", "8E8A96")
SPARKS = ["FFD27A", "FFF0B0"]


def mesh_object(collection, name, build, mat):
    bm = bmesh.new()
    build(bm)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    return obj


def frustum(collection, name, mat, bottom, top, height, segments=16):
    def build(bm):
        bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=bottom, radius2=top, depth=height)
        bmesh.ops.translate(bm, vec=(0, 0, height / 2), verts=bm.verts)

    return mesh_object(collection, name, build, mat)


def box(collection, name, mat, size, offset=(0, 0, 0)):
    def build(bm):
        result = bmesh.ops.create_cube(bm, size=1)
        bmesh.ops.scale(bm, vec=size, verts=result["verts"])
        bmesh.ops.translate(bm, vec=offset, verts=result["verts"])

    return mesh_object(collection, name, build, mat)


# The bishop stands left of the anvil, a little smaller than his board piece so he fits beside it
BISHOP_BASE = (640, 588)
BISHOP_SCALE = 1.05
# His draped arm swings from the shoulder with the hammer in hand; the head comes down on the anvil's face
SHOULDER = (680, 452)
ARM_LENGTH = 0.38
HANDLE_LENGTH = 0.78
STRIKE_POINT = (790, 436)
# Arm angle in degrees from pointing straight right, per frame: wind up, hold, strike, rebound
SWING = [60, 105, 125, 125, 80, 17, 17, 40]
# A snapped shotgun lying across the anvil's face: barrel halves and the loose stock, in background pixels and degrees
GUN_TOP = 438
BROKEN_GUN = [
    # (name, colours, from x, to x, height above GUN_TOP, thickness, tilt)
    ("Barrel", "Iron", 752, 806, 0, 0.1, 0),
    ("Muzzle", "Iron", 812, 858, 4, 0.1, 9),
    ("Pump", "Handle", 770, 798, -6, 0.16, 0),
    ("Stock", "Handle", 862, 912, 2, 0.2, -14),
]
STRIKE_FRAMES = {5, 6}


class Smith:
    def __init__(self, scene):
        self.collection = bpy.data.collections.new("Smith")
        scene.collection.children.link(self.collection)
        col = self.collection

        data = bpy.data.objects["Bishop"].data.copy()
        data.materials[0] = bpy.data.materials["Piece"]
        self.bishop = bpy.data.objects.new("SmithBishop", data)
        col.objects.link(self.bishop)

        drape = toon("Drape", *DRAPE)
        # A black cloth from his shoulders to the ground, flaring at the hem, with a cowl around his neck
        self.drape = [
            frustum(col, "Drape", drape, 0.66, 0.3, 1.38, 18),
            frustum(col, "Cowl", drape, 0.36, 0.22, 0.18, 18),
        ]

        handle = toon("Handle", *HANDLE)
        iron = toon("Iron", *IRON)
        # Built pointing along +X from the pivot, so turning about Y swings it up and down
        reach = ARM_LENGTH + HANDLE_LENGTH
        self.hammer = [
            frustum(col, "Sleeve", drape, 0.1, 0.08, ARM_LENGTH + 0.05, 10),
            box(col, "Handle", handle, (HANDLE_LENGTH, 0.07, 0.07), (ARM_LENGTH + HANDLE_LENGTH / 2 - 0.05, 0, 0)),
            box(col, "Head", iron, (0.2, 0.2, 0.36), (reach - 0.05, 0, 0)),
        ]
        # The sleeve is built standing up; lay it along +X like the rest of the hammer
        sleeve = self.hammer[0].data
        sleeve.transform(Euler((0, math.radians(90), 0)).to_matrix().to_4x4())

        materials = {"Iron": iron, "Handle": handle}
        self.gun = []
        for name, colours, x0, x1, rise, thickness, tilt in BROKEN_GUN:
            length = (x1 - x0) / PIXELS_PER_UNIT
            part = box(col, name, materials[colours], (length, thickness, thickness))
            center = at((x0 + x1) / 2, GUN_TOP - rise - thickness * PIXELS_PER_UNIT / 2, -0.3)
            part.matrix_world = Matrix.Translation(center) @ Euler((0, math.radians(-tilt), 0)).to_matrix().to_4x4()
            self.gun.append(part)

        spark = [glow(f"Spark{i}", c) for i, c in enumerate(SPARKS)]
        self.sparks = []
        for i in range(7):
            self.sparks.append(mesh_object(col, "Spark", lambda bm: bmesh.ops.create_cube(bm, size=0.06), spark[i % 2]))

    def pose(self, i):
        t = i / FRAMES
        angle = SWING[i]
        # He leans into the blow and settles back as the hammer rises
        lean = -4 if i in STRIKE_FRAMES else 2
        bob = 0.015 * math.sin(t * 2 * math.pi)

        base = at(*BISHOP_BASE)
        body = Matrix.Translation(base) @ Euler((math.radians(10), math.radians(lean), 0)).to_matrix().to_4x4()
        self.bishop.matrix_world = body @ Matrix.Diagonal((BISHOP_SCALE, BISHOP_SCALE, BISHOP_SCALE * (1 + bob), 1))
        self.drape[0].matrix_world = body @ Matrix.Translation((0, -0.02, 0)) @ Matrix.Diagonal((BISHOP_SCALE, BISHOP_SCALE, BISHOP_SCALE, 1))
        self.drape[1].matrix_world = body @ Matrix.Translation((0, -0.02, 1.3 * BISHOP_SCALE)) @ Matrix.Diagonal((BISHOP_SCALE, BISHOP_SCALE, BISHOP_SCALE, 1))

        pivot = at(*SHOULDER, -0.4)
        swing = Matrix.Translation(pivot) @ Euler((0, math.radians(-angle), 0)).to_matrix().to_4x4()
        for part in self.hammer:
            part.matrix_world = swing

        strike = at(*STRIKE_POINT, -0.4)
        for k, spark in enumerate(self.sparks):
            spark.hide_render = i not in STRIKE_FRAMES
            a = math.radians(20 + k * 23)
            reach = 0.25 + 0.25 * (i - 5) + 0.05 * (k % 3)
            spark.location = strike + Vector((math.cos(a) * reach, -0.1, math.sin(a) * reach * 0.8))


def setup_scene():
    old = bpy.data.scenes.get(SCENE_NAME)
    if old:
        remove_scene(old)

    scene = bpy.data.scenes.new(SCENE_NAME)
    scene.render.engine = bpy.data.scenes[0].render.engine
    scene.render.resolution_x = (REGION[2] - REGION[0]) // RENDER_SCALE
    scene.render.resolution_y = (REGION[3] - REGION[1]) // RENDER_SCALE
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.filter_size = 0
    scene.view_settings.view_transform = "Standard"

    scene.world = bpy.data.worlds.new("SmithWorld")
    scene.world.color = (0.02, 0.02, 0.02)

    camera_data = bpy.data.cameras.new("SmithCam")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = max(REGION[2] - REGION[0], REGION[3] - REGION[1]) / PIXELS_PER_UNIT
    camera = bpy.data.objects.new("SmithCam", camera_data)
    camera.rotation_euler = (math.radians(90), 0, 0)
    camera.location = (0, -30, 0)
    scene.collection.objects.link(camera)
    scene.camera = camera

    # Lit from the forge on the right
    sun_data = bpy.data.lights.new("SmithSun", "SUN")
    sun_data.energy = 3
    sun = bpy.data.objects.new("SmithSun", sun_data)
    sun.rotation_euler = (math.radians(60), math.radians(30), math.radians(40))
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


scene = setup_scene()
smith = Smith(scene)
os.makedirs(OUT, exist_ok=True)

try:
    for i in range(FRAMES):
        smith.pose(i)
        scene.render.filepath = os.path.join(OUT, f"Smith_{i}.png")
        bpy.ops.render.render(write_still=True, scene=scene.name)
finally:
    remove_scene(scene)
