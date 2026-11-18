# Run inside Blender (Text Editor > Run Script) with art/ShotgunChessSprites.blend open.
# Builds the stun stars and the command arrow and renders their looping frames to
# art/frames/Stun_<i>.png and art/frames/Arrow_<i>.png for build_atlas.py.
import bpy, bmesh, math, os, random
from mathutils import Vector, Matrix

ROOT = os.path.dirname(os.path.dirname(bpy.data.filepath))
FRAMES = os.path.join(ROOT, "art", "frames")

# World units per sprite pixel, matching the pieces
UPP = 0.1

STUN_FRAMES = 8
STUN_SIZE = (32, 22)
STUN_RADIUS = 0.95
# Camera pitch for the stars; a little steeper than the pieces so the orbit reads as a ring
STUN_PITCH = 62
STUN_STARS = 3
STAR_OUTER = 0.38
STAR_INNER = 0.17
STAR_DEPTH = 0.06

ARROW_FRAMES = 8
ARROW_SIZE = (16, 16)
# Side profile (x, z) of an arrow pointing down
ARROW = [(-0.16, 0.7), (0.16, 0.7), (0.16, 0.05), (0.42, 0.05), (0.0, -0.55), (-0.42, 0.05), (-0.16, 0.05)]
ARROW_DEPTH = 0.09

# Effects are built away from the pieces so the renders never overlap them
ORIGIN_Z = -12.0


def prism(bm, points, depth):
    front = [bm.verts.new((x, -depth, z)) for x, z in points]
    back = [bm.verts.new((x, depth, z)) for x, z in points]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    for i in range(len(points)):
        j = (i + 1) % len(points)
        bm.faces.new((front[i], back[i], back[j], front[j]))


def replace_object(name, points, depth, material):
    if name in bpy.data.objects:
        old = bpy.data.objects[name]
        mesh = old.data
        bpy.data.objects.remove(old)
        bpy.data.meshes.remove(mesh)

    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    prism(bm, points, depth)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(bpy.data.materials[material])

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.hide_render = True
    return obj


def star_points():
    points = []
    for i in range(10):
        angle = math.pi / 2 + i * math.pi / 5
        radius = STAR_OUTER if i % 2 == 0 else STAR_INNER
        points.append((radius * math.cos(angle), radius * math.sin(angle)))
    return points


def render_frames(objects, size, view, prefix, count, pose):
    scene = bpy.context.scene
    cam = bpy.data.objects["SpriteCam"]

    saved = (cam.location.copy(), cam.rotation_euler.copy(), cam.data.ortho_scale,
             scene.render.resolution_x, scene.render.resolution_y, scene.render.filepath,
             {o.name: o.hide_render for o in bpy.data.objects})
    try:
        for o in bpy.data.objects:
            if o.type == "MESH":
                o.hide_render = o not in objects

        scene.view_settings.view_transform = "Standard"
        pitch, back, up = view
        cam.rotation_euler = (math.radians(pitch), 0, 0)
        cam.location = (0, -back, ORIGIN_Z + up)
        cam.data.ortho_scale = UPP * max(size)
        scene.render.resolution_x, scene.render.resolution_y = size

        for i in range(count):
            pose(i / count)
            scene.render.filepath = os.path.join(FRAMES, f"{prefix}_{i}.png")
            bpy.ops.render.render(write_still=True)
    finally:
        cam.location, cam.rotation_euler, cam.data.ortho_scale, scene.render.resolution_x, scene.render.resolution_y, scene.render.filepath, hidden = saved
        for o in bpy.data.objects:
            o.hide_render = hidden[o.name]


# Stars orbit the head, seen from the same tilted camera as the pieces
stars = [replace_object(f"StunStar{i}", star_points(), STAR_DEPTH, "Gold") for i in range(STUN_STARS)]


def pose_stars(t):
    # The stars are identical, so one third of a turn loops seamlessly
    for i, star in enumerate(stars):
        angle = (i + t) * 2 * math.pi / STUN_STARS
        star.location = (STUN_RADIUS * math.cos(angle), STUN_RADIUS * math.sin(angle), ORIGIN_Z)
        # Faces the camera with a small wobble so the stars stay readable
        star.rotation_euler = (math.radians(STUN_PITCH - 90), math.radians(15) * math.sin((i + t) * 2 * math.pi), 0)


# Spins around its vertical axis; a half turn looks the same, so it loops
arrow = replace_object("CommandArrow", ARROW, ARROW_DEPTH, "Gold")


def pose_arrow(t):
    arrow.location = (0, 0, ORIGIN_Z)
    arrow.rotation_euler = (0, 0, t * math.pi)


render_frames(stars, STUN_SIZE, (STUN_PITCH, 20, 20 * math.tan(math.radians(90 - STUN_PITCH))), "Stun", STUN_FRAMES, pose_stars)
render_frames([arrow], ARROW_SIZE, (90, 20, 0), "Arrow", ARROW_FRAMES, pose_arrow)


#--CLASS EFFECTS--
# Flat emission colors so the atlas keeps them exactly (teal souls, red marks) instead of snapping to the piece palette

# Pieces are seen from 72 degrees; board effects use the same view so they sit on the tiles
BOARD_VIEW = (72, 20, 20 * math.tan(math.radians(18)))
FRONT_VIEW = (90, 20, 0)


def srgb_to_linear(c):
    c = c / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def flat(name, hex_color):
    mat = bpy.data.materials.get("Fx" + name) or bpy.data.materials.new("Fx" + name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    emission = nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value = [srgb_to_linear(int(hex_color[i:i + 2], 16)) for i in (0, 2, 4)] + [1]
    output = nodes.new("ShaderNodeOutputMaterial")
    mat.node_tree.links.new(emission.outputs["Emission"], output.inputs["Surface"])
    return mat


def mesh_object(name, build, materials):
    if name in bpy.data.objects:
        old = bpy.data.objects[name]
        mesh = old.data
        bpy.data.objects.remove(old)
        bpy.data.meshes.remove(mesh)

    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    build(bm)
    bm.to_mesh(mesh)
    bm.free()
    for mat in materials:
        mesh.materials.append(mat)

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.hide_render = True
    return obj


def set_material(bm, faces, index):
    for f in faces:
        f.material_index = index


def ball(bm, center, radius, index, subdivisions=2):
    result = bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=radius)
    bmesh.ops.translate(bm, vec=center, verts=result["verts"])
    set_material(bm, {f for v in result["verts"] for f in v.link_faces}, index)
    return result["verts"]


def cone(bm, base, tip_height, radius, index, segments=6, rotation=None):
    result = bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=radius, radius2=0, depth=tip_height)
    if rotation:
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=rotation, verts=result["verts"])
    bmesh.ops.translate(bm, vec=base, verts=result["verts"])
    set_material(bm, {f for v in result["verts"] for f in v.link_faces}, index)
    return result["verts"]


def box(bm, center, size, index, rotation=None):
    result = bmesh.ops.create_cube(bm, size=1)
    bmesh.ops.scale(bm, vec=size, verts=result["verts"])
    if rotation:
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=rotation, verts=result["verts"])
    bmesh.ops.translate(bm, vec=center, verts=result["verts"])
    set_material(bm, {f for v in result["verts"] for f in v.link_faces}, index)
    return result["verts"]


def rod(bm, start, end, radius, index, sides=4):
    start, end = Vector(start), Vector(end)
    direction = end - start
    result = bmesh.ops.create_cone(bm, cap_ends=True, segments=sides, radius1=radius, radius2=radius, depth=direction.length)
    rotation = direction.to_track_quat("Z", "Y").to_matrix().to_4x4()
    bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=rotation, verts=result["verts"])
    bmesh.ops.translate(bm, vec=(start + end) / 2, verts=result["verts"])
    set_material(bm, {f for v in result["verts"] for f in v.link_faces}, index)


def rot(axis, degrees):
    return Matrix.Rotation(math.radians(degrees), 4, axis)


def located(obj, offset=(0, 0, 0)):
    obj.location = (offset[0], offset[1], ORIGIN_Z + offset[2])
    return obj


# Soul: a black orb wrapped in greenish-blue flames that flicker upward
SOUL_FRAMES = 6
soul_mats = [flat("SoulCore", "1E1820"), flat("SoulShade", "332A35"), flat("SoulFlame", "2E9C8E"), flat("SoulFlameLight", "7FE3C8"), flat("SoulEye", "C8F6EA")]


def build_soul(t):
    def build(bm):
        ball(bm, (0, -0.02, -0.15), 0.42, 0)
        ball(bm, (0.1, -0.25, -0.05), 0.12, 4, 1)
        # Flame tongues around and above the orb, swaying with the frame
        for i, (x, height, lean) in enumerate(((-0.42, 0.75, -12), (0.42, 0.7, 12), (-0.18, 1.05, -5), (0.2, 1.0, 6), (0.0, 1.3, 0))):
            phase = math.sin((t + i * 0.23) * 2 * math.pi)
            h = height * (0.85 + 0.2 * phase)
            index = 3 if i >= 2 else 2
            cone(bm, (x, 0.05 if i >= 2 else 0.1, 0.0 + h / 2 - 0.1), h, 0.22 if i < 4 else 0.17, index, 5, rot("Y", lean + 6 * phase))
        # Embers drifting up
        for i in range(2):
            y = ((t + i * 0.5) % 1)
            ball(bm, (-0.3 + i * 0.6, -0.1, 0.6 + y * 0.9), 0.07, 4, 1)
    return build


soul_obj = located(mesh_object("FxSoul", build_soul(0), soul_mats))


def pose_soul(t):
    global soul_obj
    soul_obj = located(mesh_object("FxSoul", build_soul(t), soul_mats))
    soul_obj.hide_render = False


# Energy bolt: a chunky lightning zigzag
bolt_mats = [flat("BoltGold", "E6C47C"), flat("BoltLight", "FFF3D6"), flat("BoltShadow", "A8844A")]
BOLT = [(0.15, 0.95), (-0.35, 0.05), (-0.02, 0.05), (-0.22, -0.95), (0.38, 0.12), (0.05, 0.12), (0.32, 0.95)]


def build_bolt(bm):
    front = [bm.verts.new((x, -0.08, z)) for x, z in BOLT]
    back = [bm.verts.new((x, 0.08, z)) for x, z in BOLT]
    f = bm.faces.new(front)
    f.material_index = 0
    bm.faces.new(list(reversed(back)))
    inner = [bm.verts.new((x * 0.45, -0.09, z * 0.7 + 0.05)) for x, z in BOLT]
    bm.faces.new(inner).material_index = 1
    for i in range(len(BOLT)):
        j = (i + 1) % len(BOLT)
        bm.faces.new((front[i], back[i], back[j], front[j])).material_index = 2


bolt_obj = located(mesh_object("FxBolt", build_bolt, bolt_mats))


# Bear trap: a steel ring base with two toothed jaws hinged on its long sides
trap_mats = [flat("TrapSteel", "8A93A6"), flat("TrapDark", "4E566B"), flat("TrapLight", "C9CED8"), flat("TrapRust", "9C574B")]
TRAP_SNAP_FRAMES = 4


def build_trap(close):
    def build(bm):
        # Base plate and pressure pan
        box(bm, (0, 0, 0.02), (1.5, 1.0, 0.06), 1)
        ball(bm, (0, 0, 0.06), 0.22, 3, 1)
        # Jaws: each a bar of teeth rotating up from flat (0) to closed (1)
        for side in (-1, 1):
            angle = side * (90 - 82 * close) if close > 0 else side * 90
            matrix = rot("X", -angle)
            for k in range(5):
                x = -0.56 + k * 0.28
                verts = cone(bm, (0, 0, 0), 0.26, 0.09, 2, 4)
                bmesh.ops.translate(bm, vec=(x, 0, 0.13 + 0.4), verts=verts)
                bmesh.ops.rotate(bm, cent=(0, 0, 0.04), matrix=matrix, verts=verts)
            verts = box(bm, (0, 0, 0.3), (1.45, 0.08, 0.16), 0)
            bmesh.ops.rotate(bm, cent=(0, 0, 0.04), matrix=matrix, verts=verts)
        # Springs at both ends
        for x in (-0.85, 0.85):
            box(bm, (x, 0, 0.06), (0.16, 0.6, 0.12), 0)
    return build


trap_obj = located(mesh_object("FxTrap", build_trap(0), trap_mats))


def pose_trap(t):
    global trap_obj
    trap_obj = located(mesh_object("FxTrap", build_trap(t * TRAP_SNAP_FRAMES / (TRAP_SNAP_FRAMES - 1)), trap_mats))
    trap_obj.hide_render = False


# Bolas: three weights on cords from a shared knot, spinning in flight
bolas_mats = [flat("BolasWeight", "4E566B"), flat("BolasCord", "A0683F"), flat("BolasLight", "8A93A6")]
BOLAS_FRAMES = 4


def build_bolas(t):
    def build(bm):
        knot = Vector((0, 0, 0))
        for i in range(3):
            angle = (t + i / 3) * 2 * math.pi
            end = Vector((0.62 * math.cos(angle), -0.1, 0.62 * math.sin(angle)))
            rod(bm, knot, end, 0.06, 1)
            ball(bm, end, 0.2, 0, 1)
            ball(bm, end + Vector((-0.05, -0.12, 0.06)), 0.06, 2, 1)
    return build


bolas_obj = located(mesh_object("FxBolas", build_bolas(0), bolas_mats))


def pose_bolas(t):
    global bolas_obj
    bolas_obj = located(mesh_object("FxBolas", build_bolas(t / 3), bolas_mats))
    bolas_obj.hide_render = False


# Bolas wrapped around a piece's body: two cord loops with the weights hanging off the front
def build_bound(bm):
    for k, z in enumerate((0.12, -0.12)):
        points = []
        for i in range(12):
            a = i / 12 * 2 * math.pi
            points.append(Vector((0.55 * math.cos(a), 0.38 * math.sin(a), z + 0.06 * math.sin(a + k))))
        for i in range(12):
            rod(bm, points[i], points[(i + 1) % 12], 0.04, 1)
    for x, z in ((-0.25, -0.38), (0.12, -0.5), (0.4, -0.3)):
        rod(bm, (x * 0.6, -0.38, -0.05), (x, -0.42, z), 0.03, 1)
        ball(bm, (x, -0.44, z), 0.13, 0, 1)
        ball(bm, (x - 0.04, -0.54, z + 0.05), 0.05, 2, 1)


bound_obj = located(mesh_object("FxBolasBound", build_bound, bolas_mats))


# Revolver: side profile like the shotgun sprites
revolver_mats = [flat("RevolverSteel", "8A93A6"), flat("RevolverDark", "4E566B"), flat("RevolverGrip", "7A4B33"), flat("RevolverLight", "C9CED8")]


def build_revolver(bm):
    def plate(points, depth, index, y=0):
        front = [bm.verts.new((x, y - depth, z)) for x, z in points]
        back = [bm.verts.new((x, y + depth, z)) for x, z in points]
        bm.faces.new(front).material_index = index
        bm.faces.new(list(reversed(back))).material_index = index
        for i in range(len(points)):
            j = (i + 1) % len(points)
            bm.faces.new((front[i], back[i], back[j], front[j])).material_index = index

    plate([(-0.55, -0.55), (-0.3, -0.6), (-0.12, -0.05), (-0.35, 0.02)], 0.09, 2)
    plate([(-0.42, 0.0), (0.25, 0.0), (0.25, 0.32), (-0.3, 0.32), (-0.42, 0.22)], 0.1, 0)
    plate([(-0.12, 0.02), (0.18, 0.02), (0.18, 0.28), (-0.12, 0.28)], 0.13, 1, -0.02)
    plate([(0.25, 0.16), (0.95, 0.16), (0.95, 0.3), (0.25, 0.3)], 0.06, 0)
    plate([(0.25, 0.3), (0.95, 0.3), (0.95, 0.33), (0.25, 0.33)], 0.065, 3)
    plate([(0.88, 0.3), (0.94, 0.3), (0.94, 0.38), (0.88, 0.38)], 0.03, 1)
    plate([(-0.38, 0.3), (-0.3, 0.3), (-0.42, 0.42), (-0.48, 0.38)], 0.03, 1)
    plate([(-0.18, -0.02), (0.02, -0.02), (0.02, -0.16), (-0.08, -0.2), (-0.18, -0.14)], 0.03, 1)


revolver_obj = located(mesh_object("FxRevolver", build_revolver, revolver_mats))


# Bounty mark: a red painted X
mark_mats = [flat("MarkRed", "D9544D"), flat("MarkDark", "9E3A3C"), flat("MarkLight", "F08A7A")]


def build_mark(bm):
    for angle in (45, -45):
        verts = box(bm, (0, 0, 0), (1.2, 0.08, 0.3), 0, rot("Y", angle))
        verts = box(bm, (0, -0.05, 0.06), (0.95, 0.02, 0.1), 2, rot("Y", angle))
        verts = box(bm, (0, -0.04, -0.09), (1.1, 0.02, 0.08), 1, rot("Y", angle))


mark_obj = located(mesh_object("FxMark", build_mark, mark_mats))


# Smoke: a bank of overlapping puffs over 3x3 board tiles, seen from straight above like the board,
# drifting a little each frame; higher puffs are lighter
SMOKE_FRAMES = 3
# One board tile in world units: a 32 px sprite cell spans 1.4 tiles at UPP units per pixel
SMOKE_TILE = 32 * UPP / 1.4
smoke_mats = [flat("SmokeLight", "E9E3D6"), flat("SmokeMid", "B3A88F"), flat("SmokeDark", "8A8290")]


def build_smoke(t):
    def build(bm):
        rng = random.Random(4)
        half = SMOKE_TILE * 1.5
        for i in range(70):
            radius = rng.uniform(0.7, 1.1)
            x = rng.uniform(-half + radius, half - radius)
            y = rng.uniform(-half + radius, half - radius)
            height = rng.uniform(0, 1)
            phase = (t + rng.random()) * 2 * math.pi
            index = 0 if height > 0.66 else (1 if height > 0.33 else 2)
            ball(bm, (x + math.sin(phase) * 0.12, y + math.cos(phase) * 0.12, height), radius, index, 1)
    return build


smoke_obj = located(mesh_object("FxSmoke", build_smoke(0), smoke_mats))


def pose_smoke(t):
    global smoke_obj
    smoke_obj = located(mesh_object("FxSmoke", build_smoke(t), smoke_mats))
    smoke_obj.hide_render = False


def still(_):
    pass


# Pixels per world unit stay the same as the pieces (UPP), so the effects match the pieces' scale
# Smoke covers 3 tiles; one board tile is CELL / CELL_TILES = about 22.9 sprite pixels
render_frames([soul_obj], (20, 28), (72, 20, 20 * math.tan(math.radians(18)) + 0.35), "Soul", SOUL_FRAMES, pose_soul)
render_frames([bolt_obj], (12, 22), FRONT_VIEW, "Bolt", 1, still)
# Traps are seen more from above than the pieces so the open jaws read
TRAP_VIEW = (45, 20, 20 + 0.25)
render_frames([trap_obj], (20, 16), TRAP_VIEW, "Trap", 1, still)
render_frames([trap_obj], (20, 16), TRAP_VIEW, "TrapSnap", TRAP_SNAP_FRAMES, pose_trap)
render_frames([bolas_obj], (16, 16), FRONT_VIEW, "Bolas", BOLAS_FRAMES, pose_bolas)
render_frames([bound_obj], (14, 10), BOARD_VIEW, "BolasBound", 1, still)
render_frames([revolver_obj], (18, 12), FRONT_VIEW, "Revolver", 1, still)
render_frames([mark_obj], (12, 12), FRONT_VIEW, "Mark", 1, still)
render_frames([smoke_obj], (70, 70), (0, 0, 20), "Smoke", SMOKE_FRAMES, pose_smoke)

print("Built board effect frames")
