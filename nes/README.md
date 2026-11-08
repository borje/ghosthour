# Ghost Hour for the NES

A port of the Commodore 64 game in the parent folder to the 8-bit NES, in 6502 assembly (ca65).
The art is shared: tiles, sprites, font and room settings come from `../tools/`, and
`tools/build_assets.py` converts them to NES formats.

**Status: complete.** The whole game: the title screen with its lightning, the story, the 13
rooms in the dark with your candle, ghosts, bats and werewolves, candles and clock parts, Brooke,
the clock, music and sound, and the end screens. Find the four clock parts, rescue Brooke for the
winding key, and bring them all to the clock in the Great Hall.

## Playing

A built ROM is in [`../play/ghosthour.nes`](../play/ghosthour.nes), for any NES emulator. To build and run it here:

    ./run.sh        # builds if needed, opens FCEUX

| Action                        | NES pad     | FCEUX default keys |
|-------------------------------|-------------|--------------------|
| Walk                          | left, right | arrow keys         |
| Jump                          | A or up     | F or up arrow      |
| Climb                         | up, down    | arrow keys         |
| Raise the candle (burns wax)  | B           | D                  |
| Start, go on from a screen    | START or A  | Enter or F         |

If the keys differ on your setup, see Options > Gamepad Config in FCEUX.

## Building

Tested on Ubuntu 24.04. Run `../setup.sh` first: the asset tools use the C64 version's Python venv.

    ./setup.sh      # once: cc65 and FCEUX with their libraries into nes/.tools/, no sudo
    make            # checks the map, then builds build/ghosthour.nes
    make clean

The ROM is UNROM (mapper 2): 64 KB PRG in four banks, 8 KB CHR-RAM, NTSC. Bank 0 holds the game's
tiles and room tables, bank 1 the title and the text screens, and the code sits in the fixed bank. FCEUX keeps its settings in
`nes/.tools/fceux-home`, not in your home folder.

## How it is put together

    src/main.s            the game: rooms, physics, candle and lighting, enemies, items, Brooke,
                          the clock, storm, rain, HUD, sprites
    src/sound.s           the music and effects player, run from the NMI
    src/unrom.cfg         ld65 memory map: the four banks
    tools/layouts.py      the 13 rooms re-laid at 16 columns (the NES screen is 256 px wide)
    tools/check_map.py    checks that every room, item and Brooke can be reached, and that you can get back
    tools/build_assets.py tile sets, palettes, room tables and sprites from the C64 sources
    tools/sound.py        the C64 tunes and effects converted for the NES sound chip
    tools/title_nes.py    the C64 title picture converted to NES tiles and palettes
    tools/screens.py      the story, win and lose texts, rewrapped for the NES screen
    tools/colours.py      C64 colours to NES colours
    tools/play.py         runs the ROM in FCEUX without a window, with scripted input, room jumps,
                          screenshots and memory reads

How the lighting works: as on the C64, every room tile has a lit and a dark version, and only the
cells whose state changes are redrawn. The NES can only write video memory during vertical blank, so
the main loop queues the changed cells and the NMI copies them. The queue is capped at what fits in
one vertical blank; anything left over is drawn in the next frame. The indoor tile set holds 98 lit
tiles, 94 dark ones and the 61-tile font (253 of 256); the outdoor set has no dark tiles. They are
copied into CHR-RAM when you go between indoors and outdoors.

## Differences from the C64 version

- **Room width:** the rooms are 16 metatiles wide instead of 20, re-laid by hand (`tools/layouts.py`).
- **Speeds and timers** are scaled from 50 Hz to 60 Hz, so walking, the 36 px jump and the wax
  burning feel the same.
- **Colour:** each 16x16 metatile uses one of 4 background palettes, which matches the C64's wall
  colour, detail colour and per-tile colour. The Terrace needs 5 tile colours, so its windows are white.
- **In the dark** the outlines are drawn in the room's wall colour; the C64 uses one dim blue everywhere.
- **Greys:** the NES has no dark grey, so the stone rooms use mid and light grey.
- **Lightning** turns the whole backdrop white, the HUD included, for a frame or two.
- **Sprites** are one 3-colour layer instead of the C64's ink layer over a fill layer. The hero
  and Brooke draw their white details in the skin colour. Each room sets the two enemy palettes.
  The NES shows at most 8 sprites on a line, so when the hero, the flame, an item and two enemies
  line up, the drawing order alternates every frame and they flicker instead of vanishing.
- **The title picture** is the C64 one, drawn by the same code (`../tools/title.py`) and resized
  from 320 to 256 pixels across, which keeps its shape because NES pixels are wider. It needs about
  500 different tiles, more than one pattern table holds, so the screen switches tables part-way
  down, timed by sprite 0. A few dozen near-identical tiles of speckled grass are merged to fit.
  The 4 palettes are picked by hand, and the "PRESS START" and credit lines are redrawn underneath.
- **Text screens** are rewrapped to the 28 columns a TV shows, so the lines break differently.
- **Sound:** the NES has two square-wave channels, a triangle and noise instead of the SID's three
  voices with filters and envelopes. The bass lines play on the triangle, the melody and the
  in-game drone on the second square, and the effects on the first square and the noise channel.
  The SID's attack, decay and sustain become volume tables per frame. The C64 bell has no sustain,
  so it only ticks there; on the NES it rings out.
- **Controls:** fire is B, and jump is A as well as up.
