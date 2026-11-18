# Run inside Blender (Text Editor > Run Script) with art/ShotgunChessSprites.blend open.
# Builds the stun stars and the command arrow and renders their looping frames to
# art/frames/Stun_<i>.png and art/frames/Arrow_<i>.png for build_atlas.py.
import bpy, bmesh, math, os

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

print("Built stun and arrow frames")
