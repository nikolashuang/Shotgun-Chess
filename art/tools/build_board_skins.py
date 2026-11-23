# Run inside Blender (Text Editor > Run Script) with art/ShotgunChessSprites.blend open.
# Builds the Epic board skins as small 3D scenes seen straight down, renders each whole 12x12 board
# to art/skins/boards/<Name>.png (16 pixels per tile), writes the scene to art/BoardSkins.blend
# and removes it again so the sprite file is left as it was.
# Upload each png and put its asset id in SkinConfig.luau (Image on the board skin).
import bpy, bmesh, math, os, random
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(bpy.data.filepath))
OUT = os.path.join(ROOT, "art", "skins", "boards")
SCENE_NAME = "BoardSkins"

BOARD = 12
PIXELS_PER_TILE = 16
SIZE = BOARD * PIXELS_PER_TILE

CREATED_MATERIALS = set()


def linear(hex_color):
    def channel(c):
        c = c / 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return [channel(int(hex_color[i:i + 2], 16)) for i in (0, 2, 4)] + [1]


# Same three tone toon shading as the islands and armory icons
def toon(name, dark, base, light):
    name = "Board" + name
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
    elements[1].position, elements[1].color = 0.25, linear(base)
    third = elements.new(0.62)
    third.color = linear(light)

    links.new(diffuse.outputs[0], to_rgb.inputs[0])
    links.new(to_rgb.outputs[0], to_bw.inputs[0])
    links.new(to_bw.outputs[0], ramp.inputs[0])
    links.new(ramp.outputs[0], emission.inputs[0])
    links.new(emission.outputs[0], output.inputs[0])

    return mat


def flat(name, color):
    name = "Board" + name
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


# Tile (column, row) is 1-based like BoardRules; A1 sits bottom left and is dark
def tile_center(column, row):
    return Vector((column - BOARD / 2 - 0.5, row - BOARD / 2 - 0.5, 0))


def is_dark(column, row):
    return (column + row) % 2 == 0


class Board:
    def __init__(self, scene, name, seed):
        self.name = name
        self.random = random.Random(seed)
        self.collection = bpy.data.collections.new("Board_" + name)
        scene.collection.children.link(self.collection)

    def add(self, build, mat, location=(0, 0, 0), rotation=(0, 0, 0)):
        bm = bmesh.new()
        build(bm)
        mesh = bpy.data.meshes.new(self.name)
        bm.to_mesh(mesh)
        bm.free()
        mesh.materials.append(mat)

        obj = bpy.data.objects.new(self.name, mesh)
        obj.location = location
        obj.rotation_euler = rotation
        self.collection.objects.link(obj)

        return obj

    def block(self, mat, center, size, height, tilt=(0, 0, 0)):
        def build(bm):
            bmesh.ops.create_cube(bm, size=1)
            bmesh.ops.scale(bm, vec=(size[0], size[1], height), verts=bm.verts)
            bmesh.ops.translate(bm, vec=(0, 0, -height / 2), verts=bm.verts)

        return self.add(build, mat, center, tilt)

    def rock(self, mat, center, radius):
        r = self.random

        def build(bm):
            bmesh.ops.create_icosphere(bm, subdivisions=1, radius=radius)
            for v in bm.verts:
                v.co *= 0.7 + r.random() * 0.5
                v.co.z *= 0.6

        return self.add(build, mat, center, (0, 0, r.random() * math.tau))

    # A jagged line of thin strips, wandering from start in a direction
    def crack(self, mat, start, angle, steps, step_length=0.18, width=0.05, branch=0.25, depth=0):
        r = self.random
        point = Vector(start)

        for _ in range(steps):
            angle += (r.random() - 0.5) * 1.1
            end = point + Vector((math.cos(angle), math.sin(angle), 0)) * step_length

            def build(bm, a=point.copy(), b=end.copy()):
                side = (b - a).cross(Vector((0, 0, 1))).normalized() * width / 2
                verts = [bm.verts.new(a - side), bm.verts.new(b - side), bm.verts.new(b + side), bm.verts.new(a + side)]
                bm.faces.new(verts)

            self.add(build, mat, (0, 0, 0.02))

            if depth < 2 and r.random() < branch:
                self.crack(mat, end, angle + (r.random() - 0.5) * 2, steps // 2, step_length, width * 0.7, branch, depth + 1)

            point = end

    def patch(self, mat, center, radius, height=0.015):
        r = self.random

        def build(bm):
            count = 9
            middle = bm.verts.new((0, 0, 0))
            ring = []
            for i in range(count):
                a = math.tau * i / count
                d = radius * (0.6 + r.random() * 0.6)
                ring.append(bm.verts.new((math.cos(a) * d, math.sin(a) * d, 0)))
            for i in range(count):
                bm.faces.new((middle, ring[i], ring[(i + 1) % count]))

        return self.add(build, mat, (center[0], center[1], height))


# Heavy stone slabs, cracked through and chipped at the edges, with a couple of broken-out holes
def ruined(board):
    r = board.random
    light = toon("RuinedLight", "6E6456", "A89C88", "CDC2AC")
    dark = toon("RuinedDark", "2A241F", "4A4038", "6A5D50")
    rubble = toon("RuinedRubble", "2E2A28", "5A524C", "857A70")
    pale_rubble = toon("RuinedPaleRubble", "6E6456", "B5AA96", "DDD3C0")
    pit = flat("RuinedPit", "17131A")
    gap = flat("RuinedGap", "211B1E")
    crack = flat("RuinedCrack", "1A1519")

    board.block(gap, (0, 0, -0.06), (BOARD, BOARD), 0.2)
    missing = {(r.randint(2, BOARD - 1), r.randint(2, BOARD - 1)) for _ in range(3)}

    for column in range(1, BOARD + 1):
        for row in range(1, BOARD + 1):
            center = tile_center(column, row)

            if (column, row) in missing:
                board.block(pit, center + Vector((0, 0, -0.2)), (0.98, 0.98), 0.05)
                for _ in range(3):
                    offset = Vector(((r.random() - 0.5) * 0.6, (r.random() - 0.5) * 0.6, -0.15))
                    board.rock(rubble, center + offset, 0.12 + r.random() * 0.08)
                continue

            mat = dark if is_dark(column, row) else light
            sink = -r.random() * 0.03 if r.random() < 0.3 else 0
            board.block(mat, center + Vector((0, 0, sink)), (0.9, 0.9), 0.1, (0, 0, (r.random() - 0.5) * 0.04))

            # A chipped corner shows the gap underneath
            if r.random() < 0.25:
                cx, cy = r.choice((-1, 1)), r.choice((-1, 1))
                board.block(gap, center + Vector((cx * 0.4, cy * 0.4, 0.01)), (0.18, 0.18), 0.02, (0, 0, math.radians(45)))

            # Short hairline crack inside the slab
            if r.random() < 0.12:
                start = center + Vector(((r.random() - 0.5) * 0.6, (r.random() - 0.5) * 0.6, 0))
                board.crack(crack, start, r.random() * math.tau, 3, step_length=0.14, width=0.07, branch=0)

    # Long fractures across the board, one per quarter so they spread out
    for qx, qy in ((0, 0), (1, 0), (0, 1), (1, 1)):
        start = tile_center(qx * 6 + r.randint(2, 5), qy * 6 + r.randint(2, 5))
        board.crack(crack, start, r.random() * math.tau, 14, step_length=0.28, width=0.12, branch=0.2)

    # Debris: piles of stones heaped in the seams, pale on dark slabs and dark on light ones
    for _ in range(16):
        corner = tile_center(r.randint(1, BOARD - 1), r.randint(1, BOARD - 1)) + Vector((0.5, 0.5, 0.08))
        for _ in range(r.randint(2, 4)):
            offset = Vector(((r.random() - 0.5) * 0.4, (r.random() - 0.5) * 0.4, 0))
            board.rock(r.choice((rubble, pale_rubble)), corner + offset, 0.08 + r.random() * 0.07)

    # Broken-off slab chunks lying on top of the board
    for _ in range(12):
        column, row = r.randint(1, BOARD), r.randint(1, BOARD)
        if (column, row) in missing: continue
        mat = light if is_dark(column, row) else dark
        offset = Vector(((r.random() - 0.5) * 0.5, (r.random() - 0.5) * 0.5, 0.06))
        board.block(mat, tile_center(column, row) + offset, (0.22 + r.random() * 0.1, 0.16 + r.random() * 0.08), 0.06, (r.random() * 0.4, r.random() * 0.4, r.random() * math.tau))

    # Loose grit scattered over the slabs
    for _ in range(40):
        spot = tile_center(r.randint(1, BOARD), r.randint(1, BOARD)) + Vector(((r.random() - 0.5) * 0.9, (r.random() - 0.5) * 0.9, 0.05))
        board.rock(r.choice((rubble, pale_rubble)), spot, 0.04 + r.random() * 0.03)


# Worn flagstone tiles split into bricks, with moss, dust and cobwebs in the corners
def castle(board):
    r = board.random
    light = toon("CastleLight", "5E574E", "8F8678", "B2A898")
    dark = toon("CastleDark", "232026", "3E3A3F", "57525A")
    mortar = flat("CastleMortar", "1B171C")
    moss = toon("CastleMoss", "2E3A24", "4F6238", "6E8450")
    dust = flat("CastleDust", "A69C8C")
    web = flat("CastleWeb", "CFC8BC")

    board.block(mortar, (0, 0, -0.04), (BOARD, BOARD), 0.1)

    for column in range(1, BOARD + 1):
        for row in range(1, BOARD + 1):
            center = tile_center(column, row)
            mat = dark if is_dark(column, row) else light

            # One flagstone per tile; some have split into two uneven slabs
            if r.random() < 0.3:
                left = 0.88 * (0.4 + r.random() * 0.2)
                right = 0.88 - left - 0.07
                board.block(mat, center + Vector((-0.44 + left / 2, 0, 0)), (left, 0.88), 0.1)
                board.block(mat, center + Vector((0.44 - right / 2, 0, 0)), (right, 0.88), 0.1)
            else:
                board.block(mat, center, (0.88, 0.88), 0.1)

    for _ in range(10):
        center = tile_center(r.randint(1, BOARD), r.randint(1, BOARD)) + Vector(((r.random() - 0.5) * 0.8, (r.random() - 0.5) * 0.8, 0))
        board.patch(moss, center, 0.2 + r.random() * 0.25, 0.02)

    for _ in range(18):
        center = tile_center(r.randint(1, BOARD), r.randint(1, BOARD)) + Vector(((r.random() - 0.5), (r.random() - 0.5), 0))
        board.patch(dust, center, 0.06 + r.random() * 0.06, 0.03)

    # Cobwebs fan out from the four board corners
    half = BOARD / 2
    for corner_x, corner_y in ((-1, -1), (-1, 1), (1, -1), (1, 1)):
        origin = Vector((corner_x * half, corner_y * half, 0))
        base = math.atan2(-corner_y, -corner_x)
        for i in range(5):
            angle = base + (i - 2) * 0.3
            board.crack(web, origin, angle, 6, step_length=0.25, width=0.07, branch=0)


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

    scene.world = bpy.data.worlds.new("BoardWorld")
    scene.world.color = (0.02, 0.02, 0.02)

    camera_data = bpy.data.cameras.new("BoardCam")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = BOARD
    camera = bpy.data.objects.new("BoardCam", camera_data)
    camera.location = (0, 0, 20)
    scene.collection.objects.link(camera)
    scene.camera = camera

    # Light from the top left, so raised and tilted stones read like the sprites
    sun_data = bpy.data.lights.new("BoardSun", "SUN")
    sun_data.energy = 3
    sun = bpy.data.objects.new("BoardSun", sun_data)
    sun.rotation_euler = (math.radians(40), math.radians(-25), math.radians(-35))
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


# Names match the board skin names in SkinConfig
BUILDERS = [("Ruined", ruined, 11), ("Castle", castle, 37)]

ONLY = globals().get("ONLY")

scene = setup_scene()
boards = []

for name, build, seed in BUILDERS:
    if ONLY and name not in ONLY: continue
    board = Board(scene, name, seed)
    build(board)
    boards.append(board)

os.makedirs(OUT, exist_ok=True)
for board in boards:
    for other in boards:
        other.collection.hide_render = other is not board

    scene.render.filepath = os.path.join(OUT, board.name + ".png")
    bpy.ops.render.render(write_still=True, scene=scene.name)

for board in boards:
    board.collection.hide_render = False

if not ONLY:
    bpy.data.libraries.write(os.path.join(ROOT, "art", "BoardSkins.blend"), {scene}, fake_user=True)
remove_scene(scene)
