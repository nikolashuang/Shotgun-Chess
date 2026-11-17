# Builds the campaign and menu images from the reference art in art/reference
# and the island renders made by build_islands.py in art/campaign/islands.
# Run from the repo root: python art/tools/build_campaign_art.py
# Outputs go to art/campaign/. Upload them to Roblox and put the asset ids in CampaignArt.luau.
import math, os, sys
from PIL import Image, ImageDraw
import numpy as np

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
REFERENCE = os.path.join(ROOT, "art", "reference", "campaign_reference.png")
LOGO = os.path.join(ROOT, "art", "reference", "logo_source.png")
OUT = os.path.join(ROOT, "art", "campaign")

# Painted region panels in the reference sheet: left, top, right, bottom
REGIONS = {
    "Training": (16, 112, 496, 438),
    "Forest": (516, 112, 1010, 438),
    "Cliffside": (1032, 114, 1522, 438),
    "Outskirts": (14, 474, 538, 770),
    "Gravehollow": (556, 474, 1086, 770),
}

# Node badges from the route strip: (type, center x, center y, shape, radius)
# Octagons are measured by apothem, hexagons by corner radius
NODES = [
    ("Combat", 792.5, 917.5, "octagon", 31),
    ("Rest", 897, 917.5, "octagon", 31),
    ("Treasure", 1103.5, 918, "octagon", 31),
    ("Queen", 1309.5, 917, "hexagon", 42),
    ("King", 1439, 915.5, "hexagon", 47),
]
TILE = 100

LOGO_WIDTH = 1024

ISLANDS = os.path.join(OUT, "islands")
ISLAND_ORDER = ["Training", "Forest", "Cliffside", "Outskirts", "Gravehollow"]
LOCK_LAYERS = ["ChainA", "ChainB", "Lock"]
ISLAND_SIZE = 160
OUTLINE = (0x1E, 0x18, 0x20, 255)


def polygon(cx, cy, shape, radius):
    if shape == "octagon":
        corner = radius / math.cos(math.radians(22.5))
        angles = [22.5 + 45 * i for i in range(8)]
    else:
        corner = radius
        angles = [90 + 60 * i for i in range(6)]

    return [(cx + corner * math.cos(math.radians(a)), cy + corner * math.sin(math.radians(a))) for a in angles]


def build_regions(ref):
    for name, box in REGIONS.items():
        ref.crop(box).save(os.path.join(OUT, f"Region_{name}.png"))
        print(name, box[2] - box[0], box[3] - box[1])


def build_nodes(ref):
    atlas = Image.new("RGBA", (TILE * len(NODES), TILE), (0, 0, 0, 0))

    for i, (name, cx, cy, shape, radius) in enumerate(NODES):
        left, top = round(cx - TILE / 2), round(cy - TILE / 2)
        tile = ref.crop((left, top, left + TILE, top + TILE)).convert("RGBA")

        # Supersampled mask so the badge edge is clean
        scale = 4
        mask = Image.new("L", (TILE * scale, TILE * scale), 0)
        points = [((x - left) * scale, (y - top) * scale) for x, y in polygon(cx, cy, shape, radius)]
        ImageDraw.Draw(mask).polygon(points, fill=255)
        tile.putalpha(mask.resize((TILE, TILE), Image.LANCZOS))

        atlas.paste(tile, (i * TILE, 0))
        print(name, "x", i * TILE)

    atlas.save(os.path.join(OUT, "NodeIcons.png"))


# Removes the black background by flood filling dark pixels from the image border
def build_logo():
    image = Image.open(LOGO).convert("RGB")
    pixels = np.array(image).astype(int)
    height, width = pixels.shape[:2]
    dark = pixels.max(axis=2) < 48

    background = np.zeros((height, width), bool)
    stack = [(0, x) for x in range(width)] + [(height - 1, x) for x in range(width)]
    stack += [(y, 0) for y in range(height)] + [(y, width - 1) for y in range(height)]

    while stack:
        y, x = stack.pop()
        if background[y, x] or not dark[y, x]:
            continue

        background[y, x] = True

        for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
            if 0 <= ny < height and 0 <= nx < width and not background[ny, nx]:
                stack.append((ny, nx))

    rgba = np.dstack([pixels, np.where(background, 0, 255)]).astype(np.uint8)
    logo = Image.fromarray(rgba, "RGBA")
    logo = logo.crop(logo.getbbox())

    size = (LOGO_WIDTH, round(logo.height * LOGO_WIDTH / logo.width))
    logo = logo.resize(size, Image.LANCZOS)
    logo.save(os.path.join(OUT, "Logo.png"))
    print("Logo", size)


# 1px dark outline around every opaque pixel, like the piece sprites
def outline(image):
    pixels = np.array(image)
    alpha = pixels[..., 3] > 0
    grown = alpha.copy()
    grown[1:, :] |= alpha[:-1, :]
    grown[:-1, :] |= alpha[1:, :]
    grown[:, 1:] |= alpha[:, :-1]
    grown[:, :-1] |= alpha[:, 1:]
    pixels[grown & ~alpha] = OUTLINE

    return Image.fromarray(pixels, "RGBA")


# Locked islands are shown desaturated and darkened
def grayscale(image):
    pixels = np.array(image).astype(float)
    luminance = pixels[..., 0] * 0.3 + pixels[..., 1] * 0.59 + pixels[..., 2] * 0.11
    value = luminance * 0.7 + 18
    pixels[..., 0] = value
    pixels[..., 1] = value * 0.97
    pixels[..., 2] = value * 1.04

    return Image.fromarray(np.clip(pixels, 0, 255).astype(np.uint8), "RGBA")


# Row 0: islands in color, row 1: the same islands grayed out, row 2: chain and padlock layers
def build_islands():
    size = ISLAND_SIZE
    atlas = Image.new("RGBA", (size * len(ISLAND_ORDER), size * 3), (0, 0, 0, 0))

    for i, name in enumerate(ISLAND_ORDER):
        island = outline(Image.open(os.path.join(ISLANDS, name + ".png")).convert("RGBA"))
        atlas.paste(island, (i * size, 0))
        atlas.paste(grayscale(island), (i * size, size))

    for i, name in enumerate(LOCK_LAYERS):
        atlas.paste(outline(Image.open(os.path.join(ISLANDS, name + ".png")).convert("RGBA")), (i * size, size * 2))

    atlas.save(os.path.join(OUT, "Islands.png"))
    print("Islands", atlas.size)


os.makedirs(OUT, exist_ok=True)
reference = Image.open(REFERENCE).convert("RGB")
build_regions(reference)
build_nodes(reference)
build_logo()
build_islands()
