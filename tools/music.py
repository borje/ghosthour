"""SID tunes (original compositions) compiled to (note, frames) byte streams.
Note index 0 = rest, 1.. = semitones from C-1; $FF = loop. On arp voices, +$80 = major chord."""
NAMES = {"C":0,"C#":1,"Db":1,"D":2,"D#":3,"Eb":3,"E":4,"F":5,"F#":6,"Gb":6,"G":7,"G#":8,"Ab":8,"A":9,"A#":10,"Bb":10,"B":11}
PAL_CLOCK = 985248

def note_num(tok):
    return NAMES[tok[:-1]] + (int(tok[-1]) + 1) * 12 + 1

def freq_table():
    """index = note number; octave -1 .. 6"""
    out = [0]
    for n in range(1, 96):
        hz = 440.0 * 2 ** ((n - 1 - 69) / 12.0)
        out.append(min(65535, int(round(hz * 16777216 / PAL_CLOCK))))
    return out

def compile_voice(text, unit, chord=False):
    """Tokens are NOTE:len, with len in units; '-' is a rest; a trailing M on a chord means major."""
    out = []
    for tok in text.split():
        n, l = tok.split(":")
        frames = int(float(l) * unit)
        major = chord and n.endswith("M")
        if major: n = n[:-1]
        v = 0 if n == "-" else note_num(n)
        out += [v | (0x80 if major else 0), frames]
    return out + [0xFF]

U = 11  # frames per eighth note in the title song
TITLE_LEAD = """
D5:2 F5:1 E5:1 D5:2 A4:2   Bb4:2 A4:1 G4:1 A4:4
D5:2 F5:1 G5:1 A5:2 F5:2   E5:2 C#5:1 A4:1 D5:4
A5:1 Bb5:1 A5:1 G5:1 F5:2 E5:2   F5:1 G5:1 F5:1 E5:1 D5:4
Bb4:2 D5:1 F5:1 G5:2 F5:1 E5:1   A4:1 C#5:1 E5:1 G5:1 A5:4
D6:3 C6:1 Bb5:2 A5:2   G5:1 A5:1 Bb5:1 G5:1 A5:4
F5:1 E5:1 D5:1 C#5:1 D5:2 F5:2   E5:1 D5:1 C#5:1 E5:1 D5:2 -:2
"""
TITLE_BASS = """
D2:1 D3:1 A2:1 D3:1 D2:1 D3:1 A2:1 D3:1   Bb1:1 Bb2:1 F2:1 Bb2:1 A1:1 A2:1 E2:1 A2:1
D2:1 D3:1 A2:1 D3:1 F2:1 F3:1 C3:1 F3:1   A1:1 A2:1 E2:1 A2:1 D2:1 D3:1 A2:1 D3:1
F2:1 F3:1 C3:1 F3:1 C2:1 C3:1 G2:1 C3:1   D2:1 D3:1 A2:1 D3:1 D2:1 D3:1 A2:1 D3:1
G1:1 G2:1 D2:1 G2:1 C2:1 C3:1 G2:1 C3:1   A1:1 A2:1 E2:1 A2:1 A1:1 A2:1 E2:1 A2:1
Bb1:1 Bb2:1 F2:1 Bb2:1 F2:1 F3:1 C3:1 F3:1   G1:1 G2:1 D2:1 G2:1 A1:1 A2:1 E2:1 A2:1
D2:1 D3:1 A2:1 D3:1 G1:1 G2:1 D2:1 G2:1   A1:1 A2:1 A1:1 A2:1 D2:1 D3:1 D2:2
"""
TITLE_ARP = """
D4:4 Bb3M:2 A3M:2      D4:4 F3M:2 F3M:2
A3M:4 D4:4             F3M:2 C4M:2 D4:4
G3:4 C4M:4             A3M:8
Bb3M:4 F3M:4           G3:4 A3M:4
D4:4 G3:4              A3M:4 D4:4
"""
# in-game: a slow, cold heartbeat of a bass line and an uneasy high drone
GAME_BASS = """
D2:2 -:2 D2:2 -:10   D2:2 -:2 D2:2 -:10
Eb2:2 -:2 Eb2:2 -:10   D2:2 -:2 D2:2 -:10
Bb1:2 -:2 Bb1:2 -:10   A1:2 -:2 A1:2 -:10
D2:2 -:2 D2:2 -:10   -:16
"""
GAME_HIGH = """
-:16 A4:8 Ab4:8 -:16 F4:8 E4:8
-:16 D5:4 Db5:4 C5:4 Bb4:4 A4:12 -:20
"""

SONGS = {
    "title": dict(v=[compile_voice(TITLE_BASS, U), compile_voice(TITLE_LEAD, U), compile_voice(TITLE_ARP, U * 2, chord=True)],
                  wave=[0x21, 0x41, 0x41], ad=[0x05, 0x28, 0x08], sr=[0x63, 0xA6, 0x54], arp=[0, 0, 1], vol=0x0F),
    "game": dict(v=[compile_voice(GAME_BASS, 8), compile_voice(GAME_HIGH, 8)],
                 wave=[0x21, 0x11], ad=[0x08, 0x9A], sr=[0x65, 0x89], arp=[0, 0], vol=0x0F),
}
