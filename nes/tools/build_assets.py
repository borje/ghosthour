"""Generates what the NES build includes: build/chr_*.bin, build/gen_const.inc and build/gen_data.inc.

The art is shared with the C64 version: tiles, sprites, font and room settings are imported from
../../tools. Only the conversion to NES formats and the 16-column layouts (layouts.py) are NES-specific.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(1, os.path.join(HERE, "..", "..", "tools"))
import font, palette, rooms, sprites, tiles  # noqa: E402  (C64 sources)
import layouts  # noqa: E402
import sound  # noqa: E402

OUT = sys.argv[1] if len(sys.argv) > 1 else "build"

# 2C02 colours (the common FCEUX/Nestopia table), used to pick the nearest NES colour.
NES_RGB = bytes.fromhex(
    "7C7C7C0000FC0000BC4428BC940084A80020A81000881400503000007800006800005800004058000000000000000000"
    "BCBCBC0078F80058F86844FCD800CCE40058F83800E45C10AC7C0000B80000A80000A844008888000000000000000000"
    "F8F8F83CBCFC6888FC9878F8F878F8F85898F87858FCA044F8B800B8F81858D85458F89800E8D8787878000000000000"
    "FCFCFCA4E4FCB8B8F8D8B8F8F8B8F8F8A4C0F0D0B0FCE0A8F8D878D8F878B8F8B8B8F8D800FCFCF8D8F8000000000000")
NES_RGB = [tuple(NES_RGB[i * 3:i * 3 + 3]) for i in range(64)]
BLACK = 0x0F


def nes_colour(c64):
    if c64 == 0:
        return BLACK
    r, g, b = palette.C64[c64]
    return min((i for i in range(64) if i % 16 not in (0x0D, 0x0E, 0x0F)),
               key=lambda i: (NES_RGB[i][0] - r) ** 2 * 3 + (NES_RGB[i][1] - g) ** 2 * 4 + (NES_RGB[i][2] - b) ** 2 * 2)


C64_TO_NES = [nes_colour(i) for i in range(16)]
C64_TO_NES[6] = 0x02    # blue: the nearest match ($03) reads as purple
C64_TO_NES[7] = 0x28    # yellow: the slicker should be golden, not pale
C64_TO_NES[10] = 0x36   # skin
C64_TO_NES[11] = 0x00   # dark grey: the NES has no darker grey (and $2D shows the same)


def rgb_dist(a, b):
    return sum((x - y) ** 2 for x, y in zip(NES_RGB[C64_TO_NES[a]], NES_RGB[C64_TO_NES[b]]))


def tile_2bpp(rows):
    """8 rows of 8 pixel values (0-3) -> 16 bytes, NES planar."""
    lo, hi = bytearray(8), bytearray(8)
    for y, r in enumerate(rows):
        for x, v in enumerate(r):
            if v & 1:
                lo[y] |= 0x80 >> x
            if v & 2:
                hi[y] |= 0x80 >> x
    return bytes(lo + hi)


def c64_mc_char(data, code):
    """A C64 multicolour char (4 wide pixels per row) doubled to 8 NES pixels; values 0-3 = . a b c"""
    rows = []
    for y in range(8):
        b = data[code * 8 + y]
        px = [(b >> (6 - 2 * i)) & 3 for i in range(4)]
        rows.append([p for p in px for _ in (0, 1)])
    return rows


# In the dark the wall colour drops to black and detail becomes one colour. The C64 uses one dim
# colour for that; on the NES it is palette entry 1, the room's wall colour, which every palette shares.
DARK = {0: 0, 1: 0, 2: 1, 3: 1}

# ---------------------------------------------------------------- font (shared by both tile sets)
FONT_CHARS = " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!.,?'-:"
FONT_SPECIAL = ([("GAUGE%d" % n, font.H_GAUGE + n) for n in range(9)]
                + [("RULE", font.H_RULE), ("HEART", font.H_HEART), ("HEART0", font.H_HEART0)]
                + [("ICON%d" % n, font.H_ICON + n) for n in range(5)])
FONT_BASE = 256 - len(FONT_CHARS) - len(FONT_SPECIAL)
fdata = font.build()


def c64_screen_code(ch):
    return 32 if ch == " " else (ord(ch) - 64 if ch.isalpha() else ord(ch))


font_tiles = []
for code in [c64_screen_code(c) for c in FONT_CHARS] + [c for _, c in FONT_SPECIAL]:
    font_tiles.append(tile_2bpp([[3 if fdata[code * 8 + y] & (0x80 >> x) else 0 for x in range(8)] for y in range(8)]))
FONT = {c: FONT_BASE + i for i, c in enumerate(FONT_CHARS)}
for i, (name, _) in enumerate(FONT_SPECIAL):
    FONT[name] = FONT_BASE + len(FONT_CHARS) + i
BLANK = FONT[" "]


def encode(s):
    return [FONT[c] for c in s.upper()]


# ---------------------------------------------------------------- tile sets
names = list(rooms.ROOMS)
SETS = {False: "in", True: "out"}           # keyed by the C64 'lit' (moonlit = outdoor) flag
set_codes, set_dark, chr_sets = {}, {}, {}
for lit, tag in SETS.items():
    syms = sorted({c for n in names if rooms.ROOMS[n]["lit"] == lit for row in layouts.ROOMS[n]["map"] for c in row})
    codes, c64_chars, count = tiles.build_charset(syms)
    nes = [tile_2bpp(c64_mc_char(c64_chars, i)) for i in range(count)]
    dark_of = list(range(256))
    if not lit:
        for i in range(count):
            d = tile_2bpp([[DARK[v] for v in row] for row in c64_mc_char(c64_chars, i)])
            if d not in nes[count:]:
                nes.append(d)
            dark_of[i] = count + nes[count:].index(d)
    assert len(nes) <= FONT_BASE, f"{tag}: {len(nes)} room tiles, room for {FONT_BASE}"
    data = bytearray(4096)
    for i, t in enumerate(nes):
        data[i * 16:i * 16 + 16] = t
    for i, t in enumerate(font_tiles):
        data[(FONT_BASE + i) * 16:(FONT_BASE + i) * 16 + 16] = t
    chr_sets[tag] = bytes(data)
    set_codes[lit], set_dark[lit] = codes, dark_of
    print(f"tile set {tag:3}: {count} lit + {len(nes) - count} dark + {len(font_tiles)} font = "
          f"{len(nes) + len(font_tiles)}/256, {len(syms)} metatiles")

# global metatile ids, as on the C64: (set, symbol) -> id
mt_index, mt = {}, dict(tl=[], tr=[], bl=[], br=[], flags=[])
for lit in SETS:
    for s in sorted(set_codes[lit]):
        mt_index[(lit, s)] = len(mt["tl"])
        for k, v in zip(("tl", "tr", "bl", "br"), set_codes[lit][s]):
            mt[k].append(v)
        mt["flags"].append(tiles.TILES[s][0])
assert len(mt["tl"]) < 256

# ---------------------------------------------------------------- sprites
# Every sprite is the C64 24x21 drawing cut into 3x3 tiles (8x8), one colour layer. Facing the
# other way uses the NES flip bit, so only one direction is stored. Pixel letters -> colour 1-3:
SPR_MAP = {
    "hero":   {"K": 1, "Y": 2, "S": 3, "W": 3},     # ink, slicker, skin (C64 white -> skin)
    "enemy":  {"K": 1, "Y": 2, "S": 3, "W": 3},     # ink, body colour, light details
    "eyes":   {"Y": 3},
    "flame":  {"Y": 1, "W": 2},
    "item":   {"#": 2},
}
spr_tiles = [bytes(16)]
meta = []           # 9 tile numbers per frame, 0 = empty
frame_no = {}


def add_frame(name, grid, kind):
    g = sprites.norm(grid) + ["." * 24] * 3
    frame_no[name] = len(meta) // 9
    for ty in range(3):
        for tx in range(3):
            t = tile_2bpp([[SPR_MAP[kind].get(g[ty * 8 + y][tx * 8 + x], 0) for x in range(8)] for y in range(8)])
            if not any(t):
                meta.append(0)
                continue
            if t not in spr_tiles:
                spr_tiles.append(t)
            meta.append(spr_tiles.index(t))


for i, k in enumerate(("stand", "run1", "run2", "run3", "jump")):
    add_frame(f"HERO{i}", sprites.TOP + sprites.LEGS[k].split(), "hero")
add_frame("HERO5", sprites.CLIMB1, "hero")
add_frame("HERO6", sprites.CLIMB2, "hero")
for name in ("GHOST", "BAT", "WOLF", "BROOKE"):
    for a in (1, 2):
        add_frame(f"{name}{a}", getattr(sprites, f"{name}{a}"), "enemy")
for name in ("EYES_G", "EYES_B", "EYES_W"):
    add_frame(name, getattr(sprites, name), "eyes")
for i, f in enumerate(sprites.FLAME):
    add_frame(f"FLAME{i}", f, "flame")
for k in ("cog", "spring", "pendulum", "key", "candle", "glint"):
    add_frame("ITEM_" + k.upper(), sprites.ITEMS[k], "item")
assert len(spr_tiles) <= 256, len(spr_tiles)
chr_spr = bytearray(4096)
for i, t in enumerate(spr_tiles):
    chr_spr[i * 16:i * 16 + 16] = t

# sprite palettes: 0 the hero, 1 flame and items, 2 and 3 the room's two enemies (set per room)
SPR_PAL_HERO = [BLACK, BLACK, C64_TO_NES[7], C64_TO_NES[10]]
SPR_PAL_ITEM = [BLACK, C64_TO_NES[7], 0x30, 0x2A]
ENEMY_PAL = [            # colours 1-3 for ghost, bat, wolf, Brooke
    [BLACK, 0x10, 0x30],     # ghost: grey sheet, white; eyes white
    [BLACK, 0x00, 0x16],     # bat: dark wings, red eyes
    [BLACK, 0x07, 0x37],     # wolf: brown, cream snout and paws; eyes cream
    [BLACK, C64_TO_NES[7], C64_TO_NES[10]],   # Brooke: like the hero, her white dress in the skin colour
]

# ---------------------------------------------------------------- rooms
def uses_c(sym):
    return any("c" in r for r in tiles.TILES[sym][2])


room_map, room_attr, room_pal = [], [], []
HUD_COL = tiles.WHITE
for n in names:
    r, lay = rooms.ROOMS[n], layouts.ROOMS[n]["map"]
    # one background palette per tile colour, at most 4: the rarest colours merge into the nearest
    use = {HUD_COL: 1000}
    for row in lay:
        for s in row:
            if uses_c(s):
                use[tiles.TILES[s][1]] = use.get(tiles.TILES[s][1], 0) + 1
    merged = {c: c for c in use}
    while len(set(merged.values())) > 4:
        live = sorted(set(merged.values()), key=lambda c: use.get(c, 0))
        rare = live[0]
        into = min((c for c in live if c != rare), key=lambda c: rgb_dist(rare, c))
        for k in merged:
            if merged[k] == rare:
                merged[k] = into
        use[into] = use.get(into, 0) + use.get(rare, 0)
        print(f"  {n}: colour {rare} drawn as {into} (the NES has 4 background palettes)")
    cols = sorted(set(merged.values()), key=lambda c: (c != HUD_COL, c))
    d022, d023, _ = r["pal"]
    wall, detail = C64_TO_NES[d022], C64_TO_NES[d023]
    if detail == wall:          # e.g. the stone rooms: dark and mid grey are one NES grey
        detail = wall + 0x10
    pals = [[BLACK, wall, detail, C64_TO_NES[c]] for c in cols]
    while len(pals) < 4:
        pals.append(pals[0])
    room_pal += [c for p in pals for c in p]
    attr = [[0] * 16 for _ in range(15)]          # HUD rows use palette 0, the white one
    for my, row in enumerate(lay):
        for mx, s in enumerate(row):
            room_map.append(mt_index[(r["lit"], s)])
            if uses_c(s):
                attr[1 + my][mx] = cols.index(merged[tiles.TILES[s][1]])
    for by in range(8):
        for bx in range(8):
            v = 0
            for i, (dy, dx) in enumerate(((0, 0), (0, 1), (1, 0), (1, 1))):
                y, x = by * 2 + dy, bx * 2 + dx
                if y < 15:
                    v |= attr[y][x] << (i * 2)
            room_attr.append(v)

idx = {n: i for i, n in enumerate(names)}

# rain: the outdoor '~' tile, rotated down 2 rows per step (as on the C64), 8 steps.
# Each step is 4 tiles of 16 bytes in the order TL, BL, TR, BR.
rain = set_codes[True]["~"]
rain_frames = []
src = chr_sets["out"]
for step in range(8):
    for top, bot in ((rain[0], rain[2]), (rain[1], rain[3])):
        rows16 = [(src[top * 16 + y], src[top * 16 + 8 + y]) for y in range(8)]
        rows16 += [(src[bot * 16 + y], src[bot * 16 + 8 + y]) for y in range(8)]
        rot = [rows16[(y - 2 * step) % 16] for y in range(16)]
        for half in (rot[:8], rot[8:]):
            rain_frames += [lo for lo, _ in half] + [hi for _, hi in half]

disc = []
for R in range(9):
    for dy in range(9):
        disc.append(0xFF if dy > R else int(((R + 0.45) ** 2 - dy * dy) ** 0.5))

# ---------------------------------------------------------------- outputs
os.makedirs(OUT, exist_ok=True)
for tag, data in chr_sets.items():
    with open(os.path.join(OUT, f"chr_{tag}.bin"), "wb") as f:
        f.write(data)
with open(os.path.join(OUT, "chr_spr.bin"), "wb") as f:
    f.write(bytes(chr_spr))


def ca65_bytes(label, values, per=16):
    values = list(values)
    lines = [f"{label}:"]
    for i in range(0, len(values), per):
        lines.append("  .byte " + ",".join(f"${v & 255:02X}" for v in values[i:i + per]))
    return "\n".join(lines) + "\n"


const = ["; GENERATED by nes/tools/build_assets.py - do not edit\n",
         f"TF_SOLID = {tiles.SOLID}\nTF_PLATFORM = {tiles.PLATFORM}\nTF_LADDER = {tiles.LADDER}\nTF_CLOCK = {tiles.CLOCK}\n",
         f"NUM_ROOMS = {len(names)}\nSTART_ROOM = {idx[rooms.START_ROOM]}\n",
         f"START_X = {layouts.START[0]}\nSTART_Y = {layouts.START[1]}\n",
         f"BLANK = {BLANK}\nT_RULE = {FONT['RULE']}\nT_GAUGE = {FONT['GAUGE0']}\n",
         f"RAIN_TL = {rain[0]}\nRAIN_TR = {rain[1]}\nRAIN_BL = {rain[2]}\nRAIN_BR = {rain[3]}\n"]
data = ["; GENERATED by nes/tools/build_assets.py - do not edit\n"]
for k in ("tl", "tr", "bl", "br", "flags"):
    data.append(ca65_bytes(f"mt_{k}", mt[k]))
data.append(ca65_bytes("room_maps", room_map))
data.append(ca65_bytes("room_attrs", room_attr))
data.append(ca65_bytes("room_pals", room_pal))
data.append(ca65_bytes("room_lit", [1 if rooms.ROOMS[n]["lit"] else 0 for n in names]))
for side in "LRUD":
    data.append(ca65_bytes(f"room_exit_{side.lower()}",
                           [idx[rooms.ROOMS[n]["exits"][side]] if side in rooms.ROOMS[n]["exits"] else 255 for n in names]))
data.append(ca65_bytes("room_names", [c for n in names for c in encode(n.ljust(10))]))
data.append(ca65_bytes("dark_in", set_dark[False]))
data.append(ca65_bytes("disc_table", disc, 9))
data.append(ca65_bytes("rain_frames", rain_frames))
data.append(ca65_bytes("spr_palettes", SPR_PAL_HERO + SPR_PAL_ITEM))
data.append(ca65_bytes("enemy_pals", [c for p in ENEMY_PAL for c in p]))
data.append(ca65_bytes("meta_tiles", meta, 9))
nframes = len(meta) // 9
data.append("meta_lo:\n" + "".join(f"  .byte <(meta_tiles+{i * 9})\n" for i in range(nframes)))
data.append("meta_hi:\n" + "".join(f"  .byte >(meta_tiles+{i * 9})\n" for i in range(nframes)))
for k, v in frame_no.items():
    const.append(f"F_{k} = {v}\n")
# enemies and items per room, in NES positions (as the C64 build: x = col*16, y = row*16-5)
for slot in range(2):
    es = []
    for n in names:
        c64 = (rooms.ROOMS[n]["enemies"] + [None, None])[slot]
        pos = (layouts.ROOMS[n]["enemies"] + [None, None])[slot]
        es.append((c64[0], pos[0] * 16, pos[1] * 16 - 5) if c64 else None)
    data.append(ca65_bytes(f"room_e{slot}_type", [e[0] if e else 255 for e in es]))
    data.append(ca65_bytes(f"room_e{slot}_x", [e[1] if e else 0 for e in es]))
    data.append(ca65_bytes(f"room_e{slot}_y", [e[2] & 255 if e else 0 for e in es]))
items = [(rooms.ROOMS[n]["item"][0],) + tuple(layouts.ROOMS[n]["item"]) if rooms.ROOMS[n]["item"] else None for n in names]
data.append(ca65_bytes("room_item", [i[0] if i else 255 for i in items]))
data.append(ca65_bytes("room_item_x", [i[1] * 16 - 4 if i else 0 for i in items]))
data.append(ca65_bytes("room_item_y", [i[2] * 16 - 2 if i else 0 for i in items]))
brooke_room = next(n for n in names if any(e[0] == rooms.BROOKE for e in rooms.ROOMS[n]["enemies"]))
const.append(f"HALL_ROOM = {idx[rooms.HALL_ROOM]}\nBROOKE_ROOM = {idx[brooke_room]}\n")
const.append(f"BROOKE_HALL_X = {layouts.BROOKE_IN_HALL[0]}\nBROOKE_HALL_Y = {layouts.BROOKE_IN_HALL[1]}\n")
const.append(f"T_HEART = {FONT['HEART']}\nT_HEART0 = {FONT['HEART0']}\nT_ICON = {FONT['ICON0']}\nT_ICON0 = {FONT['ICON4']}\n")
MESSAGES = dict(txt_wax="WAX:", txt_nerve="NERVE:", txt_clock="CLOCK:",
    msg_boom="BOOM! CRASH!", msg_dark="YOUR CANDLE IS OUT!", msg_start="THE GATE SLAMS SHUT!",
    msg_win="TWELVE O'CLOCK!", msg_candle="A FRESH CANDLE!", msg_part="A CLOCK PART!", msg_eek="EEEK!",
    msg_bat="A BAT! YOUR WAX!", msg_clock0="IT NEEDS FOUR PARTS.", msg_snuff="TOO DARK! TOO DARK!",
    msg_help="HELP! UP HERE!", msg_glint="A CLOCK PART IS HERE!", msg_keep="BROOKE: KEEP IT UP...",
    msg_nowax="BROOKE: FIND A CANDLE!", msg_hold="BROOKE: HOLD B!", msg_thanks="BROOKE: TAKE THIS KEY!",
    msg_waits="BROOKE WAITS FOR YOU.", msg_welldone="WELL DONE! PRESS START.",
    msg_faint="YOU FAINT. PRESS START.")
for label, text in MESSAGES.items():
    assert len(text) <= 28, text
    data.append(ca65_bytes(label, encode(text) + [0]))
snd_const, snd_data = sound.asm()
const.append(snd_const)
data.append(snd_data)
with open(os.path.join(OUT, "gen_const.inc"), "w") as f:
    f.write("".join(const))
with open(os.path.join(OUT, "gen_data.inc"), "w") as f:
    f.write("".join(data))
print(f"sprite tiles: {len(spr_tiles)}/256, sprite frames: {len(meta) // 9}, metatiles: {len(mt['tl'])}, rooms: {len(names)}")
