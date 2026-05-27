# DOSYA

![logo](docs/logo.jpg)

DOSYA (`Дося`) is a DOS/FAT filesystem implementation for Z80 computers.

It is built with `sjasmplus`, exposes a small POSIX-like file and directory API, and supports FAT16 and FAT32 volumes.

Parts of DOSYA are based on UnoDOS 3.0: [source-solutions/unodos3](https://github.com/source-solutions/unodos3).

## Source Layout

- `src/fat.asm` contains the FAT core plus the public file and directory entry points such as `fopen`, `fread`, `fopendir`, and `freaddir`.
- `src/path.asm` contains current-path helpers built around unix-style `/` paths.
- `src/spi.asm` contains the bundled divMMC-compatible SD/SPI transport, with SDSC and SDHC support.
- `src/dosya.asm` is the library include entry point and provides `dosya_init`.
- `example/list.asm` is the read-only directory listing smoke test.
- `example/loadscr.asm` and `example/writetest.asm` show read-only and writable file I/O.

Define `RO` before including `src/dosya.asm` for a read-only build. Omit `RO` for the writable profile.

## Required Tools

- `sjasmplus` 1.23 or newer
- A Z80 target or emulator compatible with the assembled output
- For the bundled transport, SD/SPI hardware compatible with the ports used in `src/spi.asm`

## Include DOSYA

Use `src/dosya.asm` as the library entry point.

```asm
    DEFINE RO
    include "src/dosya.asm"
```

## Minimal API Example

This example dosya and prints root directory listing to screen.

```asm

    call dosya_init

    ld hl, .vol_name
    call fat_getlabel

    ld hl, .vol
    call printZ
    
    ld a, 13
    call putC

    ld hl, path
    call path_get

    ld hl, .path
    call printZ

    ld a, 13 
    call putC 
    ld a, 13
    call putC

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
```

For lower-level control, call `path_init`, `sd_init`, and `fat_mount` directly.

## Examples

- `sjasmplus example/list.asm` builds the read-only directory listing example.
- `sjasmplus example/loadscr.asm` builds the read-only file-loading example.
- `sjasmplus example/writetest.asm` builds the writable file and directory test.
- `cd example/bad-apple && sjasmplus main.asm` builds the streaming example.

For routine-by-routine register contracts and examples, see [docs/api.md](docs/api.md).

## License

DOSYA is licensed under GPL-3. See [LICENSE](LICENSE).
