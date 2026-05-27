;	// =====================================================================
;	// dosya.asm -- main Dosya file
;	// =====================================================================
;	//
;	// Public API:
;	//   dosya_init            Inits dosya and all it's subsystems

    include "fat.asm"
    include "path.asm"
    include "spi.asm"

dosya_init:
    call path_init
    call sd_init
    ret c
    jp fat_mount
