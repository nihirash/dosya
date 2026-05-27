;; Write enabled test:
;;  - Show directory
;;  - Read file
;;  - Save file
;;  - Load it again
;;  - Delete file
;;  - Create directory
;;  - Delete directory
    DEVICE ZXSPECTRUM48
    org #8000
start:
    ld a,2
    call $1601

    call dosya_init
    jp c, error
    
    call ls

    xor a
    out (#fe), a

    ld hl, filename
    call loadscr

    ld hl, filename2
    ld a, FA_CREATE_ALWAYS + FA_WRITE
    call fopen
    jp c, error
    ld (handle), a

    ld bc, 6912
    ld hl, #4000
    call fwrite
    jp c, error

    ld a, (handle)
    call fclose

    ld hl, #4000
    ld de, #4001
    ld bc, 6911
    ld a, #ff
    ld (hl), a
    ldir

    call ls

    ; loads new file
    ld hl, filename2
    call   loadscr

    ; Deletes file
    ld hl, filename2
    call unlink
    jp c, error


    call ls

    ld hl, dir_name
    call mkdir

    call ls

    ld hl, dir_name
    call rmdir

    call ls
    
    jr $

error:
    ld a, 2
    out (#fe), a
    jr $

;; HL - name
loadscr:
    ld a, FA_READ
    call fopen
    jp c, error
    ld (handle), a

    ld bc, 6912
    ld hl, #4000
    call fread

    ld a, (handle)
    jp fclose
    


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
    call fclose

    ld b, 50
.wait
    halt
    djnz .wait
    ret
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

filename:
    db "/test.scr", 0
filename2:
    db "/test2.scr", 0
dir_name:
    db "new", 0
handle: 
    db 0

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
    savehob "write.$c", "write.c", start, $ - start
    ELSE
    savetap "write.tap", start
    ENDIF
