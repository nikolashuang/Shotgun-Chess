# Run inside Blender with art/ShotgunChessSprites.blend open.
# Rebuilds the Knight's head from a Staunton-style side profile and renders its
# Idle/Hop/Hit/Death frames to art/frames/Knight_<Anim>_<i>.png for build_atlas.py.
# The revolved base is kept from the existing Knight mesh.
import bpy, bmesh, math, os
from mathutils import Vector, Matrix

ROOT = os.path.dirname(os.path.dirname(bpy.data.filepath))
FRAMES = os.path.join(ROOT, "art", "frames")

# Side profile (x, z), snout facing -x. Mane teeth run down the back edge
HEAD = [
    (-0.30, 0.45), (-0.40, 0.62), (-0.36, 0.82), (-0.12, 1.02), (-0.10, 1.14),
    (-0.30, 1.10), (-0.56, 1.14), (-0.68, 1.18), (-0.68, 1.26), (-0.50, 1.32),
    (-0.74, 1.36), (-0.74, 1.50), (-0.60, 1.60), (-0.40, 1.76), (-0.28, 1.92),
    (-0.32, 2.22), (-0.16, 2.06), (0.10, 1.98), (0.24, 1.88), (0.18, 1.78), (0.32, 1.66),
    (0.26, 1.56), (0.40, 1.42), (0.32, 1.32), (0.44, 1.16), (0.38, 1.04),
    (0.48, 0.86), (0.46, 0.66), (0.40, 0.45),
]
HEAD_DEPTH = 0.18
# Cheek plate sits proud of the head so the face reads as a separate plane
CHEEK = [(-0.20, 1.20), (-0.50, 1.24), (-0.56, 1.44), (-0.36, 1.62), (-0.12, 1.50)]
CHEEK_DEPTH = 0.23
EYE = [(-0.32, 1.62), (-0.42, 1.62), (-0.42, 1.70), (-0.32, 1.70)]
EYE_DEPTH = 0.26

# The head topples off the base around this point
NECK = Vector((0, 0, 0.5))

YAW = -0.3839724361896515


def prism(bm, points, depth, mat_index=0):
    front = [bm.verts.new((x, -depth, z)) for x, z in points]
    back = [bm.verts.new((x, depth, z)) for x, z in points]
    faces = [bm.faces.new(front), bm.faces.new(list(reversed(back)))]
    for i in range(len(points)):
        j = (i + 1) % len(points)
        faces.append(bm.faces.new((front[i], back[i], back[j], front[j])))
    for f in faces:
        f.material_index = mat_index


def make_head_mesh():
    bm = bmesh.new()
    prism(bm, HEAD, HEAD_DEPTH)
    prism(bm, CHEEK, CHEEK_DEPTH)
    prism(bm, EYE, EYE_DEPTH, 1)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("KnightHead")
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(bpy.data.materials["Piece"])
    mesh.materials.append(bpy.data.materials["Gunmetal"])
    return mesh


def split_old_knight(old):
    # Keeps the revolved base (z <= 0.5) and drops the old head
    bm = bmesh.new()
    bm.from_mesh(old.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z > 0.55], context="VERTS")
    mesh = bpy.data.meshes.new("KnightBase")
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(bpy.data.materials["Piece"])
    return mesh


def build():
    knight = bpy.data.objects["Knight"]
    if "KnightOld" not in bpy.data.objects:
        backup = knight.copy()
        backup.data = knight.data.copy()
        backup.name = "KnightOld"
        bpy.context.scene.collection.objects.link(backup)
        backup.hide_render = True
        backup.hide_viewport = True

    base_mesh = split_old_knight(bpy.data.objects["KnightOld"])
    head_mesh = make_head_mesh()

    bm = bmesh.new()
    bm.from_mesh(base_mesh)
    bm.from_mesh(head_mesh)
    combined = bpy.data.meshes.new("Knight")
    bm.to_mesh(combined)
    bm.free()
    combined.materials.append(bpy.data.materials["Piece"])
    combined.materials.append(bpy.data.materials["Gunmetal"])

    old_mesh = knight.data
    knight.data = combined
    if old_mesh.users == 0:
        bpy.data.meshes.remove(old_mesh)
    return base_mesh, head_mesh


# name: list of per-frame (base transform, head transform)
# A transform is (offset xyz, rotation xyz in degrees, scale xyz) applied around the piece's foot
def T(offset=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    return (offset, rot, scale)


def whole(t):
    return (t, t)


SQUASH = T(scale=(1.08, 1.08, 0.86))
STRETCH = T(scale=(0.92, 0.92, 1.12))
ANIMS = {
    "Idle": [whole(T()), whole(T()), whole(T(scale=(1.03, 1.03, 0.95))), whole(T())],
    "Hop": [whole(SQUASH), whole(STRETCH), whole(T(scale=(0.95, 0.95, 1.07))), whole(T()), whole(SQUASH), whole(T())],
    "Hit": [whole(T(rot=(0, -8, 0), scale=(1.06, 1.06, 0.9))), whole(T(rot=(0, 6, 0), scale=(0.95, 0.95, 1.06))), whole(T())],
    "Death": [
        whole(T()),
        (T(), T(offset=(0, 0, 0.12), rot=(0, 5, 0))),
        (T(), T(offset=(0.05, 0, 0.28), rot=(0, 15, 0))),
        (T(scale=(1, 1, 0.9)), T(offset=(0.1, 0, -0.1), rot=(0, 40, 0))),
        (T(scale=(1.1, 1.1, 0.4)), T(offset=(0.25, 0, -0.55), rot=(0, 90, 0), scale=(0.6, 0.6, 0.6))),
        (T(scale=(0.8, 0.8, 0.2)), T(offset=(0.3, 0, -0.62), rot=(0, 90, 0), scale=(0.3, 0.3, 0.3))),
    ],
}


def apply(obj, t, pivot=Vector()):
    offset, rot, scale = t
    yaw = Matrix.Rotation(YAW, 4, "Z")
    tilt = Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(rot[1]), 4, "Y") @ Matrix.Translation(-pivot)
    pre = Matrix.Diagonal((1.35 * scale[0], 1.35 * scale[1], scale[2], 1))
    obj.matrix_world = Matrix.Translation(offset) @ tilt @ yaw @ pre


def render(base_mesh, head_mesh, out_dir=FRAMES, preview_only=False):
    scene = bpy.context.scene
    hidden = {}
    for o in scene.objects:
        if o.type == "MESH":
            hidden[o.name] = o.hide_render
            o.hide_render = True

    base = bpy.data.objects.new("RenderBase", base_mesh)
    head = bpy.data.objects.new("RenderHead", head_mesh)
    for o in (base, head):
        scene.collection.objects.link(o)

    written = []
    try:
        for anim, frames in ANIMS.items():
            for i, (bt, ht) in enumerate(frames):
                if preview_only and (anim, i) != ("Idle", 0):
                    continue
                apply(base, bt)
                apply(head, ht, NECK)
                path = os.path.join(out_dir, f"Knight_{anim}_{i}.png")
                scene.render.filepath = path
                bpy.ops.render.render(write_still=True)
                written.append(path)
    finally:
        bpy.data.objects.remove(base)
        bpy.data.objects.remove(head)
        for name, value in hidden.items():
            bpy.data.objects[name].hide_render = value
    return written


if __name__ == "__main__":
    base_mesh, head_mesh = build()
    render(base_mesh, head_mesh)
