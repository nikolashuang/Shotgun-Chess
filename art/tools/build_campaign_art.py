# Builds the campaign and menu images: node icons and logo from art/reference,
# islands from the build_islands.py renders in art/campaign/islands, and the area map parchment.
# Run from the repo root: python art/tools/build_campaign_art.py
# Outputs go to art/campaign/. Upload them to Roblox and put the asset ids in CampaignArt.luau.
import math, os, sys
from PIL import Image, ImageDraw
import numpy as np

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
REFERENCE = os.path.join(ROOT, "art", "reference", "campaign_reference.png")
LOGO = os.path.join(ROOT, "art", "reference", "logo_source.png")
OUT = os.path.join(ROOT, "art", "campaign")

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

# Parchment behind the area maps, in pixels; shown about 4x larger in game
PAPER_SIZE = (300, 120)
PAPER_SEED = 7
# Lightest to darkest paper tones, the last two only appear near the burnt edges
PAPER_TONES = [(0xF4, 0xE6, 0xCC), (0xF1, 0xD4, 0xAC), (0xE4, 0xBE, 0x92), (0xD4, 0x9A, 0x77), (0x9C, 0x57, 0x4B)]


def polygon(cx, cy, shape, radius):
    if shape == "octagon":
        corner = radius / math.cos(math.radians(22.5))
        angles = [22.5 + 45 * i for i in range(8)]
    else:
        corner = radius
        angles = [90 + 60 * i for i in range(6)]

    return [(cx + corner * math.cos(math.radians(a)), cy + corner * math.sin(math.radians(a))) for a in angles]


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

    atlas = add_mystery(atlas)
    atlas.save(os.path.join(OUT, "NodeIcons.png"))


# "?" drawn in pixels, scaled up 5x; g is the gold fill, h its highlight
QUESTION = [
    ".gggg.",
    "gh..gg",
    "....gg",
    "...gg.",
    "..gg..",
    "..gg..",
    "......",
    "..gg..",
]
QUESTION_SCALE = 5


# The Mystery badge: the Treasure badge's gold octagon, emptied and stamped with a big gold question mark
def add_mystery(atlas):
    treasure = atlas.crop((2 * TILE, 0, 3 * TILE, TILE))
    tile = treasure.copy()
    px = tile.load()

    # Paint over the chest with the badge's dark fill, sampled just inside the rim
    fill = px[29, TILE // 2]
    inner = Image.new("L", (TILE, TILE), 0)
    corner = 25 / math.cos(math.radians(22.5))
    points = [(TILE / 2 + corner * math.cos(math.radians(22.5 + 45 * i)), TILE / 2 + corner * math.sin(math.radians(22.5 + 45 * i))) for i in range(8)]
    ImageDraw.Draw(inner).polygon(points, fill=255)
    tile.paste(Image.new("RGBA", (TILE, TILE), fill), (0, 0), inner)

    gold, light, ink = (0xE6, 0xB0, 0x48, 255), (0xFF, 0xE2, 0x8A, 255), (0x2A, 0x1C, 0x14, 255)
    width, height = len(QUESTION[0]) * QUESTION_SCALE, len(QUESTION) * QUESTION_SCALE
    left, top = (TILE - width) // 2, (TILE - height) // 2
    glyph = Image.new("RGBA", (width + 2, height + 2), (0, 0, 0, 0))
    gp = glyph.load()

    for y, line in enumerate(QUESTION):
        for x, ch in enumerate(line):
            if ch == ".": continue
            for dy in range(QUESTION_SCALE):
                for dx in range(QUESTION_SCALE):
                    gp[1 + x * QUESTION_SCALE + dx, 1 + y * QUESTION_SCALE + dy] = light if ch == "h" or dy == 0 else gold

    # One pixel dark outline so the mark reads on the badge
    outlined = glyph.copy()
    op = outlined.load()
    for y in range(glyph.height):
        for x in range(glyph.width):
            if gp[x, y][3]: continue
            for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if 0 <= nx < glyph.width and 0 <= ny < glyph.height and gp[nx, ny][3]:
                    op[x, y] = ink
                    break

    tile.alpha_composite(outlined, (left - 1, top - 1))

    grown = Image.new("RGBA", (atlas.width + TILE, TILE), (0, 0, 0, 0))
    grown.paste(atlas, (0, 0))
    grown.paste(tile, (atlas.width, 0))
    print("Mystery", "x", atlas.width)

    return grown


# Sources with transparency keep it, snapped to fully on or off so pixel edges stay hard.
# Opaque sources have their black background removed by flood filling dark pixels from the image border
def build_logo():
    source = Image.open(LOGO)
    image = source.convert("RGB")
    pixels = np.array(image).astype(int)
    height, width = pixels.shape[:2]

    if "A" in source.getbands():
        alpha = np.array(source.getchannel("A")) >= 128
        rgba = np.dstack([pixels, np.where(alpha, 255, 0)]).astype(np.uint8)
        save_logo(Image.fromarray(rgba, "RGBA"))
        return

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
    save_logo(Image.fromarray(rgba, "RGBA"))


def save_logo(logo):
    logo = logo.crop(logo.getbbox())

    size = (LOGO_WIDTH, round(logo.height * LOGO_WIDTH / logo.width))
    logo = logo.resize(size, Image.LANCZOS)
    logo.save(os.path.join(OUT, "Logo.png"))
    print("Logo", size)


def smooth_noise(rng, width, height, cell):
    grid = rng.random((height // cell + 2, width // cell + 2))
    image = Image.fromarray((grid * 255).astype(np.uint8), "L")
    return np.array(image.resize((width + cell, height + cell), Image.BICUBIC))[:height, :width] / 255


# Pixel parchment with ragged edges, stains, two fold creases and darkened edges
def build_paper():
    rng = np.random.default_rng(PAPER_SEED)
    width, height = PAPER_SIZE
    inset = 5

    # Ragged edges: each side wanders in and out by a few pixels
    def edge(length):
        walk = np.cumsum(rng.integers(-1, 2, length))
        return np.clip(inset + walk - walk.mean(), 1, inset * 2).astype(int)

    top, bottom, left, right = edge(width), edge(width), edge(height), edge(height)
    ys, xs = np.mgrid[0:height, 0:width]
    inside = (ys >= top[xs]) & (ys < height - bottom[xs]) & (xs >= left[ys]) & (xs < width - right[ys])

    # Distance to the nearest edge, for the burnt rim
    distance = np.minimum.reduce([ys - top[xs], height - 1 - bottom[xs] - ys, xs - left[ys], width - 1 - right[ys] - xs])

    stains = smooth_noise(rng, width, height, 18) * 0.7 + smooth_noise(rng, width, height, 6) * 0.3
    tone = np.digitize(stains, [0.3, 0.72, 0.9])
    tone[distance < 6] = np.maximum(tone[distance < 6], 2)
    tone[distance < 3] = 3
    tone[distance < 1] = 4

    # Fold creases a third of the way in from each side
    for x in (width // 3, width * 2 // 3):
        tone[:, x] = np.maximum(tone[:, x], 2)

    pixels = np.zeros((height, width, 4), np.uint8)
    for i, color in enumerate(PAPER_TONES):
        pixels[(tone == i) & inside] = color + (255,)

    paper = outline(Image.fromarray(pixels, "RGBA"))
    paper.save(os.path.join(OUT, "Paper.png"))
    print("Paper", paper.size)


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
build_nodes(reference)
build_logo()
build_islands()
build_paper()
