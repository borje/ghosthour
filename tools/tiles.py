"""Metatiles: 16x16 hi-res px = 8x16 multicolour px = 2x2 chars.

Pixel letters:  . ink (background, black)   a $D022 (room wall colour)
                b $D023 (room detail colour)   c colour RAM (per tile, 0-7)
In the dark version of a char:  a -> .   b -> c   c -> c
so walls vanish into black and structure stays as a dim outline.
"""
SOLID, PLATFORM, LADDER, CLOCK = 1, 2, 4, 8
BLACK, WHITE, RED, CYAN, PURPLE, GREEN, BLUE, YELLOW = range(8)


def rep(rows, n=2):
    return list(rows) * n


FLAT = ["aaaaaaaa"] * 16

_moon = []
for y in range(32):
    row = ""
    for x in range(16):
        dx, dy = (x - 7.5) / 8.0, (y - 15.5) / 16.0
        d = dx * dx + dy * dy
        row += "c" if d < 0.86 else ("." if d < 1.0 else "a")
    _moon.append(row)
# a couple of faint craters
for (cx, cy) in ((5, 9), (10, 20), (6, 22)):
    for yy in range(cy - 1, cy + 2):
        r = list(_moon[yy])
        r[cx] = "b"
        _moon[yy] = "".join(r)

TILES = {
    # sym: (flags, colour, 16 rows of 8)
    " ": (0, BLACK, FLAT),
    "#": (SOLID, RED, rep(["cbb.bbbb", "bbb.bbbb", "bbb.bbbb", "........",
                           "cbbbbb.b", "bbbbbb.b", "bbbbbb.b", "........"])),
    "_": (SOLID, WHITE, ["cccccccc", "bbbbbbbb", "bbbbbb.b", "bbbbbbbb",
                         "........", "bb.bbbbb", "bb.bbbbb", "bb.bbbbb",
                         "........", "bbbbb.bb", "bbbbb.bb", "bbbbb.bb",
                         "........", "b.bbbbbb", "b.bbbbbb", "........"]),
    "=": (PLATFORM, YELLOW, ["cccccccc", "bbbbbbbb", "bbb.bbbb", "bbbbbbbb",
                             "........", ".a.a.a.a", "aaaaaaaa", "a.aaaa.a"]
          + ["aaaaaaaa"] * 8),
    "H": (LADDER, YELLOW, rep(["abaaaaba", "abaaaaba", "bccccccb", "b......b",
                               "abaaaaba", "abaaaaba", "abaaaaba", "abaaaaba"])),
    # windows: two tiles stacked
    "W": (0, CYAN, ["aaaaaaaa", "a......a", "a.bbbb.a", ".bccccb.", ".bcccc.b", ".b.cc.cb",
                    ".bccc..b", ".bc..ccb", ".b....b.", ".bccc.cb", ".bcc.ccb", ".bc.cccb",
                    ".b.ccccb", ".bcc.ccb", ".bccc.cb", ".bcccc.b"]),
    "V": (0, CYAN, [".b....b.", ".bc.cccb", ".b.ccccb", ".bccccc.", ".bcc.ccb", ".bc.cccb",
                    ".b.ccccb", ".bccccc.", ".b....b.", ".bccc.cb", ".bcc.ccb", ".bbbbbbb",
                    "........", "bbbbbbbb", "........", "aaaaaaaa"]),
    # bookshelves
    "B": (0, RED, rep(["bbbbbbbb", "........", "c.b.c.c.", "c.b.c.c.", "c.b.c.b.", "c.b.c.b.",
                       "c.b.c.b.", "bbbbbbbb"])),
    "E": (0, GREEN, rep(["bbbbbbbb", "........", "b.c.c.b.", "b.c.c.b.", "b.c.c.c.", "..c.c.c.",
                         ".bc.c.c.", "bbbbbbbb"])),
    # painting
    "P": (0, YELLOW, ["aaaaaaaa", "aaaaaaaa", "........", ".cccccc.", ".c.bbb..", ".c.bbb..",
                      ".cb...b.", ".cb.b.b.", ".cb...b.", ".cbbbbb.", ".c.b.b..", ".c.bbb..",
                      ".cccccc.", "........", "aaaaaaaa", "aaaaaaaa"]),
    # cobwebs (top-left, top-right)
    "C": (0, WHITE, ["cccccccc", "c.aaca.a", "ca.aacaa", "caa.acaa", "ccaa.caa", "c.c.acaa",
                     "ca.ccaaa", "caacaaaa", "cac.aaaa", "cc.aaaaa", "c.aaaaaa", "caaaaaaa",
                     "caaaaaaa", "caaaaaaa", "aaaaaaaa", "aaaaaaaa"]),
    "c": (0, WHITE, ["cccccccc", "a.acaa.c", "aacaa.ac", "aaca.aac", "aac.aacc", "aaca.c.c",
                     "aaacc.ac", "aaaacaac", "aaaa.cac", "aaaaa.cc", "aaaaaa.c", "aaaaaaac",
                     "aaaaaaac", "aaaaaaac", "aaaaaaaa", "aaaaaaaa"]),
    # door (decor) - two tiles stacked
    "D": (0, YELLOW, ["aa......", "a.bbbbbb", ".bbbbbbb", ".bb.....", ".bb.bbbb", ".bb.bbbb",
                      ".bb.bbbb", ".bb.bbbb", ".bb.bbbb", ".bb.....", ".bbbbbbb", ".bbbbbcc",
                      ".bbbbbcc", ".bbbbbbb", ".bb.....", ".bb.bbbb"]),
    "d": (0, YELLOW, [".bb.bbbb", ".bb.bbbb", ".bb.bbbb", ".bb.bbbb", ".bb.bbbb", ".bb.....",
                      ".bbbbbbb", ".bb.....", ".bb.bbbb", ".bb.bbbb", ".bb.bbbb", ".bb.....",
                      ".bbbbbbb", ".bbbbbbb", ".bbbbbbb", "........"]),
    # stone pillar (decor)
    "i": (0, WHITE, rep(["a.cbbb.a", "a.cbbb.a", "a.cbb..a", "a.cbbb.a",
                         "a.cbbb.a", "a.cbbb.a", "a..bbb.a", "a.cbbb.a"])),
    # roof beams (attic)
    "A": (0, YELLOW, ["bb.aaaaa", "bbb.aaaa", ".bbb.aaa", "a.bbb.aa", "aa.bbb.a", "aaa.bbb.",
                      "aaaa.bbb", "aaaaa.bb", "aaaaaa.b", "aaaaaaa.", "aaaaaaaa", "aaaaaaaa",
                      "aaaaaaaa", "aaaaaaaa", "aaaaaaaa", "aaaaaaaa"]),
    "Z": (0, YELLOW, ["aaaaa.bb", "aaaa.bbb", "aaa.bbb.", "aa.bbb.a", "a.bbb.aa", ".bbb.aaa",
                      "bbb.aaaa", "bb.aaaaa", "b.aaaaaa", ".aaaaaaa", "aaaaaaaa", "aaaaaaaa",
                      "aaaaaaaa", "aaaaaaaa", "aaaaaaaa", "aaaaaaaa"]),
    # lab: flasks on a bench, cauldron
    "l": (0, GREEN, ["aaa..aaa", "aaa..aaa", "aaa..aaa", "aa.cc.aa", "aa.cc.aa", "a.cccc.a",
                     ".cccccc.", ".cccccc.", "a......a", "........", "bbbbbbbb", "........",
                     "ab.aaab.", "ab.aaab.", "ab.aaab.", "ab.aaab."]),
    "o": (0, RED, ["aaaaaaaa", "aa.c.aaa", "aaa.c.aa", "aa.c.aaa", "aaa.caaa", "........",
                   ".cccccc.", "........", "........", ".b......", "........", "........",
                   "........", "a......a", "a.a..a.a", ".c.cc.c."]),
    # cellar: barrel, wine rack, coffin
    "J": (0, YELLOW, ["aaaaaaaa", "aa....aa", "a.bbbb.a", ".bbbbbb.", ".cccccc.", ".bbbbbb.",
                      ".bbbbbb.", ".bb.bbb.", ".bb.bbb.", ".bbbbbb.", ".bbbbbb.", ".cccccc.",
                      ".bbbbbb.", "a.bbbb.a", "aa....aa", "aaaaaaaa"]),
    "j": (0, PURPLE, rep(["bbbbbbbb", "..c...c.", ".ccc.ccc", ".ccc.ccc", "..c...c.", "bbbbbbbb",
                          "b..c...c", "b.ccc.cc"])),
    "u": (0, YELLOW, ["aaa....a", "aa.bbbb.", "a.bbbbbb", ".bbbcbbb", ".bbcccbb", ".bbbcbbb",
                      ".bbbcbbb", ".bbbbbbb", "a.bbbbbb", "a.bbbbbb", "a.bbbbbb", "a.bbbbb.",
                      "aa.bbbb.", "aa.bbbb.", "aaa.bb.a", "aaaa..aa"]),
    "e": (0, GREEN, ["aaaaaaaa", "ca.aaaca", "aaacaaaa", "a.cacaaa", "aacaaa.a", "aaaacaaa",
                     "c.aaaaca", "aaaca.aa", "aaaaaaca", "acaa.aaa", "aaacaaaa", "a.aaacaa",
                     "aacaaaaa", "aaaa.aca", "ca.aaaaa", "aaacaaca"]),
    # bedroom: bed, kitchen: stove, pots, table
    "z": (0, RED, ["aaaaaaaa", "aaaaaaaa", "aaaaaaaa", "aaaaaaaa", "a.aaaaaa", ".b.aaaaa", ".b......",
                   ".bcccccc", ".bcccccc", ".bc.cc.c", ".bcccccc", ".bcccccc", ".b......",
                   ".b.aaaaa", ".b.aaaaa", "...aaaaa"]),
    "q": (0, RED, ["aaa..aaa", "aa.bb.aa", "aa....aa", "a.bbbb.a", "........", "bbbbbbbb", "........",
                   ".b....b.", ".b.cc.b.", ".bcccc..", ".bc..cb.", ".b.cc.b.", ".b....b.",
                   "........", ".b....b.", "........"]),
    "y": (0, YELLOW, ["aa.cc.aa", "a.cccc.a", ".cc.ccc.", "a.cccc.a", "aa....aa", "........",
                      "bbbbbbbb", "........", "a.b..b.a", "a.b..b.a", "a.b..b.a", "a.b..b.a",
                      "a.b..b.a", "a.b..b.a", "a.b..b.a", "a.b..b.a"]),
    # outdoors
    "~": (0, WHITE, ["aaaaaaaa", "aaaaaaca", "aaaaaaca", "aaaaacaa", "aaaaaaaa", "aaaaaaaa",
                     "acaaaaaa", "acaaaaaa", "caaaaaaa", "aaaaaaaa", "aaaacaaa", "aaaacaaa",
                     "aaacaaaa", "aaaaaaaa", "aaaaaaaa", "aaaaaaaa"]),
    "M": (0, WHITE, [r[:8] for r in _moon[:16]]),
    "N": (0, WHITE, [r[8:] for r in _moon[:16]]),
    "m": (0, WHITE, [r[:8] for r in _moon[16:]]),
    "n": (0, WHITE, [r[8:] for r in _moon[16:]]),
    "/": (0, BLACK, [("a" * max(0, 7 - y // 2)).ljust(8, ".") for y in range(16)]),
    "\\": (0, BLACK, [("." * min(8, y // 2 + 1)).ljust(8, "a") for y in range(16)]),
    "!": (0, BLACK, ["........"] * 16),
    "Y": (0, YELLOW, ["........"] * 4 + ["..cc.cc."] * 3 + ["........"] + ["..cc.cc."] * 3 + ["........"] * 5),
    "g": (SOLID, GREEN, ["ccaccacc", "cccccccc", "cc.ccc.c", "........", "bbbbbbbb", "bb.bbbbb",
                         "bbbbbbbb", "bbbbb.bb", "........", "bb.bb.bb", "bbbbbbbb", "bbb.bbbb",
                         "........", "bbbbbbb.", "b.bbbbbb", "........"]),
    '"': (0, GREEN, ["aaaaaaaa"] * 10 + ["aaaaacaa", "acaaacaa", "acacacac", "cacacaca",
                                         "cacccaca", "cccccccc"]),
    "t": (PLATFORM, WHITE, ["aaa..aaa", "aa.bb.aa", "a.cbbb.a", ".cbbbbb.", ".cb..bb.", ".cbbbbb.",
                            ".cb...b.", ".cbbbbb.", ".cb...b.", ".cbbbbb.", ".cbbbbb.", ".cbbbbb.",
                            ".cbbbbb.", ".cbbbbb.", ".cbbbbb.", "........"]),
    "x": (0, WHITE, ["aaaa.aaa", "aaa.c.aa", "aaa.b.aa", "a...b...", ".ccbbbb.", "a...b...",
                     "aaa.b.aa", "aaa.b.aa", "aaa.b.aa", "aaa.b.aa", "aaa.b.aa", "aaa.b.aa",
                     "aa.bbb.a", "a.bbbbb.", "a.bbbbb.", "........"]),
    "f": (0, BLACK, ["aa.aaa.a", "aa.aaa.a", "aa.aaa.a", "aa.aaa.a", "a...a...", "a...a...", "aa.aaa.a",
                     "........", "aa.aaa.a", "aa.aaa.a", "aa.aaa.a", "aa.aaa.a", "aa.aaa.a", "aa.aaa.a",
                     "........", "aa.aaa.a"]),
    "G": (SOLID, RED, ["a.......", ".ccccccc", ".bbbbbbb", "........", "cbb.bbbb", "bbb.bbbb",
                       "bbb.bbbb", "........", "cbbbbb.b", "bbbbbb.b", "bbbbbb.b", "........",
                       "cbb.bbbb", "bbb.bbbb", "bbb.bbbb", "........"]),
}

# brick facade you walk in front of
TILES["%"] = (0, TILES["#"][1], TILES["#"][2])

# The grandfather clock: 2 tiles wide, 3 tall, 16x48 multicolour px
_clock = [
    "aaaaa......aaaaa", "aaa..bbbbbb..aaa", "aa.bbbbbbbbbb.aa", "aa.bb......bb.aa",
    "a.bb.cccccc.bb.a", "a.b.cc.cc.cc.b.a", "a.b.cccccccc.b.a", "a.b.ccc.cccc.b.a",
    "a.b.c.c.cc.c.b.a", "a.b.ccc.cccc.b.a", "a.b.ccc.cccc.b.a", "a.b.cc.cc.cc.b.a",
    "a.bb.cccccc.bb.a", "aa.bb......bb.aa", "aa.bbbbbbbbbb.aa", "aaa..........aaa",
    "aaa.bbbbbbbb.aaa", "aaa.bb....bb.aaa", "aaa.b.bccb.b.aaa", "aaa.b.bccb.b.aaa",
    "aaa.b.bccb.b.aaa", "aaa.b.bccb.b.aaa", "aaa.b.bccb.b.aaa", "aaa.b.bccb.b.aaa",
    "aaa.b.bccb.b.aaa", "aaa.b.bccb.b.aaa", "aaa.b.ccccb.b.aa"[:16], "aaa.b.ccccb.b.aa"[:16],
    "aaa.b.bccb.b.aaa", "aaa.bb....bb.aaa", "aaa.bbbbbbbb.aaa", "aaa.........aaaa"[:16],
    "aa.bbbbbbbbbb.aa", "aa.bb......bb.aa", "aa.bb.cccc.bb.aa", "aa.bb.c..c.bb.aa",
    "aa.bb.c..c.bb.aa", "aa.bb.cccc.bb.aa", "aa.bb......bb.aa", "aa.bbbbbbbbbb.aa",
    "aa.bbbbbbbbbb.aa", "aa.bb......bb.aa", "aa.bb.bbbb.bb.aa", "aa.bb.bbbb.bb.aa",
    "aa.bb......bb.aa", "a.bbbbbbbbbbbb.a", "a..............a", "aaaaaaaaaaaaaaaa",
]
for i, (sym, col) in enumerate(zip("KLQRST", (WHITE, WHITE, YELLOW, YELLOW, YELLOW, YELLOW))):
    x = 0 if i % 2 == 0 else 8
    y = (i // 2) * 16
    TILES[sym] = (CLOCK, col, [r[x:x + 8] for r in _clock[y:y + 16]])

DARK_MAP = {".": ".", "a": ".", "b": "c", "c": "c"}
PIX = {".": 0, "a": 1, "b": 2, "c": 3}


def build_charset(symbols):
    """Build one 256-char set (128 lit + 128 dark) from the given tile symbols.
    Returns (dict sym -> (tl, tr, bl, br), charset_bytes, char_count)."""
    chars, index = [], {}

    def char_of(rows):
        key = tuple(rows)
        if key not in index:
            index[key] = len(chars)
            chars.append(rows)
        return index[key]

    codes = {}
    for s in symbols:
        _, _, rows = TILES[s]
        assert len(rows) == 16, (s, len(rows))
        for r in rows:
            assert len(r) == 8, (s, r)
        codes[s] = (char_of([r[:4] for r in rows[:8]]), char_of([r[4:] for r in rows[:8]]),
                    char_of([r[:4] for r in rows[8:]]), char_of([r[4:] for r in rows[8:]]))
    assert len(chars) <= 128, f"too many chars: {len(chars)}"
    data = bytearray(2048)
    for i, rows in enumerate(chars):
        for y, r in enumerate(rows):
            v = dv = 0
            for p in r:
                v = v * 4 + PIX[p]
                dv = dv * 4 + PIX[DARK_MAP[p]]
            data[i * 8 + y] = v
            data[(i + 128) * 8 + y] = dv
    return codes, bytes(data), len(chars)
