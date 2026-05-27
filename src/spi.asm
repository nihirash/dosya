; ---------------------------------------------------------------------------
; Z-Controller/divMMC-compatible SD over SPI implementation
; ---------------------------------------------------------------------------
    IFDEF ZC
SPI_CTL         equ #77
SPI_DATA        equ #57
SD_CS_ON        equ #01
SD_CS_OFF       equ #03
    ELSE
SPI_CTL         equ #e7
SPI_DATA        equ #eb
SD_CS_ON        equ #fe
SD_CS_OFF       equ #ff
    ENDIF

sd_select:
    ld a, (sd_select_value)
    out (SPI_CTL), a
    ret

sd_deselect:
    ld a, SD_CS_OFF
    out (SPI_CTL), a
    ld a, #ff
    out (SPI_DATA), a
    ret

; sd_cmd: A=command byte, sd_arg[0..3]=MSB..LSB. Returns R1 in A, CF=1 timeout.
sd_cmd:
    ld (sd_cmd_byte), a
    call sd_select
    ld a, (sd_cmd_byte)
    out (SPI_DATA), a
    ld hl, sd_arg
    ld b, 4
.arg:
    ld a, (hl)
    inc hl
    out (SPI_DATA), a
    djnz .arg
    ld a, (sd_cmd_byte)
    cp #40
    jr nz, .not0
    ld a, #95
    jr .crc
.not0:
    cp #48
    jr nz, .crc_ff
    ld a, #87
    jr .crc
.crc_ff:
    ld a, #ff
.crc:
    out (SPI_DATA), a
    ld bc, #32
.wait:
    in a, (SPI_DATA)
    cp #ff
    jr nz, .ok
    djnz .wait
    dec c
    jr nz, .wait
    ld a, #ff
    scf
    ret
.ok:
    or a
    ret

	IFNDEF RO
sd_wait_not_ff:
    ld bc, #32
.wait:
    in a, (SPI_DATA)
    cp #ff
    jr nz, .ok
    djnz .wait
    dec c
    jr nz, .wait
    ld a, #ff
    scf
    ret
.ok:
    or a
    ret
	ENDIF

sd_arg_zero:
    xor a
    ld (sd_arg+0), a
    ld (sd_arg+1), a
    ld (sd_arg+2), a
    ld (sd_arg+3), a
    ret

sd_init:
    ld a, #f6
    ld (sd_select_value), a
    call sd_init_try
    jr nc, .ok
    cp 1
    ret nz
    ld a, #f5
    ld (sd_select_value), a
    call sd_init_try
    jr nc, .ok
    cp 1
    ret nz
    ld a, #fe
    ld (sd_select_value), a
    call sd_init_try
    ret c
.ok:
    xor a
    ret

sd_init_try:
    xor a
    ld (sd_blockaddr), a
    ld (sd_v2), a
    call sd_deselect
    ld b, 12
.warm:
    ld a, #ff
    out (SPI_DATA), a
    djnz .warm

    call sd_arg_zero
    ld b, #ff
.cmd0:
    push bc
    ld a, #40
    call sd_cmd
    pop bc
    jr c, .cmd0_next
    and #fe
    jr z, .cmd8
.cmd0_next:
    djnz .cmd0
    ld a, 1
    scf
    ret

.cmd8:
    xor a
    ld (sd_arg+0), a
    ld (sd_arg+1), a
    ld a, #01
    ld (sd_arg+2), a
    ld a, #aa
    ld (sd_arg+3), a
    ld a, #48
    call sd_cmd
    jp c, .cmd8_legacy
    bit 2, a
    jp nz, .cmd8_legacy
    cp #01
    jp nz, .fail2
    ld a, 1
    ld (sd_v2), a
    in a, (SPI_DATA)
    or a
    jp nz, .fail2
    in a, (SPI_DATA)
    or a
    jp nz, .fail2
    in a, (SPI_DATA)
    cp #01
    jp nz, .fail2
    in a, (SPI_DATA)
    cp #aa
    jp nz, .fail2
    call sd_deselect

    ld hl, 0
    ld (sd_retry), hl
.acmd41:
    call sd_arg_zero
    ld a, #77
    call sd_cmd
    jr c, .fail3
    ld a, (sd_v2)
    or a
    jr z, .acmd41_v1
    ld a, #40
    ld (sd_arg+0), a
    ld a, #30
    ld (sd_arg+1), a
    jr .acmd41_arg_tail
.acmd41_v1:
    xor a
    ld (sd_arg+0), a
    ld (sd_arg+1), a
.acmd41_arg_tail:
    xor a
    ld (sd_arg+2), a
    ld (sd_arg+3), a
    ld a, #69
    call sd_cmd
    jr c, .fail3
    or a
    jr z, .cmd58
    ld hl, (sd_retry)
    inc hl
    ld (sd_retry), hl
    ld a, h
    cp #40
    jr c, .acmd41
.fail3:
    call sd_deselect
    ld a, (sd_v2)
    or a
    jr z, .cmd1_init
    ld a, 3
    scf
    ret

.cmd1_init:
    ld hl, 0
    ld (sd_retry), hl
.cmd1_loop:
    call sd_arg_zero
    ld a, #41
    call sd_cmd
    jr c, .cmd1_next
    or a
    jr z, .cmd16
.cmd1_next:
    ld hl, (sd_retry)
    inc hl
    ld (sd_retry), hl
    ld a, h
    cp #40
    jr c, .cmd1_loop
    ld a, 3
    scf
    ret

.cmd58:
    call sd_arg_zero
    ld a, #7a
    call sd_cmd
    jr c, .fail4
    or a
    jr nz, .fail4
    in a, (SPI_DATA)
    and #40
    ld a, 0
    jr z, .ocr_tail
    inc a
    ld (sd_blockaddr), a
.ocr_tail:
    in a, (SPI_DATA) : nop 
    in a, (SPI_DATA) : nop 
    in a, (SPI_DATA) : nop 
    call sd_deselect
    ld a, (sd_blockaddr)
    or a
    jr nz, .init_ok

    ; SET_BLOCKLEN 512 is required for byte-addressed cards.
.cmd16:
    xor a
    ld (sd_arg+0), a
    ld (sd_arg+1), a
    ld a, #02
    ld (sd_arg+2), a
    xor a
    ld (sd_arg+3), a
    ld a, #50
    call sd_cmd
    push af
    call sd_deselect
    pop af
    or a
    jr z, .init_ok
    ld a, 5
    scf
    ret
.init_ok:
    xor a
    ret
.fail2:
    call sd_deselect
    ld a, 2
    scf
    ret
.cmd8_legacy:
    call sd_deselect
.legacy_init:
    xor a
    ld (sd_v2), a
    ld hl, 0
    ld (sd_retry), hl
    jp .acmd41
.fail4:
    call sd_deselect
    ld a, 4
    scf
    ret

; Input DEBC=LBA. Output sd_arg=card command address.
; SDSC/MMC cards want byte addresses, while SDHC/SDXC cards want block LBAs.
sd_set_lba_arg:
    ld a, (sd_blockaddr)
    or a
    jr nz, .store
    ld a, 9
.shift:
    sla c
    rl b
    rl e
    rl d
    dec a
    jr nz, .shift
.store:
    ld a, d
    ld (sd_arg+0), a
    ld a, e
    ld (sd_arg+1), a
    ld a, b
    ld (sd_arg+2), a
    ld a, c
    ld (sd_arg+3), a
    ret

read_sector:
    ld (rw_buf), hl
    call sd_set_lba_arg
    ld a, #51
    call sd_cmd
    jr c, .fail
    or a
    jr nz, .fail
    ld hl, 0
.tok:
    in a, (SPI_DATA) 
    cp #fe
    jr z, .data
    inc hl
    ld a, h
    or l
    jr nz, .tok
.fail:
    call sd_deselect
    ld a, 1
    scf
    ret
.data:
    ld hl, (rw_buf)
    ; Some divMMC setups leave the data token visible for one or two extra
    ; reads. Drain a few repeated token echoes before storing sector byte 0.
    ld b, 4
.align:
    in a, (SPI_DATA) 
    cp #fe
    jr nz, .first
    djnz .align
.first:
    ld (hl), a
    inc hl
    ld de, 511
.rdloop:
    in a, (SPI_DATA) 
    ld (hl), a
    inc hl
    dec de
    ld a, d
    or e
    jr nz, .rdloop
    in a, (SPI_DATA) : nop 
    in a, (SPI_DATA) : nop 
    call sd_deselect
    or a
    ret

	IFNDEF RO
write_sector:
    ld (rw_buf), hl
    call sd_set_lba_arg
    ld a, #58
    call sd_cmd
    jr c, .cmd_timeout
    ld (sd_last_resp), a
    or a
    jr nz, .cmd_reject
    ld a, #fe
    out (SPI_DATA), a
    ld hl, (rw_buf)
    ld c, SPI_DATA
    ld b, 0
    otir
    nop
    ld b, 0
    otir
    nop
    ld a, #ff
    out (SPI_DATA), a
    nop
    out (SPI_DATA), a
    call sd_wait_not_ff
    jr c, .data_timeout
    ld (sd_last_resp), a
    and #1f
    cp #05
    jr nz, .data_reject
.busy:
    call sd_wait_not_ff
    jr c, .done
    or a
    jr z, .busy
.done:
    call sd_deselect
    or a
    ret
.cmd_timeout:
    ld a, #21
    jr .fail
.cmd_reject:
    ld a, #22
    jr .fail
.data_timeout:
    ld a, #23
    jr .fail
.data_reject:
    ld a, #24
.fail:
    call sd_deselect
    scf
    ret
	ENDIF


sd_cmd_byte         db 0
sd_select_value     db SD_CS_ON
sd_blockaddr        db 0
sd_v2               db 0
sd_retry            dw 0
sd_arg              db 0, 0, 0, 0
rw_buf              dw 0
	IFNDEF RO
sd_last_resp        db 0
	ENDIF
