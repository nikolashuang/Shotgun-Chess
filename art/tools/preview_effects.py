# Contact sheet of effect frames on a board-colored background, for checking renders: python art/tools/preview_effects.py
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FRAMES = os.path.join(ROOT, "frames")
OUT = os.path.join(ROOT, "test", "effects", "class_effects.png")
OUTLINE = (0x17, 0x1D, 0x32, 255)
SCALE = 5
NAMES = ["Soul", "Bolt", "Trap", "TrapSnap", "Bolas", "BolasBound", "Revolver", "Mark", "Smoke"]


def outlined(im):
    im = im.convert("RGBA")
    w, h = im.size
    px = im.load()
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    op = out.load()
    solid = lambda x, y: 0 <= x < w and 0 <= y < h and px[x, y][3] >= 128
    for y in range(h):
        for x in range(w):
            if solid(x, y):
                op[x, y] = px[x, y][:3] + (255,)
            elif any(solid(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                op[x, y] = OUTLINE
    return out


rows = []
for name in NAMES:
    frames = sorted((f for f in os.listdir(FRAMES) if f.rsplit("_", 1)[0] == name), key=lambda f: int(f.rsplit("_", 1)[1][:-4]))
    rows.append([outlined(Image.open(os.path.join(FRAMES, f))) for f in frames])

width = max(sum(im.width + 4 for im in row) for row in rows) + 4
height = sum(max(im.height for im in row) + 4 for row in rows) + 4
sheet = Image.new("RGBA", (width, height), (0xD4, 0x9A, 0x77, 255))
y = 4
for row in rows:
    x = 4
    for im in row:
        sheet.alpha_composite(im, (x, y))
        x += im.width + 4
    y += max(im.height for im in row) + 4

sheet.resize((width * SCALE, height * SCALE), Image.NEAREST).save(OUT)
print(OUT, sheet.size)
