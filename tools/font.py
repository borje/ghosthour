"""Bold comic-style HUD font, derived from a classic 5x7 column table and thickened by one pixel.
Laid out in C64 screen-code order so ACME's !scr strings map straight on."""
F5X7 = {
"A":"7E1111117E","B":"7F49494936","C":"3E41414122","D":"7F4141413E","E":"7F49494941","F":"7F09090901",
"G":"3E4149497A","H":"7F0808087F","I":"00417F4100","J":"2040413F01","K":"7F08142241","L":"7F40404040",
"M":"7F020C027F","N":"7F0408107F","O":"3E4141413E","P":"7F09090906","Q":"3E4151215E","R":"7F09192946",
"S":"4649494931","T":"01017F0101","U":"3F4040403F","V":"1F2040201F","W":"3F4038403F","X":"6314081463",
"Y":"0708700807","Z":"6151494543",
"0":"3E5149453E","1":"00427F4000","2":"4261514946","3":"2141454B31","4":"1814127F10","5":"2745454539",
"6":"3C4A494930","7":"0171090503","8":"3649494936","9":"064949291E",
"!":"00005F0000",".":"0060600000",",":"0080600000","?":"0201510906","'":"0000070000","-":"0808080808",":":"0036360000",
}

def glyph(ch):
    cols = bytes.fromhex(F5X7[ch])
    rows = bytearray(8)
    for x, c in enumerate(cols):
        for y in range(8):
            if c >> y & 1:
                rows[y] |= (0xC0 >> x)   # the 2-px stamp thickens every stroke
    return bytes(rows)

HEART = ["01100110", "11111111", "11111111", "11111111", "01111110", "00111100", "00011000", "00000000"]
HEART0 = ["01100110", "10011001", "10000001", "10000001", "01000010", "00100100", "00011000", "00000000"]
ICONS = [
    ["00011000", "01011010", "01111110", "11100111", "11100111", "01111110", "01011010", "00011000"],  # cog
    ["01111110", "00100001", "01111110", "10000100", "01111110", "00100001", "01111110", "00000000"],  # spring
    ["00011000", "00011000", "00011000", "00011000", "00111100", "01111110", "01111110", "00111100"],  # pendulum
    ["01110000", "10001000", "01110000", "00100000", "00100000", "00111000", "00100000", "00111000"],  # key
    ["00000000", "01100110", "10000001", "00000000", "10000001", "01100110", "00000000", "00000000"],  # empty slot
]
RULE = ["00000000", "00000000", "00000000", "11111111", "11111111", "00000000", "00000000", "00000000"]

H_GAUGE, H_HEART, H_HEART0, H_ICON, H_ICON0, H_RULE = 64, 73, 74, 75, 79, 80

def build():
    data = bytearray(2048)
    def put(i, b): data[i * 8:i * 8 + 8] = b
    for i, ch in enumerate("ABCDEFGHIJKLMNOPQRSTUVWXYZ", 1): put(i, glyph(ch))
    for ch in "0123456789!.,?'-:": put(ord(ch), glyph(ch))
    bits = lambda rows: bytes(int(r, 2) for r in rows)
    for n in range(9):                            # wax gauge: n of 8 columns full
        v = (0xFF00 >> n) & 0xFF
        put(H_GAUGE + n, bytes([0xFF] + [v] * 6 + [0xFF]))
    put(H_HEART, bits(HEART)); put(H_HEART0, bits(HEART0))
    for i, ic in enumerate(ICONS): put(H_ICON + i, bits(ic))
    put(H_RULE, bits(RULE))
    return bytes(data)
