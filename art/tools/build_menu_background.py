# Splits the main menu background and packs the build_menu_fire.py renders in art/menu/fire into one sheet.
# Run from the repo root: python art/tools/build_menu_background.py
# Roblox shrinks images past 1024 pixels, so the art is cut into two halves (and scaled to 1024 tall if it's taller).
# Upload MenuBackground_L.png, MenuBackground_R.png and art/menu/MenuFire.png and put the ids in MenuArt.luau.
import os, sys
from PIL import Image

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
ART = os.path.join(ROOT, "art")
FRAMES_DIR = os.path.join(ART, "menu", "fire")

FRAMES = 12
COLUMNS = 4
HEIGHT = 1024
# Each half overlaps the seam by this many pixels so no gap shows when they're stretched
OVERLAP = 2

background = Image.open(os.path.join(ART, "MenuBackground.png")).convert("RGB")
if background.height > HEIGHT:
    background = background.resize((round(background.width * HEIGHT / background.height), HEIGHT), Image.LANCZOS)
width, height = background.size
half = width // 2
background.crop((0, 0, half + OVERLAP, height)).save(os.path.join(ART, "MenuBackground_L.png"))
background.crop((half - OVERLAP, 0, width, height)).save(os.path.join(ART, "MenuBackground_R.png"))

first = Image.open(os.path.join(FRAMES_DIR, "Fire_0.png"))
fw, fh = first.size
sheet = Image.new("RGBA", (fw * COLUMNS, fh * ((FRAMES + COLUMNS - 1) // COLUMNS)), (0, 0, 0, 0))

for i in range(FRAMES):
    frame = Image.open(os.path.join(FRAMES_DIR, f"Fire_{i}.png")).convert("RGBA")
    # Hard pixel edges, like the rest of the art
    frame.putalpha(frame.getchannel("A").point(lambda a: 255 if a >= 128 else 0))
    sheet.paste(frame, ((i % COLUMNS) * fw, (i // COLUMNS) * fh))

sheet.save(os.path.join(ART, "menu", "MenuFire.png"))
print("background", width, height, "half", half, "frame", fw, fh, "sheet", sheet.size)
