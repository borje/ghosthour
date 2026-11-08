; Ghost Hour - NES port. The title, the story, 13 rooms with candle lighting, ghosts, bats,
; werewolves, candles, clock parts, Brooke, the clock, music and sound, and the end screens.
; The game logic is a port of the C64 version (../src/main.asm), with speeds and timers
; rescaled from 50 Hz (PAL C64) to 60 Hz (NTSC NES).
;
; Screen: rows 0-1 empty, rows 2-23 the room (16x11 metatiles of 2x2 tiles), rows 25-27 the HUD.
; The PPU can only be written in vertical blank, so the main loop queues changes in vbuf and the
; NMI copies them. Each frame's queue is limited to what fits in vertical blank (VB_BUDGET).

PPUCTRL   = $2000
PPUMASK   = $2001
PPUSTATUS = $2002
OAMADDR   = $2003
PPUSCROLL = $2005
PPUADDR   = $2006
PPUDATA   = $2007
OAMDMA    = $4014
JOY1      = $4016
APUFRAME  = $4017

OAM       = $0200           ; sprite shadow, sent by DMA every vblank

; controller bits, in the order they are read
J_RIGHT = $01
J_LEFT  = $02
J_DOWN  = $04
J_UP    = $08
J_START = $10
J_SELECT = $20
J_B     = $40
J_A     = $80
J_FIRE  = J_B               ; raise the candle (C64: fire)

; C64: JUMP_V $0300, GRAVITY $20 at 50 Hz. Scaled by 5/6 and (5/6)^2 so the jump
; reaches the same height (36 px) in the same time.
JUMP_V   = $0280
GRAVITY  = $16
MAX_FALL = 3                ; whole pixels per frame (C64: 4)
WAX_FULL = 64
BURN_SLOW = 108             ; frames per unit of wax (C64: 90 at 50 Hz)
BURN_FAST = 10              ; same, with the candle raised (C64: 8)
MSG_TIME = 180
MSG_FOREVER = $FF           ; msg_timer value for a message that stays
NERVE_FULL = 5
RESCUE_TIME = 120           ; frames of raised candle that calm Brooke (C64: 100)
CTRL     = %10001000        ; NMI on, sprites from $1000, background from $0000
MASK_ON  = %00011110        ; show background and sprites, also in the left 8 px
VB_BUDGET = 96              ; vblank work per frame: data bytes + 2 per run
ROOM_ROWS = 22              ; tile rows of the room
ROOM_TOP  = 2               ; tile row where the room starts
; HUD: row 24 a rule, 25 room name and wax, 26 nerve and clock parts, 27 messages
HUD_GAUGE = $2000 + 25*32 + 22
HUD_HEARTS = $2000 + 26*32 + 8
HUD_ICONS = $2000 + 26*32 + 24
HUD_MSG   = $2000 + 27*32 + 2
MSG_LEN   = 28
E_BROOKE  = 3

.include "gen_const.inc"

.segment "HEADER"
    .byte "NES", $1A
    .byte 4                 ; 4 x 16 KB PRG
    .byte 0                 ; CHR-RAM
    .byte $21               ; mapper 2, vertical mirroring
    .byte $00
    .res 8, 0

.segment "ZEROPAGE"
dbg_room:  .res 1           ; test hook: tools/play.py writes room+1 here to jump to a room
nmi_count: .res 1
nmi_skip:  .res 1           ; set while the main code writes the PPU directly
ctrl_shadow: .res 1         ; PPUCTRL, written every vblank
mask_shadow: .res 1
bgcol:     .res 1           ; backdrop colour, written every vblank (lightning)
vb_ready:  .res 1
vbx:       .res 1           ; write position in vbuf
vb_left:   .res 1           ; budget left this frame
vaddr:     .res 2
frame:     .res 1
joy:       .res 1
joy_prev:  .res 1
rng:       .res 1
room:      .res 1
cur_lit:   .res 1           ; moonlit (outdoor) room: no lighting, no wax burnt
set_loaded: .res 1          ; tile set in CHR-RAM: 0 indoor, 1 outdoor
px:        .res 2           ; player x (16 bit, as on the C64), y, sub-pixel y
py:        .res 1
pys:       .res 1
vy:        .res 2           ; 8.8 vertical speed, negative = up
grounded:  .res 1
on_ladder: .res 1
facing:    .res 1           ; 0 right, 1 left
pframe:    .res 1
entry_x:   .res 2
entry_y:   .res 1
tx:        .res 2           ; probe position
ty:        .res 1
tmp:       .res 1
tmp2:      .res 1
tmp3:      .res 1
tmp4:      .res 1
tmp5:      .res 1
ptr:       .res 2
ptr2:      .res 2
; candle and light
wax:       .res 1
wax_tick:  .res 1
flare:     .res 1
flick:     .res 1
radius:    .res 1
cx:        .res 1           ; light centre, in tiles
cy:        .res 1
last_r:    .res 1
last_cx:   .res 1
last_cy:   .res 1
lrow:      .res 1           ; next row light_flush looks at
run_a:     .res 2           ; up to two runs per row: [run_a, run_b)
run_b:     .res 2
lit_l:     .res 1           ; the row's new light span
lit_r:     .res 1
; storm, rain, HUD
flash:     .res 1
thunder_t: .res 2
rain_step: .res 1
msg_ptr:   .res 2
msg_timer: .res 1
msg_dirty: .res 1
hud_dirty: .res 1
; the player's state, the clock, Brooke
nerve:     .res 1
invuln:    .res 1           ; frames of safety after a scare
parts:     .res 1           ; clock parts: bits 0-3 cog, spring, pendulum, key
game_over: .res 1           ; 1 the clock strikes, 2 fainted
red_flash: .res 1
clock_cd:  .res 1
rescued:   .res 1
rescue_t:  .res 1
brooke_said: .res 1
dark_tick: .res 1
all_lit:   .res 1           ; the ending: every light in the room is on
item_type: .res 1           ; this room's item, $FF none
item_x:    .res 2
item_y:    .res 1
; sprite drawing
oam_i:     .res 1
ox:        .res 2
oy:        .res 1
oattr:     .res 1
ofr:       .res 1
count:     .res 1
idle_n:    .res 1

.segment "BSS"
vbuf:      .res 256         ; queued PPU writes: [length, address hi, address lo, data...], 0 ends
LITBUF:    .res ROOM_ROWS*32 ; the room's tiles as they look when lit
MAP:       .res 176         ; the room's metatiles
CUR_L:     .res ROOM_ROWS   ; light span on screen, per row
CUR_R:     .res ROOM_ROWS
NEW_L:     .res ROOM_ROWS   ; light span wanted, per row
NEW_R:     .res ROOM_ROWS
hud_buf:   .res 17          ; wax gauge (8), hearts (5), clock parts (4)
E_TYPE:    .res 2           ; the room's two enemies: 0 ghost, 1 bat, 2 wolf, 3 Brooke, $FF none
E_X:       .res 2
E_XH:      .res 2
E_Y:       .res 2
E_DIR:     .res 2
E_T:       .res 2
E_FLEE:    .res 2
E_HOME:    .res 2
E_DRAWY:   .res 2
ITEM_GONE: .res NUM_ROOMS

; ---------------------------------------------------------------------------
.segment "BANK0"
chr_in:    .incbin "chr_in.bin"
chr_out:   .incbin "chr_out.bin"
chr_spr:   .incbin "chr_spr.bin"
.include "gen_bank0.inc"

.segment "BANK1"
title_chr: .incbin "title_chr0.bin"   ; both pattern tables: the top and the bottom of the picture
           .incbin "title_chr1.bin"
title_nam: .incbin "title.nam"
.include "gen_bank1.inc"

; ---------------------------------------------------------------------------
.segment "RODATA"
.include "gen_data.inc"

; UNROM has bus conflicts: the bank number is written over a ROM byte holding the same value
bank_table: .byte 0, 1, 2, 3
; title lightning, played from the end (C64: light blue twice, sky, white, light blue)
title_flash: .byte TITLE_SKY, $21, $30, TITLE_SKY, $21, $21

; where each of the 9 hero tiles goes, relative to the sprite's top left
part_dx:   .byte 0, 8, 16, 0, 8, 16, 0, 8, 16
part_dxf:  .byte 16, 8, 0, 16, 8, 0, 16, 8, 0
part_dy:   .byte 0, 0, 0, 8, 8, 8, 16, 16, 16
run_cycle: .byte 1, 2, 3, 2
part_bits: .byte 1, 2, 4, 8
enemy_frame: .byte F_GHOST1, F_BAT1, F_WOLF1, F_BROOKE1
bob_table: .byte 0, 1, 2, 3, 3, 3, 2, 1, 0, $FF, $FE, $FD, $FD, $FD, $FE, $FF
bat_wave:  .byte 0, 3, 6, 9, 11, 13, 15, 16, 16, 16, 15, 13, 11, 9, 6, 3
           .byte 0, $FD, $FA, $F7, $F5, $F3, $F1, $F0, $F0, $F0, $F1, $F3, $F5, $F7, $FA, $FD
flash_seq: .byte $0F, $30, $30, $0F, $0F, $30, $10, $30   ; C64: 0,1,1,0,0,1,15,1

; per room row: name table address, and the row in LITBUF
.define ROWADDR(r) ($2000 + (r + ROOM_TOP) * 32)
row_vhi:   .repeat ROOM_ROWS, r
             .byte >ROWADDR(r)
           .endrepeat
row_vlo:   .repeat ROOM_ROWS, r
             .byte <ROWADDR(r)
           .endrepeat
row_lbhi:  .repeat ROOM_ROWS, r
             .byte >(LITBUF + r * 32)
           .endrepeat
row_lblo:  .repeat ROOM_ROWS, r
             .byte <(LITBUF + r * 32)
           .endrepeat

; ---------------------------------------------------------------------------
.segment "CODE"

.proc reset
    sei
    cld
    ldx #$40
    stx APUFRAME            ; no APU frame IRQ
    ldx #$FF
    txs
    inx
    stx PPUCTRL
    stx PPUMASK
    stx $4010
    bit PPUSTATUS
:   bit PPUSTATUS           ; first vblank: the PPU is warming up
    bpl :-
    lda #0
    tax
:   sta $00,x
    sta $0100,x
    sta $0300,x
    sta $0400,x
    sta $0500,x
    sta $0600,x
    sta $0700,x
    inx
    bne :-
    lda #$FF
:   sta OAM,x               ; all sprites off screen
    inx
    bne :-
:   bit PPUSTATUS           ; second vblank: the PPU is ready
    bpl :-

    lda #0                  ; bank 0 at $8000
    jsr set_bank
    jsr sound_init
    lda #$0F
    sta bgcol
    lda #$A7
    sta rng
    lda #1
    sta nmi_skip            ; the screen is off: the NMI only counts and plays the sound
    lda #CTRL
    sta ctrl_shadow
    sta PPUCTRL
    jsr title_screen
    lda #<page_story
    ldx #>page_story
    jsr text_screen
    ; fall through
.endproc

.proc new_game
    jsr screen_off
    lda #$10                ; sprite tiles into CHR-RAM at $1000 (the title used them)
    sta PPUADDR
    lda #0
    sta PPUADDR
    lda #<chr_spr
    sta ptr
    lda #>chr_spr
    sta ptr+1
    ldx #16
    jsr copy_pages
    lda #WAX_FULL
    sta wax
    lda #NERVE_FULL
    sta nerve
    lda #<300
    sta thunder_t
    lda #>300
    sta thunder_t+1
    lda #START_ROOM
    sta room
    lda #<START_X
    sta px
    lda #>START_X
    sta px+1
    lda #START_Y
    sta py
    lda #CTRL
    sta ctrl_shadow
    jsr enter_room
    lda #SONG_GAME
    jsr music_start
    lda #<msg_start
    ldx #>msg_start
    jsr show_message
    jsr player_anim
    jsr draw_sprites
    ; fall through
.endproc

.proc main_loop
    jsr wait_nmi            ; last frame's queue has been written
    jsr vb_begin
    jsr read_joy
    lda dbg_room
    beq :+
    sec
    sbc #1
    sta room
    lda #0
    sta dbg_room
    jsr enter_room
:   jsr candle_update
    jsr player_update
    jsr enemies_update
    jsr item_update
    jsr clock_check
    jsr storm_update
    jsr hud_update
    jsr rain_update
    jsr light_update
    jsr light_flush
    jsr draw_sprites
    jsr vb_end
    inc frame
    lda game_over
    bne ending
    jmp main_loop
.endproc

; The clock strikes twelve (game_over 1), or you faint (2); then the end screen, and the title.
.proc ending
    cmp #1
    beq win
    lda #SFX_HIT            ; a last scream
    jsr sfx_play
    jsr music_stop
    lda #2                  ; the red flash of the last scare, then dark
    jsr idle_frames
    lda #0
    sta red_flash
    lda #$0F
    sta bgcol
    lda #58
    jsr idle_frames
    lda #<page_lose
    ldx #>page_lose
    jsr text_screen
    jmp reset
win:
    ; every light in the room comes on, and the bell tolls twelve times
    jsr music_stop
    lda #$FF
    sta E_TYPE
    sta E_TYPE+1
    sta item_type
    lda #1
    sta all_lit
    ldx #ROOM_ROWS-1
:   lda #0
    sta NEW_L,x
    lda #32
    sta NEW_R,x
    dex
    bpl :-
    lda #<msg_win
    ldx #>msg_win
    jsr show_message
    lda #12
    sta count
bell:
    lda #SFX_BELL
    jsr sfx_play
    lda #$30
    sta bgcol
    lda #2
    jsr idle_frames
    lda #$0F
    sta bgcol
    lda #55
    jsr idle_frames
    dec count
    bne bell
    lda #SONG_TITLE
    jsr music_start
    lda #<page_win
    ldx #>page_win
    jsr text_screen
    jmp reset
.endproc

; A frames with nothing moving: the screen, the HUD and the sprites keep up
.proc idle_frames
    sta idle_n
:   jsr wait_nmi
    jsr vb_begin
    jsr read_joy
    jsr hud_update
    jsr light_flush
    jsr draw_sprites
    jsr vb_end
    inc frame
    dec idle_n
    bne :-
    rts
.endproc

; X pages from (ptr) to PPUDATA
.proc copy_pages
    ldy #0
:   lda (ptr),y
    sta PPUDATA
    iny
    bne :-
    inc ptr+1
    dex
    bne :-
    rts
.endproc

; X bytes of A to PPUDATA
.proc fill_ppu
:   sta PPUDATA
    dex
    bne :-
    rts
.endproc

.proc nmi
    pha
    txa
    pha
    tya
    pha
    lda nmi_skip
    bne done
    lda #0
    sta OAMADDR
    lda #>OAM
    sta OAMDMA
    lda vb_ready
    beq novb
    ldx #0
run:
    ldy vbuf,x
    beq vbdone
    lda vbuf+1,x
    sta PPUADDR
    lda vbuf+2,x
    sta PPUADDR
    inx
    inx
    inx
:   lda vbuf,x
    sta PPUDATA
    inx
    dey
    bne :-
    jmp run
vbdone:
    lda #0
    sta vb_ready
novb:
    lda #$3F                ; backdrop: black, or lightning
    sta PPUADDR
    lda #0
    sta PPUADDR
    lda bgcol
    sta PPUDATA
    lda #0
    sta PPUSCROLL
    sta PPUSCROLL
    lda ctrl_shadow
    sta PPUCTRL
    lda mask_shadow
    sta PPUMASK
done:
    inc nmi_count
    jsr sound_tick          ; music and effects keep time even while a room is drawn
    pla
    tay
    pla
    tax
    pla
    rti
.endproc

.proc irq
    rti
.endproc

.proc wait_nmi
    lda nmi_count
:   cmp nmi_count
    beq :-
    rts
.endproc

; ---- screens -----------------------------------------------------------------
; A = bank at $8000. Keeps A.
.proc set_bank
    tax
    sta bank_table,x
    rts
.endproc

; screen off now; the NMI leaves the PPU alone until screen_on
.proc screen_off
    lda #1
    sta nmi_skip
    lda #0
    sta PPUMASK
    sta mask_shadow
    rts
.endproc

; the next NMI turns the screen on
.proc screen_on
    lda #MASK_ON
    sta mask_shadow
    lda #0
    sta vb_ready
    sta nmi_skip
    rts
.endproc

; A = tile set (0 indoor, 1 outdoor) into the background half of CHR-RAM, unless it is there
; already. Screen off, bank 0.
.proc load_tiles
    cmp set_loaded
    beq out
    sta set_loaded
    tay
    lda #0
    sta rain_step
    sta PPUADDR
    sta PPUADDR
    lda #<chr_in
    ldx #>chr_in
    cpy #0
    beq :+
    lda #<chr_out
    ldx #>chr_out
:   sta ptr
    stx ptr+1
    ldx #16
    jsr copy_pages
out:
    rts
.endproc

; only sprite 0, for the title's split
.proc clear_oam
    ldx #0
    lda #$FF
:   sta OAM,x
    inx
    bne :-
    rts
.endproc

; The title: the picture uses both pattern tables. Sprite 0 sits behind the picture just
; above the split; when the PPU draws it, the rest of the screen switches to the tiles at $1000.
.proc title_screen
    jsr screen_off
    lda #1
    jsr set_bank
    lda #0
    sta PPUADDR
    sta PPUADDR
    lda #<title_chr
    sta ptr
    lda #>title_chr
    sta ptr+1
    ldx #32                 ; 8 KB: both tables
    jsr copy_pages
    lda #$20
    sta PPUADDR
    lda #0
    sta PPUADDR
    ldx #4                  ; name table and attributes follow the tiles
    jsr copy_pages
    lda #$3F
    sta PPUADDR
    lda #0
    sta PPUADDR
    ldx #0
:   lda title_pal,x
    sta PPUDATA
    inx
    cpx #16
    bne :-
    lda #0
    jsr set_bank
    lda #$FF
    sta set_loaded          ; the game's tiles are gone
    jsr clear_oam
    lda #TITLE_S0_Y - 1
    sta OAM
    lda #TITLE_S0_TILE
    sta OAM+1
    lda #$20                ; behind the background
    sta OAM+2
    lda #TITLE_S0_X
    sta OAM+3
    lda #TITLE_SKY
    sta bgcol
    lda #%10000000          ; NMI on; sprites and the top of the picture from $0000
    sta ctrl_shadow
    lda #SONG_TITLE
    jsr music_start
    lda #120
    sta count
    lda #0
    sta flash
    jsr screen_on
    jsr wait_nmi
loop:
    jsr wait_nmi
    ; wait for last frame's sprite 0 hit to clear, then for this frame's (with a way out)
    ldx #0
:   bit PPUSTATUS
    bvc :+
    dex
    bne :-
:   ldx #0
    ldy #8
:   bit PPUSTATUS
    bvs hit
    dex
    bne :-
    dey
    bne :-
hit:
    lda #%10010000          ; the bottom of the picture from $1000
    sta PPUCTRL
    jsr read_joy
    jsr random
    ; lightning in the sky now and then
    lda flash
    beq :+
    dec flash
    ldx flash
    lda title_flash,x
    sta bgcol
    jmp keys
:   dec count
    bne keys
    lda rng
    ora #$40
    sta count
    lda #6
    sta flash
keys:
    lda joy_prev
    eor #$FF
    and joy
    and #J_START|J_A
    beq loop
    lda #TITLE_SKY
    sta bgcol
    rts
.endproc

; A/X = a text page in bank 1 (tools/screens.py): 16 palette bytes, 64 attribute bytes, then
; lines of (address hi, address lo, text, 0), ended by $FF. Waits for START or A.
.proc text_screen
    sta ptr2
    stx ptr2+1
    jsr screen_off
    lda #0                  ; the font is in the indoor tiles
    jsr set_bank
    lda #0
    jsr load_tiles
    lda #1
    jsr set_bank
    lda #$20
    sta PPUADDR
    lda #0
    sta PPUADDR
    lda #BLANK
    ldx #0
    ldy #4
:   sta PPUDATA             ; 1024 blanks, the attributes come after
    dex
    bne :-
    dey
    bne :-
    lda #$23
    sta PPUADDR
    lda #$C0
    sta PPUADDR
    ldy #16
:   lda (ptr2),y
    sta PPUDATA
    iny
    cpy #16+64
    bne :-
    lda #$3F
    sta PPUADDR
    lda #0
    sta PPUADDR
    ldy #0
:   lda (ptr2),y
    sta PPUDATA
    iny
    cpy #16
    bne :-
    lda #16+64
    jsr advance
line:
    ldy #0
    lda (ptr2),y
    cmp #$FF
    beq done
    sta PPUADDR
    iny
    lda (ptr2),y
    sta PPUADDR
    iny
:   lda (ptr2),y
    beq :+
    sta PPUDATA
    iny
    bne :-
:   iny
    tya
    jsr advance
    jmp line
done:
    lda #0
    jsr set_bank
    jsr clear_oam
    lda #$0F
    sta bgcol
    lda #CTRL
    sta ctrl_shadow
    jsr screen_on
:   jsr wait_nmi            ; wait for START or A to be pressed (not still held)
    jsr read_joy
    jsr random
    lda joy_prev
    eor #$FF
    and joy
    and #J_START|J_A
    beq :-
    rts
advance:
    clc
    adc ptr2
    sta ptr2
    bcc :+
    inc ptr2+1
:   rts
.endproc

; ---- the vblank queue --------------------------------------------------------
.proc vb_begin
    lda #0
    sta vbx
    lda #VB_BUDGET
    sta vb_left
    rts
.endproc

.proc vb_end
    ldx vbx
    lda #0
    sta vbuf,x
    lda #1
    sta vb_ready
    rts
.endproc

; A = cost (bytes + 2 per run): carry set if it still fits this frame
.proc vb_fits
    cmp vb_left
    beq yes
    bcc yes
    clc
    rts
yes:
    sec
    rts
.endproc

; start a run of A bytes at vaddr; returns X = where the data goes. The caller stores X in vbx.
.proc vb_head
    sta tmp
    clc
    adc #2
    eor #$FF
    sec
    adc vb_left
    sta vb_left
    ldx vbx
    lda tmp
    sta vbuf,x
    lda vaddr+1
    sta vbuf+1,x
    lda vaddr
    sta vbuf+2,x
    inx
    inx
    inx
    rts
.endproc

.proc read_joy
    lda joy
    sta joy_prev
    lda #1
    sta JOY1
    sta joy                 ; a 1 that falls out after 8 reads
    lda #0
    sta JOY1
:   lda JOY1
    lsr
    rol joy
    bcc :-
    rts
.endproc

.proc random
    lda rng
    asl
    bcc :+
    eor #$1D
:   sta rng
    rts
.endproc

; ptr += room * A
.proc add_room_times
    ldx room
    beq done
    sta tmp
:   lda ptr
    clc
    adc tmp
    sta ptr
    bcc :+
    inc ptr+1
:   dex
    bne :--
done:
    rts
.endproc

; ---- rooms -------------------------------------------------------------------
; Draws the whole room with the screen off. Called with the player already placed.
.proc enter_room
    lda #1
    sta nmi_skip            ; the NMI keeps its hands off the PPU
    lda #0
    sta PPUMASK
    ldx room
    lda room_lit,x
    sta cur_lit
    jsr load_tiles
    ; the room's metatiles
    lda #<room_maps
    sta ptr
    lda #>room_maps
    sta ptr+1
    lda #176
    jsr add_room_times
    ldy #175
:   lda (ptr),y
    sta MAP,y
    dey
    cpy #$FF
    bne :-
    ; expand them into LITBUF: metatile (row r, col c) -> tiles at (2r, 2c)
    lda #<LITBUF
    sta ptr
    lda #>LITBUF
    sta ptr+1
    ldx #0                  ; MAP index
mrow:
    ldy #0                  ; column in tiles
mcol:
    stx tmp
    lda MAP,x
    tax
    lda mt_tl,x
    sta (ptr),y
    iny
    lda mt_tr,x
    sta (ptr),y
    tya
    clc
    adc #32
    tay
    lda mt_br,x
    sta (ptr),y
    dey
    lda mt_bl,x
    sta (ptr),y
    tya
    sec
    sbc #30                 ; from the bottom-left tile to the next metatile's top-left
    tay
    ldx tmp
    inx
    cpy #32
    bne mcol
    lda ptr
    clc
    adc #64
    sta ptr
    bcc :+
    inc ptr+1
:   cpx #176
    bne mrow

    ; name table: two empty rows, the room, the HUD
    lda #$20
    sta PPUADDR
    lda #0
    sta PPUADDR
    lda #BLANK
    ldx #64
    jsr fill_ppu
    lda #<LITBUF
    sta ptr
    lda #>LITBUF
    sta ptr+1
    ldx #ROOM_ROWS
nrow:
    ldy #0
:   lda (ptr),y
    ldx cur_lit
    bne :+
    tax                     ; dark rooms start dark
    lda dark_in,x
:   sta PPUDATA
    iny
    cpy #32
    bne :--
    lda ptr
    clc
    adc #32
    sta ptr
    bcc :+
    inc ptr+1
:   lda ptr                 ; ptr past the end of LITBUF?
    cmp #<(LITBUF + ROOM_ROWS*32)
    bne nrow
    lda ptr+1
    cmp #>(LITBUF + ROOM_ROWS*32)
    bne nrow
    ; HUD: row 24 a rule; 25 name and wax; 26 nerve and clock parts; 27 messages; 28-29 empty
    jsr spawn_enemies       ; before the sprite palettes, which depend on them
    jsr make_hud
    lda #BLANK
    ldx #1
    jsr fill_ppu
    lda #T_RULE
    ldx #30
    jsr fill_ppu
    lda #BLANK
    ldx #3
    jsr fill_ppu
    lda #<room_names
    sta ptr
    lda #>room_names
    sta ptr+1
    lda #10
    jsr add_room_times
    ldy #0
:   lda (ptr),y
    sta PPUDATA
    iny
    cpy #10
    bne :-
    lda #BLANK
    ldx #6
    jsr fill_ppu
    lda #<txt_wax
    ldx #>txt_wax
    jsr put_text
    ldx #0
    ldy #8
    jsr put_hud
    lda #BLANK
    ldx #4
    jsr fill_ppu
    lda #<txt_nerve
    ldx #>txt_nerve
    jsr put_text
    ldx #8
    ldy #5
    jsr put_hud
    lda #BLANK
    ldx #5
    jsr fill_ppu
    lda #<txt_clock
    ldx #>txt_clock
    jsr put_text
    ldx #13
    ldy #4
    jsr put_hud
    lda #BLANK
    ldx #4+96
    jsr fill_ppu
    ; attributes
    lda #<room_attrs
    sta ptr
    lda #>room_attrs
    sta ptr+1
    lda #64
    jsr add_room_times
    ldy #0
:   lda (ptr),y
    sta PPUDATA
    iny
    cpy #64
    bne :-
    ; palettes
    lda #$3F
    sta PPUADDR
    lda #0
    sta PPUADDR
    lda #<room_pals
    sta ptr
    lda #>room_pals
    sta ptr+1
    lda #16
    jsr add_room_times
    ldy #0
:   lda (ptr),y
    sta PPUDATA
    iny
    cpy #16
    bne :-
    ldy #0
:   lda spr_palettes,y      ; the hero, and flame and items
    sta PPUDATA
    iny
    cpy #8
    bne :-
    ldx #0                  ; the two enemies
    jsr put_enemy_pal
    ldx #1
    jsr put_enemy_pal

    ; light: everything dark, nothing queued
    ldx #ROOM_ROWS-1
    lda #0
:   sta CUR_L,x
    sta CUR_R,x
    sta NEW_L,x
    sta NEW_R,x
    dex
    bpl :-
    sta lrow
    sta msg_timer
    lda #$FF
    sta last_cx
    ; remember the way in, for falls
    lda px
    sta entry_x
    lda px+1
    sta entry_x+1
    lda py
    sta entry_y
    jsr vb_begin
    lda #MASK_ON
    sta mask_shadow
    lda #0
    sta nmi_skip            ; the next NMI turns the screen back on
    sta brooke_said
    lda #1
    sta msg_dirty           ; the message row was drawn empty
    ; this room's item
    ldx room
    lda #$FF
    sta item_type
    lda ITEM_GONE,x
    bne :+
    lda room_item,x
    sta item_type
    lda room_item_x,x
    sta item_x
    lda #0
    sta item_x+1
    lda room_item_y,x
    sta item_y
:   ; a clock part here?
    lda item_type
    cmp #4
    bcs :+
    lda #<msg_glint
    ldx #>msg_glint
    jmp show_message
:   ; Brooke calls out
    lda E_TYPE+1
    cmp #E_BROOKE
    bne quiet
    lda rescued
    bne :+
    lda #<msg_help
    ldx #>msg_help
    jmp show_message
:   lda #<msg_waits
    ldx #>msg_waits
    jmp show_message
quiet:
    rts
.endproc

; text at A/X (0 ends) to PPUDATA
.proc put_text
    sta ptr2
    stx ptr2+1
    ldy #0
:   lda (ptr2),y
    beq :+
    sta PPUDATA
    iny
    bne :-
:   rts
.endproc

; Y bytes of hud_buf from X to PPUDATA
.proc put_hud
:   lda hud_buf,x
    sta PPUDATA
    inx
    dey
    bne :-
    rts
.endproc

; sprite palette 2+X for enemy X: transparent, then its 3 colours
.proc put_enemy_pal
    lda #$0F
    sta PPUDATA
    lda E_TYPE,x
    cmp #$FF
    bne :+
    lda #0
:   sta tmp
    asl
    adc tmp                 ; type * 3
    tay
    ldx #3
:   lda enemy_pals,y
    sta PPUDATA
    iny
    dex
    bne :-
    rts
.endproc

; ---- tile lookups ------------------------------------------------------------
; A = tile flags at (tx, ty) in room pixels; 0 outside the room
.proc probe
    lda tx+1
    bne off
    lda ty
    cmp #176
    bcs off
    and #$F0
    sta tmp
    lda tx
    lsr
    lsr
    lsr
    lsr
    ora tmp
    tay
    lda MAP,y
    tay
    lda mt_flags,y
    rts
off:
    lda #0
    rts
.endproc

; tx = px + A
.proc set_tx
    clc
    adc px
    sta tx
    lda px+1
    adc #0
    sta tx+1
    rts
.endproc

; ---- the player --------------------------------------------------------------
.proc player_update
    lda on_ladder
    beq walk
    jmp ladder_update
walk:
    ; 1.25 px per frame (C64: 1.5 at 50 Hz)
    lda frame
    and #3
    bne :+
    lda #2
    bne :++
:   lda #1
:   sta tmp4
    lda joy
    and #J_LEFT
    beq noleft
    lda #1
    sta facing
lstep:
    jsr try_left
    dec tmp4
    bne lstep
    jmp moved
noleft:
    lda joy
    and #J_RIGHT
    beq moved
    lda #0
    sta facing
rstep:
    jsr try_right
    dec tmp4
    bne rstep
moved:
    jsr check_side_exits
    ; standing on something?
    lda vy+1
    bmi air
    jsr feet_on_ground
    bcc air
    lda #1
    sta grounded
    lda #0
    sta vy
    sta vy+1
    sta pys
    ; up: ladder.  up or A, newly pressed: jump.  down: ladder below
    lda joy
    and #J_UP
    beq nograb
    jsr ladder_here
    bcs grab
nograb:
    lda joy_prev
    eor #$FF
    and joy
    and #J_UP|J_A
    beq nojump
    lda #<($10000-JUMP_V)
    sta vy
    lda #>($10000-JUMP_V)
    sta vy+1
    lda #0
    sta grounded
    lda #SFX_JUMP
    jsr sfx_play
    jmp air2
nojump:
    lda joy
    and #J_DOWN
    beq done
    jsr ladder_below
    bcs grab
done:
    jmp player_anim
grab:
    jmp grab_ladder
air:
    lda #0
    sta grounded
    ; catching a ladder in mid-air
    lda joy
    and #J_UP|J_DOWN
    beq air2
    jsr ladder_here
    bcs grab
air2:
    ; gravity
    lda vy
    clc
    adc #GRAVITY
    sta vy
    lda vy+1
    adc #0
    sta vy+1
    bmi :+
    cmp #MAX_FALL
    bcc :+
    lda #MAX_FALL
    sta vy+1
    lda #0
    sta vy
:   ; integrate
    lda pys
    clc
    adc vy
    sta pys
    lda #0
    adc vy+1
    sta tmp4                ; signed whole pixels this frame
    beq vdone
    bmi rise
fall:
    jsr feet_on_ground
    bcs land
    inc py
    dec tmp4
    bne fall
    jmp vdone
land:
    lda #0
    sta vy
    sta vy+1
    sta pys
    lda #1
    sta grounded
    jmp vdone
rise:
    lda #7
    jsr set_tx
    lda py
    clc
    adc #1
    sta ty
    jsr probe
    and #TF_SOLID
    bne bump
    lda #16
    jsr set_tx
    jsr probe
    and #TF_SOLID
    bne bump
    dec py
    inc tmp4
    bne rise
    jmp vdone
bump:
    lda #0
    sta vy
    sta vy+1
vdone:
    jsr check_vert_exits
    jmp player_anim
.endproc

; carry set if the player's feet rest on something at this exact y
.proc feet_on_ground
    lda py
    clc
    adc #21
    sta ty
    lda #7
    jsr set_tx
    jsr probe
    jsr eval
    bcs yes
    lda #16
    jsr set_tx
    jsr probe
eval:
    sta tmp
    and #TF_SOLID
    bne yes
    lda tmp
    and #TF_PLATFORM|TF_LADDER
    beq no
    lda ty                  ; one-way: only the top pixel row of a tile counts
    and #15
    bne no
yes:
    sec
    rts
no:
    clc
    rts
.endproc

.proc try_left
    lda px
    sec
    sbc #1
    sta tmp2
    lda px+1
    sbc #0
    sta tmp3
    ; left edge of the body
    lda tmp2
    clc
    adc #6
    sta tx
    lda tmp3
    adc #0
    sta tx+1
    jsr body_blocked
    bne no
    lda tmp2
    sta px
    lda tmp3
    sta px+1
no:
    rts
.endproc

.proc try_right
    lda px
    clc
    adc #1
    sta tmp2
    lda px+1
    adc #0
    sta tmp3
    lda tmp2
    clc
    adc #17
    sta tx
    lda tmp3
    adc #0
    sta tx+1
    jsr body_blocked
    bne no
    lda tmp2
    sta px
    lda tmp3
    sta px+1
no:
    rts
.endproc

; in: tx; out: Z clear if a solid tile touches the body at that x
.proc body_blocked
    lda py
    clc
    adc #3
    sta ty
    jsr probe
    and #TF_SOLID
    bne out
    lda py
    clc
    adc #19
    sta ty
    jsr probe
    and #TF_SOLID
out:
    rts
.endproc

; through a side of the room (C64: 320 wide, exits at 306 and -10)
.proc check_side_exits
    lda px+1
    bmi left                ; negative x
    beq :+
    jmp right               ; 256 and up
:   lda px
    cmp #242
    bcc none
right:
    ldx room
    lda room_exit_r,x
    cmp #$FF
    beq stopr
    sta room
    lda #<($10000-8)
    sta px
    lda #>($10000-8)
    sta px+1
    jmp enter_room
stopr:
    lda #241
    sta px
    lda #0
    sta px+1
    rts
left:
    lda px
    cmp #$F6                ; x < -10
    bcs none
    ldx room
    lda room_exit_l,x
    cmp #$FF
    beq stopl
    sta room
    lda #240
    sta px
    lda #0
    sta px+1
    jmp enter_room
stopl:
    lda #$F6
    sta px
none:
    rts
.endproc

.proc check_vert_exits
    lda py
    cmp #224                ; 224-255 means above the screen
    bcc below
    cmp #244                ; py < -12: through the ceiling
    bcs none
    ldx room
    lda room_exit_u,x
    cmp #$FF
    beq stopu
    sta room
    lda py
    clc
    adc #176
    sta py
    jmp enter_room
stopu:
    lda #244
    sta py
    lda #0
    sta vy
    sta vy+1
    rts
below:
    cmp #170
    bcc none
    ldx room
    lda room_exit_d,x
    cmp #$FF
    beq pit
    sta room
    lda py
    sec
    sbc #176
    sta py
    jmp enter_room
pit:                        ; should not happen: back to the room's entrance
    lda entry_x
    sta px
    lda entry_x+1
    sta px+1
    lda entry_y
    sta py
none:
    rts
.endproc

; carry set when a ladder overlaps the player's middle
.proc ladder_here
    lda #12
    jsr set_tx
    lda py
    clc
    adc #10
    sta ty
    jsr probe
    and #TF_LADDER
    bne yes
    lda py
    clc
    adc #20
    sta ty
    jsr probe
    and #TF_LADDER
    bne yes
    clc
    rts
yes:
    sec
    rts
.endproc

.proc ladder_below
    lda #12
    jsr set_tx
    lda py
    clc
    adc #21
    sta ty
    cmp #176                ; below the last row: the ladder carries on in the next room
    bcs yes
    jsr probe
    and #TF_LADDER
    bne yes
    clc
    rts
yes:
    sec
    rts
.endproc

; centre the player on the ladder column
.proc grab_ladder
    lda #1
    sta on_ladder
    lda #0
    sta vy
    sta vy+1
    sta grounded
    ; px = column*16 - 4 (sprite centre on the tile centre)
    lda px
    clc
    adc #12
    sta tmp
    lda px+1
    adc #0
    sta tmp2
    lda tmp
    and #$F0
    sec
    sbc #4
    sta px
    lda tmp2
    sbc #0
    sta px+1
    jmp player_anim
.endproc

.proc ladder_update
    lda joy
    and #J_LEFT|J_RIGHT
    beq stay
    ; stepping off sideways
    lda #0
    sta on_ladder
    jmp player_anim
stay:
    lda joy
    and #J_UP
    beq noup
    jsr ladder_here
    bcc off
    dec py
    jsr check_vert_exits
    jmp player_anim
noup:
    lda joy
    and #J_DOWN
    beq idle
    ; blocked by the floor?
    jsr feet_on_solid
    bcs off
    jsr ladder_below
    bcc off
    inc py
    jsr check_vert_exits
idle:
    jmp player_anim
off:
    lda #0
    sta on_ladder
    jmp player_anim
.endproc

.proc feet_on_solid
    lda py
    clc
    adc #21
    sta ty
    lda #12
    jsr set_tx
    jsr probe
    and #TF_SOLID
    beq no
    sec
    rts
no:
    clc
    rts
.endproc

; choose the animation frame (same numbering as the C64: 0 stand, 1-3 run, 4 jump, 5-6 climb)
.proc player_anim
    lda on_ladder
    beq :+
    lda py
    lsr
    lsr
    lsr
    and #1
    clc
    adc #5
    sta pframe
    rts
:   lda grounded
    bne :+
    lda #4
    sta pframe
    rts
:   lda joy
    and #J_LEFT|J_RIGHT
    bne :+
    lda #0
    sta pframe
    rts
:   lda frame
    lsr
    lsr
    and #3
    tax
    lda run_cycle,x
    sta pframe
    rts
.endproc

; ---- the candle --------------------------------------------------------------
.proc candle_update
    ; fire held: flare, while there is wax
    lda #0
    sta flare
    lda wax
    beq noflare
    lda joy
    and #J_FIRE
    beq noflare
    lda #1
    sta flare
noflare:
    ; burning
    lda cur_lit
    bne burnt               ; moonlit rooms: the candle is shielded
    inc wax_tick
    lda wax_tick
    ldx flare
    beq :+
    cmp #BURN_FAST
    bcc burnt
    bcs burn
:   cmp #BURN_SLOW
    bcc burnt
burn:
    lda #0
    sta wax_tick
    lda wax
    beq burnt
    dec wax
    bne :+
    lda #<msg_dark
    ldx #>msg_dark
    jsr show_message
:   lda #1
    sta hud_dirty
burnt:
    ; no light at all wears your nerve down
    lda wax
    bne nodark
    lda cur_lit
    bne nodark
    inc dark_tick
    bne nodark
    lda #<msg_snuff
    ldx #>msg_snuff
    jsr show_message
    lda invuln
    bne nodark
    lda #1
    jsr hurt_player
nodark:
    ; radius from wax left
    lda wax
    beq r0
    cmp #9
    bcc r1
    cmp #24
    bcc r2
    cmp #44
    bcc r3
    lda #7
    bne rr
r3: lda #6
    bne rr
r2: lda #5
    bne rr
r1: lda #4
    bne rr
r0: lda #2
rr: sta radius
    ; flicker
    lda frame
    and #7
    bne :+
    jsr random
    and #1
    sta flick
:   lda radius
    clc
    adc flick
    ldx flare
    beq :+
    clc
    adc #2
:   cmp #9
    bcc :+
    lda #8
:   sta radius
    ; centre of the light: the player's chest, in tiles
    lda px
    clc
    adc #12
    sta tmp
    lda px+1
    adc #0
    beq :++
    bmi :+
    lda #31                 ; off the right edge
    bne :+++
:   lda #0                  ; off the left edge
    beq :++
:   lda tmp
    lsr
    lsr
    lsr
:   sta cx
    lda py
    clc
    adc #8
    cmp #224
    bcc :+
    lda #0
:   lsr
    lsr
    lsr
    cmp #ROOM_ROWS
    bcc :+
    lda #ROOM_ROWS-1
:   sta cy
    rts
.endproc

; Works out the light span each row should have, when the light moved or changed size.
.proc light_update
    lda cur_lit
    ora all_lit             ; the ending sets every span itself
    beq :+
    rts
:   lda radius
    cmp last_r
    bne changed
    lda cx
    cmp last_cx
    bne changed
    lda cy
    cmp last_cy
    bne changed
    rts
changed:
    lda radius
    sta last_r
    lda cx
    sta last_cx
    lda cy
    sta last_cy
    ; disc row for this radius: table is radius*9
    lda radius
    asl
    asl
    asl
    adc radius
    sta tmp4
    ldx #0
rowloop:
    txa
    sec
    sbc cy
    bcs :+
    eor #$FF
    adc #1
:   cmp #9
    bcs empty
    clc
    adc tmp4
    tay
    lda disc_table,y
    cmp #$FF
    beq empty
    sta tmp                 ; half width
    lda cx
    sec
    sbc tmp
    bcs :+
    lda #0
:   sta NEW_L,x
    lda cx
    sec
    adc tmp                 ; cx + hw + 1
    cmp #32
    bcc :+
    lda #32
:   sta NEW_R,x
    jmp next
empty:
    lda #0
    sta NEW_L,x
    sta NEW_R,x
next:
    inx
    cpx #ROOM_ROWS
    bne rowloop
    rts
.endproc

; Queues the rows whose light span changed, as far as this frame's budget goes.
; Each row needs at most two runs: the cells that change at its left end and at its right end.
.proc light_flush
    lda cur_lit
    beq :+
    rts
:   lda #ROOM_ROWS
    sta tmp5
loop:
    ldx lrow
    lda NEW_L,x
    cmp CUR_L,x
    bne diff
    lda NEW_R,x
    cmp CUR_R,x
    bne diff
    jmp next
diff:
    lda #0
    sta run_a+1
    sta run_b+1             ; second run empty
    lda CUR_L,x
    cmp CUR_R,x
    bne :+
    lda NEW_L,x             ; was dark: light the new span
    sta run_a
    lda NEW_R,x
    sta run_b
    jmp costs
:   lda NEW_L,x
    cmp NEW_R,x
    bne :+
    lda CUR_L,x             ; goes dark: darken the old span
    sta run_a
    lda CUR_R,x
    sta run_b
    jmp costs
:   lda NEW_L,x             ; overlapping? new L < old R and old L < new R
    cmp CUR_R,x
    bcs apart
    lda CUR_L,x
    cmp NEW_R,x
    bcs apart
    ; left ends: [min, max) of the two
    lda NEW_L,x
    cmp CUR_L,x
    bcc :+
    lda CUR_L,x
    sta run_a
    lda NEW_L,x
    sta run_b
    jmp right_ends
:   sta run_a
    lda CUR_L,x
    sta run_b
right_ends:
    lda NEW_R,x
    cmp CUR_R,x
    bcc :+
    lda CUR_R,x
    sta run_a+1
    lda NEW_R,x
    sta run_b+1
    jmp costs
:   sta run_a+1
    lda CUR_R,x
    sta run_b+1
    jmp costs
apart:
    lda CUR_L,x             ; two separate spans: redraw both
    sta run_a
    lda CUR_R,x
    sta run_b
    lda NEW_L,x
    sta run_a+1
    lda NEW_R,x
    sta run_b+1
costs:
    ; cost = len + 2 for each non-empty run
    lda #0
    sta tmp
    ldy #1
:   lda run_b,y
    sec
    sbc run_a,y
    beq :+
    clc
    adc #2
    adc tmp
    sta tmp
:   dey
    bpl :--
    lda tmp
    jsr vb_fits
    bcs :+
    rts                     ; the rest waits for the next frame
:   ldx lrow
    lda NEW_L,x
    sta lit_l
    lda NEW_R,x
    sta lit_r
    ldy #0
    jsr emit_run
    ldy #1
    jsr emit_run
    ldx lrow
    lda NEW_L,x
    sta CUR_L,x
    lda NEW_R,x
    sta CUR_R,x
next:
    inc lrow
    lda lrow
    cmp #ROOM_ROWS
    bne :+
    lda #0
    sta lrow
:   dec tmp5
    beq :+
    jmp loop
:   rts
.endproc

; queue run Y (0 or 1) of row lrow: each cell lit if inside [lit_l, lit_r), else dark
.proc emit_run
    lda run_b,y
    sec
    sbc run_a,y
    bne :+
    rts
:   sta tmp2                ; length
    lda run_a,y
    sta tmp3                ; first column
    lda run_b,y
    sta tmp4                ; end column
    ldx lrow
    lda row_vlo,x
    clc
    adc tmp3                ; no carry: a row is 32 bytes inside one page
    sta vaddr
    lda row_vhi,x
    sta vaddr+1
    lda row_lblo,x
    sta ptr2
    lda row_lbhi,x
    sta ptr2+1
    lda tmp2
    jsr vb_head
    ldy tmp3
cell:
    lda (ptr2),y
    cpy lit_l
    bcc dark
    cpy lit_r
    bcc lit
dark:
    sty tmp
    tay
    lda dark_in,y
    ldy tmp
lit:
    sta vbuf,x
    inx
    iny
    cpy tmp4
    bne cell
    stx vbx
    rts
.endproc

; ---- storm, rain, HUD ----------------------------------------------------------
.proc storm_update
    jsr storm
    lda red_flash           ; a scare turns the backdrop red for a moment
    beq :+
    dec red_flash
    lda #$16
    sta bgcol
:   rts
.endproc

.proc storm
    lda flash
    beq waiting
    dec flash
    ldx flash
    lda flash_seq,x
    sta bgcol
    rts
waiting:
    lda #$0F
    sta bgcol
    lda thunder_t
    bne :+
    dec thunder_t+1
:   dec thunder_t
    lda thunder_t
    ora thunder_t+1
    bne out
    ; strike! the next one in 5-15 seconds
    lda #7
    sta flash
    lda #SFX_THUNDER
    jsr sfx_play
    jsr random
    sta thunder_t
    and #1
    clc
    adc #1
    sta thunder_t+1
    lda #<msg_boom
    ldx #>msg_boom
    jmp show_message
out:
    rts
.endproc

; outdoors: roll the rain tiles down 2 pixel rows every other frame
.proc rain_update
    lda cur_lit
    beq out
    lda frame
    and #1
    bne out
    lda #4*18
    jsr vb_fits
    bcc out
    lda rain_step
    clc
    adc #1
    and #7
    sta rain_step
    asl                     ; 64 bytes per step
    asl
    asl
    asl
    asl
    asl
    sta tmp5                ; offset into rain_frames (up to 7*64 = 448: see the high byte below)
    lda #<rain_frames
    sta ptr2
    lda #>rain_frames
    sta ptr2+1
    lda rain_step
    lsr
    lsr                     ; steps 4-7 are in the second page
    clc
    adc ptr2+1
    sta ptr2+1
    lda #RAIN_TL
    jsr rain_tile
    lda #RAIN_BL
    jsr rain_tile
    lda #RAIN_TR
    jsr rain_tile
    lda #RAIN_BR
    jsr rain_tile
out:
    rts
.endproc

; queue the 16 bytes at (ptr2)+tmp5 as tile A; advances tmp5
.proc rain_tile
    pha
    lsr
    lsr
    lsr
    lsr
    sta vaddr+1             ; tile * 16
    pla
    asl
    asl
    asl
    asl
    sta vaddr
    lda #16
    jsr vb_head
    ldy tmp5
:   lda (ptr2),y
    sta vbuf,x
    inx
    iny
    tya
    and #15
    bne :-
    sty tmp5
    stx vbx
    rts
.endproc

; A/X = message: shown on the HUD's bottom row for a while
.proc show_message
    sta msg_ptr
    stx msg_ptr+1
    lda #MSG_TIME
    sta msg_timer
    lda #1
    sta msg_dirty
    rts
.endproc

; HUD values into hud_buf: wax gauge (8 tiles, each 0-8 columns full), hearts (5), clock parts (4)
.proc make_hud
    lda wax
    sta tmp
    ldx #0
:   lda tmp
    cmp #8
    bcc :+
    lda #8
:   sta tmp2
    clc
    adc #T_GAUGE
    sta hud_buf,x
    lda tmp
    sec
    sbc tmp2
    sta tmp
    inx
    cpx #8
    bne :--
    ldy #0
:   lda #T_HEART
    cpy nerve
    bcc :+
    lda #T_HEART0
:   sta hud_buf,x
    inx
    iny
    cpy #5
    bne :--
    ldy #0
:   lda parts
    and part_bits,y
    beq :+
    tya
    clc
    adc #T_ICON
    bne :++
:   lda #T_ICON0
:   sta hud_buf,x
    inx
    iny
    cpy #4
    bne :---
    rts
.endproc

; queue hud_buf from X, Y bytes, at vaddr
.proc queue_hud
    sty tmp3
    stx tmp4
    tya
    jsr vb_head
    ldy tmp4
:   lda hud_buf,y
    sta vbuf,x
    inx
    iny
    dec tmp3
    bne :-
    stx vbx
    rts
.endproc

.proc hud_update
    lda hud_dirty
    beq msg
    lda #8+5+4+6
    jsr vb_fits
    bcc msg
    lda #0
    sta hud_dirty
    jsr make_hud
    lda #<HUD_GAUGE
    sta vaddr
    lda #>HUD_GAUGE
    sta vaddr+1
    ldx #0
    ldy #8
    jsr queue_hud
    lda #<HUD_HEARTS
    sta vaddr
    lda #>HUD_HEARTS
    sta vaddr+1
    ldx #8
    ldy #5
    jsr queue_hud
    lda #<HUD_ICONS
    sta vaddr
    lda #>HUD_ICONS
    sta vaddr+1
    ldx #13
    ldy #4
    jsr queue_hud
msg:
    lda msg_timer
    beq :+
    cmp #MSG_FOREVER
    beq :+
    dec msg_timer
    bne :+
    lda #1                  ; time is up: blank the row
    sta msg_dirty
:   lda msg_dirty
    beq out
    lda #MSG_LEN+2
    jsr vb_fits
    bcc out
    lda #0
    sta msg_dirty
    lda #<HUD_MSG
    sta vaddr
    lda #>HUD_MSG
    sta vaddr+1
    lda #MSG_LEN
    jsr vb_head
    ldy #0
    lda msg_timer
    beq blank
:   lda (msg_ptr),y
    beq blank
    sta vbuf,x
    inx
    iny
    bne :-
blank:
    lda #BLANK
:   cpy #MSG_LEN
    beq :+
    sta vbuf,x
    inx
    iny
    bne :-
:   stx vbx
out:
    rts
.endproc

; ---- scares ------------------------------------------------------------------
; A = nerve lost
.proc hurt_player
    sta tmp
    lda invuln
    bne out
    lda #144
    sta invuln
    lda nerve
    sec
    sbc tmp
    bcs :+
    lda #0
:   sta nerve
    bne :+
    lda #2
    sta game_over
:   lda #1
    sta hud_dirty
    lda #2
    sta red_flash
    lda #SFX_HIT
    jsr sfx_play
    lda #<msg_eek
    ldx #>msg_eek
    jmp show_message
out:
    rts
.endproc

; ---- enemies -------------------------------------------------------------------
.proc spawn_enemies
    ldx room
    lda room_e0_type,x
    sta E_TYPE
    lda room_e1_type,x
    sta E_TYPE+1
    lda room_e0_x,x
    sta E_X
    lda room_e1_x,x
    sta E_X+1
    lda #0
    sta E_XH
    sta E_XH+1
    lda room_e0_y,x
    sta E_Y
    sta E_HOME
    lda room_e1_y,x
    sta E_Y+1
    sta E_HOME+1
    ldx #1
loop:
    lda #0
    sta E_FLEE,x
    sta E_DIR,x
    lda rng
    sta E_T,x
    jsr random
    lda E_Y,x
    sta E_DRAWY,x
    lda E_TYPE,x            ; Brooke stays exactly where she is
    cmp #E_BROOKE
    beq far
    ; never spawn on top of the player: half a screen away
    lda E_X,x
    sec
    sbc px
    sta tmp
    lda E_XH,x
    sbc px+1
    bmi neg
    bne far
    lda tmp
    cmp #80
    bcs far
    bcc move
neg:
    cmp #$FF
    bne far
    lda tmp
    cmp #$B0
    bcc far
move:
    lda E_X,x
    eor #$80                ; + 128, wrapping round
    cmp #233
    bcc :+
    lda #232
:   sta E_X,x
far:
    dex
    bpl loop
    ; once rescued she leaves the Bedroom and waits by the clock
    lda rescued
    beq out
    ldx room
    cpx #BROOKE_ROOM
    bne :+
    lda #$FF
    sta E_TYPE+1
    rts
:   cpx #HALL_ROOM
    bne out
    lda #E_BROOKE
    sta E_TYPE+1
    lda #BROOKE_HALL_X
    sta E_X+1
    lda #0
    sta E_XH+1
    lda #BROOKE_HALL_Y
    sta E_Y+1
    sta E_DRAWY+1
out:
    rts
.endproc

.proc enemies_update
    ldx #0
    jsr enemy_one
    ldx #1
    ; fall through
.endproc
.proc enemy_one
    lda E_TYPE,x
    cmp #$FF
    bne :+
    rts
:   inc E_T,x
    cmp #0
    bne :+
    jmp ghost_update
:   cmp #1
    bne :+
    jmp bat_update
:   cmp #2
    bne :+
    jmp wolf_update
:   jmp brooke_update
.endproc

; carry set when the player's raised candle scares this enemy. Uses tmp2.
.proc flare_scares
    lda flare
    beq no
    lda E_X,x
    sec
    sbc px
    sta tmp2
    lda E_XH,x
    sbc px+1
    beq pos
    cmp #$FF
    bne no
    lda tmp2
    eor #$FF
    clc
    adc #1
    sta tmp2
    beq no
pos:
    lda tmp2
    cmp #64
    bcs no
    lda E_Y,x
    sec
    sbc py
    bcs :+
    eor #$FF
    adc #1
:   cmp #56
    bcs no
    sec
    rts
no:
    clc
    rts
.endproc

; carry set when enemy X is at or to the right of the player (signed 16-bit)
.proc enemy_cmp
    lda E_X,x
    cmp px
    lda E_XH,x
    sbc px+1
    bvc :+
    eor #$80
:   bmi less
    sec
    rts
less:
    clc
    rts
.endproc

; one pixel towards (A=0) or away from (A=1) the player
.proc step_x
    sta tmp
    jsr enemy_cmp
    lda #0
    rol                     ; 1 = enemy is on the right
    eor tmp                 ; 1 = decrease x
    bne dec_x
    inc E_X,x
    bne :+
    inc E_XH,x
:   rts
dec_x:
    lda E_X,x
    bne :+
    dec E_XH,x
:   dec E_X,x
    rts
.endproc

; Speeds: the C64 moves enemies every frame at 50 Hz. At 60 Hz they skip one frame in 8
; (ghosts: 1 in 16 of their half-speed frames) to keep about the same pace.
.proc ghost_update
    lda E_FLEE,x
    beq hunt
    dec E_FLEE,x
    ; flee fast; at the edges they sink through the walls
    lda #1
    jsr step_x
    lda #1
    jsr step_x
    jsr ghost_y_away
    jmp draw
hunt:
    jsr flare_scares
    bcc chase
    lda #72
    sta E_FLEE,x
    lda #SFX_WAIL
    jsr sfx_play
    jmp draw
chase:
    lda E_T,x
    and #1
    bne draw
    lda E_T,x
    and #15
    beq draw
    lda #0
    jsr step_x
    lda E_Y,x               ; vertical chase
    cmp py
    beq draw
    bcc :+
    dec E_Y,x
    jmp draw
:   inc E_Y,x
draw:
    jsr clamp_enemy
    jsr enemy_cmp
    lda #0
    rol
    sta E_DIR,x
    ; gentle bob
    lda E_T,x
    lsr
    lsr
    and #15
    tay
    lda bob_table,y
    clc
    adc E_Y,x
    sta E_DRAWY,x
    jmp touch_check
.endproc

.proc ghost_y_away
    lda E_Y,x
    cmp py
    bcc :+
    inc E_Y,x
    rts
:   dec E_Y,x
    rts
.endproc

; keep x in 0-232 and y in 0-156
.proc clamp_enemy
    lda E_XH,x
    bmi low
    bne high
    lda E_X,x
    cmp #233
    bcc yclamp
high:
    lda #232
    sta E_X,x
    lda #0
    sta E_XH,x
    beq yclamp
low:
    lda #0
    sta E_X,x
    sta E_XH,x
yclamp:
    lda E_Y,x
    cmp #240
    bcs ylow
    cmp #156
    bcc out
    lda #156
    sta E_Y,x
out:
    rts
ylow:
    lda #0
    sta E_Y,x
    rts
.endproc

; swoops along in a wave and turns at the walls
.proc bat_update
    lda E_FLEE,x
    beq :+
    dec E_FLEE,x
    jmp fly
:   jsr flare_scares
    bcc fly
    lda #48
    sta E_FLEE,x
    jsr enemy_cmp
    lda #0
    rol
    eor #1                  ; head away from the player
    sta E_DIR,x
fly:
    lda E_T,x
    and #7
    beq wave
    lda E_DIR,x
    bne left
    lda E_X,x
    clc
    adc #2
    sta E_X,x
    lda E_XH,x
    adc #0
    sta E_XH,x
    bne turn
    lda E_X,x
    cmp #228
    bcc wave
turn:
    lda #1
    sta E_DIR,x
    bne wave
left:
    lda E_X,x
    sec
    sbc #2
    sta E_X,x
    lda E_XH,x
    sbc #0
    sta E_XH,x
    bpl wave
    lda #0
    sta E_X,x
    sta E_XH,x
    sta E_DIR,x
wave:
    lda E_T,x
    lsr
    and #31
    tay
    lda bat_wave,y
    clc
    adc E_HOME,x
    sta E_Y,x
    sta E_DRAWY,x
    jmp touch_check
.endproc

.proc wolf_update
    lda E_FLEE,x
    beq :+
    dec E_FLEE,x
    jmp walk
:   jsr flare_scares
    bcc walk
    lda #54
    sta E_FLEE,x
    jsr enemy_cmp
    lda #0
    rol
    eor #1
    sta E_DIR,x
    lda #SFX_WAIL
    jsr sfx_play
walk:
    ; walks at 1 px a frame; scared wolves run at 2
    lda E_T,x
    and #7
    beq :+
    jsr wolf_step
    lda E_FLEE,x
    beq :+
    jsr wolf_step
:   lda E_Y,x
    sta E_DRAWY,x
    jmp touch_check
.endproc

.proc wolf_step
    lda E_DIR,x
    bne left
    lda E_X,x
    clc
    adc #1
    sta E_X,x
    lda E_XH,x
    adc #0
    sta E_XH,x
    lda E_X,x               ; ahead: the right edge
    clc
    adc #20
    jmp check
left:
    lda E_X,x
    sec
    sbc #1
    sta E_X,x
    lda E_XH,x
    sbc #0
    sta E_XH,x
    lda E_X,x
    clc
    adc #2
check:
    sta tx
    lda E_XH,x
    adc #0
    sta tx+1
    stx tmp5
    ; floor under the leading foot, wall in front
    lda E_Y,x
    clc
    adc #21
    sta ty
    jsr probe
    and #TF_SOLID|TF_PLATFORM
    beq turn
    ldx tmp5
    lda E_Y,x
    clc
    adc #10
    sta ty
    jsr probe
    and #TF_SOLID
    bne turn
    ldx tmp5                ; stay on screen
    lda E_XH,x
    bne turn
    lda E_X,x
    cmp #216
    bcs turn
    rts
turn:
    ldx tmp5
    lda E_DIR,x
    eor #1
    sta E_DIR,x
    rts
.endproc

; Brooke is afraid of the dark: keep the candle raised beside her and she
; finds the courage to hand over the winding key
.proc brooke_update
    lda E_Y,x
    sta E_DRAWY,x
    jsr enemy_cmp
    lda #0
    rol
    sta E_DIR,x
    lda rescued
    beq :+
    lda #0                  ; calm now: stop trembling
    sta E_T,x
    rts
:   lda E_X,x
    sec
    sbc px
    tay
    lda E_XH,x
    sbc px+1
    beq pos
    cmp #$FF
    bne out
    tya
    eor #$FF
    clc
    adc #1
    tay
    beq out
pos:
    cpy #40
    bcs out
    lda E_Y,x
    sec
    sbc py
    bcs :+
    eor #$FF
    adc #1
:   cmp #24
    bcs out
    lda flare
    bne lighting
    lda msg_timer           ; say it when the row is free, or straight away on arrival
    beq say
    lda brooke_said
    bne out
say:
    lda #1
    sta brooke_said
    lda wax
    bne :+
    lda #<msg_nowax
    ldx #>msg_nowax
    jmp show_message
:   lda #<msg_hold
    ldx #>msg_hold
    jmp show_message
lighting:
    lda brooke_said
    cmp #2
    beq :+
    lda #2
    sta brooke_said
    lda #<msg_keep
    ldx #>msg_keep
    jsr show_message
:   inc rescue_t
    lda rescue_t
    cmp #RESCUE_TIME
    bcs saved
    and #15
    bne out
    lda #SFX_CANDLE
    jmp sfx_play
saved:
    lda #SFX_PART
    jsr sfx_play
    lda #1
    sta rescued
    sta hud_dirty
    lda parts
    ora #8
    sta parts
    lda #<msg_thanks
    ldx #>msg_thanks
    jmp show_message
out:
    rts
.endproc

; did this enemy catch the player?
.proc touch_check
    lda E_X,x
    sec
    sbc px
    tay
    lda E_XH,x
    sbc px+1
    beq pos
    cmp #$FF
    bne miss
    tya
    eor #$FF
    clc
    adc #1
    tay
    beq miss
pos:
    cpy #13
    bcs miss
    lda E_DRAWY,x
    sec
    sbc py
    bcs :+
    eor #$FF
    adc #1
:   cmp #14
    bcs miss
    lda invuln
    bne miss
    lda E_TYPE,x
    cmp #1
    beq batbite
    cmp #2
    beq wolfbite
    stx tmp5
    lda #1
    jsr hurt_player
    ldx tmp5
    lda #84
    sta E_FLEE,x
    rts
wolfbite:
    stx tmp5
    lda #2
    jsr hurt_player
    ldx tmp5
    rts
batbite:
    ; bats go for the candle: wax rather than nerve
    lda wax
    sec
    sbc #12
    bcs :+
    lda #0
:   sta wax
    lda #72
    sta invuln
    lda #1
    sta hud_dirty
    lda #48
    sta E_FLEE,x
    lda #SFX_HIT
    jsr sfx_play
    stx tmp5
    lda #<msg_bat
    ldx #>msg_bat
    jsr show_message
    ldx tmp5
miss:
    rts
.endproc

; ---- pick-ups and the clock ------------------------------------------------------
.proc item_update
    lda item_type
    cmp #$FF
    beq out
    lda item_x
    sec
    sbc px
    tay
    lda item_x+1
    sbc px+1
    beq pos
    cmp #$FF
    bne out
    tya
    eor #$FF
    clc
    adc #1
    tay
    beq out
pos:
    cpy #16
    bcs out
    lda item_y
    sec
    sbc py
    bcs :+
    eor #$FF
    adc #1
:   cmp #18
    bcs out
    ; got it
    lda item_type
    cmp #4
    beq candle
    tax
    lda part_bits,x
    ora parts
    sta parts
    ldx room
    lda #1
    sta ITEM_GONE,x
    lda #$FF
    sta item_type
    sta hud_dirty
    lda #SFX_PART
    jsr sfx_play
    lda #<msg_part
    ldx #>msg_part
    jmp show_message
candle:
    lda #WAX_FULL
    sta wax
    lda #1
    sta hud_dirty
    lda #$FF
    sta item_type
    ldx room                ; the hall's candle box never runs out
    cpx #HALL_ROOM
    beq :+
    lda #1
    sta ITEM_GONE,x
:   lda #SFX_CANDLE
    jsr sfx_play
    lda #<msg_candle
    ldx #>msg_candle
    jmp show_message
out:
    rts
.endproc

; walking into the clock
.proc clock_check
    lda clock_cd
    beq :+
    dec clock_cd
:   lda #12
    jsr set_tx
    lda py
    clc
    adc #10
    sta ty
    jsr probe
    and #TF_CLOCK
    beq out
    lda parts
    cmp #15
    bne notyet
    lda #1
    sta game_over
    rts
notyet:
    lda clock_cd
    bne out
    lda #240
    sta clock_cd
    lda #<msg_clock0
    ldx #>msg_clock0
    jmp show_message
out:
    rts
.endproc

; tx (16 bit), ty: is that point in the light? Carry set when lit.
.proc in_light
    lda cur_lit
    ora flash
    ora all_lit
    bne yes
    lda tx+1
    bne no                  ; off screen
    lda tx
    lsr
    lsr
    lsr                     ; to tiles
    sec
    sbc cx
    bcs :+
    eor #$FF
    adc #1
:   sta tmp2                ; |dx|
    lda ty
    lsr
    lsr
    lsr
    sec
    sbc cy
    bcs :+
    eor #$FF
    adc #1
:   cmp #9
    bcs no
    cmp radius
    beq :+
    bcs no
:   sta tmp3
    ; compare with the disc's half width at this |dy|
    lda radius
    asl
    asl
    asl
    adc radius              ; radius*9 (max 72, no carry)
    adc tmp3
    tay
    lda disc_table,y
    cmp tmp2
    bcc no
yes:
    sec
    rts
no:
    clc
    rts
.endproc

; ---- sprites -------------------------------------------------------------------
; Each object is a 3x3 grid of 8x8 sprites (meta_tiles), empty tiles left out. The NES shows
; at most 8 sprites on a line, so the drawing order flips every frame: when too many share a
; line they flicker rather than one of them vanishing.
.proc draw_sprites
    lda #0
    sta oam_i
    lda frame
    and #1
    bne odd
    jsr spr_hero
    jsr spr_flame
    jsr spr_item
    ldx #0
    jsr spr_enemy
    ldx #1
    jsr spr_enemy
    jmp hide
odd:
    ldx #1
    jsr spr_enemy
    ldx #0
    jsr spr_enemy
    jsr spr_item
    jsr spr_flame
    jsr spr_hero
hide:
    ldy oam_i
    lda #$FF
:   sta OAM,y
    iny
    iny
    iny
    iny
    bne :-
    rts
.endproc

.proc spr_hero
    lda invuln              ; blink while safe after a scare
    and #4
    bne out
    lda pframe
    clc
    adc #F_HERO0
    sta ofr
    lda px
    sta ox
    lda px+1
    sta ox+1
    lda py
    sta oy
    lda #0
    ldx facing
    beq :+
    lda #$40
:   sta oattr               ; palette 0
    jmp draw_meta
out:
    rts
.endproc

; the flame over the candle in the front hand, unless climbing or snuffed out
.proc spr_flame
    lda wax
    beq out
    lda pframe
    cmp #5
    bcs out
    lda frame
    lsr
    lsr
    and #1
    ldx flare
    beq :+
    lda #2
:   clc
    adc #F_FLAME0
    sta ofr
    lda py
    sec
    sbc #3
    sta oy
    lda facing
    beq right
    lda px
    sec
    sbc #10
    sta ox
    lda px+1
    sbc #0
    sta ox+1
    jmp :+
right:
    lda px
    clc
    adc #10
    sta ox
    lda px+1
    adc #0
    sta ox+1
:   lda #1
    sta oattr
    jmp draw_meta
out:
    rts
.endproc

; the room's item: in the light it shows, cycling white and yellow; in the dark a glint
; now and then, white for a clock part and yellow for a candle
.proc spr_item
    lda item_type
    cmp #$FF
    beq out
    lda item_x
    sta ox
    clc
    adc #12
    sta tx
    lda item_x+1
    sta ox+1
    adc #0
    sta tx+1
    lda item_y
    sta oy
    clc
    adc #10
    sta ty
    jsr in_light
    bcc glint
    lda item_type
    clc
    adc #F_ITEM_COG
    sta ofr
    lda frame
    lsr
    lsr
    lsr
    and #1                  ; palette 0 (yellow) or 1 (white)
    sta oattr
    jmp draw_meta
glint:
    lda frame
    and #31
    cmp #8
    bcs out
    lda #F_ITEM_GLINT
    sta ofr
    lda #1
    ldx item_type
    cpx #4
    bcc :+
    lda #0
:   sta oattr
    jmp draw_meta
out:
    rts
.endproc

; enemy X: lit, or only its eyes in the dark (Brooke always shows)
.proc spr_enemy
    lda E_TYPE,x
    cmp #$FF
    beq out
    stx count
    lda E_X,x
    sta ox
    clc
    adc #12
    sta tx
    lda E_XH,x
    sta ox+1
    adc #0
    sta tx+1
    lda E_DRAWY,x
    sta oy
    clc
    adc #10
    sta ty
    jsr in_light
    ldx count
    bcs shown
    lda E_TYPE,x
    cmp #E_BROOKE
    beq shown
    lda E_T,x               ; eyes, blinking now and then
    and #$3F
    cmp #4
    bcc out
    lda E_TYPE,x
    clc
    adc #F_EYES_G
    sta ofr
    txa
    ora #2                  ; palette 2 or 3
    sta oattr
    jmp draw_meta
shown:
    ldy E_TYPE,x
    lda E_T,x
    lsr
    lsr
    lsr
    and #1
    clc
    adc enemy_frame,y
    sta ofr
    txa
    ora #2
    ldy E_DIR,x
    beq :+
    ora #$40
:   sta oattr
    jmp draw_meta
out:
    rts
.endproc

; frame ofr at (ox, oy) with attributes oattr, into OAM from oam_i
.proc draw_meta
    ldx ofr
    lda meta_lo,x
    sta ptr2
    lda meta_hi,x
    sta ptr2+1
    lda #0
    sta tmp2                ; part 0-8
loop:
    ldy tmp2
    lda (ptr2),y
    beq next                ; empty tile: no sprite
    ldy oam_i
    sta OAM+1,y
    ldx tmp2
    bit oattr
    bvs flip
    lda part_dx,x
    bvc :+
flip:
    lda part_dxf,x
:   clc
    adc ox
    sta OAM+3,y
    lda ox+1
    adc #0
    bne next                ; off screen sideways
    lda part_dy,x
    clc
    adc oy
    clc
    adc #15                 ; room top is y 16; sprites show one line lower
    sta OAM,y
    lda oattr
    sta OAM+2,y
    tya
    clc
    adc #4
    sta oam_i
next:
    inc tmp2
    lda tmp2
    cmp #9
    bne loop
    rts
.endproc

.include "sound.s"

.segment "VECTORS"
    .addr nmi, reset, irq
