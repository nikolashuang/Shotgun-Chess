# Run inside Blender (Text Editor > Run Script) with art/ShotgunChessSprites.blend open.
# Builds the gold banner ribbon shown behind main menu buttons on hover and renders it to
# art/menu/Ribbon_raw.png. Then run `python art/tools/build_menu_art.py` from the repo root to outline it.
import bpy, bmesh, math, os

ROOT = os.path.dirname(os.path.dirname(bpy.data.filepath))
OUT = os.path.join(ROOT, "art", "menu")

# World units per sprite pixel
UPP = 0.1
SIZE = (112, 32)

BAND_HALF = 4.1
BAND_HEIGHT = 1.8
# How far the band's ends dip below its middle
BAND_ARCH = 0.35
BAND_SEGMENTS = 24
HIGHLIGHT = 0.22
SHADOW = 0.22

TAIL_LENGTH = 1.7
TAIL_OVERLAP = 0.6
TAIL_DROP = 0.6
TAIL_HEIGHT = 1.5
NOTCH = 0.55

# Ribbons are built away from the pieces and guns so the render never overlaps them
ORIGIN_Z = -20.0

# Flat colors, so every pixel comes out exactly on palette
COLORS = {
    "RibbonFront": "E6C47C",
    "RibbonHighlight": "F1D4AC",
    "RibbonShadow": "A8844A",
    "RibbonTail": "A8844A",
    "RibbonTailShadow": "8A5A2A",
    "RibbonFold": "5E3A22",
}
MATS = list(COLORS)


def srgb_to_linear(c):
    c = c / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def flat_material(name, hex_color):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    emission = nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value = [srgb_to_linear(int(hex_color[i:i + 2], 16)) for i in (0, 2, 4)] + [1]
    output = nodes.new("ShaderNodeOutputMaterial")
    mat.node_tree.links.new(emission.outputs["Emission"], output.inputs["Surface"])
    return mat


def arch(x):
    return -BAND_ARCH * (x / BAND_HALF) ** 2


def face(bm, points, y, mat):
    verts = [bm.verts.new((x, y, z)) for x, z in points]
    f = bm.faces.new(verts)
    f.material_index = MATS.index(mat)


def band(bm):
    # Three stacked strips (highlight, front, shadow) that follow the arch
    edges = [BAND_HEIGHT / 2, BAND_HEIGHT / 2 - HIGHLIGHT, -BAND_HEIGHT / 2 + SHADOW, -BAND_HEIGHT / 2]
    mats = ["RibbonHighlight", "RibbonFront", "RibbonShadow"]

    for i in range(BAND_SEGMENTS):
        x0 = -BAND_HALF + 2 * BAND_HALF * i / BAND_SEGMENTS
        x1 = -BAND_HALF + 2 * BAND_HALF * (i + 1) / BAND_SEGMENTS
        for strip, mat in enumerate(mats):
            top, bottom = edges[strip], edges[strip + 1]
            face(bm, [(x0, bottom + arch(x0)), (x1, bottom + arch(x1)), (x1, top + arch(x1)), (x0, top + arch(x0))], 0, mat)


def tail(bm, side):
    # Tail behind the band end, dropped a little, with a V notch cut into its outer end
    end = side * BAND_HALF
    inner = end - side * TAIL_OVERLAP
    outer = end + side * TAIL_LENGTH
    middle = arch(end) - TAIL_DROP
    top = middle + TAIL_HEIGHT / 2
    bottom = middle - TAIL_HEIGHT / 2
    shade = bottom + SHADOW
    notch = outer - side * NOTCH
    # Where the shadow line meets the notch's lower edge
    shade_x = outer - side * NOTCH * (shade - bottom) / (middle - bottom)

    face(bm, [(inner, shade), (shade_x, shade), (notch, middle), (outer, top), (inner, top)], 0.3, "RibbonTail")
    face(bm, [(inner, bottom), (outer, bottom), (shade_x, shade), (inner, shade)], 0.3, "RibbonTailShadow")

    # Fold where the band tucks back into the tail, just under the band's end
    band_bottom = -BAND_HEIGHT / 2 + arch(end)
    face(bm, [(end, band_bottom), (inner, band_bottom), (end, bottom)], 0.15, "RibbonFold")


def build():
    name = "MenuRibbon"
    if name in bpy.data.objects:
        old = bpy.data.objects[name]
        mesh = old.data
        bpy.data.objects.remove(old)
        bpy.data.meshes.remove(mesh)

    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    band(bm)
    tail(bm, -1)
    tail(bm, 1)
    bm.to_mesh(mesh)
    bm.free()

    for mat_name, hex_color in COLORS.items():
        mesh.materials.append(flat_material(mat_name, hex_color))

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = (0, 0, ORIGIN_Z)
    obj.hide_render = True
    return obj


def render(obj):
    scene = bpy.context.scene
    cam = bpy.data.objects["SpriteCam"]
    os.makedirs(OUT, exist_ok=True)

    saved = (cam.location.copy(), cam.rotation_euler.copy(), cam.data.ortho_scale,
             scene.render.resolution_x, scene.render.resolution_y, scene.render.filepath, scene.render.filter_size,
             scene.view_settings.view_transform, {o.name: o.hide_render for o in bpy.data.objects})
    try:
        for o in bpy.data.objects:
            if o.type == "MESH":
                o.hide_render = o != obj
        obj.hide_render = False
        # Faces face the camera along -y, so nearer layers (smaller y) draw on top
        cam.rotation_euler = (math.radians(90), 0, 0)
        # The tails hang below the band, so the frame is centered a little low
        cam.location = (0, -20, ORIGIN_Z - 0.4)
        cam.data.ortho_scale = UPP * max(SIZE)
        scene.render.resolution_x, scene.render.resolution_y = SIZE
        scene.render.filter_size = 0
        scene.view_settings.view_transform = "Standard"
        scene.render.filepath = os.path.join(OUT, "Ribbon_raw.png")
        bpy.ops.render.render(write_still=True)
    finally:
        (cam.location, cam.rotation_euler, cam.data.ortho_scale, scene.render.resolution_x, scene.render.resolution_y,
         scene.render.filepath, scene.render.filter_size, scene.view_settings.view_transform, hidden) = saved
        for o in bpy.data.objects:
            o.hide_render = hidden[o.name]


render(build())
print("Built menu ribbon")
