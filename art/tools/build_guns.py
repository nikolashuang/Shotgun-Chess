# Run inside Blender (Text Editor > Run Script) with art/ShotgunChessSprites.blend open.
# Builds each shotgun mesh from 2D side profiles, renders it to art/frames/<Name>_0.png
# and writes art/frames/guns.json (sprite size + grip pixel) for build_atlas.py.
# The Pump uses the hand-made "Shotgun" object and is not rebuilt here.
import bpy, bmesh, math, os, json
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(bpy.data.filepath))
FRAMES = os.path.join(ROOT, "art", "frames")

# World units per sprite pixel, matching the Pump sprite
UPP = 0.08
HEIGHT = 16

MATS = ["Gold", "Steel", "Red", "Piece", "Gunmetal"]


def srgb_to_linear(c):
    c = c / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def toon_material(name, shadow_hex, lit_hex):
    if name in bpy.data.materials:
        return
    mat = bpy.data.materials["Gold"].copy()
    mat.name = name
    ramp = next(n for n in mat.node_tree.nodes if n.type == "VALTORGB").color_ramp
    for element, hex_color in zip(ramp.elements, (shadow_hex, lit_hex)):
        element.color = [srgb_to_linear(int(hex_color[i:i + 2], 16)) for i in (0, 2, 4)] + [1]


toon_material("Red", "9E3A3C", "D9544D")
toon_material("Gunmetal", "4E566B", "4E566B")


def prism(bm, points, depth, mat):
    front = [bm.verts.new((x, -depth, z)) for x, z in points]
    back = [bm.verts.new((x, depth, z)) for x, z in points]
    faces = [bm.faces.new(front), bm.faces.new(list(reversed(back)))]
    for i in range(len(points)):
        j = (i + 1) % len(points)
        faces.append(bm.faces.new((front[i], back[i], back[j], front[j])))
    for f in faces:
        f.material_index = MATS.index(mat)


def box(bm, x0, x1, z0, z1, depth, mat):
    prism(bm, [(x0, z0), (x1, z0), (x1, z1), (x0, z1)], depth, mat)


def barrel(bm, x0, x1, zc, r, mat):
    ring = [(r * math.cos(a), zc + r * math.sin(a)) for a in [i * math.pi / 4 + math.pi / 8 for i in range(8)]]
    start = [bm.verts.new((x0, y, z)) for y, z in ring]
    end = [bm.verts.new((x1, y, z)) for y, z in ring]
    faces = [bm.faces.new(list(reversed(start))), bm.faces.new(end)]
    for i in range(8):
        j = (i + 1) % 8
        faces.append(bm.faces.new((start[i], start[j], end[j], end[i])))
    for f in faces:
        f.material_index = MATS.index(mat)


def trigger_guard(bm, x):
    box(bm, x - 0.12, x + 0.06, -0.22, -0.12, 0.06, "Steel")


# Each builder returns the grip point (x, z) the king's hand holds

def double_barrel(bm):
    prism(bm, [(-1.2, -0.3), (-1.05, -0.46), (-0.88, -0.44), (-0.6, -0.12), (-0.58, 0.16), (-0.8, 0.14), (-1.08, -0.06)], 0.1, "Gold")
    box(bm, -0.62, -0.02, -0.12, 0.2, 0.13, "Steel")
    box(bm, -0.5, -0.38, 0.2, 0.26, 0.04, "Steel")
    barrel(bm, -0.05, 1.15, 0.13, 0.08, "Steel")
    barrel(bm, -0.05, 1.15, -0.03, 0.08, "Gunmetal")
    box(bm, 1.08, 1.15, -0.13, 0.23, 0.11, "Steel")
    box(bm, -0.05, 0.7, -0.17, -0.07, 0.1, "Gold")
    trigger_guard(bm, -0.3)
    return (-0.62, -0.2)


def buck_barrel(bm):
    prism(bm, [(-1.6, -0.36), (-1.6, 0.14), (-1.3, 0.16), (-0.62, 0.14), (-0.62, -0.1), (-0.78, -0.44), (-0.98, -0.42), (-0.9, -0.16), (-1.3, -0.2)], 0.1, "Gunmetal")
    box(bm, -1.66, -1.6, -0.38, 0.16, 0.11, "Steel")
    box(bm, -0.62, 0.05, -0.1, 0.24, 0.13, "Steel")
    for x in (-0.5, -0.34, -0.18):
        box(bm, x, x + 0.08, -0.02, 0.2, 0.15, "Red")
        box(bm, x, x + 0.08, -0.08, -0.02, 0.15, "Gold")
    barrel(bm, 0.0, 1.5, 0.15, 0.075, "Steel")
    barrel(bm, 0.0, 1.32, 0.0, 0.075, "Gunmetal")
    box(bm, 0.3, 0.9, -0.12, 0.06, 0.12, "Gunmetal")
    for x in (0.38, 0.54, 0.7):
        box(bm, x, x + 0.06, -0.14, 0.08, 0.125, "Steel")
    box(bm, 1.4, 1.46, 0.22, 0.3, 0.03, "Steel")
    trigger_guard(bm, -0.3)
    return (-0.56, -0.16)


def long_barrel(bm):
    prism(bm, [(-1.75, -0.4), (-1.75, 0.1), (-0.85, 0.14), (-0.6, 0.1), (-0.6, -0.1), (-0.85, -0.14)], 0.1, "Gold")
    box(bm, -1.8, -1.75, -0.4, 0.1, 0.1, "Gunmetal")
    box(bm, -0.62, -0.2, -0.1, 0.16, 0.12, "Steel")
    prism(bm, [(-0.52, 0.12), (-0.44, 0.12), (-0.5, 0.28), (-0.6, 0.3)], 0.04, "Gunmetal")
    barrel(bm, -0.22, 2.15, 0.08, 0.07, "Steel")
    box(bm, -0.22, 0.55, -0.08, 0.02, 0.08, "Gold")
    box(bm, 2.08, 2.12, 0.15, 0.2, 0.03, "Steel")
    trigger_guard(bm, -0.36)
    return (-0.62, -0.18)


def knife_shotty(bm):
    prism(bm, [(-0.95, -0.44), (-0.75, -0.46), (-0.5, -0.06), (-0.5, 0.1), (-0.7, 0.1), (-0.85, -0.1)], 0.1, "Gold")
    box(bm, -0.55, 0.08, -0.1, 0.24, 0.13, "Steel")
    barrel(bm, 0.05, 1.4, 0.15, 0.075, "Steel")
    barrel(bm, 0.05, 1.22, 0.0, 0.075, "Gunmetal")
    box(bm, 0.3, 0.85, -0.12, 0.06, 0.12, "Gold")
    box(bm, 1.18, 1.32, -0.1, 0.24, 0.1, "Gunmetal")
    prism(bm, [(1.3, -0.16), (1.3, 0.04), (1.95, 0.02), (2.12, -0.06), (1.95, -0.16)], 0.03, "Piece")
    trigger_guard(bm, -0.25)
    return (-0.62, -0.16)


BUILDERS = {
    "DoubleBarrel": double_barrel,
    "BuckBarrel": buck_barrel,
    "LongBarrel": long_barrel,
    "KnifeShotty": knife_shotty,
}


def build(name, builder, index):
    if name in bpy.data.objects:
        old = bpy.data.objects[name]
        mesh = old.data
        bpy.data.objects.remove(old)
        bpy.data.meshes.remove(mesh)

    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    grip = builder(bm)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    for mat in MATS:
        mesh.materials.append(bpy.data.materials[mat])

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = (0, 0, -4.0 - index)
    obj.hide_render = True
    obj["GripX"], obj["GripZ"] = grip
    bpy.context.view_layer.update()
    return obj


def render(obj):
    scene = bpy.context.scene
    cam = bpy.data.objects["SpriteCam"]

    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    x0, x1 = min(c.x for c in corners), max(c.x for c in corners)
    z0, z1 = min(c.z for c in corners), max(c.z for c in corners)
    width = math.ceil((x1 - x0) / UPP) + 4
    width += width % 2
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2

    saved = (cam.location.copy(), cam.rotation_euler.copy(), cam.data.ortho_scale,
             scene.render.resolution_x, scene.render.resolution_y, scene.render.filepath,
             {o.name: o.hide_render for o in bpy.data.objects})
    try:
        for o in bpy.data.objects:
            if o.type == "MESH":
                o.hide_render = o != obj
        cam.rotation_euler = (math.radians(90), 0, 0)
        cam.location = (cx, obj.location.y - 20, cz)
        cam.data.ortho_scale = UPP * max(width, HEIGHT)
        scene.render.resolution_x = width
        scene.render.resolution_y = HEIGHT
        scene.render.filepath = os.path.join(FRAMES, obj.name + "_0.png")
        bpy.ops.render.render(write_still=True)
    finally:
        cam.location, cam.rotation_euler, cam.data.ortho_scale, scene.render.resolution_x, scene.render.resolution_y, scene.render.filepath, hidden = saved
        for o in bpy.data.objects:
            o.hide_render = hidden[o.name]

    grip_x = obj.location.x + obj["GripX"]
    grip_z = obj.location.z + obj["GripZ"]
    return {
        "Frame": obj.name + "_0.png",
        "Width": width,
        "Height": HEIGHT,
        "Grip": [round((grip_x - cx) / UPP + width / 2), round((cz - grip_z) / UPP + HEIGHT / 2)],
    }


guns = {"Pump": {"Frame": "Shotgun_0.png", "Width": 40, "Height": 16, "Grip": [13, 10]}}
for i, (name, builder) in enumerate(BUILDERS.items()):
    guns[name] = render(build(name, builder, i))

with open(os.path.join(FRAMES, "guns.json"), "w") as f:
    json.dump(guns, f, indent=2)

print("Built", ", ".join(guns))
