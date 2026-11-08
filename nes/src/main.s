; Ghost Hour - NES port, milestone 2: all 13 rooms with their exits, candle lighting, wax,
; lightning and rain. The game logic is a port of the C64 version (../src/main.asm),
; with speeds and timers rescaled from 50 Hz (PAL C64) to 60 Hz (NTSC NES).
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
CTRL     = %10001000        ; NMI on, sprites from $1000, background from $0000
MASK_ON  = %00011110        ; show background and sprites, also in the left 8 px
VB_BUDGET = 96              ; vblank work per frame: data bytes + 2 per run
ROOM_ROWS = 22              ; tile rows of the room
ROOM_TOP  = 2               ; tile row where the room starts
HUD_NAME  = $2000 + 26*32 + 2
HUD_GAUGE = $2000 + 26*32 + 22
HUD_MSG   = $2000 + 27*32 + 2
MSG_LEN   = 28

.include "gen_const.inc"

.segment "HEADER"
    .byte "NES", $1A
    .byte 2                 ; 2 x 16 KB PRG
    .byte 0                 ; CHR-RAM
    .byte $21               ; mapper 2, vertical mirroring
    .byte $00
    .res 8, 0

.segment "ZEROPAGE"
dbg_room:  .res 1           ; test hook: tools/play.py writes room+1 here to jump to a room
nmi_count: .res 1
nmi_skip:  .res 1           ; set while the main code writes the PPU directly
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

.segment "BSS"
vbuf:      .res 256         ; queued PPU writes: [length, address hi, address lo, data...], 0 ends
LITBUF:    .res ROOM_ROWS*32 ; the room's tiles as they look when lit
MAP:       .res 176         ; the room's metatiles
CUR_L:     .res ROOM_ROWS   ; light span on screen, per row
CUR_R:     .res ROOM_ROWS
NEW_L:     .res ROOM_ROWS   ; light span wanted, per row
NEW_R:     .res ROOM_ROWS
gauge_buf: .res 8

; ---------------------------------------------------------------------------
.segment "BANK0"
chr_in:    .incbin "chr_in.bin"
chr_out:   .incbin "chr_out.bin"
chr_spr:   .incbin "chr_spr.bin"

; ---------------------------------------------------------------------------
.segment "RODATA"
.include "gen_data.inc"

; UNROM has bus conflicts: the bank number is written over a ROM byte holding the same value
bank_table: .byte 0, 1

; where each of the 9 hero tiles goes, relative to the sprite's top left
part_dx:   .byte 0, 8, 16, 0, 8, 16, 0, 8, 16
part_dxf:  .byte 16, 8, 0, 16, 8, 0, 16, 8, 0
part_dy:   .byte 0, 0, 0, 8, 8, 8, 16, 16, 16
mul9:      .byte 0, 9, 18, 27, 36, 45, 54
run_cycle: .byte 1, 2, 3, 2
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

    lda #0                  ; select bank 0 at $8000
    tax
    sta bank_table,x

    ; sprite tiles into CHR-RAM at $1000
    lda #$10
    sta PPUADDR
    lda #0
    sta PPUADDR
    lda #<chr_spr
    sta ptr
    lda #>chr_spr
    sta ptr+1
    ldx #16
    jsr copy_pages

    lda #$FF
    sta set_loaded
    lda #$A7
    sta rng
    lda #$0F
    sta bgcol
    lda #WAX_FULL
    sta wax
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
    jsr enter_room
    jsr player_anim
    jsr draw_player

    lda #CTRL
    sta PPUCTRL
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
    jsr storm_update
    jsr hud_update
    jsr rain_update
    jsr light_update
    jsr light_flush
    jsr draw_player
    jsr vb_end
    inc frame
    jmp main_loop
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
    lda #CTRL
    sta PPUCTRL
    lda mask_shadow
    sta PPUMASK
done:
    inc nmi_count
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
    cmp set_loaded
    beq have_set
    sta set_loaded
    lda #0
    sta rain_step
    sta PPUADDR
    sta PPUADDR
    lda #<chr_in
    ldx #>chr_in
    ldy cur_lit
    beq :+
    lda #<chr_out
    ldx #>chr_out
:   sta ptr
    stx ptr+1
    ldx #16
    jsr copy_pages
have_set:
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
    ; HUD: row 24 empty, row 25 a rule, row 26 name and wax, rows 27-29 empty
    lda #BLANK
    ldx #33
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
    ldy #0
:   lda txt_wax,y
    sta PPUDATA
    iny
    cpy #4
    bne :-
    jsr make_gauge
    ldy #0
:   lda gauge_buf,y
    sta PPUDATA
    iny
    cpy #8
    bne :-
    lda #BLANK
    ldx #2+96
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
:   lda spr_palettes,y
    sta PPUDATA
    iny
    cpy #16
    bne :-

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

; wax gauge: 8 tiles, each 0-8 columns full
.proc make_gauge
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
    sta gauge_buf,x
    lda tmp
    sec
    sbc tmp2
    sta tmp
    inx
    cpx #8
    bne :--
    rts
.endproc

.proc hud_update
    lda hud_dirty
    beq msg
    lda #10
    jsr vb_fits
    bcc msg
    lda #0
    sta hud_dirty
    jsr make_gauge
    lda #<HUD_GAUGE
    sta vaddr
    lda #>HUD_GAUGE
    sta vaddr+1
    lda #8
    jsr vb_head
    ldy #0
:   lda gauge_buf,y
    sta vbuf,x
    inx
    iny
    cpy #8
    bne :-
    stx vbx
msg:
    lda msg_timer
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

; ---- sprites -------------------------------------------------------------------
; The hero is up to 9 tiles (3x3). Facing left flips each tile and mirrors the columns.
; Tiles off the left or right edge of the screen are left out.
.proc draw_player
    ldx pframe
    lda mul9,x
    sta tmp                 ; first entry of this frame in hero_tiles
    lda #0
    sta tmp2                ; part 0-8
    ldy #0                  ; OAM offset
loop:
    lda tmp
    clc
    adc tmp2
    tax
    lda hero_tiles,x
    beq next                ; empty tile: no sprite
    sta OAM+1,y
    ldx tmp2
    lda facing
    beq :+
    lda part_dxf,x
    ldx #$40
    bne :++
:   lda part_dx,x
    ldx #$00
:   stx tmp3                ; attributes
    clc
    adc px
    sta OAM+3,y
    lda px+1
    adc #0
    bne next                ; off screen sideways
    lda tmp3
    sta OAM+2,y
    ldx tmp2
    lda part_dy,x
    clc
    adc py
    clc
    adc #15                 ; room top is y 16; sprites show one line lower
    sta OAM,y
    iny
    iny
    iny
    iny
next:
    inc tmp2
    lda tmp2
    cmp #9
    bne loop
    lda #$FF                ; hide the rest
:   sta OAM,y
    iny
    iny
    iny
    iny
    bne :-
    rts
.endproc

.segment "VECTORS"
    .addr nmi, reset, irq
