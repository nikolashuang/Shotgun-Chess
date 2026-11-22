# Outlines the build_armory_icons.py renders in art/armory/icons and packs them into one sheet.
# Run from the repo root: python art/tools/build_armory_art.py
# Upload art/armory/ArmoryIcons.png and put the asset id in ArmoryArt.luau.
import os, sys
from PIL import Image

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
ICONS = os.path.join(ROOT, "art", "armory", "icons")
OUT = os.path.join(ROOT, "art", "armory")
OUTLINE = (0x1E, 0x18, 0x20, 255)

# Same order as ArmoryArt.IconOrder
ORDER = [
    "ReaperPassive", "ReaperSpecial", "ReaperUltimate",
    "HunterPassive", "HunterSpecial", "HunterUltimate",
    "GunslingerPassive", "GunslingerSpecial", "GunslingerUltimate",
    "OutlawPassive", "OutlawSpecial", "OutlawUltimate",
    "Siege", "Duels", "Practice", "Queue", "Challenge",
    "Pouch", "GlobalQueue",
]
# Render size plus a 1 pixel outline on each side
TILE = 66
RENDER = 64
# Icons taken from the in-game sprites instead of a render: (frame in art/frames, scale)
SPRITES = {
    "ReaperPassive": ("Soul_2.png", 2),
}
COLUMNS = 4


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


rows = (len(ORDER) + COLUMNS - 1) // COLUMNS
sheet = Image.new("RGBA", (TILE * COLUMNS, TILE * rows), (0, 0, 0, 0))

def sprite_icon(frame, scale):
    sprite = Image.open(os.path.join(ROOT, "art", "frames", frame)).convert("RGBA")
    sprite = sprite.resize((sprite.width * scale, sprite.height * scale), Image.NEAREST)
    canvas = Image.new("RGBA", (RENDER, RENDER), (0, 0, 0, 0))
    canvas.paste(sprite, ((RENDER - sprite.width) // 2, (RENDER - sprite.height) // 2))
    return canvas


for i, name in enumerate(ORDER):
    if name in SPRITES:
        icon = outline(sprite_icon(*SPRITES[name]))
    else:
        icon = outline(Image.open(os.path.join(ICONS, name + ".png")))
    sheet.paste(icon, ((i % COLUMNS) * TILE, (i // COLUMNS) * TILE))

sheet.save(os.path.join(OUT, "ArmoryIcons.png"))
sheet.resize((sheet.width * 4, sheet.height * 4), Image.NEAREST).save(os.path.join(OUT, "ArmoryIcons_preview.png"))
print("packed", len(ORDER), sheet.size)
