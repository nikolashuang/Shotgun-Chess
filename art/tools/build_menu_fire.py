# Run inside Blender (Text Editor > Run Script) with art/ShotgunChessSprites.blend open.
# Builds the main menu campfire flame that plays over art/menu/MenuBackground.png in a temporary scene:
# the shared flame from flame.py.
# Renders FRAMES looping frames to art/menu/fire/Fire_<i>.png, then removes the scene again.
# build_menu_background.py packs them into one sheet.
import bpy, math, os, sys
from mathutils import Vector

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(bpy.data.filepath)), "art", "tools"))
import flame

ROOT = os.path.dirname(os.path.dirname(bpy.data.filepath))
OUT = os.path.join(ROOT, "art", "menu", "fire")
SCENE_NAME = "MenuFire"

FRAMES = 12

# The render covers this part of the 1670x942 background, in background pixels: left, top, right, bottom
# One world unit is 100 background pixels; RENDER_SCALE background pixels make one render pixel, like the art's own pixels
REGION = (749, 652, 909, 832)
PIXELS_PER_UNIT = 100
RENDER_SCALE = 4

# Inside the log teepee in the stone pit below the King; the flame is a little bigger to match the art's pieces
FIRE_BASE = (829, 822)
FLAME_SCALE = 1.1

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


def glow(name, color):
    name = "MenuFire" + name
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

    camera_data = bpy.data.cameras.new("MenuFireCam")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = (REGION[2] - REGION[0]) / PIXELS_PER_UNIT
    camera = bpy.data.objects.new("MenuFireCam", camera_data)
    camera.rotation_euler = (math.radians(90), 0, 0)
    camera.location = (0, -30, 0)
    scene.collection.objects.link(camera)
    scene.camera = camera

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

    for collection in list(scene.collection.children_recursive):
        bpy.data.collections.remove(collection)

    bpy.data.scenes.remove(scene)

    for name in CREATED_MATERIALS:
        mat = bpy.data.materials.get(name)

        if mat and mat.users == 0:
            bpy.data.materials.remove(mat)


scene = setup_scene()
collection = bpy.data.collections.new("MenuFire")
scene.collection.children.link(collection)
fire = flame.Fire(collection, at(*FIRE_BASE), glow, FLAME_SCALE)
os.makedirs(OUT, exist_ok=True)

try:
    for i in range(FRAMES):
        fire.pose(i / FRAMES)
        scene.render.filepath = os.path.join(OUT, f"Fire_{i}.png")
        bpy.ops.render.render(write_still=True, scene=scene.name)
finally:
    remove_scene(scene)
