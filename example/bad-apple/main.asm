    define RO

    org #8000
    DEVICE ZXSPECTRUM48
start:
    call dosya_init

    call START 

    ld hl, filename : ld a, FA_READ : call fopen
    jp c, error
    ld (fp), a
    
    ld hl, imHandler : call im2On
    ei
readFrame:
    ld a, (fp) : ld bc, 6912 : ld hl, #4000 : call fread 

    ld a, b : or c : jr z, fileEnded
    ld a,#7f
    in a,(#fe)
    rra
    jr nc,stop_play
    jp readFrame
stop_play:
    ld a, (fp)
    call fclose

    call MUTE
    call im2Off
    ret

fileEnded:
    ld hl, 0, de, 0, b, 0, a, (fp)
    call fseek
    jr readFrame

error:
    ld a, 2
    out (#fe), a
    jr $

im2On
        ld    a, 195       ;код команды JP
        ld    (#bdbd), a
        ld    (#bdbe), hl  ;в HL - адрес обработчика прерываний
        ld    hl, #be00    ;построение таблицы для векторов прерываний
        ld    de, #be01
        ld    bc, 256      ;размер таблицы минус 1
        ld    (hl), #bd    ;адрес перехода #bdbd
        ld    a, h         ;запоминаем старший байт адреса таблицы
        ldir               ;заполняем таблицу
        di                 ;запрещаем прерывания на время установки второго режима
        ld    i, a         ;задаем в регистре I старший байт адреса таблицы для векторов прерываний
        im    2            ;назначаем второй режим прерываний
        ret


im2Off
    di
    ld    a, 63
    ld    i, a
    im    1
    ei
    ret


imHandler:
    push af, bc, de, hl, ix, iy
    call PLAY
    pop iy, ix, hl, de, bc, af
    ei
    ret
fp       db 0
filename db "/bad.zxv",0
    include "vtpl.asm"
    include "../../src/dosya.asm"
music:
    incbin "ba.pt3"
    IFDEF ZC    
    savehob "bad.$c", "bad.c", start, $ - start
    ELSE
    savetap "video.tap", start
    ENDIF
