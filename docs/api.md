# DOSYA API

All public FAT routines return with carry clear on success. On failure, carry is set and `A` contains an error code unless the routine notes otherwise.

Error codes:

- `FE_OK = 0`
- `FE_IO = 1`
- `FE_NOFS = 2`
- `FE_NOENT = 3`
- `FE_EXIST = 4`
- `FE_NOSPC = 5`
- `FE_NOTDIR = 6`
- `FE_ISDIR = 7`
- `FE_BADNAME = 8`
- `FE_NOHANDLE = 9`
- `FE_BADF = 10`
- `FE_NOTEMPTY = 11`
- `FE_RANGE = 12`
- `FE_RDONLY = 13`

Open mode bits for `fat_open`:

- bit 0: read access
- bit 1: write access, writable build only
- bits 2-3: disposition, writable build only
  - `%00`: open existing
  - `%01`: create new
  - `%10`: open always
  - `%11`: create always

Directory records returned by `fat_readdir` are 18 bytes:

- `+0`: FAT attribute byte
- `+1`: 8.3 ASCIIZ name, up to 13 bytes including terminator
- `+14`: file size, 32-bit little-endian

Use `src/dosya.asm` as the library include entry point. Define `RO` before including it for read-only builds.

```asm
    DEFINE RO
    include "src/dosya.asm"
```

## Contents

- [Initialization](#initialization)
- [Files](#files)
- [Directories](#directories)
- [File System Mutation](#file-system-mutation)
- [Volume Metadata](#volume-metadata)
- [Current Directory Helpers](#current-directory-helpers)
- [Platform Hooks](#platform-hooks)

## Initialization

### `sd_init`

Initializes the bundled SD/SPI driver.

Registers:

- Input: none
- Success: carry clear
- Failure: carry set, `A` contains a driver error code

Example:

```asm
    call sd_init
    ret c
```

### `fat_mount`

Mounts the first FAT16/FAT32 volume.

Registers:

- Input: none
- Success: carry clear
- Failure: carry set, `A` contains an `FE_*` error code

Example:

```asm
    call sd_init
    ret c
    call fat_mount
    ret c
```

### `cwd_init`

Resets the current working directory to `/`.

Registers:

- Input: none
- Output: current directory becomes `/`
- Failure: none

Example:

```asm
    call fat_mount
    ret c
    call cwd_init
```

## Files

### `fat_open`

Opens a file and returns a file handle.

Registers:

- Input: `HL` = ASCIIZ path, `A` = open mode bits
- Success: carry clear, `A` = handle
- Failure: carry set, `A` contains an `FE_*` error code

Example:

```asm
    ld hl, file_name
    ld a, %00000001
    call fat_open
    ret c
    ld (file_handle), a

file_name db "/README.TXT",0
file_handle db 0
```

### `fat_close`

Closes a file or directory handle. In writable builds, dirty data is synced before the handle is released.

Registers:

- Input: `A` = handle
- Success: carry clear
- Failure: carry set, `A` contains an `FE_*` error code

Example:

```asm
    ld a, (file_handle)
    call fat_close
    ret c
```

### `fat_read`

Reads bytes from an open file.

Registers:

- Input: `A` = handle, `HL` = destination buffer, `BC` = byte count
- Success: carry clear, `BC` = bytes read
- Failure: carry set, `A` contains an `FE_*` error code

Example:

```asm
    ld a, (file_handle)
    ld hl, read_buf
    ld bc, 128
    call fat_read
    ret c

read_buf ds 128
```

### `fat_write`

Writes bytes to an open file. This entry point is available only in writable builds.

Registers:

- Input: `A` = handle, `HL` = source buffer, `BC` = byte count
- Success: carry clear, `BC` = bytes written
- Failure: carry set, `A` contains an `FE_*` error code

Example:

```asm
    ld a, (file_handle)
    ld hl, write_buf
    ld bc, write_len
    call fat_write
    ret c

write_buf db "OK",13,10
write_len equ $-write_buf
```

### `fat_seek`

Moves a file handle position. Seeking is clamped to the file size.

Registers:

- Input: `A` = handle, `B` = whence, `DEHL` = unsigned offset
- `B = 0`: set absolute position
- `B = 1`: move forward from current position
- `B = 2`: move backward from current position
- Success: carry clear, `DEHL` = new position
- Failure: carry set, `A` contains an `FE_*` error code

Example:

```asm
    ld a, (file_handle)
    ld b, 0
    ld de, 0
    ld hl, 0
    call fat_seek
    ret c
```

### `fat_tell`

Returns the current file handle position.

Registers:

- Input: `A` = handle
- Success: carry clear, `DEHL` = current position
- Failure: carry set, `A` contains an `FE_*` error code

Example:

```asm
    ld a, (file_handle)
    call fat_tell
    ret c
```

### `fat_sync`

Flushes dirty file data and directory metadata. This entry point is available only in writable builds.

Registers:

- Input: `A` = handle
- Success: carry clear
- Failure: carry set, `A` contains an `FE_*` error code

Example:

```asm
    ld a, (file_handle)
    call fat_sync
    ret c
```

### `fat_truncate`

Truncates an open file to its current position. This entry point is available only in writable builds.

Registers:

- Input: `A` = handle
- Success: carry clear
- Failure: carry set, `A` contains an `FE_*` error code

Example:

```asm
    ld a, (file_handle)
    call fat_truncate
    ret c
```

## Directories

### `fat_opendir`

Opens a directory and returns a directory handle.

Registers:

- Input: `HL` = ASCIIZ path
- Success: carry clear, `A` = handle
- Failure: carry set, `A` contains an `FE_*` error code

Example:

```asm
    ld hl, dir_name
    call fat_opendir
    ret c
    ld (dir_handle), a

dir_name db "/",0
dir_handle db 0
```

### `fat_readdir`

Reads the next directory entry into an 18-byte record.

Registers:

- Input: `A` = directory handle, `HL` = destination record
- Success: carry clear, record at `HL` is filled
- Failure: carry set. End of directory is reported as carry set.

Example:

```asm
    ld a, (dir_handle)
    ld hl, dir_entry
    call fat_readdir
    jr c, .done

.done:
    ret

dir_entry ds 18
```

### `fat_mkdir`

Creates a directory. This entry point is available only in writable builds.

Registers:

- Input: `HL` = ASCIIZ path
- Success: carry clear
- Failure: carry set, `A` contains an `FE_*` error code

Example:

```asm
    ld hl, new_dir
    call fat_mkdir
    ret c

new_dir db "/LOGS",0
```

### `fat_rmdir`

Removes an empty directory. This entry point is available only in writable builds.

Registers:

- Input: `HL` = ASCIIZ path
- Success: carry clear
- Failure: carry set, `A` contains an `FE_*` error code

Example:

```asm
    ld hl, old_dir
    call fat_rmdir
    ret c

old_dir db "/EMPTY",0
```

## File System Mutation

### `fat_unlink`

Deletes a file. This entry point is available only in writable builds.

Registers:

- Input: `HL` = ASCIIZ path
- Success: carry clear
- Failure: carry set, `A` contains an `FE_*` error code

Example:

```asm
    ld hl, old_file
    call fat_unlink
    ret c

old_file db "/OLD.LOG",0
```

### `fat_rename`

Renames or moves a file or directory. Moving a directory to another parent does not rewrite its `..` entry.

Registers:

- Input: `HL` = old ASCIIZ path, `DE` = new ASCIIZ path
- Success: carry clear
- Failure: carry set, `A` contains an `FE_*` error code

Example:

```asm
    ld hl, old_name
    ld de, new_name
    call fat_rename
    ret c

old_name db "/OLD.TXT",0
new_name db "/NEW.TXT",0
```

## Volume Metadata

### `fat_getlabel`

Copies the volume label as an ASCIIZ string.

Registers:

- Input: `HL` = destination buffer, at least 12 bytes recommended
- Success: carry clear
- Failure: none expected

Example:

```asm
    ld hl, label_buf
    call fat_getlabel

label_buf ds 13
```

## Current Directory Helpers

### `cwd_get`

Copies the current directory as an ASCIIZ path.

Registers:

- Input: `HL` = destination buffer, at least `CWD_MAX` bytes
- Success: destination buffer contains the current directory as ASCIIZ
- Failure: none

Example:

```asm
    ld hl, cwd_buf
    call cwd_get

cwd_buf ds CWD_MAX
```

### `cwd_chdir`

Changes the current directory after validating it with `fat_opendir`.

Registers:

- Input: `HL` = ASCIIZ path, absolute or relative
- Success: carry clear
- Failure: carry set, `A` contains an `FE_*` error code

Example:

```asm
    ld hl, sub_dir
    call cwd_chdir
    ret c

sub_dir db "SUB",0
```

### `cwd_join`

Builds an absolute path from the current directory and a file name or path.

Registers:

- Input: `HL` = ASCIIZ file name or path, `DE` = destination buffer
- Success: carry clear, destination buffer contains an ASCIIZ path
- Failure: carry set, `A` contains `FE_BADNAME`

Example:

```asm
    ld hl, rel_file
    ld de, joined_path
    call cwd_join
    ret c

rel_file db "FILE.TXT",0
joined_path ds CWD_MAX
```

## Platform Hooks

### `read_sector`

Reads one 512-byte sector. Integrators must provide this routine, or include `src/spi.asm`.

Registers:

- Input: `HL` = 512-byte buffer, `DEBC` = 32-bit LBA
- Success: carry clear
- Failure: carry set
- May corrupt: all registers

Example:

```asm
read_sector:
    ; Platform-specific sector read goes here.
    scf
    ret
```

### `write_sector`

Writes one 512-byte sector. Writable builds require this routine, or `src/spi.asm` can provide it when `RO` is not defined.

Registers:

- Input: `HL` = 512-byte buffer, `DEBC` = 32-bit LBA
- Success: carry clear
- Failure: carry set
- May corrupt: all registers

Example:

```asm
write_sector:
    ; Platform-specific sector write goes here.
    scf
    ret
```
