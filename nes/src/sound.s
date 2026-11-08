; Ghost Hour NES: music and sound effects on the APU. Called from the NMI every frame.
; The data comes from tools/sound.py: note streams (note, frames; $FF loops; on arpeggio voices
; +$80 means a major chord), per-frame volume envelopes, and effects as per-frame register values.
;
; Channels: 0 pulse 1, 1 pulse 2, 2 triangle, 3 noise. An effect on pulse 1 takes it over from
; the music until it ends.

APU_P1   = $4000
APU_P2   = $4004
APU_TRI  = $4008
APU_NOI  = $400C
APU_STATUS = $4015

.segment "ZEROPAGE"
snd_ptr:   .res 2
sfx_ptr:   .res 2
sfx_on:    .res 1
sfx_ch:    .res 1
sfx_first: .res 1
mus_on:    .res 1
mus_frame: .res 1
snd_tmp:   .res 1
v_ptrl:    .res 3           ; per music voice
v_ptrh:    .res 3
v_stl:     .res 3
v_sth:     .res 3
v_dur:     .res 3
v_note:    .res 3
v_chan:    .res 3           ; $FF: voice not used by this song
v_inst:    .res 3
v_arp:     .res 3
v_env:     .res 3           ; frames since the note started
v_rel:     .res 3           ; 1: released (silent until the next note)
ch_hi:     .res 2           ; last period high byte written to each pulse channel ($4003/$4007)

.segment "RODATA"
arp_minor: .byte 0, 3, 7, 12
arp_major: .byte 0, 4, 7, 12
chan_reg:  .byte 0, 4       ; pulse register offsets

.segment "CODE"

.proc sound_init
    lda #0
    sta mus_on
    sta sfx_on
    lda #$0F
    sta APU_STATUS          ; pulses, triangle and noise on
    lda #$08                ; sweep units off (negate set, so low notes are not muted)
    sta APU_P1+1
    sta APU_P2+1
    lda #$30
    sta APU_P1
    sta APU_P2
    sta APU_NOI
    lda #$80
    sta APU_TRI
    lda #$FF
    sta ch_hi
    sta ch_hi+1
    rts
.endproc

; A = song
.proc music_start
    pha
    lda #0
    sta mus_on              ; the NMI leaves the voices alone while we set them up
    jsr silence_music
    pla
    sta snd_tmp
    asl
    adc snd_tmp             ; song * 3
    tay
    ldx #0
:   lda song_chan,y
    sta v_chan,x
    lda song_inst,y
    sta v_inst,x
    lda song_arp,y
    sta v_arp,x
    lda song_lo,y
    sta v_ptrl,x
    sta v_stl,x
    lda song_hi,y
    sta v_ptrh,x
    sta v_sth,x
    lda #1
    sta v_dur,x
    sta v_rel,x
    iny
    inx
    cpx #3
    bne :-
    lda #1
    sta mus_on
    rts
.endproc

.proc music_stop
    lda #0
    sta mus_on
    ; fall through
.endproc
.proc silence_music
    lda #$30
    sta APU_P2
    lda #$80
    sta APU_TRI
    lda sfx_on              ; pulse 1 only if no effect is using it
    beq :+
    lda sfx_ch
    beq :++
:   lda #$30
    sta APU_P1
:   rts
.endproc

; A = effect. Keeps X.
.proc sfx_play
    tay
    lda #0
    sta sfx_on
    lda sfx_lo,y
    sta sfx_ptr
    lda sfx_hi,y
    sta sfx_ptr+1
    lda sfx_chan,y
    sta sfx_ch
    lda #1
    sta sfx_first
    sta sfx_on
    rts
.endproc

.proc sound_tick
    jsr sfx_tick
    lda mus_on
    beq out
    inc mus_frame
    ldx #0
    jsr voice_tick
    ldx #1
    jsr voice_tick
    ldx #2
    jmp voice_tick
out:
    rts
.endproc

.proc sfx_tick
    lda sfx_on
    beq out
    ldy #0
    lda (sfx_ptr),y
    cmp #$FF
    beq done
    ldx sfx_ch
    bne noise
    sta APU_P1
    iny
    lda (sfx_ptr),y
    sta APU_P1+2
    iny
    lda (sfx_ptr),y
    cmp ch_hi
    beq next
    sta ch_hi
    sta APU_P1+3
    jmp next
noise:
    sta APU_NOI
    iny
    lda (sfx_ptr),y
    sta APU_NOI+2
    lda sfx_first
    beq next
    iny
    lda (sfx_ptr),y
    sta APU_NOI+3
next:
    lda #0
    sta sfx_first
    lda sfx_ptr
    clc
    adc #3
    sta sfx_ptr
    bcc out
    inc sfx_ptr+1
out:
    rts
done:
    lda #0
    sta sfx_on
    lda #$30
    ldx sfx_ch
    bne :+
    sta APU_P1
    rts
:   sta APU_NOI
    rts
.endproc

; music voice X
.proc voice_tick
    lda v_chan,x
    cmp #$FF
    bne :+
    rts
:   dec v_dur,x
    beq next
    lda v_dur,x
    cmp #2                  ; hard release just before the next note, as on the C64
    bne :+
    lda #1
    sta v_rel,x
    jmp silence
:   lda v_rel,x
    bne out
    jmp sound_out
out:
    rts
next:
    lda v_ptrl,x
    sta snd_ptr
    lda v_ptrh,x
    sta snd_ptr+1
    ldy #0
    lda (snd_ptr),y
    cmp #$FF
    bne :+
    lda v_stl,x             ; loop
    sta snd_ptr
    lda v_sth,x
    sta snd_ptr+1
    lda (snd_ptr),y
:   sta v_note,x
    iny
    lda (snd_ptr),y
    sta v_dur,x
    lda snd_ptr
    clc
    adc #2
    sta v_ptrl,x
    lda snd_ptr+1
    adc #0
    sta v_ptrh,x
    lda #0
    sta v_env,x
    sta v_rel,x
    lda v_note,x
    bne :+
    lda #1                  ; a rest
    sta v_rel,x
    jmp silence
:   lda v_chan,x
    cmp #2
    bne pulse_new
    ; triangle: a new note
    lda v_note,x
    and #$7F
    tay
    lda #$FF
    sta APU_TRI
    lda tri_lo,y
    sta APU_TRI+2
    lda tri_hi,y
    sta APU_TRI+3
    rts
pulse_new:
    tay
    lda #$FF                ; write the high byte, which restarts the note
    sta ch_hi,y
    jmp sound_out
.endproc

; silence voice X's channel
.proc silence
    lda v_chan,x
    cmp #2
    bne :+
    lda #$80
    sta APU_TRI
    rts
:   tay
    bne :+
    lda sfx_on              ; pulse 1 belongs to the effect
    beq :+
    lda sfx_ch
    beq out
    ldy #0
:   lda chan_reg,y
    tay
    lda #$30
    sta APU_P1,y
out:
    rts
.endproc

; pulse voice X: volume from its envelope, pitch (with arpeggio)
.proc sound_out
    lda v_chan,x
    cmp #2
    bne :+
    rts                     ; the triangle needs nothing per frame
:   tay
    bne :+
    lda sfx_on              ; pulse 1 belongs to the effect
    beq :+
    lda sfx_ch
    bne :+
    rts
:   sty snd_tmp             ; channel 0 or 1
    ; envelope: inst * ENV_LEN + min(frames, ENV_LEN-1)
    lda v_inst,x
    asl
    asl
    asl
    asl
    asl
    asl                     ; * 64 (ENV_LEN)
    sta snd_ptr
    lda v_env,x
    cmp #ENV_LEN-1
    bcs :+
    inc v_env,x
:   clc
    adc snd_ptr
    tay
    lda inst_env,y
    ldy v_inst,x
    ora inst_duty,y
    ora #$30
    ldy snd_tmp
    pha
    lda chan_reg,y
    tay
    pla
    sta APU_P1,y
    ; pitch
    lda v_note,x
    and #$7F
    sta snd_ptr
    lda v_arp,x
    beq pitch
    lda mus_frame
    and #3
    tay
    lda v_note,x
    bmi :+
    lda arp_minor,y
    bpl :++
:   lda arp_major,y
:   clc
    adc snd_ptr
    sta snd_ptr
pitch:
    ldy snd_ptr
    lda pulse_lo,y
    pha
    lda pulse_hi,y
    ldy snd_tmp
    cmp ch_hi,y
    beq :+
    sta ch_hi,y
    pha
    lda chan_reg,y
    tay
    pla
    sta APU_P1+3,y
    ldy snd_tmp
:   lda chan_reg,y
    tay
    pla
    sta APU_P1+2,y
out:
    rts
.endproc
