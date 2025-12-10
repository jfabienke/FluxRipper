;==============================================================================
; FluxRipper FDD BIOS - Drive Type Detection
;==============================================================================
; Maps FPGA DRIVE_PROFILE register values to BIOS drive type codes.
; This eliminates the need for manual F2 configuration like Sergey's BIOS.
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

;==============================================================================
; Map Drive Types
;==============================================================================
; Converts all detected drive profiles to BIOS type codes.
;
; Input:  [drive_profiles] = populated profile array
; Output: [drive_types] = BIOS type codes for each drive
;         [drive_params] = geometry for each drive
;==============================================================================
map_drive_types:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si
    push    di

    ; Process each drive
    mov     cl, [num_drives]
    xor     ch, ch
    test    cl, cl
    jz      .done

    xor     dl, dl                  ; Drive number

.map_loop:
    push    cx

    ; Map this drive's profile to type
    call    profile_to_type
    mov     si, drive_types
    mov     bh, 0
    mov     bl, dl
    mov     [si+bx], al             ; Store type code

    ; Set up geometry based on type
    call    type_to_geometry

    pop     cx
    inc     dl
    loop    .map_loop

.done:
    pop     di
    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

;==============================================================================
; Profile to Type
;==============================================================================
; Converts a single drive profile to a BIOS type code.
;
; Input:  DL = drive number (0-3)
; Output: AL = BIOS drive type code
;==============================================================================
profile_to_type:
    push    bx
    push    cx
    push    dx
    push    si

    ; Get the profile
    call    get_drive_profile
    jc      .unknown

    ; Extract form factor, density, and tracks
    ; Profile byte 0: [5:4]=tracks, [3:2]=density, [1:0]=form
    mov     bl, al                  ; Save byte 0

    ; Determine type based on form factor and density
    mov     al, bl
    and     al, FORM_MASK           ; Form factor

    cmp     al, FORM_35
    je      .form_35
    cmp     al, FORM_525
    je      .form_525
    cmp     al, FORM_8
    je      .form_8
    jmp     .unknown

.form_35:
    ; 3.5" drive - check density
    mov     al, bl
    and     al, DENS_MASK
    shr     al, DENS_SHIFT

    cmp     al, DENS_DD
    je      .type_720k
    cmp     al, DENS_HD
    je      .type_1440k
    cmp     al, DENS_ED
    je      .type_2880k
    jmp     .unknown

.type_720k:
    mov     al, DTYPE_720K
    jmp     .done

.type_1440k:
    mov     al, DTYPE_1440K
    jmp     .done

.type_2880k:
    mov     al, DTYPE_2880K
    jmp     .done

.form_525:
    ; 5.25" drive - check density and tracks
    mov     al, bl
    and     al, DENS_MASK
    shr     al, DENS_SHIFT

    cmp     al, DENS_DD
    je      .type_360k
    cmp     al, DENS_HD
    je      .type_1200k
    jmp     .unknown

.type_360k:
    mov     al, DTYPE_360K
    jmp     .done

.type_1200k:
    mov     al, DTYPE_1200K
    jmp     .done

.form_8:
    ; 8" drive - check density and encoding
    mov     al, bl
    and     al, DENS_MASK
    shr     al, DENS_SHIFT

    ; Check encoding type for SD/FM detection
    push    bx
    mov     al, bl
    and     al, (ENC_MASK >> 8)         ; Encoding is in bits 8:6
    mov     cl, 6
    shr     al, cl
    pop     bx

    cmp     al, ENC_FM                  ; FM encoding = Single Density
    je      .type_8_sd

    ; MFM encoding - check for DD vs PC-compat vs CP/M
    ; Look at sector size in profile bits 10:9
    mov     ax, [si]                    ; Get profile word
    and     ax, SECSIZE_MASK
    mov     cl, SECSIZE_SHIFT
    shr     ax, cl

    cmp     al, SECSIZE_128
    je      .type_8_sd                  ; 128-byte sectors = SD (should be FM)
    cmp     al, SECSIZE_256
    je      .type_8_cpm                 ; 256-byte sectors = CP/M format
    cmp     al, SECSIZE_512
    je      .type_8_pc                  ; 512-byte sectors = PC-compatible
    cmp     al, SECSIZE_1024
    je      .type_8_dd                  ; 1024-byte sectors = standard 8" DD
    jmp     .type_8_dd                  ; Default to DD

.type_8_sd:
    mov     al, DTYPE_8_SD
    jmp     .done

.type_8_dd:
    mov     al, DTYPE_8_DD
    jmp     .done

.type_8_pc:
    mov     al, DTYPE_8_PC
    jmp     .done

.type_8_cpm:
    mov     al, DTYPE_8_CPM
    jmp     .done

.unknown:
    mov     al, DTYPE_NONE

.done:
    pop     si
    pop     dx
    pop     cx
    pop     bx
    ret

;==============================================================================
; Type to Geometry
;==============================================================================
; Sets up drive geometry based on BIOS type code.
;
; Input:  DL = drive number (0-3)
;         AL = BIOS type code
; Output: [drive_params] updated with geometry
;==============================================================================
type_to_geometry:
    push    ax
    push    bx
    push    cx
    push    si

    ; Calculate offset into drive_params (4 bytes per drive)
    mov     bl, dl
    xor     bh, bh
    shl     bx, 2                   ; Multiply by 4
    mov     si, drive_params
    add     si, bx

    ; Look up geometry based on type
    cmp     al, DTYPE_360K
    je      .geom_360k
    cmp     al, DTYPE_1200K
    je      .geom_1200k
    cmp     al, DTYPE_720K
    je      .geom_720k
    cmp     al, DTYPE_1440K
    je      .geom_1440k
    cmp     al, DTYPE_2880K
    je      .geom_2880k
    cmp     al, DTYPE_8_SD
    je      .geom_8_sd
    cmp     al, DTYPE_8_DD
    je      .geom_8_dd
    cmp     al, DTYPE_8_PC
    je      .geom_8_pc
    cmp     al, DTYPE_8_CPM
    je      .geom_8_cpm
    jmp     .geom_none

.geom_360k:
    ; 5.25" DD: 40 cyl, 2 heads, 9 spt
    mov     word [si], 40           ; Cylinders
    mov     byte [si+2], 2          ; Heads
    mov     byte [si+3], 9          ; Sectors per track
    jmp     .done

.geom_1200k:
    ; 5.25" HD: 80 cyl, 2 heads, 15 spt
    mov     word [si], 80
    mov     byte [si+2], 2
    mov     byte [si+3], 15
    jmp     .done

.geom_720k:
    ; 3.5" DD: 80 cyl, 2 heads, 9 spt
    mov     word [si], 80
    mov     byte [si+2], 2
    mov     byte [si+3], 9
    jmp     .done

.geom_1440k:
    ; 3.5" HD: 80 cyl, 2 heads, 18 spt
    mov     word [si], 80
    mov     byte [si+2], 2
    mov     byte [si+3], 18
    jmp     .done

.geom_2880k:
    ; 3.5" ED: 80 cyl, 2 heads, 36 spt
    mov     word [si], 80
    mov     byte [si+2], 2
    mov     byte [si+3], 36
    jmp     .done

.geom_8_sd:
    ; 8" SD (FM): 77 cyl, 1 head, 26 spt (128-byte sectors)
    ; IBM 3740 format: 250K capacity
    mov     word [si], 77
    mov     byte [si+2], 1
    mov     byte [si+3], 26
    jmp     .done

.geom_8_dd:
    ; 8" DD (MFM): 77 cyl, 2 heads, 8 spt (1024-byte sectors)
    ; IBM System/34 format: 1.2M capacity
    mov     word [si], 77
    mov     byte [si+2], 2
    mov     byte [si+3], 8
    jmp     .done

.geom_8_pc:
    ; 8" PC-compatible: 77 cyl, 2 heads, 15 spt (512-byte sectors)
    ; 1.2M capacity, PC-like format
    mov     word [si], 77
    mov     byte [si+2], 2
    mov     byte [si+3], 15
    jmp     .done

.geom_8_cpm:
    ; 8" CP/M: 77 cyl, 1 head, 26 spt (256-byte sectors)
    ; Standard CP/M-80 format: 500K capacity
    mov     word [si], 77
    mov     byte [si+2], 1
    mov     byte [si+3], 26
    jmp     .done

.geom_none:
    ; No drive or unknown
    mov     word [si], 0
    mov     byte [si+2], 0
    mov     byte [si+3], 0

.done:
    pop     si
    pop     cx
    pop     bx
    pop     ax
    ret

;==============================================================================
; Get Data Rate for Type
;==============================================================================
; Returns the appropriate data rate for a drive type.
;
; Input:  AL = BIOS drive type code
; Output: AL = data rate code (for FDC DSR/CCR register)
;
; Note: For 8" FM drives, the FPGA translates FM to MFM internally,
;       so we use 250K rate. The FPGA handles clock/data separation.
;==============================================================================
get_data_rate:
    ; Standard PC drive types
    cmp     al, DTYPE_360K
    je      .rate_250k                  ; 5.25" DD: 250 Kbps
    cmp     al, DTYPE_720K
    je      .rate_250k                  ; 3.5" DD: 250 Kbps
    cmp     al, DTYPE_1200K
    je      .rate_500k                  ; 5.25" HD: 500 Kbps
    cmp     al, DTYPE_1440K
    je      .rate_500k                  ; 3.5" HD: 500 Kbps
    cmp     al, DTYPE_2880K
    je      .rate_1m                    ; 3.5" ED: 1 Mbps

    ; 8" drive types
    cmp     al, DTYPE_8_SD
    je      .rate_250k                  ; 8" SD FM: 250 Kbps (FPGA translates)
    cmp     al, DTYPE_8_DD
    je      .rate_500k                  ; 8" DD MFM: 500 Kbps
    cmp     al, DTYPE_8_PC
    je      .rate_500k                  ; 8" PC: 500 Kbps
    cmp     al, DTYPE_8_CPM
    je      .rate_500k                  ; 8" CP/M: 500 Kbps

    ; Default to 250K for unknown types
    jmp     .rate_250k

.rate_250k:
    mov     al, RATE_250K
    ret

.rate_500k:
    mov     al, RATE_500K
    ret

.rate_1m:
    mov     al, RATE_1M
    ret

;==============================================================================
; Get Drive Type String
;==============================================================================
; Returns a pointer to a descriptive string for a drive type.
;
; Input:  AL = BIOS drive type code
; Output: SI = pointer to null-terminated string
;==============================================================================
get_type_string:
    ; Standard PC drive types
    cmp     al, DTYPE_360K
    je      .str_360k
    cmp     al, DTYPE_1200K
    je      .str_1200k
    cmp     al, DTYPE_720K
    je      .str_720k
    cmp     al, DTYPE_1440K
    je      .str_1440k
    cmp     al, DTYPE_2880K
    je      .str_2880k

    ; 8" drive types
    cmp     al, DTYPE_8_SD
    je      .str_8_sd
    cmp     al, DTYPE_8_DD
    je      .str_8_dd
    cmp     al, DTYPE_8_PC
    je      .str_8_pc
    cmp     al, DTYPE_8_CPM
    je      .str_8_cpm

    ; Default: unknown
    mov     si, str_unknown
    ret

.str_360k:
    mov     si, str_360k
    ret
.str_1200k:
    mov     si, str_1200k
    ret
.str_720k:
    mov     si, str_720k
    ret
.str_1440k:
    mov     si, str_1440k
    ret
.str_2880k:
    mov     si, str_2880k
    ret
.str_8_sd:
    mov     si, str_8_sd
    ret
.str_8_dd:
    mov     si, str_8_dd
    ret
.str_8_pc:
    mov     si, str_8_pc
    ret
.str_8_cpm:
    mov     si, str_8_cpm
    ret

; Type strings - Standard PC drives
str_360k:   db "5.25'' 360K", 0
str_1200k:  db "5.25'' 1.2M", 0
str_720k:   db "3.5'' 720K", 0
str_1440k:  db "3.5'' 1.44M", 0
str_2880k:  db "3.5'' 2.88M", 0

; Type strings - 8" drives (FluxRipper extended)
str_8_sd:   db "8'' SD (FM)", 0
str_8_dd:   db "8'' DD 1.2M", 0
str_8_pc:   db "8'' PC 1.2M", 0
str_8_cpm:  db "8'' CP/M", 0

str_unknown: db "Unknown", 0
