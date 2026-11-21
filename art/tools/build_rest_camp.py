# Run inside Blender (Text Editor > Run Script) with art/ShotgunChessSprites.blend open.
# Builds the Rest Site campfire that plays over art/campaign/RestCamp.png in a temporary scene:
# a crackling fire in the stone pit, the King sitting on the right log, and either his party (two pawns on the left log,
# a knight and a bishop on the stumps) or the Fallen Knight on the left log once he has joined the run.
# Renders FRAMES frames of each version to art/campaign/rest/<Version>_<i>.png, then removes the scene again.
# build_rest_art.py outlines, tints and packs them.
import bpy, bmesh, math, os
from mathutils import Vector, Euler, Matrix

ROOT = os.path.dirname(os.path.dirname(bpy.data.filepath))
OUT = os.path.join(ROOT, "art", "campaign", "rest")
SCENE_NAME = "RestCamp"

FRAMES = 8

# The render covers this part of the 1672x941 background, in background pixels: left, top, right, bottom
# One world unit is 100 background pixels; the render is a quarter of the background's resolution
REGION = (480, 250, 1260, 650)
PIXELS_PER_UNIT = 100
RENDER_SCALE = 4

CREATED_MATERIALS = set()


# Background pixel position to a world position (x, depth, z); depth is toward the camera when negative
def at(x, y, depth=0.0):
    center_x = (REGION[0] + REGION[2]) / 2
    center_y = (REGION[1] + REGION[3]) / 2
    return Vector(((x - center_x) / PIXELS_PER_UNIT, depth, (center_y - y) / PIXELS_PER_UNIT))


def linear(hex_color):
    def channel(c):
        c = c / 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return [channel(int(hex_color[i:i + 2], 16)) for i in (0, 2, 4)] + [1]


# Three tone toon shading, like the sprites and icons
def toon(name, dark, base, light):
    name = "Camp" + name
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
    name = "Camp" + name
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


WOOD = ("3A2018", "6A3A24", "94573A")
BARK = ("2A1810", "4A2C1C", "6A4028")
FALLEN = ("22333A", "3E5A63", "5E8A94")
FLAME_COLORS = ["B8341E", "F0782A", "FFC24A", "FFF0B0"]
EMBER = "FFB040"
AURA = ["1F6F72", "2E9C8E", "7FE3C8"]


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


def cone(collection, name, mat, radius, height, segments=6):
    def build(bm):
        bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=radius, radius2=0, depth=height)
        # Base at the origin so scaling the height grows the flame upward
        bmesh.ops.translate(bm, vec=(0, 0, height / 2), verts=bm.verts)

    return mesh_object(collection, name, build, mat)


def ball(collection, name, mat, radius):
    return mesh_object(collection, name, lambda bm: bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=4, radius=radius), mat)


def log(collection, name, mat, length, radius):
    def build(bm):
        bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=radius, radius2=radius, depth=length)

    return mesh_object(collection, name, build, mat)


# A copy of one of the sprite pieces, standing on its base at the origin
def piece(collection, name, source, materials=None, flip=False):
    data = bpy.data.objects[source].data.copy()

    if materials:
        for i, mat in enumerate(materials):
            if mat and i < len(data.materials):
                data.materials[i] = mat

    obj = bpy.data.objects.new(name, data)
    collection.objects.link(obj)
    obj["flip"] = flip
    return obj


# Pieces are a bit under half their board size so they sit on the logs at the background's scale
PIECE_SCALE = 0.48
# Tipped toward the camera so the tops of the pieces show, like the background's slightly raised view
PIECE_TIP = 14


# Places a piece with its base at a background pixel, breathing with the frame: t is 0 to 1, phase offsets each piece
def pose_piece(obj, x, y, t, phase, depth=0.0, yaw=0.0):
    breath = math.sin((t + phase) * 2 * math.pi)
    sx = PIECE_SCALE * (1 - 0.015 * breath) * (-1 if obj["flip"] else 1)
    sz = PIECE_SCALE * (1 + 0.03 * breath)
    obj.matrix_world = Matrix.Translation(at(x, y, depth)) @ Euler((math.radians(PIECE_TIP), 0, yaw)).to_matrix().to_4x4() @ Matrix.Diagonal((sx, PIECE_SCALE, sz, 1))


# Fire in the stone pit: crossed logs with tongues of flame flickering over them and embers rising
FIRE_BASE = (866, 585)
TONGUES = [
    # (x offset, depth offset, radius, height, colour index, phase)
    (-0.42, 0.05, 0.2, 0.6, 0, 0.0),
    (0.4, 0.05, 0.2, 0.65, 0, 0.4),
    (-0.2, -0.05, 0.26, 1.0, 1, 0.15),
    (0.2, -0.05, 0.26, 1.05, 1, 0.65),
    (0.0, -0.1, 0.28, 1.35, 1, 0.3),
    (-0.1, -0.15, 0.18, 0.85, 2, 0.8),
    (0.12, -0.15, 0.18, 0.8, 2, 0.5),
    (0.0, -0.2, 0.12, 0.5, 3, 0.2),
]
EMBERS = 5
# The Fallen Knight's flame, matching build_effects.py's board aura: (x, z of the base, height, colour index)
# in unscaled piece units; the right half is listed and mirrored, plus one peak over his head
AURA_RIGHT = [(0.82, 0.1, 0.65, 2), (0.86, 0.5, 0.7, 0), (0.82, 0.9, 0.75, 1), (0.7, 1.3, 0.8, 0), (0.5, 1.7, 0.85, 1), (0.24, 2.0, 0.95, 0)]
# Dark tongues between each pair fill the gaps so the flame reads as one unbroken wall
AURA_FILL = [((a[0] + b[0]) / 2 - 0.05, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2 + 0.1, 0) for a, b in zip(AURA_RIGHT, AURA_RIGHT[1:])]
# Solid flame behind his whole body so the aura is one filled shape: (z of the base, height, radius, colour index)
# Brighter than his board aura so his dark body still stands out against it at the fire
AURA_BODY = [(0.0, 1.9, 1.0, 1), (0.7, 1.9, 0.85, 1), (1.4, 1.4, 0.65, 2)]
AURA_FLAMES = [(x * side, z, h, c) for x, z, h, c in AURA_FILL + AURA_RIGHT for side in (-1, 1)] + [(0.0, 2.15, 1.1, 1)]


class Camp:
    def __init__(self, scene, version):
        self.version = version
        self.collection = bpy.data.collections.new("Camp_" + version)
        scene.collection.children.link(self.collection)
        col = self.collection

        piece_mat = bpy.data.materials["Piece"]
        wood = toon("Wood", *WOOD)
        bark = toon("Bark", *BARK)

        base = at(*FIRE_BASE, -1.2)
        self.logs = []
        for angle in (25, -25):
            stick = log(col, "FireLog", bark if angle > 0 else wood, 0.85, 0.08)
            stick.matrix_world = Matrix.Translation(base + Vector((0, 0, 0.05))) @ Euler((0, math.radians(90 + angle), math.radians(12))).to_matrix().to_4x4()

        flames = [glow(f"Flame{i}", c) for i, c in enumerate(FLAME_COLORS)]
        self.tongues = [(cone(col, "Flame", flames[c], r, 1.0), dx, dz, h, ph) for dx, dz, r, h, c, ph in TONGUES]
        self.embers = [ball(col, "Ember", glow("Ember", EMBER), 0.04) for _ in range(EMBERS)]
        self.fire_base = base

        self.king = piece(col, "King", "King", [piece_mat, bpy.data.materials["Gold"]])

        if version == "Knight":
            fallen = toon("Fallen", *FALLEN)
            eye = glow("FallenEye", "6CC4FF")
            # Facing the fire, so the left-log knight is mirrored
            self.knight = piece(col, "FallenKnight", "Knight", [fallen, eye], flip=True)
            auras = [glow(f"Aura{i}", c) for i, c in enumerate(AURA)]
            self.aura = [(cone(col, "Aura", auras[c], 0.32 * PIECE_SCALE, 1.0), x, z, h, i) for i, (x, z, h, c) in enumerate(AURA_FLAMES)]
            self.aura_body = [(cone(col, "AuraBody", auras[c], r * PIECE_SCALE, 1.0, 8), z, h, i) for i, (z, h, r, c) in enumerate(AURA_BODY)]
        else:
            self.pawns = [piece(col, f"Pawn{i}", "Pawn", [piece_mat]) for i in range(2)]
            self.knight = piece(col, "Knight", "Knight", [piece_mat, bpy.data.materials["Gunmetal"]], flip=True)
            self.bishop = piece(col, "Bishop", "Bishop", [piece_mat])

    def pose(self, t):
        # The King sits on the right log, turned a little toward the fire
        pose_piece(self.king, 1050, 500, t, 0.0)

        if self.version == "Knight":
            pose_piece(self.knight, 690, 500, t, 0.35, yaw=math.radians(20))
            # The same close-wrapped flame as his board aura, burning up from his outline behind him
            base = at(690, 500) + Vector((0, 0.3, 0))
            for obj, x, z, h, i in self.aura:
                phase = math.sin((t + i * 0.37) * 2 * math.pi)
                height = h * PIECE_SCALE * (0.78 + 0.25 * phase)
                lean = (8 if x > 0 else -8 if x < 0 else 0) + 7 * phase
                offset = Vector((x * PIECE_SCALE, 0, z * PIECE_SCALE))
                obj.matrix_world = Matrix.Translation(base + offset) @ Euler((0, math.radians(lean), 0)).to_matrix().to_4x4() @ Matrix.Diagonal((1, 1, height, 1))
            for obj, z, h, i in self.aura_body:
                height = h * PIECE_SCALE * (0.92 + 0.08 * math.sin((t + i * 0.3) * 2 * math.pi))
                obj.matrix_world = Matrix.Translation(base + Vector((0, 0.2, z * PIECE_SCALE))) @ Matrix.Diagonal((1, 1, height, 1))
        else:
            pose_piece(self.pawns[0], 625, 500, t, 0.25)
            pose_piece(self.pawns[1], 735, 500, t, 0.6)
            pose_piece(self.knight, 556, 556, t, 0.45, depth=-0.3, yaw=math.radians(20))
            pose_piece(self.bishop, 1186, 540, t, 0.8, depth=-0.3)

        for obj, dx, dz, h, ph in self.tongues:
            flicker = math.sin((t + ph) * 2 * math.pi)
            sway = math.radians(7 * math.sin((t * 2 + ph) * 2 * math.pi))
            height = h * (0.82 + 0.22 * flicker)
            obj.matrix_world = Matrix.Translation(self.fire_base + Vector((dx, dz, 0.02))) @ Euler((0, sway, 0)).to_matrix().to_4x4() @ Matrix.Diagonal((1, 1, height, 1))

        for i, ember in enumerate(self.embers):
            rise = (t + i / EMBERS) % 1
            drift = 0.25 * math.sin((rise + i * 0.3) * math.pi * 2)
            ember.location = self.fire_base + Vector((-0.3 + i * 0.2 + drift, -0.3, 0.4 + rise * 1.3))


def setup_scene():
    old = bpy.data.scenes.get(SCENE_NAME)
    if old:
        remove_scene(old)

    scene = bpy.data.scenes.new(SCENE_NAME)
    scene.render.engine = bpy.data.scenes[0].render.engine
    width = (REGION[2] - REGION[0]) // RENDER_SCALE
    height = (REGION[3] - REGION[1]) // RENDER_SCALE
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.filter_size = 0
    scene.view_settings.view_transform = "Standard"

    scene.world = bpy.data.worlds.new("CampWorld")
    scene.world.color = (0.02, 0.02, 0.02)

    camera_data = bpy.data.cameras.new("CampCam")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = (REGION[2] - REGION[0]) / PIXELS_PER_UNIT
    camera = bpy.data.objects.new("CampCam", camera_data)
    camera.rotation_euler = (math.radians(90), 0, 0)
    camera.location = (0, -30, 0)
    scene.collection.objects.link(camera)
    scene.camera = camera

    # Lit from the front left like the sprites; the fire's glow is added as a tint when packing
    sun_data = bpy.data.lights.new("CampSun", "SUN")
    sun_data.energy = 3
    sun = bpy.data.objects.new("CampSun", sun_data)
    sun.rotation_euler = (math.radians(60), math.radians(-25), math.radians(-30))
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
camps = [Camp(scene, "Party"), Camp(scene, "Knight")]
os.makedirs(OUT, exist_ok=True)

try:
    for camp in camps:
        for other in camps:
            other.collection.hide_render = other is not camp

        # The Fallen Knight's aura renders on its own so packing can lay it behind him see-through
        aura = {obj for obj, *_ in getattr(camp, "aura", []) + getattr(camp, "aura_body", [])}
        passes = [("", lambda obj: obj not in aura)] + ([("Aura", lambda obj: obj in aura)] if aura else [])

        for suffix, shown in passes:
            for obj in camp.collection.all_objects:
                obj.hide_render = not shown(obj)

            for i in range(FRAMES):
                camp.pose(i / FRAMES)
                scene.render.filepath = os.path.join(OUT, f"{camp.version}{suffix}_{i}.png")
                bpy.ops.render.render(write_still=True, scene=scene.name)
finally:
    remove_scene(scene)
