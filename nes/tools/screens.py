"""The story, win and lose screens: the C64 texts (../../src/main.asm), rewrapped for the
28 columns a TV shows of the NES screen. Each paragraph has a colour; paragraphs are separated
by an empty row, so every 16-pixel band of the screen holds one colour (the NES sets colours
per 16x16 block)."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from colours import BLACK, C64_TO_NES  # noqa: E402

WHITE, RED, YELLOW, LBLUE, LGREY = 1, 2, 7, 14, 15
WIDTH = 28

# (colour, centred, lines)
STORY = [
    (YELLOW, True, ["GHOST HOUR"]),
    (WHITE, False, ["A STORMY NIGHT. YOUR BICYCLE", "IS IN A DITCH, AND THE", "TELEGRAM IN YOUR POCKET IS",
                    "FOR THE OLD MANOR HOUSE."]),
    (LGREY, False, ["THE GREAT CLOCK STOPPED ONE", "MINUTE BEFORE MIDNIGHT, AND",
                    "THE HOUR OF THE GHOSTS HAS", "NEVER ENDED."]),
    (WHITE, False, ["FIND THE FOUR LOST CLOCK", "PARTS AND BRING THEM TO THE", "GREAT HALL. AND LISTEN:",
                    "SOMEONE IS CALLING FOR HELP."]),
    (YELLOW, False, ["PAD: WALK.  A OR UP: JUMP,", "UP AND DOWN: CLIMB LADDERS.", "B: RAISE YOUR CANDLE TO",
                     "SCARE GHOSTS - BUT IT BURNS", "WAX."]),
    (LBLUE, True, ["PRESS START TO ENTER"]),
]
WIN = [
    (YELLOW, True, ["BONG! BONG! BONG!"]),
    (WHITE, False, ["THE CLOCK STRIKES TWELVE AT", "LAST."]),
    (LGREY, False, ["ONE BY ONE THE SHEETS SINK", "EMPTY TO THE FLOOR. THE", "MANOR SIGHS. EVEN THE RAIN",
                    "STOPS."]),
    (WHITE, False, ["YOU DELIVER THE TELEGRAM TO", "NOBODY, AND BROOKE HELPS",
                    "FIND YOUR BICYCLE."]),
    (LBLUE, True, ["WELL DONE!"]),
]
LOSE = [
    (RED, True, ["EEEK!!"]),
    (WHITE, False, ["IT IS ALL TOO MUCH. YOU", "FAINT ON THE SPOT, AND WAKE", "UP WITH A COLD, A SHEET OVER",
                    "YOU, AND AN ODD URGE TO", "FLOAT."]),
    (LBLUE, True, ["PRESS START TO TRY AGAIN"]),
]
PAGES = dict(story=STORY, win=WIN, lose=LOSE)


def page(paras, encode):
    """Returns bytes: 16 palette bytes, 64 attribute bytes, then lines of
    (address hi, address lo, text..., 0), ended by $FF."""
    colours = []
    for c, _, _ in paras:
        if c not in colours:
            colours.append(c)
    assert len(colours) <= 4
    pal = []
    for c in colours + [colours[0]] * (4 - len(colours)):
        pal += [BLACK, BLACK, BLACK, C64_TO_NES[c] if c != 10 else 0x26]
    rows = sum(len(p[2]) for p in paras) + len(paras) - 1
    row = (30 - rows) // 2
    attr_rows = [None] * 15
    out = bytearray()
    for c, centred, lines in paras:
        for line in lines:
            assert len(line) <= WIDTH, line
            col = (32 - len(line)) // 2 if centred else 2
            a = 0x2000 + row * 32 + col
            out += bytes([a >> 8, a & 255]) + bytes(encode(line)) + b"\0"
            assert attr_rows[row // 2] in (None, c), f"two colours in one band at row {row}"
            attr_rows[row // 2] = c
            row += 1
        row += 1
    out.append(0xFF)
    attr = bytearray(64)
    for by in range(8):
        v = 0
        for i, dy in enumerate((0, 0, 1, 1)):
            y = by * 2 + dy
            c = attr_rows[y] if y < 15 else None
            v |= (colours.index(c) if c is not None else 0) << (i * 2)
        for bx in range(8):
            attr[by * 8 + bx] = v
    return bytes(pal) + bytes(attr) + bytes(out)
