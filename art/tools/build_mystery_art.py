# Builds the Mystery encounter screens' art in art/campaign/mystery.
# Run from the repo root after build_gunsmith.py: python art/tools/build_mystery_art.py
# - Halves each background (Altar, Ambush, Gunsmith, FallenKnight) to <Name>Background.png so Roblox doesn't shrink it
# - Outlines, firelights and packs the gunsmith renders into GunsmithSheet.png
# - Traces the Fallen Knight's eye into EyeWake.png, lit up when he wakes before his fight
# Upload the pngs and put the ids in CampaignArt.luau.
import os, sys
from PIL import Image

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
DIR = os.path.join(ROOT, "art", "campaign", "mystery")
SMITH_DIR = os.path.join(DIR, "smith")

BACKGROUNDS = ["Altar", "Ambush", "Gunsmith", "FallenKnight"]
FRAMES = 8
COLUMNS = 4
OUTLINE = (0x1E, 0x18, 0x20, 255)
# The forge lights the smith from the right in warm orange
FORGELIGHT = (1.0, 0.78, 0.6)
# The eye's box on the FallenKnight background (left, top, right, bottom); keep CampaignArt.EYE_RECT in step
EYE_BOX = (944, 460, 992, 500)
# Only these parts of the box belong to the eye, not the cyan rim of his head
EYE_LIMIT = {"MaxX": 978, "MinY": 472, "MaxY": 490, "PupilMaxX": 972, "PupilMinY": 470}
EYE_OUTLINE = (0xB8, 0xFF, 0xF4, 255)
EYE_FILL = (0x3F, 0xD8, 0xC8, 230)
EYE_PUPIL = (0xFF, 0xFF, 0xFF, 255)
# Soft rings of light spilling past the socket, strongest first
EYE_HALO = [(0x7F, 0xF3, 0xE8, 170), (0x4F, 0xD8, 0xD0, 90)]


def is_unlit(r, g, b):
    return r > 200 and g > 150 and b < 140


def light(image):
    px = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = px[x, y]
            if a == 0 or is_unlit(r, g, b): continue
            px[x, y] = (round(r * FORGELIGHT[0]), round(g * FORGELIGHT[1]), round(b * FORGELIGHT[2]), a)
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


for name in BACKGROUNDS:
    background = Image.open(os.path.join(DIR, name + ".png")).convert("RGB")
    background.resize((background.width // 2, background.height // 2), Image.LANCZOS).save(os.path.join(DIR, name + "Background.png"))

first = Image.open(os.path.join(SMITH_DIR, "Smith_0.png"))
fw, fh = first.size
sheet = Image.new("RGBA", (fw * COLUMNS, fh * ((FRAMES + COLUMNS - 1) // COLUMNS)), (0, 0, 0, 0))
for i in range(FRAMES):
    frame = outline(light(Image.open(os.path.join(SMITH_DIR, f"Smith_{i}.png")).convert("RGBA")))
    sheet.paste(frame, ((i % COLUMNS) * fw, (i // COLUMNS) * fh))
sheet.save(os.path.join(DIR, "GunsmithSheet.png"))

knight = Image.open(os.path.join(DIR, "FallenKnight.png")).convert("RGB")


# Dark socket pixels, his cyan pupil, or anything else
def eye_kind(x, y):
    r, g, b = knight.getpixel((x, y))
    if g > 180 and b > 180 and r < 120 and x <= EYE_LIMIT["PupilMaxX"] and y >= EYE_LIMIT["PupilMinY"]: return "Pupil"
    if (r + g + b) / 3 < 45 and x <= EYE_LIMIT["MaxX"] and EYE_LIMIT["MinY"] <= y <= EYE_LIMIT["MaxY"]: return "Socket"
    return None


left, top, right, bottom = EYE_BOX
wake = Image.new("RGBA", (right - left, bottom - top), (0, 0, 0, 0))
for y in range(top, bottom):
    for x in range(left, right):
        kind = eye_kind(x, y)
        if kind == "Pupil":
            wake.putpixel((x - left, y - top), EYE_PUPIL)
        elif kind == "Socket":
            # A two pixel rim around the socket lights up as his outline
            edge = any(eye_kind(x + dx, y + dy) is None for dx in range(-3, 4) for dy in range(-3, 4) if abs(dx) + abs(dy) <= 3)
            wake.putpixel((x - left, y - top), EYE_OUTLINE if edge else EYE_FILL)

# Each halo ring lights the empty pixels touching the eye so far, so the glow spills out a little
for color in EYE_HALO:
    lit = {(x, y) for y in range(wake.height) for x in range(wake.width) if wake.getpixel((x, y))[3]}
    for x, y in lit:
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < wake.width and 0 <= ny < wake.height and (nx, ny) not in lit and not wake.getpixel((nx, ny))[3]:
                wake.putpixel((nx, ny), color)
wake.save(os.path.join(DIR, "EyeWake.png"))

print("smith frame", fw, fh, "sheet", sheet.size)
