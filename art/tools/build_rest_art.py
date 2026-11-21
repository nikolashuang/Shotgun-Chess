# Outlines, firelights and packs the build_rest_camp.py renders in art/campaign/rest into one sheet.
# Run from the repo root: python art/tools/build_rest_art.py
# Also halves the background (art/campaign/RestCamp.png) to RestCampBackground.png so Roblox doesn't shrink it.
# Upload RestCampBackground.png and RestCampFire.png and put the ids in CampaignArt.luau.
import os, sys
from PIL import Image

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
FRAMES_DIR = os.path.join(ROOT, "art", "campaign", "rest")
OUT = os.path.join(ROOT, "art", "campaign", "RestCampFire.png")

VERSIONS = ["Party", "Knight"]
FRAMES = 8
COLUMNS = 4
OUTLINE = (0x1E, 0x18, 0x20, 255)
# Night scene lit by the fire: everything that isn't flame is warmed and dimmed a little
FIRELIGHT = (1.0, 0.82, 0.66)


# Flames glow on their own and the Fallen Knight's cool teal stays cold, so neither gets the warm light
def is_unlit(r, g, b):
    return (r > 200 and b < 140 and r - b > 90) or b > r


def light(image):
    px = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = px[x, y]
            if a == 0 or is_unlit(r, g, b): continue
            px[x, y] = (round(r * FIRELIGHT[0]), round(g * FIRELIGHT[1]), round(b * FIRELIGHT[2]), a)
    return image


def outline(image):
    w, h = image.size
    px = image.load()
    solid = [[px[x, y][3] >= 128 for x in range(w)] for y in range(h)]
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    op = out.load()
    for y in range(h):
        for x in range(w):
            if solid[y][x]:
                op[x, y] = px[x, y][:3] + (255,)
    for y in range(h):
        for x in range(w):
            if solid[y][x]: continue
            for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if 0 <= nx < w and 0 <= ny < h and solid[ny][nx]:
                    op[x, y] = OUTLINE
                    break
    return out


first = Image.open(os.path.join(FRAMES_DIR, "Party_0.png"))
fw, fh = first.size
rows_per_version = (FRAMES + COLUMNS - 1) // COLUMNS
sheet = Image.new("RGBA", (fw * COLUMNS, fh * rows_per_version * len(VERSIONS)), (0, 0, 0, 0))

for v, version in enumerate(VERSIONS):
    for i in range(FRAMES):
        frame = outline(light(Image.open(os.path.join(FRAMES_DIR, f"{version}_{i}.png")).convert("RGBA")))
        sheet.paste(frame, ((i % COLUMNS) * fw, (v * rows_per_version + i // COLUMNS) * fh))

sheet.save(OUT)

background = Image.open(os.path.join(ROOT, "art", "campaign", "RestCamp.png")).convert("RGB")
background.resize((background.width // 2, background.height // 2), Image.LANCZOS).save(os.path.join(ROOT, "art", "campaign", "RestCampBackground.png"))
print("frame", fw, fh, "sheet", sheet.size)
