# DOSYA API

`src/dosya.asm` is the library entry point. Define `RO` before including it for a read-only build. Omit `RO` to assemble writable entry points as well.

```asm
    DEFINE RO
    include "src/dosya.asm"
```

All public filesystem routines return with carry clear on success. On failure, carry is set and `A` contains an error code unless the routine notes otherwise.

Writable builds add `fwrite`, `fsync`, `ftruncate`, `unlink`, `mkdir`, `rmdir`, `frename`, and `write_sector`. These entry points are omitted when `RO` is defined.

## Error Codes

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

## Contents

- [Initialization](#initialization)
- [Files](#files)
- [Directories](#directories)
- [File System Mutation](#file-system-mutation)
- [Volume Metadata](#volume-metadata)
- [Path Helpers](#path-helpers)

## Initialization

### `dosya_init`

Initializes the path layer, the bundled SD/SPI driver, and mounts the first FAT16 or FAT32 volume.

Registers:

- Input: none
- Success: carry clear
- Failure: carry set, `A` contains an `sd_init` driver code or an `FE_*` mount error

Example:

```asm
    call dosya_init
    ret c
```

## Files

### `fopen`

Opens a file and returns a handle.

The open mode byte passed in `A` uses the following constants:

- `FA_READ = %0001`
- `FA_WRITE = %0010`
- `FA_CREATE_NEW = %0100`
- `FA_OPEN_ALWAYS = %1000`
- `FA_CREATE_ALWAYS = %1100`

The writable disposition bits are meaningful only in writable builds.

Registers:

- Input: `HL` = ASCIIZ path, `A` = open mode bits
- Success: carry clear, `A` = handle
- Failure: carry set, `A` contains an `FE_*` error code

Example:

```asm
    ld hl, file_name
    ld a, FA_READ
    call fopen
    ret c
    ld (file_handle), a

file_name db "/README.TXT",0
file_handle db 0
```

### `fclose`

Closes a file or directory handle. In writable builds, dirty file data is synced before the handle is released.

Registers:

- Input: `A` = handle
- Success: carry clear
- Failure: carry set, `A` contains an `FE_*` error code

Example:

```asm
    ld a, (file_handle)
    call fclose
    ret c
```

### `fread`

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
    call fread
    ret c

read_buf ds 128
```

### `fwrite`

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
    call fwrite
    ret c

write_buf db "OK",13,10
write_len equ $-write_buf
```

### `fseek`

Moves the file position. Seeking is clamped to the current file size.

Registers:

- Input: `A` = handle, `B` = whence, `DEHL` = unsigned offset
- `B = 0`: set absolute position
- `B = 1`: move forward from the current position
- `B = 2`: move backward from the current position
- Success: carry clear, `DEHL` = new position
- Failure: carry set, `A` contains an `FE_*` error code

Example:

```asm
    ld a, (file_handle)
    ld b, 0
    ld de, 0
    ld hl, 0
    call fseek
    ret c
```

### `ftell`

Returns the current file position.

Registers:

- Input: `A` = handle
- Success: carry clear, `DEHL` = current position
- Failure: carry set, `A` contains an `FE_*` error code

Example:

```asm
    ld a, (file_handle)
    call ftell
    ret c
```

### `fsync`

Flushes dirty file data and directory metadata. This entry point is available only in writable builds.

Registers:

- Input: `A` = handle
- Success: carry clear
- Failure: carry set, `A` contains an `FE_*` error code

Example:

```asm
    ld a, (file_handle)
    call fsync
    ret c
```

### `ftruncate`

Truncates an open file to its current position. This entry point is available only in writable builds.

Registers:

- Input: `A` = handle
- Success: carry clear
- Failure: carry set, `A` contains an `FE_*` error code

Example:

```asm
    ld a, (file_handle)
    call ftruncate
    ret c
```

## Directories

### `fopendir`

Opens a directory and returns a directory handle.

Registers:

- Input: `HL` = ASCIIZ path
- Success: carry clear, `A` = handle
- Failure: carry set, `A` contains an `FE_*` error code

Example:

```asm
    ld hl, dir_name
    call fopendir
    ret c
    ld (dir_handle), a

dir_name db "/",0
dir_handle db 0
```

### `freaddir`

Reads the next directory entry into an 18-byte record.

`freaddir` writes an 18-byte record to `HL`:

- `+0`: FAT attribute byte
- `+1`: 8.3 ASCIIZ name, up to 13 bytes including terminator
- `+14`: file size, 32-bit little-endian

Registers:

- Input: `A` = directory handle, `HL` = destination record
- Success: carry clear, record at `HL` is filled
- Failure: carry set, `A = FE_NOENT` at end of directory, or another `FE_*` code on error

Example:

```asm
    ld a, (dir_handle)
    ld hl, dir_entry
    call freaddir
    jr c, .done

.done:
    ret

dir_entry ds 18
```

## File System Mutation

### `unlink`

Deletes a file. This entry point is available only in writable builds.

Registers:

- Input: `HL` = ASCIIZ path
- Success: carry clear
- Failure: carry set, `A` contains an `FE_*` error code

Example:

```asm
    ld hl, old_file
    call unlink
    ret c

old_file db "/OLD.LOG",0
```

### `mkdir`

Creates a directory. This entry point is available only in writable builds.

Registers:

- Input: `HL` = ASCIIZ path
- Success: carry clear
- Failure: carry set, `A` contains an `FE_*` error code

Example:

```asm
    ld hl, new_dir
    call mkdir
    ret c

new_dir db "/LOGS",0
```

### `rmdir`

Removes an empty directory. This entry point is available only in writable builds.

Registers:

- Input: `HL` = ASCIIZ path
- Success: carry clear
- Failure: carry set, `A` contains an `FE_*` error code

Example:

```asm
    ld hl, old_dir
    call rmdir
    ret c

old_dir db "/EMPTY",0
```

### `frename`

Renames or moves a file or directory. Moving a directory to another parent does not rewrite its `..` entry.

Registers:

- Input: `HL` = old ASCIIZ path, `DE` = new ASCIIZ path
- Success: carry clear
- Failure: carry set, `A` contains an `FE_*` error code

Example:

```asm
    ld hl, old_name
    ld de, new_name
    call frename
    ret c

old_name db "/OLD.TXT",0
new_name db "/NEW.TXT",0
```

## Volume Metadata

### `fat_getlabel`

Copies the volume label as an ASCIIZ string. If no label is present, the destination receives an empty string. This routine always returns with carry clear.

Registers:

- Input: `HL` = destination buffer, at least 12 bytes recommended
- Success: carry clear
- Failure: none

Example:

```asm
    ld hl, label_buf
    call fat_getlabel

label_buf ds 13
```

## Path Helpers

`PATH_MAX` is defined in `src/path.asm` and is currently `256`.

### `path_get`

Copies the current path as an ASCIIZ string.

Registers:

- Input: `HL` = destination buffer, at least `PATH_MAX` bytes
- Success: destination buffer contains the current path as ASCIIZ
- Failure: none

Example:

```asm
    ld hl, path_buf
    call path_get

path_buf ds PATH_MAX
```

### `chdir`

Changes the current path after validating the target directory with `fopendir`.

Registers:

- Input: `HL` = ASCIIZ path, absolute or relative
- Success: carry clear
- Failure: carry set, `A` contains an `FE_*` error code

Example:

```asm
    ld hl, sub_dir
    call chdir
    ret c

sub_dir db "SUB",0
```

### `path_join`

Builds an absolute path from the current path and a file name or path.

Registers:

- Input: `HL` = ASCIIZ file name or path, `DE` = destination buffer
- Success: carry clear, destination buffer contains an ASCIIZ absolute path
- Failure: carry set, `A` contains `FE_BADNAME`

Example:

```asm
    ld hl, rel_file
    ld de, joined_path
    call path_join
    ret c

rel_file db "FILE.TXT",0
joined_path ds PATH_MAX
```
