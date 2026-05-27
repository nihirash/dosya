    DEFINE RO
    
    DEVICE ZXSPECTRUM48
    org #8000
start:
    ld a,2
    call $1601

    call dosya_init
    ret c
    
    call ls

    ld hl, .sub
    call chdir


    call ls

    ld hl, .up
    call chdir

    call ls
    jr $
.sub db "sub",0
.up db "..", 0

ls:
    ld hl, .vol_name
    call fat_getlabel

    ld hl, .vol : call printZ
    ld a, 13 : call putC

    ld hl, path
    call path_get

    ld hl, .path : call printZ
    ld a, 13 : call putC : ld a, 13 : call putC

    ld hl, path
    call fopendir
    ret c

    ld (handle), a
.loop:
    ld a, (handle)
    ld hl, dir_buf
    call freaddir
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
    jp fclose
    
.vol:
    db "Volume: "
.vol_name
    ds 13

.path:
    db "Directory of "
path: ds PATH_MAX
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

putC:
    rst 16
    ret

    include "../src/dosya.asm"
    IFDEF ZC
    savehob "list.$c", "list.c", start, $ - start
    ELSE
    savetap "list.tap", start
    ENDIF
