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

This example initializes the path layer, SD/SPI driver, and FAT volume through `dosya_init`, then opens the root directory and reads one entry.

```asm
    call dosya_init
    ret c

    ld hl, root_path
    call fopendir
    ret c
    ld (dir_handle), a

    ld a, (dir_handle)
    ld hl, dir_entry
    call freaddir
    jr c, .done

.done:
    ld a, (dir_handle)
    call fclose
    ret

root_path db "/",0
dir_handle db 0
dir_entry ds 18
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
