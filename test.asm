    DEVICE ZXSPECTRUM48
    org #8000
start:
    ld a,2
    call $1601

    call sd_init
    ret c
    call fat_mount
    ret c
    call cwd_init
    
    call ls

    ld hl, .sub
    call cwd_chdir


    call ls

    ld hl, .up
    call cwd_chdir

    call ls
    ret
.sub db "sub",0
.up db "..", 0

ls:
    ld hl, .vol_name
    call fat_getlabel

    ld hl, .vol : call printZ
    ld a, 13 : call putC

    ld hl, path
    call cwd_get

    ld hl, .path : call printZ
    ld a, 13 : call putC : ld a, 13 : call putC

    ld hl, path
    call fat_opendir
    ret c

    ld (handle), a
.loop:
    ld a, (handle)
    ld hl, dir_buf
    call fat_readdir
    jr c, .done

    ld hl, dir_buf + 1
    call printZ

    ld a, (dir_buf)
    and ATTR_DIR
    jr z, .file

    ld a, '/'
    call putC
.file
    ld a, 13
    call putC

    jr .loop
.done:
    ld a, 13 : call putC
    
    ld a, (handle)
    jp fat_close
.vol:
    db "Volume: "
.vol_name
    ds 13

.path:
    db "Directory of "
path: ds CWD_MAX
    db 0

dir_buf:
    ds 18

handle: db 0

printZ:
    ld a,(hl)
    and a
    ret z
    push hl
    call putC
    pop hl
    inc hl
    jr printZ

printHex8:
    push af
    rrca
    rrca
    rrca
    rrca
    call .nibble
    pop af
.nibble:
    and #0F
    add a,'0'
    cp '9'+1
    jr c,.emit
    add a,7
.emit:
    jp putC

putC:
    rst 16
    ret

    include "full/spi.asm"
    include "common/cwd.asm"
    include "full/fat.asm"

    savebin "test.bin", $8000, $ - $8000
    savetap "test.tap", start
