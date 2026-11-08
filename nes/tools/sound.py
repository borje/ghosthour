"""NES versions of the C64 tunes and sound effects (../../tools/music.py and the sfx tables in
../../src/main.asm). Durations are rescaled from 50 to 60 frames a second, and the SID's ADSR
envelopes become per-frame volume tables, because the NES channels have no envelope of that kind.

Channels: 0 pulse 1, 1 pulse 2, 2 triangle, 3 noise.
In the game the bass is on the triangle and the drone on pulse 2, which leaves pulse 1 and the
noise channel to the sound effects. The title tune also uses pulse 1, for its arpeggio.
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(1, os.path.join(HERE, "..", "..", "tools"))
import music  # noqa: E402  (C64 source)

CPU = 1789773           # NTSC
TIME = 60 / 50          # NES frames per C64 frame
SID_CLOCK = 985248      # PAL C64

ATTACK_MS = [2, 8, 16, 24, 38, 56, 68, 80, 100, 250, 500, 800, 1000, 3000, 5000, 8000]
DECAY_MS = [6, 24, 48, 72, 114, 168, 204, 240, 300, 750, 1500, 2400, 3000, 9000, 15000, 24000]


def envelope(ad, sr, peak, frames):
    """Volume 0-15 for each frame after the gate opens (the SID's attack, decay, sustain)."""
    a = ATTACK_MS[ad >> 4] / 1000 * 60
    d = DECAY_MS[ad & 15] / 1000 * 60
    s = (sr >> 4) / 15
    out = []
    for t in range(frames):
        if t < a:
            level = (t + 1) / max(a, 1)
        elif t < a + d:
            level = 1 - (1 - s) * (t - a) / d
        else:
            level = s
        out.append(max(0, min(15, int(round(peak * min(level, 1))))))
    return out


def note_hz(n):
    return 440.0 * 2 ** ((n - 1 - 69) / 12.0)


def pulse_period(hz):
    return max(8, min(2047, int(round(CPU / (16 * hz) - 1))))


def tri_period(hz):
    return max(2, min(2047, int(round(CPU / (32 * hz) - 1))))


PULSE_TABLE = [0] + [pulse_period(note_hz(n)) for n in range(1, 96)]
TRI_TABLE = [0] + [tri_period(note_hz(n)) for n in range(1, 96)]

# ---------------------------------------------------------------- music
DUTY = {"12": 0x00, "25": 0x40, "50": 0x80}
ENV_LEN = 64
instruments = []        # (duty bits, envelope table)


def instrument(duty, ad, sr, peak):
    instruments.append((DUTY[duty], envelope(ad, sr, peak, ENV_LEN)))
    return len(instruments) - 1


def voice(text, unit, chord=False):
    out = music.compile_voice(text, unit * TIME, chord)
    assert all(0 < d < 256 for d in out[1:-1:2]), "a note is too long for one byte"
    return out


# Each song: up to 3 voices of (channel, instrument, arpeggio, data).
# The SID's waveforms map to: pulse -> square, triangle -> soft square, sawtooth on the bass -> triangle.
SONGS = {
    "title": [
        (2, None, 0, voice(music.TITLE_BASS, music.U)),
        (1, instrument("50", 0x28, 0xA6, 9), 0, voice(music.TITLE_LEAD, music.U)),
        (0, instrument("25", 0x08, 0x54, 6), 1, voice(music.TITLE_ARP, music.U * 2, chord=True)),
    ],
    "game": [
        (2, None, 0, voice(music.GAME_BASS, 8)),
        (1, instrument("50", 0x9A, 0x89, 6), 0, voice(music.GAME_HIGH, 8)),
    ],
}

# ---------------------------------------------------------------- sound effects
# The C64 effects (src/main.asm, sfx_*_t): a start frequency, a change per frame, ADSR, a length
# and a waveform. Here each becomes a list of frames: [register 0, period low, period high].
#        name     fhi   delta   ad    sr    frames wave
C64_SFX = [
    ("JUMP",    0x08, 0x0040, 0x00, 0x85, 0x0C, 0x41),
    ("PART",    0x20, 0x0080, 0x00, 0xA6, 0x20, 0x11),
    ("HIT",     0x30, -0x0200, 0x00, 0xA7, 0x14, 0x81),
    ("THUNDER", 0x06, -0x0018, 0x08, 0xFB, 0x60, 0x81),
    ("CANDLE",  0x10, 0x0080, 0x00, 0x95, 0x18, 0x11),
    ("WAIL",    0x28, -0x0040, 0x58, 0xCA, 0x50, 0x21),
    # The C64 bell has no sustain, so it is only a tick there; here it rings out.
    ("BELL",    0x22, 0x0000, 0x09, 0x0C, 0x28, 0x11),
]
NOISE_PERIODS = [4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068]


def sfx_frames(fhi, delta, ad, sr, dur, wave):
    n = int(round(dur * TIME))
    env = envelope(ad, sr, 12 if wave == 0x81 else 10, n)
    out = []
    for k in range(n):
        sid = max(16, fhi * 256 + delta * k / TIME)
        hz = sid * SID_CLOCK / 16777216
        vol = env[k]
        if wave == 0x81:
            idx = max(0, min(15, int(round(21 - 1.5 * math.log2(hz)))))
            out.append([0x30 | vol, idx, 0x08])
        else:
            duty = {0x41: 0x80, 0x11: 0x80, 0x21: 0x40}[wave]
            p = pulse_period(hz)
            out.append([duty | 0x30 | vol, p & 255, p >> 8])
    return out


SFX = [(name, 3 if wave == 0x81 else 0, sfx_frames(fhi, d, ad, sr, dur, wave))
       for name, fhi, d, ad, sr, dur, wave in C64_SFX]


def ca65(label, values, per=16):
    values = list(values)
    lines = [f"{label}:"]
    for i in range(0, len(values), per):
        lines.append("  .byte " + ",".join(f"${v & 255:02X}" for v in values[i:i + per]))
    return "\n".join(lines) + "\n"


def asm():
    """Returns (constants, data) as ca65 source."""
    const, data = [], []
    assert len(instruments) * ENV_LEN <= 256, "the player indexes envelopes with one byte"
    data.append(ca65("pulse_lo", [p & 255 for p in PULSE_TABLE]))
    data.append(ca65("pulse_hi", [p >> 8 for p in PULSE_TABLE]))
    data.append(ca65("tri_lo", [p & 255 for p in TRI_TABLE]))
    data.append(ca65("tri_hi", [p >> 8 for p in TRI_TABLE]))
    data.append(ca65("inst_duty", [d for d, _ in instruments] or [0]))
    data.append(ca65("inst_env", [v for _, e in instruments for v in e] or [0]))
    const.append(f"ENV_LEN = {ENV_LEN}\n")
    names = list(SONGS)
    for s in names:
        for v, (_, _, _, d) in enumerate(SONGS[s]):
            data.append(ca65(f"song_{s}_{v}", d))
    for field in ("chan", "inst", "arp", "lo", "hi"):
        vals = []
        for s in names:
            vs = SONGS[s] + [None] * (3 - len(SONGS[s]))
            for v, x in enumerate(vs):
                if x is None:
                    vals.append({"chan": "$FF"}.get(field, "0"))
                    continue
                ch, inst, arp, _ = x
                vals.append({"chan": str(ch), "inst": str(inst if inst is not None else 0), "arp": str(arp),
                             "lo": f"<song_{s}_{v}", "hi": f">song_{s}_{v}"}[field])
        data.append(f"song_{field}: .byte " + ",".join(vals) + "\n")
    for i, s in enumerate(names):
        const.append(f"SONG_{s.upper()} = {i}\n")
    for i, (name, ch, frames) in enumerate(SFX):
        const.append(f"SFX_{name} = {i}\n")
        data.append(ca65(f"sfx_{name.lower()}", [b for f in frames for b in f] + [0xFF]))
    data.append("sfx_chan: .byte " + ",".join(str(ch) for _, ch, _ in SFX) + "\n")
    data.append("sfx_lo: .byte " + ",".join(f"<sfx_{n.lower()}" for n, _, _ in SFX) + "\n")
    data.append("sfx_hi: .byte " + ",".join(f">sfx_{n.lower()}" for n, _, _ in SFX) + "\n")
    return "".join(const), "".join(data)


if __name__ == "__main__":
    c, d = asm()
    print(c)
    print(f"{len(d)} chars of data; {sum(len(f) for _, _, f in SFX)} effect frames")
