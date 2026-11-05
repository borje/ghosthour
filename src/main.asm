; =====================================================================
;  GHOST HOUR  -  a haunted-manor platformer for the Commodore 64
;  Assemble with ACME. See README.md.
;
;  Memory map
;    $0801-$3FFF  code, tables
;    $4000-$43FF  VIC bank 1: screen + sprite pointers
;    $4800-$4FFF  indoor charset   (128 lit + 128 dark chars)
;    $5000-$57FF  HUD/text font
;    $5800-$5FFF  outdoor charset
;    $6000-$7FFF  sprites
;    $8000-$87E7  title: screen matrix (VIC bank 2) and colour data
;    $8800-$9FFF  room maps
;    $A000-$BF3F  title: bitmap (VIC bank 2, under BASIC ROM)
;    $C000-$C8FF  runtime buffers
; =====================================================================
!cpu 6510
!to "build/ghosthour.prg", cbm
!sl "build/labels.txt"

; ---- zero page ------------------------------------------------------
!addr dbg_joy   = $02       ; debug builds: forces joystick input
!addr dbg_room  = $03       ; debug builds: room number + 1 to warp to
!addr vsync     = $04
!addr frame     = $05
!addr rng       = $06
!addr irq_mode  = $07
!addr irq_phase = $08
!addr joy       = $09
!addr joy_prev  = $0a
!addr ptr       = $10       ; +$11
!addr ptr2      = $12
!addr ptr3      = $14
!addr ptr4      = $16
!addr tmp       = $18
!addr tmp2      = $19
!addr tmp3      = $1a
!addr tmp4      = $1b
!addr tmp5      = $1c
!addr tx        = $1d       ; +$1e  probe x (16 bit)
!addr ty        = $1f       ; probe y

!addr px        = $20       ; +$21 player x
!addr py        = $22
!addr pys       = $23       ; y subpixel
!addr vy        = $24       ; +$25 velocity 8.8
!addr grounded  = $26
!addr on_ladder = $27
!addr facing    = $28       ; 0 right, 1 left
!addr pframe    = $29
!addr invuln    = $2a
!addr room      = $2b
!addr parts     = $2c
!addr nerve     = $2d
!addr wax       = $2e
!addr wax_tick  = $2f
!addr flare     = $30
!addr radius    = $31
!addr cx        = $32       ; light centre, in chars
!addr cy        = $33
!addr last_cx   = $34
!addr last_cy   = $35
!addr last_r    = $36
!addr flick     = $37
!addr flash     = $38       ; frames of lightning left
!addr flash_col = $39
!addr thunder_t = $3a       ; +$3b frames until the next strike
!addr msg_timer = $3c
!addr hud_dirty = $3d
!addr dark_tick = $3e
!addr clock_cd  = $3f
!addr cur_d018  = $40
!addr cur_d022  = $41
!addr cur_d023  = $42
!addr cur_dim   = $43
!addr cur_lit   = $44
!addr irq_d021  = $45
!addr entry_x   = $46       ; +$47 where we entered the room
!addr entry_y   = $48
!addr game_over = $49       ; 0 playing, 1 won, 2 fainted
!addr item_type = $4a
!addr item_x    = $4b       ; +$4c
!addr item_y    = $4d
!addr red_flash = $4e
!addr has_rain  = $4f

!addr mus_on    = $50
!addr mus_frame = $51
!addr pw        = $52
!addr sfx_dur   = $53
!addr sfx_flo   = $54
!addr sfx_fhi   = $55
!addr sfx_dlo   = $56
!addr sfx_dhi   = $57
!addr ptr5      = $58       ; +$59
!addr mptr      = $5a       ; +$5b  music (IRQ) only
!addr mtmp      = $5c
!addr mtmp2     = $5d
!addr rescued   = $5e       ; Brooke is safe
!addr rescue_t  = $5f       ; frames of candlelight she has had
!addr brooke_said = $60     ; 1 asked for light, 2 encouraged, this visit

; ---- arrays, outside zero page ---------------------------------------
LIT_CHR  = $C000            ; what each screen cell looks like when lit
LIT_COL  = $C400
MAP      = $C800            ; current room's 220 metatiles
CUR_L    = $C900            ; current light span per row
CUR_R    = $C920
ITEM_GONE = $C940           ; per room: item collected
E_TYPE   = $C960            ; enemies: 2 entries each
E_X      = $C962
E_XH     = $C964
E_Y      = $C966
E_DIR    = $C968
E_T      = $C96A
E_FLEE   = $C96C
E_HOME   = $C96E
E_DRAWY  = $C970
E_LIT    = $C972
S_X      = $C980            ; sprite shadows: 8 entries
S_XH     = $C988
S_Y      = $C990
S_PTR    = $C998
S_COL    = $C9A0
S_ON     = $C9A8
MUS_PTRL = $C9B0            ; music: 3 voices
MUS_PTRH = $C9B3
MUS_DUR  = $C9B6
MUS_NOTE = $C9B9
MUS_STL  = $C9BC
MUS_STH  = $C9BF
MUS_WAVE = $C9C2
MUS_ARP  = $C9C5
MUS_ACT  = $C9C8
ROT_BUF  = $C9D0            ; 16 bytes

SCREEN   = $4000
SPRPTR   = $43F8
COLOR    = $D800
SPR_BASE = 128              ; first sprite frame: $6000 in bank 1

J_UP = 1 : J_DOWN = 2 : J_LEFT = 4 : J_RIGHT = 8 : J_FIRE = 16

; HUD screen rows
HUD_ROW0 = SCREEN + 22*40
HUD_ROW1 = SCREEN + 23*40
HUD_ROW2 = SCREEN + 24*40
HUDC_ROW0 = COLOR + 22*40
HUDC_ROW1 = COLOR + 23*40
HUDC_ROW2 = COLOR + 24*40

WAX_FULL = 64
JUMP_V   = $0300            ; 8.8 px/frame: rises 36 px, just over two tiles
GRAVITY  = $20
NERVE_FULL = 5

; ---- BASIC stub -------------------------------------------------------
* = $0801
    !word basic_end, 1984
    !byte $9e
    !text "2062"
    !byte 0
!zone basic_end
basic_end:
    !word 0

* = $080e
!zone start
start:
    sei
    cld
    ldx #$ff
    txs
    lda #$35            ; RAM everywhere except I/O
    sta $01
    lda #<irq
    sta $fffe
    lda #>irq
    sta $ffff
    lda #<nmi
    sta $fffa
    lda #>nmi
    sta $fffb
    lda #$7f
    sta $dc0d
    sta $dd0d
    lda $dc0d
    lda $dd0d
    lda #$ff
    sta $dc02
    lda #$00
    sta $dc03
    lda #$01
    sta $d01a
    lda #$1b
    sta $d011
    lda #250
    sta $d012
    lda #$ff
    sta $d019
    lda #1
    sta irq_mode
    lda #0
    sta $d015
    sta $d020
    sta dbg_joy
    sta dbg_room
    lda #$a7
    sta rng
    jsr sid_init
    cli
!zone main_loop
main_loop:
    jsr title_screen
    jsr story_screen
    jsr play_game
    lda game_over
    cmp #1
    bne +
    jsr win_screen
    jmp main_loop
+   jsr lose_screen
    jmp main_loop

!zone nmi
nmi:
    rti

; ---- raster interrupt --------------------------------------------------
LINE_HUD = 225
LINE_VB  = 250
LINE_TOP = 30

!zone irq
irq:
    pha
    txa
    pha
    tya
    pha
    lda #$ff
    sta $d019
    lda irq_mode
    bne .plain
    ldx irq_phase
    beq .vb
    dex
    beq .top
    ; phase 2: hand over to the HUD
    lda #$04
    sta $d018
    lda #$08
    sta $d016
    lda #0
    sta $d021
    sta $d020
    lda #LINE_VB
    sta $d012
    lda #0
    sta irq_phase
    jmp .out
.vb:                        ; phase 0: bottom border, tell the main loop
    inc vsync
    jsr music_tick
    lda #LINE_TOP
    sta $d012
    lda #1
    sta irq_phase
    jmp .out
.top:                       ; phase 1: above the play field
    lda cur_d018
    sta $d018
    lda #$18
    sta $d016
    lda irq_d021
    sta $d021
    sta $d020
    lda cur_d022
    sta $d022
    lda cur_d023
    sta $d023
    lda #LINE_HUD
    sta $d012
    lda #2
    sta irq_phase
    jmp .out
.plain:
    inc vsync
    jsr music_tick
.out:
    pla
    tay
    pla
    tax
    pla
    rti

!zone wait_frame
wait_frame:
    lda #0
    sta vsync
-   lda vsync
    beq -
    inc frame
    rts

; ---- input ----------------------------------------------------------
; joy: active-high bits. Joystick port 2, or keyboard W A S D + SPACE.
!zone read_input
read_input:
    lda joy
    sta joy_prev
    lda #$ff
    sta $dc00
    lda $dc00
    eor #$ff
    and #$1f
    sta joy
    ; column 1: W (row 1) A (row 2) S (row 5)
    lda #%11111101
    sta $dc00
    lda $dc01
    tax
    and #%00000010
    bne +
    lda joy
    ora #J_UP
    sta joy
+   txa
    and #%00000100
    bne +
    lda joy
    ora #J_LEFT
    sta joy
+   txa
    and #%00100000
    bne +
    lda joy
    ora #J_DOWN
    sta joy
+   ; column 2: D (row 2)
    lda #%11111011
    sta $dc00
    lda $dc01
    and #%00000100
    bne +
    lda joy
    ora #J_RIGHT
    sta joy
+   ; column 7: SPACE (row 4)
    lda #%01111111
    sta $dc00
    lda $dc01
    and #%00010000
    bne +
    lda joy
    ora #J_FIRE
    sta joy
+   lda #$ff
    sta $dc00
!ifdef DEBUG {
    lda dbg_joy         ; test builds take input only from the test script
    and #$1f
    sta joy
}
    rts

; returns with carry set on a fresh press of fire
!zone fire_pressed
fire_pressed:
    lda joy
    and #J_FIRE
    beq .no
    lda joy_prev
    and #J_FIRE
    bne .no
    sec
    rts
.no:
    clc
    rts

; 8-bit LFSR
!zone random
random:
    lda rng
    asl
    bcc +
    eor #$1d
+   sta rng
    rts

; ---- text helpers ---------------------------------------------------
!zone clear_text
clear_text:
    ldx #0
    lda #32
-   sta SCREEN,x
    sta SCREEN+$100,x
    sta SCREEN+$200,x
    sta SCREEN+$300,x
    inx
    bne -
    lda #1
-   sta COLOR,x
    sta COLOR+$100,x
    sta COLOR+$200,x
    sta COLOR+$300,x
    inx
    bne -
    rts

; in: ptr = zero-terminated !scr text, ptr2 = screen address, A = colour
!zone print
print:
    sta tmp
    lda ptr2
    sta ptr3
    lda ptr2+1
    clc
    adc #>(COLOR-SCREEN)
    sta ptr3+1
    ldy #0
-   lda (ptr),y
    beq +
    sta (ptr2),y
    lda tmp
    sta (ptr3),y
    iny
    bne -
+   rts

; text pages: list of (row, col, colour, text...0), ended by a row of $ff
!zone print_page
print_page:
-   ldy #0
    lda (ptr4),y
    cmp #$ff
    beq .done
    tax
    iny
    lda (ptr4),y
    clc
    adc scr_lo,x
    sta ptr2
    lda scr_hi,x
    adc #>SCREEN
    sta ptr2+1
    iny
    lda (ptr4),y
    pha
    lda ptr4
    clc
    adc #3
    sta ptr
    lda ptr4+1
    adc #0
    sta ptr+1
    pla
    jsr print
    tya
    sec                 ; skip the text and its terminator
    adc ptr
    sta ptr4
    lda ptr+1
    adc #0
    sta ptr4+1
    jmp -
.done:
    rts

!zone set_text_mode
set_text_mode:
    sei
    lda #1
    sta irq_mode
    lda #LINE_VB
    sta $d012
    cli
    lda $dd00
    and #$fc
    ora #2              ; VIC bank 1
    sta $dd00
    lda #$1b
    sta $d011
    lda #$08
    sta $d016
    lda #$04
    sta $d018
    lda #0
    sta $d015
    sta $d020
    sta $d021
    rts

; wait for fire to be released, then pressed
!zone wait_fire
wait_fire:
-   jsr wait_frame
    jsr read_input
    lda joy
    and #J_FIRE
    bne -
-   jsr wait_frame
    jsr random
    jsr read_input
    lda joy
    and #J_FIRE
    beq -
    rts

; ---- title ----------------------------------------------------------
!zone title_screen
title_screen:
    sei
    lda #1
    sta irq_mode
    lda #LINE_VB
    sta $d012
    cli
    lda #0
    sta $d011           ; blank while we copy
    sta $d015
    ldx #0
-   lda $8400,x
    sta COLOR,x
    lda $8500,x
    sta COLOR+$100,x
    lda $8600,x
    sta COLOR+$200,x
    lda $8700,x
    sta COLOR+$300,x
    inx
    bne -
    lda $dd00
    and #$fc
    ora #1              ; VIC bank 2
    sta $dd00
    lda #$08            ; screen at $8000, bitmap at $A000
    sta $d018
    lda #$18
    sta $d016
    lda #0
    sta $d020
    lda #TITLE_BG
    sta $d021
    lda #$3b
    sta $d011
    lda #SONG_TITLE
    jsr music_start
    lda #120
    sta tmp5
.loop:
    jsr wait_frame
    jsr read_input
    jsr fire_pressed
    bcs .go
    jsr random
    ; sky lightning: the sky is the background colour, one register flashes it
    dec tmp5
    bne .noflash
    lda rng
    ora #$40
    sta tmp5
    lda #14
    sta $d021
    jsr flash_wait
    jsr flash_wait
    lda #TITLE_BG
    sta $d021
    jsr flash_wait
    lda #1
    sta $d021
    jsr flash_wait
    lda #14
    sta $d021
    jsr flash_wait
.noflash:
    lda #TITLE_BG
    sta $d021
    jmp .loop
.go:
    rts

!zone flash_wait
flash_wait:
    jsr wait_frame
!ifdef DEBUG {
    jsr read_input      ; the demo recorder steps once per input read
    lda #0              ; a press during the flash must still count as new
    sta joy
}
    rts

!zone story_screen
story_screen:
    lda #0
    sta $d011
    jsr set_text_mode
    jsr clear_text
    lda #<story_text
    sta ptr4
    lda #>story_text
    sta ptr4+1
    jsr print_page
    jmp wait_fire

!zone story_text
story_text:
    !byte 2,14,7
    !scr "ghost hour",0
    !byte 5,3,1
    !scr "a stormy night. your bicycle is in",0
    !byte 6,3,1
    !scr "a ditch, and the telegram in your",0
    !byte 7,3,1
    !scr "pocket is for the old manor house.",0
    !byte 9,3,15
    !scr "the great clock stopped one minute",0
    !byte 10,3,15
    !scr "before midnight, and the hour of",0
    !byte 11,3,15
    !scr "the ghosts has never ended.",0
    !byte 13,3,1
    !scr "find the four lost clock parts and",0
    !byte 14,3,1
    !scr "bring them to the great hall. and",0
    !byte 15,3,1
    !scr "listen: someone is calling for help.",0
    !byte 17,3,7
    !scr "move: joystick 2 or w a s d",0
    !byte 18,3,7
    !scr "up:   jump, climb ladders",0
    !byte 19,3,7
    !scr "fire or space: raise your candle",0
    !byte 20,3,7
    !scr "to scare ghosts - but it burns wax",0
    !byte 23,10,14
    !scr "press fire to enter",0
    !byte $ff

; ---- endings ----------------------------------------------------------
!zone win_screen
win_screen:
    lda #0
    sta $d011
    jsr set_text_mode
    jsr clear_text
    lda #<win_text
    sta ptr4
    lda #>win_text
    sta ptr4+1
    jsr print_page
    lda #SONG_TITLE
    jsr music_start
    jmp wait_fire

!zone lose_screen
lose_screen:
    lda #0
    sta $d011
    jsr set_text_mode
    jsr clear_text
    lda #<lose_text
    sta ptr4
    lda #>lose_text
    sta ptr4+1
    jsr print_page
    jmp wait_fire

!zone win_text
win_text:
    !byte 6,11,7
    !scr "bong! bong! bong!",0
    !byte 9,6,1
    !scr "the clock strikes twelve at last.",0
    !byte 11,4,15
    !scr "one by one the sheets sink empty to",0
    !byte 12,4,15
    !scr "the floor. the manor sighs. even the",0
    !byte 13,4,15
    !scr "rain stops.",0
    !byte 15,4,1
    !scr "you deliver the telegram to nobody,",0
    !byte 16,4,1
    !scr "and brooke helps find your bicycle.",0
    !byte 21,13,14
    !scr "well done!",0
    !byte $ff

!zone lose_text
lose_text:
    !byte 7,15,2
    !scr "eeek!!",0
    !byte 10,5,1
    !scr "it is all too much. you faint on",0
    !byte 11,5,1
    !scr "the spot, and wake up with a cold,",0
    !byte 12,5,1
    !scr "a sheet over you, and an odd urge",0
    !byte 13,5,1
    !scr "to float.",0
    !byte 18,10,14
    !scr "press fire to try again",0
    !byte $ff

; ---- the game --------------------------------------------------------
!zone play_game
play_game:
    lda #0
    sta $d015
    sta $d011
    sta parts
    sta game_over
    sta invuln
    sta flare
    sta flash
    sta msg_timer
    sta on_ladder
    sta facing
    sta vy
    sta vy+1
    sta pys
    sta red_flash
    sta clock_cd
    sta rescued
    sta rescue_t
    lda #NERVE_FULL
    sta nerve
    lda #WAX_FULL
    sta wax
    ldx #NUM_ROOMS
    lda #0
-   sta ITEM_GONE,x
    dex
    bpl -
    lda #<300
    sta thunder_t
    lda #>300
    sta thunder_t+1
    lda #START_ROOM
    sta room
    lda #40
    sta px
    lda #0
    sta px+1
    lda #139
    sta py
    ; display setup
    lda $dd00
    and #$fc
    ora #2
    sta $dd00
    lda #%10100110      ; sprites with a multicolour fill layer
    sta $d01c
    lda #10
    sta $d025           ; skin
    lda #1
    sta $d026           ; white
    lda #0
    sta $d017
    sta $d01d
    sta $d01b
    sta irq_d021
    jsr hud_init
    jsr enter_room
    sei
    lda #0
    sta irq_mode
    sta irq_phase
    lda #LINE_VB
    sta $d012
    cli
    lda #$1b
    sta $d011
    lda #SONG_GAME
    jsr music_start
    lda #<msg_start
    ldx #>msg_start
    jsr show_message
!zone game_loop
game_loop:
    jsr wait_frame
    jsr light_update
    jsr sprites_write
    jsr read_input
!ifdef DEBUG {
    lda dbg_room
    beq +
    sec
    sbc #1
    sta room
    lda #0
    sta dbg_room
    jsr enter_room
+
}
    jsr candle_update
    jsr player_update
    jsr enemies_update
    jsr item_update
    jsr clock_check
    jsr storm_update
    jsr rain_update
    jsr sprites_build
    jsr hud_update
    lda game_over
    beq game_loop
    cmp #1
    bne +
    jmp clock_strikes
+   ; fainted: a last scream
    lda #SFX_HIT
    jsr sfx_play
    ldx #50
-   stx tmp5
    jsr wait_frame
    ldx tmp5
    dex
    bne -
    lda #0
    sta $d015
    rts

; the winning moment: every light in the room comes on and the bell tolls
!zone clock_strikes
clock_strikes:
    lda #0
    sta $d015
    sta mus_on
    lda #<msg_win
    ldx #>msg_win
    jsr show_message
    ldx #0
-   lda LIT_CHR,x
    sta SCREEN,x
    lda LIT_COL,x
    sta COLOR,x
    lda LIT_CHR+$100,x
    sta SCREEN+$100,x
    lda LIT_COL+$100,x
    sta COLOR+$100,x
    lda LIT_CHR+$200,x
    sta SCREEN+$200,x
    lda LIT_COL+$200,x
    sta COLOR+$200,x
    inx
    bne -
    ldx #0
-   lda LIT_CHR+$300,x
    sta SCREEN+$300,x
    lda LIT_COL+$300,x
    sta COLOR+$300,x
    inx
    cpx #112
    bne -
    lda #12
    sta tmp4
.bell:
    lda #SFX_BELL
    jsr sfx_play
    lda #1
    sta irq_d021
    jsr wait_frame
    jsr wait_frame
    lda #0
    sta irq_d021
    ldx #46
-   stx tmp5
    jsr wait_frame
    ldx tmp5
    dex
    bne -
    dec tmp4
    bne .bell
    rts

msg_start:  !scr "the gate slams shut!",0
msg_win:    !scr "twelve o'clock!",0
msg_candle: !scr "a fresh candle!",0
msg_part:   !scr "a clock part!",0
msg_eek:    !scr "eeek!",0
msg_bat:    !scr "a bat! your wax!",0
msg_boom:   !scr "boom! crash!",0
msg_dark:   !scr "your candle is out!",0
msg_clock0: !scr "it needs four parts.",0
msg_snuff:  !scr "too dark! too dark!",0
msg_help:   !scr "help! up here!",0
msg_glint:  !scr "a clock part is here!",0
msg_keep:   !scr "brooke: keep it up...",0
msg_nowax:  !scr "brooke: find a candle!",0
msg_hold:   !scr "hold fire or space!",0
msg_thanks: !scr "brooke: take this key!",0
msg_waits:  !scr "brooke waits for you.",0

; ---- rooms ------------------------------------------------------------
!zone enter_room
enter_room:
    lda #0
    sta $d015
    ldx #7
-   sta S_ON,x
    dex
    bpl -
    ldx room
    lda room_d022,x
    sta cur_d022
    lda room_d023,x
    sta cur_d023
    lda room_dim,x
    sta cur_dim
    lda room_lit,x
    sta cur_lit
    sta has_rain
    beq +
    lda #6              ; outdoor charset at $5800
    bne ++
+   lda #2              ; indoor charset at $4800
++  sta cur_d018
    ; map pointer: $8800 + room*220
    lda #<ROOMDATA
    sta ptr
    lda #>ROOMDATA
    sta ptr+1
    ldx room
    beq .gotmap
-   lda ptr
    clc
    adc #220
    sta ptr
    bcc +
    inc ptr+1
+   dex
    bne -
.gotmap:
    ldy #219
-   lda (ptr),y
    sta MAP,y
    dey
    cpy #$ff
    bne -
    ; expand metatiles into the lit buffers
    lda #<LIT_CHR
    sta ptr
    lda #>LIT_CHR
    sta ptr+1
    lda #<LIT_COL
    sta ptr2
    lda #>LIT_COL
    sta ptr2+1
    ldx #0
    lda #11
    sta tmp2
.row:
    ldy #0
.col:
    sty tmp
    stx tmp3
    lda MAP,x
    tax
    lda tile_tl,x
    sta (ptr),y
    lda tile_col,x
    sta (ptr2),y
    iny
    lda tile_tr,x
    sta (ptr),y
    lda tile_col,x
    sta (ptr2),y
    tya
    clc
    adc #40
    tay
    lda tile_br,x
    sta (ptr),y
    lda tile_col,x
    sta (ptr2),y
    dey
    lda tile_bl,x
    sta (ptr),y
    lda tile_col,x
    sta (ptr2),y
    ldx tmp3
    inx
    ldy tmp
    iny
    iny
    cpy #40
    bne .col
    lda ptr
    clc
    adc #80
    sta ptr
    sta ptr2
    bcc +
    inc ptr+1
    inc ptr2+1
+   dec tmp2
    bne .row
    ; paint it
    lda cur_lit
    bne .paint_lit
    ldx #0
-   lda LIT_CHR,x
    ora #$80
    sta SCREEN,x
    lda LIT_CHR+$100,x
    ora #$80
    sta SCREEN+$100,x
    lda LIT_CHR+$200,x
    ora #$80
    sta SCREEN+$200,x
    lda cur_dim
    sta COLOR,x
    sta COLOR+$100,x
    sta COLOR+$200,x
    inx
    bne -
-   lda LIT_CHR+$300,x
    ora #$80
    sta SCREEN+$300,x
    lda cur_dim
    sta COLOR+$300,x
    inx
    cpx #112
    bne -
    jmp .painted
.paint_lit:
    ldx #0
-   lda LIT_CHR,x
    sta SCREEN,x
    lda LIT_CHR+$100,x
    sta SCREEN+$100,x
    lda LIT_CHR+$200,x
    sta SCREEN+$200,x
    lda LIT_COL,x
    sta COLOR,x
    lda LIT_COL+$100,x
    sta COLOR+$100,x
    lda LIT_COL+$200,x
    sta COLOR+$200,x
    inx
    bne -
-   lda LIT_CHR+$300,x
    sta SCREEN+$300,x
    lda LIT_COL+$300,x
    sta COLOR+$300,x
    inx
    cpx #112
    bne -
.painted:
    ; light: everything dark, force a redraw
    ldx #21
    lda #0
-   sta CUR_L,x
    sta CUR_R,x
    dex
    bpl -
    lda #$ff
    sta last_cx
    ; remember the way in, for falls
    lda px
    sta entry_x
    lda px+1
    sta entry_x+1
    lda py
    sta entry_y
    jsr spawn_enemies
    ; item
    ldx room
    lda #$ff
    sta item_type
    lda ITEM_GONE,x
    bne +
    lda room_item,x
    sta item_type
    lda room_item_x,x
    sta item_x
    lda room_item_xh,x
    sta item_x+1
    lda room_item_y,x
    sta item_y
+   ; name in the HUD
    ldx #39
    lda #32
-   sta HUD_ROW2,x
    dex
    bpl -
    ldx room
    lda room_name_lo,x
    sta ptr
    lda room_name_hi,x
    sta ptr+1
    lda #<(HUD_ROW2+1)
    sta ptr2
    lda #>(HUD_ROW2+1)
    sta ptr2+1
    lda #7
    jsr print
    lda #0
    sta msg_timer
    sta brooke_said
    ; a clock part in this room?
    lda item_type
    cmp #4
    bcs +
    lda #<msg_glint
    ldx #>msg_glint
    jmp show_message
+   ; Brooke calls out
    lda E_TYPE+1
    cmp #3
    bne .quiet
    lda rescued
    bne +
    lda #<msg_help
    ldx #>msg_help
    jmp show_message
+   lda #<msg_waits
    ldx #>msg_waits
    jmp show_message
.quiet:
    rts

; ---- tile lookups -------------------------------------------------------
; in: tx (16 bit), ty; out: A = tile flags, zero for anything off-screen
!zone probe
probe:
    lda tx+1
    beq +
    cmp #1
    bne .off
    lda tx
    cmp #64             ; x >= 320
    bcs .off
+   lda ty
    cmp #176
    bcs .off
    lsr
    lsr
    lsr
    lsr
    tay
    lda tx+1
    lsr
    lda tx
    ror
    lsr
    lsr
    lsr                 ; A = column 0-19
    clc
    adc row20,y
    tay
    lda MAP,y
    tay
    lda tile_flags,y
    rts
.off:
    lda #0
    rts

!zone row20
row20:
    !byte 0,20,40,60,80,100,120,140,160,180,200

; set tx = px + A
!zone set_tx
set_tx:
    clc
    adc px
    sta tx
    lda px+1
    adc #0
    sta tx+1
    rts

; ---- the player ------------------------------------------------------
!zone player_update
player_update:
    lda invuln
    beq +
    dec invuln
+   lda on_ladder
    beq .walk
    jmp ladder_update
.walk:
    ; horizontal: 1.5 pixels per frame, tested one pixel at a time
    lda frame
    and #1
    clc
    adc #1
    sta tmp4
    lda joy
    and #J_LEFT
    beq .noleft
    lda #1
    sta facing
.lstep:
    jsr try_left
    dec tmp4
    bne .lstep
    jmp .moved
.noleft:
    lda joy
    and #J_RIGHT
    beq .moved
    lda #0
    sta facing
.rstep:
    jsr try_right
    dec tmp4
    bne .rstep
.moved:
    jsr check_side_exits
    ; standing on something?
    lda vy+1
    bmi .air
    jsr feet_on_ground
    bcc .air
    lda #1
    sta grounded
    lda #0
    sta vy
    sta vy+1
    sta pys
    ; up: ladder or jump.  down: ladder below
    lda joy
    and #J_UP
    beq .nojump
    jsr ladder_here
    bcs .grab
    lda joy_prev        ; no auto-repeat jumps
    and #J_UP
    bne .nojump
    lda #<($10000-JUMP_V)
    sta vy
    lda #>($10000-JUMP_V)
    sta vy+1
    lda #0
    sta grounded
    lda #SFX_JUMP
    jsr sfx_play
    jmp .air2
.nojump:
    lda joy
    and #J_DOWN
    beq .done
    jsr ladder_below
    bcs .grab
.done:
    jmp player_anim
.grab:
    jmp grab_ladder
.air:
    lda #0
    sta grounded
    ; catching a ladder in mid-air
    lda joy
    and #J_UP|J_DOWN
    beq .air2
    jsr ladder_here
    bcs .grab
.air2:
    ; gravity
    lda vy
    clc
    adc #GRAVITY
    sta vy
    lda vy+1
    adc #0
    sta vy+1
    bmi +
    cmp #4
    bcc +
    lda #4
    sta vy+1
    lda #0
    sta vy
+   ; integrate
    lda pys
    clc
    adc vy
    sta pys
    lda #0
    adc vy+1
    sta tmp4            ; signed whole pixels this frame
    beq .vdone
    bmi .rise
.fall:
    jsr feet_on_ground
    bcs .land
    inc py
    dec tmp4
    bne .fall
    jmp .vdone
.land:
    lda #0
    sta vy
    sta vy+1
    sta pys
    lda #1
    sta grounded
    jmp .vdone
.rise:
    lda #7
    jsr set_tx
    lda py
    clc
    adc #1
    sta ty
    jsr probe
    and #TF_SOLID
    bne .bump
    lda #16
    jsr set_tx
    jsr probe
    and #TF_SOLID
    bne .bump
    dec py
    inc tmp4
    bne .rise
    jmp .vdone
.bump:
    lda #0
    sta vy
    sta vy+1
.vdone:
    jsr check_vert_exits
    jmp player_anim

; carry set if the player's feet rest on something at this exact y
!zone feet_on_ground
feet_on_ground:
    lda py
    clc
    adc #21
    sta ty
    lda #7
    jsr set_tx
    jsr probe
    jsr .eval
    bcs .yes
    lda #16
    jsr set_tx
    jsr probe
.eval:
    sta tmp
    and #TF_SOLID
    bne .yes
    lda tmp
    and #TF_PLATFORM|TF_LADDER
    beq .no
    lda ty              ; one-way: only the top pixel row of a tile counts
    and #15
    bne .no
.yes:
    sec
    rts
.no:
    clc
    rts

!zone try_left
try_left:
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
    bne .no
    lda tmp2
    sta px
    lda tmp3
    sta px+1
.no:
    rts

!zone try_right
try_right:
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
    bne .no
    lda tmp2
    sta px
    lda tmp3
    sta px+1
.no:
    rts

; in: tx; out: Z clear if a solid tile touches the body at that x
!zone body_blocked
body_blocked:
    lda py
    clc
    adc #3
    sta ty
    jsr probe
    and #TF_SOLID
    bne .out
    lda py
    clc
    adc #19
    sta ty
    jsr probe
    and #TF_SOLID
.out:
    rts

!zone check_side_exits
check_side_exits:
    lda px+1
    bmi .left           ; negative x
    cmp #1
    bne .none
    lda px
    cmp #<306
    bcc .none
    ldx room
    lda room_exit_r,x
    cmp #$ff
    beq .stopr
    sta room
    lda #<($10000-8)
    sta px
    lda #>($10000-8)
    sta px+1
    jmp enter_room
.stopr:
    lda #<305
    sta px
    lda #>305
    sta px+1
    rts
.left:
    lda px
    cmp #$f6            ; x < -10
    bcs .none
    ldx room
    lda room_exit_l,x
    cmp #$ff
    beq .stopl
    sta room
    lda #<304
    sta px
    lda #>304
    sta px+1
    jmp enter_room
.stopl:
    lda #$f6
    sta px
.none:
    rts

!zone check_vert_exits
check_vert_exits:
    lda py
    cmp #224            ; 224-255 means above the screen
    bcc .below
    cmp #244            ; py < -12: through the ceiling
    bcs .none
    ldx room
    lda room_exit_u,x
    cmp #$ff
    beq .stopu
    sta room
    lda py
    clc
    adc #176
    sta py
    jmp enter_room
.stopu:
    lda #244
    sta py
    lda #0
    sta vy
    sta vy+1
    rts
.below:
    cmp #170
    bcc .none
    ldx room
    lda room_exit_d,x
    cmp #$ff
    beq .pit
    sta room
    lda py
    sec
    sbc #176
    sta py
    jmp enter_room
.pit:                   ; should not happen: back to the room's entrance
    lda entry_x
    sta px
    lda entry_x+1
    sta px+1
    lda entry_y
    sta py
    lda #1
    jmp hurt_player
.none:
    rts

; carry set when a ladder overlaps the player's middle
!zone ladder_here
ladder_here:
    lda #12
    jsr set_tx
    lda py
    clc
    adc #10
    sta ty
    jsr probe
    and #TF_LADDER
    bne .yes
    lda py
    clc
    adc #20
    sta ty
    jsr probe
    and #TF_LADDER
    bne .yes
    clc
    rts
.yes:
    sec
    rts

!zone ladder_below
ladder_below:
    lda #12
    jsr set_tx
    lda py
    clc
    adc #21
    sta ty
    cmp #176            ; below the last row: the ladder carries on in the next room
    bcs .yes
    jsr probe
    and #TF_LADDER
    bne .yes
    clc
    rts
.yes:
    sec
    rts

; centre the player on the ladder column
!zone grab_ladder
grab_ladder:
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
    and #$f0
    sec
    sbc #4
    sta px
    lda tmp2
    sbc #0
    sta px+1
    jmp player_anim

!zone ladder_update
ladder_update:
    lda joy
    and #J_LEFT|J_RIGHT
    beq .stay
    ; stepping off sideways
    lda #0
    sta on_ladder
    jmp player_anim
.stay:
    lda joy
    and #J_UP
    beq .noup
    jsr ladder_here
    bcc .off
    dec py
    jsr check_vert_exits
    jmp player_anim
.noup:
    lda joy
    and #J_DOWN
    beq .idle
    ; blocked by the floor?
    jsr feet_on_solid
    bcs .off
    jsr ladder_below
    bcc .off
    inc py
    jsr check_vert_exits
.idle:
    jmp player_anim
.off:
    lda #0
    sta on_ladder
    jmp player_anim

!zone feet_on_solid
feet_on_solid:
    lda py
    clc
    adc #21
    sta ty
    lda #12
    jsr set_tx
    jsr probe
    and #TF_SOLID
    beq .no
    sec
    rts
.no:
    clc
    rts

; choose the sprite frame
!zone player_anim
player_anim:
    lda on_ladder
    beq +
    lda py
    lsr
    lsr
    lsr
    and #1
    clc
    adc #5
    sta pframe
    rts
+   lda grounded
    bne +
    lda #4
    sta pframe
    rts
+   lda joy
    and #J_LEFT|J_RIGHT
    bne +
    lda #0
    sta pframe
    rts
+   lda frame
    lsr
    lsr
    and #3
    tax
    lda run_cycle,x
    sta pframe
    rts
!zone run_cycle
run_cycle:
    !byte 1,2,3,2

; A = fear points lost
!zone hurt_player
hurt_player:
    sta tmp
    lda invuln
    bne .out
    lda #120
    sta invuln
    lda nerve
    sec
    sbc tmp
    bcs +
    lda #0
+   sta nerve
    bne +
    lda #2
    sta game_over
+   lda #1
    sta hud_dirty
    lda #2
    sta red_flash
    lda #SFX_HIT
    jsr sfx_play
    lda #<msg_eek
    ldx #>msg_eek
    jmp show_message
.out:
    rts

; ---- the candle --------------------------------------------------------
!zone candle_update
candle_update:
    ; fire held: flare, while there is wax
    lda #0
    sta flare
    lda wax
    beq .noflare
    lda joy
    and #J_FIRE
    beq .noflare
    lda #1
    sta flare
.noflare:
    ; burning
    lda cur_lit
    bne .burnt          ; moonlit rooms: the candle is shielded
    inc wax_tick
    lda flare
    beq +
    lda wax_tick
    and #7
    bne .burnt
    jmp .burn
+   lda wax_tick
    cmp #90
    bcc .burnt
.burn:
    lda #0
    sta wax_tick
    lda wax
    beq .burnt
    dec wax
    bne +
    lda #<msg_dark
    ldx #>msg_dark
    jsr show_message
+   lda #1
    sta hud_dirty
.burnt:
    ; no light at all wears your nerve down
    lda wax
    bne .nodark
    lda cur_lit
    bne .nodark
    inc dark_tick
    bne .nodark
    lda #<msg_snuff
    ldx #>msg_snuff
    jsr show_message
    lda invuln
    bne .nodark
    lda #1
    jsr hurt_player
.nodark:
    ; radius from wax left
    lda wax
    beq .r0
    cmp #9
    bcc .r1
    cmp #24
    bcc .r2
    cmp #44
    bcc .r3
    lda #7
    bne .rr
.r3:
    lda #6
    bne .rr
.r2:
    lda #5
    bne .rr
.r1:
    lda #4
    bne .rr
.r0:
    lda #2
.rr:
    sta radius
    ; flicker
    lda frame
    and #7
    bne +
    jsr random
    and #1
    sta flick
+   lda radius
    clc
    adc flick
    ldx flare
    beq +
    clc
    adc #2
+   cmp #9
    bcc +
    lda #8
+   sta radius
    ; centre of the light: the player's chest, in chars
    lda px
    clc
    adc #12
    sta tmp
    lda px+1
    adc #0
    lsr
    lda tmp
    ror
    lsr
    lsr
    sta cx
    lda px+1
    bpl +
    lda #0
    sta cx
+   lda py
    clc
    adc #8
    cmp #224
    bcc +
    lda #0
+   lsr
    lsr
    lsr
    cmp #22
    bcc +
    lda #21
+   sta cy
    rts

; Updates only cells whose lit state changes, so a step costs almost nothing.
!zone light_update
light_update:
    lda cur_lit
    beq +
    rts
+   lda radius
    cmp last_r
    bne .changed
    lda cx
    cmp last_cx
    bne .changed
    lda cy
    cmp last_cy
    bne .changed
    rts
.changed:
    lda radius
    sta last_r
    lda cx
    sta last_cx
    lda cy
    sta last_cy
    ; disc row for this radius: table is radius*9
    ldx radius
    lda #0
    cpx #0
    beq +
    clc
-   adc #9
    dex
    bne -
+   clc
    adc #<disc_table
    sta ptr4
    lda #>disc_table
    adc #0
    sta ptr4+1
    lda #0
    sta tmp5            ; row
.rowloop:
    ; new span for this row
    ldx tmp5
    lda tmp5
    sec
    sbc cy
    bcs +
    eor #$ff
    adc #1
+   cmp #9
    bcs .empty
    tay
    lda (ptr4),y
    cmp #$ff
    beq .empty
    sta tmp             ; half width
    lda cx
    sec
    sbc tmp
    bcs +
    lda #0
+   sta tmp2            ; new left
    lda cx
    sec
    adc tmp             ; cx + hw + 1
    cmp #40
    bcc +
    lda #40
+   sta tmp3            ; new right (exclusive)
    jmp .have
.empty:
    lda #0
    sta tmp2
    sta tmp3
.have:
    lda tmp2
    cmp CUR_L,x
    bne .diff
    lda tmp3
    cmp CUR_R,x
    bne .diff
    jmp .next
.diff:
    ; set the row pointers (all buffers are page aligned)
    lda scr_lo,x
    sta ptr
    sta ptr2
    sta ptr3
    lda scr_hi,x
    clc
    adc #>SCREEN
    sta ptr+1
    adc #>(COLOR-SCREEN)
    sta ptr2+1
    lda scr_hi,x
    clc
    adc #>LIT_CHR
    sta ptr3+1
    ; cells leaving the light
    lda CUR_R,x
    sta tmp4
    ldy CUR_L,x
.dark_loop:
    cpy tmp4
    bcs .dark_done
    cpy tmp2
    bcc .make_dark
    cpy tmp3
    bcc .dark_skip
.make_dark:
    lda (ptr3),y
    ora #$80
    sta (ptr),y
    lda cur_dim
    sta (ptr2),y
.dark_skip:
    iny
    bne .dark_loop
.dark_done:
    ; cells entering the light
    lda ptr
    sta ptr5
    lda scr_hi,x
    clc
    adc #>LIT_COL
    sta ptr5+1
    ldy tmp2
.lit_loop:
    cpy tmp3
    bcs .lit_done
    tya
    cmp CUR_L,x
    bcc .make_lit
    cmp CUR_R,x
    bcc .lit_skip
.make_lit:
    lda (ptr3),y
    sta (ptr),y
    lda (ptr5),y
    sta (ptr2),y
.lit_skip:
    iny
    bne .lit_loop
.lit_done:
    lda tmp2
    sta CUR_L,x
    lda tmp3
    sta CUR_R,x
.next:
    inc tmp5
    lda tmp5
    cmp #22
    beq +
    jmp .rowloop
+   rts

!zone scr_lo
scr_lo:
    !for r, 0, 24 { !byte <(r*40) }
!zone scr_hi
scr_hi:
    !for r, 0, 24 { !byte >(r*40) }

; A,X = sprite x (16 bit in tx), Y = sprite y in ty: is that point in the light?
; out: carry set when lit. Moonlit rooms are always lit.
!zone in_light
in_light:
    lda cur_lit
    bne .yes
    lda flash
    bne .yes
    lda tx+1
    lsr
    lda tx
    ror
    lsr
    lsr                 ; to chars
    sec
    sbc cx
    bcs +
    eor #$ff
    adc #1
+   sta tmp2            ; |dx|
    lda ty
    lsr
    lsr
    lsr
    sec
    sbc cy
    bcs +
    eor #$ff
    adc #1
+   cmp #9
    bcs .no
    cmp radius
    beq +
    bcs .no
+   sta tmp3
    ; compare with the disc half width at this |dy|
    lda radius
    asl
    asl
    asl
    adc radius          ; radius*9 (max 72, no carry)
    adc tmp3
    tay
    lda disc_table,y
    cmp tmp2
    bcc .no
.yes:
    sec
    rts
.no:
    clc
    rts

; ---- enemies --------------------------------------------------------
!zone spawn_enemies
spawn_enemies:
    ldx room
    lda room_e0_type,x
    sta E_TYPE
    lda room_e1_type,x
    sta E_TYPE+1
    lda room_e0_x,x
    sta E_X
    lda room_e1_x,x
    sta E_X+1
    lda room_e0_xh,x
    sta E_XH
    lda room_e1_xh,x
    sta E_XH+1
    lda room_e0_y,x
    sta E_Y
    sta E_HOME
    lda room_e1_y,x
    sta E_Y+1
    sta E_HOME+1
    ldx #1
-   lda #0
    sta E_FLEE,x
    sta E_DIR,x
    lda rng
    sta E_T,x
    jsr random
    lda E_TYPE,x        ; Brooke stays exactly where she is
    cmp #3
    bne +
    jmp .far
+   ; never spawn on top of the player: jump half a screen away
    lda E_X,x
    sec
    sbc px
    sta tmp
    lda E_XH,x
    sbc px+1
    bmi .neg
    bne .far
    lda tmp
    cmp #80
    bcs .far
    bcc .move
.neg:
    cmp #$ff
    bne .far
    lda tmp
    cmp #$b0
    bcc .far
.move:
    lda E_X,x
    clc
    adc #160
    sta E_X,x
    lda E_XH,x
    adc #0
    sta E_XH,x
    cmp #1
    bne .far
    lda E_X,x
    cmp #40
    bcc .far
    sec
    sbc #40
    sta E_X,x
    lda #0
    sta E_XH,x
.far:
    dex
    bmi +
    jmp -
+   ; once rescued she leaves the Bedroom and waits by the clock
    lda rescued
    beq .out
    lda #$ff
    ldx room
    cpx #BROOKE_ROOM
    bne +
    sta E_TYPE+1
    rts
+   cpx #HALL_ROOM
    bne .out
    lda #3
    sta E_TYPE+1
    lda #160
    sta E_X+1
    lda #0
    sta E_XH+1
    lda #139
    sta E_Y+1
.out:
    rts

!zone enemies_update
enemies_update:
    ldx #0
    jsr enemy_one
    ldx #1
    ; fall through
!zone enemy_one
enemy_one:
    lda E_TYPE,x
    cmp #$ff
    bne +
    rts
+   inc E_T,x
    cmp #0
    bne +
    jmp ghost_update
+   cmp #1
    bne +
    jmp bat_update
+   cmp #2
    bne +
    jmp wolf_update
+   jmp brooke_update

; sets carry when the player's flare scares this enemy. Uses tmp2/tmp3.
!zone flare_scares
flare_scares:
    lda flare
    beq .no
    lda E_X,x
    sec
    sbc px
    sta tmp2
    lda E_XH,x
    sbc px+1
    beq .pos
    cmp #$ff
    bne .no
    lda tmp2
    eor #$ff
    clc
    adc #1
    sta tmp2
    beq .no
.pos:
    lda tmp2
    cmp #64
    bcs .no
    lda E_Y,x
    sec
    sbc py
    bcs +
    eor #$ff
    adc #1
+   cmp #56
    bcs .no
    sec
    rts
.no:
    clc
    rts

; carry set when enemy X is at or to the right of the player (signed 16-bit)
!zone enemy_cmp
enemy_cmp:
    lda E_X,x
    cmp px
    lda E_XH,x
    sbc px+1
    bvc +
    eor #$80
+   bmi .less
    sec
    rts
.less:
    clc
    rts

; one pixel towards (A=0) or away from (A=1) the player
!zone step_x
step_x:
    sta tmp
    jsr enemy_cmp
    lda #0
    rol                 ; 1 = enemy is on the right
    eor tmp             ; 1 = decrease x
    bne .dec
    inc E_X,x
    bne +
    inc E_XH,x
+   rts
.dec:
    lda E_X,x
    bne +
    dec E_XH,x
+   dec E_X,x
    rts

!zone ghost_update
ghost_update:
    lda E_FLEE,x
    beq .hunt
    dec E_FLEE,x
    ; flee fast, and off the edges they sink through the walls
    lda #1
    jsr step_x
    lda #1
    jsr step_x
    jsr ghost_y_away
    jsr clamp_enemy
    jmp .draw
.hunt:
    jsr flare_scares
    bcc .chase
    lda #60
    sta E_FLEE,x
    lda #SFX_WAIL
    jsr sfx_play
    jmp .draw
.chase:
    lda E_T,x
    and #1
    bne .draw
    lda #0
    jsr step_x
    ; vertical chase
    lda E_Y,x
    cmp py
    beq .draw
    bcc +
    dec E_Y,x
    jmp .draw
+   inc E_Y,x
.draw:
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

!zone ghost_y_away
ghost_y_away:
    lda E_Y,x
    cmp py
    bcc +
    inc E_Y,x
    rts
+   dec E_Y,x
    rts

!zone clamp_enemy
clamp_enemy:
    lda E_XH,x
    bmi .low
    cmp #1
    bne .y
    lda E_X,x
    cmp #40
    bcc .y
    lda #40
    sta E_X,x
    bne .y
.low:
    lda #0
    sta E_X,x
    sta E_XH,x
.y: lda E_Y,x
    cmp #240
    bcs .ylow
    cmp #156
    bcc .out
    lda #156
    sta E_Y,x
.out:
    rts
.ylow:
    lda #0
    sta E_Y,x
    rts

!zone bob_table
bob_table:
    !byte 0,1,2,3,3,3,2,1,0,$ff,$fe,$fd,$fd,$fd,$fe,$ff

!zone bat_update
bat_update:
    ; swoops along in a wave and turns at the walls
    lda E_FLEE,x
    beq +
    dec E_FLEE,x
    jmp .fly
+   jsr flare_scares
    bcc .fly
    lda #40
    sta E_FLEE,x
    jsr enemy_cmp
    lda #0
    rol
    eor #1              ; head away from the player
    sta E_DIR,x
.fly:
    lda E_DIR,x
    bne .left
    lda E_X,x
    clc
    adc #2
    sta E_X,x
    lda E_XH,x
    adc #0
    sta E_XH,x
    beq .wave
    lda E_X,x
    cmp #36
    bcc .wave
    lda #1
    sta E_DIR,x
    bne .wave
.left:
    lda E_X,x
    sec
    sbc #2
    sta E_X,x
    lda E_XH,x
    sbc #0
    sta E_XH,x
    bpl .wave
    lda #0
    sta E_X,x
    sta E_XH,x
    sta E_DIR,x
.wave:
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

!zone bat_wave
bat_wave:
    !byte 0,3,6,9,11,13,15,16,16,16,15,13,11,9,6,3
    !byte 0,$fd,$fa,$f7,$f5,$f3,$f1,$f0,$f0,$f0,$f1,$f3,$f5,$f7,$fa,$fd

!zone wolf_update
wolf_update:
    lda E_FLEE,x
    beq +
    dec E_FLEE,x
    jmp .walk
+   jsr flare_scares
    bcc .walk
    lda #45
    sta E_FLEE,x
    jsr enemy_cmp
    lda #0
    rol
    eor #1
    sta E_DIR,x
    lda #SFX_WAIL
    jsr sfx_play
.walk:
    ; walks at 1 px/frame; scared wolves run at 2
    jsr wolf_step
    lda E_FLEE,x
    beq +
    jsr wolf_step
+   lda E_Y,x
    sta E_DRAWY,x
    jmp touch_check

!zone wolf_step
wolf_step:
    lda E_DIR,x
    bne .left
    lda E_X,x
    clc
    adc #1
    sta E_X,x
    lda E_XH,x
    adc #0
    sta E_XH,x
    ; ahead: right edge
    lda E_X,x
    clc
    adc #20
    jmp .check
.left:
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
.check:
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
    beq .turn
    ldx tmp5
    lda E_Y,x
    clc
    adc #10
    sta ty
    jsr probe
    and #TF_SOLID
    bne .turn
    ; stay on screen
    ldx tmp5
    lda E_XH,x
    bmi .turn
    cmp #1
    bne .ok
    lda E_X,x
    cmp #24
    bcs .turn
.ok:
    rts
.turn:
    ldx tmp5
    lda E_DIR,x
    eor #1
    sta E_DIR,x
    rts

; Brooke is afraid of the dark: keep the candle raised beside her and she
; finds the courage to hand over the winding key
!zone brooke_update
brooke_update:
    lda E_Y,x
    sta E_DRAWY,x
    jsr enemy_cmp
    lda #0
    rol
    sta E_DIR,x
    lda rescued
    beq +
    lda #0              ; calm now: stop trembling
    sta E_T,x
    rts
+   lda E_X,x
    sec
    sbc px
    tay
    lda E_XH,x
    sbc px+1
    beq .pos
    cmp #$ff
    bne .out
    tya
    eor #$ff
    clc
    adc #1
    tay
    beq .out
.pos:
    cpy #40
    bcs .out
    lda E_Y,x
    sec
    sbc py
    bcs +
    eor #$ff
    adc #1
+   cmp #24
    bcs .out
    lda flare
    bne .lighting
    lda msg_timer       ; say it when the row is free, or straight away on arrival
    beq .say
    lda brooke_said
    bne .out
.say:
    lda #1
    sta brooke_said
    lda wax
    bne +
    lda #<msg_nowax
    ldx #>msg_nowax
    jmp show_message
+   lda #<msg_hold
    ldx #>msg_hold
    jmp show_message
.lighting:
    lda brooke_said
    cmp #2
    beq +
    lda #2
    sta brooke_said
    lda #<msg_keep
    ldx #>msg_keep
    jsr show_message
+   inc rescue_t
    lda rescue_t
    cmp #100
    bcs .saved
    and #15
    bne .out
    lda #SFX_CANDLE
    jmp sfx_play
.saved:
    lda #1
    sta rescued
    sta hud_dirty
    lda parts
    ora #8
    sta parts
    lda #SFX_PART
    jsr sfx_play
    lda #<msg_thanks
    ldx #>msg_thanks
    jmp show_message
.out:
    rts

; did this enemy catch the player?
!zone touch_check
touch_check:
    lda E_X,x
    sec
    sbc px
    tay
    lda E_XH,x
    sbc px+1
    beq .pos
    cmp #$ff
    bne .miss
    tya
    eor #$ff
    clc
    adc #1
    tay
    beq .miss
.pos:
    cpy #13
    bcs .miss
    lda E_DRAWY,x
    sec
    sbc py
    bcs +
    eor #$ff
    adc #1
+   cmp #14
    bcs .miss
    lda invuln
    bne .miss
    lda E_TYPE,x
    cmp #1
    beq .batbite
    cmp #2
    beq .wolfbite
    stx tmp5
    lda #1
    jsr hurt_player
    ldx tmp5
    lda #70
    sta E_FLEE,x
    rts
.wolfbite:
    stx tmp5
    lda #2
    jsr hurt_player
    ldx tmp5
    rts
.batbite:
    ; bats go for the candle: wax rather than nerve
    lda wax
    sec
    sbc #12
    bcs +
    lda #0
+   sta wax
    lda #60
    sta invuln
    lda #1
    sta hud_dirty
    lda #40
    sta E_FLEE,x
    stx tmp5
    lda #SFX_HIT
    jsr sfx_play
    lda #<msg_bat
    ldx #>msg_bat
    jsr show_message
    ldx tmp5
.miss:
    rts

; ---- pick-ups --------------------------------------------------------
!zone item_update
item_update:
    lda item_type
    cmp #$ff
    beq .out
    lda item_x
    sec
    sbc px
    tay
    lda item_x+1
    sbc px+1
    beq .pos
    cmp #$ff
    bne .out
    tya
    eor #$ff
    clc
    adc #1
    tay
    beq .out
.pos:
    cpy #16
    bcs .out
    lda item_y
    sec
    sbc py
    bcs +
    eor #$ff
    adc #1
+   cmp #18
    bcs .out
    ; got it
    lda item_type
    cmp #4
    beq .candle
    tax
    lda part_bits,x
    ora parts
    sta parts
    ldx room
    lda #1
    sta ITEM_GONE,x
    lda #$ff
    sta item_type
    sta hud_dirty
    lda #SFX_PART
    jsr sfx_play
    lda #<msg_part
    ldx #>msg_part
    jmp show_message
.candle:
    lda #WAX_FULL
    sta wax
    lda #1
    sta hud_dirty
    lda #$ff
    sta item_type
    ; the hall's candle box never runs out
    ldx room
    cpx #HALL_ROOM
    beq +
    lda #1
    sta ITEM_GONE,x
+   lda #SFX_CANDLE
    jsr sfx_play
    lda #<msg_candle
    ldx #>msg_candle
    jmp show_message
.out:
    rts

!zone part_bits
part_bits:
    !byte 1,2,4,8

; walking into the clock
!zone clock_check
clock_check:
    lda clock_cd
    beq +
    dec clock_cd
+   lda #12
    jsr set_tx
    lda py
    clc
    adc #10
    sta ty
    jsr probe
    and #TF_CLOCK
    beq .out
    lda parts
    cmp #15
    bne .notyet
    lda #1
    sta game_over
    rts
.notyet:
    lda clock_cd
    bne .out
    lda #200
    sta clock_cd
    lda #<msg_clock0
    ldx #>msg_clock0
    jmp show_message
.out:
    rts

; ---- storm ------------------------------------------------------------
!zone storm_update
storm_update:
    lda flash
    beq .waiting
    dec flash
    ldx flash
    lda flash_seq,x
    sta flash_col
    jmp .apply
.waiting:
    lda #0
    sta flash_col
    lda thunder_t
    bne +
    dec thunder_t+1
+   dec thunder_t
    lda thunder_t
    ora thunder_t+1
    bne .apply
    ; strike! next one in 6-11 seconds, in the rooms that feel it
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
    jsr show_message
.apply:
    lda red_flash
    beq +
    dec red_flash
    lda #2
    sta irq_d021
    rts
+   lda flash_col
    sta irq_d021
    rts

!zone flash_seq
flash_seq:
    !byte 0,1,1,0,0,1,15,1

; rotate the rain tile's chars downward
!zone rain_update
rain_update:
    lda has_rain
    beq .out
    lda frame
    and #1
    bne .out
    jsr .rot_tr
    jmp .rot_tl
.out:
    rts
.rot_tl:
    ldx #<(CHAR_OUT+RAIN_TL*8)
    ldy #>(CHAR_OUT+RAIN_TL*8)
    stx ptr
    sty ptr+1
    ldx #<(CHAR_OUT+RAIN_BL*8)
    ldy #>(CHAR_OUT+RAIN_BL*8)
    stx ptr2
    sty ptr2+1
    jmp rot_col
.rot_tr:
    ldx #<(CHAR_OUT+RAIN_TR*8)
    ldy #>(CHAR_OUT+RAIN_TR*8)
    stx ptr
    sty ptr+1
    ldx #<(CHAR_OUT+RAIN_BR*8)
    ldy #>(CHAR_OUT+RAIN_BR*8)
    stx ptr2
    sty ptr2+1
    ; fall through
!zone rot_col
rot_col:
    ; 16 rows spread over two chars, rotated down by 2 rows
    ldy #7
-   lda (ptr),y
    sta ROT_BUF,y
    lda (ptr2),y
    sta ROT_BUF+8,y
    dey
    bpl -
    ldx #0
.r: txa
    clc
    adc #2
    and #15
    cmp #8
    bcs .low
    tay
    lda ROT_BUF,x
    sta (ptr),y
    jmp .n
.low:
    sbc #8
    tay
    lda ROT_BUF,x
    sta (ptr2),y
.n: inx
    cpx #16
    bne .r
    rts

; ---- sprites ----------------------------------------------------------
; slots: 0 player ink, 1 player fill, 2 flame, 3 item
;        4 enemy0 ink, 5 enemy0 fill, 6 enemy1 ink, 7 enemy1 fill
!zone sprites_build
sprites_build:
    ; player
    lda px
    clc
    adc #24
    sta S_X
    sta S_X+1
    lda px+1
    adc #0
    sta S_XH
    sta S_XH+1
    lda py
    clc
    adc #50
    sta S_Y
    sta S_Y+1
    ; blink while invulnerable
    lda invuln
    and #4
    beq +
    lda #0
    sta S_ON
    sta S_ON+1
    sta S_ON+2
    jmp .enemies
+   lda #1
    sta S_ON
    sta S_ON+1
    lda pframe
    asl
    ldx facing
    beq +
    clc
    adc #14
+   clc
    adc #SP_PLAYER+SPR_BASE
    sta S_PTR
    adc #1
    sta S_PTR+1
    lda #0
    sta S_COL
    lda #7
    sta S_COL+1
    ; flame: above the candle, unless climbing or snuffed out
    lda #0
    sta S_ON+2
    lda wax
    beq .enemies
    lda pframe
    cmp #5
    bcs .enemies
    lda #1
    sta S_ON+2
    lda frame
    lsr
    lsr
    and #1
    ldx flare
    beq +
    lda #2
+   clc
    adc #SP_FLAME+SPR_BASE
    sta S_PTR+2
    lda #7
    sta S_COL+2
    lda S_Y
    clc
    adc #$fd            ; 3 above the sprite top + 11-row flame
    sta S_Y+2
    ; the candle is at the front hand
    lda facing
    beq .fr
    lda S_X
    sec
    sbc #10
    sta S_X+2
    lda S_XH
    sbc #0
    sta S_XH+2
    jmp .enemies
.fr:
    lda S_X
    clc
    adc #10
    sta S_X+2
    lda S_XH
    adc #0
    sta S_XH+2
.enemies:
    ; item
    lda #0
    sta S_ON+3
    lda item_type
    cmp #$ff
    beq .noitem
    lda item_x
    clc
    adc #24
    sta S_X+3
    sta tx
    lda item_x+1
    adc #0
    sta S_XH+3
    lda item_x
    clc
    adc #12
    sta tx
    lda item_x+1
    adc #0
    sta tx+1
    lda item_y
    clc
    adc #10
    sta ty
    lda item_y
    clc
    adc #50
    sta S_Y+3
    jsr in_light
    bcc .glint
    lda item_type
    clc
    adc #SP_ITEM+SPR_BASE
    sta S_PTR+3
    lda #1
    sta S_ON+3
    lda frame
    lsr
    lsr
    lsr
    and #3
    tax
    lda item_cols,x
    sta S_COL+3
    jmp .noitem
.glint:
    lda frame
    and #31
    cmp #8
    bcs .noitem
    lda #SP_ITEM+5+SPR_BASE
    sta S_PTR+3
    lda #1
    ldx item_type
    cpx #4
    bcc +
    lda #7
+   sta S_COL+3
    lda #1
    sta S_ON+3
.noitem:
    ldx #0
    jsr enemy_sprite
    ldx #1
    ; fall through
; enemy X into slots 4+2X (ink), 5+2X (fill)
!zone enemy_sprite
enemy_sprite:
    txa
    asl
    clc
    adc #4
    tay                 ; Y = ink slot
    lda #0
    sta S_ON,y
    sta S_ON+1,y
    lda E_TYPE,x
    cmp #$ff
    bne +
    rts
+   lda E_X,x
    clc
    adc #24
    sta S_X,y
    sta S_X+1,y
    lda E_XH,x
    adc #0
    sta S_XH,y
    sta S_XH+1,y
    lda E_DRAWY,x
    clc
    adc #50
    sta S_Y,y
    sta S_Y+1,y
    sty tmp5
    stx tmp4
    ; lit or just eyes?
    lda E_X,x
    clc
    adc #12
    sta tx
    lda E_XH,x
    adc #0
    sta tx+1
    lda E_DRAWY,x
    clc
    adc #10
    sta ty
    jsr in_light
    ldx tmp4
    ldy tmp5
    bcs .shown
    lda E_TYPE,x        ; Brooke is always visible: you can hear her too
    cmp #3
    bne .eyes
.shown:
    ; frame: base + dir*4 + anim*2
    lda E_TYPE,x
    tax
    lda enemy_base,x
    sta tmp
    lda enemy_fill,x
    sta S_COL+1,y
    ldx tmp4
    lda E_DIR,x
    beq +
    lda tmp
    clc
    adc #4
    sta tmp
+   lda E_T,x
    lsr
    lsr
    lsr
    and #1
    asl
    clc
    adc tmp
    sta S_PTR,y
    clc
    adc #1
    sta S_PTR+1,y
    lda #0
    sta S_COL,y
    lda #1
    sta S_ON,y
    sta S_ON+1,y
    rts
.eyes:
    ; blink now and then
    lda E_T,x
    and #$3f
    cmp #4
    bcc .closed
    lda E_TYPE,x
    tax
    lda enemy_eyes,x
    sta S_PTR+1,y
    lda enemy_eyecol,x
    sta S_COL+1,y
    lda #1
    sta S_ON+1,y
.closed:
    rts

!zone enemy_base
enemy_base:
    !byte SP_GHOST+SPR_BASE, SP_BAT+SPR_BASE, SP_WOLF+SPR_BASE, SP_BROOKE+SPR_BASE
!zone enemy_fill
enemy_fill:
    !byte 15, 11, 9, 7
!zone enemy_eyes
enemy_eyes:
    !byte SP_EYES+SPR_BASE, SP_EYES+1+SPR_BASE, SP_EYES+2+SPR_BASE
!zone enemy_eyecol
enemy_eyecol:
    !byte 1, 2, 7
!zone item_cols
item_cols:
    !byte 1, 7, 13, 7

; copy the shadows to the VIC while the beam is in the border
!zone sprites_write
sprites_write:
    lda #0
    sta tmp
    sta tmp2
    ldx #7
-   lda S_ON,x
    lsr
    rol tmp             ; enable bits
    lda S_XH,x
    lsr
    rol tmp2            ; x high bits
    dex
    bpl -
    ; tmp holds bit0 = slot 0 after the rols above
    ldx #0
    ldy #0
-   lda S_X,x
    sta $d000,y
    lda S_Y,x
    sta $d001,y
    lda S_COL,x
    sta $d027,x
    lda S_PTR,x
    sta SPRPTR,x
    iny
    iny
    inx
    cpx #8
    bne -
    lda tmp2
    sta $d010
    lda tmp
    sta $d015
    rts

; ---- HUD --------------------------------------------------------------
!zone hud_init
hud_init:
    ldx #39
-   lda #H_RULE
    sta HUD_ROW0,x
    lda #32
    sta HUD_ROW1,x
    sta HUD_ROW2,x
    lda #11
    sta HUDC_ROW0,x
    lda #1
    sta HUDC_ROW1,x
    sta HUDC_ROW2,x
    dex
    bpl -
    lda #<txt_wax
    sta ptr
    lda #>txt_wax
    sta ptr+1
    lda #<(HUD_ROW1+1)
    sta ptr2
    lda #>(HUD_ROW1+1)
    sta ptr2+1
    lda #15
    jsr print
    lda #<txt_nerve
    sta ptr
    lda #>txt_nerve
    sta ptr+1
    lda #<(HUD_ROW1+15)
    sta ptr2
    lda #>(HUD_ROW1+15)
    sta ptr2+1
    lda #15
    jsr print
    lda #<txt_clock
    sta ptr
    lda #>txt_clock
    sta ptr+1
    lda #<(HUD_ROW1+27)
    sta ptr2
    lda #>(HUD_ROW1+27)
    sta ptr2+1
    lda #15
    jsr print
    lda #1
    sta hud_dirty
    ; fall through to draw the values now
!zone hud_draw
hud_draw:
    lda #0
    sta hud_dirty
    ; wax gauge: 8 chars at col 5
    lda wax
    sta tmp
    ldx #0
-   lda tmp
    cmp #8
    bcc +
    lda #8
+   sta tmp2
    clc
    adc #H_GAUGE
    sta HUD_ROW1+5,x
    lda #7
    ldy wax
    cpy #9
    bcs +
    lda #2
+   sta HUDC_ROW1+5,x
    lda tmp
    sec
    sbc tmp2
    sta tmp
    inx
    cpx #8
    bne -
    ; nerve: 5 hearts at col 21
    ldx #0
-   cpx nerve
    bcs +
    lda #H_HEART
    bne ++
+   lda #H_HEART0
++  sta HUD_ROW1+21,x
    lda #2
    sta HUDC_ROW1+21,x
    inx
    cpx #5
    bne -
    ; clock parts: 4 icons at col 33
    ldx #0
-   lda parts
    and part_bits,x
    beq +
    txa
    clc
    adc #H_ICON
    ldy #7
    bne ++
+   lda #H_ICON0
    ldy #11
++  sta HUD_ROW1+33,x
    tya
    sta HUDC_ROW1+33,x
    inx
    cpx #4
    bne -
    rts

!zone hud_update
hud_update:
    lda hud_dirty
    beq +
    jsr hud_draw
+   lda msg_timer
    beq .out
    dec msg_timer
    bne .out
    ldx #21
    lda #32
-   sta HUD_ROW2+18,x
    dex
    bpl -
.out:
    rts

txt_wax:   !scr "wax:",0
txt_nerve: !scr "nerve:",0
txt_clock: !scr "clock:",0

; A/X = message text. Shown on the HUD's bottom row, for a while.
!zone show_message
show_message:
    sta ptr
    stx ptr+1
    ldx #21
    lda #32
-   sta HUD_ROW2+18,x
    dex
    bpl -
    lda #<(HUD_ROW2+18)
    sta ptr2
    lda #>(HUD_ROW2+18)
    sta ptr2+1
    lda #1
    jsr print
    lda #150
    sta msg_timer
    rts

; ---- sound --------------------------------------------------------------
SID = $d400
SFX_JUMP = 0 : SFX_PART = 1 : SFX_HIT = 2 : SFX_THUNDER = 3
SFX_CANDLE = 4 : SFX_WAIL = 5 : SFX_BELL = 6

!zone sid_init
sid_init:
    ldx #$18
    lda #0
-   sta SID,x
    dex
    bpl -
    lda #$0f
    sta SID+$18
    rts

; A = song number
!zone music_start
music_start:
    sta tmp5
    sei
    lda #0
    sta mus_on
    ldx #2
-   lda sid_voice,x
    tay
    lda #0
    sta SID+4,y
    dex
    bpl -
    lda tmp5
    asl
    adc tmp5            ; song*3: index into the per-voice tables
    sta tmp4
    ldx #0
.v:
    ldy tmp4
    lda song_wave,y
    sta MUS_WAVE,x
    lda song_arp,y
    sta MUS_ARP,x
    lda song_ad,y
    pha
    lda song_sr,y
    ldy sid_voice,x
    sta SID+6,y
    pla
    sta SID+5,y
    inc tmp4
    inx
    cpx #3
    bne .v
    lda #0
    sta sfx_dur
    ldy tmp5
    lda song_ptr_lo_0,y
    sta MUS_STL
    sta MUS_PTRL
    lda song_ptr_hi_0,y
    sta MUS_STH
    sta MUS_PTRH
    lda song_ptr_lo_1,y
    sta MUS_STL+1
    sta MUS_PTRL+1
    lda song_ptr_hi_1,y
    sta MUS_STH+1
    sta MUS_PTRH+1
    lda song_ptr_lo_2,y
    sta MUS_STL+2
    sta MUS_PTRL+2
    lda song_ptr_hi_2,y
    sta MUS_STH+2
    sta MUS_PTRH+2
    ldx #2
-   lda #1
    sta MUS_DUR,x
    lda MUS_STH,x       ; a null pointer means the voice is free for effects
    sta MUS_ACT,x
    dex
    bpl -
    lda #$08
    sta SID+3
    sta SID+10
    sta SID+17
    lda #1
    sta mus_on
    cli
    rts

!zone sid_voice
sid_voice:
    !byte 0,7,14

!zone music_tick
music_tick:
    jsr sfx_tick
    lda mus_on
    beq .out
    inc mus_frame
    ; slow pulse-width sweep gives the lead some life
    inc pw
    lda pw
    sta SID+9
    ldx #0
    jsr voice_tick
    ldx #1
    jsr voice_tick
    ldx #2
    jmp voice_tick
.out:
    rts

!zone voice_tick
voice_tick:
    lda MUS_ACT,x
    bne +
    rts
+   dec MUS_DUR,x
    beq .next
    ; hard release just before the next note
    lda MUS_DUR,x
    cmp #2
    bne .held
    ldy sid_voice,x
    lda MUS_WAVE,x
    and #$fe
    sta SID+4,y
.held:
    lda MUS_ARP,x
    beq .none
    jsr arp_step
.none:
    rts
.next:
    lda MUS_PTRL,x
    sta mptr
    lda MUS_PTRH,x
    sta mptr+1
    ldy #0
    lda (mptr),y
    cmp #$ff
    bne +
    lda MUS_STL,x
    sta mptr
    lda MUS_STH,x
    sta mptr+1
    lda (mptr),y
+   sta MUS_NOTE,x
    iny
    lda (mptr),y
    sta MUS_DUR,x
    lda mptr
    clc
    adc #2
    sta MUS_PTRL,x
    lda mptr+1
    adc #0
    sta MUS_PTRH,x
    ldy sid_voice,x
    lda MUS_NOTE,x
    bne +
    ; rest
    lda MUS_WAVE,x
    and #$fe
    sta SID+4,y
    rts
+   and #$7f
    stx mtmp
    tax
    lda freq_lo,x
    sta SID,y
    lda freq_hi,x
    sta SID+1,y
    ldx mtmp
    lda MUS_WAVE,x
    sta SID+4,y
    rts

!zone arp_step
arp_step:
    lda MUS_NOTE,x
    beq .out
    stx mtmp
    tay
    and #$7f
    sta mtmp2
    tya
    bmi .major
    lda mus_frame
    and #3
    tay
    lda arp_minor,y
    jmp .ok
.major:
    lda mus_frame
    and #3
    tay
    lda arp_major,y
.ok:
    clc
    adc mtmp2
    tax
    ldy mtmp
    lda sid_voice,y
    tay
    lda freq_lo,x
    sta SID,y
    lda freq_hi,x
    sta SID+1,y
    ldx mtmp
.out:
    rts

arp_minor: !byte 0,3,7,12
arp_major: !byte 0,4,7,12

; effects take voice 3 (the in-game song leaves it free)
!zone sfx_play
sfx_play:
    tax
    sei
    lda #0
    sta SID+18
    lda sfx_flo_t,x
    sta sfx_flo
    sta SID+14
    lda sfx_fhi_t,x
    sta sfx_fhi
    sta SID+15
    lda sfx_dlo_t,x
    sta sfx_dlo
    lda sfx_dhi_t,x
    sta sfx_dhi
    lda sfx_ad_t,x
    sta SID+19
    lda sfx_sr_t,x
    sta SID+20
    lda sfx_dur_t,x
    sta sfx_dur
    lda sfx_wave_t,x
    sta SID+18
    cli
    rts

!zone sfx_tick
sfx_tick:
    lda sfx_dur
    beq .out
    dec sfx_dur
    bne +
    lda #0
    sta SID+18
    rts
+   lda sfx_flo
    clc
    adc sfx_dlo
    sta sfx_flo
    sta SID+14
    lda sfx_fhi
    adc sfx_dhi
    sta sfx_fhi
    sta SID+15
.out:
    rts

;              jump part  hit   thun  cand  wail  bell
sfx_flo_t:  !byte $00, $00, $00, $00, $00, $00, $00
sfx_fhi_t:  !byte $08, $20, $30, $06, $10, $28, $22
sfx_dlo_t:  !byte $40, $80, $00, $e8, $80, $c0, $00
sfx_dhi_t:  !byte $00, $00, $fe, $ff, $00, $ff, $00
sfx_ad_t:   !byte $00, $00, $00, $08, $00, $58, $00
sfx_sr_t:   !byte $85, $a6, $a7, $fb, $95, $ca, $0c
sfx_dur_t:  !byte $0c, $20, $14, $60, $18, $50, $28
sfx_wave_t: !byte $41, $11, $81, $81, $11, $21, $11

!source "build/gen.asm"

!zone code_end
code_end:
!if code_end > $4000 { !error "code overflows into VIC bank 1" }

; ---- graphics, positioned for the VIC ---------------------------------
CHAR_IN  = $4800
FONT     = $5000
CHAR_OUT = $5800
SPRITES  = $6000
ROOMDATA = $8800

* = CHAR_IN
    !bin "build/charset_in.bin"
* = FONT
    !bin "build/font.bin"
* = CHAR_OUT
    !bin "build/charset_out.bin"
* = SPRITES
    !bin "build/sprites.bin"
* = $8000
    !bin "build/title_screen.bin"
* = $8400
    !bin "build/title_color.bin"
* = ROOMDATA
    !bin "build/rooms.bin"
* = $A000
    !bin "build/title_bitmap.bin"
