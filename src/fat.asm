;	// ---------------------------------------------------------------------
;	// PUBLIC API   (all routines: CF=0 ok / CF=1 fail with A = error code)
;	// ---------------------------------------------------------------------
;	//   fat_mount                      mount first FAT16/32 volume
;	//   fat_getlabel HL=buf            copy volume label (ASCIIZ) to buf
;	//   fopen     	  HL=path A=mode     -> A = file handle
;	//   fclose    	  A=handle
;	//   fread        A=handle HL=buf BC=count   -> BC = bytes read
;	//   fwrite       A=handle HL=buf BC=count   -> BC = bytes written
;	//   fseek        A=handle B=whence DEHL=off -> DEHL = new position
;	//   ftell        A=handle                   -> DEHL = position
;	//   fsync        A=handle           flush a file's data + dir entry
;	//   fopendir     HL=path            -> A = dir handle
;	//
;	//   freaddir     A=handle HL=buf    fill 18-byte entry record
;	// 					readdir record (18 bytes) written to HL:
;	//   					+0   attributes byte (FAT directory attribute bits)
;	//   					+1   name, 8.3 ASCIIZ, up to 13 bytes incl. terminator
;	//   					+14  file size, 32-bit
;	//
;	//   unlink       HL=path            delete a file
;	//   mkdir        HL=path            create a directory
;	//   rmdir        HL=path            remove an empty directory
;	//   frename      HL=oldpath DE=newpath
;	//   ftruncate    A=handle          truncate file to current position
;	// =====================================================================



;	// ---- error codes -----------------------------------------------------
FE_OK		equ 0
FE_IO		equ 1			;	// read_sector / write_sector failed
FE_NOFS		equ 2			;	// not a FAT16/FAT32 volume
FE_NOENT	equ 3			;	// no such file or directory
FE_EXIST	equ 4			;	// already exists
FE_NOSPC	equ 5			;	// volume full
FE_NOTDIR	equ 6			;	// path component is not a directory
FE_ISDIR	equ 7			;	// target is a directory
FE_BADNAME	equ 8			;	// malformed name
FE_NOHANDLE	equ 9			;	// no free file handle
FE_BADF		equ 10			;	// bad file handle
FE_NOTEMPTY	equ 11			;	// directory not empty
FE_RANGE	equ 12			;	// seek / position out of range
FE_RDONLY	equ 13			;	// handle not opened for that access

;	// ---- file open modes -------------------------------------------------

;	// open mode bits (A in fopen):
;	//   bit0  FA_READ        request read access
;	//   bit1  FA_WRITE       request write access
;	//   bits2-3  disposition:
;	//       %00  open existing      (error if missing)
;	//       %01  create new         (error if exists)
;	//       %10  open always        (create if missing)
;	//       %11  create always      (create, or open + truncate)
FA_READ 	     equ %0001
FA_WRITE 	     equ %0010
FA_CREATE_NEW    equ %0100
FA_OPEN_ALWAYS   equ %1000
FA_CREATE_ALWAYS equ %1100


;	// ---- tunables --------------------------------------------------------
FAT_MAXH	equ 4			;	// number of simultaneous file handles

;	// ---- FAT on-disk attribute bits -------------------------------------
ATTR_RO		equ %00000001
ATTR_HIDDEN	equ %00000010
ATTR_SYSTEM	equ %00000100
ATTR_VOLID	equ %00001000
ATTR_DIR	equ %00010000
ATTR_ARCHIVE	equ %00100000
ATTR_LFN	equ %00001111		;	// long-file-name entry marker

;	// ---- volume descriptor field offsets (base = fat_vol) ---------------
VOL_TYPE	equ 0			;	// 0 unmounted / 16 FAT16 / 32 FAT32
VOL_SPC		equ 1			;	// sectors per cluster
VOL_CSHIFT	equ 2			;	// log2(sectors per cluster)
VOL_NFATS	equ 3			;	// number of FATs
VOL_PARTBASE	equ 4			;	// 4: partition start LBA
VOL_FATSTART	equ 8			;	// 4: LBA of FAT #0
VOL_FATSIZE	equ 12			;	// 4: sectors per FAT
VOL_ROOTLBA	equ 16			;	// 4: FAT16 root-dir LBA
VOL_ROOTSECS	equ 20			;	// 2: FAT16 root-dir sector count
VOL_ROOTCLUS	equ 22			;	// 4: FAT32 root-dir first cluster
VOL_DATALBA	equ 26			;	// 4: LBA of cluster #2
VOL_CLUSCNT	equ 30			;	// 4: number of data clusters
VOL_FREEHINT	equ 34			;	// 4: next-free-cluster search hint
VOL_LABEL	equ 38			;	// 11: volume label copied from the BPB
VOL__SIZE	equ 49

;	// ---- file handle field offsets (IX = handle base) -------------------
FH_INUSE	equ 0			;	// 0 = free
FH_MODE		equ 1			;	// access flags, see below
FH_FCLUS	equ 2			;	// 4: first cluster (0 = empty)
FH_SIZE		equ 6			;	// 4: file size in bytes
FH_POS		equ 10			;	// 4: current position
FH_CCLUS	equ 14			;	// 4: cluster cached for FH_CIDX
FH_CIDX		equ 18			;	// 4: cluster index of FH_CCLUS
FH_DELBA	equ 22			;	// 4: LBA of sector with dir entry
FH_DEOFF	equ 26			;	// 2: byte offset of dir entry
FH_DCLUS	equ 28			;	// 4: first cluster of parent dir
FH_FLAGS	equ 32			;	// 1: bit0 = dir entry dirty
FH__SIZE	equ 34

;	// FH_MODE bits
MD_READ		equ %00000001
MD_WRITE	equ %00000010
MD_ISDIR	equ %00100000

;	// =====================================================================
;	// 32-bit little-endian arithmetic helpers
;	// =====================================================================

;	// mov32 : copy 4 bytes (HL) -> (DE).  preserves BC,DE,HL.
mov32:
	push bc
	push de
	push hl
	ldi
	ldi
	ldi
	ldi
	pop hl
	pop de
	pop bc
	ret

;	// clr32 : zero the 4 bytes at (HL).  preserves HL.
clr32:
	push hl
	push af
	xor a
	ld (hl),a
	inc hl
	ld (hl),a
	inc hl
	ld (hl),a
	inc hl
	ld (hl),a
	pop af
	pop hl
	ret

;	// add32 : (HL) = (HL) + (DE).  preserves DE,HL.
add32:
	push hl
	push de
	push bc
	or a
	ld b,4
.l:
	ld a,(de)
	adc a,(hl)
	ld (hl),a
	inc hl
	inc de
	djnz .l
	pop bc
	pop de
	pop hl
	ret

;	// sub32 : (HL) = (HL) - (DE).  preserves DE,HL.  CF=1 if underflow.
sub32:
	push hl
	push de
	push bc
	or a
	ld b,4
.l:
	ld a,(de)
	ld c,a
	ld a,(hl)
	sbc a,c
	ld (hl),a
	inc hl
	inc de
	djnz .l
	pop bc
	pop de
	pop hl
	ret

;	// cp32 : compare (HL) with (DE) as unsigned 32-bit.
;	//        ZF=1 equal, CF=1 if (HL) < (DE).  preserves BC,DE,HL.
cp32:
	push hl
	push de
	push bc
	ld bc,3
	add hl,bc
	ex de,hl
	add hl,bc
	ex de,hl			;	// HL -> A msb, DE -> B msb
	ld b,4
.l:
	ld a,(de)
	ld c,a
	ld a,(hl)
	cp c
	jr nz,.done
	dec hl
	dec de
	djnz .l
.done:
	pop bc
	pop de
	pop hl
	ret

;	// inc32 : (HL) = (HL) + 1.  preserves HL.
inc32:
	push hl
	push bc
	push af
	ld b,4
.l:
	inc (hl)
	jr nz,.done
	inc hl
	djnz .l
.done:
	pop af
	pop bc
	pop hl
	ret

;	// shl32 : (HL) = (HL) << 1.  preserves HL.  CF = bit shifted out.
shl32:
	push hl
	sla (hl)
	inc hl
	rl (hl)
	inc hl
	rl (hl)
	inc hl
	rl (hl)
	pop hl
	ret

;	// shr32 : (HL) = (HL) >> 1 logical.  preserves HL.
shr32:
	push hl
	push bc
	ld bc,3
	add hl,bc
	srl (hl)
	dec hl
	rr (hl)
	dec hl
	rr (hl)
	dec hl
	rr (hl)
	pop bc
	pop hl
	ret

;	// iszero32 : ZF=1 if the 4 bytes at (HL) are all zero.  preserves HL.
iszero32:
	push hl
	push bc
	ld a,(hl)
	inc hl
	or (hl)
	inc hl
	or (hl)
	inc hl
	or (hl)
	pop bc
	pop hl
	ret

;	// =====================================================================
;	// buffered I/O : two sector caches
;	//   slot 0  -> FAT sectors only
;	//   slot 1  -> directory + file-data sectors
;	// =====================================================================

;	// cache_init : invalidate both cache slots.
cache_init:
	xor a
	ld (slot_flags+0),a
	ld (slot_flags+1),a
	ret

;	// cache_addr : select a slot.  in: A = slot (0/1).
;	//   sets cbufp / clbap / cflagp.  trashes A,HL.
cache_addr:
	or a
	jr nz,.s1
	ld hl,slot_buf0
	ld (cbufp),hl
	ld hl,slot_lba+0
	ld (clbap),hl
	ld hl,slot_flags+0
	ld (cflagp),hl
	ret
.s1:
	ld hl,slot_buf1
	ld (cbufp),hl
	ld hl,slot_lba+4
	ld (clbap),hl
	ld hl,slot_flags+1
	ld (cflagp),hl
	ret

;	// cache_flush_sel : flush the currently-selected slot if dirty.
;	//   out: CF=1 on I/O error.  trashes A,BC,DE,HL.
cache_flush_sel:
	IFDEF RO
	or a
	ret
	ELSE
	ld hl,(cflagp)
	bit 1,(hl)			;	// dirty?
	jr nz,.dirty
	or a				;	// not dirty: succeed with CF=0
	ret
.dirty:
	;	// mtmp = slot LBA
	ld hl,(clbap)
	ld de,mtmp
	call mov32
	;	// write the primary copy
	ld hl,mtmp
	call lba_into_debc
	ld hl,(cbufp)
	call wr_sector_raw
	ret c
	;	// FAT slot?  mirror into the remaining FAT copies.
	ld a,(cbufp+1)
	cp slot_buf0/256
	jr nz,.clean			;	// not the FAT slot
	ld a,(fat_vol+VOL_NFATS)
	dec a
	jr z,.clean			;	// only one FAT
	ld (mcount),a
.mirror:
	ld hl,mtmp
	ld de,fat_vol+VOL_FATSIZE
	call add32
	ld hl,mtmp
	call lba_into_debc
	ld hl,(cbufp)
	call wr_sector_raw
	ret c
	ld hl,mcount
	dec (hl)
	jr nz,.mirror
.clean:
	ld hl,(cflagp)
	res 1,(hl)			;	// clear dirty
	or a				;	// CF=0
	ret
	ENDIF

;	// lba_into_debc : load the 32-bit LBA at (HL) into DEBC.  trashes A,HL.
lba_into_debc:
	ld c,(hl)
	inc hl
	ld b,(hl)
	inc hl
	ld e,(hl)
	inc hl
	ld d,(hl)
	ret

;	// cache_get : ensure selected-by-A slot holds (reqlba); return buffer.
;	//   in : A = slot, reqlba = wanted 32-bit LBA
;	//   out: HL = buffer address, CF=1 on I/O error
;	//   trashes A,BC,DE
cache_get:
	call cache_addr
	;	// already valid and holding the right LBA?
	ld hl,(cflagp)
	bit 0,(hl)
	jr z,.miss
	ld hl,(clbap)
	ld de,reqlba
	call cp32
	jr nz,.miss
	ld hl,(cbufp)			;	// hit
	or a
	ret
.miss:
	call cache_flush_sel
	ret c
	;	// read reqlba into the slot buffer
	ld hl,reqlba
	ld c,(hl)
	inc hl
	ld b,(hl)
	inc hl
	ld e,(hl)
	inc hl
	ld d,(hl)
	push bc
	push de
	ld hl,(cbufp)
	call rd_sector_raw
	pop de
	pop bc
	ret c
	;	// record new LBA, mark valid & clean
	ld hl,reqlba
	ld de,(clbap)
	call mov32
	ld hl,(cflagp)
	ld (hl),%00000001
	ld hl,(cbufp)
	or a
	ret

	IFNDEF RO
;	// cache_get_blank : like cache_get but does NOT read the sector --
;	//   used when the caller is going to overwrite the whole sector.
;	//   in : A = slot, reqlba = wanted LBA.  out: HL = buffer, CF=err
cache_get_blank:
	call cache_addr
	call cache_flush_sel
	ret c
	ld hl,reqlba
	ld de,(clbap)
	call mov32
	ld hl,(cflagp)
	ld (hl),%00000001		;	// valid, clean
	ld hl,(cbufp)
	or a
	ret

;	// cache_dirty_sel : mark the currently-selected slot dirty.
cache_dirty_sel:
	ld hl,(cflagp)
	set 1,(hl)
	or a
	ret

;	// cache_flush_all : flush both slots.  CF=1 on error.
cache_flush_all:
	xor a
	call cache_addr
	call cache_flush_sel
	ret c
	ld a,1
	call cache_addr
	jp cache_flush_sel
	ENDIF

	;	// rd_sector_raw : call the integrator hook, saving the driver's IX
	;	//   (active handle pointer) across the call.
	;	//   in: HL=buffer, DEBC=LBA.  out: CF.
rd_sector_raw:
	push ix
	call read_sector
	pop ix
	ret c
	or a
	ret

	IFNDEF RO
	;	// wr_sector_raw : call the integrator hook, saving the driver's IX
	;	//   the driver's IX (active handle pointer) across the call.
	;	//   in: HL=buffer, DEBC=LBA.  out: CF.
wr_sector_raw:
	push ix
	call write_sector
	pop ix
	ret c
	or a
	ret
	ENDIF
;	// add16 : (HL) += DE  (DE treated as unsigned 16-bit).  preserves HL,DE.
add16:
	push hl
	push af
	ld a,e
	add a,(hl)
	ld (hl),a
	inc hl
	ld a,d
	adc a,(hl)
	ld (hl),a
	inc hl
	ld a,0
	adc a,(hl)
	ld (hl),a
	inc hl
	ld a,0
	adc a,(hl)
	ld (hl),a
	pop af
	pop hl
	ret

;	// add8 : (HL) += A  (A treated as unsigned 8-bit).  preserves HL.
add8:
	push hl
	add a,(hl)
	ld (hl),a
	jr nc,.d
	inc hl
	inc (hl)
	jr nz,.d
	inc hl
	inc (hl)
	jr nz,.d
	inc hl
	inc (hl)
.d:
	pop hl
	ret

;	// dec32 : (HL) -= 1.  preserves HL.
dec32:
	push hl
	push bc
	ld b,4
.l:
	ld a,(hl)
	sub 1
	ld (hl),a
	jr nc,.d
	inc hl
	djnz .l
.d:
	pop bc
	pop hl
	ret

;	// =====================================================================
;	// read-only constants
;	// =====================================================================
c_two:		db 2,0,0,0
c4085:		db 0xF5,0x0F,0,0
c65525:		db 0xF5,0xFF,0,0
c_eoc16:	db 0xF7,0xFF,0x00,0x00
c_eoc32:	db 0xF7,0xFF,0xFF,0x0F

;	// =====================================================================
;	// volume mount
;	// =====================================================================

pbuf		equ slot_buf1		;	// scratch parse buffer = data cache

;	// vbr_ok : CF=0 if pbuf holds a plausible FAT BPB, else CF=1.
vbr_ok:
	ld hl,(pbuf+0x0B)		;	// bytes per sector
	ld a,h
	cp 0x02
	jr nz,.bad
	ld a,l
	or a
	jr nz,.bad
	ld a,(pbuf+0x10)		;	// number of FATs
	or a
	jr z,.bad
	cp 3
	jr nc,.bad
	ld a,(pbuf+0x0D)		;	// sectors per cluster
	or a
	jr z,.bad
	ld c,a
	dec a
	and c				;	// power of two?
	jr nz,.bad
	or a
	ret
.bad:
	scf
	ret

;	// fat_mount : mount the first FAT16/FAT32 volume.
fat_mount:
	xor a
	ld (fat_vol+VOL_TYPE),a		;	// unmounted until proven good
	ld (mount_dbg+0),a
	ld (mount_dbg+1),a
	ld (mount_dbg+2),a
	ld (mount_dbg+3),a
	ld (mount_dbg+4),a
	ld (mount_dbg+5),a
	call cache_init
	call handles_init
	;	// read LBA 0
	ld bc,0
	ld de,0
	ld hl,pbuf
	call read_sector
	jp c,.eio
	ld a,(pbuf+0x1FE)
	ld (mount_dbg+0),a
	ld a,(pbuf+0x1FF)
	ld (mount_dbg+1),a
	ld a,(pbuf+0x1FE)
	cp 0x55
	jp nz,.enofs
	ld a,(pbuf+0x1FF)
	cp 0xAA
	jp nz,.enofs
	ld hl,m_partbase
	call clr32
	call vbr_ok
	jr nc,.havevbr
	;	// not a VBR -> treat LBA 0 as an MBR, scan the 4 primary entries
	;	// for the first partition whose first sector looks like a FAT BPB.
	ld hl,pbuf+0x1BE
	ld b,4
.mbrscan:
	push bc
	push hl
	ld de,4
	add hl,de			;	// HL -> partition type
	ld a,(hl)
	or a
	jr z,.nextpart
	ld de,4
	add hl,de			;	// HL -> partition start LBA
	ld de,m_partbase
	call mov32
	ld hl,m_partbase
	call lba_into_debc
	ld hl,pbuf
	call read_sector
	jr c,.eio_pop
	ld a,(pbuf+0x1FE)
	ld (mount_dbg+2),a
	ld a,(pbuf+0x1FF)
	ld (mount_dbg+3),a
	call vbr_ok
	jr nc,.havevbr_pop
.nextpart:
	pop hl
	ld de,16
	add hl,de
	pop bc
	djnz .mbrscan
	jp .enofs
.havevbr_pop:
	pop hl
	pop bc
	jr .havevbr
.eio_pop:
	pop hl
	pop bc
	jp .eio
.havevbr:
	;	// sectors per cluster + log2
	ld a,(pbuf+0x0D)
	ld (fat_vol+VOL_SPC),a
	ld b,255
.clog:
	inc b
	srl a
	jr nz,.clog
	ld a,b
	ld (fat_vol+VOL_CSHIFT),a
	;	// number of FATs
	ld a,(pbuf+0x10)
	ld (fat_vol+VOL_NFATS),a
	;	// FAT size (sectors) -> VOL_FATSIZE
	ld hl,(pbuf+0x16)
	ld a,h
	or l
	jr z,.fatsz32
	ld (fat_vol+VOL_FATSIZE),hl
	xor a
	ld (fat_vol+VOL_FATSIZE+2),a
	ld (fat_vol+VOL_FATSIZE+3),a
	jr .fatszd
.fatsz32:
	ld hl,pbuf+0x24
	ld de,fat_vol+VOL_FATSIZE
	call mov32
.fatszd:
	;	// total sectors -> t1
	ld hl,(pbuf+0x13)
	ld a,h
	or l
	jr z,.tot32
	ld (t1),hl
	xor a
	ld (t1+2),a
	ld (t1+3),a
	jr .totd
.tot32:
	ld hl,pbuf+0x20
	ld de,t1
	call mov32
.totd:
	;	// root-dir sector count = ceil(rootentcnt/16)
	ld hl,(pbuf+0x11)
	ld bc,15
	add hl,bc
	srl h
	rr l
	srl h
	rr l
	srl h
	rr l
	srl h
	rr l
	ld (fat_vol+VOL_ROOTSECS),hl
	;	// fatregion = VOL_FATSIZE * NFATS -> t0
	ld hl,fat_vol+VOL_FATSIZE
	ld de,t0
	call mov32
	ld a,(fat_vol+VOL_NFATS)
	cp 2
	jr nz,.nf1
	ld hl,t0
	ld de,fat_vol+VOL_FATSIZE
	call add32
.nf1:
	;	// VOL_FATSTART = partbase + reserved
	ld hl,m_partbase
	ld de,fat_vol+VOL_FATSTART
	call mov32
	ld de,(pbuf+0x0E)
	ld hl,fat_vol+VOL_FATSTART
	call add16
	;	// VOL_ROOTLBA = VOL_FATSTART + fatregion
	ld hl,fat_vol+VOL_FATSTART
	ld de,fat_vol+VOL_ROOTLBA
	call mov32
	ld hl,fat_vol+VOL_ROOTLBA
	ld de,t0
	call add32
	;	// VOL_DATALBA = VOL_ROOTLBA + rootdirsecs
	ld hl,fat_vol+VOL_ROOTLBA
	ld de,fat_vol+VOL_DATALBA
	call mov32
	ld de,(fat_vol+VOL_ROOTSECS)
	ld hl,fat_vol+VOL_DATALBA
	call add16
	;	// firstdata(relative) t0 = fatregion + reserved + rootdirsecs
	ld de,(pbuf+0x0E)
	ld hl,t0
	call add16
	ld de,(fat_vol+VOL_ROOTSECS)
	ld hl,t0
	call add16
	;	// datasectors = totsec(t1) - firstdata(t0)
	ld hl,t1
	ld de,t0
	call sub32
	;	// clustercount = datasectors >> cshift
	ld a,(fat_vol+VOL_CSHIFT)
	or a
	jr z,.noshift
	ld b,a
.shc:
	ld hl,t1
	call shr32
	djnz .shc
.noshift:
	ld hl,t1
	ld de,fat_vol+VOL_CLUSCNT
	call mov32
	;	// classify
	ld hl,fat_vol+VOL_CLUSCNT
	ld de,c4085
	call cp32
	jr c,.enofs
	ld hl,fat_vol+VOL_CLUSCNT
	ld de,c65525
	call cp32
	jr c,.isf16
	ld hl,pbuf+0x2C
	ld de,fat_vol+VOL_ROOTCLUS
	call mov32
	ld a,32
	jr .settype
.isf16:
	ld hl,fat_vol+VOL_ROOTCLUS
	call clr32
	ld a,16
.settype:
	ld (fat_vol+VOL_TYPE),a
	;	// copy the volume label out of the BPB
	cp 32
	ld hl,pbuf+0x47			;	// FAT32 BPB label field
	jr z,.lblcopy
	ld hl,pbuf+0x2B			;	// FAT16 BPB label field
.lblcopy:
	ld de,fat_vol+VOL_LABEL
	ld bc,11
	ldir
	ld hl,fat_vol+VOL_FREEHINT
	call clr32
	ld a,2
	ld (fat_vol+VOL_FREEHINT),a
	or a
	ret
.eio:
	ld a,FE_IO
	scf
	ret
.enofs:
	ld a,FE_NOFS
	scf
	ret

;	// =====================================================================
;	// fat_getlabel : copy the volume label to the buffer at HL (>= 12
;	//   bytes) as an ASCIIZ string -- empty string if there is no label.
;	//   Prefers the root-directory volume-label entry; falls back to the
;	//   label held in the BPB.  Always returns CF=0.
;	// =====================================================================
fat_getlabel:
	ld (gl_dst),hl
	ld a,(fat_vol+VOL_TYPE)
	cp 32
	jr z,.r32
	ld hl,cl_dir
	call clr32			;	// FAT16 root
	jr .scan0
.r32:
	ld hl,fat_vol+VOL_ROOTCLUS
	ld de,cl_dir
	call mov32
.scan0:
	call dir_first
.scan:
	call dir_cur
	jr c,.bpb			;	// end of dir / I/O error -> use BPB
	ld a,(hl)
	or a
	jr z,.bpb			;	// 0x00 -> end of directory
	cp 0xE5
	jr z,.next
	push hl
	ld de,DE_ATTR
	add hl,de
	ld a,(hl)
	pop hl
	cp ATTR_LFN
	jr z,.next			;	// long-file-name entry
	and ATTR_VOLID
	jr z,.next			;	// not the volume-label entry
	ld de,(gl_dst)			;	// found it
	call gl_make
	or a
	ret
.next:
	call dir_next
	jr c,.bpb
	jr .scan
.bpb:
	ld hl,fat_vol+VOL_LABEL
	ld de,(gl_dst)
	call gl_make
	or a
	ret

;	// gl_make : HL = 11-byte label field, DE = dest; copy it, strip
;	//   trailing spaces, NUL-terminate.
gl_make:
	push de
	ld bc,11
	ldir
	xor a
	ld (de),a			;	// dest[11] = 0
	pop hl
	ld bc,10
	add hl,bc			;	// HL -> dest[10]
	ld b,11
.tl:
	ld a,(hl)
	cp ' '
	jr nz,.td
	ld (hl),0			;	// drop a trailing space
	dec hl
	djnz .tl
.td:
	ret

;	// =====================================================================
;	// FAT chain navigation
;	// =====================================================================

;	// fat_locate : compute FAT sector + byte index for cluster cl_in.
;	//   sets reqlba and fatidx.  trashes A,BC,DE,HL.
fat_locate:
	ld a,(fat_vol+VOL_TYPE)
	cp 32
	jr z,.f32
	;	// FAT16: cluster is 16-bit
	ld hl,fat_vol+VOL_FATSTART
	ld de,reqlba
	call mov32
	ld a,(cl_in+1)			;	// sector index = cluster >> 8
	ld hl,reqlba
	call add8
	ld a,(cl_in+0)
	ld l,a
	ld h,0
	add hl,hl			;	// idx = (cluster & 255) * 2
	ld (fatidx),hl
	ret
.f32:
	ld hl,cl_in
	ld de,t2
	call mov32
	ld b,7
.sh:
	ld hl,t2
	call shr32			;	// t2 = cluster >> 7
	djnz .sh
	ld hl,fat_vol+VOL_FATSTART
	ld de,reqlba
	call mov32
	ld hl,reqlba
	ld de,t2
	call add32
	ld a,(cl_in+0)
	and 0x7F
	ld l,a
	ld h,0
	add hl,hl
	add hl,hl			;	// idx = (cluster & 127) * 4
	ld (fatidx),hl
	ret

;	// fat_get : read FAT entry for cl_in -> cl_out (32-bit).  CF=err.
fat_get:
	call fat_locate
	xor a
	call cache_get
	ret c
	ld de,(fatidx)
	add hl,de
	ld a,(fat_vol+VOL_TYPE)
	cp 32
	jr z,.g32
	ld e,(hl)
	inc hl
	ld d,(hl)
	ld (cl_out),de
	xor a
	ld (cl_out+2),a
	ld (cl_out+3),a
	ret
.g32:
	ld de,cl_out
	ld bc,4
	ldir
	ld a,(cl_out+3)
	and 0x0F
	ld (cl_out+3),a
	or a
	ret

	IFNDEF RO
;	// fat_set : write cl_val into the FAT entry for cl_in.  CF=err.
fat_set:
	call fat_locate
	xor a
	call cache_get
	ret c
	ld de,(fatidx)
	add hl,de
	ld a,(fat_vol+VOL_TYPE)
	cp 32
	jr z,.s32
	ld a,(cl_val+0)
	ld (hl),a
	inc hl
	ld a,(cl_val+1)
	ld (hl),a
	jr .mark
.s32:
	push hl
	inc hl
	inc hl
	inc hl
	ld a,(hl)
	and 0xF0
	ld b,a
	pop hl
	ld a,(cl_val+0)
	ld (hl),a
	inc hl
	ld a,(cl_val+1)
	ld (hl),a
	inc hl
	ld a,(cl_val+2)
	ld (hl),a
	inc hl
	ld a,(cl_val+3)
	and 0x0F
	or b
	ld (hl),a
.mark:
	call cache_dirty_sel
	or a
	ret

;	// set_clval_eoc : load cl_val with the end-of-chain marker.
set_clval_eoc:
	ld hl,cl_val
	ld a,(fat_vol+VOL_TYPE)
	cp 32
	jr z,.e32
	ld (hl),0xFF
	inc hl
	ld (hl),0xFF
	inc hl
	ld (hl),0
	inc hl
	ld (hl),0
	ret
.e32:
	ld (hl),0xFF
	inc hl
	ld (hl),0xFF
	inc hl
	ld (hl),0xFF
	inc hl
	ld (hl),0x0F
	ret
	ENDIF

;	// clus_is_last : in (HL)=32-bit value -> CF=1 if terminal/unusable.
clus_is_last:
	call iszero32
	jr z,.last
	push hl
	push de
	ld de,c_eoc16
	ld a,(fat_vol+VOL_TYPE)
	cp 32
	jr nz,.cmp
	ld de,c_eoc32
.cmp:
	call cp32
	pop de
	pop hl
	ccf
	ret
.last:
	scf
	ret

;	// clus_to_lba : in (HL)=cluster number -> reqlba = its first LBA.
clus_to_lba:
	push hl
	ld de,t3
	call mov32
	ld hl,t3
	ld de,c_two
	call sub32
	ld a,(fat_vol+VOL_CSHIFT)
	or a
	jr z,.noss
	ld b,a
.ss:
	ld hl,t3
	call shl32
	djnz .ss
.noss:
	ld hl,fat_vol+VOL_DATALBA
	ld de,reqlba
	call mov32
	ld hl,reqlba
	ld de,t3
	call add32
	pop hl
	ret

	IFNDEF RO
;	// fat_alloc : allocate a free cluster, link it EOC -> cl_out.  CF=err.
fat_alloc:
	ld hl,fat_vol+VOL_CLUSCNT
	ld de,t1
	call mov32
	ld hl,t1
	ld de,c_two
	call add32			;	// t1 = first invalid cluster number
	ld hl,fat_vol+VOL_FREEHINT
	ld de,cl_scan
	call mov32
	ld hl,fat_vol+VOL_CLUSCNT
	ld de,t2
	call mov32			;	// t2 = clusters left to try
.loop:
	ld hl,t2
	call iszero32
	jr z,.full
	ld hl,cl_scan
	ld de,t1
	call cp32
	jr c,.inrange
	ld hl,cl_scan
	call clr32
	ld a,2
	ld (cl_scan),a
.inrange:
	ld hl,cl_scan
	ld de,cl_in
	call mov32
	call fat_get
	ret c
	ld hl,cl_out
	call iszero32
	jr z,.found
	ld hl,cl_scan
	call inc32
	ld hl,t2
	call dec32
	jr .loop
.found:
	call set_clval_eoc
	call fat_set			;	// cl_in already = cl_scan
	ret c
	ld hl,cl_scan
	ld de,cl_out
	call mov32
	ld hl,cl_scan
	ld de,fat_vol+VOL_FREEHINT
	call mov32
	ld hl,fat_vol+VOL_FREEHINT
	call inc32
	or a
	ret
.full:
	ld a,FE_NOSPC
	scf
	ret

;	// fat_free_chain : free the whole cluster chain starting at cl_in.
fat_free_chain:
.loop:
	ld hl,cl_in
	call iszero32
	jr z,.done
	ld hl,cl_in
	call clus_is_last
	jr c,.done
	call fat_get
	ret c
	ld hl,cl_val
	call clr32
	call fat_set
	ret c
	ld hl,cl_out
	ld de,cl_in
	call mov32
	jr .loop
.done:
	or a
	ret
	ENDIF
;	// =====================================================================
;	// directory layer
;	// =====================================================================

;	// ---- 32-byte directory entry field offsets --------------------------
DE_NAME		equ 0			;	// 11 bytes, 8.3 padded
DE_ATTR		equ 11
DE_NTRES	equ 12
DE_CRTTMS	equ 13
DE_CRTTIME	equ 14
DE_CRTDATE	equ 16
DE_ACCDATE	equ 18
DE_CLUSHI	equ 20
DE_WRTTIME	equ 22
DE_WRTDATE	equ 24
DE_CLUSLO	equ 26
DE_SIZE		equ 28

;	// characters not allowed in 8.3 names
fat_badchars:
	db '"','*','+',',','/',':',';','<','=','>','?','[','\','] ',0x7C,' '
fat_badchars_end:

;	// upcase : if A in 'a'..'z' convert to upper case.
upcase:
	cp 'a'
	ret c
	cp 'z'+1
	ret nc
	and 0xDF
	ret

;	// valid_fatchar : in A=char -> CF=1 if not allowed in an 8.3 name.
valid_fatchar:
	cp 0x20
	jr c,.inv
	cp 0x7F
	jr nc,.inv
	push hl
	push bc
	ld hl,fat_badchars
	ld bc,fat_badchars_end-fat_badchars
	cpir
	pop bc
	pop hl
	jr z,.inv
	or a
	ret
.inv:
	scf
	ret

;	// name_to_83 : parse one path component at (HL) into name83 (11 bytes,
;	//   space-padded, upper-cased).  HL is advanced past the component.
;	//   CF=1 + A=FE_BADNAME on a malformed component.
name_to_83:
	push hl
	ld hl,name83
	ld b,11
	ld a,' '
.fill:
	ld (hl),a
	inc hl
	djnz .fill
	pop hl
	ld a,(hl)
	or a
	jr z,.bad
	cp '/'
	jr z,.bad
	cp '.'
	jr nz,.normal
	;	// "." or ".." only
	inc hl
	ld a,(hl)
	call .isterm
	jr z,.isdot
	cp '.'
	jr nz,.bad
	inc hl
	ld a,(hl)
	call .isterm
	jr nz,.bad
	ld a,'.'
	ld (name83+0),a
	ld (name83+1),a
	or a
	ret
.isdot:
	ld a,'.'
	ld (name83+0),a
	or a
	ret
.normal:
	ld de,name83
	ld b,8
.nloop:
	ld a,(hl)
	call .isterm
	jr z,.ok
	cp '.'
	jr z,.dotpart
	call valid_fatchar
	jr c,.bad
	call upcase
	ld (de),a
	inc de
	inc hl
	djnz .nloop
.skipname:
	ld a,(hl)
	call .isterm
	jr z,.ok
	cp '.'
	jr z,.dotpart
	inc hl
	jr .skipname
.dotpart:
	inc hl
	ld de,name83+8
	ld b,3
.eloop:
	ld a,(hl)
	call .isterm
	jr z,.ok
	call valid_fatchar
	jr c,.bad
	call upcase
	ld (de),a
	inc de
	inc hl
	djnz .eloop
.skipext:
	ld a,(hl)
	call .isterm
	jr z,.ok
	inc hl
	jr .skipext
.ok:
	or a
	ret
.bad:
	ld a,FE_BADNAME
	scf
	ret
;	// .isterm : ZF=1 if A is 0 or '/'
.isterm:
	or a
	ret z
	cp '/'
	ret

;	// cmp_name83 : compare 11 bytes at (HL) with name83.  ZF=1 if equal.
cmp_name83:
	push hl
	push de
	push bc
	ld de,name83
	ld b,11
.l:
	ld a,(de)
	cp (hl)
	jr nz,.ne
	inc hl
	inc de
	djnz .l
	cp a
.ne:
	pop bc
	pop de
	pop hl
	ret

;	// ent_get_clus : in HL -> 32-byte entry; out cl_tmp = first cluster.
ent_get_clus:
	push hl
	ld a,(fat_vol+VOL_TYPE)
	cp 32
	jr z,.f32
	xor a
	ld (cl_tmp+2),a
	ld (cl_tmp+3),a
	jr .lo
.f32:
	push hl
	ld de,DE_CLUSHI
	add hl,de
	ld a,(hl)
	ld (cl_tmp+2),a
	inc hl
	ld a,(hl)
	ld (cl_tmp+3),a
	pop hl
.lo:
	ld de,DE_CLUSLO
	add hl,de
	ld a,(hl)
	ld (cl_tmp+0),a
	inc hl
	ld a,(hl)
	ld (cl_tmp+1),a
	pop hl
	ret

	IFNDEF RO
;	// ent_put_clus : in HL -> entry, cl_tmp = cluster; store into entry.
ent_put_clus:
	push hl
	push hl
	ld de,DE_CLUSLO
	add hl,de
	ld a,(cl_tmp+0)
	ld (hl),a
	inc hl
	ld a,(cl_tmp+1)
	ld (hl),a
	pop hl
	ld de,DE_CLUSHI
	add hl,de
	ld a,(cl_tmp+2)
	ld (hl),a
	inc hl
	ld a,(cl_tmp+3)
	ld (hl),a
	pop hl
	ret
	ENDIF

;	// =====================================================================
;	// directory iterator
;	// =====================================================================

;	// dir_first : start iterating the directory whose first cluster is in
;	//   cl_dir (0 = FAT16 root, or FAT32 root if type is FAT32).
dir_first:
	ld hl,cl_dir
	call iszero32
	jr nz,.cluster
	ld a,(fat_vol+VOL_TYPE)
	cp 32
	jr z,.f32root
	xor a
	ld (dc_mode),a
	ld hl,fat_vol+VOL_ROOTLBA
	ld de,dc_lba
	call mov32
	ld hl,(fat_vol+VOL_ROOTSECS)
	ld (dc_secleft),hl
	jr .clrent
.f32root:
	ld hl,fat_vol+VOL_ROOTCLUS
	ld de,cl_dir
	call mov32
.cluster:
	ld a,1
	ld (dc_mode),a
	ld hl,cl_dir
	ld de,dc_curclus
	call mov32
	ld hl,cl_dir
	ld de,dc_lastclus
	call mov32
	ld hl,dc_curclus
	call clus_to_lba
	ld hl,reqlba
	ld de,dc_lba
	call mov32
	xor a
	ld (dc_secincl),a
.clrent:
	xor a
	ld (dc_entoff),a
	ld (dc_entoff+1),a
	ret

;	// dir_cur : out HL -> current 32-byte entry in the data cache.
;	//   CF=1 if the directory is exhausted (also A=FE_IO on read error).
dir_cur:
	ld a,(dc_mode)
	or a
	jr nz,.clus
	ld hl,(dc_secleft)
	ld a,h
	or l
	jr z,.end
	jr .load
.clus:
	ld hl,dc_curclus
	call clus_is_last
	jr c,.end
.load:
	ld hl,dc_lba
	ld de,reqlba
	call mov32
	ld a,1
	call cache_get
	jr c,.ioerr
	ld de,(dc_entoff)
	add hl,de
	or a
	ret
.end:
	scf
	ret
.ioerr:
	ld a,FE_IO
	scf
	ret

;	// dir_next : advance to the next entry.  CF=1 + A=FE_IO on read error.
dir_next:
	ld hl,(dc_entoff)
	ld de,32
	add hl,de
	ld (dc_entoff),hl
	ld a,h
	cp 0x02
	jr nc,.nextsec
	or a
	ret
.nextsec:
	xor a
	ld (dc_entoff),a
	ld (dc_entoff+1),a
	ld a,(dc_mode)
	or a
	jr nz,.clus
	ld hl,(dc_secleft)
	dec hl
	ld (dc_secleft),hl
	ld hl,dc_lba
	call inc32
	or a
	ret
.clus:
	ld a,(dc_secincl)
	inc a
	ld b,a
	ld a,(fat_vol+VOL_SPC)
	cp b
	jr z,.nextclus
	ld a,b
	ld (dc_secincl),a
	ld hl,dc_lba
	call inc32
	or a
	ret
.nextclus:
	ld hl,dc_curclus
	ld de,dc_lastclus
	call mov32
	ld hl,dc_curclus
	ld de,cl_in
	call mov32
	call fat_get
	ret c
	ld hl,cl_out
	ld de,dc_curclus
	call mov32
	ld hl,dc_curclus
	call clus_is_last
	jr c,.done
	xor a
	ld (dc_secincl),a
	ld hl,dc_curclus
	call clus_to_lba
	ld hl,reqlba
	ld de,dc_lba
	call mov32
.done:
	or a
	ret

;	// dir_scan : search directory cl_dir for name83.
;	//   out: found_ent / found_lba / found_off filled; CF=0 on hit.
;	//        CF=1 + A=FE_NOENT (or FE_IO) on miss.
dir_scan:
	call dir_first
.loop:
	call dir_cur
	jr c,.miss
	ld a,(hl)
	or a
	jr z,.notfound
	cp 0xE5
	jr z,.skip
	push hl
	ld de,DE_ATTR
	add hl,de
	ld a,(hl)
	pop hl
	cp ATTR_LFN
	jr z,.skip
	and ATTR_VOLID
	jr nz,.skip
	call cmp_name83
	jr z,.hit
.skip:
	call dir_next
	ret c
	jr .loop
.hit:
	ld de,found_ent
	ld bc,32
	push hl
	ldir
	pop hl
	ld hl,dc_lba
	ld de,found_lba
	call mov32
	ld hl,(dc_entoff)
	ld (found_off),hl
	or a
	ret
.notfound:
	ld a,FE_NOENT
.miss:
	scf
	ret

	IFNDEF RO
;	// dir_alloc_entry : find / create a free 32-byte slot in directory
;	//   cl_dir.  out: found_lba/found_off = slot location; CF=err.
dir_alloc_entry:
	xor a
	ld (da_have_del),a
	call dir_first
.loop:
	call dir_cur
	jr c,.atend
	ld a,(hl)
	or a
	jr z,.usehere
	cp 0xE5
	jr nz,.next
	ld a,(da_have_del)
	or a
	jr nz,.next
	ld hl,dc_lba
	ld de,da_del_lba
	call mov32
	ld hl,(dc_entoff)
	ld (da_del_off),hl
	ld a,1
	ld (da_have_del),a
.next:
	call dir_next
	ret c
	jr .loop
.usehere:
	ld hl,dc_lba
	ld de,found_lba
	call mov32
	ld hl,(dc_entoff)
	ld (found_off),hl
	or a
	ret
.atend:
	ld a,(da_have_del)
	or a
	jr nz,.usedeleted
	ld a,(dc_mode)
	or a
	jr z,.rootfull
	;	// extend the directory by one cluster
	call fat_alloc
	ret c
	;	// link new cluster after dc_lastclus
	ld hl,dc_lastclus
	ld de,cl_in
	call mov32
	ld hl,cl_out
	ld de,cl_val
	call mov32
	call fat_set
	ret c
	;	// remember new cluster, zero it
	ld hl,cl_out
	ld de,cl_tmp
	call mov32
	ld hl,cl_tmp
	call clus_zero
	ret c
	;	// free slot is at offset 0 of the new cluster
	ld hl,cl_tmp
	call clus_to_lba
	ld hl,reqlba
	ld de,found_lba
	call mov32
	xor a
	ld (found_off),a
	ld (found_off+1),a
	or a
	ret
.usedeleted:
	ld hl,da_del_lba
	ld de,found_lba
	call mov32
	ld hl,(da_del_off)
	ld (found_off),hl
	or a
	ret
.rootfull:
	ld a,FE_NOSPC
	scf
	ret

;	// clus_zero : zero every sector of the cluster pointed to by (HL).
clus_zero:
	call clus_to_lba
	ld a,(fat_vol+VOL_SPC)
	ld (cz_count),a
.l:
	ld a,1
	call cache_get_blank
	ret c
	push hl
	ld d,h
	ld e,l
	inc de
	ld (hl),0
	ld bc,511
	ldir
	pop hl
	call cache_dirty_sel
	call cache_flush_sel
	ret c
	ld hl,reqlba
	call inc32
	ld a,(cz_count)
	dec a
	ld (cz_count),a
	jr nz,.l
	or a
	ret

;	// dir_put_entry : write found_ent (32 bytes) to found_lba/found_off.
dir_put_entry:
	ld hl,found_lba
	ld de,reqlba
	call mov32
	ld a,1
	call cache_get
	ret c
	ld de,(found_off)
	add hl,de
	ex de,hl
	ld hl,found_ent
	ld bc,32
	ldir
	call cache_dirty_sel
	or a
	ret

;	// set_entry_datetime : stamp found_ent date/time fields.
;	//   Fixed timestamp 2026-01-01 00:00.  Patch here to use a real clock.
set_entry_datetime:
	xor a
	ld (found_ent+DE_CRTTMS),a
	ld (found_ent+DE_CRTTIME),a
	ld (found_ent+DE_CRTTIME+1),a
	ld (found_ent+DE_WRTTIME),a
	ld (found_ent+DE_WRTTIME+1),a
	ld hl,0x5C21			;	// (2026-1980)<<9 | 1<<5 | 1
	ld (found_ent+DE_CRTDATE),hl
	ld (found_ent+DE_WRTDATE),hl
	ld (found_ent+DE_ACCDATE),hl
	ret
	ENDIF

;	// =====================================================================
;	// path resolution
;	// =====================================================================

;	// path_find : resolve ASCIIZ path at (HL).
;	//   out CF=0: found_ent/found_lba/found_off describe the target,
;	//             cl_dir = first cluster of the containing directory,
;	//             found_isroot = 1 if the path denotes the volume root.
;	//   out CF=1: A = FE_NOENT / FE_NOTDIR / FE_BADNAME / FE_IO.
path_find:
	ld (pathp),hl
	xor a
	ld (found_isroot),a
	ld a,(fat_vol+VOL_TYPE)
	cp 32
	jr z,.r32
	ld hl,cl_dir
	call clr32
	jr .skipsl
.r32:
	ld hl,fat_vol+VOL_ROOTCLUS
	ld de,cl_dir
	call mov32
.skipsl:
	ld hl,(pathp)
.ss:
	ld a,(hl)
	cp '/'
	jr nz,.c0
	inc hl
	jr .ss
.c0:
	ld (pathp),hl
	ld a,(hl)
	or a
	jr nz,.comploop
	ld a,1
	ld (found_isroot),a
	or a
	ret
.comploop:
	ld hl,(pathp)
	call name_to_83
	ret c
	ld a,(hl)
	cp '/'
	jr nz,.term
.sk2:
	inc hl
	ld a,(hl)
	cp '/'
	jr z,.sk2
.term:
	ld (pathp),hl
	push af
	call dir_scan
	jr c,.scanfail
	pop af
	or a
	jr z,.success
	ld a,(found_ent+DE_ATTR)
	and ATTR_DIR
	jr z,.notdir
	ld hl,found_ent
	call ent_get_clus
	ld hl,cl_tmp
	ld de,cl_dir
	call mov32
	jr .comploop
.success:
	or a
	ret
.notdir:
	ld a,FE_NOTDIR
	scf
	ret
.scanfail:
	pop de				;	// D = saved terminator (0 => last component)
	push af
	ld a,d
	or a
	ld a, 0
	jr nz,.sf1
	inc a
.sf1:
	ld (noent_last),a		;	// 1 if the missing item was the last component
	pop af
	scf
	ret
;	// =====================================================================
;	// file handle layer
;	// =====================================================================

;	// hfield : in C = handle field offset -> HL = handle base + C.
;	//   uses IX as the handle base.  preserves A,DE,IX.
hfield:
	push ix
	pop hl
	ld b,0
	add hl,bc
	ret

;	// handles_init : mark every file handle free.
handles_init:
	ld ix,fat_handles
	ld b,FAT_MAXH
.l:
	ld (ix+FH_INUSE),0
	ld de,FH__SIZE
	add ix,de
	djnz .l
	ret

;	// handle_alloc : find a free handle.  out: IX = handle, A = index.
;	//   CF=1 + A=FE_NOHANDLE if all handles are busy.
handle_alloc:
	ld ix,fat_handles
	ld b,FAT_MAXH
	ld c,0
.l:
	ld a,(ix+FH_INUSE)
	or a
	jr z,.free
	ld de,FH__SIZE
	add ix,de
	inc c
	djnz .l
	ld a,FE_NOHANDLE
	scf
	ret
.free:
	ld a,c
	or a
	ret

;	// handle_ptr : in A = handle index -> IX = handle base.
;	//   CF=1 + A=FE_BADF if the index is invalid or not open.
handle_ptr:
	cp FAT_MAXH
	jr nc,.bad
	ld ix,fat_handles
	or a
	jr z,.got
	ld b,a
	ld de,FH__SIZE
.l:
	add ix,de
	djnz .l
.got:
	ld a,(ix+FH_INUSE)
	or a
	jr z,.bad
	or a
	ret
.bad:
	ld a,FE_BADF
	scf
	ret

;	// =====================================================================
;	// position breakdown + cluster walk
;	// =====================================================================

;	// pos_breakdown : split FH_POS into cluster index / sector / byte.
;	//   sets pb_cidx, pb_sic, pb_boff.  IX = handle.
pos_breakdown:
	ld c,FH_POS
	call hfield
	ld de,t0
	call mov32
	ld a,(t0+0)
	ld (pb_boff),a
	ld a,(t0+1)
	and 1
	ld (pb_boff+1),a
	ld b,9
.sh9:
	ld hl,t0
	call shr32
	djnz .sh9
	ld a,(fat_vol+VOL_SPC)
	dec a
	ld c,a
	ld a,(t0+0)
	and c
	ld (pb_sic),a
	ld hl,t0
	ld de,pb_cidx
	call mov32
	ld a,(fat_vol+VOL_CSHIFT)
	or a
	ret z
	ld b,a
.shc:
	ld hl,pb_cidx
	call shr32
	djnz .shc
	ret

;	// file_locate : make FH_CCLUS the cluster at index pb_cidx.
	IFNDEF RO
;	//   io_extend = 1 allocates clusters as needed; 0 fails past the end.
	ENDIF
;	//   IX = handle.  CF=1 on error.
file_locate:
	ld c,FH_FCLUS
	call hfield
	call iszero32
	jr nz,.havefc
	IFDEF RO
	ld a,FE_RANGE
	scf
	ret
	ELSE
	ld a,(io_extend)
	or a
	jr nz,.alloc1
	ld a,FE_RANGE
	scf
	ret
.alloc1:
	call fat_alloc
	ret c
	ld c,FH_FCLUS
	call hfield
	ex de,hl
	ld hl,cl_out
	call mov32
	set 0,(ix+FH_FLAGS)
	ENDIF
.havefc:
	ld c,FH_CCLUS
	call hfield
	call iszero32
	jr z,.fromstart
	ld c,FH_CIDX
	call hfield
	ld de,pb_cidx
	call cp32
	jr z,.fromcache
	jr c,.fromcache
.fromstart:
	ld c,FH_FCLUS
	call hfield
	ld de,wclus
	call mov32
	ld hl,widx
	call clr32
	jr .walk
.fromcache:
	ld c,FH_CCLUS
	call hfield
	ld de,wclus
	call mov32
	ld c,FH_CIDX
	call hfield
	ld de,widx
	call mov32
.walk:
	ld hl,widx
	ld de,pb_cidx
	call cp32
	jr z,.walkdone
	ld hl,wclus
	ld de,cl_in
	call mov32
	call fat_get
	ret c
	ld hl,cl_out
	call clus_is_last
	IFDEF RO
	jr c,.rangeerr
	jr .advance
	ELSE
	jr nc,.advance
	ld a,(io_extend)
	or a
	jr z,.rangeerr
	call fat_alloc
	ret c
	ld hl,wclus
	ld de,cl_in
	call mov32
	ld hl,cl_out
	ld de,cl_val
	call mov32
	call fat_set
	ret c
	ENDIF
.advance:
	ld hl,cl_out
	ld de,wclus
	call mov32
	ld hl,widx
	call inc32
	jr .walk
.walkdone:
	ld c,FH_CCLUS
	call hfield
	ex de,hl
	ld hl,wclus
	call mov32
	ld c,FH_CIDX
	call hfield
	ex de,hl
	ld hl,pb_cidx
	call mov32
	or a
	ret
.rangeerr:
	ld a,FE_RANGE
	scf
	ret

;	// calc_chunk : io_chunk = min(io_count, 512 - pb_boff).
calc_chunk:
	ld hl,512
	ld de,(pb_boff)
	or a
	sbc hl,de
	ld de,(io_count)
	push hl
	or a
	sbc hl,de
	pop hl
	jr c,.usehl
	jr z,.usehl
	ex de,hl
.usehl:
	ld (io_chunk),hl
	ret

;	// io_advance : FH_POS += io_chunk; io_ptr += io_chunk;
;	//   io_count -= io_chunk; io_done += io_chunk.  IX = handle.
io_advance:
	ld c,FH_POS
	call hfield
	ld de,(io_chunk)
	call add16
	ld hl,(io_ptr)
	ld de,(io_chunk)
	add hl,de
	ld (io_ptr),hl
	ld hl,(io_count)
	ld de,(io_chunk)
	or a
	sbc hl,de
	ld (io_count),hl
	ld hl,(io_done)
	ld de,(io_chunk)
	add hl,de
	ld (io_done),hl
	ret

;	// =====================================================================
;	// fread
;	// =====================================================================
fread:
	push hl
	push bc
	call handle_ptr
	pop bc
	pop hl
	ret c
	bit 0,(ix+FH_MODE)
	jp z,.noread
	ld (io_ptr),hl
	ld (io_count),bc
	ld hl,0
	ld (io_done),hl
.loop:
	ld hl,(io_count)
	ld a,h
	or l
	jr z,.finish
	;	// remaining = FH_SIZE - FH_POS -> t1
	ld c,FH_SIZE
	call hfield
	ld de,t1
	call mov32
	ld c,FH_POS
	call hfield
	ex de,hl
	ld hl,t1
	call sub32
	ld hl,t1
	call iszero32
	jr z,.finish
	call pos_breakdown
	xor a
	ld (io_extend),a
	call file_locate
	jr c,.finish
	ld c,FH_CCLUS
	call hfield
	call clus_to_lba
	ld a,(pb_sic)
	ld hl,reqlba
	call add8
	ld a,1
	call cache_get
	jr c,.ioerr
	push hl
	call calc_chunk
	;	// clamp io_chunk to remaining (t1) when t1 < 65536
	ld a,(t1+2)
	or a
	jr nz,.noclamp
	ld a,(t1+3)
	or a
	jr nz,.noclamp
	ld hl,(t1)
	ld de,(io_chunk)
	or a
	sbc hl,de
	jr nc,.noclamp
	ld hl,(t1)
	ld (io_chunk),hl
.noclamp:
	pop hl
	ld de,(pb_boff)
	add hl,de
	ld de,(io_ptr)
	ld bc,(io_chunk)
	ldir
	call io_advance
	jp .loop
.finish:
	ld bc,(io_done)
	or a
	ret
.ioerr:
	ld a,FE_IO
	scf
	ret
.noread:
	ld a,FE_RDONLY
	scf
	ret

	IFNDEF RO
;	// =====================================================================
;	// fwrite
;	// =====================================================================
fwrite:
	push hl
	push bc
	call handle_ptr
	pop bc
	pop hl
	ret c
	bit 1,(ix+FH_MODE)
	jp z,.nowrite
	ld (io_ptr),hl
	ld (io_count),bc
	ld hl,0
	ld (io_done),hl
.loop:
	ld hl,(io_count)
	ld a,h
	or l
	jr z,.finish
	call pos_breakdown
	ld a,1
	ld (io_extend),a
	call file_locate
	jr c,.err
	ld c,FH_CCLUS
	call hfield
	call clus_to_lba
	ld a,(pb_sic)
	ld hl,reqlba
	call add8
	ld a,1
	call cache_get
	jr c,.ioerr
	push hl
	call calc_chunk
	pop hl
	ld de,(pb_boff)
	add hl,de
	ex de,hl
	ld hl,(io_ptr)
	ld bc,(io_chunk)
	ldir
	call cache_dirty_sel
	call io_advance
	;	// grow FH_SIZE if we wrote past the old end
	ld c,FH_POS
	call hfield
	ld de,t2
	call mov32
	ld c,FH_SIZE
	call hfield
	ld de,t2
	call cp32
	jr nc,.loop
	ld c,FH_SIZE
	call hfield
	ex de,hl
	ld hl,t2
	call mov32
	set 0,(ix+FH_FLAGS)
	jr .loop
.finish:
	ld bc,(io_done)
	or a
	ret
.err:
	push af
	ld bc,(io_done)
	pop af
	ret
.ioerr:
	ld bc,(io_done)
	ld a,FE_IO
	scf
	ret
.nowrite:
	ld a,FE_RDONLY
	scf
	ret
	ENDIF

;	// =====================================================================
;	// fseek / ftell
;	// =====================================================================

;	// fseek : A=handle, B=whence (0 set / 1 fwd-from-cur / 2 back),
;	//   DE:HL = unsigned offset.  out: DE:HL = new position.
fseek:
	ld (seek_off+0),hl
	ld (seek_off+2),de
	ld a,b
	ld (seek_whence),a
	call handle_ptr
	ret c
	ld a,(seek_whence)
	or a
	jr z,.set
	dec a
	jr z,.fwd
	;	// backward from current
	ld c,FH_POS
	call hfield
	ld de,t0
	call mov32
	ld hl,t0
	ld de,seek_off
	call sub32
	jr c,.zero
	jr .clamp
.fwd:
	ld c,FH_POS
	call hfield
	ld de,t0
	call mov32
	ld hl,t0
	ld de,seek_off
	call add32
	jr .clamp
.set:
	ld hl,seek_off
	ld de,t0
	call mov32
	jr .clamp
.zero:
	ld hl,t0
	call clr32
.clamp:
	ld c,FH_SIZE
	call hfield
	ld de,t0
	call cp32			;	// (FH_SIZE) vs t0
	jr nc,.store			;	// FH_SIZE >= t0 : ok
	ld c,FH_SIZE
	call hfield
	ld de,t0
	call mov32			;	// t0 = FH_SIZE
.store:
	ld c,FH_POS
	call hfield
	ex de,hl
	ld hl,t0
	call mov32
	ld hl,(t0+0)
	ld de,(t0+2)
	or a
	ret

;	// ftell : A=handle -> DE:HL = current position.
ftell:
	call handle_ptr
	ret c
	ld l,(ix+FH_POS+0)
	ld h,(ix+FH_POS+1)
	ld e,(ix+FH_POS+2)
	ld d,(ix+FH_POS+3)
	or a
	ret

;	// =====================================================================
;	// fopen
;	// =====================================================================
fopen:
	ld (open_mode),a
	IFDEF RO
	and %11111110
	jr z,.modeok
	ld a,FE_RDONLY
	scf
	ret
.modeok:
	ENDIF
	push hl
	call handle_alloc
	pop hl
	ret c
	ld (open_h),a
	ld (open_ix),ix
	call path_find
	IFDEF RO
	ret c
	ELSE
	jr c,.notfound
	ENDIF
	ld a,(found_ent+DE_ATTR)
	and ATTR_DIR
	jr nz,.eisdir
	IFDEF RO
	call open_into_handle
	ret c
	ELSE
	ld a,(open_mode)
	and %00001100
	cp %00000100
	jr z,.eexist
	call open_into_handle
	ret c
	ld a,(open_mode)
	and %00001100
	cp %00001100
	jr nz,.done
	call trunc_to_zero
	ret c
	jr .done
.notfound:
	cp FE_NOENT
	jr nz,.fail
	ld a,(noent_last)
	or a
	jr z,.failnoent
	ld a,(open_mode)
	and %00001100
	jr z,.failnoent
	call make_empty_file
	ret c
	call open_into_handle
	ret c
.done:
	ENDIF
	ld ix,(open_ix)
	ld (ix+FH_INUSE),1
	ld a,(open_h)
	or a
	ret
.eisdir:
	ld a,FE_ISDIR
	scf
	ret
	IFNDEF RO
.eexist:
	ld a,FE_EXIST
	scf
	ret
.failnoent:
	ld a,FE_NOENT
.fail:
	scf
	ret
	ENDIF

;	// open_into_handle : populate the handle from found_ent.
open_into_handle:
	ld ix,(open_ix)
	IFDEF RO
	ld (ix+FH_MODE),MD_READ
	ELSE
	ld a,(open_mode)
	and %00000011
	ld (ix+FH_MODE),a
	ENDIF
	ld hl,found_ent
	call ent_get_clus
	ld c,FH_FCLUS
	call hfield
	ex de,hl
	ld hl,cl_tmp
	call mov32
	ld c,FH_SIZE
	call hfield
	ex de,hl
	ld hl,found_ent+DE_SIZE
	call mov32
	ld c,FH_POS
	call hfield
	call clr32
	ld c,FH_CCLUS
	call hfield
	call clr32
	ld c,FH_CIDX
	call hfield
	call clr32
	ld c,FH_DELBA
	call hfield
	ex de,hl
	ld hl,found_lba
	call mov32
	ld a,(found_off+0)
	ld (ix+FH_DEOFF+0),a
	ld a,(found_off+1)
	ld (ix+FH_DEOFF+1),a
	ld c,FH_DCLUS
	call hfield
	ex de,hl
	ld hl,cl_dir
	call mov32
	ld (ix+FH_FLAGS),0
	or a
	ret

	IFNDEF RO
;	// make_empty_file : create a zero-length file in directory cl_dir
;	//   using name83.  Fills found_ent/found_lba/found_off.
make_empty_file:
	call dir_alloc_entry
	ret c
	ld hl,name83
	ld de,found_ent
	ld bc,11
	ldir
	ld a,ATTR_ARCHIVE
	ld (found_ent+DE_ATTR),a
	xor a
	ld (found_ent+DE_NTRES),a
	ld (found_ent+DE_CLUSLO+0),a
	ld (found_ent+DE_CLUSLO+1),a
	ld (found_ent+DE_CLUSHI+0),a
	ld (found_ent+DE_CLUSHI+1),a
	ld (found_ent+DE_SIZE+0),a
	ld (found_ent+DE_SIZE+1),a
	ld (found_ent+DE_SIZE+2),a
	ld (found_ent+DE_SIZE+3),a
	call set_entry_datetime
	jp dir_put_entry

;	// trunc_to_zero : free a handle's chain, reset to an empty file.
trunc_to_zero:
	ld ix,(open_ix)
	ld c,FH_FCLUS
	call hfield
	ld de,cl_in
	call mov32
	call fat_free_chain
	ret c
	ld ix,(open_ix)
	ld c,FH_FCLUS
	call hfield
	call clr32
	ld c,FH_SIZE
	call hfield
	call clr32
	ld c,FH_POS
	call hfield
	call clr32
	ld c,FH_CCLUS
	call hfield
	call clr32
	ld c,FH_CIDX
	call hfield
	call clr32
	ld ix,(open_ix)
	set 0,(ix+FH_FLAGS)
	or a
	ret

;	// =====================================================================
;	// fsync / fclose
;	// =====================================================================

;	// fsync : A=handle -> flush file data and the directory entry.
fsync:
	call handle_ptr
	ret c
;	// sync_ix : flush for the handle at IX.
sync_ix:
	bit 0,(ix+FH_FLAGS)
	jr z,.flushonly
	ld c,FH_DELBA
	call hfield
	ld de,reqlba
	call mov32
	ld a,1
	call cache_get
	ret c
	ld e,(ix+FH_DEOFF+0)
	ld d,(ix+FH_DEOFF+1)
	add hl,de			;	// HL -> on-disk entry
	push hl
	ld de,DE_SIZE
	add hl,de
	ex de,hl			;	// DE -> entry size field
	ld c,FH_SIZE
	call hfield
	call mov32
	pop hl				;	// HL -> entry
	push hl
	ld c,FH_FCLUS
	call hfield
	ld de,cl_tmp
	call mov32
	pop hl				;	// HL -> entry (hfield clobbered it)
	call ent_put_clus
	res 0,(ix+FH_FLAGS)
	ld a,1
	call cache_addr
	call cache_dirty_sel
.flushonly:
	jp cache_flush_all
	ENDIF

	IFNDEF RO
;	// fclose : A=handle -> sync and release the handle.
fclose:
	call handle_ptr
	ret c
	call sync_ix
	push af
	ld (ix+FH_INUSE),0
	pop af
	ret
	ELSE
;	// fclose : A=handle -> release the handle.
fclose:
	call handle_ptr
	ret c
	ld (ix+FH_INUSE),0
	or a
	ret
	ENDIF

;	// =====================================================================
;	// fopendir / freaddir
;	// =====================================================================
fopendir:
	push hl
	call handle_alloc
	pop hl
	ret c
	ld (open_h),a
	ld (open_ix),ix
	call path_find
	ret c
	ld a,(found_isroot)
	or a
	jr nz,.useroot
	ld a,(found_ent+DE_ATTR)
	and ATTR_DIR
	jr z,.enotdir
	ld hl,found_ent
	call ent_get_clus
	jr .setup
.useroot:
	ld hl,cl_dir
	ld de,cl_tmp
	call mov32
.setup:
	ld ix,(open_ix)
	ld c,FH_FCLUS
	call hfield
	ex de,hl
	ld hl,cl_tmp
	call mov32
	ld ix,(open_ix)
	ld (ix+FH_MODE),MD_ISDIR
	ld c,FH_POS
	call hfield
	call clr32
	ld ix,(open_ix)
	ld (ix+FH_FLAGS),0
	ld (ix+FH_INUSE),1
	ld a,(open_h)
	or a
	ret
.enotdir:
	ld a,FE_NOTDIR
	scf
	ret

;	// freaddir : A=handle, HL=18-byte record buffer.
;	//   CF=0 record filled; CF=1 + A=FE_NOENT at end of directory.
freaddir:
	ld (rd_buf),hl
	call handle_ptr
	ret c
	bit 5,(ix+FH_MODE)
	jr z,.notdir
	ld c,FH_FCLUS
	call hfield
	ld de,cl_dir
	call mov32
	call dir_first
	;	// skip FH_POS/32 entries
	ld c,FH_POS
	call hfield
	ld de,t0
	call mov32
	ld b,5
.sh:
	ld hl,t0
	call shr32
	djnz .sh
	ld bc,(t0)
.skip:
	ld a,b
	or c
	jr z,.scan
	dec bc
	push bc
	call dir_next
	pop bc
	ret c
	jr .skip
.scan:
	call dir_cur
	jr c,.end
	ld a,(hl)
	or a
	jr z,.end
	cp 0xE5
	jr z,.skipone
	push hl
	ld de,DE_ATTR
	add hl,de
	ld a,(hl)
	pop hl
	cp ATTR_LFN
	jr z,.skipone
	and ATTR_VOLID
	jr nz,.skipone
	call fill_rd_buf
	ld c,FH_POS
	call hfield
	ld de,32
	call add16
	or a
	ret
.skipone:
	ld c,FH_POS
	call hfield
	ld de,32
	call add16
	call dir_next
	ret c
	jr .scan
.end:
	ld a,FE_NOENT
	scf
	ret
.notdir:
	ld a,FE_NOTDIR
	scf
	ret

;	// fill_rd_buf : HL -> 32-byte entry; build the 18-byte readdir record.
fill_rd_buf:
	ld (rd_ent),hl
	;	// attribute -> record+0
	ld de,(rd_buf)
	ld bc,DE_ATTR
	add hl,bc
	ld a,(hl)
	ld (de),a
	inc de
	ld (rd_dst),de
	;	// trimmed name length
	ld hl,(rd_ent)
	ld b,8
	ld c,0
	ld d,0
.nl:
	ld a,(hl)
	inc hl
	cp ' '
	jr z,.nl1
	inc d
	ld c,d
	dec d
.nl1:
	inc d
	djnz .nl
	;	// copy C name characters
	ld hl,(rd_ent)
	ld de,(rd_dst)
	ld a,c
	or a
	jr z,.nx
	ld b,c
.ncp:
	ld a,(hl)
	ld (de),a
	inc hl
	inc de
	djnz .ncp
.nx:
	ld (rd_dst),de
	;	// trimmed extension length
	ld hl,(rd_ent)
	ld bc,8
	add hl,bc
	ld b,3
	ld c,0
	ld d,0
.el:
	ld a,(hl)
	inc hl
	cp ' '
	jr z,.el1
	inc d
	ld c,d
	dec d
.el1:
	inc d
	djnz .el
	ld a,c
	ld (rd_elen),a
	or a
	jr z,.noext
	ld de,(rd_dst)
	ld a,'.'
	ld (de),a
	inc de
	ld hl,(rd_ent)
	ld bc,8
	add hl,bc
	ld a,(rd_elen)
	ld b,a
.ecp:
	ld a,(hl)
	ld (de),a
	inc hl
	inc de
	djnz .ecp
	ld (rd_dst),de
.noext:
	ld de,(rd_dst)
	xor a
	ld (de),a			;	// ASCIIZ terminator
	;	// file size -> record+14
	ld hl,(rd_ent)
	ld bc,DE_SIZE
	add hl,bc
	ld de,(rd_buf)
	ex de,hl
	ld bc,14
	add hl,bc
	ex de,hl
	jp mov32
	IFNDEF RO
;	// =====================================================================
;	// high-level operations
;	// =====================================================================

;	// build_dotent : HL -> 32-byte dest, B = dot count, cl_tmp = cluster.
;	//   Builds a "." / ".." directory entry.  HL preserved.
build_dotent:
	push hl
	ld d,h
	ld e,l
	inc de
	ld (hl),0
	push bc
	ld bc,31
	ldir
	pop bc
	pop hl
	push hl
	push bc
	ld b,11
	ld a,' '
.sp:
	ld (hl),a
	inc hl
	djnz .sp
	pop bc
	pop hl
	push hl
	ld a,'.'
.dt:
	ld (hl),a
	inc hl
	djnz .dt
	pop hl
	push hl
	ld de,DE_ATTR
	add hl,de
	ld (hl),ATTR_DIR
	pop hl
	jp ent_put_clus

;	// unlink : delete the file at path (HL).
unlink:
	call path_find
	ret c
	ld a,(found_isroot)
	or a
	jr nz,.eisdir
	ld a,(found_ent+DE_ATTR)
	and ATTR_DIR
	jr nz,.eisdir
	ld hl,found_ent
	call ent_get_clus
	ld hl,cl_tmp
	ld de,cl_in
	call mov32
	call fat_free_chain
	ret c
	ld a,0xE5
	ld (found_ent+DE_NAME),a
	call dir_put_entry
	ret c
	jp cache_flush_all
.eisdir:
	ld a,FE_ISDIR
	scf
	ret

;	// mkdir : create the directory at path (HL).
mkdir:
	call path_find
	jp nc,.eexist
	cp FE_NOENT
	jp nz,.fail
	ld a,(noent_last)
	or a
	jp z,.failnoent
	ld hl,cl_dir
	ld de,mk_parent
	call mov32
	call dir_alloc_entry
	ret c
	call fat_alloc
	ret c
	ld hl,cl_out
	ld de,mk_clus
	call mov32
	ld hl,mk_clus
	call clus_zero
	ret c
	;	// write "." and ".." into the new cluster
	ld hl,mk_clus
	call clus_to_lba
	ld a,1
	call cache_get
	ret c
	push hl
	ld hl,mk_clus
	ld de,cl_tmp
	call mov32
	pop hl
	push hl
	ld b,1
	call build_dotent
	pop hl
	ld de,32
	add hl,de
	push hl
	ld hl,mk_parent
	ld de,cl_tmp
	call mov32
	pop hl
	ld b,2
	call build_dotent
	ld a,1
	call cache_addr
	call cache_dirty_sel
	;	// build the parent directory entry
	ld hl,name83
	ld de,found_ent
	ld bc,11
	ldir
	ld a,ATTR_DIR
	ld (found_ent+DE_ATTR),a
	xor a
	ld (found_ent+DE_NTRES),a
	ld (found_ent+DE_SIZE+0),a
	ld (found_ent+DE_SIZE+1),a
	ld (found_ent+DE_SIZE+2),a
	ld (found_ent+DE_SIZE+3),a
	call set_entry_datetime
	ld hl,mk_clus
	ld de,cl_tmp
	call mov32
	ld hl,found_ent
	call ent_put_clus
	call dir_put_entry
	ret c
	jp cache_flush_all
.eexist:
	ld a,FE_EXIST
	scf
	ret
.failnoent:
	ld a,FE_NOENT
.fail:
	scf
	ret

;	// rmdir : remove the empty directory at path (HL).
rmdir:
	call path_find
	ret c
	ld a,(found_isroot)
	or a
	jr nz,.ebusy
	ld a,(found_ent+DE_ATTR)
	and ATTR_DIR
	jr z,.enotdir
	ld hl,found_ent
	call ent_get_clus
	ld hl,cl_tmp
	ld de,rm_save
	call mov32
	;	// scan for non-empty contents
	ld hl,rm_save
	ld de,cl_dir
	call mov32
	call dir_first
.chk:
	call dir_cur
	jr c,.empty
	ld a,(hl)
	or a
	jr z,.empty
	cp 0xE5
	jr z,.chknext
	push hl
	ld de,DE_ATTR
	add hl,de
	ld a,(hl)
	pop hl
	cp ATTR_LFN
	jr z,.chknext
	and ATTR_VOLID
	jr nz,.chknext
	ld a,(hl)
	cp '.'
	jr nz,.notempty
.chknext:
	call dir_next
	ret c
	jr .chk
.empty:
	ld hl,rm_save
	ld de,cl_in
	call mov32
	call fat_free_chain
	ret c
	ld a,0xE5
	ld (found_ent+DE_NAME),a
	call dir_put_entry
	ret c
	jp cache_flush_all
.notempty:
	ld a,FE_NOTEMPTY
	scf
	ret
.enotdir:
	ld a,FE_NOTDIR
	scf
	ret
.ebusy:
	ld a,FE_ISDIR
	scf
	ret

;	// frename : rename / move HL=oldpath to DE=newpath.
;	//   NOTE: moving a directory to a different parent does not rewrite
;	//   its ".." entry.
frename:
	ld (rn_newp),de
	call path_find
	ret c
	ld a,(found_isroot)
	or a
	jr nz,.ebad
	ld hl,found_ent
	ld de,rn_ent
	ld bc,32
	ldir
	ld hl,found_lba
	ld de,rn_lba
	call mov32
	ld hl,(found_off)
	ld (rn_off),hl
	ld hl,(rn_newp)
	call path_find
	jr nc,.eexist
	cp FE_NOENT
	jr nz,.fail
	ld a,(noent_last)
	or a
	jr z,.failnoent
	call dir_alloc_entry
	ret c
	ld hl,rn_ent
	ld de,found_ent
	ld bc,32
	ldir
	ld hl,name83
	ld de,found_ent
	ld bc,11
	ldir
	call dir_put_entry
	ret c
	ld hl,rn_lba
	ld de,found_lba
	call mov32
	ld hl,(rn_off)
	ld (found_off),hl
	ld hl,rn_ent
	ld de,found_ent
	ld bc,32
	ldir
	ld a,0xE5
	ld (found_ent+DE_NAME),a
	call dir_put_entry
	ret c
	jp cache_flush_all
.eexist:
	ld a,FE_EXIST
	scf
	ret
.failnoent:
	ld a,FE_NOENT
.fail:
	scf
	ret
.ebad:
	ld a,FE_BADNAME
	scf
	ret

;	// ftruncate : truncate the open file (A=handle) to its position.
ftruncate:
	call handle_ptr
	ret c
	bit 1,(ix+FH_MODE)
	jp z,.nowrite
	ld c,FH_POS
	call hfield
	call iszero32
	jr nz,.nonzero
	ld c,FH_FCLUS
	call hfield
	ld de,cl_in
	call mov32
	call fat_free_chain
	ret c
	ld c,FH_FCLUS
	call hfield
	call clr32
	ld c,FH_CCLUS
	call hfield
	call clr32
	ld c,FH_CIDX
	call hfield
	call clr32
	jr .setsize
.nonzero:
	ld c,FH_POS
	call hfield
	ld de,t0
	call mov32
	ld hl,t0
	call dec32
	ld b,9
.s9:
	ld hl,t0
	call shr32
	djnz .s9
	ld a,(fat_vol+VOL_CSHIFT)
	or a
	jr z,.noc
	ld b,a
.sc:
	ld hl,t0
	call shr32
	djnz .sc
.noc:
	ld hl,t0
	ld de,pb_cidx
	call mov32
	xor a
	ld (io_extend),a
	call file_locate
	ret c
	ld c,FH_CCLUS
	call hfield
	ld de,cl_in
	call mov32
	call fat_get
	ret c
	call set_clval_eoc
	call fat_set
	ret c
	ld hl,cl_out
	ld de,cl_in
	call mov32
	call fat_free_chain
	ret c
.setsize:
	ld c,FH_POS
	call hfield
	ld de,t0
	call mov32
	ld c,FH_SIZE
	call hfield
	ex de,hl
	ld hl,t0
	call mov32
	set 0,(ix+FH_FLAGS)
	jp cache_flush_all
.nowrite:
	ld a,FE_RDONLY
	scf
	ret
	ENDIF

;	// =====================================================================
;	// driver RAM  (uninitialised working storage)
;	// =====================================================================
fat_bss:
fat_vol:		ds VOL__SIZE
fat_handles:	ds FH__SIZE*FAT_MAXH

slot_lba:	ds 8
slot_flags:	ds 2
cbufp:		ds 2
clbap:		ds 2
cflagp:		ds 2
reqlba:		ds 4
mtmp:		ds 4
mcount:		ds 1

m_partbase:	ds 4
t0:		ds 4
t1:		ds 4
mount_dbg:	ds 6
t2:		ds 4
t3:		ds 4
cl_in:		ds 4
cl_out:		ds 4
cl_val:		ds 4
cl_scan:	ds 4
cl_dir:		ds 4
cl_tmp:		ds 4
fatidx:		ds 2

name83:		ds 11
found_ent:	ds 32
found_lba:	ds 4
found_off:	ds 2
found_isroot:	ds 1
da_have_del:	ds 1
da_del_lba:	ds 4
da_del_off:	ds 2
pathp:		ds 2
noent_last:	ds 1

dc_mode:	ds 1
dc_curclus:	ds 4
dc_lastclus:	ds 4
dc_lba:		ds 4
dc_secleft:	ds 2
dc_secincl:	ds 1
dc_entoff:	ds 2
cz_count:	ds 1

pb_cidx:	ds 4
pb_sic:		ds 1
pb_boff:	ds 2
wclus:		ds 4
widx:		ds 4
io_ptr:		ds 2
io_count:	ds 2
io_done:	ds 2
io_chunk:	ds 2
io_extend:	ds 1
open_mode:	ds 1
open_h:		ds 1
open_ix:	ds 2
seek_off:	ds 4
seek_whence:	ds 1
rd_buf:		ds 2
rd_ent:		ds 2
rd_dst:		ds 2
rd_elen:	ds 1

mk_clus:	ds 4
mk_parent:	ds 4
rm_save:	ds 4
rn_ent:		ds 32
rn_lba:		ds 4
rn_off:		ds 2
rn_newp:	ds 2
gl_dst:		ds 2

;	// 512-byte cache buffers last, so the rest stays compact
slot_buf0:	ds 512
slot_buf1:	ds 512
fat_bss_end:
