# Outlines the Blender menu renders and generates the CRT filter textures.
# Run from the repo root after build_ribbon.py: python art/tools/build_menu_art.py
# Upload art/menu/Ribbon.png, Scanlines.png and Vignette.png and put the asset ids in MenuArt.luau.
import os, sys
from PIL import Image

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
OUT = os.path.join(ROOT, "art", "menu")
OUTLINE = (0x1E, 0x18, 0x20, 255)

# One dark line every SCANLINE_PERIOD pixel rows; the texture is tiled over the whole screen
SCANLINE_PERIOD = 3
SCANLINE_ALPHA = 110
VIGNETTE_SIZE = 256
# Vignette darkness at the corners (0-255) and how far in it starts (0 center, 1 corner)
VIGNETTE_ALPHA = 200
VIGNETTE_START = 0.45


def outline(image):
    image = image.convert("RGBA")
    w, h = image.size
    px = image.load()
    solid = [[px[x, y][3] >= 128 for x in range(w)] for y in range(h)]
    out = Image.new("RGBA", (w + 2, h + 2), (0, 0, 0, 0))
    op = out.load()
    for y in range(h):
        for x in range(w):
            if solid[y][x]:
                op[x + 1, y + 1] = px[x, y][:3] + (255,)
    for y in range(h + 2):
        for x in range(w + 2):
            if op[x, y][3]: continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx - 1, y + dy - 1
                if 0 <= nx < w and 0 <= ny < h and solid[ny][nx]:
                    op[x, y] = OUTLINE
                    break
    return out


def scanlines():
    image = Image.new("RGBA", (1, SCANLINE_PERIOD), (0, 0, 0, 0))
    image.putpixel((0, SCANLINE_PERIOD - 1), (0, 0, 0, SCANLINE_ALPHA))
    return image


def vignette():
    size = VIGNETTE_SIZE
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = image.load()
    for y in range(size):
        for x in range(size):
            dx = (x + 0.5) / size * 2 - 1
            dy = (y + 0.5) / size * 2 - 1
            d = min((dx * dx + dy * dy) ** 0.5 / 2 ** 0.5, 1)
            t = max(0, (d - VIGNETTE_START) / (1 - VIGNETTE_START))
            px[x, y] = (0, 0, 0, round(VIGNETTE_ALPHA * t * t))
    return image


os.makedirs(OUT, exist_ok=True)
ribbon = outline(Image.open(os.path.join(OUT, "Ribbon_raw.png")))
ribbon.save(os.path.join(OUT, "Ribbon.png"))
scanlines().save(os.path.join(OUT, "Scanlines.png"))
vignette().save(os.path.join(OUT, "Vignette.png"))
print("Ribbon", ribbon.size)
