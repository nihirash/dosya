    DEFINE RO
    
    DEVICE ZXSPECTRUM48
    org #8000
start:
    call dosya_init
    ret c

    ld hl, filename
    ld a, FA_READ
    call fopen
    ret c
    ld (handle), a

    ld bc, 6912
    ld hl, #4000
    call fread

    ld a, (handle)
    call fclose
    
    jr $
    
filename:
    db "/test.scr", 0
handle: 
    db 0
    include "../src/dosya.asm"

    IFDEF ZC
    savehob "loadscr.$c", "loadscr.c", start, $ - start
    ELSE
    savetap "loadscr.tap", start
    ENDIF
