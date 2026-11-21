# Builds the three Rest Site choice cards from the build_armory_icons.py renders (RestBandage, RestTrain, RestUpgrade).
# Run from the repo root: python art/tools/build_rest_cards.py
# Upload art/campaign/RestCards.png and put the asset id in CampaignArt.luau (REST_CARDS).
import math, os, sys
from PIL import Image, ImageDraw

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
ICONS = os.path.join(ROOT, "art", "armory", "icons")
OUT = os.path.join(ROOT, "art", "campaign")

CARD = (96, 72)
OUTLINE = (0x1E, 0x18, 0x20, 255)

# Same order as CampaignArt.RestCardOrder: background, rays, rim
CARDS = [
    ("RestBandage", (0x5E, 0xA8, 0x4E), (0x74, 0xBC, 0x5E), (0xB4, 0xE8, 0x8E)),
    ("RestTrain", (0xA8, 0x48, 0x34), (0xC8, 0x64, 0x44), (0xF1, 0xA0, 0x72)),
    ("RestUpgrade", (0x24, 0x4E, 0x8A), (0x34, 0x64, 0xA8), (0x9E, 0xC4, 0xEE)),
]
BLUEPRINT_LINE = (0xE8, 0xF4, 0xFF, 255)
BLUEPRINT_FILL = (0x8E, 0xB8, 0xE8, 255)
# The gun's body, a touch lighter than the paper
BLUEPRINT_SHADE = (0x34, 0x66, 0xAC, 255)


def outline(image):
    w, h = image.size
    px = image.load()
    out = image.copy()
    op = out.load()
    for y in range(h):
        for x in range(w):
            if px[x, y][3] >= 128: continue
            for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if 0 <= nx < w and 0 <= ny < h and px[nx, ny][3] >= 128:
                    op[x, y] = OUTLINE
                    break
    return out


def solidify(image):
    px = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = px[x, y]
            px[x, y] = (r, g, b, 255) if a >= 128 else (0, 0, 0, 0)
    return image


# White linework on a pale fill, like a drawing on blueprint paper
def blueprint(image):
    w, h = image.size
    px = image.load()
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    op = out.load()
    for y in range(h):
        for x in range(w):
            if not px[x, y][3]: continue
            edge = any(not (0 <= nx < w and 0 <= ny < h) or not px[nx, ny][3] for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
            # Where two parts meet (wood against steel) draw a fainter seam so the gun's pieces read
            seam = any(px[nx, ny][3] and sum(abs(px[x, y][i] - px[nx, ny][i]) for i in range(3)) > 50 for nx, ny in ((x + 1, y), (x, y + 1)) if nx < w and ny < h)
            op[x, y] = BLUEPRINT_LINE if edge else BLUEPRINT_FILL if seam else BLUEPRINT_SHADE
    return out


def rays(draw, center, color, count=12):
    cx, cy = center
    for i in range(count):
        if i % 2: continue
        a0 = 2 * math.pi * i / count
        a1 = 2 * math.pi * (i + 1) / count
        draw.polygon([(cx, cy), (cx + 120 * math.cos(a0), cy + 120 * math.sin(a0)), (cx + 120 * math.cos(a1), cy + 120 * math.sin(a1))], fill=color)


def grid(draw, color):
    for x in range(4, CARD[0], 8):
        draw.line([(x, 0), (x, CARD[1])], fill=color)
    for y in range(4, CARD[1], 8):
        draw.line([(0, y), (CARD[0], y)], fill=color)


# Soft painted blotches, like the reference's green cloth
def mottle(draw, color):
    import random
    rng = random.Random(7)
    for _ in range(14):
        x, y = rng.randrange(CARD[0]), rng.randrange(CARD[1])
        w, h = rng.randrange(10, 26), rng.randrange(6, 14)
        draw.ellipse([x - w, y - h, x + w, y + h], fill=color)


def card(name, base, accent, rim):
    image = Image.new("RGBA", CARD, base + (255,))
    draw = ImageDraw.Draw(image)
    center = (CARD[0] // 2, CARD[1] // 2)

    icon = solidify(Image.open(os.path.join(ICONS, name + ".png")).convert("RGBA"))
    icon = icon.crop(icon.getbbox())

    if name == "RestUpgrade":
        grid(draw, accent + (255,))
        icon = blueprint(icon)
        # Dimension lines above and below the drawing
        left, right = center[0] - icon.width // 2, center[0] + (icon.width + 1) // 2 - 1
        top, bottom = center[1] - icon.height // 2, center[1] + (icon.height + 1) // 2
        # Callout ring around the muzzle
        alpha = icon.getchannel("A")
        muzzle = top + next(y for y in range(icon.height) if alpha.getpixel((icon.width - 1, y)))
        draw.ellipse([right - 7, muzzle - 6, right + 7, muzzle + 8], outline=rim + (255,))
        for y in (top - 6, bottom + 5):
            draw.line([(left, y), (right, y)], fill=rim + (255,))
            draw.line([(left, y - 2), (left, y + 2)], fill=rim + (255,))
            draw.line([(right, y - 2), (right, y + 2)], fill=rim + (255,))
    elif name == "RestBandage":
        mottle(draw, accent + (255,))
        icon = outline(icon)
    else:
        rays(draw, center, accent + (255,))
        icon = outline(icon)

    if name != "RestUpgrade":
        # Ground shadow so the drawing sits on something
        shadow = Image.new("RGBA", CARD, (0, 0, 0, 0))
        bottom = center[1] + icon.height // 2
        ImageDraw.Draw(shadow).ellipse([center[0] - icon.width // 2 + 2, bottom - 6, center[0] + icon.width // 2 - 2, bottom + 3], fill=OUTLINE[:3] + (90,))
        image.alpha_composite(shadow)

    image.alpha_composite(icon, (center[0] - icon.width // 2, center[1] - icon.height // 2))

    # Two pixel frame: a bright inner rim and the dark outline
    draw = ImageDraw.Draw(image)
    draw.rectangle([1, 1, CARD[0] - 2, CARD[1] - 2], outline=rim + (255,))
    draw.rectangle([0, 0, CARD[0] - 1, CARD[1] - 1], outline=OUTLINE)
    return image


sheet = Image.new("RGBA", (CARD[0] * len(CARDS), CARD[1]), (0, 0, 0, 0))
for i, entry in enumerate(CARDS):
    sheet.paste(card(*entry), (i * CARD[0], 0))

sheet.save(os.path.join(OUT, "RestCards.png"))
sheet.resize((sheet.width * 4, sheet.height * 4), Image.NEAREST).save(os.path.join(OUT, "RestCards_preview.png"))
print("cards", sheet.size)
