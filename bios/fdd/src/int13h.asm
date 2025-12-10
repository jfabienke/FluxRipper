;==============================================================================
; FluxRipper FDD BIOS - INT 13h Handler
;==============================================================================
; Main INT 13h dispatcher for floppy disk operations.
; Handles drives 00h-03h, chains to original handler for drives 80h+.
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

;==============================================================================
; INT 13h Entry Point
;==============================================================================
; This is the main interrupt handler for disk services.
;
; Input varies by function, but typically:
;   AH = function number
;   DL = drive number (00-03 for floppy, 80+ for hard disk)
;
; Output varies by function, but typically:
;   AH = status code
;   CF = 0 for success, 1 for error
;==============================================================================
int13h_handler:
    ; Check if this is a floppy drive request
    cmp     dl, DRIVE_FDD_LAST
    ja      .chain_original         ; Drive > 03h, chain to original

    ; Translate logical drive (A:, B:, etc.) to physical drive
    ; This allows drive letter remapping
    push    bx
    mov     bl, dl
    xor     bh, bh
    mov     dl, [cs:drive_map + bx]  ; Get physical drive from map
    cmp     dl, 0xFF
    pop     bx
    je      .chain_original         ; Drive not mapped, chain to original

    ; Check if physical drive exists
    push    bx
    mov     bl, dl
    xor     bh, bh
    cmp     bl, [cs:num_drives]
    pop     bx
    jae     .chain_original         ; Physical drive doesn't exist, chain

    ; This is our drive - dispatch based on function
    sti                             ; Enable interrupts

    ; Save registers for later
    push    bx
    push    cx
    push    dx
    push    si
    push    di
    push    bp
    push    ds
    push    es

    ; Set DS to our ROM segment
    push    cs
    pop     ds

    ; Dispatch based on function number in AH
    cmp     ah, FN_RESET
    je      .fn_reset
    cmp     ah, FN_GET_STATUS
    je      .fn_get_status
    cmp     ah, FN_READ_SECTORS
    je      .fn_read_sectors
    cmp     ah, FN_WRITE_SECTORS
    je      .fn_write_sectors
    cmp     ah, FN_VERIFY_SECTORS
    je      .fn_verify_sectors
    cmp     ah, FN_FORMAT_TRACK
    je      .fn_format_track
    cmp     ah, FN_GET_PARAMS
    je      .fn_get_params
    cmp     ah, FN_GET_DISK_TYPE
    je      .fn_get_disk_type
    cmp     ah, FN_DISK_CHANGE
    je      .fn_disk_change

    ; Unknown function - return error
    mov     ah, STAT_INVALID_CMD
    stc
    jmp     .return

.fn_reset:
    call    int13h_reset
    jmp     .return

.fn_get_status:
    call    int13h_get_status
    jmp     .return

.fn_read_sectors:
    call    int13h_read_sectors
    jmp     .return

.fn_write_sectors:
    call    int13h_write_sectors
    jmp     .return

.fn_verify_sectors:
    call    int13h_verify_sectors
    jmp     .return

.fn_format_track:
    call    int13h_format_track
    jmp     .return

.fn_get_params:
    call    int13h_get_params
    jmp     .return

.fn_get_disk_type:
    call    int13h_get_disk_type
    jmp     .return

.fn_disk_change:
    call    int13h_disk_change
    jmp     .return

.return:
    ; Restore registers
    pop     es
    pop     ds
    pop     bp
    pop     di
    pop     si
    pop     dx
    pop     cx
    pop     bx

    ; Return from interrupt
    retf    2                       ; Pop flags

.chain_original:
    ; Chain to original INT 13h handler
    jmp     far [cs:old_int13h]

;==============================================================================
; Function 00h: Reset Disk System
;==============================================================================
; Resets the FDC and recalibrates all drives.
;
; Input:  DL = drive number
; Output: AH = status
;         CF = 0 if success, 1 if error
;==============================================================================
int13h_reset:
    push    bx
    push    cx
    push    dx

    ; Reset the FDC
    call    init_fdc

    ; Recalibrate all drives
    mov     cl, [num_drives]
    test    cl, cl
    jz      .success

    xor     dl, dl                  ; Start with drive 0
.recal_loop:
    push    cx
    call    fdc_recalibrate
    pop     cx
    ; Ignore errors, continue with next drive
    inc     dl
    loop    .recal_loop

.success:
    ; Clear status
    mov     al, STAT_SUCCESS
    call    set_disk_status
    xor     ah, ah
    clc

    pop     dx
    pop     cx
    pop     bx
    ret

;==============================================================================
; Function 01h: Get Status
;==============================================================================
; Returns the status of the last disk operation.
;
; Input:  DL = drive number
; Output: AH = status from last operation
;         CF = 0 if last operation succeeded, 1 if failed
;==============================================================================
int13h_get_status:
    call    get_disk_status
    mov     ah, al
    test    al, al
    jz      .success
    stc
    ret

.success:
    clc
    ret

;==============================================================================
; Function 08h: Get Drive Parameters
;==============================================================================
; Returns the geometry of the drive.
;
; Input:  DL = drive number
; Output: AH = 0 (success)
;         BL = drive type code
;         CH = maximum cylinder number (low 8 bits)
;         CL = maximum sector number (bits 0-5) + high cyl bits (6-7)
;         DH = maximum head number
;         DL = number of drives
;         ES:DI = pointer to drive parameter table
;         CF = 0
;==============================================================================
int13h_get_params:
    push    bx
    push    si

    ; Get drive type
    mov     bl, dl
    xor     bh, bh
    mov     al, [drive_types + bx]
    test    al, al
    jz      .invalid

    mov     bl, al                  ; Drive type for return

    ; Get geometry
    mov     si, bx                  ; Reuse BX
    xor     bh, bh
    shl     si, 2                   ; 4 bytes per drive
    add     si, drive_params

    mov     ax, [si]                ; Cylinders
    dec     ax                      ; Max cylinder (0-based)
    mov     ch, al                  ; Low 8 bits
    mov     cl, [si+3]              ; Sectors per track (max sector)
    and     ax, 0x0300              ; High 2 bits of cylinder
    shr     ax, 2
    or      cl, al                  ; Combine into CL

    mov     dh, [si+2]              ; Heads
    dec     dh                      ; Max head (0-based)

    mov     dl, [num_drives]        ; Number of drives

    ; Point ES:DI to drive parameter table
    ; (Use our internal table or standard BIOS table)
    mov     ax, cs
    mov     es, ax
    mov     di, dpt_table

    xor     ah, ah
    clc
    pop     si
    pop     bx
    ret

.invalid:
    mov     ah, STAT_DRV_PARAM_ERR
    stc
    pop     si
    pop     bx
    ret

;==============================================================================
; Function 15h: Get Disk Type
;==============================================================================
; Returns the type of disk/drive.
;
; Input:  DL = drive number
; Output: AH = disk type:
;              00h = no drive
;              01h = floppy without change line
;              02h = floppy with change line
;         CX:DX = 0 (sector count, not applicable for floppy)
;         CF = 0 if success
;==============================================================================
int13h_get_disk_type:
    push    bx

    ; Check if drive exists
    mov     bl, dl
    xor     bh, bh
    cmp     bl, [num_drives]
    jae     .no_drive

    ; Get drive type
    mov     al, [drive_types + bx]
    test    al, al
    jz      .no_drive

    ; All FluxRipper drives support change line
    mov     ah, 0x02                ; Floppy with change line
    xor     cx, cx
    xor     dx, dx
    clc
    pop     bx
    ret

.no_drive:
    xor     ah, ah                  ; No drive
    xor     cx, cx
    xor     dx, dx
    clc                             ; This is not an error condition
    pop     bx
    ret

;==============================================================================
; Function 16h: Disk Change Status
;==============================================================================
; Returns whether the disk has been changed.
;
; Input:  DL = drive number
; Output: AH = status:
;              00h = no disk change
;              06h = disk changed
;         CF = 0 if no change, 1 if changed
;==============================================================================
int13h_disk_change:
    push    dx

    ; Read DIR to check change line
    push    dx
    mov     dx, [current_fdc]
    add     dx, FDC_DIR
    in      al, dx
    pop     dx

    test    al, DIR_DSKCHG
    jnz     .changed

    ; No change
    xor     ah, ah
    clc
    pop     dx
    ret

.changed:
    mov     ah, STAT_DISK_CHANGE
    stc
    pop     dx
    ret

;==============================================================================
; Drive Parameter Table (DPT) for INT 13h AH=08h
;==============================================================================
; Standard 11-byte DPT structure
dpt_table:
    ; Default 1.44M parameters (most common)
    db      0xAF                    ; Specify 1: SRT=10, HUT=15
    db      0x02                    ; Specify 2: HLT=1, ND=0
    db      0x25                    ; Motor off timeout (37 ticks)
    db      0x02                    ; Bytes per sector code (2 = 512)
    db      18                      ; Sectors per track
    db      0x1B                    ; Gap length for R/W
    db      0xFF                    ; Data length (unused for 512-byte)
    db      0x6C                    ; Gap length for format
    db      0xF6                    ; Fill byte for format
    db      0x0F                    ; Head settle time (15ms)
    db      0x08                    ; Motor start time (1 second)
