;==============================================================================
; FluxRipper HDD BIOS - Initialization Routines
;==============================================================================
; Handles BIOS initialization after ROM entry:
;   - Set up Fixed Disk Parameter Tables
;   - Hook INT 13h
;   - Update BDA with drive count
;   - Display detected drives
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

;==============================================================================
; Set Up Fixed Disk Parameter Tables
;==============================================================================
; Populates FDPT structures from discovered geometry and updates INT vectors.
;
; The FDPT is a 16-byte structure that the BIOS uses to track drive geometry.
; INT 41h vector points to drive 0's FDPT, INT 46h to drive 1's FDPT.
;
; Destroys: AX, BX, CX, DX, SI, DI, ES
;==============================================================================
setup_fdpt:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si
    push    di
    push    es

    ; Check if any drives present
    cmp     byte [num_drives], 0
    je      .done

    ;--------------------------------------------------------------------------
    ; Set up Drive 0 FDPT
    ;--------------------------------------------------------------------------
    mov     si, drive0_params       ; Source: discovered geometry
    mov     di, fdpt_drive0         ; Destination: FDPT structure

    ; Copy cylinders
    mov     ax, [si + 0]            ; Cylinders from discovery
    mov     [di + FDPT_MAX_CYL], ax

    ; Copy heads
    xor     ah, ah
    mov     al, [si + 2]
    mov     [di + FDPT_MAX_HEAD], al

    ; Set control byte
    mov     al, 0                   ; Start with no flags
    cmp     byte [si + 2], 8        ; More than 8 heads?
    jbe     .d0_heads_ok
    or      al, FDPT_CTL_MORE_8_HEADS
.d0_heads_ok:
    mov     [di + FDPT_CONTROL], al

    ; Copy sectors per track
    mov     al, [si + 3]
    mov     [di + FDPT_SECTORS], al

    ; Set landing zone = max cylinder
    mov     ax, [si + 0]
    mov     [di + FDPT_LANDING], ax

    ; Write precomp = 0xFFFF (none needed for modern drives)
    mov     word [di + FDPT_WR_PRECOMP], 0xFFFF

    ;--------------------------------------------------------------------------
    ; Update INT 41h vector to point to our FDPT
    ;--------------------------------------------------------------------------
    xor     ax, ax
    mov     es, ax                  ; ES = 0000 (IVT segment)

    ; Store offset and segment of our FDPT
    mov     ax, fdpt_drive0
    mov     [es:INT_41_VECTOR], ax  ; Offset
    mov     ax, cs
    mov     [es:INT_41_VECTOR + 2], ax  ; Segment

    ;--------------------------------------------------------------------------
    ; Set up Drive 1 FDPT (if present)
    ;--------------------------------------------------------------------------
    cmp     byte [num_drives], 2
    jb      .done

    mov     si, drive1_params
    mov     di, fdpt_drive1

    ; Copy cylinders
    mov     ax, [si + 0]
    mov     [di + FDPT_MAX_CYL], ax

    ; Copy heads
    mov     al, [si + 2]
    mov     [di + FDPT_MAX_HEAD], al

    ; Set control byte
    mov     al, 0
    cmp     byte [si + 2], 8
    jbe     .d1_heads_ok
    or      al, FDPT_CTL_MORE_8_HEADS
.d1_heads_ok:
    mov     [di + FDPT_CONTROL], al

    ; Copy sectors per track
    mov     al, [si + 3]
    mov     [di + FDPT_SECTORS], al

    ; Set landing zone
    mov     ax, [si + 0]
    mov     [di + FDPT_LANDING], ax

    ; Write precomp = none
    mov     word [di + FDPT_WR_PRECOMP], 0xFFFF

    ;--------------------------------------------------------------------------
    ; Update INT 46h vector for drive 1
    ;--------------------------------------------------------------------------
    mov     ax, fdpt_drive1
    mov     [es:INT_46_VECTOR], ax
    mov     ax, cs
    mov     [es:INT_46_VECTOR + 2], ax

.done:
    pop     es
    pop     di
    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

;==============================================================================
; Hook INT 13h
;==============================================================================
; Saves the original INT 13h vector and installs our handler.
; We handle hard disk calls (DL >= 80h) and chain to original for floppy.
;
; Destroys: AX, ES
;==============================================================================
hook_int13h:
    push    ax
    push    es

    ; Point ES to IVT
    xor     ax, ax
    mov     es, ax

    ; Save original INT 13h vector
    mov     ax, [es:INT_13_VECTOR]
    mov     [old_int13h], ax
    mov     ax, [es:INT_13_VECTOR + 2]
    mov     [old_int13h + 2], ax

    ; Install our handler
    cli                             ; Disable interrupts during vector update
    mov     word [es:INT_13_VECTOR], int13h_handler
    mov     [es:INT_13_VECTOR + 2], cs
    sti                             ; Re-enable interrupts

    pop     es
    pop     ax
    ret

;==============================================================================
; Update BDA Drive Count
;==============================================================================
; Updates the hard disk count in the BIOS Data Area.
;
; Destroys: AX, ES
;==============================================================================
update_bda:
    push    ax
    push    es

    ; Point ES to BDA
    mov     ax, BDA_SEG
    mov     es, ax

    ; Get current drive count (in case system BIOS found some)
    mov     al, [es:BDA_HDD_COUNT]

    ; Add our drives
    add     al, [num_drives]

    ; Clamp to maximum of 2 for compatibility
    cmp     al, 2
    jbe     .store
    mov     al, 2

.store:
    mov     [es:BDA_HDD_COUNT], al

    pop     es
    pop     ax
    ret

;==============================================================================
; Display Detected Drives
;==============================================================================
; Prints information about detected drives.
;
; Destroys: AX, BX, CX, DX, SI
;==============================================================================
display_drives:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si

    ; Print number of drives
    mov     si, msg_drives_found
    call    print_string
    xor     ah, ah
    mov     al, [num_drives]
    call    print_decimal
    mov     si, msg_drives_suffix
    call    print_string
    call    print_newline

    ; Display drive 0 if present
    cmp     byte [num_drives], 0
    je      .done

    mov     si, msg_drive0
    call    print_string
    mov     si, drive0_params
    call    print_drive_info

    ; Display drive 1 if present
    cmp     byte [num_drives], 2
    jb      .done

    mov     si, msg_drive1
    call    print_string
    mov     si, drive1_params
    call    print_drive_info

.done:
    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

;==============================================================================
; Print Drive Info
;==============================================================================
; Prints geometry for a single drive.
;
; Input:  SI = pointer to drive parameter structure
; Destroys: AX, BX, CX, DX
;==============================================================================
print_drive_info:
    push    si

    ; Print cylinders
    mov     ax, [si + 0]            ; Cylinders
    call    print_decimal
    mov     al, '/'
    call    print_char

    ; Print heads
    xor     ah, ah
    mov     al, [si + 2]            ; Heads
    call    print_decimal
    mov     al, '/'
    call    print_char

    ; Print sectors
    xor     ah, ah
    mov     al, [si + 3]            ; Sectors
    call    print_decimal

    ; Print interface type based on flags
    mov     al, [si + 4]            ; Flags
    test    al, DDRV_FLG_ESDI
    jz      .check_rll
    mov     si, msg_esdi
    jmp     .print_type

.check_rll:
    test    al, DDRV_FLG_RLL
    jz      .mfm
    mov     si, msg_rll
    jmp     .print_type

.mfm:
    mov     si, msg_mfm

.print_type:
    call    print_string
    call    print_newline

    pop     si
    ret
