import os
import json
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FRAMES = os.path.join(ROOT, "frames")
OUT_PNG = os.path.join(ROOT, "SpriteAtlas.png")
OUT_LUAU = os.path.join(os.path.dirname(ROOT), "src", "shared", "Sprites", "SpriteConfig.luau")
ASSET_ID = "rbxassetid://110802814818807"

CELL = 32
# Transparent gutter around every sprite so rotated or scaled sampling can't bleed into neighbors
PAD = 2
STRIDE = CELL + PAD * 2
OUTLINE = (0x17, 0x1D, 0x32, 255)
FLASH = (0xFF, 0xFF, 0xFF, 255)
RED = (0xD9, 0x54, 0x4D, 255)
CREAM = (0xF0, 0xE9, 0xD8, 255)
DARK_RED = (0x9E, 0x3A, 0x3C, 255)
GOLD = (0xE6, 0xC4, 0x7C, 255)
BRASS = (0xA8, 0x84, 0x4A, 255)
SLOT = (0x4E, 0x56, 0x6B, 255)
PALETTE = [(0xF0,0xE9,0xD8),(0xB3,0xA8,0x8F),(0xE6,0xC4,0x7C),(0xA8,0x84,0x4A),(0x8A,0x93,0xA6),(0x4E,0x56,0x6B),(0xD9,0x54,0x4D),(0x9E,0x3A,0x3C)]

# White sprites are recolored into the black team set
BLACK_RECOLOR = {
    (0xF0, 0xE9, 0xD8, 255): (0x3B, 0x3F, 0x52, 255),
    (0xB3, 0xA8, 0x8F, 255): (0x26, 0x29, 0x38, 255),
    OUTLINE: CREAM,
}

PIECES = ["Pawn", "Knight", "Bishop", "Rook", "Queen", "King"]
# name: (frames, seconds per frame, looped, flash frames)
ANIMS = {
    "Idle":   (4, 0.22, True, []),
    "Hop":    (6, 0.05, False, []),
    "Hit":    (3, 0.07, False, [0]),
    "Death":  (6, 0.08, False, [0]),
    "Recoil": (4, 0.05, False, []),
}

# Looping board effects from art/tools/build_effects.py: name: (frames, seconds per frame)
EFFECTS = {
    "Stun": (8, 0.08),
    "Arrow": (8, 0.08),
}

def nearest(c):
    return min(PALETTE, key=lambda p: sum((a - b) ** 2 for a, b in zip(p, c[:3])))

def clean(im, flash=False):
    im = im.convert("RGBA")
    w, h = im.size
    px = im.load()
    solid = [[px[x, y][3] >= 128 for x in range(w)] for y in range(h)]
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    op = out.load()
    for y in range(h):
        for x in range(w):
            if solid[y][x]:
                op[x, y] = FLASH if flash else nearest(px[x, y]) + (255,)
    for y in range(h):
        for x in range(w):
            if solid[y][x]: continue
            for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and solid[ny][nx]:
                    op[x, y] = OUTLINE
                    break
    return out

def recolor(im, mapping):
    out = im.copy()
    px = out.load()
    for y in range(out.size[1]):
        for x in range(out.size[0]):
            if px[x, y] in mapping:
                px[x, y] = mapping[px[x, y]]
    return out

def from_mask(rows, colors):
    im = Image.new("RGBA", (len(rows[0]), len(rows)), (0, 0, 0, 0))
    for y, line in enumerate(rows):
        for x, ch in enumerate(line):
            if ch in colors:
                im.putpixel((x, y), colors[ch])
    return im

def tile_mark(size=32, arm=7):
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    red = set()
    for cx, cy, sx, sy in ((1,1,1,1),(size-2,1,-1,1),(1,size-2,1,-1),(size-2,size-2,-1,-1)):
        for i in range(arm):
            for t in range(1):
                red.add((cx + sx * i, cy + sy * t))
                red.add((cx + sx * t, cy + sy * i))
    for (x, y) in red:
        im.putpixel((x, y), RED)
    for (x, y) in red:
        for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
            n = (x + dx, y + dy)
            if n not in red and 0 <= n[0] < size and 0 <= n[1] < size:
                im.putpixel(n, OUTLINE)
    return im

rows = []
for piece in PIECES:
    for anim, (count, _, _, flashes) in ANIMS.items():
        if anim == "Recoil" and piece != "King": continue
        frames = [clean(Image.open(os.path.join(FRAMES, f"{piece}_{anim}_{i}.png")), i in flashes) for i in range(count)]
        black = [f if i in flashes else recolor(f, BLACK_RECOLOR) for i, f in enumerate(frames)]
        rows.append((piece, anim, frames, black))

# Gun sprites and grips come from art/tools/build_guns.py
GUNS = json.load(open(os.path.join(FRAMES, "guns.json")))
gun_images = {name: clean(Image.open(os.path.join(FRAMES, info["Frame"]))) for name, info in GUNS.items()}

# Loaded shell and empty slot for the ammo bar
shell_full = from_mask([
    ".ooo.",
    "occco",
    "orrdo",
    "orrdo",
    "orrdo",
    "orrdo",
    "orrdo",
    "oggbo",
    "oggbo",
    ".ooo.",
], {"o": OUTLINE, "c": CREAM, "r": RED, "d": DARK_RED, "g": GOLD, "b": BRASS})
shell_empty = from_mask([
    ".sss.",
    "s...s",
    "s...s",
    "s...s",
    "s...s",
    "s...s",
    "s...s",
    "s...s",
    "s...s",
    ".sss.",
], {"s": SLOT})

dot_mask = [".oo.", "oxxo", "oxxo", ".oo."]
arc_dot = from_mask(dot_mask, {"o": OUTLINE, "x": RED})
arc_edge = from_mask(dot_mask, {"o": OUTLINE, "x": CREAM})
pellet = from_mask([".oo.", "oxxo", "oxxo", ".oo."], {"o": OUTLINE, "x": CREAM})
mark = tile_mark()

TEAM_WIDTH = STRIDE * 6
width = TEAM_WIDTH * 2
ui_y = len(rows) * STRIDE + PAD

ui_images = [("TileMark", mark), ("ArcDot", arc_dot), ("ArcEdge", arc_edge), ("Pellet", pellet), ("ShellFull", shell_full), ("ShellEmpty", shell_empty)]
for name, img in gun_images.items():
    ui_images.append(("Gun" + name, img))
    ui_images.append(("Gun" + name + "Flipped", img.transpose(Image.FLIP_TOP_BOTTOM)))
for name, (count, _) in EFFECTS.items():
    for i in range(count):
        ui_images.append((f"{name}{i + 1}", clean(Image.open(os.path.join(FRAMES, f"{name}_{i}.png")))))

# Shelf pack the UI sprites below the piece rows
ui = {}
x, y, row_height = PAD, ui_y, 0
for name, img in ui_images:
    w, h = img.size
    if x + w + PAD > width:
        x, y, row_height = PAD, y + row_height + PAD * 2, 0
    ui[name] = (x, y, w, h)
    x += w + PAD * 2
    row_height = max(row_height, h)

height = y + row_height + PAD
atlas = Image.new("RGBA", (width, height), (0, 0, 0, 0))

anim_entries = {}
for r, (piece, anim, frames, black) in enumerate(rows):
    for i, f in enumerate(frames):
        atlas.alpha_composite(f, (PAD + i * STRIDE, PAD + r * STRIDE))
        atlas.alpha_composite(black[i], (TEAM_WIDTH + PAD + i * STRIDE, PAD + r * STRIDE))
    anim_entries.setdefault(piece, {})[anim] = PAD + r * STRIDE

for name, img in ui_images:
    atlas.alpha_composite(img, ui[name][:2])

atlas.save(OUT_PNG)

lines = []
lines.append("-- Generated by art/tools/build_atlas.py")
lines.append("local SpriteConfig = {")
lines.append(f"    ASSET_ID = \"{ASSET_ID}\",")
lines.append(f"    CELL = {CELL},")
lines.append("    -- Distance between frames in the atlas, including the gutter")
lines.append(f"    STRIDE = {STRIDE},")
lines.append("    -- Size of one sprite cell on the board, in tiles")
lines.append("    CELL_TILES = 1.4,")
lines.append("")
lines.append("    Anims = {")
for anim, (count, frame_time, looped, _) in ANIMS.items():
    lines.append(f"        {anim} = {{Frames = {count}, FrameTime = {frame_time}, Looped = {'true' if looped else 'false'}}},")
lines.append("    },")
lines.append("")
lines.append("    -- X offset of each team's sprites in the atlas")
lines.append(f"    Teams = {{White = {PAD}, Black = {TEAM_WIDTH + PAD}}},")
lines.append("")
lines.append("    -- Y offset of each animation row in the atlas")
lines.append("    Pieces = {")
for piece in PIECES:
    entries = ", ".join(f"{a} = {y}" for a, y in anim_entries[piece].items())
    lines.append(f"        {piece} = {{{entries}}},")
lines.append("    },")
lines.append("")
lines.append("    -- Topmost opaque pixel row of each piece's idle sprite")
lines.append("    HeadRows = {")
for piece in PIECES:
    idle = next(frames for p, a, frames, _ in rows if p == piece and a == "Idle")[0]
    top = next(y for y in range(CELL) if any(idle.getpixel((x, y))[3] > 0 for x in range(CELL)))
    lines.append(f"        {piece} = {top},")
lines.append("    },")
lines.append("")
lines.append("    -- Offset X, Offset Y, Width, Height")
lines.append("    Rects = {")
for name, (rx, ry, rw, rh) in ui.items():
    lines.append(f"        {name} = {{{rx}, {ry}, {rw}, {rh}}},")
lines.append("    },")
lines.append("")
lines.append("    -- Looping board effects: one rect per frame")
lines.append("    Effects = {")
for name, (count, frame_time) in EFFECTS.items():
    rects = ", ".join(f"\"{name}{i + 1}\"" for i in range(count))
    lines.append(f"        {name} = {{FrameTime = {frame_time}, Rects = {{{rects}}}}},")
lines.append("    },")
lines.append("")
lines.append("    -- Rect names and grip position (pixels inside the sprite) for each shotgun")
lines.append("    Guns = {")
for name, info in GUNS.items():
    gx, gy = info["Grip"]
    lines.append(f"        {name} = {{Rect = \"Gun{name}\", FlippedRect = \"Gun{name}Flipped\", Grip = Vector2.new({gx}, {gy})}},")
lines.append("    },")
lines.append("}")
lines.append("")
lines.append("return SpriteConfig")
os.makedirs(os.path.dirname(OUT_LUAU), exist_ok=True)
open(OUT_LUAU, "w", newline="\n").write("\n".join(lines) + "\n")

atlas.resize((width * 4, height * 4), Image.NEAREST).save(os.path.join(ROOT, "SpriteAtlas_preview.png"))
print(width, height)
