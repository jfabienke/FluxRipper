;==============================================================================
; FluxRipper HDD BIOS - Geometry Translation
;==============================================================================
; C/H/S to LBA translation and parameter conversion routines.
;
; Translation Modes:
;   - None:   Physical = Logical (small drives)
;   - Normal: Standard INT 13h limits (1024 cyl / 16 heads / 63 sectors)
;   - Large:  ECHS mapping for drives > 504MB
;   - LBA:    Direct LBA addressing (bypasses C/H/S entirely)
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

;==============================================================================
; Convert CHS to LBA
;==============================================================================
; Converts Cylinder/Head/Sector address to Linear Block Address.
;
; Formula: LBA = (C * H_max + H) * S_max + S - 1
;
; Input:  CX = cylinder (as packed in INT 13h format)
;         DH = head
;         DL = drive (to look up geometry)
;         (Also uses: CL bits 0-5 = sector)
; Output: DX:AX = 32-bit LBA
;         CF = 0 if success, CF = 1 if invalid parameters
; Destroys: BX, CX
;==============================================================================
chs_to_lba:
    push    si

    ; Get drive geometry
    push    dx
    call    get_drive_params
    pop     dx
    jc      .error

    ; Extract physical geometry
    ; SI points to drive params: [cyl_lo, cyl_hi, heads, sectors, flags, ...]

    ; Extract cylinder from CX
    ; CH = low 8 bits, CL bits 6-7 = high 2 bits
    mov     bx, cx
    mov     al, bh                  ; AL = low 8 bits (CH)
    mov     ah, bl                  ; AH = CL
    shr     ah, 6                   ; AH = high 2 bits
    ; AX now has cylinder number

    push    ax                      ; Save cylinder

    ; Heads per cylinder
    xor     bh, bh
    mov     bl, [si + 2]            ; BX = heads per cylinder

    ; Cylinder * heads
    mul     bx                      ; DX:AX = cylinder * heads

    ; Add head number
    xor     bh, bh
    mov     bl, dh                  ; BX = head
    add     ax, bx
    adc     dx, 0                   ; DX:AX = (C * H) + H

    ; Sectors per track
    xor     bh, bh
    mov     bl, [si + 3]            ; BX = sectors per track

    ; (C*H + H) * sectors
    push    dx                      ; Save high word
    mul     bx                      ; DX:AX = low * sectors
    mov     cx, ax                  ; Save low result
    pop     ax                      ; Get saved high word
    push    dx                      ; Save new high word
    mul     bx                      ; DX:AX = high * sectors
    pop     bx                      ; Get saved high
    add     ax, bx                  ; Combine
    mov     dx, ax                  ; DX = final high word
    mov     ax, cx                  ; AX = final low word

    ; Add (sector - 1)
    pop     cx                      ; Restore cylinder (not needed, but clean stack)
    push    ax
    mov     al, cl
    and     al, 0x3F                ; Extract sector number (1-63)
    dec     al                      ; Sector - 1 (sectors are 1-based)
    xor     ah, ah
    mov     bx, ax                  ; BX = sector - 1
    pop     ax
    add     ax, bx
    adc     dx, 0                   ; DX:AX = final LBA

    clc
    pop     si
    ret

.error:
    stc
    pop     si
    ret

;==============================================================================
; Convert LBA to CHS
;==============================================================================
; Converts Linear Block Address to Cylinder/Head/Sector.
;
; Formula:
;   Sector   = (LBA mod S_max) + 1
;   Head     = (LBA / S_max) mod H_max
;   Cylinder = LBA / (S_max * H_max)
;
; Input:  DX:AX = 32-bit LBA
;         BL = drive (80h or 81h)
; Output: CH = cylinder low 8 bits
;         CL = sector (bits 0-5) | cylinder high (bits 6-7)
;         DH = head
;         CF = 0 if success, CF = 1 if out of range
; Destroys: AX, BX, DX, SI
;==============================================================================
lba_to_chs:
    push    di

    ; Save LBA
    mov     di, dx                  ; DI = LBA high
    push    ax                      ; Stack: LBA low

    ; Get drive geometry
    push    bx
    mov     dl, bl
    call    get_drive_params
    pop     bx
    jc      .error

    ; Get sectors per track
    xor     ch, ch
    mov     cl, [si + 3]            ; CX = sectors per track

    ; LBA / sectors_per_track
    pop     ax                      ; AX = LBA low
    mov     dx, di                  ; DX = LBA high
    div     cx                      ; AX = quotient, DX = remainder
    inc     dl                      ; Sector = remainder + 1 (1-based)
    mov     [.sector], dl           ; Save sector

    ; Quotient / heads
    xor     dx, dx                  ; Clear for division
    xor     ch, ch
    mov     cl, [si + 2]            ; CX = heads
    div     cx                      ; AX = cylinder, DX = head

    mov     [.head], dl             ; Save head

    ; Check cylinder limit
    cmp     ax, 1024                ; INT 13h limit
    jae     .overflow

    ; Pack result
    mov     ch, al                  ; CH = cylinder low 8 bits
    mov     cl, [.sector]           ; CL = sector
    shl     ah, 6                   ; Cylinder high bits to 6-7
    or      cl, ah                  ; CL = sector | (cyl_high << 6)
    mov     dh, [.head]             ; DH = head

    clc
    pop     di
    ret

.overflow:
    ; Cylinder too large for CHS
    stc
    pop     di
    ret

.error:
    pop     ax                      ; Clean stack
    stc
    pop     di
    ret

.sector:    db 0
.head:      db 0

;==============================================================================
; Get Translated Geometry
;==============================================================================
; Returns logical geometry for a drive (may differ from physical).
;
; For drives with >1024 cylinders, applies ECHS translation:
;   - Double heads, halve cylinders until cylinders <= 1024
;
; Input:  DL = drive (80h or 81h)
; Output: AX = logical cylinders
;         BL = logical heads
;         BH = logical sectors per track
;         CF = 0 if success
; Destroys: CX, SI
;==============================================================================
get_translated_geometry:
    push    dx

    ; Get physical geometry
    call    get_drive_params
    jc      .error

    ; Read physical values
    mov     ax, [si + 0]            ; Cylinders
    xor     ch, ch
    mov     cl, [si + 2]            ; Heads
    mov     bh, [si + 3]            ; Sectors

    ; Check if translation needed
    cmp     ax, 1024
    jbe     .no_translation

    ; Apply ECHS translation
    ; Double heads, halve cylinders until cyl <= 1024
.translate_loop:
    cmp     cl, 128                 ; Max heads we can report
    jae     .no_translation         ; Can't translate further
    shl     cl, 1                   ; Double heads
    shr     ax, 1                   ; Halve cylinders
    cmp     ax, 1024
    ja      .translate_loop

.no_translation:
    mov     bl, cl                  ; BL = heads

    clc
    pop     dx
    ret

.error:
    stc
    pop     dx
    ret

;==============================================================================
; Calculate Total Sectors
;==============================================================================
; Returns total sector count for a drive.
;
; Input:  DL = drive (80h or 81h)
; Output: DX:AX = 32-bit sector count
;         CF = 0 if success
; Destroys: BX, CX, SI
;==============================================================================
calc_total_sectors:
    ; Get drive parameters
    call    get_drive_params
    jc      .error

    ; Total = Cylinders * Heads * Sectors
    mov     ax, [si + 0]            ; AX = cylinders
    xor     bh, bh
    mov     bl, [si + 2]            ; BX = heads
    mul     bx                      ; DX:AX = cyl * heads

    xor     bh, bh
    mov     bl, [si + 3]            ; BX = sectors
    ; Multiply 32-bit result by sectors
    push    dx                      ; Save high word
    mul     bx                      ; DX:AX = low * sectors
    mov     cx, ax                  ; Save low result
    pop     ax                      ; Get saved high word
    push    dx                      ; Save new high word
    mul     bx                      ; DX:AX = high * sectors
    pop     bx                      ; Get saved high
    add     ax, bx                  ; Combine
    mov     dx, ax                  ; DX = final high word
    mov     ax, cx                  ; AX = final low word

    clc
    ret

.error:
    xor     ax, ax
    xor     dx, dx
    stc
    ret

;==============================================================================
; Validate CHS Parameters
;==============================================================================
; Checks if C/H/S values are within drive limits.
;
; Input:  CX = packed cylinder/sector
;         DH = head
;         DL = drive
; Output: CF = 0 if valid, CF = 1 if invalid
; Destroys: AX, BX, SI
;==============================================================================
validate_chs:
    push    dx

    ; Get drive parameters
    call    get_drive_params
    jc      .invalid

    ; Extract and check cylinder
    mov     al, ch                  ; Low 8 bits
    mov     ah, cl
    shr     ah, 6                   ; High 2 bits
    cmp     ax, [si + 0]            ; Compare with max
    jae     .invalid

    ; Check head
    cmp     dh, [si + 2]
    jae     .invalid

    ; Check sector (1-based)
    mov     al, cl
    and     al, 0x3F
    test    al, al                  ; Sector 0 invalid
    jz      .invalid
    cmp     al, [si + 3]
    ja      .invalid

    clc
    pop     dx
    ret

.invalid:
    stc
    pop     dx
    ret
