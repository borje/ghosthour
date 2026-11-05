"""Render the tile set, each room and the sprites to PNG for art review (no emulator needed)."""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from PIL import Image
from palette import C64
import tiles, rooms, sprites

def tile_img(sym, d022, d023, dark=False, dim=6):
    f, col, rows = tiles.TILES[sym]
    im = Image.new("RGB", (16, 16))
    for y, r in enumerate(rows):
        for x, p in enumerate(r):
            if dark:
                p = tiles.DARK_MAP[p]
            c = {".": 0, "a": d022, "b": d023, "c": dim if dark else col}[p]
            im.putpixel((x * 2, y), C64[c]); im.putpixel((x * 2 + 1, y), C64[c])
    return im

def room_img(name, dark=False):
    r = rooms.ROOMS[name]
    d022, d023, dim = r["pal"]
    im = Image.new("RGB", (320, 176))
    for y, row in enumerate(r["map"]):
        assert len(row) == 20, (name, y, len(row), row)
        for x, s in enumerate(row):
            im.paste(tile_img(s, d022, d023, dark, dim), (x * 16, y * 16))
    return im

def main(out):
    names = list(rooms.ROOMS)
    cols = 3
    sheet = Image.new("RGB", (cols * 330, ((len(names) + 2) // cols) * 186), (40, 40, 40))
    for i, n in enumerate(names):
        sheet.paste(room_img(n), ((i % cols) * 330 + 5, (i // cols) * 186 + 5))
    sheet.save(os.path.join(out, "rooms.png"))
    sheet = Image.new("RGB", (640, 176), (40, 40, 40))
    sheet.paste(room_img("GREAT HALL"), (0, 0)); sheet.paste(room_img("GREAT HALL", True), (320, 0))
    sheet.save(os.path.join(out, "dark.png"))
    _, _, prev = sprites.build()
    W = 8
    sh = Image.new("RGB", (W * 52, ((len(prev) + W - 1) // W) * 46), (80, 90, 140))
    for i, (n, g, col) in enumerate(prev):
        for y, r in enumerate(g):
            for x, p in enumerate(r):
                if p == ".": continue
                c = {"K": 0, "S": 10, "W": 1, "Y": col}[p]
                for dx in range(2):
                    for dy in range(2):
                        sh.putpixel(((i % W) * 52 + 2 + x * 2 + dx, (i // W) * 46 + 2 + y * 2 + dy), C64[c])
    sh.save(os.path.join(out, "sprites.png"))
    for lit in (True, False):
        syms = sorted({c for r in rooms.ROOMS.values() if r["lit"] == lit for row in r["map"] for c in row})
        print("outdoor" if lit else "indoor", tiles.build_charset(syms)[2], "chars,", len(syms), "tiles")

main(sys.argv[1])
