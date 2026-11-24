# Epic King skin previews, one per class: the White King's first idle frame from the atlas, restyled
# Run from the project root: python art/tools/build_epic_kings.py (writes into art/skins/pieces)
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, 'art', 'skins', 'pieces')

C, S, O, G, B = (240,233,216,255), (179,168,143,255), (23,29,50,255), (230,196,124,255), (168,132,74,255)
CLEAR = (0, 0, 0, 0)

def hexc(h):
    h = h.lstrip('#'); return (int(h[0:2],16), int(h[2:4],16), int(h[4:6],16), 255)

base = Image.open(os.path.join(ROOT, 'art', 'SpriteAtlas.png')).convert('RGBA').crop((2, 722, 34, 754))

# Start from the King without its outline, recolored; finish() redraws the outline around whatever was painted
def start(mapping):
    im = base.copy(); px = im.load()
    for y in range(32):
        for x in range(32):
            p = px[x, y]
            if p == O: px[x, y] = CLEAR
            elif p[3] and p in mapping: px[x, y] = mapping[p]
    return im

def put(im, pts, col):
    px = im.load()
    for x, y in pts: px[x, y] = col

def finish(im, outline):
    px = im.load()
    body = {(x, y) for y in range(32) for x in range(32) if px[x, y][3]}
    for y in range(32):
        for x in range(32):
            if (x, y) in body: continue
            if any((x + dx, y + dy) in body for dx, dy in ((1,0),(-1,0),(0,1),(0,-1))):
                px[x, y] = outline
    return im

# Rings an item with the outline color, over the King and his clothes too, so it reads as its own object
def outline_item(im, pts, col=O):
    pts = set(pts)
    for x, y in pts:
        for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
            n = (x + dx, y + dy)
            if n not in pts and 0 <= n[0] < 32 and 0 <= n[1] < 32:
                put(im, [n], col)

def line(x0, y0, x1, y1):
    pts = []
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx + dy
    while True:
        pts.append((x0, y0))
        if (x0, y0) == (x1, y1): return pts
        e2 = 2 * err
        if e2 >= dy: err += dy; x0 += sx
        if e2 <= dx: err += dx; y0 += sy

def clear_crown(im):
    px = im.load()
    for y in range(3, 7):
        for x in range(13, 19):
            if px[x, y] in (G, B): px[x, y] = CLEAR

def row_span(im, y):
    xs = [x for x in range(32) if im.getpixel((x, y))[3]]
    return (min(xs), max(xs)) if xs else None

# Span of the King himself on a row, ignoring the scythe behind him
def row_span_body(im, y):
    xs = [x for x in range(32) if base.getpixel((x, y))[3] and base.getpixel((x, y)) != O]
    return (min(xs), max(xs)) if xs else None

# A cloak hanging behind the King from his shoulders, flaring toward a ragged hem; only shows past his edges
def back_cloak(im, light, dark, top=13, bottom=30, ragged=True):
    px = im.load()
    for y in range(top, bottom + 1):
        t = (y - top) / (30 - top)
        half = 6 + t * 4.5
        for x in range(int(15.5 - half), int(16.5 + half)):
            if not (0 <= x < 32) or px[x, y][3]: continue
            if ragged and y == bottom and x % 3 == 0: continue
            px[x, y] = light if x < 16 else dark

def monarch():
    # The King in a royal-red cloak fastened round his neck, hanging behind him down to the top of the base,
    # with a white ermine collar and a gold chain clasp across the front
    red_l, red_d = hexc('B8323A'), hexc('7A1E28')
    fur_l, fur_s, fleck = hexc('F7F4EC'), hexc('CFC8BA'), hexc('1E1B22')
    gold_l, gold_d = hexc('F0CC72'), hexc('A8844A')
    im = start({})
    px = im.load()
    # The cloak wraps round him: the front drapes over his shoulders and sides and ends high with a gold hem,
    # while the back hangs lower behind him, darker because it's the far side in shadow
    hi, lit, mid, dark, deep = hexc('D6484C'), hexc('B8323A'), hexc('962834'), hexc('6E1C26'), hexc('4A1219')
    # Back of the cloak, behind him and lower than the front
    back_cloak(im, dark, deep, top=13, bottom=25, ragged=False)
    for y in range(16, 26):
        for x in range(32):
            if px[x, y] == dark and x % 3 == 1: px[x, y] = mid if y < 20 else dark
            if px[x, y] == deep and x % 3 == 0: px[x, y] = dark
    # Front of the cloak, over the outer edge of his body on each side, ending above the base
    front_bottom = 20
    for y in range(13, front_bottom + 1):
        span = row_span_body(im, y)
        if not span: continue
        left, right = span
        width = 3 if y < 15 else 2
        for i in range(width):
            put(im, [(left + i, y)], hi if i == 0 else lit)
            put(im, [(right - i, y)], dark if i == 0 else mid)
    for x in range(32):
        if px[x, front_bottom] in (hi, lit, mid, dark) and base.getpixel((x, front_bottom))[3]:
            px[x, front_bottom] = gold_l if x < 16 else gold_d
    # Ermine collar wrapped round the neck
    for y in (12, 13):
        for x in range(11, 21):
            px[x, y] = fur_l if y == 12 or x < 16 else fur_s
    put(im, [(10,13),(21,13)], fur_s)
    # Ermine flecks kept to the sides, so the middle of the collar doesn't read as a face
    put(im, [(11,13),(12,12),(19,12),(20,13)], fleck)
    # Gold chain draped across his chest from one side of the collar to the other, clasp in the middle
    chain = [(11,14),(12,15),(13,15),(14,16),(17,16),(18,15),(19,15),(20,14)]
    for i, (x, y) in enumerate(chain):
        put(im, [(x, y)], gold_l if i % 2 == 0 else gold_d)
    put(im, [(15,16),(16,16),(15,17),(16,17)], gold_l); put(im, [(16,17)], gold_d)
    outline_item(im, [(15,16),(16,16),(15,17),(16,17)])
    return finish(im, O)

def hunter():
    # An original trophy hunter: a heavy, shaggy fur coat hanging open behind him and a necklace of bone teeth
    fur_l, fur_m, fur_d = hexc('A88A64'), hexc('76593F'), hexc('4A372A')
    coat_l, coat_d, trim = hexc('5A4130'), hexc('3A2A1F'), hexc('C9A24E')
    bone_l, bone_d, socket, belt = hexc('E6DABE'), hexc('A8977A'), hexc('2A2018'), hexc('2E2118')
    im = start({})
    px = im.load()
    # Fur collar bunched up behind the neck and shoulders, puffing out past both sides
    fur = {}
    for cx, cy, r in ((10.5, 13.5, 2.6), (21.5, 13.5, 2.6), (9.5, 16.5, 2.2), (22.5, 16.5, 2.2), (12, 11.5, 1.8), (20, 11.5, 1.8)):
        for y in range(int(cy - r) - 1, int(cy + r) + 2):
            for x in range(int(cx - r) - 1, int(cx + r) + 2):
                dx, dy = x + 0.5 - cx, y + 0.5 - cy
                if dx * dx + dy * dy <= r * r:
                    shade = dx + dy if x < 16 else dy - dx + 1.5
                    fur[(x, y)] = fur_l if shade < -1 else fur_m if shade < 1.2 else fur_d
    for (x, y), col in fur.items():
        if not px[x, y][3]: px[x, y] = col
    # The collar wraps over the tops of the shoulders
    put(im, [(12,13),(13,13),(18,13),(19,13),(12,14),(19,14)], fur_m); put(im, [(12,13),(13,13)], fur_l)
    # Heavy fur coat hanging behind him down to the top of the base, open so his whole front shows
    back_cloak(im, fur_m, fur_d, bottom=23)
    for y in range(14, 25):
        for x in range(32):
            if px[x, y] not in (fur_m, fur_d) or base.getpixel((x, y))[3] and base.getpixel((x, y)) != O: continue
            n = (x * 5 + y * 3) % 7
            if n == 0: px[x, y] = fur_l
            elif n == 4: px[x, y] = fur_d
    # Shaggy tufts sticking out along the sides and hem
    for x, y in [(6,19),(5,21),(25,19),(26,21),(7,24),(10,24),(13,24),(19,24),(22,24),(25,24)]:
        if not px[x, y][3]: px[x, y] = fur_d
    for x, y in [(6,17),(25,17),(4,22),(27,22)]:
        if not px[x, y][3]: px[x, y] = fur_m
    # Necklace of bone teeth on a cord across his chest
    tooth, tooth_d = hexc('B9A57C'), hexc('6E5A3C')
    cord = [(12,14),(13,15),(14,16),(15,16),(16,16),(17,16),(18,15),(19,14)]
    put(im, cord, belt)
    # Fangs hanging off the cord, a shaded edge on each so they show against his cream chest
    for x, y, length in ((13,16,2), (15,17,3), (17,17,2), (19,15,2)):
        for i in range(length):
            put(im, [(x, y + i)], tooth if i < length - 1 else tooth_d)
        put(im, [(x + 1, y)], tooth_d)
    return finish(im, O)

def bandit():
    # A bandit: gray cloth mask over the lower face, layered tattered scarves round the
    # neck and shoulders with ragged ends, a leather vest with crossed straps, and a belt with pouches, a dagger and cloth flaps
    mask_l, mask_d = hexc('6E6A68'), hexc('4A4644')
    rag_l, rag_m, rag_d = hexc('8A7A66'), hexc('5E5246'), hexc('3C342E')
    leather, buckle, eye = hexc('4A3222'), hexc('9AA0AC'), hexc('2A2422')
    im = start({})
    px = im.load()
    # Cloth mask over the nose and mouth
    for y in (10, 11, 12):
        for x in range(11, 21):
            if px[x, y][3]: px[x, y] = mask_l if x < 17 else mask_d
    put(im, [(13,11),(15,12)], mask_d)
    # Layered scarves wound round the neck and draped over the shoulders, in uneven bands
    for y in range(13, 18):
        half = 4 if y in (13, 17) else 5
        for x in range(15 - half, 17 + half):
            band = (y + (x // 3)) % 3
            px[x, y] = rag_l if band == 0 and x < 18 else rag_d if band == 2 or x > 18 else rag_m
    # Ragged ends hanging off the scarves
    put(im, [(11,18),(12,19),(11,19),(19,18),(20,18),(20,19),(20,20),(15,18),(16,19)], rag_d)
    put(im, [(10,17),(21,17),(12,18),(14,18)], rag_m)
    # Dark leather vest over the torso, crossed straps over the chest
    vest_l, vest_d, steel, hilt = hexc('5E4230'), hexc('3E2A1E'), hexc('B9BFC9'), hexc('6B4A2E')
    for y in range(18, 23):
        put(im, [(13, y), (14, y)], vest_l)
        put(im, [(17, y), (18, y)], vest_d)
    for x, y in [(13,18),(14,19),(15,20),(16,21),(17,22),(18,18),(17,19),(16,20),(15,21),(14,22)]:
        put(im, [(x, y)], leather)
    put(im, [(15,20),(16,20)], buckle)
    # Belt with pouches, and a dagger tucked at the hip
    for x in range(12, 20): put(im, [(x, 23)], leather)
    put(im, [(15,23)], buckle)
    put(im, [(10,24),(11,24),(10,25),(11,25)], vest_d); put(im, [(20,24),(21,24),(20,25)], vest_l)
    # Pocket knife on his right side, angled so it pushes back behind him: a shaded brass end cap facing us,
    # the side of the wooden handle running away from us, a crossguard, then the blade narrowing and darkening
    # as it recedes behind his base, with only the part past his edge showing
    cap_l, cap_m, cap_d = hexc('F0CC72'), hexc('C99A44'), hexc('7E5A24')
    wood_l, wood_d, guard = hexc('9A6A42'), hexc('5A3A22'), hexc('8A90A0')
    near_l, near_d, far = hexc('F2F4F8'), hexc('A9B0BE'), hexc('6E7586')
    cap = [(17,19),(18,19),(17,20),(18,20)]
    handle = [(19,20),(19,21),(20,21),(20,22)]
    crossguard = [(21,21),(21,22),(21,23)]
    outline_item(im, cap + handle + crossguard)
    put(im, [(17,19)], cap_l); put(im, [(18,19),(17,20)], cap_m); put(im, [(18,20)], cap_d)
    put(im, [(19,20),(20,21)], wood_l); put(im, [(19,21),(20,22)], wood_d)
    put(im, crossguard, guard)
    # Blade: two pixels wide and bright close to the guard, one dark pixel wide toward the far tip
    for x, y, col in [(22,23,near_l),(23,23,near_d),(22,24,near_d),(23,24,near_l),(24,25,near_l),(23,25,near_d),
                      (24,26,far),(25,27,far)]:
        if not px[x, y][3]: px[x, y] = col
    # Ragged cloth flaps hanging from the belt
    for x, length in ((13, 2), (14, 3), (16, 2), (17, 3)):
        for i in range(length):
            put(im, [(x, 24 + i)], rag_m if x < 16 else rag_d)
    return finish(im, O)

def gunslinger():
    # A cowboy: wide-brim hat with a gold crown pin, red fringed poncho, revolvers holstered on both hips
    hat_l, hat_d, band, pin = hexc('C49A62'), hexc('86643C'), hexc('5E3222'), hexc('E6C462')
    red_l, red_d = hexc('C2472F'), hexc('7E2A20')
    belt, buckle, steel, grip = hexc('3A2416'), hexc('E6C462'), hexc('B9BFC9'), hexc('7A4A2A')
    im = start({})
    clear_crown(im)
    # Hat: crown with a dent, band with the crown pin, and a wide brim
    for x in range(13, 19):
        for y in (4, 5, 6): put(im, [(x, y)], hat_l if x < 17 else hat_d)
    put(im, [(15,4),(16,4)], CLEAR); put(im, [(15,5)], hat_d)
    for x in range(13, 19): put(im, [(x, 6)], band)
    put(im, [(15,6)], pin)
    for x in range(9, 23): put(im, [(x, 7)], hat_l if x < 18 else hat_d)
    # Brim's shadow on the head
    for x in range(12, 20): put(im, [(x, 8)], S)
    # Red poncho over the shoulders, fringed at the bottom
    for y in range(13, 18):
        for x in range(12, 20):
            put(im, [(x, y)], red_l if x < 17 else red_d)
    put(im, [(11,15),(20,15),(11,16),(20,16),(11,17),(20,17)], red_d)
    for x in range(11, 21, 2): put(im, [(x, 18)], red_d)
    # Gun belt and buckle
    for x in range(12, 20): put(im, [(x, 23)], belt)
    put(im, [(15,23),(16,23)], buckle)
    # Bandolier slung from the right shoulder to the left hip, brass rounds in loops
    for i, (x, y) in enumerate(line(19, 13, 12, 22)):
        put(im, [(x, y)], belt)
        if i % 2 == 0: put(im, [(x + 1, y)], hexc('E3BA5A'))
    # Leather holster high on the right hip, just under the poncho, a revolver in it with its grip angled back,
    # ringed in dark so it reads against the poncho and his body
    holster_l, holster_d, gun_l, gun_d = hexc('7A4A2A'), hexc('4E2E1A'), hexc('C9CED8'), hexc('6A6F80')
    holster = [(19,20),(20,20),(21,20),(19,21),(20,21),(21,21),(20,22),(21,22),(21,23)]
    gun = [(19,19),(20,19),(21,19),(21,18),(22,18),(22,17),(23,17)]
    outline_item(im, holster + gun)
    for x, y in holster: put(im, [(x, y)], holster_l if x < 21 else holster_d)
    put(im, [(20,21)], hexc('C9A24E'))
    put(im, [(19,19),(20,19)], gun_l); put(im, [(21,19)], gun_d)
    put(im, [(21,18),(22,18),(22,17)], grip); put(im, [(23,17)], hexc('4A2C18'))
    return finish(im, O)

def reaper():
    # The King wrapped in a dark cloak from the neck down, ending in ragged swept tips, scythe slung across his back
    cloak_l, cloak_m, cloak_d = hexc('4A4560'), hexc('34304A'), hexc('211E30')
    wood, steel_l, steel_d = hexc('5A4632'), hexc('D3D8E0'), hexc('8A93A6')
    im = start({})
    px = im.load()
    # Cloak body: rounded over the shoulders, wrapping the stem and widening as it falls
    cloak = {}
    top, hem = 14, 22
    for y in range(top, hem + 1):
        t = (y - top) / (hem - top)
        half = 4.2 + t * 3.3 - (0.8 if y == top else 0)
        for x in range(int(15.5 - half), int(16.5 + half)):
            cloak[(x, y)] = cloak_l if x < 14 else cloak_d if x > 18 else cloak_m
    # Fold lines down the front
    for y in range(top + 3, hem + 1):
        cloak[(15, y)] = cloak_d
        cloak[(12, y)] = cloak_m
    # Tendrils trailing from the hem, wavy and swept to the right, with gaps that show the base
    for sx, length in ((9, 3), (11, 4), (14, 5), (17, 5), (20, 4), (22, 4)):
        x = sx
        for i in range(1, length + 1):
            y = hem + i
            if i % 2 == 0: x += 1
            cloak[(x, y)] = cloak_d if sx > 15 else cloak_m
            if i < length - 1: cloak[(x + 1, y)] = cloak_m if sx > 15 else cloak_l
    for (x, y), col in cloak.items():
        if 0 <= x < 32 and 0 <= y < 32: px[x, y] = col
    # Scythe across his back: only shows past the cloak and the King
    for x, y in line(3, 29, 25, 4):
        if not px[x, y][3] or base.getpixel((x, y)) == O and (x, y) not in cloak: px[x, y] = wood
    put(im, [(25,3),(26,2),(27,2),(28,3),(29,4),(30,5),(30,6)], steel_l)
    put(im, [(26,3),(27,3),(28,4),(29,5)], steel_d)
    return finish(im, O)

kings = [('Classic', base.copy()), ('Monarch', monarch()), ('Hunter', hunter()), ('Bandit', bandit()), ('Gunslinger', gunslinger()), ('Reaper', reaper())]
os.makedirs(OUT, exist_ok=True)
for name, im in kings[1:]:
    im.save(os.path.join(OUT, name + '_King.png'))

# Preview sheet: each King big on a light and a dark board tile
SCALE = 7
LIGHT, DARK = (0xD4,0x9A,0x77,255), (0x9C,0x57,0x4B,255)
cell = 32 * SCALE
font = None
for path in ('arialbd.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'):
    try: font = ImageFont.truetype(path, 26); break
    except Exception: pass
font = font or ImageFont.load_default()
W = len(kings) * (cell + 20) + 20
sheet = Image.new('RGBA', (W, cell * 2 + 90), (0x33,0x2A,0x35,255))
d = ImageDraw.Draw(sheet)
for i, (name, im) in enumerate(kings):
    x0 = 20 + i * (cell + 20)
    for j, tile in enumerate((LIGHT, DARK)):
        y0 = 60 + j * cell
        sheet.paste(Image.new('RGBA', (cell, cell), tile), (x0, y0))
        sheet.alpha_composite(im.resize((cell, cell), Image.NEAREST), (x0, y0))
    tw = d.textlength(name, font=font)
    d.text((x0 + (cell - tw) / 2, 16), name, font=font, fill=(0xE9,0xE3,0xD6,255))
sheet.save(os.path.join(OUT, 'epic_kings_preview.png'))
