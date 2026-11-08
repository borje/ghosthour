"""C64 colours to NES colours."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(1, os.path.join(HERE, "..", "..", "tools"))
import palette  # noqa: E402  (C64 source)

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
