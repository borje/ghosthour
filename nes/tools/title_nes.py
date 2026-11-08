"""The C64 title picture (../../tools/title.py) converted for the NES.

The NES has no bitmap mode: the picture becomes 32x30 tiles, each 16x16 block uses one of 4
palettes of 3 colours plus the shared backdrop (the sky, so lightning still flashes one colour),
and the picture needs more tiles than one pattern table holds. So the screen is split: the rows
above SPLIT use the tiles at $0000 and the rows below use the tiles at $1000. Sprite 0, hidden
behind the picture, tells the program when the split line is reached.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(1, os.path.join(HERE, "..", "..", "tools"))
from PIL import Image  # noqa: E402
import title  # noqa: E402  (C64 source)
from palette import C64  # noqa: E402
from colours import NES_RGB, nes_colour  # noqa: E402

W, H = 256, 240
TOP = 8                 # the picture starts below the 8 lines a TV hides
BG = title.BG
BLK, WHT, LGY = title.BLK, title.WHT, title.LGY

# C64 -> NES for the picture: the plain nearest colours (the game's skin override does not apply)
NES = {c: nes_colour(c) for c in range(16)}
NES[title.BLU] = 0x02
NES[title.YEL] = 0x28
NES[title.DGY] = 0x00   # the nearest match is brown
NES[title.GRY] = 0x00


def compose():
    """The C64 picture at NES size, with the NES lettering underneath. Returns C64 colour indices."""
    c64 = title.draw()
    pic = c64.crop((0, 0, 160, 182)).resize((W, 182), Image.NEAREST)   # 320 hires px -> 256
    im = Image.new("P", (W, H), BG)
    im.putpalette(c64.getpalette())
    im.paste(pic, (0, TOP))
    px = im.load()
    for y in range(TOP + 182, H):
        for x in range(W):
            px[x, y] = BLK
    def text(s, y, colour, small=False):
        width = len(s) * (4 if small else 7) - 1
        x = (W - width) // 2
        for ch in s:
            if ch != " ":
                rows = title.SMALL[ch].split() if small else title.letter_rows(ch)
                for j, row in enumerate(rows):
                    for i, v in enumerate(row):
                        if v in (1, "1"):
                            px[x + i, y + j] = colour
            x += 4 if small else 7
    text("PRESS START", TOP + 186, WHT)
    text("CLAUDE - BRUNO KEYMOLEN - (C)2026", TOP + 198, LGY, small=True)
    return im


def dist(a, b):
    return sum((x - y) ** 2 for x, y in zip(C64[a], C64[b]))


# The 4 palettes, chosen by hand like a C64 artist would (all with black for the outlines):
PALETTES = [
    [title.BLK, title.YEL, title.ORG],   # the lettering, the lit windows, the hero and his flame
    [title.BLK, title.WHT, title.LBL],   # the moon and its halo, HOUR, the ghosts
    [title.BLK, title.GRN, title.DGY],   # grass and the hill
    [title.BLK, title.LRD, title.LGY],   # the brick pillar, the tombstones
]


def fit_palettes(px):
    """Give every 16x16 block the palette with the least colour error. Pixels whose colour is not
    in their block's palette take the nearest one."""
    blocks = {}
    for by in range(H // 16):
        for bx in range(W // 16):
            counts = {}
            for y in range(16):
                for x in range(16):
                    c = px[bx * 16 + x, by * 16 + y]
                    if c != BG:
                        counts[c] = counts.get(c, 0) + 1
            blocks[(bx, by)] = counts

    def err(pal, cn):
        allowed = [BG] + list(pal)
        return sum(v * min(dist(c, k) for k in allowed) for c, v in cn.items())
    chosen = PALETTES
    assign = {k: min(range(4), key=lambda i: err(chosen[i], cn)) for k, cn in blocks.items()}
    return chosen, assign


def tile_2bpp(rows):
    lo, hi = bytearray(8), bytearray(8)
    for y, r in enumerate(rows):
        for x, v in enumerate(r):
            if v & 1:
                lo[y] |= 0x80 >> x
            if v & 2:
                hi[y] |= 0x80 >> x
    return bytes(lo + hi)


def squeeze(rows, limit):
    """Too many different tiles: replace the rarest tile by its most similar one until they fit.
    In this picture that only touches the speckled grass. Returns the number of tiles replaced."""
    def pixels(t):
        return [((t[y] >> (7 - x)) & 1) | (((t[8 + y] >> (7 - x)) & 1) << 1) for y in range(8) for x in range(8)]
    merged = 0
    while True:
        count = {}
        for r in rows:
            for t in r:
                count[t] = count.get(t, 0) + 1
        if len(count) <= limit:
            return merged
        rare = min(count, key=lambda t: count[t])
        pr = pixels(rare)
        near = min((t for t in count if t != rare), key=lambda t: sum(a != b for a, b in zip(pr, pixels(t))))
        for r in rows:
            for i, t in enumerate(r):
                if t == rare:
                    r[i] = near
        merged += 1


def build():
    im = compose()
    px = im.load()
    pals, assign = fit_palettes(px)
    # pixel values 0-3 per block
    val = [[0] * W for _ in range(H)]
    for (bx, by), i in assign.items():
        allowed = [BG] + pals[i]
        for y in range(16):
            for x in range(16):
                c = px[bx * 16 + x, by * 16 + y]
                if c not in allowed:
                    c = min(allowed, key=lambda k: dist(c, k))
                val[by * 16 + y][bx * 16 + x] = allowed.index(c)
    rows = []
    for ty in range(30):
        row = []
        for tx in range(32):
            row.append(tile_2bpp([val[ty * 8 + y][tx * 8:tx * 8 + 8] for y in range(8)]))
        rows.append(row)

    # the split: as many rows as fit in the first table go on top
    def unique(rs):
        return len({t for r in rs for t in r})
    split = 0
    while split < 30 and unique(rows[:split + 1]) <= 256:
        split += 1
    tables, nam = [], bytearray()
    merged = 0
    for part in (rows[:split], rows[split:]):
        part = [list(r) for r in part]
        merged += squeeze(part, 256)
        tl = []
        for r in part:
            for t in r:
                if t not in tl:
                    tl.append(t)
                nam.append(tl.index(t))
        tables.append(tl)
    attr = bytearray(64)
    for by in range(8):
        for bx in range(8):
            v = 0
            for i, (dy, dx) in enumerate(((0, 0), (0, 1), (1, 0), (1, 1))):
                y, x = by * 2 + dy, bx * 2 + dx
                if y < 15:
                    v |= assign[(x, y)] << (i * 2)
            attr[by * 8 + bx] = v
    palette = []
    for p in pals:
        palette += [NES[BG]] + [NES[c] for c in p]
    # sprite 0: behind the picture, on the last line above the split, at a solid pixel near the right
    y = split * 8 - 1
    x = next(x for x in range(W - 9, 0, -1) if val[y][x] != 0)
    return dict(tables=tables, nam=bytes(nam), attr=bytes(attr), palette=palette, split=split, merged=merged,
                sprite0=(x, y), preview=preview(val, assign, pals), sky=NES[BG])


def preview(val, assign, pals):
    out = Image.new("RGB", (W, H))
    o = out.load()
    for y in range(H):
        for x in range(W):
            i = assign[(x // 16, y // 16)]
            c = [title.BG] + pals[i]
            o[x, y] = NES_RGB[NES[c[val[y][x]]]]
    return out


if __name__ == "__main__":
    t = build()
    print("split at row", t["split"], "tiles:", [len(x) for x in t["tables"]], "merged:", t["merged"], "sprite 0 at", t["sprite0"])
    print("palettes:", t["palette"])
    t["preview"].resize((W * 2, H * 2), Image.NEAREST).save(sys.argv[1] if len(sys.argv) > 1 else "title_nes.png")
