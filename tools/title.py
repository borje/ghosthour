"""Draws the title picture from scratch at 160x200 (multicolour) with C64 palette indices,
then fits it to the 3-colours-plus-background per 4x8-cell bitmap limit.
The sky is the shared background colour, so the game can flash lightning with one register."""
import math, random, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from PIL import Image, ImageDraw
from palette import C64
import font

BLK, WHT, RED, CYN, PUR, GRN, BLU, YEL, ORG, BRN, LRD, DGY, GRY, LGN, LBL, LGY = range(16)
BG = BLU

SMALL = {
    " ": "000 000 000 000 000", "-": "000 000 111 000 000", "(": "010 100 100 100 010", ")": "010 001 001 001 010",
    "0": "111 101 101 101 111", "2": "111 001 111 100 111", "6": "111 100 111 101 111",
    "A": "010 101 111 101 101", "B": "110 101 110 101 110", "C": "011 100 100 100 011", "D": "110 101 101 101 110",
    "E": "111 100 110 100 111", "K": "101 101 110 101 101", "L": "100 100 100 100 111", "M": "101 111 111 101 101",
    "N": "110 101 101 101 101", "O": "010 101 101 101 010", "R": "110 101 110 101 101", "U": "101 101 101 101 111",
    "Y": "101 101 010 010 010",
}

def letter_rows(ch):
    cols = bytes.fromhex(font.F5X7[ch])
    return [[(c >> y) & 1 for c in cols] for y in range(7)]

def draw_big_text(px, text, x0, y0, sx, sy, fill, shade, seed=3):
    """Chunky wobbly comic capitals: black outline, drop shadow, shaded lower half."""
    rnd = random.Random(seed)
    w, h = 160, 200
    mask = {}
    x = x0
    for ch in text:
        if ch == " ":
            x += sx * 3
            continue
        dy = rnd.choice((-2, -1, 0, 1, 2))
        rows = letter_rows(ch)
        for j, row in enumerate(rows):
            for i, v in enumerate(row):
                if not v: continue
                for yy in range(sy):
                    for xx in range(sx):
                        mask[(x + i * sx + xx, y0 + dy + j * sy + yy)] = (j * sy + yy) / (7 * sy)
        x += 5 * sx + 2
    # shadow + outline
    for (mx, my) in mask:
        for ox in range(-1, 3):
            for oy in range(-2, 4):
                if 0 <= mx + ox < w and 0 <= my + oy < h:
                    px[mx + ox, my + oy] = BLK
    for (mx, my), t in mask.items():
        px[mx, my] = shade if t > 0.62 else fill

def draw():
    im = Image.new("P", (160, 200), BG)
    pal = []
    for c in C64: pal += list(c)
    im.putpalette(pal + [0] * (768 - len(pal)))
    d = ImageDraw.Draw(im)
    rnd = random.Random(1984)

    # moon halo, moon
    mx, my = 118, 82
    for r, c in ((30, LBL),):
        d.ellipse((mx - r, my - r * 2 + 6, mx + r, my + r * 2 - 6), fill=c)
    d.ellipse((mx - 17, my - 33, mx + 17, my + 33), fill=WHT, outline=BLK)
    for (a, b, r) in ((-6, -10, 3), (7, 8, 4), (-3, 16, 2)):
        d.ellipse((mx + a - r, my + b - r * 2, mx + a + r, my + b + r * 2), fill=LGY)

    # wind-driven storm strokes
    for _ in range(26):
        x = rnd.randint(-10, 150); y = rnd.randint(46, 128)
        l = rnd.randint(8, 24)
        if not (84 < x + l // 2 < 150 and 40 < y < 122):
            d.line((x, y, x + l, y - l // 2), fill=BLK)

    # manor silhouette on the hill
    S = BLK
    d.polygon([(70, 118), (70, 104), (82, 92), (88, 104), (96, 104), (96, 92), (108, 92), (108, 104),
               (116, 104), (122, 80), (128, 104), (136, 104), (142, 88), (150, 104), (159, 110), (159, 150), (60, 150), (60, 118)], fill=S)
    d.line((122, 80, 122, 68), fill=S); d.line((142, 88, 142, 78), fill=S); d.line((82, 92, 82, 82), fill=S)
    # lit windows: someone is home
    for (x, y) in ((76, 112), (88, 112), (100, 112), (112, 112), (126, 110), (138, 112), (150, 114)):
        d.rectangle((x, y, x + 2, y + 6), fill=YEL)
        d.line((x, y + 3, x + 2, y + 3), fill=BLK)
    d.rectangle((122, 94, 123, 99), fill=YEL)

    # hill
    pts = [(0, 142)]
    for x in range(0, 170, 10):
        pts.append((x, 134 + int(5 * math.sin(x * 0.06))))
    pts += [(160, 200), (0, 200)]
    d.polygon(pts, fill=DGY)
    # grass
    d.polygon([(0, 150)] + [(x, 146 + int(4 * math.sin(x * 0.11 + 1))) for x in range(0, 170, 8)] + [(160, 200), (0, 200)], fill=GRN)
    for _ in range(170):
        x = rnd.randint(0, 159); y = rnd.randint(150, 199)
        d.point((x, y), fill=rnd.choice((BLK, LGN, BLK)))

    # row of hooded sheet ghosts drifting along the ridge
    for i, x in enumerate((72, 89, 106, 123, 140)):
        y = 130 + (i % 2) * 3
        d.polygon([(x + 5, y - 28), (x + 7, y - 22), (x + 9, y - 16), (x + 10, y - 6), (x + 12, y + 2), (x + 10, y),
                   (x + 8, y + 3), (x + 6, y), (x + 4, y + 3), (x + 2, y), (x, y + 2), (x + 2, y - 6),
                   (x + 2, y - 16), (x + 3, y - 22)], fill=WHT, outline=BLK)
        d.rectangle((x + 4, y - 17, x + 4, y - 13), fill=BLK); d.rectangle((x + 7, y - 17, x + 7, y - 13), fill=BLK)
        d.line((x + 1, y - 3, x + 3, y - 12), fill=LGY); d.line((x + 10, y - 3, x + 9, y - 10), fill=LGY)
        d.line((x - 7, y - 10, x - 1, y - 12), fill=LGY); d.line((x - 8, y - 4, x, y - 6), fill=LGY)

    # the winding path
    d.polygon([(60, 199), (112, 199), (96, 170), (82, 156), (76, 150), (70, 156), (72, 172)], fill=GRY, outline=BLK)
    for _ in range(24):
        d.point((rnd.randint(66, 104), rnd.randint(160, 198)), fill=DGY)

    # tombstones
    def grave(x, y, w, h, cross=False):
        if cross:
            d.rectangle((x - 1, y - h, x + 1, y), fill=LGY, outline=BLK)
            d.rectangle((x - 4, y - h + 6, x + 4, y - h + 11), fill=LGY, outline=BLK)
        else:
            d.chord((x - w, y - h, x + w, y - h + 16), 180, 360, fill=LGY, outline=BLK)
            d.rectangle((x - w, y - h + 8, x + w, y), fill=LGY, outline=BLK)
            d.line((x - w + 2, y - h + 14, x + w - 2, y - h + 14), fill=DGY)
            d.line((x - w + 2, y - h + 19, x + w - 2, y - h + 19), fill=DGY)
    grave(121, 172, 8, 30); grave(148, 180, 9, 34); grave(104, 188, 6, 20); grave(136, 160, 5, 20, True)

    # brick pillar + iron gate on the left
    d.rectangle((0, 62, 22, 199), fill=LRD, outline=BLK)
    d.rectangle((0, 56, 26, 62), fill=LGY, outline=BLK)
    for y in range(66, 200, 6):
        d.line((0, y, 22, y), fill=BLK)
        off = 3 if (y // 6) % 2 else 9
        for x in range(off, 22, 12):
            d.line((x, y - 5, x, y - 1), fill=BLK)
    for i, x in enumerate((30, 40, 50, 60)):
        top = 74 + i * 7
        d.line((x, top, x, 165), fill=BLK); d.line((x + 1, top, x + 1, 165), fill=BLK)
        d.polygon([(x, top - 8), (x + 3, top - 2), (x, top + 3), (x - 2, top - 2)], fill=BLK)
    for y0, y1 in ((96, 110), (135, 148)):
        d.line((22, y0, 68, y1), fill=BLK); d.line((22, y0 + 1, 68, y1 + 1), fill=BLK)
    for i, x in enumerate((30, 40, 50, 60)):
        d.ellipse((x - 3, 112 + i * 3, x + 5, 126 + i * 3), outline=BLK)

    # our hero from behind: yellow slicker, candle held high
    hx, hy = 84, 160
    d.polygon([(hx - 7, hy + 22), (hx - 6, hy), (hx + 7, hy), (hx + 8, hy + 22)], fill=YEL, outline=BLK)
    d.ellipse((hx - 4, hy - 15, hx + 4, hy + 1), fill=BLK)
    d.line((hx + 6, hy + 4, hx + 12, hy - 6), fill=BLK); d.line((hx + 7, hy + 4, hx + 13, hy - 6), fill=YEL)
    d.rectangle((hx + 12, hy - 18, hx + 13, hy - 7), fill=WHT, outline=BLK)
    d.ellipse((hx + 10, hy - 28, hx + 15, hy - 19), fill=YEL, outline=ORG)
    d.point((hx + 12, hy - 24), fill=WHT)
    d.rectangle((hx - 6, hy + 22, hx - 1, hy + 24), fill=BLK); d.rectangle((hx + 2, hy + 22, hx + 7, hy + 24), fill=BLK)

    # lettering
    px = im.load()
    d.rectangle((0, 182, 159, 199), fill=BLK)
    x = 44
    for ch in "PRESS FIRE":
        if ch != " ":
            for j, row in enumerate(letter_rows(ch)):
                for i, v in enumerate(row):
                    if v: px[x + i, 183 + j] = WHT
        x += 7
    # credit line, in a 3x5 font: 33 characters only fit at 4 px each
    text = "CLAUDE - BRUNO KEYMOLEN - (C)2026"
    x = (160 - (len(text) * 4 - 1)) // 2
    for ch in text:
        for j, row in enumerate(SMALL[ch].split()):
            for i, v in enumerate(row):
                if v == "1": px[x + i, 193 + j] = LGY
        x += 4
    draw_big_text(px, "GHOST", 26, 6, 4, 5, YEL, ORG, seed=4)
    draw_big_text(px, "HOUR", 28, 48, 3, 3, WHT, LGY, seed=8)
    return im

def nearest(c, choices):
    r, g, b = C64[c]
    return min(choices, key=lambda k: (C64[k][0] - r) ** 2 + (C64[k][1] - g) ** 2 + (C64[k][2] - b) ** 2)

def convert(im, press_row=True):
    """Returns (bitmap 8000, screen 1000, colour 1000, preview image)."""
    px = im.load()
    bitmap, screen, colour = bytearray(8000), bytearray(1000), bytearray(1000)
    out = im.copy(); opx = out.load()
    clashes = 0
    for cy in range(25):
        for cx in range(40):
            counts = {}
            for y in range(8):
                for x in range(4):
                    c = px[cx * 4 + x, cy * 8 + y]
                    if c != BG: counts[c] = counts.get(c, 0) + 1
            keep = sorted(counts, key=lambda k: -counts[k])[:3]
            clashes += max(0, len(counts) - 3)
            keep += [0] * (3 - len(keep))
            c1, c2, c3 = keep
            screen[cy * 40 + cx] = (c1 << 4) | c2
            colour[cy * 40 + cx] = c3
            allowed = {BG: 0, c1: 1, c2: 2, c3: 3}
            for y in range(8):
                v = 0
                for x in range(4):
                    c = px[cx * 4 + x, cy * 8 + y]
                    if c not in allowed:
                        c = nearest(c, list(allowed))
                    v = v * 4 + allowed[c]
                    opx[cx * 4 + x, cy * 8 + y] = c
                bitmap[(cy * 40 + cx) * 8 + y] = v
    return bytes(bitmap), bytes(screen), bytes(colour), out, clashes

def preview(path):
    im = draw()
    *_, out, clashes = convert(im)
    out.convert("RGB").resize((640, 400), Image.NEAREST).save(path)
    print("cell colour clashes:", clashes)

if __name__ == "__main__":
    preview(sys.argv[1])
