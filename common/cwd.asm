;	// =====================================================================
;	// cwd.asm -- current-working-directory helpers for the read-only FAT API
;	// =====================================================================
;	// Public API:
;	//   cwd_init                 -> reset current directory to "/"
;	//   cwd_chdir HL=path        -> change directory (absolute or relative)
;	//   cwd_get   HL=buf         -> copy current directory as ASCIIZ
;	//   cwd_join  HL=path DE=buf -> build an absolute path for a filename
;	//
;	// Path rules:
;	//   - unix-style slashes
;	//   - current directory always ends with '/'
;	//   - root directory is exactly "/"
;	//   - '.' path parts are ignored
;	//   - '..' path parts move one level up, stopping at root
;	//   - relative paths are resolved against the current directory
;	//
;	// Notes:
;	//   - cwd_chdir validates the target with fat_opendir / fat_close before
;	//     committing the new current directory.
;	//   - cwd_join is purely a string helper; it does not touch the volume.
;	//   - path components longer than 12 characters are rejected with
;	//     FE_BADNAME because this FAT reader only deals in 8.3 names.
;	// =====================================================================

CWD_MAX		equ 128

;	// cwd_init : reset current directory to root.
cwd_init:
	ld hl,cwd_cur
	ld (hl),'/'
	inc hl
	xor a
	ld (hl),a
	ret

;	// cwd_get : HL = destination buffer, copy current directory as ASCIIZ.
cwd_get:
	ex de,hl
	ld hl,cwd_cur
	jp cwd_copy_string

;	// cwd_join : HL = filename/path, DE = destination buffer.
;	//   Returns an absolute unix-style path without a trailing slash unless
;	//   the result is root itself.
cwd_join:
	xor a
	jr cwd_normalize_into

;	// cwd_chdir : HL = path (absolute or relative).
;	//   Validates the directory, then commits it as the current directory.
cwd_chdir:
	ld de,cwd_tmp
	ld a,1
	call cwd_normalize_into
	ret c
	ld hl,cwd_tmp
	call fat_opendir
	ret c
	ld (cwd_handle),a
	call fat_close
	ret c
	ld de,cwd_cur
	ld hl,cwd_tmp
	jp cwd_copy_string

;	// cwd_normalize_into : HL = source path, DE = destination buffer,
;	//   A bit0 = 1 => keep trailing '/', A bit0 = 0 => trim trailing '/'
;	//   (except for root).
cwd_normalize_into:
	ld (cwd_srcp),hl
	ld (cwd_base),de
	ld h,d
	ld l,e
	inc hl
	ld (cwd_rootend),hl

	ld hl,(cwd_srcp)
	ld a,(hl)
	cp '/'
	jr z,.absolute

	;	// relative path: start from cwd_cur
	push de
	ld hl,cwd_cur
	call cwd_copy_string
	pop de
	ld d,h
	ld e,l
	ld hl,(cwd_srcp)			;	// restore the caller's source path
	jr .setptr

.absolute:
	;	// absolute path: collapse all leading '/'
.skipabs:
	ld a,(hl)
	cp '/'
	jr nz,.mkroot
	inc hl
	jr .skipabs
.mkroot:
	ld a,'/'
	ld (de),a
	inc de
	xor a
	ld (de),a
.setptr:
	ld (cwd_dptr),de
	ld (cwd_srcp),hl

.next_part:
	ld hl,(cwd_srcp)
.skipsep:
	ld a,(hl)
	cp '/'
	jr nz,.part_or_done
	inc hl
	jr .skipsep
.part_or_done:
	ld (cwd_srcp),hl
	ld a,(hl)
	or a
	jr z,.finish

	ld de,cwd_comp
	ld b,0
.read_part:
	ld a,(hl)
	or a
	jr z,.part_done
	cp '/'
	jr z,.part_done
	ld (de),a
	inc de
	inc hl
	inc b
	ld a,b
	cp 13
	jr c,.read_part
	ld a,FE_BADNAME
	scf
	ret
.part_done:
	xor a
	ld (de),a
	ld (cwd_srcp),hl

	ld a,(cwd_comp)
	cp '.'
	jr nz,.append
	ld a,(cwd_comp+1)
	or a
	jr z,.next_part
	cp '.'
	jr nz,.append
	ld a,(cwd_comp+2)
	or a
	jr nz,.append
	call cwd_pop_component
	jr .next_part

.append:
	call cwd_append_component
	jr .next_part

.finish:
	ld a,(cwd_flags)
	and 1
	jr nz,.ok
	call cwd_trim_trailing
.ok:
	or a
	ret

;	// cwd_append_component : append cwd_comp + '/' to the destination.
cwd_append_component:
	ld hl,(cwd_dptr)
	ld de,cwd_comp
.copy:
	ld a,(de)
	or a
	jr z,.slash
	ld (hl),a
	inc hl
	inc de
	jr .copy
.slash:
	ld (hl),'/'
	inc hl
	xor a
	ld (hl),a
	ld (cwd_dptr),hl
	ret

;	// cwd_pop_component : move one directory up, stopping at root.
cwd_pop_component:
	ld hl,(cwd_dptr)
	ld de,(cwd_rootend)
	call cwd_cmp_hl_de
	ret z
	dec hl				;	// points at trailing '/'
.find:
	dec hl
	ld a,(hl)
	cp '/'
	jr nz,.find
	inc hl
	xor a
	ld (hl),a
	ld (cwd_dptr),hl
	ret

;	// cwd_trim_trailing : drop the final '/' unless the path is root.
cwd_trim_trailing:
	ld hl,(cwd_dptr)
	ld de,(cwd_rootend)
	call cwd_cmp_hl_de
	ret z
	dec hl
	xor a
	ld (hl),a
	ld (cwd_dptr),hl
	ret

;	// cwd_copy_string : HL = source, DE = destination.
;	//   Returns HL = destination NUL position.
cwd_copy_string:
.loop:
	ld a,(hl)
	ld (de),a
	inc hl
	inc de
	or a
	jr nz,.loop
	ex de,hl
	dec hl
	ret

;	// cwd_cmp_hl_de : compare HL and DE, preserving both.
;	//   ZF=1 if equal.
cwd_cmp_hl_de:
	push hl
	or a
	sbc hl,de
	pop hl
	ret

cwd_cur:		ds CWD_MAX
cwd_tmp:		ds CWD_MAX
cwd_comp:	ds 13
cwd_srcp:	ds 2
cwd_dptr:	ds 2
cwd_base:	ds 2
cwd_rootend:	ds 2
cwd_flags:	ds 1
cwd_handle:	ds 1
