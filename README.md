# DOSYA

DOSYA (`Дося`) is a DOS/FAT filesystem implementation for Z80 computers.

It is built with `sjasmplus`, exposes a small POSIX-like file and directory API, and supports FAT16 and FAT32 volumes. 

Parts of DOSYA are based on UnoDOS 3.0: [source-solutions/unodos3](https://github.com/source-solutions/unodos3).

## Source Layout

- `src/fat.asm` contains the merged FAT16/FAT32 implementation.
- `src/spi.asm` contains the bundled SD/SPI transport implementation.
- `src/cwd.asm` contains current-working-directory helpers.
- `src/dosya.asm` is the include entry point for the library.
- `example/list.asm` is a small read-only directory listing example.

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

This example initializes the bundled SD/SPI driver, mounts the first FAT16/FAT32 volume, initializes the current working directory, and opens the root directory.

```asm
    call sd_init
    ret c

    call fat_mount
    ret c

    call cwd_init

    ld hl, root_path
    call fat_opendir
    ret c
    ld (dir_handle), a

    ld a, (dir_handle)
    ld hl, dir_entry
    call fat_readdir
    jr c, .done

.done:
    ld a, (dir_handle)
    call fat_close
    ret

root_path db "/",0
dir_handle db 0
dir_entry ds 18
```

For routine-by-routine register contracts and examples, see [docs/api.md](docs/api.md).

## License

DOSYA is licensed under GPL-3. See [LICENSE](LICENSE).
